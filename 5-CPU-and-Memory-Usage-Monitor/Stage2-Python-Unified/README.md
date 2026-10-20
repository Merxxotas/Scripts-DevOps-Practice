# System Resource Monitor - Stage 2: Python Unified

> **Python Unified Implementation** using Click, type hints, and psutil for cross-platform system monitoring.

---

## Quick Reference

| Feature | Status | Notes |
|---------|--------|-------|
| **Platforms** | Yes | Linux, macOS, Windows |
| **Python Version** | 3.9+ | Type hints throughout |
| **CLI Framework** | Click | Comprehensive help, validation |
| **Monitoring** | psutil | CPU, Memory, Disk, Process |
| **Export Formats** | JSON, CSV, Display | All with color coding |
| **Process Kill/Restart** | Yes | By PID or name |
| **Unit Tests** | pytest | Comprehensive coverage |

---

## Installation with UV

[UV](https://github.com/astral-sh/uv) is a modern Python package manager that's faster than pip. This project is optimized for UV.

### Option 1: Quick Run (No Virtual Environment)

Run the script directly with dependencies auto-installed:

```bash
# Clone/navigate to the project
cd Stage2-Python-Unified

# Quick execution with UV (module mode)
uv run --with click --with psutil --with colorama -m system_monitor

# With specific options
uv run --with click --with psutil --with colorama -m system_monitor --format json
```

### Option 2: Development Setup (Recommended)

Create a proper development environment with UV:

```bash
# Navigate to project
cd Stage2-Python-Unified

# Initialize UV project (creates virtual environment)
uv init

# Add production dependencies
uv add click psutil
uv add colorama  # Windows only, but safe on all platforms

# Add development dependencies
uv add --dev pytest pytest-cov pytest-mock mypy ruff black

# Activate the virtual environment
source .venv/bin/activate  # Linux/macOS
# or
.venv\Scripts\activate  # Windows
```

### Option 3: Install from pyproject.toml

```bash
# Navigate to project
cd Stage2-Python-Unified

# Install all dependencies from pyproject.toml
uv pip install -e ".[dev]"

# Or just production dependencies
uv pip install -e .
```

---

## Usage

### Basic Monitoring

```bash
# Standard display mode (with colors)
system-monitor

# JSON output
system-monitor --format json

# Export to file
system-monitor --export ./report.json

# Watch mode (continuous monitoring)
system-monitor --watch --interval 5

# Custom thresholds
system-monitor --cpu-threshold 70 --mem-threshold 80
```

### Process Kill/Restart

```bash
# Kill by PID
system-monitor kill 1234

# Kill by name
system-monitor kill firefox

# Force kill
system-monitor kill 1234 --force

# Restart process
system-monitor restart nginx

# Restart with custom command
system-monitor restart nginx --command "nginx -c /etc/nginx.conf"

# View kill log
system-monitor kill-log
```

---

## Development Workflow

### Running Tests

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov

# Run specific test file
uv run pytest tests/test_models.py

# Run with verbose output
uv run pytest -v
```

### Code Quality

```bash
# Format with black
uv run black src/ tests/

# Lint with ruff
uv run ruff check src/ tests/

# Type check with mypy
uv run mypy src/system_monitor/

# Run all checks
uv run black --check src/ tests/ && uv run ruff check src/ tests/ && uv run mypy src/system_monitor/
```

### Building and Distribution

```bash
# Build wheel
uv pip install build
uv run python -m build

# The built package will be in dist/
ls dist/
# system_monitor-2.0.0-py3-none-any.whl
# system-monitor-2.0.0.tar.gz
```

---

## Project Structure

```
Stage2-Python-Unified/
├── pyproject.toml           # Project configuration with UV/pip
├── README.md                # This file
├── src/
│   └── system_monitor/
│       ├── __init__.py      # Package initialization
│       ├── models.py        # Data classes with type hints
│       ├── monitor.py       # Core monitoring logic (psutil)
│       ├── exporters.py     # JSON, CSV, Display exporters
│       └── cli.py           # Click CLI commands
├── tests/
│   ├── __init__.py
│   ├── test_models.py       # Model tests
│   ├── test_monitor.py      # Monitor tests
│   ├── test_exporters.py    # Exporter tests
│── └── test_cli.py          # CLI tests

```

---

## Type Hints

This project uses comprehensive type hints:

```python
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime

def get_cpu_usage(self) -> Optional[float]:
    """Get current CPU usage percentage."""
    ...

def kill_process(self, pid: int, force: bool = False) -> Tuple[bool, str]:
    """Kill a process by PID.
    
    Returns:
        Tuple of (success, message)
    """
    ...
```

Run type checking:
```bash
uv run mypy src/system_monitor/
```

---

## UV Command Reference

| Task | UV Command |
|------|------------|
| Run script | `uv run --with <pkg> script.py` |
| Install package | `uv pip install <package>` |
| Install dev deps | `uv pip install -e ".[dev]"` |
| Create venv | `uv venv` |
| Activate venv | `source .venv/bin/activate` |
| Run tests | `uv run pytest` |
| Format code | `uv run black src/` |
| Type check | `uv run mypy src/` |
| Build package | `uv run python -m build` |

---

## Migration from Stage 1

| Stage 1 (Bash/PowerShell) | Stage 2 (Python) |
|---------------------------|------------------|
| `./system_monitor.sh` | `system-monitor` |
| `./system_monitor.ps1 -Kill 1234` | `system-monitor kill 1234` |
| `--export ./report.json` | `--export ./report.json` |
| `--watch 5` | `--watch --interval 5` |

---

## License

MIT License - See main project for details.

---

**Version**: 2.0.0  
**Python**: 3.9+  
**Package Manager**: UV (recommended) / pip  
**Maintainer**: DevOps Capstone Project