# Lab 2: Exit Codes & Retention

## Objective

Reproduce every exit code the module defines, and watch retention pruning delete old archives.
By the end you will know which failures are configuration errors (`1`) and which are partial
failures (`2`).

## Prerequisites

- Bash 4+.
- A stubbed `mysqldump` on `PATH` (see Lab 1, Step 1).

Run from the module folder.

## Setup

```bash
mkdir -p /tmp/lab2_db/stubbin /tmp/lab2_db/backups
cat > /tmp/lab2_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
echo "-- MySQL dump stub"
EOF
chmod +x /tmp/lab2_db/stubbin/mysqldump
export PATH="/tmp/lab2_db/stubbin:$PATH"
export DB_BACKUP_PASSWORD='secret'
```

## Step 1: Success (exit 0)

```bash
rm -rf /tmp/lab2_db/backups && mkdir -p /tmp/lab2_db/backups
./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/backups
echo "exit=$?"
```

Expected: `exit=0`, a `.sql.gz` archive, and the "Backup complete" line.

## Step 2: Configuration error — missing password (exit 1)

```bash
env -u DB_BACKUP_PASSWORD ./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/backups
echo "exit=$?"
```

Expected: `Error: Database password is required...` and `exit=1`.

## Step 3: Configuration error — system path (exit 1)

```bash
./db_backup.sh -t mysql -n labdb -d /etc --db-password secret
echo "exit=$?"
```

Expected: `Error: Refusing to use a system path...` and `exit=1`.

## Step 4: Configuration error — bad retention (exit 1)

```bash
./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/backups -r abc --db-password secret
echo "exit=$?"
```

Expected: `Error: Retention days must be an integer between 0 and 3650.` and `exit=1`.

## Step 5: Partial failure — dump fails (exit 2)

```bash
cat > /tmp/lab2_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
exit 3
EOF
chmod +x /tmp/lab2_db/stubbin/mysqldump
rm -rf /tmp/lab2_db/fail && mkdir -p /tmp/lab2_db/fail
./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/fail
echo "exit=$?"
ls /tmp/lab2_db/fail
```

Expected: `Error: Database dump failed (exit 3).`, `exit=2`, and an empty backup directory
(the partial `.sql` was removed).

Restore the good stub:

```bash
cat > /tmp/lab2_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
echo "-- MySQL dump stub"
EOF
chmod +x /tmp/lab2_db/stubbin/mysqldump
```

## Step 6: Retention pruning

Create three archives with old mtimes, then run with a 7-day retention.

```bash
rm -rf /tmp/lab2_db/ret && mkdir -p /tmp/lab2_db/ret
for i in 1 2 3; do
  f="/tmp/lab2_db/ret/mysql_labdb_2020010${i}_000000.sql.gz"
  echo "stub" > "$f"
  touch -d "2020-01-0${i}" "$f"
done
ls /tmp/lab2_db/ret
./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/ret -r 7
echo "exit=$?"
ls /tmp/lab2_db/ret
```

Expected: `Backup complete. Pruned 3 old backup(s).`, `exit=0`, and the directory holds only the
new archive.

## Step 7: Audit log on failure

```bash
cat > /tmp/lab2_db/stubbin/mysqldump <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x /tmp/lab2_db/stubbin/mysqldump
rm -rf /tmp/lab2_db/aud && mkdir -p /tmp/lab2_db/aud
./db_backup.sh -t mysql -n labdb -d /tmp/lab2_db/aud -l /tmp/lab2_db/audit.log
echo "exit=$?"
cat /tmp/lab2_db/audit.log
```

Expected: the audit log contains `Dump failed for mysql/labdb (exit 1).` and the password never
appears.

## Step 8: Clean up

```bash
rm -rf /tmp/lab2_db
```

---

## What You Should See

| Check | Expected |
| :--- | :--- |
| Success | exit `0` |
| Missing password / system path / bad retention | exit `1` |
| Failed dump | exit `2`, empty dir |
| Retention | old archives removed, count reported |
| Audit log | failure recorded, no password |

---

## Try It Yourself

1. Set retention to `0` and confirm every existing archive is pruned.
2. Point `-l` at a read-only file and confirm the backup still succeeds (best-effort audit).
3. Pass `--no-compress` and confirm the raw `.sql` is retained.

---

## Related Documents

- [Lab 1 -- Backup & Dry Run](LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 3 -- Scheduling in Production](LAB3_PRODUCTION_SCHEDULING.md)
- [SCENARIOS.md](../SCENARIOS.md)
