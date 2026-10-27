# Roadmap — Module 8 (Log Rotation and Compression)

## Phase 1 — Core (shipped in this PR)
- [x] CLI parser with all documented flags on both platforms
- [x] Size threshold + force rotation
- [x] Compression (gzip / zip) + raw mode
- [x] Retention pruning
- [x] Dry-run mode
- [x] Audit log
- [x] Safety guardrails
- [x] Exit codes
- [x] Test suites (Bash + PowerShell)
- [x] CI workflow

## Phase 2 — Enhancements (future)
- [ ] Time-based / date-stamped rotation
- [ ] `copytruncate` mode (rotate without restarting the writer)
- [ ] `create` mode (new empty file with specified ownership/mode)
- [ ] Post-rotation hook / signal
- [ ] Compression of already-rotated backups
- [ ] `--json` / `--csv` output
- [ ] Multiple log files per invocation