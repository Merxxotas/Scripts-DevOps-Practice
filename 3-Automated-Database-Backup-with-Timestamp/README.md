# Database Backup Utility 🗄️

Cross-platform automated database backup with timestamp, compression and retention.
Supports **MySQL** and **PostgreSQL**. Available in **POSIX Bash** (Linux/macOS) and
**PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: refuses system paths as the backup directory.
- 🧪 **Dry-Run Simulation**: preview the dump, compression and pruning without touching anything.
- 📦 **Compression**: gzip on Bash, zip on PowerShell, raw `.sql` removed after success.
- 🧹 **Retention Pruning**: deletes backups older than N days (by mtime).
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- 🔐 **Credential Safety**: password from flag or `DB_BACKUP_PASSWORD`; never hardcoded or logged.
- ⚙️ **Zero Dependencies** beyond the database client (`mysqldump` / `pg_dump`).

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x db_backup.sh
export DB_BACKUP_PASSWORD='secret'

# Dry run
./db_backup.sh -t mysql -n mydb -u backup_user -d ./backups --dry-run

# Real backup, 7-day retention
./db_backup.sh -t mysql -n mydb -u backup_user -d ./backups -r 7
```

### Windows (PowerShell)

```powershell
$env:DB_BACKUP_PASSWORD = 'secret'

# Dry run
.\db_backup.ps1 -DbType mysql -DbName mydb -DbUser backup_user -BackupDir C:\Backups\Database -DryRun

# Real backup
.\db_backup.ps1 -DbType mysql -DbName mydb -DbUser backup_user -BackupDir C:\Backups\Database -RetentionDays 7
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success · `1` configuration or safety violation · `2` partial failure (dump, compression or retention).

---

## Tests

```bash
bash tests/test_db_backup.sh
pwsh tests/test_db_backup.ps1   # when available
```

The suite stubs `mysqldump`/`pg_dump` on `PATH`, so no real database is needed.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.