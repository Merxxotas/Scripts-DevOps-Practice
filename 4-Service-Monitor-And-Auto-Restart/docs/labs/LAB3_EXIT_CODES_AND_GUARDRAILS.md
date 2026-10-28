# Lab 3 — Exit Codes and Guardrails

**Goal:** verify the safety contract.

1. Invalid service name:
   ```bash
   ./service_monitor.sh -s "bad/name"; echo "exit=$?"
   ```
   Expected: exit 1.

2. Service not installed:
   ```bash
   ./service_monitor.sh -s nope; echo "exit=$?"
   ```
   Expected: exit 1.

3. Bad max-retries:
   ```bash
   ./service_monitor.sh -s nginx -r 0; echo "exit=$?"
   ```
   Expected: exit 1.

4. Audit log:
   ```bash
   ./service_monitor.sh -s nginx --audit-log /tmp/sm.audit; cat /tmp/sm.audit
   ```