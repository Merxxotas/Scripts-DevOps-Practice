"""
Unit tests for exporters.
"""

import csv
import io
import json
from datetime import datetime
from pathlib import Path

import pytest

from system_monitor.exporters import CSVExporter, DisplayExporter, JSONExporter
from system_monitor.models import DiskIO, DiskUsage, ProcessInfo, SystemSnapshot


@pytest.fixture
def sample_snapshot() -> SystemSnapshot:
    """Create a sample snapshot for testing."""
    return SystemSnapshot(
        timestamp=datetime(2024, 1, 1, 12, 0, 0),
        os="Linux",
        cpu_percent=50.0,
        memory_percent=60.0,
        disk_usage=[
            DiskUsage("/", 100.0, 50.0, 50.0, 50.0),
            DiskUsage("/home", 200.0, 100.0, 100.0, 50.0),
        ],
        disk_io=[
            DiskIO("sda", 1000, 500, 8000, 4000),
        ],
        top_processes=[
            ProcessInfo("python", 1234, 25.0, 512.0),
            ProcessInfo("chrome", 5678, 15.0, 256.0),
        ],
        aggregated_totals=[
            ProcessInfo("python", 0, 0.0, 1024.0),
        ],
    )


class TestJSONExporter:
    """Tests for JSONExporter."""

    def test_export_to_stream(self, sample_snapshot: SystemSnapshot) -> None:
        """Test exporting to a stream."""
        exporter = JSONExporter()
        output = io.StringIO()
        exporter.export(sample_snapshot, output)

        output.seek(0)
        data = json.load(output)

        assert data["os"] == "Linux"
        assert data["cpu_percent"] == 50.0
        assert len(data["disk_usage"]) == 2

    def test_export_to_file(self, sample_snapshot: SystemSnapshot, tmp_path: Path) -> None:
        """Test exporting to a file."""
        exporter = JSONExporter()
        file_path = tmp_path / "test.json"
        exporter.export_to_file(sample_snapshot, file_path)

        assert file_path.exists()
        with open(file_path) as f:
            data = json.load(f)
        assert data["os"] == "Linux"


class TestCSVExporter:
    """Tests for CSVExporter."""

    def test_export_to_stream(self, sample_snapshot: SystemSnapshot) -> None:
        """Test exporting to a stream."""
        exporter = CSVExporter()
        output = io.StringIO()
        exporter.export(sample_snapshot, output)

        output.seek(0)
        reader = csv.reader(output)
        rows = list(reader)

        # Check header
        assert rows[0][0] == "timestamp"
        assert "metric_type" in rows[0]

        # Should have multiple rows (system + processes + disks)
        assert len(rows) > 1

    def test_export_to_file(self, sample_snapshot: SystemSnapshot, tmp_path: Path) -> None:
        """Test exporting to a file."""
        exporter = CSVExporter()
        file_path = tmp_path / "test.csv"
        exporter.export_to_file(sample_snapshot, file_path)

        assert file_path.exists()
        with open(file_path, newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        assert len(rows) > 1


class TestDisplayExporter:
    """Tests for DisplayExporter."""

    def test_export_with_colors(self, sample_snapshot: SystemSnapshot) -> None:
        """Test display export with colors."""
        exporter = DisplayExporter(use_color=True)
        output = io.StringIO()
        exporter.export(sample_snapshot, output)

        output.seek(0)
        content = output.read()

        assert "System Resource Monitor" in content
        assert "CPU Usage:" in content
        assert "Memory Usage:" in content
        assert "python" in content  # Process name

    def test_export_without_colors(self, sample_snapshot: SystemSnapshot) -> None:
        """Test display export without colors."""
        exporter = DisplayExporter(use_color=False)
        output = io.StringIO()
        exporter.export(sample_snapshot, output)

        output.seek(0)
        content = output.read()

        assert "System Resource Monitor" in content
        # Should not contain ANSI codes
        assert "\033[" not in content

    def test_export_file_not_supported(
        self, sample_snapshot: SystemSnapshot, tmp_path: Path
    ) -> None:
        """Test that export_to_file raises NotImplementedError."""
        exporter = DisplayExporter()
        with pytest.raises(NotImplementedError):
            exporter.export_to_file(sample_snapshot, tmp_path / "test.txt")
