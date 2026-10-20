"""
Unit tests for CLI commands.
Uses Click's test runner.
"""

from unittest.mock import Mock, patch

import pytest
from click.testing import CliRunner

from system_monitor.cli import cli


@pytest.fixture
def runner() -> CliRunner:
    """Create a Click test runner."""
    return CliRunner()


class TestCLIVersion:
    """Tests for version command."""

    def test_version(self, runner: CliRunner) -> None:
        """Test version output."""
        result = runner.invoke(cli, ["--version"])
        assert result.exit_code == 0
        assert "system-monitor" in result.output


class TestCLIMonitor:
    """Tests for main monitoring command."""

    @patch("system_monitor.cli.SystemMonitor")
    def test_display_mode(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test display mode output."""
        mock_monitor = Mock()
        mock_snapshot = Mock()
        mock_snapshot.to_dict.return_value = {
            "os": "Linux",
            "cpu_percent": 50.0,
            "memory_percent": 60.0,
            "disk_usage": [],
            "disk_io": [],
            "top_processes": [],
            "aggregated_totals": [],
        }
        mock_monitor.get_snapshot.return_value = mock_snapshot
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, [])

        # Should run without errors
        assert result.exit_code == 0 or result.exit_code is None

    @patch("system_monitor.cli.SystemMonitor")
    def test_json_output(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test JSON output format."""
        mock_monitor = Mock()
        mock_snapshot = Mock()
        mock_snapshot.to_dict.return_value = {
            "os": "Linux",
            "cpu_percent": 50.0,
            "memory_percent": 60.0,
            "disk_usage": [],
            "disk_io": [],
            "top_processes": [],
            "aggregated_totals": [],
        }
        mock_monitor.get_snapshot.return_value = mock_snapshot
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["--format", "json"])

        assert result.exit_code == 0
        assert "Linux" in result.output or result.output == ""


class TestCLIKill:
    """Tests for kill command."""

    @patch("system_monitor.cli.SystemMonitor")
    def test_kill_by_pid(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test killing by PID."""
        mock_monitor = Mock()
        mock_monitor.kill_process.return_value = (True, "Process 1234 terminated")
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["kill", "1234"])

        assert result.exit_code == 0
        mock_monitor.kill_process.assert_called_once_with(1234, force=False)

    @patch("system_monitor.cli.SystemMonitor")
    def test_kill_by_name(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test killing by process name."""
        mock_monitor = Mock()
        mock_monitor.kill_process_by_name.return_value = (1, 1, "Killed 1/1 processes")
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["kill", "firefox"])

        assert result.exit_code == 0
        mock_monitor.kill_process_by_name.assert_called_once_with("firefox", force=False)

    @patch("system_monitor.cli.SystemMonitor")
    def test_kill_force(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test force kill."""
        mock_monitor = Mock()
        mock_monitor.kill_process.return_value = (True, "Process terminated")
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["kill", "1234", "--force"])

        assert result.exit_code == 0
        mock_monitor.kill_process.assert_called_once_with(1234, force=True)


class TestCLIRestart:
    """Tests for restart command."""

    @patch("system_monitor.cli.SystemMonitor")
    def test_restart_by_pid(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test restarting by PID."""
        mock_monitor = Mock()
        mock_monitor.restart_process.return_value = (True, "Process restarted")
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["restart", "1234"])

        assert result.exit_code == 0
        mock_monitor.restart_process.assert_called_once_with(1234, None)

    @patch("system_monitor.cli.SystemMonitor")
    def test_restart_with_command(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test restart with custom command."""
        mock_monitor = Mock()
        mock_monitor.restart_process.return_value = (True, "Process restarted")
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["restart", "nginx", "--command", "nginx -c /etc/nginx.conf"])

        assert result.exit_code == 0
        mock_monitor.restart_process.assert_called_once_with("nginx", "nginx -c /etc/nginx.conf")


class TestCLIKillLog:
    """Tests for kill-log command."""

    @patch("system_monitor.cli.SystemMonitor")
    def test_kill_log_empty(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test kill log when empty."""
        mock_monitor = Mock()
        mock_monitor.get_kill_log.return_value = []
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["kill-log"])

        assert result.exit_code == 0
        assert "No kill log found" in result.output

    @patch("system_monitor.cli.SystemMonitor")
    def test_kill_log_with_entries(self, mock_monitor_class: Mock, runner: CliRunner) -> None:
        """Test kill log with entries."""
        mock_monitor = Mock()
        mock_monitor.get_kill_log.return_value = [
            "[2024-01-01] [KILL] Target: 1234 | Result: SUCCESS\n",
        ]
        mock_monitor_class.return_value = mock_monitor

        result = runner.invoke(cli, ["kill-log"])

        assert result.exit_code == 0
        assert "KILL" in result.output


class TestCLIHelp:
    """Tests for help output."""

    def test_main_help(self, runner: CliRunner) -> None:
        """Test main help text."""
        result = runner.invoke(cli, ["--help"])

        assert result.exit_code == 0
        assert "System Resource Monitor" in result.output
        assert "--watch" in result.output
        assert "--format" in result.output

    def test_kill_help(self, runner: CliRunner) -> None:
        """Test kill command help."""
        result = runner.invoke(cli, ["kill", "--help"])

        assert result.exit_code == 0
        assert "Kill a process" in result.output
        assert "--force" in result.output
