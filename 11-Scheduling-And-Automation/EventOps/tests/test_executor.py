"""Unit tests for the ActionExecutor module."""

import logging

from executor import ActionExecutor, execute_async, execute_sync


def test_execute_sync_success(caplog):
    caplog.set_level(logging.INFO)
    result = execute_sync("echo 'Hello EventOps'", rule_name="TestRule")

    assert result.returncode == 0
    assert "Hello EventOps" in result.stdout
    assert "Action [TestRule] completed successfully." in caplog.text


def test_execute_sync_failure(caplog):
    caplog.set_level(logging.ERROR)
    result = execute_sync("exit 42", rule_name="FailRule")

    assert result.returncode == 42
    assert "Action [FailRule] failed with exit code 42" in caplog.text


def test_execute_async():
    thread = execute_async("echo 'Async Test'", rule_name="AsyncRule")
    thread.join(timeout=2.0)

    assert not thread.is_alive()


def test_action_executor_class():
    executor = ActionExecutor()
    thread = executor.run("echo 'Class Exec'", rule_name="ClassRule", async_exec=True)
    thread.join(timeout=2.0)
    assert not thread.is_alive()

    sync_result = executor.run(
        "echo 'Sync Class'", rule_name="SyncClass", async_exec=False
    )
    assert sync_result.returncode == 0
