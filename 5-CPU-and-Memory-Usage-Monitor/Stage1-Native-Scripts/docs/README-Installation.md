# Installation and Setup Guide

> Get the native scripts running on your system in under 5 minutes.

---

## Prerequisites

### For Bash Script

| Requirement | Version | How to Check |
|-------------|---------|--------------|
| Bash | 4.0+ | `bash --version` |
| Standard Unix tools | Any | `which ps awk grep date df` |

**Supported Platforms:**
- Linux (Ubuntu, Debian, CentOS, RHEL, Alpine)
- macOS (10.14+)
- Windows Subsystem for Linux (WSL2)
- Git Bash on Windows

### For PowerShell Script

| Requirement | Version | How to Check |
|-------------|---------|--------------|
| PowerShell | 5.1+ (Windows) / 7+ (cross-platform) | `$PSVersionTable.PSVersion` |

**Supported Platforms:**
- Windows Server 2019/2022
- Windows 10/11
- Linux (Ubuntu, CentOS, Alpine)
- macOS

---

## Installation Steps

### Bash Installation

```bash
# Step 1: Navigate to the Stage1 directory
cd Stage1-Native-Scripts

# Step 2: Make the script executable
chmod +x system_monitor.sh

# Step 3: Verify it works
./system_monitor.sh --help
```

### PowerShell Installation

```powershell
# Step 1: Navigate to the Stage1 directory
cd Stage1-Native-Scripts

# Step 2: Check execution policy (may need adjustment)
Get-ExecutionPolicy

# If the policy is "Restricted", you may need to run:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Step 3: Verify it works
.\system_monitor.ps1 -Help
```

---

## Verification

### Test Bash Script

```bash
# Test basic functionality
./system_monitor.sh

# Expected output:
# - CPU usage percentage (green/yellow/red based on threshold)
# - Memory usage percentage
# - Top processes table
# - No errors

# Test with JSON output
./system_monitor.sh --json

# Expected output:
# {"timestamp":"2026-01-15T10:30:00","cpu_percent":25.5,"memory_percent":60.2,...}
```

### Test PowerShell Script

```powershell
# Test basic functionality
.\system_monitor.ps1

# Expected output:
# - CPU usage percentage (color-coded)
# - Memory usage percentage
# - Top processes table

# Test with JSON output
.\system_monitor.ps1 -Format Json

# Expected output:
# {
#   "timestamp": "2026-01-15T10:30:00",
#   "cpu_percent": 25.5,
#   "memory_percent": 60.2,
#   ...
# }
```

---

## Troubleshooting

### Bash Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `Permission denied` | Not executable | `chmod +x system_monitor.sh` |
| `bad interpreter` | CRLF line endings | `sed -i 's/\r$//' system_monitor.sh` |
| `command not found` | Missing dependencies | Install `procps`, `gawk`, `coreutils` |
| Blank output | WSL path issues | Run from Linux filesystem (`/home/user/`) |

### PowerShell Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `cannot be loaded` | Execution policy | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| `is not recognized` | Wrong directory | Navigate to script directory first |
| `Access denied` | Insufficient privileges | Run as Administrator (for some features) |

---

## Security Notes

- Scripts do not require root/admin for basic monitoring
- Root/admin required only for:
  - Viewing all system processes
  - Killing processes owned by other users
  - Accessing certain disk I/O statistics

---

## Next Steps

Now that you have the scripts installed:

- Learn about [Basic Monitoring](README-Basic-Monitoring.md)  
- Explore [Disk Usage Monitoring](README-Disk-Usage.md)  
- Set up [Continuous Monitoring](README-Watch-Mode.md)