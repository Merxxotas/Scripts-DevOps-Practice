# Stage 1: Native Scripts - System Resource Monitor

> **Dual-Native Implementation**: Bash and PowerShell scripts for cross-platform system monitoring without external dependencies.

---

## Overview

This stage provides native shell implementations that work on any system without requiring Python or Docker installations.

| Script | Platform | File |
|--------|----------|------|
| **Bash** | Linux, macOS, WSL | [`system_monitor.sh`](system_monitor.sh) |
| **PowerShell** | Windows, Linux, macOS | [`system_monitor.ps1`](system_monitor.ps1) |

---

## Documentation Structure

| Document | Description |
|----------|-------------|
| [README-Installation.md](docs/README-Installation.md) | Setup, prerequisites, and first run |
| [README-Basic-Monitoring.md](docs/README-Basic-Monitoring.md) | CPU, Memory, and basic usage |
| [README-Disk-Usage.md](docs/README-Disk-Usage.md) | Disk I/O monitoring and storage analysis |
| [README-Export-Formats.md](docs/README-Export-Formats.md) | JSON, CSV, and file export options |
| [README-Watch-Mode.md](docs/README-Watch-Mode.md) | Continuous monitoring and logging |
| [README-Kill-Process.md](docs/README-Kill-Process.md) | Process termination and restart |
| [README-Process-Restart.md](docs/README-Process-Restart.md) | Process restart with audit logging |
| [README-Examples.md](docs/README-Examples.md) | Real-world usage scenarios |

---

## Quick Start

### Bash (Linux/macOS/WSL)

```bash
# Make executable and run
chmod +x system_monitor.sh
./system_monitor.sh

# Watch mode with 5-second refresh
./system_monitor.sh --watch 5

# Export to JSON
./system_monitor.sh --json --export ./report.json
```

### PowerShell (Windows/Linux/macOS)

```powershell
# Run directly
.\system_monitor.ps1

# Watch mode
.\system_monitor.ps1 -Watch -RefreshSeconds 5

# Export to CSV
.\system_monitor.ps1 -Format Csv -ExportPath .\report.csv
```

---

## Features

| Feature | Bash | PowerShell | Documentation |
|---------|------|------------|---------------|
| CPU Monitoring | Yes | Yes | [Basic Monitoring](docs/README-Basic-Monitoring.md) |
| Memory Monitoring | Yes | Yes | [Basic Monitoring](docs/README-Basic-Monitoring.md) |
| Disk Usage | Yes | Yes | [Disk Usage](docs/README-Disk-Usage.md) |
| Disk I/O Stats | Yes | Yes | [Disk Usage](docs/README-Disk-Usage.md) |
| Process Listing | Yes | Yes | [Basic Monitoring](docs/README-Basic-Monitoring.md) |
| Kill Process | Yes | Yes | [Kill Process](docs/README-Kill-Process.md) |
| Restart Process | Yes | Yes | [Process Restart](docs/README-Process-Restart.md) |
| JSON Export | Yes | Yes | [Export Formats](docs/README-Export-Formats.md) |
| CSV Export | Yes | Yes | [Export Formats](docs/README-Export-Formats.md) |
| Watch Mode | Yes | Yes | [Watch Mode](docs/README-Watch-Mode.md) |
| Audit Logging | Yes | Yes | [Process Restart](docs/README-Process-Restart.md) |

---

## Command Reference

### Bash Options

```bash
./system_monitor.sh [OPTIONS]

Options:
  -w, --watch [seconds]     Enable continuous refresh mode (default: 2s)
  -j, --json                Output JSON format to stdout
  -c, --csv                 Output CSV format to stdout
  -e, --export <path>       Export to file (auto-generates filename if directory)
  -k, --kill <pid>          Kill process by PID
  -r, --restart <pid>       Restart process by PID
  -h, --help                Display help and exit
```

### PowerShell Parameters

```powershell
.\system_monitor.ps1 [[-TopProcesses] <Int32>] [[-CpuThreshold] <Int32>] 
                     [[-MemThreshold] <Int32>] [-Watch] 
                     [[-RefreshSeconds] <Int32>] [[-Format] <String>] 
                     [[-ExportPath] <String>] [-KillPid <Int32>] 
                     [-RestartPid <Int32>]

Parameters:
  -TopProcesses     Number of top processes to display (default: 100)
  -CpuThreshold     CPU % threshold for alerts (default: 80)
  -MemThreshold     Memory % threshold for alerts (default: 80)
  -Watch            Enable continuous refresh mode
  -RefreshSeconds   Refresh interval in watch mode (default: 2)
  -Format           Output format: Display, Json, or Csv (default: Display)
  -ExportPath       Export file path or directory
  -KillPid          Kill process by PID
  -RestartPid       Restart process by PID
```

---

## Project Structure

```
Stage1-Native-Scripts/
├── system_monitor.sh              # Main Bash script
├── system_monitor.ps1             # Main PowerShell script
├── system_monitor - windows version.txt  # Windows-specific notes
├── docs/                          # Documentation
│   ├── README-Installation.md
│   ├── README-Basic-Monitoring.md
│   ├── README-Disk-Usage.md
│   ├── README-Export-Formats.md
│   ├── README-Watch-Mode.md
│   ├── README-Kill-Process.md
│   ├── README-Process-Restart.md
│   └── README-Examples.md
├── New-Addittions/                # Additional implementations
│   ├── 1.Disk-IO-and-Storage-Monitoring/
│   └── 2.Process-Kill_Restart-Capability/
└── logs/                          # Default log directory
```

---

## Next Stage

Once you're comfortable with native scripts, proceed to:

→ **[Stage 2: Python Unified](../Stage2-Python-Unified/)** - Type-safe, testable implementation

---

## All Stages

| Stage | Description | Link |
|-------|-------------|------|
| Stage 1 | Native Scripts (Bash + PowerShell) | **You are here** |
| Stage 2 | Python Unified | [../Stage2-Python-Unified/](../Stage2-Python-Unified/) |
| Stage 3 | Containerization | [../Stage3-Containerization/](../Stage3-Containerization/) |
| Stage 4 | CI/CD Pipeline | [../Stage4-CI-CD-Pipeline/](../Stage4-CI-CD-Pipeline/) |

---

*Version 1.3.0 | Cross-Platform Infrastructure Toolkit*