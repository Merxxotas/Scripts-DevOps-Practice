# Lab 3 — Guardrails and Exit Codes

Goal: exercise input validation and audit logging.

1. `./health_check.sh -u ftp://x` -> exit 1.
2. `./health_check.sh -t 0` -> exit 1.
3. `./health_check.sh -e 999` -> exit 1.
4. `./health_check.sh --audit-log /tmp/hc.log` then inspect the log line.

Expected: config violations exit 1; audit line is ISO-8601.
