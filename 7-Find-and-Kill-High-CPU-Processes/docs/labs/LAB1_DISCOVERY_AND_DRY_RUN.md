# Lab 1 — Discovery and Dry Run

**Goal:** list candidates without signaling anything.

1. Default threshold:
   ```bash
   ./kill_high_cpu.sh
   ```
2. Dry run:
   ```bash
   ./kill_high_cpu.sh --dry-run
   ```
3. Custom threshold:
   ```bash
   ./kill_high_cpu.sh -t 80 --dry-run
   ```