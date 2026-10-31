# 16. Automated Database Backup — Overview & Specs

> Module 3 of the [Scripts-DevOps-Practice](https://github.com/Merxxotas/Scripts-DevOps-Practice)
> monorepo: a cross-platform database backup utility that runs a dump, compresses the result,
> stores it in a backup directory, and prunes backups older than a retention window.

---

## What it is

A **backup creator and rotator**, not a scheduler. The module runs one database dump per
invocation, compresses it, stores it, and prunes old archives. It ships as Bash + PowerShell
with full parity, plus tests, docs, CI and wiki pages.

| Concern | Value |
| :--- | :--- |
| Implementations | `db_backup.sh` (Bash) · `db_backup.ps1` (PowerShell) |
| Backends | MySQL (`mysqldump`) · PostgreSQL (`pg_dump`) |
| Databases per run | one |
| Compression | gzip (Bash) · zip (PowerShell) |
| Retention | by mtime, configurable days |
| Credentials | `--db-password` or `DB_BACKUP_PASSWORD`; never hardcoded or logged |
| Exit codes | `0` success · `1` config/safety · `2` partial failure |

---

## The CLI surface

| Flag (Bash) | Param (PowerShell) | Default | Meaning |
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

## Exit codes

| Code | Meaning |
| :--: | :--- |
| `0` | Success (backup created, compressed, retention applied) |
| `1` | Configuration or safety violation |
| `2` | Partial failure (dump, compression or retention step failed) |

---

## Credential handling

The password is resolved `--db-password` -> `DB_BACKUP_PASSWORD` env. It is never hardcoded,
echoed or logged in full. It is passed to the dump tool via its native env var (`MYSQL_PWD`,
`PGPASSWORD`) so it does not appear in `ps`.

A missing password is a configuration error (exit 1).

---

## Safety guardrails

- **Path blacklist:** refuses `/`, `C:\`, `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/lib`,
  `/lib64`, `/boot`, `/dev`, `/proc`, `/sys`, `/root`, `C:\Windows`, `C:\Program Files`,
  `C:\Users`.
- **Backup dir:** must be creatable and writable.
- **Dry-run:** no dump, no compression, no deletion.
- **Exit codes:** documented and consistent.

---

## Backup flow

1. Parse + validate flags.
2. Resolve credentials (env/flag). Fail (exit 1) if missing.
3. Validate backup dir (blacklist, creatable). Create if missing.
4. Build timestamp `YYYYMMDD_HHMMSS` and target filename
   `<dbtype>_<dbname>_<timestamp>.sql`.
5. If dry-run: print planned actions and exit 0 without invoking the dump tool.
6. Invoke the dump tool with resolved credentials. On failure: exit 2.
7. Compress (gzip/zip) and remove the raw `.sql`.
8. Prune backups older than retention-days (by mtime).
9. Write an ISO-8601 audit line per run.
10. Exit 0 on full success.

---

## Testing

Tests stub `mysqldump`/`pg_dump` on `PATH`. Suites assert flags, exit codes, emitted files,
dry-run, guardrails, retention pruning, audit log, credential handling and parity. No real
database required.

- Bash suite: `bash tests/test_db_backup.sh` (26 tests).
- PowerShell suite: `pwsh tests/test_db_backup.ps1` (31 tests, incl. parity proof).

---

## Documentation

- [SPECS.md](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/3-Automated-Database-Backup-with-Timestamp/SPECS.md)
- [README.md](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/3-Automated-Database-Backup-with-Timestamp/README.md)
- [ROADMAP.md](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/3-Automated-Database-Backup-with-Timestamp/ROADMAP.md)
- [CODESTYLE.md](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/3-Automated-Database-Backup-with-Timestamp/CODESTYLE.md)
- [docs/](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/3-Automated-Database-Backup-with-Timestamp/docs) — architecture comparison, scenarios, labs.

---

## Scope exclusions (v1)

No incremental/differential backups, no cloud streaming, no MSSQL, no encryption of the backup
file, no `--json`/`--csv` output. One database per invocation. Audit write is best-effort.

---

## Where to go next

- [17. Bash vs PowerShell](17-Database-Backup-Bash-vs-PowerShell.md)
- [18. Scenarios & Labs](18-Database-Backup-Scenarios-and-Labs.md)
