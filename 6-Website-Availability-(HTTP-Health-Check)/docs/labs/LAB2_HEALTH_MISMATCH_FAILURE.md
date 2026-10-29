# Lab 2 — Health, Mismatch and Failure

Goal: observe the three outcomes and exit codes.

1. `./health_check.sh` (default URL) -> healthy, exit 0.
2. Point at an endpoint returning a non-200 status -> exit 2.
3. Point at a non-existent host -> CONNECTION FAILED, exit 2.

Verify the colored output and timing/size fields.
