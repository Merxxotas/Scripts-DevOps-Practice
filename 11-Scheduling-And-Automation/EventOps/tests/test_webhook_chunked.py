"""Raw socket level tests for the Webhook Server chunked body handling.

These tests speak HTTP/1.1 on a bare socket because the failure they cover is
invisible above the socket: a chunked request carries no Content-Length, and a
server that only reads Content-Length signs an empty body. Malformed framing
cannot be produced with a high-level client either — it has to be written.
"""

import hashlib
import hmac
import json
import socket
import time

import pytest

from rule_engine import RuleEngine
from triggers import webhook_server
from triggers.webhook_server import MAX_BODY_BYTES, WebhookServer

TEST_SECRET = "raw-socket-secret"
PORT = 8091


def sign_body(body: bytes, secret: str = TEST_SECRET) -> str:
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return f"sha256={digest}"


@pytest.fixture
def running_webhook_server():
    engine = RuleEngine()
    engine.load_from_dict(
        {
            "rules": [
                {
                    "name": "Raw Deploy",
                    "type": "webhook",
                    "endpoint": "/deploy",
                    "action": "echo 'raw webhook triggered'",
                }
            ]
        }
    )
    server = WebhookServer(
        rule_engine=engine, host="127.0.0.1", port=PORT, secret=TEST_SECRET
    )
    server.start()
    time.sleep(0.2)
    yield server
    server.stop()


def send_raw(raw_request: bytes, half_close: bool = False) -> tuple[int, dict]:
    """Sends raw HTTP bytes and parses the status line and JSON body.

    The server answers a 401 without draining the connection, so the client
    must not block forever on a keep-alive socket: read the headers, then the
    exact Content-Length the response declares.
    """
    with socket.create_connection(("127.0.0.1", PORT), timeout=10) as sock:
        sock.sendall(raw_request)
        if half_close:
            sock.shutdown(socket.SHUT_WR)
        data = b""
        while b"\r\n\r\n" not in data:
            piece = sock.recv(65536)
            if not piece:
                break
            data += piece
        head, _, rest = data.partition(b"\r\n\r\n")
        length = 0
        for line in head.split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":", 1)[1])
        body = rest
        while len(body) < length:
            piece = sock.recv(65536)
            if not piece:
                break
            body += piece
    status_line = head.split(b"\r\n", 1)[0].decode("latin-1")
    status = int(status_line.split(" ")[1])
    try:
        payload = json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        payload = {}
    return status, payload


def chunked_request(path: str, body: bytes, signature: str | None, extra: bytes = b""):
    """Builds a chunked POST where the chunks are arbitrary bytes."""
    lines = [
        f"POST {path} HTTP/1.1",
        f"Host: 127.0.0.1:{PORT}",
        "Transfer-Encoding: chunked",
        "Content-Type: application/json",
    ]
    if signature is not None:
        lines.append(f"X-Hub-Signature-256: {signature}")
    head = "\r\n".join(lines).encode("latin-1") + b"\r\n\r\n"
    return head + body + extra


def framed(*chunks: bytes) -> bytes:
    """Encodes payload pieces with correct RFC 7230 chunk framing."""
    out = b""
    for chunk in chunks:
        out += f"{len(chunk):x}".encode("ascii") + b"\r\n" + chunk + b"\r\n"
    return out + b"0\r\n\r\n"


def test_chunked_signed_body_returns_200(running_webhook_server):
    payload = b'{"ref":"main","after":"a2ea1f0"}'
    raw = chunked_request("/deploy", framed(payload), sign_body(payload))

    status, data = send_raw(raw)

    assert status == 200
    assert data["status"] == "success"
    assert data["rule"] == "Raw Deploy"


def test_chunked_split_across_multiple_chunks_returns_200(running_webhook_server):
    """The signature covers the concatenated payload, not the chunk framing."""
    piece_a = b'{"ref":'
    piece_b = b'"main","after":"a2ea1f0"}'
    payload = piece_a + piece_b
    raw = chunked_request("/deploy", framed(piece_a, piece_b), sign_body(payload))

    status, data = send_raw(raw)

    assert status == 200
    assert data["rule"] == "Raw Deploy"


def test_chunked_empty_signed_body_returns_200(running_webhook_server):
    raw = chunked_request("/deploy", b"0\r\n\r\n", sign_body(b""))

    status, data = send_raw(raw)

    assert status == 200
    assert data["rule"] == "Raw Deploy"


def test_chunked_signature_over_empty_body_is_rejected(running_webhook_server):
    payload = b'{"ref":"main"}'
    raw = chunked_request("/deploy", framed(payload), sign_body(b""))

    status, data = send_raw(raw)

    assert status == 401
    assert data["message"] == "Missing or invalid signature"


def test_chunked_tampered_payload_returns_401(running_webhook_server):
    signed = b'{"ref":"main"}'
    raw = chunked_request("/deploy", framed(b'{"ref":"pwned"}'), sign_body(signed))

    status, _data = send_raw(raw)

    assert status == 401


def test_chunked_without_signature_returns_401(running_webhook_server):
    raw = chunked_request("/deploy", framed(b'{"ref":"main"}'), None)

    status, data = send_raw(raw)

    assert status == 401
    assert data["message"] == "Missing or invalid signature"


def test_chunked_unknown_endpoint_returns_404_after_valid_signature(
    running_webhook_server,
):
    payload = b"{}"
    raw = chunked_request("/nonexistent", framed(payload), sign_body(payload))

    status, _data = send_raw(raw)

    assert status == 404


def test_chunked_invalid_chunk_size_returns_401(running_webhook_server):
    payload = b'{"ref":"main"}'
    # "zz" is not a hexadecimal chunk size and the framing is unparseable, but
    # the signature is valid for the bytes a lenient parser would recover.
    raw = chunked_request(
        "/deploy", b"zz\r\n" + payload + b"\r\n0\r\n\r\n", sign_body(payload)
    )

    status, data = send_raw(raw)

    assert status == 401
    assert data["message"] == "Missing or invalid signature"


def test_chunked_missing_terminator_returns_401(running_webhook_server):
    """A sender that ends the stream early still deserves an answer, not a hang."""
    payload = b'{"ref":"main"}'
    body = f"{len(payload):x}\r\n".encode("ascii") + payload + b"\r\n"
    raw = chunked_request("/deploy", body, sign_body(payload))

    status, data = send_raw(raw, half_close=True)

    assert status == 401
    assert data["message"] == "Missing or invalid signature"


def test_chunked_missing_chunk_crlf_returns_401(running_webhook_server):
    payload = b'{"ref":"main"}'
    body = f"{len(payload):x}".encode("ascii") + payload + b"0\r\n\r\n"
    raw = chunked_request("/deploy", body, sign_body(payload))

    status, _data = send_raw(raw)

    assert status == 401


def test_chunked_body_over_cap_returns_413(running_webhook_server):
    oversized = b"x" * (MAX_BODY_BYTES + 1)
    first = oversized[:10_000]
    declared = oversized[10_000:]
    # The server rejects on the declared chunk size before reading the chunk
    # payload, so the client sends the first chunk and the oversized size line,
    # then reads the 413. Sending the whole 1 MB body races the server's early
    # close: macOS raises BrokenPipeError mid-send (observed in CI).
    body = (
        f"{len(first):x}\r\n".encode("ascii")
        + first
        + b"\r\n"
        + f"{len(declared):x}\r\n".encode("ascii")
    )
    raw = chunked_request("/deploy", body, sign_body(oversized))

    status, data = send_raw(raw)

    assert status == 413
    assert data["status"] == "error"


def test_chunked_body_exactly_at_cap_is_accepted(running_webhook_server):
    """The cap is a maximum, not an exclusive bound: 1 MB must still work."""
    payload = b"x" * MAX_BODY_BYTES
    raw = chunked_request("/deploy", framed(payload), sign_body(payload))

    status, _data = send_raw(raw)

    assert status == 200


def test_unsupported_transfer_encoding_returns_401(running_webhook_server):
    """`gzip, chunked` must not be treated as chunked; Go rejects it outright."""
    payload = b'{"ref":"main"}'
    raw = (
        f"POST /deploy HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{PORT}\r\n"
        f"Transfer-Encoding: gzip, chunked\r\n"
        f"Content-Type: application/json\r\n"
        f"X-Hub-Signature-256: {sign_body(payload)}\r\n\r\n"
    ).encode("latin-1") + framed(payload)

    status, data = send_raw(raw)

    assert status == 401
    assert data["message"] == "Missing or invalid signature"


def test_chunked_socket_timeout_returns_401(running_webhook_server, monkeypatch):
    """A client that stalls mid-chunk gets the generic 401, not an unhandled timeout."""
    monkeypatch.setattr(webhook_server, "REQUEST_TIMEOUT_SECONDS", 1.0)
    raw = chunked_request("/deploy", b"10\r\nabc", sign_body(b"abc"))

    with socket.create_connection(("127.0.0.1", PORT), timeout=10) as sock:
        sock.sendall(raw)
        data = b""
        while b"\r\n\r\n" not in data:
            piece = sock.recv(65536)
            if not piece:
                break
            data += piece

    status_line = data.split(b"\r\n", 1)[0]
    assert b" 401 " in status_line
