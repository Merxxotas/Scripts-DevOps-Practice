"""Logging configuration module for EventOps daemon."""

import logging
import os


def setup_logger(
    log_file: str = "eventops.log",
    level: int = logging.INFO,
    name: str | None = None,
) -> logging.Logger:
    """Configures and returns the central logger for EventOps.

    Args:
        log_file: Path to the log file.
        level: Logging level (default: logging.INFO).
        name: Name of the logger instance.

    Returns:
        Configured logging.Logger instance.
    """
    logger = logging.getLogger(name or "eventops")
    logger.setLevel(level)

    # Avoid duplicate handlers if already configured
    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Console Handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # File Handler
    try:
        log_dir = os.path.dirname(log_file)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)
        file_handler = logging.FileHandler(log_file, encoding="utf-8")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except OSError as e:
        logger.error("Failed to set up log file handler: %s", e)

    return logger
