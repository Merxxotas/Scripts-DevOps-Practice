# Audit follow-up — current handoff

Updated 2026-11-26. Last verified functional main: `13526f7302781617c4c96979539c94ff199a1623`.
Disk [post-merge CI](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45879152227)
passed on that exact commit. The bounded ranked findings are delivered; the broader audit is
not exhaustive and must not be described as complete.

## Current disposition

Webhook Lab 1, Disk Lab 1 PowerShell caller-state preservation and Disk Lab 3 scratch audit
defaults shipped in PRs #92–94. Do not restart them. Optional test advisories remain in the
[delivery ledger](tasks/high-cpu-lab2-isolation.md); they are not blocking corrections or approval
for another implementation cycle. No additional functional unit is currently queued by this list.
Any wider audit needs a fresh bounded scope, not a claim that all repository hazards were checked.

Run Windows validation only in GitHub Actions. Never execute unsafe production examples,
read real credentials or touch real services.

## Completed — do not repeat

| Unit | Delivery record |
| --- | --- |
| Database Backup Lab 2, PR #80, main `5d28679` | [record](tasks/database-backup-lab2.md) |
| Database Backup Lab 1, PR #81, main `2dfc485` | [record](tasks/database-backup-lab1.md) |
| Kubernetes Lab 2, PR #77, main `e4e8bf2` | [record](tasks/k8s-lab2-isolation.md) |
| Log Cleanup Labs 1–3, PRs #74–76 | [Lab 1](tasks/log-cleanup-lab1.md), [Lab 2](tasks/log-cleanup-lab2.md), [Lab 3](tasks/log-cleanup-lab3.md) |
| Log Cleanup enumeration, PR #79, main `3c0cc5e` | [successful main CI](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45439516436) |
| High-CPU, Service Monitor, Kubernetes Lab 3, Git Deployment Lab 2, Disk scratch and production guards, PRs #82–83 and #87–90 | [ranked delivery ledger](tasks/high-cpu-lab2-isolation.md) |

Preserve rejected candidate `b04c20a` and its lineage; do not recover or replay it.
Preserve original Disk scratch candidate `70535b3` and its references. Its temporary worktree
was missing before the latest session; do not claim it is still available or silently prune metadata.
Dependabot PRs #84–86 were open at the last check and were not modified by this remediation.
Inspect their live state separately rather than assuming they are unchanged.

## Merge policy and temporary waiver

The standing policy has one home: [CONTRIBUTING.md — Merge flow](../CONTRIBUTING.md#merge-flow).
The maintainer explicitly waived waiting for Copilot during **November 2026 only**, until December,
because of exhausted credits. Recheck the date before using that waiver. From December onward,
apply the standing review/quota rule unless the maintainer provides a new explicit disposition.
No agent changed Copilot settings. This waiver does not disable RDD, CI or required GitHub approval.

For each authorized focused PR, verify the exact head, current base and merge tree, applicable
hosted checks and native RDD. Use the standing administrator exception only when required GitHub
approval is the sole remaining gate. Do not change branch protection. After merge, verify the
resulting main commit/tree and post-merge CI. Stop and ask for genuine doubts or blockers.

## Latest separate deliveries

| Unit | Main commit | Post-merge evidence |
| --- | --- | --- |
| Documentation/policy reconciliation, PR #91 | `c5d7315` | [Pages passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45870243968); module CI not applicable |
| Webhook Lab 1, PR #92 | `1998f55` | [CI passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45873523190) |
| Disk Lab 1 PowerShell state, PR #93 | `5e322d3` | [CI passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45877756298) |
| Disk Lab 3 rehearsal audit path, PR #94 | `13526f7` | [CI passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45879152227) |

## Local-only records

Raw operational notes were preserved in the local Git administrative directory before reconciliation.
They include obsolete temporary paths, raw prompts and a misnamed planning dump, not a publishable
audit report. Concise English delivery records above replace those unpublished notes; no blanket
ignore rule was added for `odd/tasks/`. Local archives are not part of a clone or a backup service.

## Resume

1. Read `AGENTS.md`, this handoff and the applicable task record.
2. Check local changes, fetch main and reconcile the live repository before editing.
3. Check the current disposition before selecting new work; keep functional and documentation PRs separate.
4. Preserve unrelated edits and historical candidate references. Never replay historical review authority.
5. Continue authorized in-scope work after each delivery; a completed unit is not an instruction to stop.
