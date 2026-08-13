"""Unit tests for the RuleEngine module."""

import os
import tempfile

import pytest

from rule_engine import RuleEngine, RuleValidationError


def test_valid_rule_loading():
    valid_config = {
        "rules": [
            {
                "name": "Deploy Prod",
                "type": "webhook",
                "endpoint": "/deploy-prod",
                "action": "echo 'deploying'",
            },
            {
                "name": "Config Reload",
                "type": "file_change",
                "watch_path": "config.ini",
                "action": "echo 'reloading'",
            },
        ]
    }
    engine = RuleEngine()
    rules = engine.load_from_dict(valid_config)

    assert len(rules) == 2
    assert rules[0].name == "Deploy Prod"
    assert rules[0].rule_type == "webhook"
    assert rules[0].endpoint == "/deploy-prod"

    assert rules[1].name == "Config Reload"
    assert rules[1].rule_type == "file_change"
    assert rules[1].watch_path == os.path.abspath("config.ini")


def test_webhook_matching():
    valid_config = {
        "rules": [
            {
                "name": "Webhook Test",
                "type": "webhook",
                "endpoint": "/api/v1/trigger",
                "action": "echo 'hit'",
            }
        ]
    }
    engine = RuleEngine()
    engine.load_from_dict(valid_config)

    matched = engine.match_webhook("/api/v1/trigger")
    assert matched is not None
    assert matched.name == "Webhook Test"

    assert engine.match_webhook("/api/v1/unknown") is None


def test_file_change_matching():
    valid_config = {
        "rules": [
            {
                "name": "File Test",
                "type": "file_change",
                "watch_path": "/tmp/test.txt",
                "action": "echo 'file modified'",
            }
        ]
    }
    engine = RuleEngine()
    engine.load_from_dict(valid_config)

    matched = engine.match_file_change("/tmp/test.txt")
    assert matched is not None
    assert matched.name == "File Test"

    assert engine.match_file_change("/tmp/other.txt") is None


def test_invalid_json_file():
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".json") as f:
        f.write("{ invalid json")
        temp_path = f.name

    try:
        engine = RuleEngine()
        with pytest.raises(RuleValidationError):
            engine.load_from_file(temp_path)
    finally:
        os.remove(temp_path)


def test_missing_required_fields():
    invalid_configs = [
        {
            "rules": [{"type": "webhook", "endpoint": "/test", "action": "ls"}]
        },  # missing name
        {"rules": [{"name": "r1", "type": "unknown", "action": "ls"}]},  # invalid type
        {
            "rules": [{"name": "r1", "type": "webhook", "action": "ls"}]
        },  # missing endpoint
        {
            "rules": [{"name": "r1", "type": "file_change", "action": "ls"}]
        },  # missing watch_path
        {
            "rules": [{"name": "r1", "type": "webhook", "endpoint": "/t"}]
        },  # missing action
    ]

    for cfg in invalid_configs:
        engine = RuleEngine()
        with pytest.raises(RuleValidationError):
            engine.load_from_dict(cfg)


def test_duplicate_rule_names():
    duplicate_cfg = {
        "rules": [
            {"name": "Rule1", "type": "webhook", "endpoint": "/e1", "action": "ls"},
            {"name": "Rule1", "type": "webhook", "endpoint": "/e2", "action": "pwd"},
        ]
    }
    engine = RuleEngine()
    with pytest.raises(RuleValidationError) as excinfo:
        engine.load_from_dict(duplicate_cfg)
    assert "Duplicate rule name" in str(excinfo.value)
