"""Unit tests for the File Watcher trigger module."""

import logging
import os
import tempfile
import time

from rule_engine import RuleEngine
from triggers.file_watcher import FileWatcherHandler, FileWatcherManager


def test_file_watcher_debouncing(caplog):
    caplog.set_level(logging.DEBUG)

    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt") as f:
        target_file = f.name
        f.write("initial content\n")

    try:
        engine = RuleEngine()
        engine.load_from_dict(
            {
                "rules": [
                    {
                        "name": "Debounce Rule",
                        "type": "file_change",
                        "watch_path": target_file,
                        "action": "echo 'file updated'",
                    }
                ]
            }
        )

        handler = FileWatcherHandler(engine, cooldown_seconds=1.0)

        # First modification -> should process
        handler._process_event(target_file)

        # Immediate second modification -> should be debounced
        handler._process_event(target_file)

        assert "Debounced file change event for rule 'Debounce Rule'" in caplog.text

        # Wait out cooldown period
        time.sleep(1.1)

        # Third modification after cooldown -> should process again
        handler._process_event(target_file)
        assert caplog.text.count("Triggering rule 'Debounce Rule'") == 2

    finally:
        if os.path.exists(target_file):
            os.remove(target_file)


def test_file_watcher_manager_lifecycle():
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt") as f:
        target_file = f.name

    try:
        engine = RuleEngine()
        engine.load_from_dict(
            {
                "rules": [
                    {
                        "name": "Manager Test",
                        "type": "file_change",
                        "watch_path": target_file,
                        "action": "echo 'ok'",
                    }
                ]
            }
        )

        manager = FileWatcherManager(engine, cooldown_seconds=0.5)
        manager.start()

        assert manager.observer is not None
        assert manager.observer.is_alive()

        # Modify target file
        with open(target_file, "a") as fw:
            fw.write("append line\n")

        time.sleep(0.5)

        manager.stop()
        assert not manager.observer.is_alive()

    finally:
        if os.path.exists(target_file):
            os.remove(target_file)
