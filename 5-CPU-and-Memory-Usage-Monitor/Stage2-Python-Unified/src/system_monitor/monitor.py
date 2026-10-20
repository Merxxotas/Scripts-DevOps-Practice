"""
Core system monitoring functionality.
Uses psutil for cross-platform system information.
"""

from __future__ import annotations

import platform
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

import psutil

from .models import (
    DiskIO,
    DiskUsage,
    KillAction,
    ProcessInfo,
    SystemSnapshot,
)


class SystemMonitor:
    """
    Cross-platform system resource monitor.

    Provides CPU, memory, disk, and process monitoring capabilities.
    Supports JSON and CSV export formats.
    """

    # Thresholds for color coding
    CPU_THRESHOLD: float = 80.0
    MEM_THRESHOLD: float = 80.0
    DISK_WARNING: float = 70.0
    DISK_CRITICAL: float = 90.0

    def __init__(self) -> None:
        """Initialize the system monitor."""
        self.os: str = platform.system()
        self.kill_log_path: Path = (
            Path("/tmp" if self.os != "Windows" else Path.home() / "AppData" / "Local" / "Temp")
            / "system_monitor_kill.log"
        )

    def get_cpu_usage(self) -> float | None:
        """
        Get current CPU usage percentage.

        Returns:
            CPU usage as percentage (0-100), or None if unavailable
        """
        try:
            return psutil.cpu_percent(interval=1)
        except Exception as e:
            print(f"Warning: Could not read CPU usage: {e}", file=sys.stderr)
            return None

    def get_memory_usage(self) -> float | None:
        """
        Get current memory usage percentage.

        Returns:
            Memory usage as percentage (0-100), or None if unavailable
        """
        try:
            return psutil.virtual_memory().percent
        except Exception as e:
            print(f"Warning: Could not read memory usage: {e}", file=sys.stderr)
            return None

    def get_disk_usage(self) -> list[DiskUsage]:
        """
        Get disk usage for all mounted partitions.

        Returns:
            List of DiskUsage objects
        """
        disks: list[DiskUsage] = []

        try:
            partitions = psutil.disk_partitions(all=False)
            for partition in partitions:
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                    disks.append(
                        DiskUsage(
                            mount_point=partition.mountpoint,
                            total_gb=round(usage.total / (1024**3), 2),
                            used_gb=round(usage.used / (1024**3), 2),
                            free_gb=round(usage.free / (1024**3), 2),
                            percent_used=round((usage.used / usage.total) * 100, 1)
                            if usage.total > 0
                            else 0.0,
                        )
                    )
                except PermissionError:
                    # Skip partitions we can't access
                    continue
        except Exception as e:
            print(f"Warning: Could not read disk usage: {e}", file=sys.stderr)

        return disks

    def get_disk_io(self) -> list[DiskIO]:
        """
        Get disk I/O statistics.

        Returns:
            List of DiskIO objects
        """
        io_stats: list[DiskIO] = []

        try:
            disk_io = psutil.disk_io_counters(perdisk=True)
            if disk_io:
                for device, stats in disk_io.items():
                    io_stats.append(
                        DiskIO(
                            device=device,
                            reads_completed=stats.read_count,
                            writes_completed=stats.write_count,
                            read_sectors=getattr(stats, "read_sectors", None),
                            write_sectors=getattr(stats, "write_sectors", None),
                            read_bytes_per_sec=getattr(stats, "read_bytes", None),
                            write_bytes_per_sec=getattr(stats, "write_bytes", None),
                        )
                    )
        except Exception as e:
            print(f"Warning: Could not read disk I/O: {e}", file=sys.stderr)

        return io_stats

    def get_process_data(self, top_n: int = 100) -> list[ProcessInfo]:
        """
        Get top N processes by memory usage.

        Args:
            top_n: Number of top processes to return

        Returns:
            List of ProcessInfo objects sorted by RAM usage
        """
        processes: list[ProcessInfo] = []

        try:
            for proc in psutil.process_iter(["name", "pid", "cpu_percent", "memory_info"]):
                try:
                    info = proc.info
                    memory_info = info.get("memory_info")
                    processes.append(
                        ProcessInfo(
                            name=info.get("name") or "unknown",
                            pid=info.get("pid", 0),
                            cpu_percent=info.get("cpu_percent") or 0.0,
                            ram_mb=round(memory_info.rss / (1024 * 1024), 2)
                            if memory_info
                            else 0.0,
                        )
                    )
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception as e:
            print(f"Warning: Could not read process data: {e}", file=sys.stderr)

        # Sort by RAM usage descending
        return sorted(processes, key=lambda p: p.ram_mb, reverse=True)[:top_n]

    def get_aggregated_data(self) -> list[ProcessInfo]:
        """
        Get aggregated totals by process name.

        Returns:
            List of ProcessInfo with aggregated RAM and instance counts
        """
        aggregated: dict[str, tuple[float, int]] = defaultdict(lambda: (0.0, 0))

        try:
            for proc in psutil.process_iter(["name", "memory_info"]):
                try:
                    info = proc.info
                    name = info.get("name") or "unknown"
                    memory_info = info.get("memory_info")
                    ram_mb = memory_info.rss / (1024 * 1024) if memory_info else 0.0

                    current_ram, count = aggregated[name]
                    aggregated[name] = (current_ram + ram_mb, count + 1)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception as e:
            print(f"Warning: Could not read aggregated data: {e}", file=sys.stderr)

        # Convert to ProcessInfo list
        result = [
            ProcessInfo(
                name=name,
                pid=0,  # Aggregated, no single PID
                cpu_percent=0.0,
                ram_mb=round(total_ram, 2),
            )
            for name, (total_ram, count) in aggregated.items()
        ]

        return sorted(result, key=lambda p: p.ram_mb, reverse=True)

    def get_snapshot(self, top_n: int = 100) -> SystemSnapshot:
        """
        Get a complete system snapshot.

        Args:
            top_n: Number of top processes to include

        Returns:
            SystemSnapshot with all monitoring data
        """
        return SystemSnapshot(
            timestamp=datetime.now(),
            os=self.os,
            cpu_percent=self.get_cpu_usage(),
            memory_percent=self.get_memory_usage(),
            disk_usage=self.get_disk_usage(),
            disk_io=self.get_disk_io(),
            top_processes=self.get_process_data(top_n=top_n),
            aggregated_totals=self.get_aggregated_data(),
        )

    def kill_process(self, pid: int, force: bool = False) -> tuple[bool, str]:
        """
        Kill a process by PID.

        Args:
            pid: Process ID to kill
            force: If True, kill immediately without graceful shutdown

        Returns:
            Tuple of (success, message)
        """
        try:
            proc = psutil.Process(pid)
            name = proc.name()

            if force:
                proc.kill()
            else:
                proc.terminate()
                # Wait up to 3 seconds for graceful termination
                gone, alive = psutil.wait_procs([proc], timeout=3)
                if proc in alive:
                    proc.kill()

            self._log_action("KILL", pid, "SUCCESS", f"Process: {name}")
            return True, f"Process {pid} ({name}) terminated"

        except psutil.NoSuchProcess:
            # Process already gone - consider this success
            return True, f"Process {pid} was not running"
        except Exception as e:
            self._log_action("KILL", pid, "FAILED", str(e))
            return False, f"Failed to kill process {pid}: {e}"

    def kill_process_by_name(self, name: str, force: bool = False) -> tuple[int, int, str]:
        """
        Kill all processes matching a name.

        Args:
            name: Process name to match
            force: If True, kill immediately

        Returns:
            Tuple of (attempted, killed, message)
        """
        killed = 0
        attempted = 0

        try:
            procs = [p for p in psutil.process_iter(["name", "pid"]) if p.info.get("name") == name]

            for proc in procs:
                attempted += 1
                success, _ = self.kill_process(proc.pid, force)
                if success:
                    killed += 1

            return attempted, killed, f"Killed {killed}/{attempted} processes matching '{name}'"

        except Exception as e:
            return attempted, killed, f"Error killing processes: {e}"

    def restart_process(self, target: int | str, command: str | None = None) -> tuple[bool, str]:
        """
        Restart a process by PID or name.

        Args:
            target: PID (int) or process name (str)
            command: Optional command to restart with

        Returns:
            Tuple of (success, message)
        """
        try:
            if isinstance(target, int):
                proc = psutil.Process(target)
                proc.name()
                cmdline = command or " ".join(proc.cmdline())
                self.kill_process(target)
            else:
                # Find first matching process
                procs = [
                    p
                    for p in psutil.process_iter(["name", "pid", "cmdline"])
                    if p.info.get("name") == target
                ]
                if not procs:
                    return False, f"No process found with name: {target}"

                proc = procs[0]
                proc.info.get("name")
                cmdline = command or " ".join(proc.info.get("cmdline", []))
                self.kill_process(proc.pid)

            # Wait a moment then restart
            import time

            time.sleep(1)

            if cmdline:
                import subprocess

                subprocess.Popen(cmdline, shell=True)
                self._log_action("RESTART", target, "SUCCESS", f"Command: {cmdline}")
                return True, f"Process restarted with command: {cmdline}"

            return True, "Process killed (no restart command provided)"

        except Exception as e:
            self._log_action("RESTART", target, "FAILED", str(e))
            return False, f"Failed to restart: {e}"

    def _log_action(self, action: str, target: Any, result: str, details: str) -> None:
        """Log kill/restart actions to file."""
        try:
            action_record = KillAction(
                timestamp=datetime.now(),
                action=action,
                target=target,
                result=result,
                details=details,
            )
            with open(self.kill_log_path, "a") as f:
                f.write(
                    f"[{action_record.timestamp.isoformat()}] [{action}] Target: {target} | Result: {result} | {details}\n"
                )
        except Exception:
            pass  # Silently fail logging

    def get_kill_log(self, lines: int = 10) -> list[str]:
        """Get recent kill/restart actions."""
        try:
            if self.kill_log_path.exists():
                with open(self.kill_log_path) as f:
                    return f.readlines()[-lines:]
        except Exception:
            pass
        return []
