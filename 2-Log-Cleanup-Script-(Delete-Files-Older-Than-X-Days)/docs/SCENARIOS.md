# Log Cleanup Utility - Real-World Production Scenarios 🚀

Unchecked log file growth is one of the leading causes of production outages, disk exhaustion, and database service degradation. Below are four realistic enterprise scenarios demonstrating how to deploy and automate the **Log Cleanup Utility** in production.

---

## 📋 Table of Contents
1. [Scenario 1: High-Traffic Web Server (Nginx / Apache) on Linux](#scenario-1-high-traffic-web-server-nginx--apache-on-linux)
2. [Scenario 2: Windows Server IIS & .NET Application Log Retention](#scenario-2-windows-server-iis--net-application-log-retention)
3. [Scenario 3: Automated Database Backup & Dump Purging](#scenario-3-automated-database-backup--dump-purging)
4. [Scenario 4: CI/CD Runner Artifact and Workspace Pruning](#scenario-4-cicd-runner-artifact-and-workspace-pruning)

---

## Scenario 1: High-Traffic Web Server (Nginx / Apache) on Linux

### Problem
A cluster of Nginx web servers generates 5-10 GB of access and error logs daily. Without regular maintenance, the root disk partition fills up, crashing Nginx and preventing system monitoring daemons from functioning.

### Solution Architecture
Deploy `cleanup_logs.sh` via an automated daily cron job to retain 14 days of logs, with a dedicated persistent audit log file for compliance audits.

### Directory Layout
```text
/var/log/nginx/
├── access.log (active)
├── error.log (active)
├── access.2026-08-01.log (old - eligible for purge)
├── access.2026-08-02.log (old - eligible for purge)
└── error.2026-08-18.log (recent - retained)
```

### Production Cron Configuration
Add the following job to `/etc/cron.d/nginx-log-cleanup`:
```cron
# Run daily at 03:00 AM UTC
0 3 * * * root /usr/local/bin/cleanup_logs.sh -d /var/log/nginx -t 14 -p "*.log" -l /var/log/cleanup_audit.log >/dev/null 2>&1
```

### Execution Verification (Dry-Run Preview)
```bash
./cleanup_logs.sh -d /var/log/nginx -t 14 -n
```

---

## Scenario 2: Windows Server IIS & .NET Application Log Retention

### Problem
An enterprise Windows Server running multiple IIS Application Pools stores request logs in nested folders under `C:\inetpub\logs\LogFiles\W3SVC1` and `W3SVC2`. Log files older than 30 days must be purged recursively without deleting active configuration files.

### Solution Architecture
Use `cleanup_logs.ps1` with the `-Recursive` switch, targeting `*.log` files older than 30 days and logging results to `C:\Logs\iis_cleanup_audit.log`.

### PowerShell Execution Command
```powershell
.\cleanup_logs.ps1 -LogDirectory "C:\inetpub\logs\LogFiles" -Days 30 -Pattern "*.log" -Recursive -LogFile "C:\Logs\iis_cleanup_audit.log"
```

### Automated Task Scheduler Setup via PowerShell
```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\Scripts\cleanup_logs.ps1 -LogDirectory C:\inetpub\logs\LogFiles -Days 30 -Recursive -LogFile C:\Logs\iis_cleanup.log"

$Trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "DailyIISLogCleanup" -Description "Retains 30 days of IIS logs"
```

---

## Scenario 3: Automated Database Backup & Dump Purging

### Problem
A PostgreSQL or MySQL server performs daily logical dumps (`db_backup_YYYYMMDD.sql.gz`). While recent backups must be preserved locally for rapid disaster recovery, backups older than 7 days should be purged to keep storage utilization under 70%.

### Solution Architecture
Run `cleanup_logs.sh` with a custom file pattern matching `*.sql.gz` or `*.dump` and a minimum size threshold (`-m 50` for files $\ge 50$ MB).

### Command
```bash
# Purge database backups older than 7 days exceeding 50 MB
./cleanup_logs.sh -d /var/backups/postgres -t 7 -p "*.sql.gz" -m 50 -l /var/log/backup_cleanup.log
```

---

## Scenario 4: CI/CD Runner Artifact and Workspace Pruning

### Problem
Self-hosted GitHub Actions and GitLab CI runners accumulate build logs, diagnostic files, and test output in runner workspaces. Disk saturation causes subsequent pipeline runs to fail with `No space left on device`.

### Solution Architecture
Integrate `cleanup_logs.sh` into a weekly maintenance cron or runner cleanup maintenance job to recursively remove all logs older than 3 days.

### Command
```bash
./cleanup_logs.sh -d /opt/actions-runner/_work -t 3 -p "*.log" -r -v
```

