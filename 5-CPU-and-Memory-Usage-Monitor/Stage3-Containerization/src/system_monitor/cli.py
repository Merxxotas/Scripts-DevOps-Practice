"""
Command-line interface for System Resource Monitor.
Uses Click for argument parsing and command structure.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import click

from system_monitor import __version__
from system_monitor.exporters import CSVExporter, DisplayExporter, JSONExporter
from system_monitor.monitor import SystemMonitor


@click.group(invoke_without_command=True)
@click.version_option(version=__version__, prog_name="system-monitor")
@click.option("--watch", "-w", is_flag=True, help="Enable continuous monitoring mode")
@click.option(
    "--interval",
    "-i",
    default=2.0,
    type=click.FloatRange(min=0.1, max=300),
    help="Refresh interval in seconds (0.1-300, default: 2)",
)
@click.option(
    "--format",
    "-f",
    "output_format",
    type=click.Choice(["display", "json", "csv"], case_sensitive=False),
    default="display",
    help="Output format (default: display)",
)
@click.option(
    "--export",
    "-e",
    "export_path",
    type=click.Path(path_type=Path),
    help="Export to file or directory",
)
@click.option(
    "--top",
    "-t",
    default=100,
    type=click.IntRange(min=1, max=1000),
    help="Number of top processes to show (default: 100)",
)
@click.option(
    "--cpu-threshold",
    default=80.0,
    type=click.FloatRange(min=0, max=100),
    help="CPU threshold for HIGH alert (default: 80)",
)
@click.option(
    "--mem-threshold",
    default=80.0,
    type=click.FloatRange(min=0, max=100),
    help="Memory threshold for HIGH alert (default: 80)",
)
@click.option("--no-color", is_flag=True, help="Disable colored output")
@click.pass_context
def cli(
    ctx: click.Context,
    watch: bool,
    interval: float,
    output_format: str,
    export_path: Path | None,
    top: int,
    cpu_threshold: float,
    mem_threshold: float,
    no_color: bool,
) -> None:
    """
    Cross-Platform System Resource Monitor (Python Unified)

    Monitors CPU, Memory, Disk, and Process information.
    Supports JSON, CSV, and Display output formats.

    \b
    Examples:
      system-monitor                          # Standard display mode
      system-monitor -f json                  # Output JSON to stdout
      system-monitor -e ./report.json         # Export to file
      system-monitor -w -i 5 -e ./logs/       # Watch mode with export
    """
    # Ensure context object exists
    if ctx.obj is None:
        ctx.obj = {}

    ctx.obj["monitor"] = SystemMonitor()
    ctx.obj["interval"] = interval
    ctx.obj["top"] = top
    ctx.obj["cpu_threshold"] = cpu_threshold
    ctx.obj["mem_threshold"] = mem_threshold
    ctx.obj["no_color"] = no_color

    # Handle export path
    if export_path:
        if export_path.is_dir():
            # Generate timestamped filename
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            if output_format == "csv":
                export_path = export_path / f"system_monitor_{timestamp}.csv"
            else:
                export_path = export_path / f"system_monitor_{timestamp}.json"
            click.echo(f"Export directory provided. Will save as: {export_path.name}", err=True)

        # Auto-detect format from extension
        if output_format == "display":
            if export_path.suffix == ".csv":
                output_format = "csv"
            elif export_path.suffix == ".json":
                output_format = "json"
            else:
                output_format = "json"
                export_path = export_path.with_suffix(".json")

        # Ensure parent directory exists
        export_path.parent.mkdir(parents=True, exist_ok=True)

    ctx.obj["export_path"] = export_path
    ctx.obj["format"] = output_format

    # If no subcommand and not in watch mode, run single snapshot
    if ctx.invoked_subcommand is None:
        run_monitor(ctx.obj, watch)


def run_monitor(config: dict, watch_mode: bool) -> None:
    """
    Run the monitor (single snapshot or watch mode).

    Args:
        config: Configuration dictionary
        watch_mode: Whether to run in continuous watch mode
    """
    monitor: SystemMonitor = config["monitor"]
    output_format: str = config["format"]
    export_path: Path | None = config["export_path"]
    interval: float = config["interval"]
    top: int = config["top"]
    cpu_threshold: float = config["cpu_threshold"]
    mem_threshold: float = config["mem_threshold"]
    no_color: bool = config["no_color"]

    # Create exporters
    exporters = {
        "json": JSONExporter(),
        "csv": CSVExporter(),
        "display": DisplayExporter(
            use_color=not no_color,
            cpu_threshold=cpu_threshold,
            mem_threshold=mem_threshold,
        ),
    }

    if watch_mode:
        click.echo(f"Starting watch mode (refresh every {interval}s).", err=True)
        click.echo("Press Ctrl+C to exit.", err=True)
        click.echo("", err=True)
        time.sleep(1)

        try:
            while True:
                # Clear screen (cross-platform)
                click.clear()

                snapshot = monitor.get_snapshot(top_n=top)

                # Display
                exporters["display"].export(snapshot, sys.stdout)

                # Export if path specified
                if export_path:
                    if output_format == "json":
                        exporters["json"].export_to_file(snapshot, export_path)
                    elif output_format == "csv":
                        exporters["csv"].export_to_file(snapshot, export_path)
                    click.echo(f"\n[Logged to: {export_path.name}]", err=True)

                click.echo(
                    f"\nLast update: {time.strftime('%H:%M:%S')} | Next refresh in {interval}s (Ctrl+C to quit)",
                    err=True,
                )
                time.sleep(interval)

        except KeyboardInterrupt:
            click.echo("\n\nWatch mode stopped.", err=True)
            if export_path:
                click.echo(f"Final log: {export_path}", err=True)
    else:
        # Single snapshot
        snapshot = monitor.get_snapshot(top_n=top)

        if output_format == "json":
            if export_path:
                exporters["json"].export_to_file(snapshot, export_path)
                click.echo(f"Exported JSON to: {export_path}", err=True)
            else:
                exporters["json"].export(snapshot, sys.stdout)

        elif output_format == "csv":
            if export_path:
                exporters["csv"].export_to_file(snapshot, export_path)
                click.echo(f"Exported CSV to: {export_path}", err=True)
            else:
                click.echo("CSV format requires --export option", err=True)
                sys.exit(1)

        else:  # display
            exporters["display"].export(snapshot, sys.stdout)
            if export_path:
                exporters["json"].export_to_file(snapshot, export_path)
                click.echo(f"\nExported to: {export_path}", err=True)


@cli.command()
@click.argument("target")
@click.option("--force", "-f", is_flag=True, help="Force kill (SIGKILL) without graceful shutdown")
@click.option(
    "--signal",
    "-s",
    type=click.Choice(["TERM", "KILL", "HUP"], case_sensitive=False),
    default="TERM",
    help="Signal to send (default: TERM)",
)
@click.pass_obj
def kill(config: dict, target: str, force: bool, signal: str) -> None:
    """
    Kill a process by PID or name.

    TARGET can be a PID (numeric) or process name.

    \b
    Examples:
      system-monitor kill 1234              # Kill PID 1234
      system-monitor kill firefox           # Kill all firefox processes
      system-monitor kill 1234 --force      # Force kill
      system-monitor kill firefox -s KILL   # Use SIGKILL
    """
    monitor: SystemMonitor = config["monitor"]

    # Determine if target is PID or name
    if target.isdigit():
        pid = int(target)
        success, message = monitor.kill_process(pid, force=(force or signal == "KILL"))
        if success:
            click.echo(f"✓ {message}")
        else:
            click.echo(f"✗ {message}", err=True)
            sys.exit(1)
    else:
        attempted, killed, message = monitor.kill_process_by_name(
            target, force=(force or signal == "KILL")
        )
        click.echo(message)
        if killed == 0 and attempted > 0:
            sys.exit(1)


@cli.command()
@click.argument("target")
@click.option("--command", "-c", help="Custom command to restart with (optional)")
@click.option("--force", "-f", is_flag=True, help="Force kill without graceful shutdown")
@click.pass_obj
def restart(config: dict, target: str, command: str | None, force: bool) -> None:
    """
    Restart a process by PID or name.

    TARGET can be a PID (numeric) or process name.

    \b
    Examples:
      system-monitor restart 1234                    # Restart PID 1234
      system-monitor restart nginx                   # Restart nginx
      system-monitor restart nginx -c "nginx -c /etc/nginx.conf"
    """
    monitor: SystemMonitor = config["monitor"]

    # Determine if target is PID or name
    target_id = int(target) if target.isdigit() else target

    success, message = monitor.restart_process(target_id, command)
    if success:
        click.echo(f"✓ {message}")
    else:
        click.echo(f"✗ {message}", err=True)
        sys.exit(1)


@cli.command(name="kill-log")
@click.option("--lines", "-n", default=10, type=int, help="Number of lines to show (default: 10)")
@click.pass_obj
def kill_log(config: dict, lines: int) -> None:
    """
    Show recent kill/restart actions.

    Displays the kill/restart log for audit purposes.
    """
    monitor: SystemMonitor = config["monitor"]
    log_entries = monitor.get_kill_log(lines)

    if log_entries:
        click.echo("Recent Kill/Restart Actions:")
        for entry in log_entries:
            click.echo(f"  {entry.rstrip()}")
    else:
        click.echo("No kill log found.")


def main() -> None:
    """Entry point for the CLI."""
    cli()


if __name__ == "__main__":
    main()
