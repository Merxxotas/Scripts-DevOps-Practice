"""Unit tests for the Webhook Server trigger module."""

import json
import time
import urllib.error
import urllib.request

import pytest

from rule_engine import RuleEngine
from triggers.webhook_server import WebhookServer


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
    server = WebhookServer(rule_engine=engine, host="127.0.0.1", port=8089)
    server.start()
    time.sleep(0.2)  # Allow server time to bind & listen

    yield server

    server.stop()


def test_webhook_post_success(running_webhook_server):
    url = "http://127.0.0.1:8089/deploy"
    req = urllib.request.Request(url, data=b"", method="POST")

    with urllib.request.urlopen(req) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode("utf-8"))
        assert data["status"] == "success"
        assert data["rule"] == "Test Deploy"


def test_webhook_post_404_not_found(running_webhook_server):
    url = "http://127.0.0.1:8089/unknown"
    req = urllib.request.Request(url, data=b"", method="POST")

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
