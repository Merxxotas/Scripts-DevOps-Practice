# Log Rotation and Compression - Technical Specification

## 1. System Overview

The **Log Rotation and Compression Utility** is a cross-platform maintenance solution that
rotates a single log file when it grows beyond a size threshold: it shifts existing rotated
backups, compresses the current log into the first backup slot, truncates the active log, and
prunes backups older than the retention count. It runs on POSIX Bash (Linux/macOS) and
PowerShell (Windows), with 100% feature parity. No third-party dependencies beyond the shell
and the standard compression tooling (`gzip` on Bash, `Compress-Archive` on PowerShell).

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate log file path, max size, backup count                               |
|  - Safety guardrail: refuse protected system roots                             |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Size Check                                      |
|  - Stat the log file; if size <= threshold and not --force: no-op, exit 0       |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Dry-Run Gate                                    |
|  - If --dry-run: print planned renames/compression/truncation/pruning, exit 0  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Rotation                                        |
|  - Shift backups: .<i>.<ext> -> .<i+1>.<ext> (from highest down)              |
|  - Copy current log to .1.<ext>, compress when enabled                         |
|  - Truncate current log to zero bytes                                          |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Retention                                       |
|  - Remove any backup with index > backup-count                                 |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             6. Telemetry & Summary                             |
|  - Print colorized execution summary                                           |
|  - Write ISO-8601 audit log entry (if --audit-log)                             |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

### Design Principles
1. **Zero External Dependencies**: only core OS utilities (`stat`, `cp`, `mv`, `rm`, `gzip` on Bash; standard .NET / PowerShell runtime on Windows).
2. **Safety First**: destructive operations (truncation, deletion) are guarded against protected system roots and require an existing, regular log file.
3. **Dry-Run**: preview every planned action without mutating anything.
4. **Observable & Auditable**: every rotation is traceable through console output and an optional audit log.

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-f, --log-file` | `-LogFile` | `/var/log/app/application.log` / `C:\Logs\application.log` | Target log file |
| `-m, --max-size-mb` | `-MaxSizeMB` | `10` | Rotation threshold in MB |
| `-c, --backup-count` | `-BackupCount` | `5` | Number of rotated backups to retain |
| `-z, --compress` | `-Compress` | on | Compress the rotated backup |
| `--no-compress` | `-NoCompress` | off | Keep the rotated backup raw |
| `--force` | `-Force` | off | Rotate regardless of size |
| `--dry-run` | `-DryRun` | off | Preview only |
| `--audit-log` | `-AuditLog` | (none) | ISO-8601 audit log path |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (rotation performed, no-op, or dry-run) |
| 1 | Configuration or safety violation |
| 2 | Partial failure (a rename, compression, truncation or prune step failed) |

---

## 5. Safety Guardrails

- **Path blacklist:** refuse to operate when the log file's resolved directory is a protected system root (`/`, `/etc`, `/var`, `/bin`, `/sbin`, `/usr`, `/boot`, `/dev`, `/proc`, `/sys`, `/root`, `/tmp`, `/home`, `/Library`, `/System`, `/Applications`, `/Volumes` on POSIX; `C:\`, `C:\Windows`, `C:\Program Files`, `C:\Users`, `C:\ProgramData` on Windows).
- **Existence:** the log file must exist and be a regular file (not a directory).
- **Backup count:** must be a positive integer.
- **Max size:** must be a non-negative integer.
- **Dry-run:** no rename, compression, truncation or deletion.

---

## 6. Compression

- Bash: `gzip` (`.log.1.gz`).
- PowerShell: `Compress-Archive` (`.log.1.zip`).
- Both remove the intermediate raw copy after successful compression.
- `--no-compress` keeps the raw `.log.1` file and no compression is attempted.

---

## 7. Retention

After rotation, only the most recent `backup-count` backups are kept (indices 1..N). Any backup with index > N is removed. A partial failure (a file that could not be removed) exits 2.

---

## 8. Audit Log

When `--audit-log` is given, an ISO-8601 timestamped line is appended per run recording the
outcome and the backup file. The log file's content is never written. Write failures are
best-effort and do not change the exit code.

---

## 9. Scope Exclusions (v1)

No time-based or date-stamped rotation, no copy-truncate vs. create-new choice, no post-rotation
hook or signal (e.g. `copytruncate`/`create`), no compression of already-rotated backups, no
`--json`/`--csv` output. One log file per invocation. Audit write is best-effort.