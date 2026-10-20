"""
Unit tests for data models.
"""

from datetime import datetime

from system_monitor.models import (
    DiskIO,
    DiskUsage,
    KillAction,
    ProcessInfo,
    SystemSnapshot,
)


class TestProcessInfo:
    """Tests for ProcessInfo model."""

    def test_process_info_creation(self) -> None:
        """Test creating a ProcessInfo instance."""
        proc = ProcessInfo(
            name="python",
            pid=1234,
            cpu_percent=25.5,
            ram_mb=512.34,
        )
        assert proc.name == "python"
        assert proc.pid == 1234
        assert proc.cpu_percent == 25.5
        assert proc.ram_mb == 512.34

    def test_process_info_to_dict(self) -> None:
        """Test converting ProcessInfo to dictionary."""
        proc = ProcessInfo(
            name="python",
            pid=1234,
            cpu_percent=25.5,
            ram_mb=512.34,
        )
        d = proc.to_dict()
        assert d == {
            "name": "python",
            "pid": 1234,
            "cpu_percent": 25.5,
            "ram_mb": 512.34,
        }


class TestDiskUsage:
    """Tests for DiskUsage model."""

    def test_disk_usage_creation(self) -> None:
        """Test creating a DiskUsage instance."""
        disk = DiskUsage(
            mount_point="/",
            total_gb=100.0,
            used_gb=50.0,
            free_gb=50.0,
            percent_used=50.0,
        )
        assert disk.mount_point == "/"
        assert disk.total_gb == 100.0

    def test_disk_usage_get_color_green(self) -> None:
        """Test color returns green for low usage."""
        disk = DiskUsage(
            mount_point="/",
            total_gb=100.0,
            used_gb=50.0,
            free_gb=50.0,
            percent_used=50.0,
        )
        assert disk.get_color() == "green"

    def test_disk_usage_get_color_yellow(self) -> None:
        """Test color returns yellow for medium usage."""
        disk = DiskUsage(
            mount_point="/",
            total_gb=100.0,
            used_gb=80.0,
            free_gb=20.0,
            percent_used=80.0,
        )
        assert disk.get_color() == "yellow"

    def test_disk_usage_get_color_red(self) -> None:
        """Test color returns red for high usage."""
        disk = DiskUsage(
            mount_point="/",
            total_gb=100.0,
            used_gb=95.0,
            free_gb=5.0,
            percent_used=95.0,
        )
        assert disk.get_color() == "red"

    def test_disk_usage_to_dict(self) -> None:
        """Test converting DiskUsage to dictionary."""
        disk = DiskUsage(
            mount_point="/",
            total_gb=100.0,
            used_gb=50.0,
            free_gb=50.0,
            percent_used=50.0,
        )
        d = disk.to_dict()
        assert d["mount_point"] == "/"
        assert d["percent_used"] == 50.0


class TestDiskIO:
    """Tests for DiskIO model."""

    def test_disk_io_creation(self) -> None:
        """Test creating a DiskIO instance."""
        io = DiskIO(
            device="sda",
            reads_completed=1000,
            writes_completed=500,
            read_sectors=8000,
            write_sectors=4000,
        )
        assert io.device == "sda"
        assert io.reads_completed == 1000
        assert io.writes_completed == 500


class TestSystemSnapshot:
    """Tests for SystemSnapshot model."""

    def test_snapshot_creation(self) -> None:
        """Test creating a SystemSnapshot."""
        snapshot = SystemSnapshot(
            timestamp=datetime(2024, 1, 1, 12, 0, 0),
            os="Linux",
            cpu_percent=50.0,
            memory_percent=60.0,
            disk_usage=[],
            disk_io=[],
            top_processes=[],
            aggregated_totals=[],
        )
        assert snapshot.os == "Linux"
        assert snapshot.cpu_percent == 50.0

    def test_snapshot_to_dict(self) -> None:
        """Test converting SystemSnapshot to dictionary."""
        snapshot = SystemSnapshot(
            timestamp=datetime(2024, 1, 1, 12, 0, 0),
            os="Linux",
            cpu_percent=50.0,
            memory_percent=60.0,
            disk_usage=[
                DiskUsage("/", 100.0, 50.0, 50.0, 50.0),
            ],
            disk_io=[
                DiskIO("sda", 1000, 500),
            ],
            top_processes=[
                ProcessInfo("python", 1234, 25.0, 512.0),
            ],
            aggregated_totals=[],
        )
        d = snapshot.to_dict()
        assert d["os"] == "Linux"
        assert d["cpu_percent"] == 50.0
        assert len(d["disk_usage"]) == 1
        assert len(d["top_processes"]) == 1


class TestKillAction:
    """Tests for KillAction model."""

    def test_kill_action_creation(self) -> None:
        """Test creating a KillAction."""
        action = KillAction(
            timestamp=datetime(2024, 1, 1, 12, 0, 0),
            action="KILL",
            target=1234,
            result="SUCCESS",
            details="Process: python",
        )
        assert action.action == "KILL"
        assert action.result == "SUCCESS"

    def test_kill_action_to_dict(self) -> None:
        """Test converting KillAction to dictionary."""
        action = KillAction(
            timestamp=datetime(2024, 1, 1, 12, 0, 0),
            action="RESTART",
            target="nginx",
            result="SUCCESS",
            details="New PID: 5678",
        )
        d = action.to_dict()
        assert d["action"] == "RESTART"
        assert d["target"] == "nginx"
