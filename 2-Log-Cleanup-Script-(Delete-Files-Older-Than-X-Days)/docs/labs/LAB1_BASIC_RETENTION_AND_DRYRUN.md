# Lab 1: Basic Retention Policy & Dry-Run Preview 🧪

## Objective
Learn how to safely inspect, evaluate, and purge stale log files using retention thresholds and dry-run simulation mode without risking accidental file deletion.

---

## 📋 Prerequisites
- A Linux/macOS shell with Bash 4+ or a Windows workstation with PowerShell 5.1+.
- Execution permissions on `cleanup_logs.sh` or `cleanup_logs.ps1`.

---

## Step 1: Set Up the Mock Test Environment

Create a temporary sandbox directory with a mix of stale logs (older than 30 days) and active recent logs.

### Linux / macOS (Bash)
```bash
# Create sandbox directory
mkdir -p /tmp/lab1_logs

# Create sample log files
echo "Active server log" > /tmp/lab1_logs/app.log
echo "Recent access log" > /tmp/lab1_logs/access_2026-08-15.log
echo "Stale debug log" > /tmp/lab1_logs/debug_2026-06-01.log
echo "Stale error log" > /tmp/lab1_logs/error_2026-05-10.log

# Manipulate modification timestamps for stale files (45+ days old)
touch -t 202606010000 /tmp/lab1_logs/debug_2026-06-01.log
touch -t 202605100000 /tmp/lab1_logs/error_2026-05-10.log
```

### Windows (PowerShell)
```powershell
$LabDir = "$env:TEMP\lab1_logs"
New-Item -ItemType Directory -Path $LabDir -Force | Out-Null

Set-Content -Path "$LabDir\app.log" -Value "Active server log"
Set-Content -Path "$LabDir\access_2026-08-15.log" -Value "Recent access log"
Set-Content -Path "$LabDir\debug_2026-06-01.log" -Value "Stale debug log"
Set-Content -Path "$LabDir\error_2026-05-10.log" -Value "Stale error log"

# Set LastWriteTime to 45 and 60 days in the past
(Get-Item "$LabDir\debug_2026-06-01.log").LastWriteTime = (Get-Date).AddDays(-45)
(Get-Item "$LabDir\error_2026-05-10.log").LastWriteTime = (Get-Date).AddDays(-60)
```

---

## Step 2: Execute Dry-Run Simulation

Simulate a 30-day retention cleanup. The dry-run switch (`-n` / `-DryRun`) outputs candidate files and projected storage savings without deleting anything.

### Bash:
```bash
./cleanup_logs.sh -d /tmp/lab1_logs -t 30 -n
```

### PowerShell:
```powershell
.\cleanup_logs.ps1 -LogDirectory "$env:TEMP\lab1_logs" -Days 30 -DryRun
```

### Expected Output:
```text
============================================================
                DevOps Log Cleanup Utility                  
============================================================
Target Directory : /tmp/lab1_logs
Retention Policy : Older than 30 days
Matching Pattern : *.log
Min Size Filter  : 0 MB
Recursive Scan   : false
Execution Mode   : DRY RUN (Simulation)

Scanning target files...
[DRY RUN] Would delete: /tmp/lab1_logs/debug_2026-06-01.log (16 B, 79 days old)
[DRY RUN] Would delete: /tmp/lab1_logs/error_2026-05-10.log (16 B, 101 days old)

============================================================
                    Execution Summary                       
============================================================
Total Files Scanned : 4
Eligible for Purge  : 2
Files Processed     : 2
Failed Deletions    : 0
Storage Reclaimed   : 32 B
============================================================
```

Verify that all files are still present on disk:
```bash
ls -la /tmp/lab1_logs
```

---

## Step 3: Execute Live Purge

Now execute the live cleanup without the simulation switch:

### Bash:
```bash
./cleanup_logs.sh -d /tmp/lab1_logs -t 30
```

### PowerShell:
```powershell
.\cleanup_logs.ps1 -LogDirectory "$env:TEMP\lab1_logs" -Days 30
```

### Verification:
List the remaining files in the directory:
```bash
ls -la /tmp/lab1_logs
```

Only `app.log` and `access_2026-08-15.log` remain. Both stale files have been purged.

---

## Step 4: Cleanup Lab Resources
```bash
rm -rf /tmp/lab1_logs
```

