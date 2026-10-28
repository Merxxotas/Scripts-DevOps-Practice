# Lab 3 — Guardrails and Exit Codes

**Goal:** verify the safety contract.

1. Invalid threshold:
   ```bash
   ./kill_high_cpu.sh -t -1; echo "exit=$?"
   ```
   Expected: exit 1.
2. Non-numeric threshold:
   ```bash
   ./kill_high_cpu.sh -t abc; echo "exit=$?"
   ```
   Expected: exit 1.
3. Help:
   ```bash
   ./kill_high_cpu.sh -h; echo "exit=$?"
   ```
   Expected: exit 0.
4. Dry-run never signals (verify with audit log).