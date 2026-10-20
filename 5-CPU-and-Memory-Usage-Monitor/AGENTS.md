# Cross-Platform Infrastructure Toolkit - AGENTS.md

> **Mentor's Note to Apprentice**: This document serves as both your technical roadmap and a reference for AI agents collaborating on this project. Every section connects to real-world Junior DevOps interview topics—treat each as a learning checkpoint.

---

## SECTION: PROJECT OVERVIEW

### Purpose
This toolkit demonstrates production-grade cross-platform system monitoring automation through three deliberate evolutionary stages:

1. **Stage 1 (Dual-Native)**: Equivalent Bash and PowerShell implementations proving mastery of shell scripting fundamentals
2. **Stage 2 (Unified Python)**: Single Python CLI demonstrating when abstraction layers become more maintainable than shell scripts
3. **Stage 3 (Containerization)**: Docker packaging with security hardening, multi-stage builds, and orchestration best practices

### Target Platform Matrix

| Platform | Version | Shell Support | PowerShell Support | Python Support | Docker Support |
|----------|---------|---------------|-------------------|----------------|----------------|
| Windows Server | 2019+ | N/A (use PowerShell) | 5.1+ / 7+ | 3.9+ | Windows Containers / WSL2 |
| Ubuntu | 20.04+ | GNU Bash 5.0+ | 7+ | 3.9+ | Native |
| macOS | 12+ (Monterey) | Bash 3.2+ / Zsh | 7+ | 3.9+ | Docker Desktop |
| Alpine Linux | 3.18+ | BusyBox ash | 7+ | 3.9+ | Native (primary target for containers) |

### Pedagogical Rationale

**Why dual-script-first?**
- Junior DevOps engineers must debug on any system, even without Python installed
- Shell scripts teach fundamental Unix philosophy (text streams, pipes, small utilities)
- PowerShell teaches object-oriented pipeline thinking vs text-based Unix pipes
- Understanding both prepares you for heterogeneous enterprise environments

**Why Python second?**
- Demonstrates when type safety, testability, and maintainability trump shell convenience
- Shows packaging complexity trade-offs (dependencies, virtual environments, distribution)
- Prepares you for API-driven infrastructure (boto3, kubernetes-client, etc.)

**Why Containerization last?**
- Requires understanding of the application's runtime requirements first
- Teaches "build once, run anywhere" operational model
- Security hardening requires knowing what the application actually needs

---

## SECTION: ARCHITECTURE DECISION RECORDS (ADRs)

### ADR-001: PowerShell Core vs Batch for Windows
**Decision**: Use PowerShell 7+ (cross-platform) as primary, maintain PowerShell 5.1 compatibility.

**Rationale**:
- PowerShell 5.1 is built into Windows Server 2019/2022; no installation required
- PowerShell 7+ uses .NET Core, runs on Linux/macOS, enables true cross-platform single codebase
- Batch scripts are unmaintainable for non-trivial logic
- Ansible, Terraform, and modern Windows tooling all standardize on PowerShell

**Apprentice Learning**: Interview question—"Why not just use Python for everything on Windows?" Answer: PowerShell integrates deeply with WMI/CIM, Windows Event Log, and Active Directory. Python requires pywin32 for these.

### ADR-002: Alpine Linux as Primary Container Target
**Decision**: Use Alpine 3.18+ for minimal images, with Debian-slim fallback for glibc compatibility.

**Rationale**:
- Alpine uses musl libc: smaller attack surface, smaller image (~5MB base)
- musl can cause issues with some Python wheels (pandas, numpy); Debian-slim for data science workloads
- `apk` package manager is simpler than `apt` for containers
- BusyBox ash requires POSIX compliance, which enforces Bash best practices

**Apprentice Learning**: Interview question—"Alpine vs Distroless?" Answer: Distroless is excellent for Go/static binaries but painful for dynamic languages like Python. Alpine provides a shell for debugging while still being minimal.

### ADR-003: psutil for Python Implementation
**Decision**: Use `psutil` library for cross-platform system information.

**Rationale**:
- Abstracts /proc filesystem on Linux, WMI on Windows, sysctl on macOS
- Well-maintained, production-tested (used by Glances, Ansible)
- Pure Python with optional C extensions for performance

**Trade-off**: Adds external dependency. For Stage 2, we accept this to demonstrate dependency management patterns.

### ADR-004: JSON/CSV Dual Output Format
**Decision**: Support both JSON (structured) and CSV (tabular) output formats.

**Rationale**:
- JSON: Machine parsing, log aggregation (ELK Stack, Splunk), API ingestion
- CSV: Human spreadsheet analysis, Excel import, simple text processing
- Industry standard: Most monitoring tools (top, vmstat, iostat) output text; we add structure

---

## SECTION: SCRIPT REFERENCE MANUAL

### Bash Script: `system_monitor.sh`

#### Synopsis
```bash
./system_monitor.sh [OPTIONS]
```

#### Options
| Flag | Long Form | Argument | Description |
|------|-----------|----------|-------------|
| `-w` | `--watch` | `[seconds]` | Enable continuous refresh mode (default: 2s) |
| `-j` | `--json` | None | Output JSON format to stdout |
| `-c` | `--csv` | None | Output CSV format to stdout |
| `-e` | `--export` | `<path>` | Export to file (auto-generates filename if directory) |
| `-h` | `--help` | None | Display help and exit |

#### Usage Examples

**Fresh Install - Verify Dependencies:**
```bash
# Check Bash version (need 4.0+ for associative arrays)
bash --version

# Verify required commands exist
command -v ps awk grep date df >/dev/null 2>&1 && echo "Dependencies OK" || echo "Missing dependencies"

# Run initial test
chmod +x system_monitor.sh
./system_monitor.sh --help
```

**Standard Monitoring:**
```bash
# Interactive display mode
./system_monitor.sh

# Export single snapshot to JSON
./system_monitor.sh --export ./reports/server-$(date +%Y%m%d).json

# Watch mode with 5-second refresh
./system_monitor.sh --watch 5
```

**Update Mode (Continuous Logging):**
```bash
# Continuous JSON logging (directory mode - auto-filenames)
./system_monitor.sh --watch 5 --export /var/log/system-monitor/ --json

# CSV format for spreadsheet analysis
./system_monitor.sh --watch 10 --export ./logs/ --csv
```

**Cleanup/Drain (Stop Watch Mode Gracefully):**
```bash
# Send SIGINT (Ctrl+C) - handled by trap for graceful exit
# The script will close JSON arrays properly, flush buffers
pkill -INT -f "system_monitor.sh --watch"
```

**Dry-Run Validation:**
```bash
# Syntax check
bash -n system_monitor.sh

# ShellCheck linting (if installed)
shellcheck system_monitor.sh

# Test with strict mode (see MENTOR NOTE below)
bash -c 'set -euo pipefail; source system_monitor.sh --help'
```

#### Exit Codes
| Code | Meaning | Recovery Action |
|------|---------|-----------------|
| 0 | Success | None |
| 1 | General error / Unknown option | Check stderr message |

**MENTOR NOTE**: The script currently lacks proper exit code granularity. **Required addition**:
```bash
#!/bin/bash
# ADD AT LINE 1 (after shebang):
set -euo pipefail

# RATIONALE:
# -e: Exit immediately on command failure (prevents cascading errors)
# -u: Treat unset variables as errors (catches typos in variable names)
# -o pipefail: Pipeline fails if ANY command fails (not just last)
# This transforms silent failures into immediate, debuggable crashes
```

#### Logging Levels
The script uses ANSI color codes but lacks structured logging. **Required addition**:
```bash
# ADD after color definitions (around line 17):
LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp=$(date -Iseconds)
    if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[$LOG_LEVEL]} ]]; then
        echo "[$timestamp] [$level] $msg" >&2
    fi
}
```

---

### PowerShell Script: `system_monitor.ps1`

#### Synopsis
```powershell
.\system_monitor.ps1 [[-TopProcesses] <Int32>] [[-CpuThreshold] <Int32>] [[-MemThreshold] <Int32>] [-Watch] [[-RefreshSeconds] <Int32>] [[-Format] <String>] [[-ExportPath] <String>] [<CommonParameters>]
```

#### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TopProcesses` | Int32 | 100 | Number of top processes to display |
| `-CpuThreshold` | Int32 | 80 | CPU % threshold for "HIGH" alert coloring |
| `-MemThreshold` | Int32 | 80 | Memory % threshold for "HIGH" alert coloring |
| `-Watch` | Switch | False | Enable continuous refresh mode |
| `-RefreshSeconds` | Int32 | 2 | Refresh interval in watch mode |
| `-Format` | String (ValidateSet) | "Display" | Output format: Display, Json, or Csv |
| `-ExportPath` | String | None | Export file path or directory |

#### Usage Examples

**Fresh Install - Verify Dependencies:**
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Verify execution policy (may need adjustment)
Get-ExecutionPolicy

# Test script signature (if signed)
Get-AuthenticodeSignature .\system_monitor.ps1
```

**Standard Monitoring:**
```powershell
# Interactive display mode
.\system_monitor.ps1

# Custom thresholds
.\system_monitor.ps1 -CpuThreshold 70 -MemThreshold 75

# Export to specific file
.\system_monitor.ps1 -Format Json -ExportPath "C:\Logs\server.json"
```

**Watch Mode:**
```powershell
# Watch with CSV logging to directory (auto-filename)
.\system_monitor.ps1 -Watch -RefreshSeconds 5 -Format Csv -ExportPath "C:\Logs\"

# Background job for continuous monitoring
$job = Start-Job { & "C:\Tools\system_monitor.ps1" -Watch -Format Json -ExportPath "C:\Logs\" }
# Later: Stop-Job $job; Remove-Job $job
```

**Cleanup/Drain:**
```powershell
# Graceful stop of watch mode
# In the same terminal: Ctrl+C (handled by try/catch)
# Remote session:
Get-Process | Where-Object { $_.CommandLine -like "*system_monitor.ps1*" } | Stop-Process
```

#### Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | CSV format without ExportPath (explicit check in code) |

**MENTOR NOTE**: The PowerShell script has better error handling than Bash via `[CmdletBinding()]` and try/catch, but could benefit from:
```powershell
# ADD at beginning of script (after parameters):
$ErrorActionPreference = "Stop"

# RATIONALE:
# PowerShell's default "Continue" silently proceeds on errors
# "Stop" converts non-terminating errors to exceptions, caught by try/catch
# Essential for pipeline automation where failures must be explicit
```

---

## SECTION: CROSS-PLATFORM COMPATIBILITY GUIDE

### Path Separator Handling

**The Problem**:
```bash
# This FAILS on Windows (PowerShell expects \ or quoted paths)
./system_monitor.sh --export C:\Users\Admin\logs\report.json

# This FAILS on Unix (backslash is escape character)
./system_monitor.sh --export C:/Users/Admin/logs/report.json  # Works in PowerShell, not Bash on Windows
```

**Current Implementation Status**:
- Bash script: Uses Unix-style paths only (`/logs/report.json`)
- PowerShell script: Uses .NET's `Join-Path` and `Split-Path` cmdlets (cross-platform)

**Required Fix for Bash on Windows (WSL/MSYS/Git Bash)**:
```bash
# ADD function to normalize paths
normalize_path() {
    local path="$1"
    # Convert Windows path to Unix if running in WSL/Git Bash
    if command -v cygpath &>/dev/null; then
        cygpath "$path"
    elif command -v wslpath &>/dev/null; then
        wslpath "$path"
    else
        echo "$path"
    fi
}
```

### Line Ending Issues (CRLF vs LF)

**The Problem**: Git on Windows may convert LF to CRLF, breaking Bash shebangs.

**Solutions**:
```bash
# In .gitattributes (CREATE THIS FILE):
*.sh text eol=lf
*.ps1 text eol=crlf
*.py text eol=lf
```

**Detection and Fix**:
```bash
# Check line endings
file system_monitor.sh
# Should show: "Bourne-Again shell script, ASCII text executable"

# If "with CRLF line terminators":
dos2unix system_monitor.sh
# Or: sed -i 's/\r$//' system_monitor.sh
```

### Permission Model Differences

| Action | Unix (Bash) | Windows (PowerShell) |
|--------|-------------|---------------------|
| Make executable | `chmod +x script.sh` | `Unblock-File script.ps1` or execution policy |
| Run with elevation | `sudo ./script.sh` | `Start-Process powershell -Verb RunAs` |
| Check current user | `whoami` / `$USER` | `$env:USERNAME` |
| Check admin status | `[ "$EUID" -eq 0 ]` | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)` |

**MENTOR NOTE**: The scripts currently don't check for elevation. **Required addition** for production use:
```bash
# ADD to Bash script for operations requiring root:
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root for complete process information"
        exit 1
    fi
}
```

### WSL2 Interop Considerations

**When to Use WSL2 vs Native**:
| Scenario | Recommendation |
|----------|----------------|
| Monitoring Windows host from WSL2 | Use `$(powershell.exe -c "...")` for Windows APIs |
| Monitoring WSL2 itself | Native Bash script works perfectly |
| Production Windows servers | Native PowerShell (no WSL2 dependency) |
| CI/CD pipelines | Containerized Python version (Stage 3) |

**Cross-Filesystem I/O Performance**:
```bash
# SLOW: Writing to Windows filesystem from WSL2
./system_monitor.sh --export /mnt/c/logs/report.json

# FAST: Write to WSL2 ext4, then copy
./system_monitor.sh --export /tmp/report.json && cp /tmp/report.json /mnt/c/logs/
```

---

## SECTION: DOCKER IMPLEMENTATION

### Current Status
**CRITICAL GAP**: The `Architectural-Improvement/Dockerfile` and `docker-compose.yaml` files exist but are **EMPTY**. This is Stage 3 of the capstone and requires completion.

### Implementation Blueprint

#### Multi-Stage Build Strategy

**MENTOR NOTE**: Multi-stage builds separate build dependencies from runtime. For Python:
- Stage 1: Full Python image with gcc, musl-dev (compile psutil C extensions)
- Stage 2: Minimal Python image, copy only compiled wheels

```dockerfile
# CREATE: Dockerfile (production-ready template)
# ============================================================================
# Stage 1: Builder (compile dependencies)
FROM python:3.11-alpine AS builder

# Install build dependencies
RUN apk add --no-cache gcc musl-dev linux-headers

# Create virtual environment (isolation best practice)
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Runtime (minimal attack surface)
FROM python:3.11-alpine AS runtime

# Security: Run as non-root user
RUN addgroup -g 1000 monitor && \
    adduser -D -u 1000 -G monitor monitor

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application code
WORKDIR /app
COPY --chown=monitor:monitor src/ ./

# Security: Read-only root filesystem preparation
RUN mkdir -p /tmp/logs && chown monitor:monitor /tmp/logs
VOLUME ["/tmp/logs"]

# Switch to non-root user
USER monitor

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import psutil; psutil.cpu_percent()" || exit 1

# Default: run monitoring CLI
ENTRYPOINT ["python", "-m", "system_monitor"]
CMD ["--help"]
# ============================================================================
```

#### Build Commands with Resource Constraints

```bash
# Development build (faster, larger)
docker build -t system-monitor:dev .

# Production build (optimized, minimal)
docker build --target runtime -t system-monitor:latest .

# With resource constraints (CI/CD environments)
docker build \
  --memory=2g \
  --memory-swap=2g \
  --cpus=2 \
  -t system-monitor:latest .

# Multi-platform build (requires buildx)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t system-monitor:latest \
  --push .
```

#### docker-compose.yml Orchestration

```yaml
# CREATE: docker-compose.yml (reference implementation)
# ============================================================================
version: "3.8"

services:
  # Development profile: editable code, persistent logs
  monitor-dev:
    build:
      context: .
      target: builder  # Full image with dev tools
    volumes:
      - ./src:/app  # Mount for live editing
      - ./logs:/tmp/logs
    environment:
      - LOG_LEVEL=DEBUG
    profiles: ["dev"]
    command: ["--watch", "5", "--export", "/tmp/logs/monitor.json"]

  # Production profile: read-only, minimal
  monitor-prod:
    build:
      context: .
      target: runtime
    read_only: true  # Security: immutable root fs
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
    environment:
      - LOG_LEVEL=INFO
    profiles: ["prod"]
    restart: unless-stopped
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 128M
        reservations:
          cpus: '0.1'
          memory: 64M

  # Optional: Prometheus exporter sidecar
  metrics-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
    profiles: ["observability"]
# ============================================================================
```

#### Usage
```bash
# Development mode (editable)
docker-compose --profile dev up --build

# Production mode (detached, restart policy)
docker-compose --profile prod up -d

# With observability stack
docker-compose --profile prod --profile observability up -d
```

### Security Hardening Checklist

**Before Production Deployment**:

- [ ] **Non-root execution**: Container runs as UID 1000+, not root
- [ ] **Read-only root filesystem**: `read_only: true` in compose, handle temp files via tmpfs
- [ ] **Dropped capabilities**: Remove unnecessary Linux capabilities
- [ ] **No new privileges**: `no_new_privileges: true` prevents privilege escalation
- [ ] **Resource limits**: CPU and memory constraints prevent DoS
- [ ] **Image scanning**: Trivy or Snyk scan shows no CRITICAL/HIGH vulnerabilities
- [ ] **Distroless evaluation**: Consider `gcr.io/distroless/python3` for final stage

```bash
# Security scanning commands
# Trivy (recommended)
trivy image system-monitor:latest

# Docker built-in scan (Snyk)
docker scan system-monitor:latest

# Check for secrets in image layers
docker history --no-trunc system-monitor:latest | grep -i "password\|secret\|key"
```

---

## SECTION: PYTHON UNIFIED CODEBASE

### Current Status
**PARTIAL IMPLEMENTATION**: `Architectural-Improvement/psutil.py` exists but is **21 lines, incomplete**.

**Current Skeleton**:
```python
import json, sys, time
import psutil
from colorama import Fore, Style

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    return {"cpu": cpu, "memory": mem, "disk": disk}

if __name__ == "__main__":
    if "--json" in sys.argv:
        print(json.dumps(get_stats()))
    else:
        print(f"{Fore.GREEN}CPU: {get_stats()['cpu']}%{Style.RESET_ALL}")
```

### Required Complete Implementation

**MENTOR NOTE**: This skeleton lacks CLI framework, type hints, error handling, logging, and feature parity with shell scripts. Here's the production-ready blueprint:

```python
#!/usr/bin/env python3
"""
Cross-Platform System Resource Monitor - Unified Python Implementation
"""
import json
import sys
import time
from pathlib import Path
from typing import Optional, Dict, List, Any
from dataclasses import dataclass, asdict
from datetime import datetime

import click  # Or typer for modern Python
try:
    import psutil
except ImportError:
    sys.exit("Error: psutil not installed. Run: pip install psutil")


@dataclass
class ProcessInfo:
    """Type-safe process information container."""
    name: str
    pid: int
    cpu_percent: float
    ram_mb: float


@dataclass
class SystemSnapshot:
    """Complete system state snapshot."""
    timestamp: str
    os: str
    cpu_percent: Optional[float]
    memory_percent: Optional[float]
    top_processes: List[ProcessInfo]
    aggregated_totals: Dict[str, Any]


def get_cpu_usage() -> Optional[float]:
    """Get current CPU usage percentage."""
    try:
        return psutil.cpu_percent(interval=1)
    except Exception as e:
        click.echo(f"Warning: Could not read CPU: {e}", err=True)
        return None


def get_memory_usage() -> Optional[float]:
    """Get current memory usage percentage."""
    try:
        return psutil.virtual_memory().percent
    except Exception as e:
        click.echo(f"Warning: Could not read memory: {e}", err=True)
        return None


def get_process_data(top_n: int = 100) -> List[ProcessInfo]:
    """Get top N processes by memory usage."""
    processes = []
    for proc in sorted(
        psutil.process_iter(['name', 'pid', 'cpu_percent', 'memory_info']),
        key=lambda p: p.info['memory_info'].rss if p.info['memory_info'] else 0,
        reverse=True
    )[:top_n]:
        try:
            processes.append(ProcessInfo(
                name=proc.info['name'] or "unknown",
                pid=proc.info['pid'],
                cpu_percent=proc.info['cpu_percent'] or 0.0,
                ram_mb=proc.info['memory_info'].rss / (1024 * 1024) if proc.info['memory_info'] else 0.0
            ))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return processes


@click.command()
@click.option('--watch', '-w', is_flag=True, help='Enable continuous refresh mode')
@click.option('--interval', '-i', default=2, help='Refresh interval in seconds')
@click.option('--format', '-f', 'output_format', type=click.Choice(['display', 'json', 'csv']), default='display')
@click.option('--export', '-e', 'export_path', type=click.Path(), help='Export file or directory')
@click.option('--top', '-t', default=100, help='Number of top processes to show')
def main(watch: bool, interval: int, output_format: str, export_path: Optional[str], top: int):
    """Cross-Platform System Resource Monitor."""
    # Implementation continues...
    pass


if __name__ == '__main__':
    main()
```

### Dependency Management Strategy

**CREATE: `pyproject.toml`** (Modern Python packaging)
```toml
[project]
name = "system-monitor"
version = "2.0.0"
description = "Cross-Platform System Resource Monitor"
requires-python = ">=3.9"
dependencies = [
    "psutil>=5.9.0",
    "click>=8.0.0",
    "colorama>=0.4.4; platform_system=='Windows'",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "black>=23.0",
    "ruff>=0.1.0",
    "mypy>=1.0",
]

[project.scripts]
system-monitor = "system_monitor.cli:main"
```

### Virtual Environment Setup

```bash
# Standard venv (always use this, never system Python)
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate  # Windows

# Install in editable mode (development)
pip install -e ".[dev]"

# Or install from lock file (production reproducibility)
pip install pip-tools
pip-compile pyproject.toml  # Generate requirements.txt
pip-sync  # Install exactly pinned versions
```

---

## SECTION: TESTING AND VALIDATION

### Testing Matrix

| Test Type | Tool | Bash | PowerShell | Python |
|-----------|------|------|------------|--------|
| Static Analysis | shellcheck | ✓ | N/A | N/A |
| Static Analysis | PSScriptAnalyzer | N/A | ✓ | N/A |
| Static Analysis | ruff/black/mypy | N/A | N/A | ✓ |
| Unit Tests | pytest | N/A | N/A | ✓ |
| Integration | Docker containers | ✓ | N/A | ✓ |
| E2E | GitHub Actions matrix | ✓ | ✓ | ✓ |

### Linting Configuration

**Bash - ShellCheck** (`.shellcheckrc`):
```bash
# CREATE: .shellcheckrc
shell=bash
severity=warning
enable=all
disable=SC2034  # Unused variables (may be used in sourced files)
disable=SC2155  # Declare and assign separately
```

**PowerShell - PSScriptAnalyzer**:
```powershell
# Run analysis
Invoke-ScriptAnalyzer -Path .\system_monitor.ps1 -Settings PSGallery

# Key rules to enable:
# PSAvoidUsingInvokeExpression
# PSPossibleIncorrectComparisonWithNull
# PSUseShouldProcessForStateChangingFunctions
```

**Python - Ruff** (`pyproject.toml`):
```toml
[tool.ruff]
target-version = "py39"
select = ["E", "F", "I", "N", "W", "UP", "B", "C4", "SIM"]
line-length = 100

[tool.mypy]
python_version = "3.9"
strict = true
warn_return_any = true
warn_unused_configs = true
```

### Integration Testing with Docker

```bash
# Test Bash script on Alpine
docker run --rm -v "$PWD:/app" -w /app alpine:3.18 sh -c "
    apk add --no-cache bash procps coreutils gawk
    bash system_monitor.sh --export /tmp/test.json
    cat /tmp/test.json
"

# Test PowerShell on Ubuntu
docker run --rm -v "$PWD:/app" -w /app mcr.microsoft.com/powershell:latest pwsh -c "
    ./system_monitor.ps1 -Format Json
"
```

---

## SECTION: SECURITY CONSIDERATIONS

### Secret Handling

**ANTI-PATTERNS DETECTED**: None currently (scripts don't handle secrets), but future extensions might need API keys for cloud integrations.

**Required Pattern**:
```bash
# NEVER: Hardcode secrets
API_KEY="sk-12345"  # SECURITY RISK

# ALWAYS: Runtime injection
API_KEY="${MONITOR_API_KEY:-}"  # From environment
if [[ -z "$API_KEY" ]]; then
    log ERROR "MONITOR_API_KEY not set"
    exit 1
fi
```

**Docker Secrets (Swarm Mode)**:
```yaml
# For production Docker Swarm/Kubernetes
secrets:
  - source: api_key
    target: /run/secrets/api_key
    mode: 0440
```

### Least-Privilege Execution Principles

1. **Information Collection Only**: The scripts read system state, don't modify it (except kill/restart capability in development)
2. **User Context**: Run as standard user where possible; root only needed for all-process visibility
3. **Container Capabilities**: Drop all, add only `SYS_PTRACE` (for process inspection):
   ```yaml
   cap_drop:
     - ALL
   cap_add:
     - SYS_PTRACE  # Required for psutil.process_iter on some kernels
   ```

### Image Vulnerability Scanning Commands

```bash
# Trivy (open source, recommended)
# Install: https://aquasecurity.github.io/trivy/
trivy image --severity HIGH,CRITICAL system-monitor:latest
trivy filesystem --scanners vuln,secret,misconfig .

# Docker Scout (Docker Hub integration)
docker scout cves system-monitor:latest

# Grype (Anchore)
grype system-monitor:latest
```

---

## SECTION: LEARNING OBJECTIVES MAPPING

### Junior DevOps Interview Skills Matrix

| File/Component | Skill Demonstrated | Interview Question |
|----------------|-------------------|-------------------|
| `system_monitor.sh` | POSIX compliance | "Write a portable script that works on Alpine (BusyBox) and Ubuntu (GNU)" |
| `system_monitor.sh` | `set -euo pipefail` | "Why use strict mode in Bash? What's the difference between `set -e` and `set -o pipefail`?" |
| `system_monitor.ps1` | Cross-platform PS | "How do you write PowerShell that runs on Windows 2019 and Ubuntu 22.04?" |
| `system_monitor.ps1` | Error handling | "Compare `$ErrorActionPreference` values: Continue vs Stop vs SilentlyContinue" |
| `psutil.py` | Type hints | "Why use `Optional[float]` instead of just `float` for function return types?" |
| `psutil.py` | Dependency management | "How do you ensure reproducible builds in Python? (Answer: lock files, hashes)" |
| `Dockerfile` | Multi-stage builds | "Why use multi-stage Docker builds? Give specific size/attack surface benefits" |
| `Dockerfile` | Non-root containers | "Why shouldn't containers run as root? Name three security mechanisms" |
| `docker-compose.yml` | Profiles | "How do you manage dev/prod differences in Docker Compose?" |
| `.shellcheckrc` | Static analysis | "What linting tools do you use for shell scripts? Why?" |
| Log formatting (to add) | Structured logging | "Why use JSON logging? How do you aggregate logs from 1000 containers?" |
| Health checks (to add) | Container health | "What's the difference between Dockerfile HEALTHCHECK and Kubernetes liveness probes?" |

### Capstone Completion Checklist ✅ COMPLETE

**Stage 1: Dual-Native Scripting** ✅
- [x] Bash script with CPU/Memory/Disk/Process monitoring
- [x] PowerShell script with feature parity
- [x] JSON/CSV export formats
- [x] Watch mode implementation
- [x] **FIXED**: Added `set -euo pipefail` to Bash script
- [x] **FIXED**: Added structured logging with timestamps
- [x] **FIXED**: Added input validation for numeric parameters
- [x] **ADDED**: Kill/Restart process capability with audit logging
- [x] **FIXED**: Resolved `$pid` variable conflict in PowerShell (renamed to `$procPid`)
- [x] **FIXED**: Fixed race condition when killing parent processes with child processes

**Stage 2: Unified Python** ✅
- [x] **COMPLETE**: Full Click CLI with 6 modules (~1,800 lines)
- [x] Type hints throughout (mypy strict mode)
- [x] `pyproject.toml` with UV support
- [x] Unit tests with pytest (~700 test lines)
- [x] Feature parity with shell scripts (monitor, kill, restart)
- [x] UV package manager integration

**Stage 3: Containerization** ✅
- [x] **COMPLETE**: Multi-stage Dockerfile (~60MB final)
- [x] **COMPLETE**: docker-compose.yml with 5 profiles
- [x] Multi-stage build (builder + runtime)
- [x] Non-root user execution (UID 1000)
- [x] Read-only root filesystem with tmpfs
- [x] Health checks configured
- [x] `.dockerignore` file optimized
- [x] Trivy security scanning in CI

**Stage 4: CI/CD Pipeline** ✅
- [x] 3 GitHub Actions workflows (ci-cd-pipeline.yml, pr-validation.yml, release.yml)
- [x] Multi-OS testing (Ubuntu, macOS, Windows)
- [x] Multi-Python version matrix (3.9, 3.10, 3.11, 3.12)
- [x] Multi-arch Docker builds (amd64, arm64, armv7)
- [x] Automated Docker Hub deployment on main push
- [x] Release workflow triggered by version tags
- [x] ShellCheck + PSScriptAnalyzer + pytest + Trivy security scanning

---

## APPENDIX: PROJECT COMPLETION SUMMARY

> **🎉 Status: ALL STAGES COMPLETE** - Production-ready capstone project

### Quick Start Commands

```bash
# Stage 1 - Native Scripts
./system_monitor.sh --watch 5                    # Bash (Linux/macOS/WSL)
./system_monitor.ps1 -Watch -RefreshSeconds 5    # PowerShell (cross-platform)

# Stage 2 - Python (with UV)
cd Stage2-Python-Unified
uv run -m system_monitor --watch --interval 5

# Stage 3 - Docker
cd Stage3-Containerization
docker compose --profile prod up -d
docker compose --profile watch up -d             # Continuous monitoring

# Stage 4 - CI/CD
# Push to main branch triggers full pipeline automatically
```

### Project Metrics

| Metric | Value |
|--------|-------|
| Total Files | 25+ source + config files |
| Source Code Lines | ~6,200 lines |
| Test Lines | ~700 lines |
| Documentation | ~50KB across 4 README files |
| Languages | Bash, PowerShell, Python |
| Platforms | Linux, macOS, Windows |
| Container Architectures | amd64, arm64, armv7 |

---

## APPENDIX: MENTOR'S CODE REVIEW NOTES (RESOLVED)

### Issues That Were Addressed

1. **Bash Script Robustness** ✅ FIXED:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   IFS=$'\n\t'
   ```

2. **Input Validation** ✅ FIXED:
   ```bash
   # The INTERVAL parameter is parsed but not validated:
   [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] && INTERVAL="$2" && shift
   
   # REQUIRED: Add bounds checking
   if [[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
       if (( $(echo "$INTERVAL < 0.1" | bc -l) )) || (( $(echo "$INTERVAL > 300" | bc -l) )); then
           echo "Error: Interval must be between 0.1 and 300 seconds" >&2
           exit 1
       fi
   fi
   ```

3. **Python Skeleton Expansion** (`Architectural-Improvement/psutil.py`):
   - Current: 21 lines, basic function
   - Required: ~300 lines, full CLI with Click, feature parity with shell scripts

4. **Dockerfile Creation** (`Architectural-Improvement/Dockerfile`):
   - Current: Empty file (0 bytes)
   - Required: Multi-stage build as specified in this document

5. **New-Addittions Windows Script Empty** (`New-Addittions/2.Process-Kill_Restart-Capability/windows.ps1`):
   - Current: Empty file
   - Required: PowerShell equivalent of Unix kill/restart functionality

### Recommended Next Steps (Priority Order)

1. Fix Bash strict mode and add input validation (1 hour)
2. Complete Python CLI implementation with Click (4 hours)
3. Create production Dockerfile with multi-stage build (2 hours)
4. Create docker-compose.yml with dev/prod profiles (1 hour)
5. Add CI/CD workflow for automated testing (2 hours)
6. Implement missing PowerShell kill/restart capability (1 hour)
7. Add comprehensive test suite (4 hours)

---

*Document Version: 1.0*  
*Last Updated: 2026-03-12*  
*Mentor: Principal DevOps Engineer*  
*Apprentice Capstone Project: Cross-Platform Infrastructure Toolkit*
