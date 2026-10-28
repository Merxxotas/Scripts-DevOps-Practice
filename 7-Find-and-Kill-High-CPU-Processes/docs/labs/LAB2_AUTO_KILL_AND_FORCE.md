# Lab 2 — Auto-Kill and Force

**Goal:** exercise termination paths.

1. Auto-kill:
   ```bash
   ./kill_high_cpu.sh -t 80 --auto-kill
   ```
2. Force (SIGKILL):
   ```bash
   ./kill_high_cpu.sh -t 90 --auto-kill --force
   ```
3. Audit log:
   ```bash
   ./kill_high_cpu.sh --auto-kill --audit-log /tmp/khc.audit
   cat /tmp/khc.audit
   ```