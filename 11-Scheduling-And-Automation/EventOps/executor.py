"""Executor module for running shell commands asynchronously with output logging."""

import logging
import subprocess
import threading

logger = logging.getLogger("eventops.executor")

DEFAULT_ACTION_TIMEOUT = 300  # seconds; runaway actions must not hang forever


def execute_sync(
    action: str,
    rule_name: str = "",
    timeout: float | None = DEFAULT_ACTION_TIMEOUT,
) -> subprocess.CompletedProcess:
    """Executes a shell command synchronously and logs stdout/stderr.

    Args:
        action: The shell command line to run.
        rule_name: Optional name of the triggering rule for logging context.
        timeout: Maximum seconds to wait for the command. On timeout the
            process is killed and a CompletedProcess with returncode -1 is
            returned. None disables the timeout (not recommended).

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
            timeout=timeout,
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

    except subprocess.TimeoutExpired as e:
        stdout = e.stdout or ""
        stderr = e.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        logger.error(
            "Action%s timed out after %ss and was killed: %s", tag, timeout, action
        )
        return subprocess.CompletedProcess(
            args=action,
            returncode=-1,
            stdout=stdout,
            stderr=stderr or f"Timed out after {timeout}s",
        )

    except (subprocess.SubprocessError, OSError) as e:
        logger.error("Error occurred while executing action%s: %s", tag, e)
        return subprocess.CompletedProcess(
            args=action,
            returncode=-1,
            stdout="",
            stderr=str(e),
        )


def execute_async(
    action: str,
    rule_name: str = "",
    timeout: float | None = DEFAULT_ACTION_TIMEOUT,
) -> threading.Thread:
    """Spawns a background thread to execute a shell command asynchronously.

    Args:
        action: The shell command line to run.
        rule_name: Optional name of the triggering rule for logging context.
        timeout: Maximum seconds the action may run before it is killed.

    Returns:
        The spawned threading.Thread instance.
    """
    thread = threading.Thread(
        target=execute_sync,
        args=(action, rule_name),
        kwargs={"timeout": timeout},
        daemon=True,
        name=f"ExecutorThread-{rule_name or 'daemon'}",
    )
    thread.start()
    return thread


class ActionExecutor:
    """High-level Executor interface for triggering rules."""

    def __init__(self, logger_override: logging.Logger | None = None) -> None:
        self.logger = logger_override or logger

    def run(
        self,
        action: str,
        rule_name: str = "",
        async_exec: bool = True,
        timeout: float | None = DEFAULT_ACTION_TIMEOUT,
    ):
        """Runs the action either asynchronously or synchronously.

        Args:
            action: Shell command to execute.
            rule_name: Name of the rule.
            async_exec: If True, runs in background thread; else runs synchronously.
            timeout: Maximum seconds the action may run before it is killed.

        Returns:
            threading.Thread if async_exec is True, else subprocess.CompletedProcess.
        """
        if async_exec:
            return execute_async(action, rule_name, timeout=timeout)
        return execute_sync(action, rule_name, timeout=timeout)
