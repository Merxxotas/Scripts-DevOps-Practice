# Lab 1: Backup & Dry Run

## Objective

Run a real backup end to end with a stubbed dump tool, then rehearse the same run with
`--dry-run` and prove that nothing was touched. By the end you will know the filename shape,
the exit code, and the dry-run contract.

## Prerequisites

- Bash 4+ on Linux/macOS (or PowerShell 7+ on Windows).
- Execution permission on `db_backup.sh`.
- No database required: the suite stubs `mysqldump`/`pg_dump` on `PATH`.

Run every command from the module folder:

```bash
cd 3-Automated-Database-Backup-with-Timestamp
```

## Step 1: Create a stub dump tool

The module invokes `mysqldump` / `pg_dump` as an external command, so a stand-in on `PATH`
lets the lab run without a database.

```bash
mkdir -p /tmp/lab1_db/stubbin /tmp/lab1_db/backups
cat > /tmp/lab1_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
echo "-- MySQL dump stub"
echo "CREATE TABLE t (id int);"
EOF
chmod +x /tmp/lab1_db/stubbin/mysqldump
export PATH="/tmp/lab1_db/stubbin:$PATH"
export DB_BACKUP_PASSWORD='secret'
```

## Step 2: Run a real backup

```bash
rm -rf /tmp/lab1_db/backups && mkdir -p /tmp/lab1_db/backups
./db_backup.sh -t mysql -n labdb -u backup_user -d /tmp/lab1_db/backups -r 7
echo "exit=$?"
```

Expected:

```
=== Database Backup Utility ===
Database type : mysql
Database name : labdb
Backup dir    : /tmp/lab1_db/backups
Backup file   : /tmp/lab1_db/backups/mysql_labdb_<timestamp>.sql
Retention     : 7 days
Compress      : true
Backup created: /tmp/lab1_db/backups/mysql_labdb_<timestamp>.sql
Compressed: /tmp/lab1_db/backups/mysql_labdb_<timestamp>.sql.gz
Backup complete. Pruned 0 old backup(s).
exit=0
```

Confirm only the compressed archive remains:

```bash
ls /tmp/lab1_db/backups
```

## Step 3: Dry run

```bash
./db_backup.sh -t mysql -n labdb -u backup_user -d /tmp/lab1_db/backups --dry-run
echo "exit=$?"
```

Expected:

```
[DRY RUN] Would create backup directory: /tmp/lab1_db/backups
[DRY RUN] Would invoke: mysqldump ... > /tmp/lab1_db/backups/mysql_labdb_<timestamp>.sql
[DRY RUN] Would compress: ...sql -> ...sql.gz
[DRY RUN] Would prune backups older than 7 days in /tmp/lab1_db/backups
exit=0
```

Nothing is dumped, compressed or deleted. The target filename is built so you can see exactly
what would be produced.

## Step 4: Prove the dry run never invokes the dump tool

```bash
cat > /tmp/lab1_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
echo "DUMP WAS CALLED" >&2
exit 99
EOF
chmod +x /tmp/lab1_db/stubbin/mysqldump
./db_backup.sh -t mysql -n labdb -d /tmp/lab1_db/backups --dry-run
echo "exit=$?"
```

The run still exits `0` and prints the `[DRY RUN]` lines: the dump tool was never invoked,
because a failing tool would have made the run exit `1`/`2`.

Restore the good stub:

```bash
cat > /tmp/lab1_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
echo "-- MySQL dump stub"
EOF
chmod +x /tmp/lab1_db/stubbin/mysqldump
```

## Step 5: PostgreSQL backend

```bash
cat > /tmp/lab1_db/stubbin/pg_dump <<'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in -f) out="$2"; shift 2;; *) shift;; esac
done
printf -- "-- PG dump stub\n" > "$out"
EOF
chmod +x /tmp/lab1_db/stubbin/pg_dump
./db_backup.sh -t postgresql -n labdb -d /tmp/lab1_db/backups --no-compress
echo "exit=$?"
ls /tmp/lab1_db/backups
```

The file is `postgresql_labdb_<timestamp>.sql` and is left uncompressed.

## Step 6: Clean up

```bash
rm -rf /tmp/lab1_db
```

---

## What You Should See

| Check | Expected |
| :--- | :--- |
| Real backup | `.sql.gz` archive, exit `0` |
| Dry run | `[DRY RUN]` lines, no new file, exit `0` |
| PostgreSQL | `postgresql_<db>_<timestamp>.sql`, exit `0` |
| Missing password | error, exit `1` |

---

## Try It Yourself

1. Run with `-v` and watch the diagnostic output.
2. Pass `--db-password` on the command line and confirm it overrides `DB_BACKUP_PASSWORD`.
3. Point `-d` at a system path (`/etc`) and confirm exit `1`.

---

## Related Documents

- [Lab 2 -- Exit Codes & Retention](LAB2_EXIT_CODES_AND_RETENTION.md)
- [Lab 3 -- Scheduling in Production](LAB3_PRODUCTION_SCHEDULING.md)
- [SCENARIOS.md](../SCENARIOS.md)
