# Lab 2 — Threshold and Deletion

Goal: observe deletion when restart count exceeds threshold.

1. Use a stubbed kubectl returning pods with restarts above threshold.
2. Run `./k8s_monitor.sh` and verify deleted pods + exit 0.
3. Run with a failing delete and verify exit 2.

Verify per-pod output and summary block.
