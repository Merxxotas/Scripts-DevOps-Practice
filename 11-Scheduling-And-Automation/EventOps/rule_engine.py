"""Rule Engine module for loading, validating, and matching EventOps rules."""

import json
import logging
import os
from dataclasses import dataclass

logger = logging.getLogger("eventops.rule_engine")


class RuleValidationError(Exception):
    """Custom exception raised when rule validation fails."""


@dataclass
class Rule:
    """Dataclass representing an EventOps automation rule."""

    name: str
    rule_type: str  # 'webhook' or 'file_change'
    action: str
    endpoint: str | None = None
    watch_path: str | None = None

    def __post_init__(self) -> None:
        if (
            self.rule_type == "webhook"
            and self.endpoint
            and not self.endpoint.startswith("/")
        ):
            self.endpoint = "/" + self.endpoint
        if self.rule_type == "file_change" and self.watch_path:
            self.watch_path = os.path.abspath(self.watch_path)


class RuleEngine:
    """Manages parsing, validating, and searching automation rules."""

    def __init__(self) -> None:
        self.rules: list[Rule] = []

    def load_from_file(self, file_path: str) -> list[Rule]:
        """Loads and validates rules from a JSON configuration file.

        Args:
            file_path: Path to rules.json.

        Returns:
            List of parsed Rule objects.

        Raises:
            RuleValidationError: If file does not exist or JSON schema is invalid.
        """
        if not os.path.exists(file_path):
            raise RuleValidationError(f"Configuration file not found: {file_path}")

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            raise RuleValidationError(f"Invalid JSON format in {file_path}: {e}") from e
        except OSError as e:
            raise RuleValidationError(f"Failed to read {file_path}: {e}") from e

        return self.load_from_dict(data)

    def load_from_dict(self, data: dict) -> list[Rule]:
        """Loads and validates rules from a dictionary structure.

        Args:
            data: Parsed configuration dictionary.

        Returns:
            List of parsed Rule objects.

        Raises:
            RuleValidationError: If dict structure fails validation.
        """
        if not isinstance(data, dict) or "rules" not in data:
            raise RuleValidationError("Configuration root must contain a 'rules' list.")

        rules_list = data["rules"]
        if not isinstance(rules_list, list):
            raise RuleValidationError("'rules' must be a list of rule objects.")

        parsed_rules: list[Rule] = []
        rule_names = set()

        for idx, rule_data in enumerate(rules_list):
            if not isinstance(rule_data, dict):
                raise RuleValidationError(f"Rule at index {idx} must be a dictionary.")

            rule = self.validate_rule(rule_data, idx)
            if rule.name in rule_names:
                raise RuleValidationError(f"Duplicate rule name found: '{rule.name}'")
            rule_names.add(rule.name)
            parsed_rules.append(rule)

        self.rules = parsed_rules
        logger.info("Successfully loaded %d rules.", len(self.rules))
        return self.rules

    def validate_rule(self, rule_data: dict, idx: int) -> Rule:
        """Validates a single rule dictionary.

        Args:
            rule_data: Dictionary representing a rule.
            idx: Index of rule in configuration.

        Returns:
            Rule object.

        Raises:
            RuleValidationError: If required fields are missing or invalid.
        """
        name = rule_data.get("name")
        if not name or not isinstance(name, str):
            raise RuleValidationError(f"Rule at index {idx} missing valid 'name'.")

        rule_type = rule_data.get("type")
        if rule_type not in ("webhook", "file_change"):
            raise RuleValidationError(
                f"Rule '{name}' has invalid type '{rule_type}'. "
                "Must be 'webhook' or 'file_change'."
            )

        action = rule_data.get("action")
        if not action or not isinstance(action, str):
            raise RuleValidationError(f"Rule '{name}' missing valid 'action' command.")

        endpoint = None
        watch_path = None

        if rule_type == "webhook":
            endpoint = rule_data.get("endpoint")
            if not endpoint or not isinstance(endpoint, str):
                raise RuleValidationError(
                    f"Rule '{name}' of type 'webhook' requires a valid 'endpoint'."
                )
        elif rule_type == "file_change":
            watch_path = rule_data.get("watch_path")
            if not watch_path or not isinstance(watch_path, str):
                raise RuleValidationError(
                    f"Rule '{name}' of type 'file_change' requires a valid 'watch_path'."
                )

        return Rule(
            name=name,
            rule_type=rule_type,
            action=action,
            endpoint=endpoint,
            watch_path=watch_path,
        )

    def match_webhook(self, path: str) -> Rule | None:
        """Matches an incoming URI path against registered webhook rules.

        Args:
            path: Incoming HTTP URI path (e.g., '/deploy').

        Returns:
            Matching Rule if found, None otherwise.
        """
        normalized_path = path if path.startswith("/") else "/" + path
        # Normalize by removing trailing slash if not root
        if len(normalized_path) > 1 and normalized_path.endswith("/"):
            normalized_path = normalized_path.rstrip("/")

        for rule in self.rules:
            if rule.rule_type == "webhook" and rule.endpoint:
                rule_ep = rule.endpoint
                if len(rule_ep) > 1 and rule_ep.endswith("/"):
                    rule_ep = rule_ep.rstrip("/")
                if rule_ep == normalized_path:
                    return rule
        return None

    def match_file_change(self, modified_path: str) -> Rule | None:
        """Matches a modified file path against registered file_change rules.

        Args:
            modified_path: Path of the modified file.

        Returns:
            Matching Rule if found, None otherwise.
        """
        abs_modified = os.path.normcase(os.path.abspath(modified_path))

        for rule in self.rules:
            if (
                rule.rule_type == "file_change"
                and rule.watch_path
                and os.path.normcase(rule.watch_path) == abs_modified
            ):
                return rule
        return None

    def get_all_webhook_rules(self) -> list[Rule]:
        """Returns all rules of type 'webhook'."""
        return [r for r in self.rules if r.rule_type == "webhook"]

    def get_all_file_change_rules(self) -> list[Rule]:
        """Returns all rules of type 'file_change'."""
        return [r for r in self.rules if r.rule_type == "file_change"]
