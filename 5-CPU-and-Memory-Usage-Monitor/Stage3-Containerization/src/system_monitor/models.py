"""
Data models for system monitoring.
Uses dataclasses with type hints for structured data.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any


@dataclass
class ProcessInfo:
    """Type-safe process information container."""

    name: str
    pid: int
    cpu_percent: float
    ram_mb: float

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)


@dataclass
class DiskUsage:
    """Disk usage information."""

    mount_point: str
    total_gb: float
    used_gb: float
    free_gb: float
    percent_used: float

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)

    def get_color(self) -> str:
        """Return color code based on usage percentage."""
        if self.percent_used > 90:
            return "red"
        elif self.percent_used > 70:
            return "yellow"
        return "green"


@dataclass
class DiskIO:
    """Disk I/O statistics."""

    device: str
    reads_completed: int
    writes_completed: int
    read_sectors: int | None = None
    write_sectors: int | None = None
    read_bytes_per_sec: float | None = None
    write_bytes_per_sec: float | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)


@dataclass
class SystemSnapshot:
    """Complete system state snapshot."""

    timestamp: datetime
    os: str
    cpu_percent: float | None
    memory_percent: float | None
    disk_usage: list[DiskUsage]
    disk_io: list[DiskIO]
    top_processes: list[ProcessInfo]
    aggregated_totals: list[ProcessInfo]

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "os": self.os,
            "cpu_percent": self.cpu_percent,
            "memory_percent": self.memory_percent,
            "disk_usage": [d.to_dict() for d in self.disk_usage],
            "disk_io": [d.to_dict() for d in self.disk_io],
            "top_processes": [p.to_dict() for p in self.top_processes],
            "aggregated_totals": [p.to_dict() for p in self.aggregated_totals],
        }


@dataclass
class KillAction:
    """Record of a kill/restart action for audit logging."""

    timestamp: datetime
    action: str  # "KILL" or "RESTART"
    target: int | str  # PID or process name
    result: str  # "SUCCESS" or "FAILED"
    details: str

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "action": self.action,
            "target": self.target,
            "result": self.result,
            "details": self.details,
        }
