# Lab 1 — Discovery and Dry Run

Goal: verify the script runs and dry-run makes no deletion.

1. Run `./k8s_monitor.sh --help`.
2. Run `./k8s_monitor.sh --dry-run` (with a stubbed kubectl or real cluster).
3. Run `./k8s_monitor.sh --dry-run -v`.

Expected: exit 0 in all cases; no pods deleted.
