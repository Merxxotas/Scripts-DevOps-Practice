# Module 10 — Kubernetes Pod Monitor and Restart

Branch: feat/10-kubernetes-pod-monitor
Delivery strategy: ask-on-risk
Test runner: bash tests/test_k8s_monitor.sh / pwsh tests/test_k8s_monitor.ps1

## Specs

S1 — Namespace. `-n/--namespace` (Bash) / `-Namespace` (PowerShell) sets the Kubernetes namespace (default `default`). Must be non-empty and DNS-label-safe; otherwise a configuration error (exit 1).

S2 — Label selector. `-l/--label` (Bash) / `-LabelSelector` (PowerShell) sets the label selector (default `app=web`). Must be non-empty; otherwise a configuration error (exit 1).

S3 — Restart threshold. `-r/--restart-threshold` (Bash) / `-RestartThreshold` (PowerShell) sets the restart count above which a pod is deleted (default 3). Must be a non-negative integer; otherwise a configuration error (exit 1).

S4 — Force. `--force` (Bash) / `-Force` (PowerShell) performs a hard delete (`--grace-period=0 --force`); default is a graceful delete.

S5 — Dry-run. `--dry-run` (Bash) / `-DryRun` (PowerShell) lists pods and which would be deleted, no deletion, exits 0.

S6 — Audit log. `--audit-log` (Bash) / `-AuditLog` (PowerShell) appends an ISO-8601 timestamped line per run. Best-effort.

S7 — Verbose. `-v/--verbose` (Bash) / `-Verbose` (PowerShell) prints per-step diagnostic detail.

S8 — Help. `-h/--help` (Bash) / `-Help` (PowerShell) prints usage and exits 0.

S9 — Guardrails. Namespace non-empty/DNS-safe, label selector non-empty, threshold non-negative integer, kubectl available. Config violations exit 1.

S10 — Discovery. List pods matching namespace + label selector; capture name, phase, restart count (sum across all containers). No pods found → print message, exit 0.

S11 — Action. For each pod whose restart count strictly exceeds the threshold, delete it (graceful or forced per --force). Record success/failure. A failed delete exits 2.

S12 — Output contract. Per pod: name, phase (colored), restarts, action (kept/deleted/failed). Summary block. Curlie-inspired formatting.

S13 — kubectl missing. If kubectl is not available, print error and exit 1.

S14 — Parity. Bash and PowerShell implement the same flags, defaults, exit codes and guardrails.

S15 — Tests. Deterministic suite stubbing kubectl under a temp dir; covers flags, exit codes, dry-run, guardrails, kubectl-missing, healthy/no-restart, threshold-exceeded delete success/failure, audit log. No cluster.

## Tasks

- [x] T1: Create feature document + Engram mirror (this file). route: inline
- [x] T2: Write SPECS.md, README.md, CODESTYLE.md, ROADMAP.md. route: inline
- [x] T3: Harden k8s_monitor.sh (Bash). route: inline
- [x] T4: Harden k8s_monitor.ps1 (PowerShell). route: inline
- [x] T5: Write Bash test suite tests/test_k8s_monitor.sh. route: inline
- [x] T6: Write PowerShell test suite tests/test_k8s_monitor.ps1. route: inline
- [x] T7: Write docs/ (ARCHITECTURE_COMPARISON, SCENARIOS, labs LAB1-3). route: inline
- [x] T8: Create root CI workflow .github/workflows/ci-kubernetes-pod-monitor.yml. route: inline
- [x] T9: Write wiki pages + sidebar. route: inline
- [x] T10: Register module in MODULES.md, README.md, CHANGELOG.md, AGENTS.md. route: inline
- [x] T11: Close feature document + Engram mirror. route: inline

## Log

L1: User request (verbatim): "Module 10 (Kubernetes Pod Monitor and Restart) — seed on disk only. Convert to shipped contract. Decisions: threshold default 3; delete semantics graceful default + --force opt-in; auto-delete by default + --dry-run; kubectl missing exit 1; restart count sum across all containers. Testing stubbed kubectl (no cluster). User has Docker only, no kubectl installed; CI uses fake kubectl."

L2: 2026-10-29 — Created feature branch feat/10-kubernetes-pod-monitor from main. Feature document created. Open decisions resolved and recorded.
L3: 2026-10-29 — Shipped module 10. Bash suite 36/0; PS suite CI-only. Risk: item 3 (new module added; contracts/docs/wiki registered). All 11 modules now shipped.
