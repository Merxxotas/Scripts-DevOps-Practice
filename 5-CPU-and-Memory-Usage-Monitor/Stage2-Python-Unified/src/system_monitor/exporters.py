"""
Export handlers for different output formats.
Supports JSON and CSV export with proper formatting.
"""

from __future__ import annotations

import csv
import json
import sys
from abc import ABC, abstractmethod
from pathlib import Path
from typing import TextIO

from .models import SystemSnapshot


class BaseExporter(ABC):
    """Abstract base class for exporters."""

    @abstractmethod
    def export(self, snapshot: SystemSnapshot, output: TextIO) -> None:
        """
        Export the snapshot to the given output.

        Args:
            snapshot: SystemSnapshot to export
            output: File-like object to write to
        """
        pass

    @abstractmethod
    def export_to_file(self, snapshot: SystemSnapshot, path: Path) -> None:
        """
        Export the snapshot to a file.

        Args:
            snapshot: SystemSnapshot to export
            path: Path to write to
        """
        pass


class JSONExporter(BaseExporter):
    """Export system data as JSON."""

    def export(self, snapshot: SystemSnapshot, output: TextIO) -> None:
        """Export snapshot as JSON to output stream."""
        json.dump(snapshot.to_dict(), output, indent=2)
        output.write("\n")

    def export_to_file(self, snapshot: SystemSnapshot, path: Path) -> None:
        """Export snapshot as JSON to file."""
        with open(path, "w", encoding="utf-8") as f:
            self.export(snapshot, f)


class CSVExporter(BaseExporter):
    """Export system data as CSV."""

    def export(self, snapshot: SystemSnapshot, output: TextIO) -> None:
        """Export snapshot as CSV to output stream."""
        writer = csv.writer(output)

        # Write header
        writer.writerow(
            [
                "timestamp",
                "os",
                "metric_type",
                "name",
                "pid",
                "cpu_percent",
                "ram_mb",
                "instances",
                "mount_point",
                "device",
                "percent_used",
            ]
        )

        timestamp = snapshot.timestamp.isoformat()
        os_name = snapshot.os

        # System metrics
        writer.writerow(
            [
                timestamp,
                os_name,
                "system",
                "system",
                "",
                snapshot.cpu_percent or "",
                "",
                "",
                "",
                "",
                "",
            ]
        )
        writer.writerow(
            [
                timestamp,
                os_name,
                "system",
                "system",
                "",
                "",
                snapshot.memory_percent or "",
                "",
                "",
                "",
                "",
            ]
        )

        # Disk usage
        for disk in snapshot.disk_usage:
            writer.writerow(
                [
                    timestamp,
                    os_name,
                    "disk_usage",
                    "disk",
                    "",
                    "",
                    "",
                    "",
                    disk.mount_point,
                    "",
                    disk.percent_used,
                ]
            )

        # Disk I/O
        for io in snapshot.disk_io:
            writer.writerow(
                [timestamp, os_name, "disk_io", io.device, "", "", "", "", "", io.device, ""]
            )

        # Top processes
        for proc in snapshot.top_processes:
            writer.writerow(
                [
                    timestamp,
                    os_name,
                    "process",
                    proc.name,
                    proc.pid,
                    proc.cpu_percent,
                    proc.ram_mb,
                    1,
                    "",
                    "",
                    "",
                ]
            )

        # Aggregated totals
        for proc in snapshot.aggregated_totals:
            writer.writerow(
                [timestamp, os_name, "aggregate", proc.name, "", "", proc.ram_mb, "", "", "", ""]
            )

    def export_to_file(self, snapshot: SystemSnapshot, path: Path) -> None:
        """Export snapshot as CSV to file."""
        with open(path, "w", newline="", encoding="utf-8") as f:
            self.export(snapshot, f)


class DisplayExporter(BaseExporter):
    """Display system data in human-readable format with colors."""

    # ANSI color codes
    RED = "\033[0;31m"
    YELLOW = "\033[1;33m"
    GREEN = "\033[0;32m"
    CYAN = "\033[0;36m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"

    def __init__(
        self,
        use_color: bool = True,
        cpu_threshold: float = 80.0,
        mem_threshold: float = 80.0,
    ) -> None:
        """
        Initialize display exporter.

        Args:
            use_color: Whether to use ANSI color codes
            cpu_threshold: CPU usage percentage above which usage is flagged HIGH
            mem_threshold: Memory usage percentage above which usage is flagged HIGH
        """
        self.use_color = use_color and sys.platform != "win32"
        self.cpu_threshold = cpu_threshold
        self.mem_threshold = mem_threshold
        if sys.platform == "win32":
            # Try to enable ANSI on Windows
            try:
                import ctypes

                kernel32 = ctypes.windll.kernel32
                kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
                self.use_color = use_color
            except Exception:
                self.use_color = False

    def _color(self, color_code: str) -> str:
        """Return color code if colors enabled."""
        return color_code if self.use_color else ""

    def export(self, snapshot: SystemSnapshot, output: TextIO) -> None:
        """Display snapshot in human-readable format."""
        # Header
        output.write(
            f"{self._color(self.BLUE)}=== System Resource Monitor ==={self._color(self.NC)}\n"
        )
        output.write(
            f"{self._color(self.CYAN)}{snapshot.timestamp.strftime('%Y-%m-%d %H:%M:%S')}{self._color(self.NC)}\n"
        )
        output.write(f"{self._color(self.YELLOW)}OS: {snapshot.os}{self._color(self.NC)}\n\n")

        # CPU
        cpu = snapshot.cpu_percent
        output.write("CPU Usage: ")
        if cpu is None:
            output.write(f"{self._color(self.YELLOW)}Unable to detect{self._color(self.NC)}\n")
        elif cpu > self.cpu_threshold:
            output.write(f"{self._color(self.RED)}{cpu}% (HIGH){self._color(self.NC)}\n")
        else:
            output.write(f"{self._color(self.GREEN)}{cpu}%{self._color(self.NC)}\n")

        # Memory
        mem = snapshot.memory_percent
        output.write("Memory Usage: ")
        if mem is None:
            output.write(f"{self._color(self.YELLOW)}Unable to detect{self._color(self.NC)}\n")
        elif mem > self.mem_threshold:
            output.write(f"{self._color(self.RED)}{mem}% (HIGH){self._color(self.NC)}\n")
        else:
            output.write(f"{self._color(self.GREEN)}{mem}%{self._color(self.NC)}\n")

        # Disk Usage
        output.write(f"\n{self._color(self.YELLOW)}Disk Usage:{self._color(self.NC)}\n")
        for disk in snapshot.disk_usage:
            color = self._color(self.GREEN)
            if disk.percent_used > 90:
                color = self._color(self.RED)
            elif disk.percent_used > 70:
                color = self._color(self.YELLOW)
            output.write(
                f"{color}{disk.mount_point:15} {disk.used_gb:8.2f}GB used / {disk.total_gb:8.2f}GB total ({disk.percent_used:5.1f}%){self._color(self.NC)}\n"
            )

        # Disk I/O
        if snapshot.disk_io:
            output.write(
                f"\n{self._color(self.YELLOW)}Disk I/O Statistics:{self._color(self.NC)}\n"
            )
            for io in snapshot.disk_io:
                output.write(
                    f"{self._color(self.CYAN)}{io.device:10}{self._color(self.NC)} Reads: {io.reads_completed:10}  Writes: {io.writes_completed:10}\n"
                )

        # Top Processes
        output.write(
            f"\n{self._color(self.YELLOW)}Top Processes (Sorted by RAM Usage):{self._color(self.NC)}\n"
        )
        output.write(
            f"{self._color(self.CYAN)}{'PROCESS':<22} {'PID':<10} {'CPU(%)':<12} {'RAM(MB)':<12}{self._color(self.NC)}\n"
        )
        output.write(f"{self._color(self.CYAN)}{'-' * 62}{self._color(self.NC)}\n")

        for proc in snapshot.top_processes[:20]:  # Show top 20
            color = self._color(self.RED) if proc.ram_mb > 500 else ""
            output.write(
                f"{color}{proc.name:<22} {proc.pid:<10} {proc.cpu_percent:<12.1f} {proc.ram_mb:<12.1f}{self._color(self.NC)}\n"
            )

        # Aggregated
        output.write(
            f"\n{self._color(self.YELLOW)}Total Usage by Process (Aggregated RAM):{self._color(self.NC)}\n"
        )
        if snapshot.aggregated_totals:
            max_ram = snapshot.aggregated_totals[0].ram_mb
            for proc in snapshot.aggregated_totals[:20]:
                ram = proc.ram_mb
                if ram >= max_ram * 0.9:
                    color = self._color(self.RED)
                elif ram > max_ram * 0.6:
                    color = self._color(self.YELLOW)
                elif ram > max_ram * 0.3:
                    color = self._color(self.GREEN)
                else:
                    color = ""
                output.write(f"{color}{proc.name}{self._color(self.NC)}: {proc.ram_mb:.2f}MB\n")

    def export_to_file(self, snapshot: SystemSnapshot, path: Path) -> None:
        """Display is not meant for file export."""
        raise NotImplementedError("DisplayExporter does not support file export")
