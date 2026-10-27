# Scenarios — Log Rotation and Compression

## Scenario 1: Routine rotation under cron

A nightly job rotates `/var/log/app/application.log` when it exceeds 10 MB, keeping
the last 5 backups.

```bash
./log_rotate.sh -f /var/log/app/application.log -m 10 -c 5
```

## Scenario 2: Dry-run before a change

Preview what would happen without touching anything:

```bash
./log_rotate.sh -f /var/log/app/application.log -m 10 --dry-run
```

## Scenario 3: Force rotation (e.g. before a release)

Rotate regardless of size:

```bash
./log_rotate.sh -f /var/log/app/application.log --force
```

## Scenario 4: Raw (uncompressed) backups

Keep rotated backups uncompressed for fast inspection:

```bash
./log_rotate.sh -f /var/log/app/application.log -m 10 --no-compress
```

## Scenario 5: Audit trail

Record every run to an audit log:

```bash
./log_rotate.sh -f /var/log/app/application.log -m 10 --audit-log /var/log/rotate.audit.log
```

## Scenario 6: Guardrail refusal

Operating on a protected system path is refused with exit 1:

```bash
./log_rotate.sh -f /etc/passwd -m 0   # exits 1
```