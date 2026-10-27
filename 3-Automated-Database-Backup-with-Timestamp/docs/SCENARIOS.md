# Database Backup Utility — Real-World Production Scenarios

A database that is never backed up is a disaster waiting for a Friday. This document walks through
the situations an operator actually meets, and states the **exit code** each one produces, because
that is what a scheduler, a CI step or a wrapper script reacts to.

Every output below was captured from a real run of `db_backup.sh` with a stubbed `mysqldump` on
`PATH`, so no database is required to reproduce them.

---

## The Exit-Code Contract at a Glance

| Code | Meaning | Triggered by |
| :--: | :--- | :--- |
| `0` | Success | Backup created, compressed, retention applied. |
| `1` | Configuration / safety violation | Unknown flag, bad db type, empty name/user, missing password, bad retention, system path as backup dir, unwritable dir, missing dump tool. |
| `2` | Partial failure | Dump failed, compression failed, or a retention delete failed. |

---

## Scenario 1: A Successful MySQL Backup

### Problem

Nightly backup of the `orders` database. The operator wants a timestamped, compressed archive in
`/var/backups/db`, kept for 14 days.

### Command

```bash
export DB_BACKUP_PASSWORD='secret'
./db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db -r 14
```

### Observed behaviour

```
=== Database Backup Utility ===
Database type : mysql
Database name : orders
Backup dir    : /var/backups/db
Backup file   : /var/backups/db/mysql_orders_20261027_020000.sql
Retention     : 14 days
Compress      : true
Backup created: /var/backups/db/mysql_orders_20261027_020000.sql
Compressed: /var/backups/db/mysql_orders_20261027_020000.sql.gz
Backup complete. Pruned 0 old backup(s).
```

**Exit code: `0`.** The raw `.sql` was removed after compression; only the `.sql.gz` remains.

### Operational note

The filename carries the db type, db name and a `YYYYMMDD_HHMMSS` timestamp, so two runs in the
same second cannot collide and a directory listing is already sorted by time.

---

## Scenario 2: A Missing Password

### Problem

The cron entry was copied from a wiki page and the `DB_BACKUP_PASSWORD` export was lost. The
module now has no credential.

### Command

```bash
./db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db
```

### Observed behaviour

```
Error: Database password is required. Pass --db-password or set DB_BACKUP_PASSWORD.
```

**Exit code: `1`** — a configuration error. Nothing was dumped and nothing was written.

### Remediation

Set the password once in the host environment, or pass `--db-password`. The two sources are the
only ones; there is no file default, by design.

---

## Scenario 3: An Unknown Database Type

### Problem

A typo in the scheduler: `postgres` was intended but `postres` was typed.

### Command

```bash
./db_backup.sh -t postres -n orders -d /var/backups/db --db-password secret
```

### Observed behaviour

```
Error: Unsupported database type: 'postres'. Use mysql or postgresql.
```

**Exit code: `1`.** The alias `postgres` is accepted and normalised to `postgresql`; anything
else is refused.

---

## Scenario 4: A System Path as the Backup Directory

### Problem

A misconfigured job points the backup directory at `/etc` or `/var`.

### Command

```bash
./db_backup.sh -t mysql -n orders -d /etc --db-password secret
```

### Observed behaviour

```
Error: Refusing to use a system path as the backup directory: '/etc'.
```

**Exit code: `1`.** The blacklist covers `/`, `/etc`, `/var`, `/usr`, `/bin`, `/sbin`, `/lib`,
`/lib64`, `/boot`, `/dev`, `/proc`, `/sys`, `/root` and their Windows equivalents. The check
runs before any directory is created.

---

## Scenario 5: The Dump Tool Is Missing

### Problem

The host was rebuilt from a minimal image. `mysqldump` is not installed.

### Command

```bash
PATH=/usr/bin:/bin ./db_backup.sh -t mysql -n orders -d /var/backups/db --db-password secret
```

### Observed behaviour

```
Error: Database dump tool not found: 'mysqldump'. Install it and retry.
```

**Exit code: `1`** — a configuration error, because the tool can never succeed with this host.

---

## Scenario 6: A Failed Dump

### Problem

The database server is down, or the credentials are wrong. `mysqldump` exits non-zero.

### Command

```bash
# with a stub that always fails
./db_backup.sh -t mysql -n orders -d /tmp/scratchpad/fail --db-password secret
```

### Observed behaviour

```
Error: Database dump failed (exit 1).
```

**Exit code: `2`** — a partial failure. The partial `.sql` file is removed, so a failed run
leaves no corrupt archive behind. The audit log records the failure.

---

## Scenario 7: Compression Failure

### Problem

The disk is full, or `gzip` is missing. The dump succeeded but compression did not.

### Observed behaviour

```
Error: Compression failed for /var/backups/db/mysql_orders_20261027_020000.sql.
```

**Exit code: `2`.** The raw `.sql` is left in place so the operator can recover the dump
manually; only successful compression removes it.

---

## Scenario 8: Retention Pruning

### Problem

The backup directory holds archives from the last 30 days; retention is 7. The old ones should go.

### Command

```bash
./db_backup.sh -t mysql -n orders -d /var/backups/db -r 7 --db-password secret
```

### Observed behaviour

```
Backup complete. Pruned 4 old backup(s).
```

**Exit code: `0`.** Files matching `*.sql`, `*.sql.gz` and `*.zip` older than 7 days by mtime
are removed. A single file that cannot be deleted is counted as a partial failure (exit `2`) but
does not abort the rest of the pruning.

---

## Scenario 9: Dry Run

### Problem

The operator wants to see what a run would do before scheduling it.

### Command

```bash
./db_backup.sh -t mysql -n orders -d /var/backups/db -r 7 --dry-run --db-password secret
```

### Observed behaviour

```
[DRY RUN] Would create backup directory: /var/backups/db
[DRY RUN] Would invoke: mysqldump ... > /var/backups/db/mysql_orders_<timestamp>.sql
[DRY RUN] Would compress: ...sql -> ...sql.gz
[DRY RUN] Would prune backups older than 7 days in /var/backups/db
```

**Exit code: `0`.** Nothing is dumped, compressed or deleted. The target filename is built so the
operator can see exactly what would be produced.

---

## Scenario 10: No Compression

### Problem

The operator wants the raw `.sql` kept (for example, to feed a downstream tool).

### Command

```bash
./db_backup.sh -t mysql -n orders -d /var/backups/db --no-compress --db-password secret
```

### Observed behaviour

The backup is created as `mysql_orders_<timestamp>.sql` and left uncompressed. **Exit code: `0`.**

---

## Scenario 11: PostgreSQL Backend

### Command

```bash
./db_backup.sh -t postgresql -n orders -u backup_user -d /var/backups/db --db-password secret
```

`pg_dump` is invoked as `pg_dump -U backup_user -d orders -f <target>`, with `PGPASSWORD` set in
the environment. **Exit code: `0`.**

---

## Scenario 12: Audit Log

### Command

```bash
./db_backup.sh -t mysql -n orders -d /var/backups/db --db-password secret \
    -l /var/log/db-backup/audit.log
```

### Observed behaviour

```
2026-10-27T02:00:00Z [INFO] Backup created: /var/backups/db/mysql_orders_20261027_020000.sql
2026-10-27T02:00:00Z [INFO] Compressed: /var/backups/db/mysql_orders_20261027_020000.sql.gz
2026-10-27T02:00:00Z [INFO] Backup complete for mysql/orders. Pruned 0 old backup(s).
```

The password never appears in the log. A failing audit write never breaks the backup.

---

## 📎 Related Documents

- [ARCHITECTURE_COMPARISON.md](ARCHITECTURE_COMPARISON.md) -- where the two implementations agree and differ.
- [Lab 1 -- Backup & Dry Run](labs/LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 2 -- Exit Codes & Retention](labs/LAB2_EXIT_CODES_AND_RETENTION.md)
- [Lab 3 -- Scheduling in Production](labs/LAB3_PRODUCTION_SCHEDULING.md)
- [../README.md](../README.md) -- usage, flags and troubleshooting.
