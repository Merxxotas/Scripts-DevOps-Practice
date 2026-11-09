"""Unit tests for the Webhook Server trigger module."""

import hashlib
import hmac
import json
import time
import urllib.error
import urllib.request

import pytest

from rule_engine import RuleEngine
from triggers.webhook_server import WebhookServer

TEST_SECRET = "test-secret-123"


def sign_body(body: bytes, secret: str = TEST_SECRET) -> str:
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return f"sha256={digest}"


def post(url: str, body: bytes = b"", signature: str | None = None):
    headers = {}
    if signature is not None:
        headers["X-Hub-Signature-256"] = signature
    return urllib.request.Request(url, data=body, headers=headers, method="POST")


def post_chunked(url: str, body: bytes, signature: str | None = None):
    """Builds a POST that transfers its body with chunked framing.

    `http.client` chooses chunked encoding whenever the body has no declared
    length — exactly what a webhook sender does when the payload exceeds its
    in-memory buffer. The signature must cover the decoded payload bytes.
    """
    headers = {"Transfer-Encoding": "chunked"}
    if signature is not None:
        headers["X-Hub-Signature-256"] = signature
    return urllib.request.Request(url, data=body, headers=headers, method="POST")


@pytest.fixture
def running_webhook_server():
    engine = RuleEngine()
    engine.load_from_dict(
        {
            "rules": [
                {
                    "name": "Test Deploy",
                    "type": "webhook",
                    "endpoint": "/deploy",
                    "action": "echo 'webhook triggered'",
                }
            ]
        }
    )

    # Use port 8089 for tests to avoid port conflicts
    server = WebhookServer(
        rule_engine=engine, host="127.0.0.1", port=8089, secret=TEST_SECRET
    )
    server.start()
    time.sleep(0.2)  # Allow server time to bind & listen

    yield server

    server.stop()


def test_webhook_post_success(running_webhook_server):
    body = b'{"ref":"main"}'
    url = "http://127.0.0.1:8089/deploy"
    req = post(url, body, sign_body(body))

    with urllib.request.urlopen(req) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode("utf-8"))
        assert data["status"] == "success"
        assert data["rule"] == "Test Deploy"


def test_webhook_post_without_signature_returns_401(running_webhook_server):
    url = "http://127.0.0.1:8089/deploy"
    req = post(url, b"{}", None)

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401
    data = json.loads(excinfo.value.read().decode("utf-8"))
    assert data["status"] == "error"


def test_webhook_post_with_invalid_signature_returns_401(running_webhook_server):
    url = "http://127.0.0.1:8089/deploy"
    req = post(url, b"{}", "sha256=deadbeef")

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401


def test_webhook_post_with_tampered_body_returns_401(running_webhook_server):
    signed_body = b'{"ref":"main"}'
    signature = sign_body(signed_body)
    # Attacker reuses the signature but alters the payload
    url = "http://127.0.0.1:8089/deploy"
    req = post(url, b'{"ref":"pwned"}', signature)

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401


def test_webhook_post_with_wrong_secret_returns_401(running_webhook_server):
    body = b"{}"
    url = "http://127.0.0.1:8089/deploy"
    req = post(url, body, sign_body(body, secret="attacker-secret"))

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401


def test_webhook_start_without_secret_fails_closed(monkeypatch):
    monkeypatch.delenv("EVENTOPS_WEBHOOK_SECRET", raising=False)
    engine = RuleEngine()
    engine.load_from_dict({"rules": []})

    server = WebhookServer(rule_engine=engine, host="127.0.0.1", port=8090, secret=None)

    with pytest.raises(RuntimeError, match="EVENTOPS_WEBHOOK_SECRET"):
        server.start()


def test_webhook_post_404_not_found(running_webhook_server):
    body = b"{}"
    url = "http://127.0.0.1:8089/unknown"
    req = post(url, body, sign_body(body))

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 404
    data = json.loads(excinfo.value.read().decode("utf-8"))
    assert data["status"] == "error"


def test_webhook_get_405_method_not_allowed(running_webhook_server):
    url = "http://127.0.0.1:8089/deploy"
    req = urllib.request.Request(url, method="GET")

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 405


# --- Chunked transfer ------------------------------------------------
# A webhook sender above its payload threshold switches to chunked framing.
# The Daemon must sign the DECODED body, not an empty one.


def test_chunked_signed_body_returns_200(running_webhook_server):
    body = b'{"ref":"main","after":"a2ea1f0"}'
    url = "http://127.0.0.1:8089/deploy"
    req = post_chunked(url, body, sign_body(body))

    with urllib.request.urlopen(req) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode("utf-8"))
        assert data["status"] == "success"
        assert data["rule"] == "Test Deploy"


def test_chunked_without_signature_returns_401(running_webhook_server):
    url = "http://127.0.0.1:8089/deploy"
    req = post_chunked(url, b'{"ref":"main"}', None)

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401
    data = json.loads(excinfo.value.read().decode("utf-8"))
    assert data["message"] == "Missing or invalid signature"


def test_chunked_signature_over_empty_body_is_rejected(running_webhook_server):
    """A signature over nothing must not authenticate a non-empty chunked body."""
    real_body = b'{"ref":"main"}'
    url = "http://127.0.0.1:8089/deploy"
    req = post_chunked(url, real_body, sign_body(b""))

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 401


def test_chunked_unknown_endpoint_returns_404_after_valid_signature(
    running_webhook_server,
):
    body = b"{}"
    url = "http://127.0.0.1:8089/nonexistent"
    req = post_chunked(url, body, sign_body(body))

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        urllib.request.urlopen(req)

    assert excinfo.value.code == 404
