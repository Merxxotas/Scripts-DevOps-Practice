# Log Cleanup Utility (Delete Files Older Than X Days) 🧹

[![CI Log Cleanup](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-cleanup-logs.yml/badge.svg)](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-cleanup-logs.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)](https://microsoft.com/powershell)

An enterprise-grade, zero-dependency DevOps automation utility to safely prune stale log files, reclaim disk space, and prevent server outages caused by unmanaged log growth.

Available in **POSIX Bash** for Linux / macOS and **PowerShell** for Windows, with 100% feature parity.

---

## 🚀 Key Features

- 🛡️ **Safety Guardrails**: Built-in blacklist preventing accidental deletion of root and critical operating system directories (`/`, `/etc`, `C:\`, `C:\Windows`, etc.).
- 🔍 **Flexible Discovery**: Filter by file age in days (`-t / -Days`), glob patterns (`-p / -Pattern`), and minimum file size (`-m / -MinSizeMB`).
- 📁 **Recursion Support**: Choose between single-folder cleanup or deep recursive directory traversal (`-r / -Recursive`).
- 🧪 **Dry-Run Simulation**: Preview exactly which files would be deleted and see projected storage savings without making any modifications (`-n / -DryRun`).
- 📊 **Storage Reclaimed Metrics**: Dynamic space calculation reporting totals in Bytes, KB, MB, and GB.
- 📝 **Persistent Audit Logging**: Optional execution and file-action logging for compliance and monitoring (`-l / -LogFile`).
- ⚙️ **Zero Dependencies**: 100% native shell implementation requiring no package installations or external binaries.

---

## 📂 Directory Structure

```
2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/
├── cleanup_logs.sh    # Enterprise POSIX Bash script (Linux/macOS)
├── cleanup_logs.ps1   # Enterprise PowerShell script (Windows/Cross-platform)
├── README.md          # Comprehensive module documentation
├── SPECS.md           # Technical specification & architecture document
├── ROADMAP.md         # Spec-driven development milestone roadmap
├── CODESTYLE.md       # Coding conventions and style guide
├── tests/             # Automated unit and integration test suites
│   ├── test_cleanup_logs.sh
│   └── test_cleanup_logs.ps1
└── docs/              # In-depth technical guides & interactive labs
    ├── ARCHITECTURE_COMPARISON.md
    ├── SCENARIOS.md
    └── labs/
        ├── LAB1_BASIC_RETENTION_AND_DRYRUN.md
        ├── LAB2_RECURSIVE_SIZE_FILTERING.md
        └── LAB3_PRODUCTION_SCHEDULING_AND_AUDIT.md
```

---

## 📚 Architecture & Interactive Labs

Deep-dive technical documentation and step-by-step interactive labs are available in the [`docs/`](docs/) directory:

- 📊 **[Architecture & Runtime Comparison](docs/ARCHITECTURE_COMPARISON.md)**: Deep dive into POSIX streams vs. .NET object pipelines, memory footprints, and platform strengths.
- 🚀 **[Production Deployment Scenarios](docs/SCENARIOS.md)**: Real-world patterns for Nginx web servers, IIS clusters, database dumps, and CI/CD runners.
- 🧪 **[Lab 1: Basic Retention & Dry-Run Preview](docs/labs/LAB1_BASIC_RETENTION_AND_DRYRUN.md)**: Hands-on guide to testing simulation mode and live pruning.
- 📁 **[Lab 2: Recursive Traversal & Size Thresholds](docs/labs/LAB2_RECURSIVE_SIZE_FILTERING.md)**: Nested microservice cleanup and size-based filters.
- ⏰ **[Lab 3: Production Scheduling & Audit Logging](docs/labs/LAB3_PRODUCTION_SCHEDULING_AND_AUDIT.md)**: Configuring Linux Cron, Windows Task Scheduler, and ISO-8601 logging.

---

## ⚡ Quick Start

### Linux / macOS (Bash)

```bash
# 1. Grant execute permissions
chmod +x cleanup_logs.sh

# 2. Perform a dry-run preview (simulate deletion on logs older than 14 days)
./cleanup_logs.sh -d /var/log/myapp -t 14 -n

# 3. Execute recursive cleanup on logs older than 30 days matching *.log
./cleanup_logs.sh -d /var/log/myapp -t 30 -p "*.log" -r
```

### Windows (PowerShell)

```powershell
# 1. Perform a dry-run preview on logs older than 14 days
.\cleanup_logs.ps1 -LogDirectory "C:\Logs\App" -Days 14 -DryRun

# 2. Execute recursive cleanup with minimum size filter (files >= 10MB) and audit log
.\cleanup_logs.ps1 -LogDirectory "C:\Logs\App" -Days 30 -Pattern "*.log" -Recursive -MinSizeMB 10 -LogFile "C:\Logs\cleanup_audit.log"
```

---

## 📋 Command-Line Reference

| Bash Flag | PowerShell Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-d <path>` | `-LogDirectory <string>` | String | *Required* | Target directory path to clean. |
| `-t <days>` | `-Days <int>` | Integer | `30` | Delete files older than X days. |
| `-p <pattern>` | `-Pattern <string>` | String | `"*.log"` | File matching glob filter. |
| `-m <mb>` | `-MinSizeMB <double>` | Number | `0` | Minimum file size in MB to qualify for cleanup. |
| `-r` | `-Recursive` | Switch | `false` | Search subdirectories recursively. |
| `-n` | `-DryRun` | Switch | `false` | Simulation mode: preview without deleting. |
| `-l <file>` | `-LogFile <string>` | String | `none` | Path to write persistent audit logs. |
| `-v` | `-Verbose` | Switch | `false` | Enable verbose file-by-file output. |
| `-h` | `Get-Help` | Switch | `none` | Display help and usage instructions. |

---

## ⏰ Production Scheduling

### Linux (Cron Job)
To run the cleanup daily at 02:00 AM for logs older than 14 days:
```cron
0 2 * * * /usr/local/bin/cleanup_logs.sh -d /var/log/nginx -t 14 -r -l /var/log/cleanup_nginx.log >/dev/null 2>&1
```

### Windows (Task Scheduler via PowerShell)
```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\cleanup_logs.ps1 -LogDirectory C:\Logs\IIS -Days 30 -Recursive -LogFile C:\Logs\cleanup.log"
$Trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "DailyLogCleanup" -Description "Purges logs older than 30 days"
```

---

## 🚦 Exit Codes

| Exit Code | Status | Meaning |
| :---: | :--- | :--- |
| `0` | **Success** | All operations completed without errors. |
| `1` | **Configuration Error** | Invalid arguments, non-existent directory, or protected system path targeted. |
| `2` | **Partial Failure** | One or more eligible files could not be removed due to OS file locks or permission issues. |

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).
