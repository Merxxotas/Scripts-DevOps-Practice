"""Executor module for running shell commands asynchronously with output logging."""

import logging
import subprocess
import threading

logger = logging.getLogger("eventops.executor")


def execute_sync(action: str, rule_name: str = "") -> subprocess.CompletedProcess:
    """Executes a shell command synchronously and logs stdout/stderr.

    Args:
        action: The shell command line to run.
        rule_name: Optional name of the triggering rule for logging context.

    Returns:
        subprocess.CompletedProcess instance containing execution results.
    """
    tag = f" [{rule_name}]" if rule_name else ""
    logger.info("Executing action%s: %s", tag, action)

    try:
        process = subprocess.run(
            action,
            shell=True,
            capture_output=True,
            text=True,
            check=False,
        )

        if process.stdout and process.stdout.strip():
            for line in process.stdout.strip().splitlines():
                logger.info("[stdout%s] %s", tag, line)

        if process.stderr and process.stderr.strip():
            for line in process.stderr.strip().splitlines():
                logger.warning("[stderr%s] %s", tag, line)

        if process.returncode != 0:
            logger.error(
                "Action%s failed with exit code %d: %s",
                tag,
                process.returncode,
                action,
            )
        else:
            logger.info("Action%s completed successfully.", tag)

        return process

    except (subprocess.SubprocessError, OSError) as e:
        logger.error("Error occurred while executing action%s: %s", tag, e)
        return subprocess.CompletedProcess(
            args=action,
            returncode=-1,
            stdout="",
            stderr=str(e),
        )


def execute_async(action: str, rule_name: str = "") -> threading.Thread:
    """Spawns a background thread to execute a shell command asynchronously.

    Args:
        action: The shell command line to run.
        rule_name: Optional name of the triggering rule for logging context.

    Returns:
        The spawned threading.Thread instance.
    """
    thread = threading.Thread(
        target=execute_sync,
        args=(action, rule_name),
        daemon=True,
        name=f"ExecutorThread-{rule_name or 'daemon'}",
    )
    thread.start()
    return thread


class ActionExecutor:
    """High-level Executor interface for triggering rules."""

    def __init__(self, logger_override: logging.Logger | None = None) -> None:
        self.logger = logger_override or logger

    def run(self, action: str, rule_name: str = "", async_exec: bool = True):
        """Runs the action either asynchronously or synchronously.

        Args:
            action: Shell command to execute.
            rule_name: Name of the rule.
            async_exec: If True, runs in background thread; else runs synchronously.

        Returns:
            threading.Thread if async_exec is True, else subprocess.CompletedProcess.
        """
        if async_exec:
            return execute_async(action, rule_name)
        return execute_sync(action, rule_name)
