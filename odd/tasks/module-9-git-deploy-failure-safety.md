# Module 9 — Git-Deployment failure-safety remediation

Branch: fix/module9-git-deploy-failure-safety
Delivery strategy: ask-on-risk
Test runner: bash tests/test_git_deploy.sh / pwsh tests/test_git_deploy.ps1

## Specs

Source: 2026-11-04 adversarial audit, remediation authorized 2026-11-06 (L1, L2). Exact user strings quoted verbatim; the approved package (A/B/C/D) is L2.

S1 — Backup gates the deploy. Audit finding (verbatim): "backup no gatea el deploy". Approved fix: backup is created AND verified before any fetch — bash `gzip -t`, PowerShell expand-archive + payload SHA-256 (same pattern merged in Module 8, PR #60). On backup creation or verification failure: no fetch, no pull, no post-deploy; exit 2; tree untouched; audit entry "Backup failed." JSON/CSV still emitted (`result: "failed"`, `failed: 1`). `--skip-backup` remains the only opt-out; no override flag is added.

S2 — Rollback on pull failure only. Audit finding (verbatim): "sin rollback". Approved fix: before `git pull`, the tree is clean of partial deploy mutation; on pull failure (`git reset --hard` to the pre-deploy revision, which is the same `local_rev` already computed for the up-to-date check): restore exactly that revision. Rollback is automatic by default; `--no-rollback` (Bash) / `-NoRollback` (PowerShell) disables it and leaves the tree as-is with a loud warning. Rollback is NOT attempted on npm-install or service-restart failure: `reset --hard` does not touch untracked files (`node_modules` may be half-mutated), so it would be a false guarantee; and if npm fails the service is never restarted, so the live process still serves the old code from memory. Rollback failure is logged and audited (never swallowed); exit stays 2. JSON/CSV `result` gains the additive value `rolled-back` (existing values unchanged). The backup tarball/zip remains the manual escape hatch and is never auto-extracted. Rollback dialog states plainly: files rolled back; service NOT restarted.

S3 — REPO_URL enforcement. Audit finding (verbatim): "REPO_URL decorativo". Approved fix: when `-r/--repo-url` (Bash) / `-RepoUrl` (PowerShell) is passed EXPLICITLY, verify the configured `origin` before any fetch/backup: normalized comparison (lowercase; strip `scheme://` and `user:pass@`; convert `git@host:path` to `host/path`; strip trailing `/` and `.git`). Mismatch — or origin missing — exits 1 BEFORE any mutation, with both URLs named in the message. When the flag is NOT passed, banner/audit/JSON print the ACTUAL `origin` URL (truthful, not decorative); nothing is enforced and the seed default no longer misleads. Case-insensitive host+path comparison.

S4 — Not a git repository. Approved fix: pre-flight `git rev-parse --is-inside-work-tree` (via `git -C <appdir>`); on failure exit 1 with a clear message ("App directory '<path>' is not a git repository."). Replaces today's silent rev-parse failure and the cryptic exit 2 from a failed `git pull`.

S5 — PowerShell backup includes dotfiles. `Compress-Archive -Path "$AppDir\*"` never archives hidden items (`.env` and friends, typically gitignored and deploy-critical). Fix: enumerate with `Get-ChildItem -LiteralPath $AppDir -Force` and pass the item list; directory contents are archived recursively. Bash `tar -C "$APP_DIR" .` already includes dotfiles — parity holds. Empty directory (no items to archive) fails backup → gate from S1 stops the deploy; `--skip-backup` is the opt-out.

S6 — Platform parity (repo contract). Same flags, defaults, exit codes, guardrails in `git_deploy.sh` and `git_deploy.ps1`. PowerShell suite is extended with a stubbed `git` (today it uses the real git and only dry-run paths, which is why the new behavior is untested there): fake `git`/`tar`/`gzip`/`npm`/`systemctl` in Bash, fake `git` + real `Compress-Archive` in a fresh GUID temp dir in PS. Tests are deterministic; no real repository is touched.

S7 — Test-first. RED observed before implementation, one RED test per rule; existing behavior that shares changed code (up-to-date path, dry-run, exit codes, JSON/CSV shape) keeps a regression test. Suites: `bash tests/test_git_deploy.sh`, `pwsh tests/test_git_deploy.ps1`; `shellcheck -x` and `PSScriptAnalyzer` must stay clean. Scratch under `mktemp -d` (prefer `/tmp/opencode`), never inside the worktree.

S8 — Docs in the same PR. SPECS.md (§2 flow gains gate + rollback step; §3 CLI gains `--no-rollback`; §5 guardrails gain origin-verify and not-a-repo pre-flight; §7 scope exclusions lose "No rollback"), README.md, docs/ARCHITECTURE_COMPARISON.md, docs/SCENARIOS.md, docs/labs/LAB1 and LAB3, wiki/28-30, CHANGELOG.md. Exit codes unchanged (0/1/2). GitHub Wiki is synced MANUALLY after merge (AGENTS.md §9) — user decision, not automatic.

S9 — Delivery. Branch from `main` (verified `git log -1` post-checkout), test-first, PR with CI green, `merge --admin --rebase` (maintainer). RDD flow: `review assess --base-ref main --committed-only` → preflight STATUS with relevant lenses → consent relayed to the user (never auto-approved) → reviewers → ack → merge. Receipts bind to bytes; any fix after assessment re-rolls the candidate. `ci-*.yml` does not fire on `push` to `chore/**`.

S10 — Risk. `Risk: item 3` for every commit in this batch: `-r/--repo-url` changes from decorative to enforced for explicit callers, and JSON/CSV `result` gains `rolled-back` — both are contracts others consume (additive, documented). Independent verifier after the change's own checks, per the item-3 escalation.

## Tasks

- [x] T1: Create feature document + Engram mirror. route: inline
- [x] T2: Bash RED tests — backup gate + verification (tar/gzip stubs), rollback on pull failure + `--no-rollback`, repo-url verify (match/mismatch/no-origin) + not-a-repo exit 1 + truthful origin display. S1, S2, S3, S4. route: inline
- [x] T3: Bash implementation to GREEN (gate + verify + rollback + repo-url + not-a-repo pre-flight). S1, S2, S3, S4. route: inline
- [x] T4: PowerShell RED tests (stubbed git, real Compress-Archive) mirroring T2 incl. dotfiles coverage. S5, S6. route: inline
- [x] T5: PowerShell implementation to GREEN (gate + expand/hash verify + dotfiles fix + rollback + repo-url + not-a-repo pre-flight). S1–S5. route: inline
- [x] T6: Lint clean — `shellcheck -x`, `pwsh` parse + `PSScriptAnalyzer`. S7. route: inline
- [x] T7: Docs — SPECS, README, ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1/LAB2/LAB3, wiki 28/29/30, CHANGELOG, MODULES. S8. route: inline
- [x] T9: Copilot review fixes on PR #64 (9 findings: PS -ErrorAction Stop enum, dirty-worktree exit 1, nested-backup exit 1, truthful-empty repo_url, Bash `Backup verified` audit, English typos). RED observed (bash 9 fails, PS 8 fails) then GREEN to 70/70 + 51/51. route: inline
- [ ] T8: Delivery — PR, CI green, RDD consent relay, merge `--admin --rebase`, feature doc close + mirror. S9, S10. route: inline

Delivery decision (2026-11-06): user chose **PR único** at the ask-on-risk checkpoint.
PS verification deviates from L2's literal "expand + SHA-256": implemented as in-memory ZipArchive
entry hash compare (same authored checks, zero temp-dir pollution, empty archives supported).
Bash suite runs against hermetic fakes (/tmp via mktemp); PS suite runs against REAL local git
repositories with host git config isolated (GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL) — CI hosts
include Windows where bash fakes are not portable.

## Log

L1 (verbatim, 2026-11-06): "Pendiente, según la auditoría, en orden de riesgo:
1. Módulo 9 (Git-Deployment) — arrancar por acá: backup no gatea el deploy, sin rollback, REPO_URL decorativo. Proponer el enfoque y esperar OK antes de tocar código."

L2 (verbatim, 2026-11-06): "Dale con el paquete que sugieres, tal cual"
  Approving: (A) backup created AND verified (bash gzip -t; PS expand + SHA-256 payload) gating the deploy, fail closed, exit 2, no fetch/pull; `--skip-backup` stays the only opt-out. (B) rollback via `git reset --hard` on PULL FAILURE ONLY, automatic by default, `--no-rollback` / `-NoRollback` to disable; never on npm/restart failure (untracked node_modules defeats the guarantee); rollback failure logged + audited; JSON/CSV result gains `rolled-back`; service is NOT restarted by rollback. (C) explicit `-r/--repo-url` ⇒ normalized origin verify, mismatch or missing origin ⇒ exit 1 pre-flight; unset ⇒ banner/audit/JSON show the real origin; not-a-git-repo ⇒ exit 1 with clear message. (D extra) PS `Compress-Archive` dotfiles fix + backup verification included. Parity Bash↔PowerShell mandatory.

L3 (2026-11-06): Branch fix/module9-git-deploy-failure-safety created from main @ 0b01ab5 (clean tree, zero open PRs, 11/11 CI green verified pre-branch). Module 9 suites today: bash 23 tests with stubbed git/tar/npm/systemctl; PS suite has no git stub (dry-run paths only) — will be extended per S6. Existing tests contain NO backup-failure expectation, so the S1 gate changes no current test's outcome.

L4 (2026-11-06): Implementation complete. Suites: bash 59/59, PS 41/41 (real hermetic git repositories; host git config isolated — the host's ~/.gitconfig rewrites https→git@ via insteadOf, which silently changed origin display; children now run with GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL=<empty file>). shellcheck -x clean; PSScriptAnalyzer clean (no suppressions; state-changing helpers declare SupportsShouldProcess). LAB3 verified end-to-end in mktemp scratch (gate abort with exit 2, rollback restores clean tree, --no-rollback preserves the conflict). Finding: Compress-Archive cannot archive hidden files on PowerShell 7 Unix ("Could not find item .env", even with -LiteralPath) — backup rebuilt on .NET ZipArchive + entry SHA-256 verify; test 14 (dotfiles) is the regression pin. PS verification deviates from L2's literal "expand + SHA-256": in-memory ZipArchive entry-hash compare (same checks, no temp-dir payload, empty archives supported). Docs updated (SPECS/README/ROADMAP/ARCHITECTURE_COMPARISON/SCENARIOS/LAB1-3/wiki 28-30/CHANGELOG/MODULES); GitHub Wiki sync pending user decision (manual, AGENTS.md §9).

L5 (verbatim, 2026-11-09): "Listo, avancemos. Empecemos a trabajar, pero porque RDD si estamos usando ODD? Aclaremos entonces antes de seguir." User clarified ODD vs RDD; then: "Ok, dejalo on entonces y emecemos a trabajar" — RDD stays ON for PR #64 delivery. Copilot review #64 (9 findings) analyzed and approved as follows: follow all 9 (2 dirty/nested add exit-1 guardrails; seed URL becomes truthful-empty; Bash gains `Backup verified` audit; PS -ErrorAction Stop; English typos). RED observed before fixes (bash 9 fails, PS 8 fails); GREEN after: bash 70/70, PS 51/51, ShellCheck + PSScriptAnalyzer clean. SPECS guardrails updated for dirty/nested/truthful-empty. T9 checked; S10 independent verifier, RDD assess/consent/review and merge still pending in T8.
