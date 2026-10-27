# Database Backup Utility - Technical Specification

## 1. System Overview

The **Database Backup Utility** is a cross-platform maintenance solution that automates
database dumps, compression, storage and retention for MySQL and PostgreSQL. It runs a
dump, compresses the result, stores it in a backup directory, and prunes backups older
than a retention window. Credentials come from a flag or an environment variable and
are never hardcoded, echoed or written to the audit log in full.

Available in **POSIX Bash** for Linux / macOS and **PowerShell** for Windows, with 100%
feature parity. No third-party dependencies beyond the database client itself.

---

## 2. Core Architecture & Design Principles

```
+--------------------------------------------------------------------------------+
|                             1. Input & Validation                              |
|  - Parse CLI flags / parameters                                                |
|  - Validate db type, db name, db user, retention days                          |
|  - Resolve password from flag or DB_BACKUP_PASSWORD                            |
|  - Blacklist check: disallow system paths as backup directory                 |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             2. Dry-Run Gate                                    |
|  - If --dry-run: print planned actions, exit 0, touch nothing                  |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             3. Dump                                            |
|  - Create backup directory (if missing)                                        |
|  - Verify dump tool is on PATH (mysqldump / pg_dump)                           |
|  - Invoke dump tool with credentials via native env var                        |
|  - Write raw .sql file                                                         |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             4. Compression                                     |
|  - gzip on Bash, zip (Compress-Archive) on PowerShell                          |
|  - Remove raw .sql after successful compression                                |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             5. Retention                                       |
|  - Find backups older than retention-days (by mtime) in backup dir            |
|  - Delete each; count pruned and failed                                        |
+---------------------------------------+----------------------------------------+
                                        |
                                        v
+--------------------------------------------------------------------------------+
|                             6. Telemetry & Summary                             |
|  - Print colorized execution summary                                           |
|  - Write ISO-8601 audit log entry (if --log-file)                              |
|  - Return standardized exit code                                               |
+--------------------------------------------------------------------------------+
```

---

## 3. CLI Reference

| Flag (Bash) | Param (PowerShell) | Default | Description |
| :--- | :--- | :--- | :--- |
| `-t, --db-type` | `-DbType` | `mysql` | `mysql` or `postgresql` |
| `-n, --db-name` | `-DbName` | `mydatabase` | Database name |
| `-u, --db-user` | `-DbUser` | `backup_user` | Database user |
| `--db-password` | `-DbPassword` | (env) | Password; falls back to `DB_BACKUP_PASSWORD` |
| `-d, --backup-dir` | `-BackupDir` | `./backups` / `C:\Backups\Database` | Storage directory |
| `-r, --retention-days` | `-RetentionDays` | `7` | Delete backups older than N days |
| `-c, --compress` | `-Compress` | on | Compress the backup |
| `--no-compress` | `-NoCompress` | off | Do not compress |
| `--dry-run` | `-DryRun` | off | Preview only |
| `-l, --log-file` | `-LogFile` | (none) | ISO-8601 audit log |
| `-v, --verbose` | `-Verbose` | off | Diagnostic output |
| `-h, --help` | `-Help` | off | Show help, exit 0 |

---

## 4. Exit Codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success (backup created, compressed, retention applied) |
| 1 | Configuration or safety violation |
| 2 | Partial failure (dump, compression or retention step failed) |

---

## 5. Credential Handling

The password is resolved in this order: `--db-password` flag → `DB_BACKUP_PASSWORD` environment
variable. It is never hardcoded, never echoed, never logged in full. It is passed to the dump tool
via its native environment variable (`MYSQL_PWD`, `PGPASSWORD`) so it does not appear in `ps`.

A missing password is a configuration error (exit 1).

---

## 6. Safety Guardrails

- **Path blacklist:** refuse `/`, `C:\`, `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/lib`,
  `/lib64`, `/boot`, `/dev`, `/proc`, `/sys`, `/root`, `C:\Windows`, `C:\Program Files`,
  `C:\Users`.
- **Backup dir:** must be creatable and writable.
- **Dry-run:** no dump, no compression, no deletion.
- **Exit codes:** documented and consistent.

---

## 7. Compression

- Bash: `gzip` (`.sql.gz`).
- PowerShell: `Compress-Archive` (`.sql.zip`).
- Both remove the raw `.sql` after successful compression.

---

## 8. Retention

Backups older than `retention-days` (by mtime) matching `*.sql` / `*.sql.gz` / `*.zip` are
deleted. A partial failure (some files could not be deleted) exits 2.

---

## 9. Audit Log

When `--log-file` is given, an ISO-8601 timestamped line is appended per run recording the
outcome, the backup file, and pruned files. The password is never written.

---

## 10. Scope Exclusions (v1)

No incremental/differential backups, no cloud streaming, no MSSQL, no encryption of the backup
file, no `--json`/`--csv` output. One database per invocation. Audit write is best-effort.

---

## 11. Testing Strategy

Tests stub `mysqldump`/`pg_dump` on `PATH` so no real database is needed. Suites assert flags,
exit codes, emitted files, dry-run, guardrails, retention pruning, audit log and credential
handling. Parity tests compare the two implementations' flag sets.