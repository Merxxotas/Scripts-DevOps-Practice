# Lab 1 — Monitoring and Dry Run

Preview the monitor's decisions for a running service and a stopped service. Both are fixtures:
the lab never queries the host's service manager or writes to its log.

From the Service Monitor module directory, run:

```bash
bash docs/labs/run_service_monitor_lab.sh 1
```

Both CSV results have outcome `dry-run` and `retries_used=0`. The lab verifies that neither
preview requested a restart or sent a notification. It exits 0 on success and removes its private
scratch directory.
