# Log Cleanup Utility - Technical Specification

## 1. System Overview

The **Log Cleanup Utility** is an enterprise-grade, cross-platform maintenance solution designed to automate log retention, directory purging, and storage reclamation across Linux, macOS, and Windows environments.

Rather than relying on generic shell one-liners, this utility provides:
- Deterministic, timestamp-based file age evaluation.
- Multi-layer safety guardrails preventing accidental deletion of critical system paths.
- Recursive and flat directory traversal capabilities.
- Size-based filtering and aggregate storage reclamation reporting.
- Non-destructive dry-run simulation mode.
- Complete parity between POSIX Bash (`cleanup_logs.sh`) and Windows PowerShell (`cleanup_logs.ps1`) with zero third-party dependencies.

---

## 2. Core Architecture & Design Principles

The utility follows a modular, pipeline-driven processing architecture:

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Verify directory existence & accessibility                                  |
|  - Blacklist check: Disallow root & critical system paths                      |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Discovery & Filter                              |
|  - Traverse directory (flat or recursive based on flag)                        |
|  - Filter by glob pattern (default: *.log)                                     |
|  - Filter by age threshold (cutoff = CurrentTime - Days)                       |
|  - Filter by minimum file size (optional threshold in MB)                      |
|  - Exclude symbolic links pointing outside boundaries                          |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Space & Accounting                              |
|  - Query file size in bytes                                                    |
|  - Accumulate total candidate file count & aggregate byte count                |
|  - Format human-readable units (Bytes, KB, MB, GB)                             |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Execution & Action                              |
|  - If DryRun == True: Log candidate path and projected size without mutation   |
|  - If DryRun == False: Delete file, trap errors, increment deleted count       |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Telemetry & Summary                             |
|  - Print formatted colorized execution summary table                           |
|  - Write structured audit log entry (if logfile specified)                     |
|  - Return standardized process exit code                                       |
+--------------------------------------------------------------------------------+
```

### Design Principles
1. **Zero External Dependencies**: Uses only core operating system utilities (POSIX coreutils for Bash, standard .NET / PowerShell 5.1+ runtime).
2. **Safety First**: Destructive operations require explicit target confirmation and refuse to execute on blacklisted or ambiguous paths.
3. **Idempotency**: Repeated executions under identical conditions leave the system in a clean, predictable state without errors.
4. **Observable & Auditable**: Every scanned, skipped, or deleted file is traceable through standard output and optional file logging.

---

## 3. Technology Stack & Runtime Requirements

| Component | Linux / macOS Target | Windows Target |
| :--- | :--- | :--- |
| **Primary Script** | `cleanup_logs.sh` | `cleanup_logs.ps1` |
| **Runtime Interpreter** | Bash 4.0+ (POSIX-compatible fallback for 3.2 on macOS) | PowerShell 5.1+ (Windows PowerShell & PowerShell 7+) |
| **Core Utilities** | `find`, `stat`, `date`, `rm`, `awk` / `bc` | `Get-ChildItem`, `Remove-Item`, `Measure-Object` |
| **External Dependencies** | None (100% native) | None (100% native) |

---

## 4. Command-Line Interface (CLI) Specifications

Both implementations share identical operational flags and behaviors.

### 4.1 Bash Implementation (`cleanup_logs.sh`)

```bash
Usage: ./cleanup_logs.sh -d <path> [-t <days>] [-p <pattern>] [-m <min_size_mb>] [-r] [-n] [-l <log_file>] [-v] [-h]
```

| Flag | Long Option Equivalent | Description | Default Value | Required |
| :--- | :--- | :--- | :--- | :--- |
| `-d <path>` | `--dir <path>` | Target directory to clean | None | **Yes** |
| `-t <days>` | `--days <days>` | Retention threshold in days (files older than X days) | `30` | No |
| `-p <pattern>` | `--pattern <pattern>`| File matching glob pattern | `*.log` | No |
| `-m <mb>` | `--min-size <mb>` | Minimum file size threshold in Megabytes | `0` (any size) | No |
| `-r` | `--recursive` | Scan directory and all subdirectories recursively | `false` (flat) | No |
| `-n` | `--dry-run` | Simulation mode: preview actions without deleting | `false` | No |
| `-l <file>` | `--log-file <file>` | Append execution results and audit log to file | None | No |
| `-v` | `--verbose` | Enable verbose diagnostic output per file | `false` | No |
| `-h` | `--help` | Display command usage and examples | N/A | No |

### 4.2 PowerShell Implementation (`cleanup_logs.ps1`)

```powershell
Syntax:
.\cleanup_logs.ps1 -LogDirectory <String> [-Days <Int32>] [-Pattern <String>] 
                   [-MinSizeMB <Double>] [-Recursive] [-DryRun] 
                   [-LogFile <String>] [-Verbose]
```

| Parameter | Type | Description | Default Value | Required |
| :--- | :--- | :--- | :--- | :--- |
| `-LogDirectory` | `[string]` | Target directory path to clean | None | **Yes** (Positional 0) |
| `-Days` | `[int]` | Retention threshold in days | `30` | No |
| `-Pattern` | `[string]` | File matching glob filter | `"*.log"` | No |
| `-MinSizeMB` | `[double]` | Minimum file size in MB to qualify for cleanup | `0.0` | No |
| `-Recursive` | `[switch]` | Scan recursively through child directories | `$false` | No |
| `-DryRun` | `[switch]` | Preview files to be deleted without removing | `$false` | No |
| `-LogFile` | `[string]` | Path to persistent audit logfile | `$null` | No |
| `-Verbose` | `[switch]` | Standard PowerShell switch for verbose stream | `$false` | No |

---

## 5. Safety Guardrails & System Protection Rules

To prevent accidental data loss or catastrophic operating system corruption, both scripts enforce the following safety checks before executing any scan or deletion:

1. **Root Directory Protection (Blacklist)**:
   The script refuses execution and exits immediately with code `1` if the target directory is:
   - **Linux / macOS**: `/`, `/bin`, `/sbin`, `/usr`, `/usr/bin`, `/etc`, `/dev`, `/proc`, `/sys`, `/boot`, `/root`, `/var` (root level), `/var/log` without subfolder or explicit override.
   - **Windows**: `C:\`, `C:\Windows`, `C:\Windows\System32`, `C:\Program Files`, `C:\Program Files (x86)`, `C:\Users`, `C:\ProgramData` (root level).

2. **Existence & Directory Type Check**:
   - The path must exist and resolve to a valid directory (not a regular file or broken block device).
   - Read and write permissions are tested before initiating file deletion.

3. **Symbolic Link Policy**:
   - Symbolic links pointing to directories outside the target tree will NOT be traversed during recursive mode.
   - Only regular files (`-type f` / `[System.IO.FileInfo]`) matching the age criteria are targeted.

---

## 6. Space Calculation & Metric Aggregation

To provide transparent DevOps reporting, the utility aggregates storage statistics during the scan:

- **Unit Normalization**: File sizes are accumulated in raw bytes and dynamically formatted into human-readable strings:
  - $< 1024 \text{ B} \rightarrow \text{B}$
  - $\ge 1024 \text{ B} \text{ and } < 1024^2 \text{ B} \rightarrow \text{KB}$
  - $\ge 1024^2 \text{ B} \text{ and } < 1024^3 \text{ B} \rightarrow \text{MB}$
  - $\ge 1024^3 \text{ B} \rightarrow \text{GB}$
- **Metrics Collected**:
  - `Total Files Scanned`: Count of all files matching the pattern in the directory.
  - `Eligible Files`: Count of files exceeding the age and size threshold.
  - `Deleted Files`: Count of successfully removed files (or simulated deletions in dry-run).
  - `Failed Deletions`: Count of files that could not be deleted due to permission locks or I/O errors.
  - `Total Space Reclaimed`: Cumulative size of deleted (or simulated) files.

---

## 7. Logging & Auditability System

### 7.1 Console Output (Standard Stream)
- Colorized status headers, scan progress indicators, and individual file action logs:
  - Green (`✓`) for successful deletions.
  - Yellow (`[DRY RUN]`) for simulated actions.
  - Red (`✗`) for errors and failed deletions.
  - Cyan for target paths and metric summaries.

### 7.2 File Logging (Audit Trail)
When `-l / -LogFile` is supplied, entries are appended in standard ISO-8601 format:
```text
2026-08-19T14:30:00Z [INFO] Log cleanup initiated for directory: /var/log/nginx (Retention: 30 days, Pattern: *.log, Recursive: true, DryRun: false)
2026-08-19T14:30:01Z [INFO] DELETED: /var/log/nginx/access.2026-07-01.log (Size: 45.20 MB, Age: 49 days)
2026-08-19T14:30:01Z [INFO] DELETED: /var/log/nginx/error.2026-06-15.log (Size: 2.10 MB, Age: 65 days)
2026-08-19T14:30:02Z [INFO] Cleanup summary: Scanned=14, Eligible=2, Deleted=2, Failed=0, SpaceReclaimed=47.30 MB
```

---

## 8. Exit Codes & Error Handling

Standardized exit codes ensure seamless integration with CI/CD runners, cron daemons, and alert monitors:

| Exit Code | Meaning | Condition |
| :---: | :--- | :--- |
| `0` | **Success** | Cleanup finished with 0 errors (including clean dry-run runs). |
| `1` | **Configuration / Safety Error** | Invalid arguments, non-existent path, permission denied, or target is a protected system directory. |
| `2` | **Partial Failure** | One or more eligible files could not be deleted (e.g., file lock, transient permission error). |

---

## 9. CI/CD Pipeline & Automated Testing

### 9.1 Monorepo Segregation
The GitHub Actions workflow is isolated to this module:
- **File**: `.github/workflows/ci-cleanup-logs.yml`
- **Trigger Filter**: Paths matching `'2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/**'`.

### 9.2 Quality Gates & Automated Test Matrix
- **Static Analysis / Linting**:
  - ShellCheck (`shellcheck -x cleanup_logs.sh`) for POSIX / Bash standards.
  - PSScriptAnalyzer (`Invoke-ScriptAnalyzer`) for PowerShell best practices and rule compliance.
- **Cross-Platform Matrix Testing**:
  - `ubuntu-24.04`: Unit & integration tests for Bash script with mock temporary directory trees and manipulated timestamps.
  - `macos-14`: Validation of BSD `stat` and `date` compatibility in Bash.
  - `windows-2022`: Unit & integration tests for PowerShell script testing file locks, read-only attributes, and recursion.

