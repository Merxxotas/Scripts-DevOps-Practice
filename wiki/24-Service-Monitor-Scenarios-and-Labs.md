# 24. Service Monitor — Scenarios & Labs

## Scenarios

- Running service → exit 0, no restart.
- Down service, restart succeeds → exit 0.
- Down service, restart fails → exit 2.
- Dry run → exit 0, no mutation.
- Service not installed → exit 1.
- Invalid service name → exit 1.

## Labs

See `4-Service-Monitor-And-Auto-Restart/docs/labs/`:
- LAB1_MONITORING_AND_DRY_RUN.md
- LAB2_RESTART_AND_RETRIES.md
- LAB3_EXIT_CODES_AND_GUARDRAILS.md