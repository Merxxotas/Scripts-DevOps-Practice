"""Webhook Server trigger module for EventOps daemon."""

import hashlib
import hmac
import http.server
import json
import logging
import os
import socketserver
import threading

from executor import execute_async
from rule_engine import RuleEngine

logger = logging.getLogger("eventops.webhook_server")

SECRET_ENV_VAR = "EVENTOPS_WEBHOOK_SECRET"
MAX_BODY_BYTES = 1_048_576  # 1 MB hard cap on webhook payloads
REQUEST_TIMEOUT_SECONDS = 30


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

        Returns the body bytes, or None when the Content-Length header is
        invalid or exceeds MAX_BODY_BYTES (the caller decides the response).
        """
        raw_length = self.headers.get("Content-Length")
        try:
            content_length = int(raw_length) if raw_length is not None else 0
        except ValueError:
            return None
        if content_length < 0 or content_length > MAX_BODY_BYTES:
            return None
        return self.rfile.read(content_length)

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

        body = self._read_body()
        if body is None:
            logger.warning(
                "Rejected POST %s: invalid or oversized Content-Length",
                endpoint_path,
            )
            self._send_json_response(
                413,
                {"status": "error", "message": "Request body too large or invalid"},
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
