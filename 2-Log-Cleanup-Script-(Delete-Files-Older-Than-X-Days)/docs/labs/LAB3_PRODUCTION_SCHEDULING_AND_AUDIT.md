# Lab 3: Production Scheduling & Audit Logging ⏰

## Objective
Configure production-grade automated scheduling (Linux Cron and Windows Task Scheduler) with persistent ISO-8601 audit logging, exit code validation, and error alert hooking.

---

## 📋 Prerequisites
- Administrative/sudo access on Linux or Administrator privileges on Windows (for system scheduler setup).
- Completed [Lab 1](LAB1_BASIC_RETENTION_AND_DRYRUN.md) and [Lab 2](LAB2_RECURSIVE_SIZE_FILTERING.md).

---

## Step 1: Set Up Persistent Audit Logging

The utility provides built-in ISO-8601 audit logging via the `-l / -LogFile` option.

### Execute Cleanup with Audit Log:
```bash
mkdir -p /tmp/lab3_logs /tmp/lab3_audit
echo "Stale log" > /tmp/lab3_logs/old.log
touch -t 202606010000 /tmp/lab3_logs/old.log

./cleanup_logs.sh -d /tmp/lab3_logs -t 30 -l /tmp/lab3_audit/cleanup.log
```

### Inspect Audit Log:
```bash
cat /tmp/lab3_audit/cleanup.log
```

### Example Output:
```text
2026-08-19T14:45:00Z [INFO] Log cleanup initiated for '/tmp/lab3_logs' (Retention: 30d, Pattern: '*.log', Recursive: false, DryRun: false, MinSizeMB: 0)
2026-08-19T14:45:01Z [INFO] DELETED: /tmp/lab3_logs/old.log (Size: 10 B, Age: 79d)
2026-08-19T14:45:01Z [INFO] Cleanup completed: Scanned=1, Eligible=1, Processed=1, Failed=0, Reclaimed=10 B
```

---

## Step 2: Validate Standardized Exit Codes

In automated DevOps pipelines, exit codes determine whether alerting systems trigger pager incidents.

### Test Case A: Success (Code 0)
```bash
./cleanup_logs.sh -d /tmp/lab3_logs -t 30
echo "Exit Code: $?"  # Outputs: 0
```

### Test Case B: Safety Violation (Code 1)
```bash
./cleanup_logs.sh -d /etc
echo "Exit Code: $?"  # Outputs: 1
```

---

## Step 3: Production Schedulers Configuration

### 1. Linux Cron Configuration
Edit the system crontab (`crontab -e`):
```cron
# Run daily at 02:30 AM with automatic error alerting
30 2 * * * /usr/local/bin/cleanup_logs.sh -d /var/log/myapp -t 14 -r -l /var/log/cleanup_audit.log || echo "Log cleanup failed!" | mail -s "ALERT: Log Cleanup Error" devops-alerts@example.com
```

### 2. Windows Task Scheduler (PowerShell Automation)
Create and register the daily task programmatically:
```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\Scripts\cleanup_logs.ps1 -LogDirectory C:\Logs\App -Days 30 -Recursive -LogFile C:\Logs\audit.log"

$Trigger = New-ScheduledTaskTrigger -Daily -At 2am
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount

Register-ScheduledTask -TaskName "AutomatedLogCleanup" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -Principal $Principal `
                       -Description "Daily automated log retention and purging"
```

### Verify Task in Windows:
```powershell
Get-ScheduledTask -TaskName "AutomatedLogCleanup"
```

---

## Step 4: Cleanup Lab Environment
```bash
rm -rf /tmp/lab3_logs /tmp/lab3_audit
```

