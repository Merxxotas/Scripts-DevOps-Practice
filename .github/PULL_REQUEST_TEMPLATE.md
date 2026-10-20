<!--
Thanks for contributing to Scripts-DevOps-Practice.
Delete any section that genuinely does not apply, but do not silently drop a failing check —
write "n/a — reason" instead.
-->

### What changed

<!-- What does this pull request do, and why? Link the issue it closes, if any. -->

Closes #

### Module

<!-- e.g. "2 — Log Cleanup (Delete Files Older Than X Days)". Use "repository root" for docs/CI work. -->

**Risk:** <!-- `Risk: none` or `Risk: item N (reason)` — see AGENTS.md §2.6 -->

### Verification

<!-- Run the commands locally. Paste real output, not a claim. -->

| Check | Command | Result |
| :--- | :--- | :--- |
| Bash suite | `bash <module>/tests/test_<module>.sh` | |
| PowerShell suite | `pwsh <module>/tests/test_<module>.ps1` | |
| Python | `pytest` (in module dir) | |
| Go | `go test ./...` (in module dir) | |
| Lint | `shellcheck -x` / `PSScriptAnalyzer` / `ruff check` / `go vet` | |

- [ ] Every applicable command above was run locally and its result is pasted above.
- [ ] The failing test was observed **before** the fix (RED → GREEN → REFACTOR).
- [ ] A regression test was added for **every existing command or option** this change touches.
- [ ] Tests are deterministic — no dependence on the host's real services, disk layout, locale or clock.

### Documentation

- [ ] Module `README.md` updated (usage, flags, exit codes, troubleshooting).
- [ ] `SPECS.md` and/or `ROADMAP.md` updated where the contract or the plan changed.
- [ ] `CHANGELOG.md` updated — this change is user-visible.
- [ ] `MODULES.md` updated if a module's status changed.
- [ ] `docs/` updated: `SCENARIOS.md`, `ARCHITECTURE_COMPARISON.md`, labs — as applicable.
- [ ] Wiki page and `wiki/_Sidebar.md` entry updated for a new module.

### CI

- [ ] The module's workflow is at the **repository root** (`.github/workflows/`), not nested.
- [ ] The workflow is path-filtered to this module's folder and includes its own file in `paths:`.
- [ ] OS versions are pinned explicitly — no `-latest` aliases.
- [ ] No credentials, tokens or real hostnames appear anywhere in the diff.

### Review notes

<!-- What should a reviewer look at first? Anything non-obvious, any deliberate deviation, any
     part you are unsure about. Honest uncertainty is more useful than a confident guess. -->
