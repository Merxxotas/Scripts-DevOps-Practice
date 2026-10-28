# Lab 1 — Monitoring and Dry Run

**Goal:** observe a running service and preview a restart without touching it.

1. Check a running service:
   ```bash
   ./service_monitor.sh -s nginx
   ```
   Expected: success message, exit 0.

2. Dry run against a down service:
   ```bash
   ./service_monitor.sh -s nginx --dry-run
   ```
   Expected: `[DRY RUN]` plan, no restart, exit 0.

3. Inspect the help:
   ```bash
   ./service_monitor.sh -h
   ```