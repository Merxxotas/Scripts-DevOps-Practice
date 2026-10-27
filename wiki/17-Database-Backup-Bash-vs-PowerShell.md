# 17. Database Backup — Bash vs PowerShell

> Module 3 parity reference. Full detail in the module's
> [ARCHITECTURE_COMPARISON.md](../3-Automated-Database-Backup-with-Timestamp/docs/ARCHITECTURE_COMPARISON.md).

---

## Where they are identical

Same 12 options, same defaults, same validation, same exit codes (`0`/`1`/`2`), same audit
format, same filename shape, same retention glob. The parity test
(`Test-PublicInterfaceMatchesBashSide`) compares the two declarations as set equality.

## Where they legitimately differ

| # | Difference | Why |
| :-- | :-- | :--- |
| 1 | Compression format | `gzip` (`.sql.gz`) on POSIX; `Compress-Archive` (`.sql.zip`) on PowerShell. |
| 2 | Retention enumeration | `find -mtime` vs `Get-ChildItem` by `LastWriteTime`. Both use mtime. |
| 3 | Default backup dir | `./backups` vs `C:\Backups\Database`. |
| 4 | Verbosity flag | Bash `-v`; PowerShell `-Verbose` common parameter. |
| 5 | Parameter syntax | GNU flags vs named parameters. |
| 6 | Db-type alias | Both accept `postgres` -> `postgresql`. |

## Credential handling (both sides)

Password from `--db-password` -> `DB_BACKUP_PASSWORD`. Passed via `MYSQL_PWD` / `PGPASSWORD`
so it never appears in `ps` or the audit log.

## Related

- [16. Overview](16-Database-Backup-Overview.md)
- [18. Scenarios & Labs](18-Database-Backup-Scenarios-and-Labs.md)
