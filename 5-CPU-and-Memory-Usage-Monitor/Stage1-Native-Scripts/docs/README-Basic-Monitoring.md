# Basic Monitoring - CPU and Memory

> Monitor CPU and Memory usage with color-coded output and threshold alerts.

---

## What Gets Monitored

| Metric | Description | Source |
|--------|-------------|--------|
| **CPU Usage** | Overall system CPU utilization % | `/proc/stat` (Linux), `top` (macOS) |
| **Memory Usage** | RAM utilization % | `/proc/meminfo` (Linux), `vm_stat` (macOS) |
| **Top Processes** | Highest resource-consuming processes | `ps` command |

---

## Basic Usage

### Bash

```bash
# Simple execution - shows CPU, Memory, and top processes
./system_monitor.sh

# Sample Output:
# ╔════════════════════════════════════════════════════════════╗
# ║         SYSTEM RESOURCE MONITOR v1.3.0                     ║
# ╚════════════════════════════════════════════════════════════╝
# 
# Timestamp: 2026-01-15 10:30:00
# 
# CPU Usage:    [████████████████████░░░░░░░░░░]  45.2%  (OK)
# Memory Usage: [████████████████░░░░░░░░░░░░░░]  35.8%  (OK)
#
# Top Processes (by Memory):
# PID     NAME          CPU%   RAM(MB)
# 1234    firefox       12.5   512.3
# 5678    code          8.2    423.1
# ...
```

### PowerShell

```powershell
# Simple execution
.\system_monitor.ps1

# Sample Output:
# ========================================
# System Resource Monitor v1.3.0
# ========================================
# Timestamp: 2026-01-15 10:30:00
# 
# CPU Usage:    ████████████████░░░░  45.2%  OK
# Memory Usage: ████████████░░░░░░░░  35.8%  OK
#
# Top Processes (by Memory):
# PID   Name          CPU%   RAM(MB)
# 1234  firefox       12.5   512.3
# 5678  code          8.2    423.1
```

---

## Color Coding

Colors indicate resource usage levels:

| Color | Range | Meaning | Action |
|-------|-------|---------|--------|
| 🟢 | 0-70% | Normal | No action needed |
| 🟡 | 70-90% | Warning | Monitor closely |
| 🔴 | 90%+ | Critical | Investigate immediately |

---

## Customizing Thresholds

### Bash

```bash
# Change color thresholds (edit script or use environment variables)
CPU_THRESHOLD=70    # Yellow above this
CPU_CRITICAL=90     # Red above this
MEM_THRESHOLD=70
MEM_CRITICAL=90

# Example with custom thresholds
CPU_THRESHOLD=60 CPU_CRITICAL=80 ./system_monitor.sh
```

### PowerShell

```powershell
# Set thresholds via parameters
.\system_monitor.ps1 -CpuThreshold 70 -MemThreshold 75

# This changes when colors shift:
# - Below 70%: Green
# - 70-75%: Yellow
# - Above 75%: Red
```

---

## 📊 Understanding the Output

### CPU Usage

```
CPU Usage: [████████████████████░░░░░░░░░░]  45.2%  (OK)
           └─ Visual bar (20 chars)         └─ %     └─ Status
```

**What it measures:**
- Percentage of time CPU is busy (not idle)
- Includes user processes, system/kernel time, and I/O wait
- Average across all CPU cores

**Typical values:**
- 0-30%: Idle/Light load
- 30-70%: Normal load
- 70-90%: Heavy load
- 90%+: Overloaded

### Memory Usage

```
Memory Usage: [████████████████░░░░░░░░░░░░░░]  35.8%  (OK)
              └─ Visual bar                    └─ %    └─ Status
```

**What it measures:**
- Percentage of total RAM currently in use
- Includes active memory, buffers, and cache (Linux)
- Physical memory only (not swap/virtual)

**Typical values:**
- 0-40%: Plenty of memory available
- 40-70%: Normal usage
- 70-90%: High usage, consider closing applications
- 90%+: Critical, system may start swapping

### Process List

```
Top Processes (by Memory):
PID     NAME          CPU%   RAM(MB)
1234    firefox       12.5   512.3
5678    code          8.2    423.1
9012    python        5.1    256.7
```

**Columns:**
- **PID**: Process ID (unique identifier)
- **NAME**: Process/command name
- **CPU%**: Current CPU usage percentage
- **RAM(MB)**: Memory usage in megabytes

---

## Filtering Top Processes

### Bash

```bash
# Show top 50 processes (default is 100)
# Edit the script variable or pipe to head:
./system_monitor.sh | head -n 30

# Show only processes using >100MB RAM
./system_monitor.sh | awk '$4 > 100'
```

### PowerShell

```powershell
# Show top 50 processes
.\system_monitor.ps1 -TopProcesses 50

# Show top 20 processes
.\system_monitor.ps1 -TopProcesses 20
```

---

## Interpreting Results

### When to Worry

| Scenario | Interpretation | Action |
|----------|----------------|--------|
| CPU consistently >90% | System overloaded | Check for runaway processes |
| Memory consistently >90% | RAM exhausted | Close apps or add RAM |
| One process using >50% CPU | Runaway process | Consider killing it |
| One process using >2GB RAM | Memory leak possible | Monitor or restart |

### Normal Patterns

| Pattern | Explanation |
|---------|-------------|
| CPU spikes during startup | Normal - loading programs |
| High CPU during builds | Expected - compilation is CPU-intensive |
| Memory slowly increasing | Possible leak, or just cache filling |
| Brief CPU spikes | Normal background tasks |

---

## Related Documentation

- [Installation Guide](README-Installation.md)
- [Disk Usage Monitoring](README-Disk-Usage.md)
- [Export Formats](README-Export-Formats.md)
- [Watch Mode (Continuous)](README-Watch-Mode.md)