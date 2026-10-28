# 27. Find and Kill High-CPU — Scenarios & Labs

## Scenarios

- No high-CPU processes → exit 0.
- Dry run → exit 0, no signal.
- Interactive kill → prompt per candidate.
- Auto-kill → kills all, exit 0 (or 2 on failure).
- Force → SIGKILL / Stop-Process -Force.
- Guardrails → never targets PID 0/1, self, parent, kernel threads.

## Labs

See `7-Find-and-Kill-High-CPU-Processes/docs/labs/`:
- LAB1_DISCOVERY_AND_DRY_RUN.md
- LAB2_AUTO_KILL_AND_FORCE.md
- LAB3_GUARDRAILS_AND_EXIT_CODES.md