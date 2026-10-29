# AGENTS.md — Scripts-DevOps-Practice

> **Read this first.** Router: what the repo is, the invariants a change must not break, and where every
> detail lives. Detail has exactly one home — [`CONTRIBUTING.md`](CONTRIBUTING.md) (contributor workflow),
> [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md) (expanded ODD protocol), [`MODULES.md`](MODULES.md) (module
> status), [`wiki/`](wiki/) (deep dives). If something is not here, look it up.

---

## 1. What This Repository Is

**Scripts-DevOps-Practice** is a multi-language **DevOps automation practice monorepo**: 11 self-contained
automation utilities, monitoring daemons and system utilities, each engineered to production standard
(spec → implementation → tests → CI → documentation → hands-on labs). It is a **learning and portfolio
repository** — the code doubles as a reference implementation.

| Property | Value |
| :--- | :--- |
| Repository | `Merxxotas/Scripts-DevOps-Practice` (public) · `main` · MIT |
| Layout | One folder per numbered module · Bash, PowerShell, Python, Go · one path-filtered CI workflow each |
| Knowledge base / Methodology | [`wiki/`](wiki/) (9 pages) · ODD (§2) |

**Monorepo philosophy.** No single monolithic pipeline: each module owns its code, tests, spec and CI
workflow; `paths:` filters guarantee changing module 2 never triggers module 11's pipeline. Polyglot by
intent: Bash (Unix admin), PowerShell (Windows/.NET), Python (orchestration), Go (compiled daemons). →
[`wiki/01`](wiki/01-Monorepo-Architecture.md)

**Module status — check before assuming anything exists.** Shipped: **1** (Disk Usage), **2** (Log Cleanup), **3** (Database Backup), **4** (Service Monitor and Auto-Restart), **5** (CPU/Memory Monitor), **7** (Find and Kill High-CPU Processes), **8** (Log Rotation and Compression), **9** (Automated Git Deployment), **11** (EventOps).
Seed, on disk only: **6, 10**. →
[`MODULES.md`](MODULES.md)

---

## 2. Methodology: ODD

ODD is the gentle-ai implementation. SDD (the previous flow) and ODD are **not** in conflict — ODD governs
*how* the work happens; `SPECS.md`/`ROADMAP.md` govern *what the module is*. The seven-phase protocol ships
with the agent harness; expanded repository-local rules (phases, task size, test-first, routing, delivery
strategy, native review/RDD, memory) live in [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md). This section keeps
only the risk line, which every code change must carry.

**Risk line — mandatory on every code change.** Close every change with exactly one of:

```
Risk: none
Risk: item 3 (removed public API without a deprecation path)
```

High-risk items (any raises the verification tier and forces an independent verifier): 1 data/irreversible
effects (migrations, changing/deleting stored data, persisted format changes); 2 security (auth, permissions,
credentials, secrets, guards, sandbox); 3 contracts others consume (changing/removing a public API, CLI flag,
config format, published export or mirrored contract — adding one is not high risk); 4 concurrency (locks,
races, async ordering); 5 delivery/environment (installers, release, CI, deploy, dependencies); 6 no test
would catch a regression in what changes.

Before writing `Risk: none`, check whether the diff changes code that **existing behaviour the request did
not mention** also uses. If it does, that is **item 3**.

---

## 3. The Module Contract

Every numbered module folder is self-contained and ships:

```
<N>-<Module-Name>/: README.md · SPECS.md · ROADMAP.md · CODESTYLE.md · <impl> · tests/ · docs/
```

Plus, at the **repository root**: a path-filtered `.github/workflows/ci-<module>.yml`; a row in
[`MODULES.md`](MODULES.md) and the module table in [`README.md`](README.md); a wiki page + sidebar entry.

**Non-negotiable invariants** — violating any of them is a defect:

1. **Self-contained.** A module never reaches into another module's code. Cross-module *references in
   documentation* are fine; code dependencies are not.
2. **Parity across platforms.** Bash and PowerShell must implement the **same flags, defaults, exit codes
   and safety guardrails**. A flag on only one side is a defect.
3. **Segregated CI.** Exactly one workflow per module, at the **repository root**, with `paths:` filters
   scoped to that module's folder.
4. **Safety first.** Anything that deletes, restarts, kills, mutates or notifies must ship guardrails, a
   dry-run mode where feasible, and a non-zero exit code on violation.
5. **English only.** All code, comments, identifiers, docs and commit messages.

**Labs are executable documentation** — every command must actually run, and the expected output must be real.

---

## 4. Branching and Commits

Branch from `main`: `feat/<n>-<slug>` · `fix/<slug>` · `docs/<slug>` · `ci/<slug>` (`<n>` = module number
when targeting one module; `kebab-case` slug). Commits: `<type>(<scope>): <imperative summary ≤72 chars>` +
optional body explaining **WHY**, not what. Types: `feat` `fix` `docs` `ci` `test` `refactor` `chore`. Scope
= module name. Imperative mood; one logical change per commit, each buildable and CI-green on its own; tests
and docs ship with it; **no** `Co-Authored-By` or AI attribution.

**Merge flow:** `feature branch → local fast-forward merge into main → push`. `main` has **no branch
protection and no rulesets**, so CI-green-before-merge is a **manual** obligation — check with
`gh run list --workflow ci-<module>.yml --branch main --limit 1`. → [`CONTRIBUTING.md`](CONTRIBUTING.md)

---

## 5. CI/CD Model

One workflow per module, at the repository root, path-filtered to that module's folder. Both shipped
workflows trigger on `push` to `main`, `feat/**`, `fix/**` and `pull_request` to `main`.

### 5.1 Gates

Bash `shellcheck -x` · PowerShell `PSScriptAnalyzer` · Python `ruff check` + `ruff format --check` +
`pytest` · Go `go vet ./...` + `go test ./...`.

### 5.2 Rules when adding a workflow

- **One workflow per module.** Never a "monolithic" build for the whole repo.
- **Always at the repository root** in `.github/workflows/`. GitHub ignores workflows in nested
  `.github/` folders — a module's pipeline placed inside its own folder **will never run**.
- **Always path-filtered**, including the workflow file itself.
- **Pin OS versions explicitly** (`ubuntu-24.04`, `macos-14`, `windows-2022`) — do not use `-latest`
  aliases for the matrix.
- **Never** bake credentials into the workflow. Use repository secrets. →
[`wiki/08-CI-CD-Pipelines.md`](wiki/08-CI-CD-Pipelines.md)

---

## 6. Testing Conventions

Suites live in `<module>/tests/` — Bash, `pwsh`, `pytest`, `go test`. Runners → [`CONTRIBUTING.md`](CONTRIBUTING.md) §Testing.

- Tests exercise the **public interface** (CLI flags, exit codes, emitted files), not internals.
- Every test must be **deterministic**: pin timestamps, isolate the filesystem under a temp dir, never
  depend on the host's real services, disk layout, or locale, and clean up after themselves.
- A test that cannot be run in CI does not belong in the suite.
- When a change touches an existing command or option, add a **regression test** proving the old
  behaviour still holds (§2.5).

---

## 7. Code Standards

Authoritative source: each module's `CODESTYLE.md`. Full baseline in
[`CONTRIBUTING.md`](CONTRIBUTING.md) §Code Standards and [`wiki/09`](wiki/09-Code-Style-and-Standards.md).
The rules that break things most often:

- **English only** — code, comments, identifiers, docs, commit messages. **B2 English**, lines under
  **100 characters**. Python **PEP 8**; PowerShell **Approved Verb-Noun** naming. `snake_case` variables
  and functions, `PascalCase` types, `UPPER_SNAKE_CASE` constants, `kebab-case` CLI flags.
- **No `print()` in production code** — structured logging instead. Catch **specific** exceptions, never a
  bare `except Exception:`. Every destructive action writes an **audit line**. Comments explain **why**,
  not what; no commented-out code in `main`, no `TODO` without a linked issue.
- **Exit codes are a public contract:** `0` success, `1` configuration/safety violation, `2` partial
  failure. Document them in the README.
- **Never hardcode secrets.** Read from the environment and fail loudly when unset. Validate and sanitise
  every external input — paths, arguments, JSON payloads, webhook bodies.
- **Guardrail destructive paths.** Refuse to operate on `/`, `C:\`, `/etc`, `/var`, system directories.
  Prefer **dry-run** modes. Never log credentials or tokens.
- Bash scripts start with `set -euo pipefail` and `IFS=$'\n\t'`.

---

## 8. Navigation Map

| I want to… | Go to |
| :--- | :--- |
| Understand the architecture | [`wiki/01-Monorepo-Architecture.md`](wiki/01-Monorepo-Architecture.md) |
| EventOps — overview, Python vs Go, scenarios & labs | [`wiki/02`](wiki/02-EventOps-Overview.md) · [`03`](wiki/03-EventOps-Python-vs-Go.md) · [`04`](wiki/04-EventOps-Scenarios-and-Labs.md) |
| CPU Monitor — overview, Bash vs PowerShell vs Python, scenarios & labs | [`wiki/10`](wiki/10-CPU-Monitor-Overview.md) · [`11`](wiki/11-CPU-Monitor-Bash-vs-PowerShell.md) · [`12`](wiki/12-CPU-Monitor-Scenarios-and-Labs.md) |
| Log Cleanup — overview, Bash vs PowerShell, scenarios & labs | [`wiki/05`](wiki/05-Log-Cleanup-Overview.md) · [`06`](wiki/06-Log-Cleanup-Bash-vs-PowerShell.md) · [`07`](wiki/07-Log-Cleanup-Scenarios-and-Labs.md) |
| CI/CD philosophy and code standards | [`wiki/08`](wiki/08-CI-CD-Pipelines.md) · [`wiki/09`](wiki/09-Code-Style-and-Standards.md) |
| Know a module's status | [`MODULES.md`](MODULES.md) |
| Contribute code | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Report a vulnerability | [`SECURITY.md`](SECURITY.md) |

---

## 9. Known State and Gotchas

Verified on **2026-10-21**. These are real, current, and will bite you.

| # | Gotcha |
| :-- | :--- |
| 1 | **All modules shipped** — no seed modules remain on disk. |
| 2 | **Path filters create a blind spot** — changes under `wiki/`, `MODULES.md`, `AGENTS.md` and other root docs match no workflow → no CI run. |
| 3 | **The wiki lives in two places** — `main:wiki/` and the GitHub Wiki (`Scripts-DevOps-Practice.wiki.git`). Verified identical 2026-10-20, nothing enforces it. Push edits to both. |
| 4 | **`main` is unprotected** — no branch protection, rulesets or required checks. |
| 5 | **`.gitattributes` normalizes line endings** — `.ps1` stored LF, checked out CRLF. Compare with `git show HEAD:<path>`, not the working file. |
| 6 | **Go version drift** — CI pins Go `1.22`; newer toolchains work, but keep the pin current. |
| 7 | **Private vulnerability reporting not enabled** — needs one click in GitHub UI (*Settings → Code security*). Until on, [`SECURITY.md`](SECURITY.md) directs reporters to the maintainer's email. |

---

## 10. Working Agreements

- **One question at a time.** Ask, then stop and wait. Never bundle menus unless there is a real fork with meaningful trade-offs.
- **Never agree without verifying.** Check code, docs or run output before confirming a claim.
- **Prose in artifacts is English.** Chat replies follow the user's language; repository artifacts stay English.
- **Preserve human control.** Push, PR creation, merges and releases are the user's decisions.
- **Report faithfully.** State failed, skipped and pending checks honestly. A hedge is not a stop.
- **Match the harness to the work.** Small understood change → inline. Large, tracked or genuinely parallel → the ODD machinery.
