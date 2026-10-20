# Process Restart Capability

> Kill and automatically restart processes with full audit logging.

---

## What is Process Restart?

Process restart combines two operations:
1. **Kill** the running process
2. **Restart** it with the same or modified command

**Use Cases:**
- Apply configuration changes
- Clear memory leaks
- Recover from hung states
- Scheduled maintenance restarts

---

## Basic Restart

### Bash

```bash
# Restart a process by PID
./system_monitor.sh --restart 1234

# Confirmation prompt:
# Process: firefox (PID 1234)
# Command: /usr/lib/firefox/firefox
# Restart this process? [y/N]: y
# 
# ✓ Process 1234 killed successfully
# ✓ Process restarted with PID 5678
```

### PowerShell

```powershell
# Restart a process by PID
.\system_monitor.ps1 -RestartPid 1234

# Confirmation:
# Process: firefox (PID 1234)
# Path: C:\Program Files\Mozilla Firefox\firefox.exe
# Restart this process? [Y/N]: Y
#
# ✓ Process 1234 stopped successfully
# ✓ Process restarted with PID 5678
```

---

## Restart with Custom Command

Sometimes you need to restart with different parameters:

### Bash

```bash
# Restart with custom command
./system_monitor.sh --restart 1234 --command "/usr/bin/firefox --safe-mode"

# Restart with environment variables
DEBUG=1 ./system_monitor.sh --restart 1234 --command "/app/server --verbose"
```

### PowerShell

```powershell
# Restart with custom command
.\system_monitor.ps1 -RestartPid 1234 -Command '"C:\Program Files\App\server.exe" -Verbose'

# Restart with arguments
.\system_monitor.ps1 -RestartPid 1234 -Arguments "--config", "production.conf"
```

---

## Audit Logging

All restart operations are logged with full details:

### Log File Location

```bash
# Default log
cat logs/system_monitor_kill.log

# Or
cat logs/system_monitor_restart.log
```

### Log Format

```
[2026-01-15 10:30:00] RESTART user=john 
  old_pid=1234 
  new_pid=5678 
  name=firefox 
  old_command="/usr/lib/firefox/firefox"
  new_command="/usr/lib/firefox/firefox"
  reason=manual_restart
  duration_ms=1500
```

### Viewing Logs

```bash
# View all restart operations
grep "RESTART" logs/system_monitor_kill.log

# View recent operations
tail -n 50 logs/system_monitor_kill.log

# Count restarts today
grep "$(date +%Y-%m-%d)" logs/system_monitor_kill.log | grep -c "RESTART"
```

---

## Common Restart Scenarios

### 1. Web Server Restart

```bash
# Restart nginx
./system_monitor.sh --restart $(pgrep nginx) --command "nginx -g 'daemon off;'"

# Or use service manager (recommended for system services)
sudo systemctl restart nginx
```

### 2. Application with Memory Leak

```bash
# Find and restart a leaky Java app
PID=$(pgrep -f "java.*myapp")
./system_monitor.sh --restart $PID --command "java -Xmx2G -jar myapp.jar"
```

### 3. Database Connection Pool Reset

```bash
# Restart connection pool without full DB restart
./system_monitor.sh --restart $(pgrep connection-pool) --command "pool-manager --reset"
```

### 4. Scheduled Maintenance

```bash
# Cron job for nightly restart
0 3 * * * /path/to/system_monitor.sh --restart $(pgrep myapp) >> /var/log/maintenance.log 2>&1
```

---

## Safety Features

### Confirmation Prompts

By default, all restart operations require confirmation:

```bash
# Will prompt for confirmation
./system_monitor.sh --restart 1234

# Skip confirmation (use with caution!)
./system_monitor.sh --restart 1234 --force
```

### Pre-Restart Verification

The script checks before restarting:

1. **Process exists** - Verifies PID is valid
2. **Command captured** - Saves the original command line
3. **Permissions** - Ensures user can restart the process
4. **Dependencies** - Warns if process has child processes

### Rollback on Failure

If restart fails, the script:
1. Logs the failure
2. Attempts to notify (if configured)
3. Returns non-zero exit code

---

## Restart Monitoring

Track how often processes need restarts:

### Restart Statistics Script

```bash
#!/bin/bash
# restart-stats.sh

LOGFILE="logs/system_monitor_kill.log"

echo "=== Process Restart Statistics ==="
echo ""

# Total restarts
echo "Total restarts: $(grep -c "RESTART" "$LOGFILE")"

# Restarts by process name
echo ""
echo "Restarts by process:"
grep "RESTART" "$LOGFILE" | grep -oP 'name=\K[^ ]+' | sort | uniq -c | sort -rn

# Restarts by user
echo ""
echo "Restarts by user:"
grep "RESTART" "$LOGFILE" | grep -oP 'user=\K[^ ]+' | sort | uniq -c | sort -rn

# Recent restarts
echo ""
echo "Last 5 restarts:"
grep "RESTART" "$LOGFILE" | tail -n 5
```

---

## Integration with Monitoring

### Auto-Restart on High Resource Usage

```bash
#!/bin/bash
# auto-restart.sh

THRESHOLD_CPU=95
PROCESS_NAME="myapp"

while true; do
    PID=$(pgrep "$PROCESS_NAME")
    if [ -n "$PID" ]; then
        CPU=$(ps -p $PID -o %cpu= | tr -d ' ')
        if (( $(echo "$CPU > $THRESHOLD_CPU" | bc -l) )); then
            echo "$(date): $PROCESS_NAME using ${CPU}% CPU, restarting..."
            ./system_monitor.sh --restart $PID --force
        fi
    fi
    sleep 60
done
```

### Notification on Restart

```bash
#!/bin/bash
# restart-and-notify.sh

PID="$1"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Perform restart and capture new PID
NEW_PID=$(./system_monitor.sh --restart $PID --force | grep -oP 'PID \K[0-9]+')

# Send notification
curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"Process restarted: Old PID $PID → New PID $NEW_PID\"}" \
    $SLACK_WEBHOOK
```

---

## Troubleshooting Restarts

| Issue | Cause | Solution |
|-------|-------|----------|
| "Command not found" | PATH issue | Use full path to executable |
| "Permission denied" | Insufficient privileges | Use sudo or run as service user |
| Process restarts then dies | Missing environment | Source profile or set env vars |
| New PID same as old | Fast restart | Normal for some processes |
| Port already in use | Old process not fully exited | Add sleep or check port |

---

## Related Documentation

- [Kill Process](README-Kill-Process.md) - Just kill without restart
- [Watch Mode](README-Watch-Mode.md) - Monitor processes before/after restart
- [Export Formats](README-Export-Formats.md) - Log restart data