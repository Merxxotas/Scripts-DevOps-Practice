# Lab 3: Scheduling in Production

## Objective

Turn the module into a nightly job: cron on Linux, Task Scheduler on Windows, with the password
kept out of the command line and the audit log as the durable record.

## Prerequisites

- A Linux host with cron, or a Windows host with Task Scheduler.
- The dump tool installed (`mysqldump` / `pg_dump`).
- A writable backup directory and a writable audit-log directory.

## Step 1: Keep the password out of the command line

Set the password once in the host environment so it never appears in `ps`:

```bash
export DB_BACKUP_PASSWORD='secret'
```

For a cron job, put it in the crontab or in a sourced env file; never on the command line.

## Step 2: A cron entry

`/etc/cron.d/db-backup`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DB_BACKUP_PASSWORD=secret

17 2 * * * root /usr/local/bin/db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db -r 14 -l /var/log/db-backup/audit.log
```

cron ignores the exit code, so wrap the call if you want syslog to see a failure:

```bash
/usr/local/bin/db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db -r 14 -l /var/log/db-backup/audit.log \
    || logger -t db-backup "backup failed with exit code $?"
```

## Step 3: A systemd timer (alternative)

`/etc/systemd/system/db-backup.service`:

```ini
[Unit]
Description=Nightly database backup

[Service]
Type=oneshot
Environment=DB_BACKUP_PASSWORD=secret
ExecStart=/usr/local/bin/db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db -r 14 -l /var/log/db-backup/audit.log
```

`/etc/systemd/system/db-backup.timer`:

```ini
[Unit]
Description=Run the database backup nightly

[Timer]
OnCalendar=*-*-* 02:17:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it:

```bash
systemctl daemon-reload
systemctl enable --now db-backup.timer
systemctl list-timers db-backup.timer
```

systemd acts on a non-zero exit code: add `OnFailure=` to page on a broken backup.

## Step 4: Windows Task Scheduler

```powershell
$env:DB_BACKUP_PASSWORD = 'secret'
.\db_backup.ps1 -DbType mysql -DbName orders -DbUser backup_user -BackupDir C:\Backups\Database -RetentionDays 14 -LogFile C:\Logs\db-backup.log
```

Store the password in the Task Scheduler "run as" environment, or in a secured env file, never in
the task action string.

## Step 5: Dry-run rehearsal before the first real run

```bash
./db_backup.sh -t mysql -n orders -u backup_user -d /var/backups/db -r 14 --dry-run
```

Confirm the target filename and the pruning plan, then drop `--dry-run`.

## Step 6: Retention and disk budget

Retention is by mtime. A host that produces large dumps should size the backup filesystem for
`retention-days * average_dump_size`, plus headroom. Pruning is best-effort per file: a single
undeletable archive is counted as a partial failure (exit `2`) but does not abort the rest.

## Step 7: Audit log as the durable record

The audit log is appended to, never rotated by this module. Point `-l` at a path on a filesystem
that is not the one being backed up, or ship it to a remote collector, so a full disk does not
also destroy the evidence.

## Step 8: Clean up

Remove any scratch directories created during rehearsal.

---

## What You Should See

| Check | Expected |
| :--- | :--- |
| cron run | archive created, audit line appended, exit `0` |
| systemd timer | `systemctl list-timers` shows the next run |
| Dry run | `[DRY RUN]` lines, no changes |
| Failed dump | exit `2`, failure in the audit log |

---

## Related Documents

- [Lab 1 -- Backup & Dry Run](LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 2 -- Exit Codes & Retention](LAB2_EXIT_CODES_AND_RETENTION.md)
- [SCENARIOS.md](../SCENARIOS.md)
- [../README.md](../README.md)
