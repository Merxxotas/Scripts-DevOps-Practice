# Lab 2: Recursive Traversal & Size Threshold Filtering 📁

## Objective
Learn how to manage complex, multi-tiered microservice log directories by combining recursive directory traversal (`-r`), glob patterns (`-p`), and minimum file size filters (`-m`).

---

## 📋 Prerequisites
- A Linux/macOS shell or Windows PowerShell environment.
- Completed [Lab 1: Basic Retention & Dry-Run Preview](LAB1_BASIC_RETENTION_AND_DRYRUN.md).

---

## Step 1: Create Nested Directory Tree

Set up a simulated microservices architecture with subdirectories and logs of varying sizes and ages.

### Linux / macOS:
```bash
mkdir -p /tmp/lab2_services/{auth,billing,worker}

# Create small and large old logs (> 40 days old)
dd if=/dev/zero of=/tmp/lab2_services/auth/small_old.log bs=1K count=100 2>/dev/null      # 100 KB
dd if=/dev/zero of=/tmp/lab2_services/billing/large_old.log bs=1M count=15 2>/dev/null   # 15 MB
dd if=/dev/zero of=/tmp/lab2_services/worker/large_old.log bs=1M count=25 2>/dev/null    # 25 MB
dd if=/dev/zero of=/tmp/lab2_services/root_old.log bs=1M count=5 2>/dev/null             # 5 MB

# Create recent active files
echo "active auth" > /tmp/lab2_services/auth/active.log
echo "active billing" > /tmp/lab2_services/billing/active.log

# Backdate old files to 45 days ago
touch -t 202606010000 /tmp/lab2_services/auth/small_old.log
touch -t 202606010000 /tmp/lab2_services/billing/large_old.log
touch -t 202606010000 /tmp/lab2_services/worker/large_old.log
touch -t 202606010000 /tmp/lab2_services/root_old.log
```

---

## Step 2: Compare Flat vs. Recursive Scans

### Flat Scan (Default Behavior):
```bash
./cleanup_logs.sh -d /tmp/lab2_services -t 30 -n
```
*Result:* Only `/tmp/lab2_services/root_old.log` is targeted (1 file, 5.00 MB). All nested subdirectory files are safely ignored.

### Recursive Scan (`-r` / `-Recursive`):
```bash
./cleanup_logs.sh -d /tmp/lab2_services -t 30 -r -n
```
*Result:* All 4 stale files across `auth/`, `billing/`, and `worker/` are detected, totaling ~45.10 MB of candidate storage.

---

## Step 3: Apply Minimum Size Threshold Filter

Suppose you only want to purge stale logs that exceed **10 Megabytes** in size, preserving smaller diagnostic logs for investigation.

### Run with `-m 10` (Files $\ge 10$ MB):
```bash
./cleanup_logs.sh -d /tmp/lab2_services -t 30 -r -m 10 -n -v
```

### PowerShell Equivalent:
```powershell
.\cleanup_logs.ps1 -LogDirectory "$env:TEMP\lab2_services" -Days 30 -Recursive -MinSizeMB 10.0 -DryRun -Verbose
```

### Output Observation:
```text
Scanning target files...
[SKIP - SIZE] /tmp/lab2_services/auth/small_old.log is below minimum size threshold (100.00 KB < 10 MB)
[SKIP - SIZE] /tmp/lab2_services/root_old.log is below minimum size threshold (5.00 MB < 10 MB)
[DRY RUN] Would delete: /tmp/lab2_services/billing/large_old.log (15.00 MB, 79 days old)
[DRY RUN] Would delete: /tmp/lab2_services/worker/large_old.log (25.00 MB, 79 days old)

============================================================
                    Execution Summary                       
============================================================
Total Files Scanned : 6
Eligible for Purge  : 2
Files Processed     : 2
Failed Deletions    : 0
Storage Reclaimed   : 40.00 MB
============================================================
```

---

## Step 4: Execute Live Purge with Reclaimed Storage Verification
```bash
./cleanup_logs.sh -d /tmp/lab2_services -t 30 -r -m 10
```

Verify that the 15 MB and 25 MB files are purged, while the small 100 KB and 5 MB logs remain intact.

---

## Step 5: Clean Up Lab Environment
```bash
rm -rf /tmp/lab2_services
```

