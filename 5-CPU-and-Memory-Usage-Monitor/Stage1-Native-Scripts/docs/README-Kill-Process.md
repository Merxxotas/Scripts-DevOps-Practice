# Kill Process Capability

> Safely terminate processes that are consuming excessive resources or have become unresponsive.

---

## Important Warning

Killing processes can:
- **Lose unsaved data** in applications
- **Crash systems** if you kill critical processes
- **Cause service outages** on production servers

**Always verify the PID before killing!**

---

## When to Kill a Process

| Scenario | Action | Example |
|----------|--------|---------|
| Runaway process (>90% CPU) | Kill and investigate | `npm run build` stuck in loop |
| Memory leak | Kill to free RAM | Browser using 8GB+ |
| Zombie process | Kill to clean up | Defunct processes |
| Unresponsive app | Kill when force quit fails | Frozen IDE |
| Security threat | Kill immediately | Unknown mining process |

---

## Finding the Process ID (PID)

Before killing, identify the correct PID:

### Using the Monitor Script

```bash
# Run the monitor to see top processes
./system_monitor.sh

# Output shows:
# PID     NAME          CPU%   RAM(MB)
# 1234    firefox       95.2   1024.0   ← High CPU
# 5678    node          45.1   512.3
```

### Using System Tools

```bash
# Find by name
pgrep firefox          # Returns PID(s)
pgrep -a firefox       # Returns PID and command

# Search with ps
ps aux | grep firefox

# Or use pidof
pidof firefox
```

### PowerShell

```powershell
# Find by name
Get-Process firefox

# Search
Get-Process | Where-Object { $_.Name -like "*fire*" }
```

---

## Killing a Process

### Bash

```bash
# Basic kill (sends SIGTERM - graceful shutdown)
./system_monitor.sh --kill 1234

# With confirmation prompt
# Process firefox (PID 1234) using 95.2% CPU
# Kill this process? [y/N]: y
# ✓ Process 1234 killed successfully
```

### PowerShell

```powershell
# Basic kill
.\system_monitor.ps1 -KillPid 1234

# With confirmation
# Process firefox (PID 1234) using 95.2% CPU
# Kill this process? [Y/N]: Y
# ✓ Process 1234 stopped successfully
```

---

## Kill Signals Explained

Different ways to terminate a process:

| Signal | Name | Effect | Use Case |
|--------|------|--------|----------|
| `SIGTERM` (15) | Terminate | Graceful shutdown (default) | Normal kills |
| `SIGKILL` (9) | Kill | Force immediate termination | Unresponsive |
| `SIGHUP` (1) | Hang up | Reload config or terminate | Daemon reload |
| `SIGINT` (2) | Interrupt | Same as Ctrl+C | Interactive |

### Bash - Specify Signal

```bash
# Graceful kill (default)
kill -15 1234

# Force kill (use when -15 doesn't work)
kill -9 1234

# Kill with the script
./system_monitor.sh --kill 1234 --signal KILL
```

### PowerShell - Force Kill

```powershell
# Graceful stop (default)
Stop-Process -Id 1234

# Force kill
Stop-Process -Id 1234 -Force
```

---

## Protected Processes

Some processes cannot be killed:

| Type | Reason | What to Do |
|------|--------|------------|
| Kernel processes | Essential for OS | Never kill |
| Root-owned (as user) | Insufficient privileges | Use `sudo` |
| System services | May crash system | Use service manager |
| Zombie processes | Already dead | Wait for parent to reap |

### Using sudo (Linux/macOS)

```bash
# Kill system process owned by root
sudo ./system_monitor.sh --kill 1

# Or use sudo with kill
sudo kill -9 1234
```

### Run as Administrator (Windows)

```powershell
# Start PowerShell as Administrator
# Right-click → Run as Administrator

# Then run the script
.\system_monitor.ps1 -KillPid 1234
```

---

## Testing Kill Functionality

**Test with a harmless process first:**

### Create a Test Process

```bash
# Terminal 1: Start a test process
sleep 300 &
echo $!  # Note the PID

# Terminal 2: Kill it
./system_monitor.sh --kill <PID>
```

### PowerShell Test

```powershell
# Start notepad
notepad

# Get PID and kill
$proc = Get-Process notepad
.\system_monitor.ps1 -KillPid $proc.Id
```

---

## Audit Logging

All kill actions are logged for accountability:

### Log Location

```bash
# Default log location
cat logs/system_monitor_kill.log

# Or check the KILL_LOG_DIR if set
cat $KILL_LOG_DIR/system_monitor_kill.log
```

### Log Format

```
[2026-01-15 10:30:00] KILL user=john pid=1234 name=firefox signal=TERM reason=high_cpu
[2026-01-15 10:35:22] KILL user=john pid=5678 name=node signal=KILL reason=unresponsive
```

---

## Emergency Kill Script

For critical situations:

```bash
#!/bin/bash
# emergency-kill.sh - Kill all processes matching pattern

PATTERN="$1"
if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <process-name>"
    exit 1
fi

PIDS=$(pgrep "$PATTERN")
if [ -z "$PIDS" ]; then
    echo "No processes found matching: $PATTERN"
    exit 0
fi

echo "Found processes:"
echo "$PIDS" | xargs ps -fp

echo ""
read -p "Kill all these processes? [y/N]: " confirm
if [[ $confirm =~ ^[Yy]$ ]]; then
    echo "$PIDS" | xargs kill -9
    echo "Processes killed."
fi
```

---

## Related Documentation

- [Process Restart](README-Process-Restart.md) - Kill and automatically restart
- [Basic Monitoring](README-Basic-Monitoring.md) - Identify processes to kill
- [Watch Mode](README-Watch-Mode.md) - Monitor before/after killing