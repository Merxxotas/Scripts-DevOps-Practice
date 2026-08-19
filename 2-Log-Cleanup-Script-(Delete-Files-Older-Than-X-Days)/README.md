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
└── CODESTYLE.md       # Coding conventions and style guide
```

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
.cleanup_logs.ps1 -LogDirectory "C:LogsApp" -Days 14 -DryRun

# 2. Execute recursive cleanup with minimum size filter (files >= 10MB) and audit log
.cleanup_logs.ps1 -LogDirectory "C:LogsApp" -Days 30 -Pattern "*.log" -Recursive -MinSizeMB 10 -LogFile "C:Logscleanup_audit.log"
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
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:Scriptscleanup_logs.ps1 -LogDirectory C:LogsIIS -Days 30 -Recursive -LogFile C:Logscleanup.log"
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

