# Find and Kill High-CPU Processes — Roadmap

## Phase 1 — Foundation (shipped)

- [x] CLI parser (Bash + PowerShell) with help.
- [x] Threshold validation.
- [x] Process discovery with guardrails.
- [x] Interactive and auto-kill modes.
- [x] Force mode (SIGKILL / Stop-Process -Force).
- [x] Dry-run mode.
- [x] Audit log.
- [x] Exit codes 0/1/2.
- [x] Tests (Bash + PowerShell).
- [x] CI workflow.
- [x] Docs and wiki.

## Phase 2 — Enhancements (planned)

- [ ] Continuous watch loop.
- [ ] `--top <n>` limit.
- [ ] `--json` / `--csv` output.
- [ ] Process-tree killing.
- [ ] cgroups / container awareness.