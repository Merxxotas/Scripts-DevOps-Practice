"""Main EventOps automation daemon CLI entry point."""

import argparse
import logging
import signal
import sys
import threading
import time

from logger_config import setup_logger
from rule_engine import RuleEngine, RuleValidationError
from triggers.file_watcher import FileWatcherManager
from triggers.webhook_server import WebhookServer

logger = logging.getLogger("eventops.main")


class EventOpsDaemon:
    """Main EventOps daemon orchestrator."""

    def __init__(
        self,
        config_path: str = "rules.json",
        host: str = "0.0.0.0",
        port: int = 8080,
        log_file: str = "eventops.log",
        log_level: str = "INFO",
    ) -> None:
        self.config_path = config_path
        self.host = host
        self.port = port
        self.log_file = log_file
        self.log_level_name = log_level.upper()

        numeric_level = getattr(logging, self.log_level_name, logging.INFO)
        setup_logger(log_file=self.log_file, level=numeric_level)

        self.rule_engine = RuleEngine()
        self.webhook_server: WebhookServer | None = None
        self.file_watcher: FileWatcherManager | None = None
        self._running = False

    def load_configuration(self) -> bool:
        """Loads and validates rules.json configuration."""
        try:
            logger.info("Loading configuration from: %s", self.config_path)
            self.rule_engine.load_from_file(self.config_path)
            return True
        except RuleValidationError as e:
            logger.error("Configuration error: %s", e)
            return False

    def start(self) -> None:
        """Starts listener threads and runs main event loop."""
        logger.info("Starting EventOps Daemon...")

        if not self.load_configuration():
            logger.critical("Failed to load configuration. Aborting daemon startup.")
            sys.exit(1)

        # Register OS signal handlers if running in main thread
        if threading.current_thread() is threading.main_thread():
            try:
                signal.signal(signal.SIGINT, self._signal_handler)
                signal.signal(signal.SIGTERM, self._signal_handler)
            except (ValueError, OSError) as e:
                logger.debug("Signal registration skipped: %s", e)

        # Initialize and start Webhook Server
        self.webhook_server = WebhookServer(
            rule_engine=self.rule_engine, host=self.host, port=self.port
        )
        self.webhook_server.start()

        # Initialize and start File Watcher
        self.file_watcher = FileWatcherManager(
            rule_engine=self.rule_engine, cooldown_seconds=2.0
        )
        self.file_watcher.start()

        self._running = True
        logger.info("EventOps Daemon is now active and monitoring events.")

        try:
            while self._running:
                time.sleep(0.1)
        except KeyboardInterrupt:
            logger.info("KeyboardInterrupt received.")
        finally:
            self.stop()

    def _signal_handler(self, signum, frame) -> None:
        """Handles termination signals cleanly."""
        sig_name = signal.Signals(signum).name
        logger.info("Received OS signal %s. Shutting down daemon...", sig_name)
        self._running = False

    def stop(self) -> None:
        """Stops listener threads and shuts down cleanly."""
        logger.info("Initiating graceful shutdown of EventOps Daemon...")
        self._running = False

        if self.webhook_server:
            self.webhook_server.stop()
            self.webhook_server = None

        if self.file_watcher:
            self.file_watcher.stop()
            self.file_watcher = None

        logger.info("EventOps Daemon shutdown complete.")


def parse_args(args: list[str] | None = None) -> argparse.Namespace:
    """Parses CLI arguments."""
    parser = argparse.ArgumentParser(
        description="EventOps - Cross-platform Event-Driven Automation Daemon"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    start_parser = subparsers.add_parser("start", help="Start the EventOps daemon")
    start_parser.add_argument(
        "--config",
        "-c",
        default="rules.json",
        help="Path to rules.json configuration file (default: rules.json)",
    )
    start_parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Host interface for Webhook server (default: 0.0.0.0)",
    )
    start_parser.add_argument(
        "--port",
        "-p",
        type=int,
        default=8080,
        help="Port for Webhook server (default: 8080)",
    )
    start_parser.add_argument(
        "--log-file",
        default="eventops.log",
        help="Path to log file (default: eventops.log)",
    )
    start_parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level (default: INFO)",
    )

    return parser.parse_args(args)


def main(cli_args: list[str] | None = None) -> None:
    """Main execution function."""
    args = parse_args(cli_args)

    if args.command == "start":
        daemon = EventOpsDaemon(
            config_path=args.config,
            host=args.host,
            port=args.port,
            log_file=args.log_file,
            log_level=args.log_level,
        )
        daemon.start()


if __name__ == "__main__":
    main()
