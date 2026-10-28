# Lab 2 — Restart and Retries

**Goal:** exercise the auto-restart loop.

1. Force a restart attempt with a short delay:
   ```bash
   ./service_monitor.sh -s nginx -r 3 --retry-delay 1
   ```

2. Observe retry exhaustion (use a service that cannot restart):
   ```bash
   ./service_monitor.sh -s nonexistent -r 2 --retry-delay 0
   ```
   Expected: exit 2.

3. Enable verbose output to see per-attempt detail:
   ```bash
   ./service_monitor.sh -s nginx -v --retry-delay 0
   ```