"""File Watcher trigger module with debouncing mechanism for EventOps daemon."""

import logging
import os
import time

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from executor import execute_async
from rule_engine import RuleEngine

logger = logging.getLogger("eventops.file_watcher")


class FileWatcherHandler(FileSystemEventHandler):
    """Handles OS filesystem modification events with a debouncing cooldown."""

    def __init__(self, rule_engine: RuleEngine, cooldown_seconds: float = 2.0) -> None:
        super().__init__()
        self.rule_engine = rule_engine
        self.cooldown_seconds = cooldown_seconds
        self._last_triggered: dict[str, float] = {}

    def _process_event(self, src_path: str) -> None:
        """Processes a filesystem path change event."""
        rule = self.rule_engine.match_file_change(src_path)
        if not rule:
            return

        now = time.time()
        last_time = self._last_triggered.get(rule.name, 0.0)
        time_since_last = now - last_time

        if time_since_last < self.cooldown_seconds:
            logger.debug(
                "Debounced file change event for rule '%s' (%.2fs < %.2fs cooldown)",
                rule.name,
                time_since_last,
                self.cooldown_seconds,
            )
            return

        self._last_triggered[rule.name] = now
        logger.info(
            "File change detected on '%s'. Triggering rule '%s'", src_path, rule.name
        )
        execute_async(rule.action, rule.name)

    def on_modified(self, event: FileSystemEvent) -> None:
        """Called when a file or directory is modified."""
        if not event.is_directory:
            self._process_event(event.src_path)

    def on_created(self, event: FileSystemEvent) -> None:
        """Called when a file or directory is created."""
        if not event.is_directory:
            self._process_event(event.src_path)


class FileWatcherManager:
    """Manages the watchdog Observer for file change rules."""

    def __init__(self, rule_engine: RuleEngine, cooldown_seconds: float = 2.0) -> None:
        self.rule_engine = rule_engine
        self.cooldown_seconds = cooldown_seconds
        self.observer: Observer | None = None
        self.handler: FileWatcherHandler | None = None

    def start(self) -> None:
        """Starts monitoring watched paths using watchdog Observer."""
        file_rules = self.rule_engine.get_all_file_change_rules()
        if not file_rules:
            logger.info("No file change rules registered. File Watcher dormant.")
            return

        self.handler = FileWatcherHandler(
            self.rule_engine, cooldown_seconds=self.cooldown_seconds
        )
        self.observer = Observer()

        watch_dirs: set[str] = set()
        for rule in file_rules:
            if rule.watch_path:
                watch_dir = os.path.dirname(rule.watch_path)
                if not watch_dir:
                    watch_dir = "."
                if os.path.exists(watch_dir):
                    watch_dirs.add(os.path.abspath(watch_dir))
                else:
                    logger.warning(
                        "Watch directory does not exist for rule '%s': %s",
                        rule.name,
                        watch_dir,
                    )

        for directory in watch_dirs:
            logger.info("Watching directory for changes: %s", directory)
            self.observer.schedule(self.handler, path=directory, recursive=False)

        self.observer.start()
        logger.info("File Watcher started successfully.")

    def stop(self) -> None:
        """Stops the watchdog Observer cleanly."""
        if self.observer and self.observer.is_alive():
            logger.info("Stopping File Watcher...")
            self.observer.stop()
            self.observer.join(timeout=2.0)
            logger.info("File Watcher stopped.")
