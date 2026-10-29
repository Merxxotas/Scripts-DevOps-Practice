# Lab 3 — Guardrails and Exit Codes

Goal: exercise input validation and audit logging.

1. `./k8s_monitor.sh -n ""` -> exit 1.
2. `./k8s_monitor.sh -r -1` -> exit 1.
3. `./k8s_monitor.sh -l ""` -> exit 1.
4. `./k8s_monitor.sh --audit-log /tmp/k8s.log` then inspect the log line.

Expected: config violations exit 1; audit line is ISO-8601.
