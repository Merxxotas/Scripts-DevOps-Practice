# Watch Mode - Continuous Monitoring

> Monitor your system continuously with automatic refresh and logging.

---

## What is Watch Mode?

Watch mode continuously monitors your system, refreshing the display at regular intervals. It's perfect for:

- **Real-time monitoring** during load tests
- **Long-term data collection** for trend analysis
- **Dashboard displays** on NOC walls
- **Troubleshooting** performance issues

---

## Basic Watch Mode

### Bash

```bash
# Watch with default 2-second interval
./system_monitor.sh --watch

# Watch with custom interval (5 seconds)
./system_monitor.sh --watch 5

# Watch with 1-second refresh (real-time)
./system_monitor.sh --watch 1
```

### PowerShell

```powershell
# Watch with default 2-second interval
.\system_monitor.ps1 -Watch

# Watch with custom interval
.\system_monitor.ps1 -Watch -RefreshSeconds 5

# Watch with 1-second refresh
.\system_monitor.ps1 -Watch -RefreshSeconds 1
```

---

## Choosing Refresh Intervals

| Interval | Use Case | CPU Impact |
|----------|----------|------------|
| 1 second | Real-time troubleshooting | Higher |
| 2-5 seconds | General monitoring | Low |
| 10-30 seconds | Long-term trending | Minimal |
| 60+ seconds | Background logging | Negligible |

---

## Terminal Display in Watch Mode

In watch mode, the terminal clears and redraws at each interval:

```
╔════════════════════════════════════════════════════════════╗
║         SYSTEM RESOURCE MONITOR v1.3.0                     ║
║         Watch Mode - Refreshing every 5s                   ║
╚════════════════════════════════════════════════════════════╝

Timestamp: 2026-01-15 10:30:00

CPU Usage:    [████████████████████░░░░░░░░░░]  45.2%  (OK)
Memory Usage: [████████████████░░░░░░░░░░░░░░]  35.8%  (OK)

Top Processes (by Memory):
PID     NAME          CPU%   RAM(MB)
1234    firefox       12.5   512.3
5678    code          8.2    423.1

Press Ctrl+C to exit...
```

---

## Watch Mode with Logging

Combine watch mode with export for continuous data collection:

### Bash

```bash
# Log to JSON files every 5 seconds
./system_monitor.sh --watch 5 --json --export ./logs/

# Output:
# ./logs/system-monitor-20260115-103000.json
# ./logs/system-monitor-20260115-103005.json
# ./logs/system-monitor-20260115-103010.json
# ... (every 5 seconds)

# Log to CSV every 10 seconds
./system_monitor.sh --watch 10 --csv --export ./logs/
```

### PowerShell

```powershell
# Log to CSV every 5 seconds
.\system_monitor.ps1 -Watch -RefreshSeconds 5 -Format Csv -ExportPath .\logs\
```

---

## Background Monitoring

Run monitoring in the background:

### Bash (Linux/macOS)

```bash
# Run in background, log to file
./system_monitor.sh --watch 60 --json --export ./logs/ &
# Returns: [1] 12345 (PID)

# Check it's running
ps aux | grep system_monitor

# Stop background monitoring
kill 12345
```

### Using nohup (survives logout)

```bash
# Run even after you log out
nohup ./system_monitor.sh --watch 60 --json --export ./logs/ > /dev/null 2>&1 &

# Will keep running until:
# - You kill the process
# - System reboots
```

### Using systemd (Linux)

```bash
# Create service file
sudo tee /etc/systemd/system/system-monitor.service > /dev/null <<EOF
[Unit]
Description=System Resource Monitor
After=network.target

[Service]
Type=simple
ExecStart=/path/to/system_monitor.sh --watch 60 --json --export /var/log/system-monitor/
Restart=always
User=monitor

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable system-monitor
sudo systemctl start system-monitor

# Check status
sudo systemctl status system-monitor
```

### PowerShell (Windows)

```powershell
# Run as background job
$job = Start-Job {
    & "C:\Tools\system_monitor.ps1" -Watch -RefreshSeconds 60 -Format Json -ExportPath "C:\Logs\"
}

# Check job status
Get-Job

# Stop job
Stop-Job $job
Remove-Job $job
```

### Windows Task Scheduler

```powershell
# Create scheduled task for continuous monitoring
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Tools\system_monitor.ps1 -Watch -RefreshSeconds 60 -Format Json -ExportPath C:\Logs\"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "SystemMonitor" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM"
```

---

## Log Rotation

Prevent logs from filling up your disk:

### Logrotate (Linux)

```bash
# Create logrotate config
sudo tee /etc/logrotate.d/system-monitor > /dev/null <<EOF
/var/log/system-monitor/*.json {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF
```

### PowerShell Script (Windows)

```powershell
# Clean up logs older than 7 days
Get-ChildItem "C:\Logs\system-monitor-*.json" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item
```

---

## Alerting from Watch Mode

Send alerts when thresholds are exceeded:

### Bash Alert Script

```bash
#!/bin/bash
# alert-monitor.sh

while true; do
    DATA=$(./system_monitor.sh --json)
    CPU=$(echo $DATA | jq '.cpu.percent')
    MEM=$(echo $DATA | jq '.memory.percent')
    
    if (( $(echo "$CPU > 90" | bc -l) )); then
        echo "HIGH CPU ALERT: ${CPU}% at $(date)" | tee -a alerts.log
        # Add: send email, Slack notification, etc.
    fi
    
    if (( $(echo "$MEM > 90" | bc -l) )); then
        echo "HIGH MEMORY ALERT: ${MEM}% at $(date)" | tee -a alerts.log
    fi
    
    sleep 60
done
```

---

## Related Documentation

- [Export Formats](README-Export-Formats.md)
- [Basic Monitoring](README-Basic-Monitoring.md)
- [Kill Process](README-Kill-Process.md)