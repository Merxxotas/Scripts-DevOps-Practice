# Disk Usage and I/O Monitoring

> Monitor disk space utilization and disk I/O statistics to prevent storage issues.

---

## What Gets Monitored

| Metric | Description | Platforms |
|--------|-------------|-----------|
| **Disk Usage** | Space used/available per mount point | All (Linux, macOS, Windows) |
| **Disk I/O** | Read/write operations and throughput | Linux (best), Windows, macOS |
| **I/O Wait** | Time spent waiting for disk operations | Linux |

---

## Disk Usage Monitoring

### Bash

```bash
# Display disk usage for all mounted filesystems
./system_monitor.sh --disk

# Sample Output:
# ╔════════════════════════════════════════════════════════════╗
# ║                    DISK USAGE                              ║
# ╚════════════════════════════════════════════════════════════╝
# 
# Mount Point     Total     Used     Free   Usage
# /               500G     350G     150G    70%
# /home           1.0T     600G     400G    60%
# /boot           500M     100M     400G    20%
# /mnt/data       2.0T     1.8T     200G    90%  ⚠️ WARNING
```

### PowerShell

```powershell
# Display disk usage
.\system_monitor.ps1 -IncludeDisk

# Sample Output:
# ========================================
# Disk Usage
# ========================================
# Drive  Total     Used      Free      Usage
# C:     500 GB    350 GB    150 GB    70%
# D:     1.0 TB    600 GB    400 GB    60%
# E:     2.0 TB    1.8 TB    200 GB    90%  WARNING
```

---

## Understanding Disk Usage Output

### Columns Explained

| Column | Description | Example |
|--------|-------------|---------|
| Mount Point | Where the filesystem is accessible | `/`, `/home`, `C:` |
| Total | Total capacity of the filesystem | 500G, 1.0T |
| Used | Space currently occupied | 350G |
| Free | Space available for use | 150G |
| Usage | Percentage of space used | 70% |

### Alert Thresholds

| Usage % | Status | Icon | Action |
|---------|--------|------|--------|
| 0-70% | Normal | 🟢 | None needed |
| 70-90% | Warning | 🟡 | Plan cleanup |
| 90%+ | Critical | 🔴 | Free space immediately |

---

## Disk I/O Statistics (Linux)

Disk I/O monitoring shows how much data is being read from and written to your disks.

### Bash (Linux)

```bash
# Display disk I/O statistics
./system_monitor.sh --disk-io

# Sample Output:
# ╔════════════════════════════════════════════════════════════╗
# ║                    DISK I/O STATISTICS                     ║
# ╚════════════════════════════════════════════════════════════╝
# 
# Device     Reads    Writes    Read MB/s   Write MB/s   I/O Wait
# sda        15234    8234      45.2        23.1         2%
# sdb        5234     1234      12.3        5.6          0%
# nvme0n1    45234    12345     245.6       89.3         5%
```

### Understanding I/O Metrics

| Metric | Description | Good Value | Concerning |
|--------|-------------|------------|------------|
| **Reads** | Number of read operations | Varies | Sudden spikes |
| **Writes** | Number of write operations | Varies | Sustained high |
| **Read MB/s** | Data read throughput | Depends on disk | Near disk max |
| **Write MB/s** | Data write throughput | Depends on disk | Near disk max |
| **I/O Wait** | % of time CPU waits for disk | <10% | >20% |

### Interpreting I/O Wait

```
I/O Wait: 2%   →  Normal, disk keeping up
I/O Wait: 15%  →  Moderate load, monitor
I/O Wait: 30%+ →  Disk bottleneck, upgrade disk or reduce load
```

---

## Identifying Slow Disks

High I/O wait with low throughput indicates a slow or failing disk:

```
Device     Reads    Writes    Read MB/s   Write MB/s   I/O Wait
sda        100      50        0.5         0.3          45%  ← SLOW!
```

**This disk is slow because:**
- Low throughput (0.5 MB/s) despite high wait (45%)
- CPU is waiting for the disk to respond
- Consider upgrading to SSD or checking disk health

---

## Common Use Cases

### 1. Check Before Large Operations

```bash
# Before running a large download or build
./system_monitor.sh --disk

# Ensure you have at least 20% free space
```

### 2. Find Large Files (Bash)

```bash
# Find files larger than 1GB
find /home -type f -size +1G -exec ls -lh {} \;

# Then clean up as needed
```

### 3. Monitor During Data Transfer

```bash
# Watch disk I/O during large file copy
./system_monitor.sh --watch 2 --disk-io

# Look for:
# - Consistent throughput
# - I/O wait staying low
# - No sudden drops
```

### 4. Check Disk Health (Linux)

```bash
# Check SMART status
sudo smartctl -a /dev/sda

# Check for errors in dmesg
dmesg | grep -i error
```

---

## Disk Usage Trends

### Set Up Disk Monitoring

```bash
# Log disk usage every hour
crontab -e

# Add this line:
0 * * * * /path/to/system_monitor.sh --json --export /var/log/disk-usage/

# Analyze trends later
# (See README-Watch-Mode.md for more)
```

---

## Troubleshooting Disk Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| 100% disk usage | Log files growing | Rotate logs with `logrotate` |
| High I/O wait | Slow disk or too many operations | Move to SSD, spread load |
| Disk full but files deleted | Open file handles | Restart services holding files |
| Slow writes | Disk fragmentation (HDD) | Defragment or upgrade to SSD |

---

## Related Documentation

- [Basic Monitoring](README-Basic-Monitoring.md)
- [Watch Mode (Continuous Monitoring)](README-Watch-Mode.md)
- [Export Formats](README-Export-Formats.md)