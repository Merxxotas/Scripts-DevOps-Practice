"""
Entry point for running system_monitor as a module.

Usage:
    python -m system_monitor
    uv run -m system_monitor
"""

from system_monitor.cli import main

if __name__ == "__main__":
    main()
