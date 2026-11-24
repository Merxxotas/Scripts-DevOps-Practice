# Lab 2 — Restart and Retries

Exercise restart and retry behavior using a fake service manager and logger. No host service is
queried or restarted. Use the lab runner rather than copying restart flags into a host command.

From the Service Monitor module directory, run:

```bash
bash docs/labs/run_service_monitor_lab.sh 2
```

- `lab-recover`: the first attempt fails, then the second succeeds and sends one mock notification.
  The CSV outcome is `restarted`, with `retries_used=2`.
- `lab-stuck`: both attempts fail. The CSV outcome is `failed`, with `retries_used=2`; the
  monitor exits 2 and the lab checks that status. Failed attempts are reported on stderr.

The lab exits 0 when the simulated outcomes match, and removes its private scratch directory.
