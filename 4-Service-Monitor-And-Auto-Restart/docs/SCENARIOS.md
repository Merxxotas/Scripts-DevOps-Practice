# Scenarios — Service Monitor and Auto-Restart

## Scenario 1: Service is running

```bash
./service_monitor.sh -s nginx
# → "✓ Service 'nginx' is running." exit 0
```

## Scenario 2: Service is down, restart succeeds

```bash
./service_monitor.sh -s nginx -r 3 --retry-delay 2
# → attempts restart; on success logs and exits 0
```

## Scenario 3: Service is down, restart fails

```bash
./service_monitor.sh -s nginx -r 2 --retry-delay 0
# → exits 2 after exhausting retries
```

## Scenario 4: Dry run

```bash
./service_monitor.sh -s nginx --dry-run
# → prints planned actions, no restart, exit 0
```

## Scenario 5: Service not installed

```bash
./service_monitor.sh -s nope
# → "Error: Service 'nope' is not installed or not found." exit 1
```

## Scenario 6: Invalid service name

```bash
./service_monitor.sh -s "bad/name"
# → "Error: Invalid service name ..." exit 1
```

## Scenario 7: Audit log

```bash
./service_monitor.sh -s nginx --audit-log /tmp/audit.log
# → appends an ISO-8601 line to /tmp/audit.log
```