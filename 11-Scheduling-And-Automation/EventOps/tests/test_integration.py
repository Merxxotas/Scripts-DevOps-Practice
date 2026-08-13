"""End-to-end integration tests for EventOps daemon."""

import json
import sys
import threading
import time
import urllib.request

from eventops import EventOpsDaemon


def test_full_daemon_integration(tmp_path):
    config_file = tmp_path / "rules.json"
    watched_file = tmp_path / "trigger_file.txt"
    output_log_file = tmp_path / "output_action.log"
    log_file = tmp_path / "eventops_test.log"

    watched_file.write_text("initial state\n")

    # Use python executable for 100% cross-platform file writing in tests
    # Works identically across Windows cmd/powershell, Linux bash, and macOS zsh
    action_webhook = f"{sys.executable} -c \"with open(r'{output_log_file}', 'a') as f: f.write('webhook ok\\n')\""
    action_file = f"{sys.executable} -c \"with open(r'{output_log_file}', 'a') as f: f.write('file ok\\n')\""

    rules_content = {
        "rules": [
            {
                "name": "E2E Webhook Rule",
                "type": "webhook",
                "endpoint": "/e2e-webhook",
                "action": action_webhook,
            },
            {
                "name": "E2E File Rule",
                "type": "file_change",
                "watch_path": str(watched_file),
                "action": action_file,
            },
        ]
    }
    config_file.write_text(json.dumps(rules_content))

    daemon = EventOpsDaemon(
        config_path=str(config_file),
        host="127.0.0.1",
        port=8099,
        log_file=str(log_file),
        log_level="DEBUG",
    )

    # Start daemon in background thread
    daemon_thread = threading.Thread(target=daemon.start, daemon=True)
    daemon_thread.start()

    time.sleep(0.5)  # Wait for daemon startup

    try:
        # 1. Trigger Webhook
        url = "http://127.0.0.1:8099/e2e-webhook"
        req = urllib.request.Request(url, data=b"", method="POST")
        with urllib.request.urlopen(req) as resp:
            assert resp.status == 200

        time.sleep(0.5)

        # 2. Trigger File Watcher
        with open(watched_file, "a") as f:
            f.write("modified state\n")

        time.sleep(0.8)

        # Verify output log file created by executed actions
        assert output_log_file.exists()
        content = output_log_file.read_text()
        assert "webhook ok" in content
        assert "file ok" in content

    finally:
        daemon.stop()
        daemon_thread.join(timeout=2.0)
