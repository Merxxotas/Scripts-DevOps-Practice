"""Webhook Server trigger module for EventOps daemon."""

import hashlib
import hmac
import http.server
import json
import logging
import os
import socketserver
import threading
from typing import BinaryIO

from executor import execute_async
from rule_engine import RuleEngine

logger = logging.getLogger("eventops.webhook_server")

SECRET_ENV_VAR = "EVENTOPS_WEBHOOK_SECRET"
MAX_BODY_BYTES = 1_048_576  # 1 MB hard cap on webhook payloads
REQUEST_TIMEOUT_SECONDS = 30
MAX_CHUNK_LINE_BYTES = 1024  # a chunk-size line is short; a long one is garbage
# Framing overhead cap: chunks carry bytes of framing that the payload cap cannot
# see. A stream of zero-size chunks adds nothing to the payload but everything to
# the work, so the wire budget is bounded separately.
MAX_CHUNKED_WIRE_BYTES = MAX_BODY_BYTES + 65_536
HEX_DIGITS = frozenset(b"0123456789abcdefABCDEF")
# RFC 7230 token characters, used to validate trailer field names.
TOKEN_CHARS = frozenset(
    b"!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
)


class ChunkedBodyError(Exception):
    """The chunked framing is unparseable or the body exceeds the cap."""

    def __init__(self, too_large: bool) -> None:
        super().__init__("chunked body rejected")
        self.too_large = too_large


class _BodyTooLarge(Exception):
    """The request body exceeds MAX_BODY_BYTES and must be answered with 413."""


def _read_chunk_size(rfile: BinaryIO, wire: list[int]) -> int:
    """Reads one chunk-size line (strict hex digits plus optional extensions)."""
    line = rfile.readline(MAX_CHUNK_LINE_BYTES + 1)
    wire[0] += len(line)
    if not line or len(line) > MAX_CHUNK_LINE_BYTES:
        raise ChunkedBodyError(too_large=False)
    # RFC 7230 chunk-size is 1*HEXDIG followed by CRLF. A bare LF is not a
    # terminator here, and whitespace around the size is not allowed — Go
    # rejects both, so accepting them would be a parity break of its own.
    if not line.endswith(b"\r\n"):
        raise ChunkedBodyError(too_large=False)

    size_field = line[:-2].split(b";", 1)[0]
    if not size_field:
        raise ChunkedBodyError(too_large=False)
    # RFC 7230 chunk-size is 1*HEXDIG. int(x, 16) is looser than that — it also
    # accepts "1_0", "0x10" and "+a" — so the charset is checked first.
    if any(byte not in HEX_DIGITS for byte in size_field):
        raise ChunkedBodyError(too_large=False)
    return int(size_field, 16)


def read_chunked_body(rfile: BinaryIO, max_bytes: int) -> bytes:
    """Decodes an RFC 7230 chunked body, enforcing a decoded-size cap.

    A webhook sender switches to chunked framing once its payload outgrows its
    in-memory buffer, and then sends no Content-Length at all. Reading only
    Content-Length would sign an empty body and reject a perfectly valid
    request, so the framing is decoded here and the HMAC is taken over the
    payload bytes exactly as received.

    Two budgets are enforced, because a payload cap alone is not enough: a
    hostile stream can spend unbounded time and framing bytes without ever
    growing the payload (zero-size chunks, endless trailers).

    Returns:
        The decoded payload.

    Raises:
        ChunkedBodyError: when the framing is malformed (`too_large=False`) or
            the decoded payload or the wire budget exceeds its cap
            (`too_large=True`).
    """
    payload = bytearray()
    wire = [0]  # bytes consumed from the stream, framing included
    while True:
        if wire[0] > MAX_CHUNKED_WIRE_BYTES:
            raise ChunkedBodyError(too_large=True)

        size = _read_chunk_size(rfile, wire)
        if size == 0:
            # Trailer section: headers until the terminating empty line.
            while True:
                trailer = rfile.readline(MAX_CHUNK_LINE_BYTES + 1)
                wire[0] += len(trailer)
                if not trailer or len(trailer) > MAX_CHUNK_LINE_BYTES:
                    raise ChunkedBodyError(too_large=False)
                if wire[0] > MAX_CHUNKED_WIRE_BYTES:
                    raise ChunkedBodyError(too_large=True)
                if trailer == b"\r\n":
                    return bytes(payload)
                # A trailer section carries header fields, not arbitrary lines.
                # Go rejects a malformed trailer before the handler runs, so
                # accepting one here would be a parity break of its own.
                field, sep, _value = trailer[:-2].partition(b":")
                if (
                    not sep
                    or not field
                    or any(byte not in TOKEN_CHARS for byte in field)
                ):
                    raise ChunkedBodyError(too_large=False)

        if len(payload) + size > max_bytes:
            raise ChunkedBodyError(too_large=True)

        data = rfile.read(size)
        wire[0] += len(data)
        if len(data) != size:
            raise ChunkedBodyError(too_large=False)
        payload.extend(data)

        if rfile.read(2) != b"\r\n":
            raise ChunkedBodyError(too_large=False)
        wire[0] += 2


class EventOpsHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    """Custom HTTP request handler for incoming webhook triggers.

    Configuration (rule engine and shared secret) is carried on the server
    instance (`self.server`), not on the handler class, so concurrent server
    instances never leak configuration into each other.
    """

    def setup(self) -> None:
        """Set a read/write timeout so idle clients cannot pin a thread."""
        super().setup()
        self.request.settimeout(REQUEST_TIMEOUT_SECONDS)

    def log_message(self, format: str, *args) -> None:
        """Override default logging to pipe through central logger."""
        logger.debug("[HTTP] " + format, *args)

    def _send_json_response(self, status_code: int, payload: dict) -> None:
        """Helper to send JSON HTTP response."""
        response_data = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response_data)))
        self.end_headers()
        self.wfile.write(response_data)

    def _read_body(self) -> bytes | None:
        """Reads the request body enforcing the size cap.

        Handles both framings a webhook sender can choose: a declared
        Content-Length and chunked transfer encoding.

        Returns:
            The body bytes, or None when the body was already rejected and a
            response has been sent.

        Raises:
            _BodyTooLarge: when the decoded body exceeds MAX_BODY_BYTES.
        """
        if self._is_chunked():
            # A sender may close its write side before the terminating chunk and
            # then wait for the answer, so a failed decode must reply without
            # draining the connection first.
            self.close_connection = True
            try:
                return read_chunked_body(self.rfile, MAX_BODY_BYTES)
            except ChunkedBodyError as exc:
                if exc.too_large:
                    raise _BodyTooLarge from exc
                logger.warning(
                    "Rejected POST %s: malformed chunked body", self._endpoint_path()
                )
                return None
            except TimeoutError:
                logger.warning(
                    "Rejected POST %s: chunked body read timed out",
                    self._endpoint_path(),
                )
                return None

        if self.headers.get("Transfer-Encoding"):
            logger.warning(
                "Rejected POST %s: unsupported Transfer-Encoding %r",
                self._endpoint_path(),
                self.headers.get("Transfer-Encoding"),
            )
            return None

        raw_length = self.headers.get("Content-Length")
        try:
            content_length = int(raw_length) if raw_length is not None else 0
        except ValueError:
            return None
        if content_length < 0 or content_length > MAX_BODY_BYTES:
            raise _BodyTooLarge
        try:
            return self.rfile.read(content_length)
        except TimeoutError:
            logger.warning(
                "Rejected POST %s: body read timed out", self._endpoint_path()
            )
            return None

    def _is_chunked(self) -> bool:
        """Reports whether the request body uses chunked transfer encoding."""
        transfer_encoding = self.headers.get("Transfer-Encoding", "")
        encodings = [part.strip().lower() for part in transfer_encoding.split(",")]
        # Go accepts exactly one coding, `chunked`; a list with other codings or
        # a duplicate is rejected before the handler runs, so accepting it here
        # would let the two implementations authenticate different bytes.
        return encodings == ["chunked"]

    def _endpoint_path(self) -> str:
        """Returns the request path without its query string."""
        return self.path.split("?")[0]

    def _signature_valid(self, body: bytes) -> bool:
        """Verifies the X-Hub-Signature-256 HMAC over the raw body."""
        provided = self.headers.get("X-Hub-Signature-256", "")
        if not provided.startswith("sha256="):
            return False
        secret = self.server.webhook_secret
        expected = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(f"sha256={expected}", provided)

    def do_POST(self) -> None:
        """Handles incoming POST requests to webhook endpoints."""
        rule_engine = getattr(self.server, "rule_engine", None)
        if rule_engine is None:
            logger.error("Rule engine not initialized on HTTP server.")
            self._send_json_response(
                500, {"status": "error", "message": "Server configuration error"}
            )
            return

        endpoint_path = self.path.split("?")[0]

        try:
            body = self._read_body()
        except _BodyTooLarge:
            logger.warning(
                "Rejected POST %s: body exceeds %d bytes",
                endpoint_path,
                MAX_BODY_BYTES,
            )
            self._send_json_response(
                413,
                {"status": "error", "message": "Request body too large or invalid"},
            )
            return

        if body is None:
            self._send_json_response(
                401,
                {"status": "error", "message": "Missing or invalid signature"},
            )
            return

        if not self._signature_valid(body):
            logger.warning(
                "Rejected POST %s: missing or invalid X-Hub-Signature-256",
                endpoint_path,
            )
            self._send_json_response(
                401,
                {"status": "error", "message": "Missing or invalid signature"},
            )
            return

        logger.info("Received POST request on %s", endpoint_path)

        rule = rule_engine.match_webhook(endpoint_path)
        if not rule:
            logger.warning("No webhook rule matching endpoint '%s'", endpoint_path)
            self._send_json_response(
                404,
                {
                    "status": "error",
                    "message": f"No webhook rule matching endpoint '{endpoint_path}'",
                },
            )
            return

        logger.info("Triggering rule '%s' for endpoint '%s'", rule.name, endpoint_path)
        execute_async(rule.action, rule.name)

        self._send_json_response(
            200,
            {
                "status": "success",
                "rule": rule.name,
                "message": "Action triggered successfully",
            },
        )

    def do_GET(self) -> None:
        """Handles GET requests with 405 Method Not Allowed."""
        self._send_json_response(
            405, {"status": "error", "message": "Method Not Allowed. Use POST."}
        )


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Threaded HTTP server allowing concurrent request handling."""

    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, server_address, handler_class, *, rule_engine, webhook_secret):
        self.rule_engine = rule_engine
        self.webhook_secret = webhook_secret
        super().__init__(server_address, handler_class)


class WebhookServer:
    """Server manager class for controlling Webhook trigger listener.

    The shared HMAC secret is taken from the `secret` argument or, when not
    provided, from the EVENTOPS_WEBHOOK_SECRET environment variable. Starting
    without a secret fails closed: `start()` raises RuntimeError instead of
    exposing an unauthenticated listener.
    """

    def __init__(
        self,
        rule_engine: RuleEngine,
        host: str = "127.0.0.1",
        port: int = 8080,
        secret: str | None = None,
    ) -> None:
        self.rule_engine = rule_engine
        self.host = host
        self.port = port
        self.secret = secret if secret is not None else os.environ.get(SECRET_ENV_VAR)
        self.server: ThreadedHTTPServer | None = None
        self.thread: threading.Thread | None = None

    def start(self) -> None:
        """Starts the Webhook HTTP server in a background daemon thread.

        Raises:
            RuntimeError: If no HMAC secret is configured (fail-closed).
        """
        if not self.secret:
            raise RuntimeError(
                f"{SECRET_ENV_VAR} is not set; refusing to start the webhook "
                "listener. Set it to a strong shared secret (e.g. "
                "'openssl rand -hex 32') before starting the daemon."
            )

        self.server = ThreadedHTTPServer(
            (self.host, self.port),
            EventOpsHTTPRequestHandler,
            rule_engine=self.rule_engine,
            webhook_secret=self.secret,
        )
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            daemon=True,
            name="WebhookServerThread",
        )
        self.thread.start()
        logger.info("Webhook Server listening on http://%s:%d", self.host, self.port)

    def stop(self) -> None:
        """Stops the Webhook HTTP server cleanly."""
        if self.server:
            logger.info("Stopping Webhook Server...")
            self.server.shutdown()
            self.server.server_close()
            logger.info("Webhook Server stopped.")
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=2.0)
