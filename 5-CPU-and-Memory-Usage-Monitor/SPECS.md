# SPECS — CPU and Memory Usage Monitor

> Technical specification and architecture for module 5 of the
> [Scripts-DevOps-Practice](../../README.md) monorepo.

---

## 1. Purpose

A cross-platform system resource monitor that reports CPU, memory, disk and
process usage, and can kill or restart a process by PID or name.

The module ships three implementations of the same tool:

| Stage | Implementation | Runtime |
| :--- | :--- | :--- |
| 1 | Native scripts | Bash 4+ / PowerShell 5.1+ |
| 2 | Unified package | Python 3.9+ |
| 3 | Container image | Alpine 3.18+ |

Stage 4 is the CI pipeline, which lives at the repository root rather than
inside the module.

---

## 2. Architecture

```
5-CPU-and-Memory-Usage-Monitor/
├── README.md                      # usage, flags, scheduling, troubleshooting
├── SPECS.md                       # this document
├── ROADMAP.md                     # phased milestones
├── CODESTYLE.md                   # module conventions
├── AGENTS.md                      # design decisions and the mentor's notes
├── tests/                         # Stage 1 suites (Bash and PowerShell)
│   ├── test_system_monitor.sh
│   └── test_system_monitor.ps1
├── docs/                          # ARCHITECTURE_COMPARISON, SCENARIOS, labs
├── Stage1-Native-Scripts/         # system_monitor.sh, system_monitor.ps1
├── Stage2-Python-Unified/         # src/system_monitor, tests, pyproject.toml
├── Stage3-Containerization/       # the same package plus Dockerfile and compose
└── Stage4-CI-CD-Pipeline/         # documentation of the root workflow
```

Stage 2 and Stage 3 each carry their own copy of the `system_monitor`
package. They are kept byte-identical on purpose: the Stage 3 Dockerfile
installs the package from **its own** `src/` tree, so both are linted and
tested independently.

### Module boundaries

Each stage is self-contained. No stage imports code from another; the
Stage 2 and Stage 3 packages are copies rather than shared code, so either
stage can be lifted out on its own.

---

## 3. Data collection

| Metric | Source | Notes |
| :--- | :--- | :--- |
| CPU usage | `/proc/stat` on Linux, `top` elsewhere | Falls back to `N/A` when unavailable |
| Memory usage | `free`, then `/proc/meminfo` on Linux; `vm_stat` on macOS | Percentage of total |
| Disk usage | `df` and `Get-PSDrive` | One entry per mounted filesystem |
| Disk I/O | `/proc/diskstats` and Windows performance counters | See §7 |
| Processes | `ps` and `Get-Process` | Sorted by resident memory |

### Locale independence

Both native scripts pin their locale so the output never depends on the
host:

* Bash sets `export LC_ALL=C`.
* PowerShell sets `CurrentCulture` to `InvariantCulture`.

Without this, a host whose numeric locale uses a comma as the decimal
separator produces values that `printf` rejects, and a successful run
turns into a non-zero exit.

---

## 4. Command-line reference

### 4.1 Stage 1 — Bash

```
system_monitor.sh [OPTIONS]
```

| Flag | Long form | Argument | Description |
| :--- | :--- | :--- | :--- |
| `-w` | `--watch` | `[seconds]` | Continuous refresh, default 2s, range 0.1–300 |
| `-j` | `--json` | — | JSON on stdout |
| `-c` | `--csv` | — | CSV on stdout |
| `-e` | `--export` | `<path>` | Write to a file, or to a directory with a generated name |
| `-k` | `--kill` | `<pid\|name>` | Terminate a process |
| `-s` | `--kill-signal` | `<sig>` | Signal to send: TERM, KILL or HUP |
| `-r` | `--restart` | `<pid\|name>` | Terminate and start again |
| — | `--restart-cmd` | `<cmd>` | Command to run when restarting |
| — | `--kill-log` | — | Show the recent kill and restart actions |
| `-h` | `--help` | — | Usage and exit |
| `-v` | `--version` | — | Version and exit |

### 4.2 Stage 1 — PowerShell

```
.\system_monitor.ps1 [-Watch] [-RefreshSeconds <Int32>] [-Format <String>]
                      [-ExportPath <String>] [-TopProcesses <Int32>]
                      [-CpuThreshold <Int32>] [-MemThreshold <Int32>]
                      [-Kill <String>] [-KillMethod <String>]
                      [-Restart <String>] [-RestartCommand <String>]
                      [-KillLog] [-Version]
```

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Watch` | switch | off | Continuous refresh |
| `RefreshSeconds` | int | 2 | Refresh interval, range 0–300 |
| `Format` | Display, Json, Csv | Display | Output format |
| `ExportPath` | string | none | File or directory to write to |
| `TopProcesses` | int | 100 | Number of processes to report, range 1–1000 |
| `CpuThreshold` | int | 80 | CPU percentage above which usage is flagged HIGH |
| `MemThreshold` | int | 80 | Memory percentage above which usage is flagged HIGH |
| `Kill` | string | none | Process to terminate, by PID or name |
| `KillMethod` | Graceful, Terminate, Kill | Graceful | How to terminate |
| `Restart` | string | none | Process to restart, by PID or name |
| `RestartCommand` | string | none | Command to run when restarting |
| `KillLog` | switch | off | Show the recent kill and restart actions |
| `Version` | switch | off | Print the version and exit |

The three functions that terminate and restart processes support
`-WhatIf` and `-Confirm`.

### 4.3 Stage 2 and 3 — Python

```
system-monitor [OPTIONS] [COMMAND]
```

| Option | Default | Description |
| :--- | :--- | :--- |
| `--watch`, `-w` | off | Continuous refresh |
| `--interval`, `-i` | 2.0 | Refresh interval, range 0.1–300 |
| `--format`, `-f` | display | `display`, `json` or `csv` |
| `--export`, `-e` | none | File or directory to write to |
| `--top`, `-t` | 100 | Number of processes to report, range 1–1000 |
| `--cpu-threshold` | 80.0 | CPU percentage above which usage is flagged HIGH |
| `--mem-threshold` | 80.0 | Memory percentage above which usage is flagged HIGH |
| `--no-color` | off | Disable ANSI colour |

Subcommands: `kill`, `restart`, `kill-log`.

---

## 5. Output contract

All three implementations emit the same JSON key names, so a consumer can
parse any of them.

```json
{
  "timestamp": "2026-10-20T14:02:36.2626960-05:00",
  "os": "Linux",
  "cpu_percent": 10.64,
  "memory_percent": 38.70,
  "disk_usage": [
    {
      "mount_point": "/",
      "total": "672G",
      "used": "324G",
      "free": "347G",
      "percent_used": 49
    }
  ],
  "disk_io": [
    {
      "device": "sda",
      "reads_completed": 84536,
      "writes_completed": 10736,
      "read_sectors": 19081,
      "write_sectors": 637
    }
  ],
  "top_processes": [
    { "name": "python", "pid": 1234, "cpu_percent": 25.0, "ram_mb": 512.0 }
  ],
  "aggregated_totals": [
    { "name": "python", "total_ram_mb": 1024.0, "instances": 1 }
  ]
}
```

The CSV output carries the same eleven columns, in this order:

```
timestamp,os,metric_type,name,pid,cpu_percent,ram_mb,instances,mount_point,device,percent_used
```

The `metric_type` column is one of `system`, `disk_usage`, `process` or
`aggregate`.

---

## 6. Exit codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success |
| 1 | Configuration or safety violation — unknown flag, value out of range, the target process does not exist, the output format needs an export path |
| 2 | Partial failure — reserved by the repository standard, not used by this module yet |

Every destructive action writes an audit line to the kill log, which lives
in the platform temporary directory unless `KILL_LOG_DIR` says otherwise.

---

## 7. Platform differences

These are the known differences between the implementations. They are
deliberate, and they are listed here so a consumer knows what to expect.

| Aspect | Bash | PowerShell | Python |
| :--- | :--- | :--- | :--- |
| Thresholds | Fixed at 80 | `-CpuThreshold`, `-MemThreshold` | `--cpu-threshold`, `--mem-threshold` |
| Top process count | Fixed at 100 | `-TopProcesses` | `--top` |
| Output format | Separate `-j` and `-c` flags | `-Format` | `--format` |
| Kill method | Signal name | Graceful, Terminate, Kill | Graceful, then force |
| Disk I/O fields | Cumulative counters | Per-second rates | Both |
| CSV quoting | Unquoted | Every field quoted | Unquoted |

The disk I/O difference is the one that matters to a consumer: the Bash
script reads cumulative counters from `/proc/diskstats`, while the
PowerShell script reads per-second rates from the Windows performance
counters. The Python implementation reports both families.

---

## 8. Security

* The Bash script runs under `set -euo pipefail` with `IFS` restricted, and
  every external value is validated before it is used.
* The PowerShell script sets `$ErrorActionPreference = "Stop"` and declares
  `[CmdletBinding()]`.
* Every destructive path writes an audit line to the kill log.
* The container image runs as the non-root user `monitor` (UID 1000) with a
  read-only root filesystem in the production profile.
* No secret is read, stored or logged by any implementation.

---

## 9. Related

* Usage and troubleshooting: [`README.md`](README.md)
* Architecture comparison: [`docs/ARCHITECTURE_COMPARISON.md`](docs/ARCHITECTURE_COMPARISON.md)
* Operational scenarios: [`docs/SCENARIOS.md`](docs/SCENARIOS.md)
* Repository standards: [`../../AGENTS.md`](../../AGENTS.md)
