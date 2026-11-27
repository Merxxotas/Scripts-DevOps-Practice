# Ranked lab safety remediation — delivery ledger

Status reconciled on 2026-11-26 against merged history and recorded post-merge evidence.
This ledger supersedes the earlier local-only and in-progress statuses.

## Delivered units

| Unit | PR | Main commit | Post-merge CI |
| --- | --- | --- | --- |
| High-CPU Lab 2 | [82](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/82) | `033c101` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45667785375) |
| Service Monitor Labs 1–2 | [83](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/83) | `047d148` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45669683705) |
| Kubernetes Lab 3 | [87](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/87) | `5c1f6ef` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45666991002) |
| Git Deployment Lab 2 | [88](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/88) | `90645fd` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45674309657) |
| Disk lab scratch isolation | [89](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/89) | `758cdf5` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45676072257) |
| Disk Lab 3 production guards | [90](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/90) | `b2aa004` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45865816789) |

Later deliveries:

| Unit | PR | Main commit | Post-merge CI |
| --- | --- | --- | --- |
| Webhook Lab 1 | [92](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/92) | `1998f55` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45873523190) |
| Disk Lab 1 PowerShell state | [93](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/93) | `5e322d3` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45877756298) |
| Disk Lab 3 scratch audit default | [94](https://github.com/Merxxotas/Scripts-DevOps-Practice/pull/94) | `13526f7` | [passed](https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/runs/45879152227) |

Each delivery cleared exact-candidate checks, applicable verification, native assessment and hosted CI.
Due native reviews were approved and acknowledged; PR #93 was assessed medium/under-budget, so
no review was due. Historical outcomes are not transferable authority for a different candidate.
High-CPU and Service Monitor final Bash suites passed 68/0 and 43/0 respectively.
Disk production helper verification passed 341/0 locally plus 29 independent public CLI cases.

## Current disposition

These bounded ranked findings are delivered. This is not an exhaustive repository-wide safety
assessment. Routine Bash prerequisite navigation was reviewed as normal directory navigation,
not an uncontained export or a demonstrated destructive effect; no broad rewrite was made.
Webhook fixture tests passed 5/0 plus six independent scenario groups. Disk PowerShell hosted
RED exposed both the original override leak and absent-entry restoration; final hosted checks
passed. Rehearsal audit tests passed 359/0 and preserve explicit log-file overrides.

## Deferred, non-blocking test improvements

- High-CPU relative TMPDIR/CDPATH and duplicated fault-injection harness readability.
- Service Monitor permanent post-precheck helper-loss probes; independently exercised.
- Disk production helper permanent partial-I/O regression; independently exercised.
- Webhook child-probe semicolon assertions can mask early permission failures; independent probes
  verified the private modes directly. Strengthen permanent assertions as separate follow-up.

Do not reopen delivered Database Backup Labs 1–2, Kubernetes Lab 2 or Log Cleanup.
Preserve rejected candidate `b04c20a` and its lineage. Original Disk candidate `70535b3`
remains referenced; its temporary checkout was already missing at the 2026-11-26 resume.
No worktree metadata was pruned or recreated. Do not claim the entire audit complete.
