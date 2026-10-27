# Database Backup Utility — Bash vs PowerShell Architecture Comparison

The Database Backup Utility is implemented in both **POSIX Bash** (`db_backup.sh`) and
**PowerShell** (`db_backup.ps1`). Both are the same program with two coats of paint: one
contract, one set of exit codes, one audit format, one retention rule. This document separates
what the two implementations **must** share from what they **may** differ on.

The module runs one database dump per invocation, compresses the result, stores it in a backup
directory, and prunes backups older than a retention window. It never opens a network socket of
its own: the dump tool (`mysqldump` / `pg_dump`) is an external command resolved on `PATH`.

---

## Feature & Architecture Matrix

| Dimension | POSIX Bash (`db_backup.sh`) | PowerShell (`db_backup.ps1`) |
| :--- | :--- | :--- |
| **Primary platform** | Linux, macOS | Windows (also Linux/macOS via PowerShell 7) |
| **Runtime** | Bash 4.0+ | PowerShell 5.1+ / 7+ |
| **Dump tool (MySQL)** | `mysqldump` | `mysqldump` |
| **Dump tool (PostgreSQL)** | `pg_dump` | `pg_dump` |
| **Compression** | `gzip` (`.sql.gz`) | `Compress-Archive` (`.sql.zip`) |
| **Retention source** | `find ... -mtime` | `Get-ChildItem` filtered by `LastWriteTime` |
| **Parameter syntax** | GNU-style flags: `-t`, `--db-type` | Named parameters: `-DbType` |
| **Verbosity** | `-v` / `--verbose` (own flag) | `-Verbose` (a PowerShell common parameter) |
| **Dry run** | `--dry-run` | `-DryRun` (`[switch]`) |
| **Help** | `-h` / `--help` | `-Help` (`[switch]`) |
| **Credential passing** | `MYSQL_PWD` / `PGPASSWORD` env var | `MYSQL_PWD` / `PGPASSWORD` env var |
| **Error output** | `>&2` | `[Console]::Error.WriteLine` |
| **Tool lookup** | `command -v` | `Get-Command` |

---

## Where the Two Implementations Are Identical

Parity is a repository invariant. The same flags, the same defaults, the same validation, the same
exit codes and the same messages. The table below is the **contract**; neither implementation may
drift from it.

| Contract element | Shared behaviour |
| :--- | :--- |
| **Option count** | 12 options, one behaviour per option |
| **Default db type** | `mysql` |
| **Default db name** | `mydatabase` |
| **Default db user** | `backup_user` |
| **Default backup dir** | `./backups` (Bash) / `C:\Backups\Database` (PowerShell) |
| **Default retention** | `7` days |
| **Default compress** | on |
| **Exit codes** | `0` success / `1` configuration/safety error / `2` partial failure |
| **Failure ordering** | Parse, resolve credentials, validate, guardrail, dump, compress, retain |
| **Credential precedence** | `--db-password` -> `DB_BACKUP_PASSWORD` env -> (none) |
| **Credential secrecy** | never echoed, never logged in full; passed via native env var |
| **Path blacklist** | refuses system paths as the backup directory |
| **Dry run** | prints planned actions; touches nothing; exits `0` |
| **Audit format** | `<ISO-8601 UTC> [<LEVEL>] <message>`, one line per event, appended |
| **Backup filename** | `<dbtype>_<dbname>_<YYYYMMDD_HHMMSS>.sql` |
| **Retention glob** | `*.sql`, `*.sql.gz`, `*.zip` by mtime |

Both suites assert the same scenario matrix against the same public interface, and the parity
test compares the two declarations, so a divergence in any row above is a test failure.

---

## Where They Legitimately Differ

These differences are **required by the platform**, not accidental.

| # | Difference | Why it must differ |
| :-- | :-- | :--- |
| 1 | **Compression format** | `gzip` ships on every POSIX host; PowerShell's native archive cmdlet is `Compress-Archive` (zip). Both remove the raw `.sql` after success. |
| 2 | **Retention enumeration** | `find -mtime` is the POSIX idiom; PowerShell filters `Get-ChildItem` by `LastWriteTime`. Both use mtime and the same glob. |
| 3 | **Default backup dir** | `./backups` is idiomatic on Unix; `C:\Backups\Database` is idiomatic on Windows. |
| 4 | **Verbosity flag** | `-Verbose` is already a PowerShell common parameter, so the script captures it once at script scope. Bash needs its own `-v`. |
| 5 | **Parameter syntax** | Bash has no named parameters; PowerShell has no `--long-options`. The *set* of behaviours is identical. |
| 6 | **Db-type alias** | Bash accepts `postgres` as an alias for `postgresql`; PowerShell accepts the same. Both normalise to `postgresql`. |

---

## Design Decisions

### 1. Credentials never reach the process list

The password is resolved from `--db-password` or `DB_BACKUP_PASSWORD`, then handed to the dump tool
through its native environment variable (`MYSQL_PWD` for MySQL, `PGPASSWORD` for PostgreSQL). It is
never placed on the command line, so it does not appear in `ps` and is never written to the audit
log.

### 2. Validate before dumping

The configuration is fully validated -- db type, db name, db user, retention, password, backup dir
blacklist and writability -- **before** the dump tool is invoked. A broken configuration is
reported at deployment time, not at 03:00 when the backup is scheduled.

### 3. One database per invocation

The module backs up exactly one database per run. Scheduling one job per database keeps the
failure domain small: a failed dump for one database does not abort the others.

### 4. Retention is best-effort per file

Each old backup is deleted individually. A single file that cannot be removed is counted as a
partial failure (exit `2`) but does not abort the rest of the pruning. The audit log records both
the pruned count and the failures.

### 5. Dry run is a genuine rehearsal

`--dry-run` resolves the dump tool, builds the target filename and prints the planned compression
and pruning -- but invokes nothing and touches the filesystem. It exits `0`.

### 6. Audit write is best-effort

A failing audit write never breaks the backup. A backup tool that dies because its log directory
is read-only stops backing up, which is worse than a missing audit line.

---

## When to Use Which Implementation?

| Use case | Recommended engine | Justification |
| :--- | :--- | :--- |
| **Linux/macOS servers, cron/systemd** | **Bash (`db_backup.sh`)** | Zero startup overhead, native cron integration, `gzip` is already there. |
| **Windows Server / Task Scheduler** | **PowerShell (`db_backup.ps1`)** | Native Windows scheduling, `Compress-Archive` is built in. |
| **Fleet with both Unix and Windows hosts** | **Both** | Identical flags, defaults, validation and exit codes; the same runbook drives both. |
| **Container / CI** | **Bash (`db_backup.sh`)** | Smallest footprint; the dump tool is the only dependency. |

---

## Related Documents

- [SCENARIOS.md](SCENARIOS.md) -- operational failure modes and their exit codes.
- [Lab 1 -- Backup & Dry Run](labs/LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 2 -- Exit Codes & Retention](labs/LAB2_EXIT_CODES_AND_RETENTION.md)
- [Lab 3 -- Scheduling in Production](labs/LAB3_PRODUCTION_SCHEDULING.md)
- [../README.md](../README.md) -- usage, flags and troubleshooting.
- [../SPECS.md](../SPECS.md) -- technical specification.
