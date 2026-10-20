"""
Unit tests for SystemMonitor class.
Uses mocking to avoid actual system calls.
"""

from pathlib import Path
from unittest.mock import Mock, patch

from system_monitor.monitor import SystemMonitor


class TestSystemMonitorInit:
    """Tests for SystemMonitor initialization."""

    def test_init(self) -> None:
        """Test monitor initialization."""
        monitor = SystemMonitor()
        assert monitor.os is not None
        assert isinstance(monitor.kill_log_path, Path)


class TestSystemMonitorMetrics:
    """Tests for metric collection methods."""

    @patch("system_monitor.monitor.psutil.cpu_percent")
    def test_get_cpu_usage(self, mock_cpu: Mock) -> None:
        """Test CPU usage retrieval."""
        mock_cpu.return_value = 50.0
        monitor = SystemMonitor()

        result = monitor.get_cpu_usage()

        assert result == 50.0
        mock_cpu.assert_called_once_with(interval=1)

    @patch("system_monitor.monitor.psutil.cpu_percent")
    def test_get_cpu_usage_error(self, mock_cpu: Mock) -> None:
        """Test CPU usage error handling."""
        mock_cpu.side_effect = Exception("CPU error")
        monitor = SystemMonitor()

        result = monitor.get_cpu_usage()

        assert result is None

    @patch("system_monitor.monitor.psutil.virtual_memory")
    def test_get_memory_usage(self, mock_mem: Mock) -> None:
        """Test memory usage retrieval."""
        mock_mem.return_value = Mock(percent=60.0)
        monitor = SystemMonitor()

        result = monitor.get_memory_usage()

        assert result == 60.0

    @patch("system_monitor.monitor.psutil.disk_partitions")
    @patch("system_monitor.monitor.psutil.disk_usage")
    def test_get_disk_usage(self, mock_usage: Mock, mock_parts: Mock) -> None:
        """Test disk usage retrieval."""
        mock_parts.return_value = [
            Mock(mountpoint="/", fstype="ext4"),
        ]
        mock_usage.return_value = Mock(
            total=100 * 1024**3,  # 100 GB
            used=50 * 1024**3,  # 50 GB
            free=50 * 1024**3,  # 50 GB
        )
        monitor = SystemMonitor()

        result = monitor.get_disk_usage()

        assert len(result) == 1
        assert result[0].mount_point == "/"
        assert result[0].percent_used == 50.0

    @patch("system_monitor.monitor.psutil.disk_io_counters")
    def test_get_disk_io(self, mock_io: Mock) -> None:
        """Test disk I/O retrieval."""
        mock_io.return_value = {
            "sda": Mock(
                read_count=1000,
                write_count=500,
                read_sectors=8000,
                write_sectors=4000,
            ),
        }
        monitor = SystemMonitor()

        result = monitor.get_disk_io()

        assert len(result) == 1
        assert result[0].device == "sda"
        assert result[0].reads_completed == 1000


class TestSystemMonitorSnapshot:
    """Tests for snapshot functionality."""

    @patch.object(SystemMonitor, "get_cpu_usage")
    @patch.object(SystemMonitor, "get_memory_usage")
    @patch.object(SystemMonitor, "get_disk_usage")
    @patch.object(SystemMonitor, "get_disk_io")
    @patch.object(SystemMonitor, "get_process_data")
    @patch.object(SystemMonitor, "get_aggregated_data")
    def test_get_snapshot(
        self,
        mock_agg: Mock,
        mock_proc: Mock,
        mock_disk_io: Mock,
        mock_disk: Mock,
        mock_mem: Mock,
        mock_cpu: Mock,
    ) -> None:
        """Test getting a complete snapshot."""
        mock_cpu.return_value = 50.0
        mock_mem.return_value = 60.0
        mock_disk.return_value = []
        mock_disk_io.return_value = []
        mock_proc.return_value = []
        mock_agg.return_value = []

        monitor = SystemMonitor()
        snapshot = monitor.get_snapshot(top_n=10)

        assert snapshot.os == monitor.os
        assert snapshot.cpu_percent == 50.0
        assert snapshot.memory_percent == 60.0
        mock_proc.assert_called_once_with(top_n=10)


class TestSystemMonitorKill:
    """Tests for kill functionality."""

    @patch("system_monitor.monitor.psutil.Process")
    def test_kill_process_success(self, mock_proc_class: Mock) -> None:
        """Test successful process kill."""
        mock_proc = Mock()
        mock_proc.name.return_value = "python"
        mock_proc_class.return_value = mock_proc

        monitor = SystemMonitor()
        success, message = monitor.kill_process(1234)

        assert success is True
        assert "1234" in message
        assert "python" in message
        mock_proc.terminate.assert_called_once()

    @patch("system_monitor.monitor.psutil.Process")
    def test_kill_process_force(self, mock_proc_class: Mock) -> None:
        """Test force kill."""
        mock_proc = Mock()
        mock_proc.name.return_value = "python"
        mock_proc_class.return_value = mock_proc

        monitor = SystemMonitor()
        success, message = monitor.kill_process(1234, force=True)

        assert success is True
        mock_proc.kill.assert_called_once()

    @patch("system_monitor.monitor.psutil.Process")
    def test_kill_process_not_found(self, mock_proc_class: Mock) -> None:
        """Test kill when process doesn't exist."""
        import psutil

        mock_proc_class.side_effect = psutil.NoSuchProcess(1234)

        monitor = SystemMonitor()
        success, message = monitor.kill_process(1234)

        # Should be considered success (process is already gone)
        assert success is True
        assert "not running" in message


class TestSystemMonitorLogging:
    """Tests for kill log functionality."""

    def test_get_kill_log_empty(self) -> None:
        """Test getting kill log when file doesn't exist."""
        monitor = SystemMonitor()
        # Use a non-existent path
        monitor.kill_log_path = Path("/nonexistent/path/log.txt")

        result = monitor.get_kill_log()

        assert result == []
