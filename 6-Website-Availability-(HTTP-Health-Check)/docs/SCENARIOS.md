# Scenarios — Website Availability (HTTP Health Check)

## Scenario 1 — Basic health check

```bash
./health_check.sh
```

Expected: status 200 OK, exit 0.

## Scenario 2 — Unhealthy endpoint

```bash
./health_check.sh -u https://httpstat.us/503 -e 200
```

Expected: status 503, exit 2.

## Scenario 3 — Connection failure

```bash
./health_check.sh -u https://this-host-does-not-exist.invalid
```

Expected: CONNECTION FAILED, exit 2.

## Scenario 4 — Dry run

```bash
./health_check.sh -u https://example.com --dry-run
```

Expected: prints target/expected/timeout, no request, exit 0.

## Scenario 5 — Audit log

```bash
./health_check.sh --audit-log /tmp/hc.log
cat /tmp/hc.log
```

Expected: one ISO-8601 line appended.

## Scenario 6 — SSL expiry

```bash
./health_check.sh -u https://example.com --ssl-check
```

Expected: SSL expiry line with certificate date.
