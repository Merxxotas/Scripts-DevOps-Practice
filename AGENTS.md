# AGENTS.md — Scripts-DevOps-Practice

> **Read this first.** It is the router for this repository: what the repo is, the invariants a change
> must not break, and where every detail lives.
>
> **It deliberately does not repeat detail.** Each fact has exactly one home — this file holds the
> agent-facing invariants, [`CONTRIBUTING.md`](CONTRIBUTING.md) the contributor workflow,
> [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md) the expanded ODD protocol, [`MODULES.md`](MODULES.md) the
> module status, and [`wiki/`](wiki/) the deep dives. If something is not here, look it up.

---

## 1. What This Repository Is

**Scripts-DevOps-Practice** is a multi-language **DevOps automation practice monorepo**: 11
self-contained automation utilities, monitoring daemons and system utilities, each engineered to
production standard (spec → implementation → tests → CI → documentation → hands-on labs). It is a
**learning and portfolio repository** — the code doubles as a reference implementation.

| Property | Value |
| :--- | :--- |
| Repository | `Merxxotas/Scripts-DevOps-Practice` (public) · `main` · MIT |
| Layout | One folder per numbered module · Bash, PowerShell, Python, Go · one path-filtered CI workflow each |
| Knowledge base | [`wiki/`](wiki/) — 9 topic pages + Home, Sidebar, Footer |
| Methodology | ODD — Organic Driven Development (§2) |

**Monorepo philosophy.** There is **no single monolithic pipeline**. Each module owns its code,
tests, specification and CI workflow, and `paths:` filters guarantee that changing module 2 never
triggers module 11's pipeline. Polyglot by intent: Bash for Unix administration, PowerShell for
Windows and cross-platform .NET, Python for orchestration engines, Go for compiled daemons. →
[`wiki/01`](wiki/01-Monorepo-Architecture.md)

**Module status — check before assuming anything exists.** Shipped and committed: **2** (Log Cleanup),
**11** (EventOps) and **5** (CPU and Memory Usage Monitor). Seed, on disk only: **1, 3, 4, 6, 7, 8, 9, 10**.
Only modules 2, 5 and 11 are in git. → [`MODULES.md`](MODULES.md)

---

## 2. Methodology: ODD

> **Change notice (2026-10-20):** this repository previously ran a *Spec-Driven Development* (SDD)
> flow. It now runs **ODD — Organic Driven Development**, the gentle-ai implementation. SDD and ODD
> are **not** in conflict; the relationship is explained in §2.3.

The seven-phase protocol ships with the agent harness. This section indexes the repository-local
rules; the expanded form lives in [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md).

### 2.1 What ODD actually is

**Authorize → Explore → Resolve uncertainty → Classify → Track → Implement → Close.** Investigation,
review and audit are read-only unless implementation was explicitly requested; size is decided by the
resume test (§2.4), never by file count; work is handed off **by reference**, never by paraphrase. →
[`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.2 The ODD feature document

Large work only, created **automatically before the first source write**. The specification subagents
read lives at `odd/tasks/<feature-name>.md` — header, `## Specs` (`S1..Sn`, quoting the user's exact
strings verbatim), `## Tasks`, `## Log` — mirrored in Engram under `odd/<feature-name>/tasks`. →
[`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.3 How ODD relates to the module artifacts (SDD)

**ODD governs *how* the work happens; `SPECS.md` / `ROADMAP.md` govern *what the module is*.** The
module contract is unchanged. What changed is *when* the spec is written: under SDD a 200-line spec
came before anyone looked at the code; under ODD it crystallizes as the work lands. → [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.4 Task size — how to classify

Small when **understood**, **contained risk** and **resumable from the diff** all hold; large only when
the resume test fails. Small → inline, no durable artifacts. Large → feature document + mirror +
work-unit commits. → [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.5 Test-first policy

**Observe RED** before implementing, **implement GREEN**, then refactor while tests stay green. One
RED test per requested rule, asserting every observable effect through the public interface; one
regression test per existing option touched. → [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.6 Risk line — mandatory on every code change

Close every code change, inline or delegated, with exactly one of:

```
Risk: none
Risk: item 3 (removed public API without a deprecation path)
```

**High-risk items** — any of these raises the verification tier and forces an independent verifier:

| # | Item |
| :-- | :--- |
| 1 | **Data / irreversible effects** — migrations, changing or deleting stored data, persisted format changes. |
| 2 | **Security** — auth, permissions, credentials, secrets, guards, sandbox. |
| 3 | **Contracts others consume** — changing or removing a public API, CLI flag, config format, published export or mirrored contract. Adding one is not high risk. |
| 4 | **Concurrency** — locks, races, async ordering. |
| 5 | **Delivery / environment** — installers, release, CI, deploy, dependencies. |
| 6 | **No test would catch a regression** in what changes. |

Before writing `Risk: none`, check whether the diff changes code that **existing behaviour the
request did not mention** also uses. If it does, that is **item 3**.

### 2.7 Routing — inline versus delegated

**Small understood changes stay inline.** Delegate a writer only for **parallelism** (two or more
independent units with disjoint edit surfaces) or the **long-session context backstop** — never for
size, file count or price ratio. → [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md)

### 2.8 Delivery strategy

- **Work-unit commits** on a feature branch, one per coherent behaviour change, with tests and docs
  alongside the behaviour. **Conventional Commits**, scoped by module: `feat(log-cleanup):`,
  `fix(eventops-go):`, `docs(log-cleanup):`, `ci(eventops):`, `test(eventops):`. **Never** add
  `Co-Authored-By` or AI attribution trailers.
- **Delivery strategies** (one per feature): `ask-on-risk` *(default)*, `auto-chain`, `single-pr`,
  `exception-ok`. Above roughly **400 authored changed lines**, apply the strategy before the next
  commit — a heuristic, **not** a hard cap. Never shrink scope to hit it, never drop tests to hit it.
- **Push, PR creation and merge remain human decisions.** Never force-push, never amend published
  history, never open a PR unprompted.

### 2.9 Native review (receipt-driven development)

The review switch is **user-owned** — `gentle-ai review mode status` (read-only), `enable` (only
when the user explicitly asks), `disable` (when the user asks to stop). It is **on by default and
opt-out**; an unset preference permits review, but explicit global or clone-local **OFF** wins.
Candidate **consent is separate** from the mode default — global RDD enabled permits review but never
grants consent for a candidate.

The candidate is a **work-unit commit or a PR slice** — never a TODO checkbox, never the accumulated
feature branch. Never lower prospective candidate risk by substituting model judgement, task size or
defect severity, and never infer low risk from a failed assessment. When RDD is disabled: do not
start reviews, do not retry, and deliver under ordinary policy, reporting `disabled/unmanaged`.

### 2.10 Memory

Engram is the cross-session memory layer for this project. Project key: `scripts-devops-practice`.
Save proactively — decisions, bug fixes with root cause, non-obvious discoveries, conventions,
config changes, user preferences — in the format `**What**` / `**Why**` / `**Where**` / `**Learned**`.
On resume: `mem_context` → project-scoped `mem_search` → `mem_get_observation` → the feature
document. Close with `mem_session_summary`.

---

## 3. The Module Contract

Every numbered module folder is self-contained and ships:

```
<N>-<Module-Name>/
├── README.md              # usage, flags, scheduling examples, troubleshooting
├── SPECS.md               # technical specification & architecture
├── ROADMAP.md             # phased milestones, checkboxes = observed outcomes only
├── CODESTYLE.md           # module-specific coding conventions
├── <implementation>       # source: scripts, packages, binaries
├── tests/                 # automated test suites (see §6)
└── docs/                  # ARCHITECTURE_COMPARISON.md, SCENARIOS.md, labs/LAB1-3.md
```

Plus, at the **repository root**: a path-filtered `.github/workflows/ci-<module>.yml`; a row in
[`MODULES.md`](MODULES.md) and the module table in [`README.md`](README.md); a wiki page + sidebar entry.

**Non-negotiable invariants** — violating any of them is a defect:

1. **Self-contained.** A module never reaches into another module's code. Cross-module *references
   in documentation* are fine; code dependencies are not.
2. **Parity across platforms.** Bash and PowerShell must implement the **same flags, defaults, exit
   codes and safety guardrails**. A flag on only one side is a defect.
3. **Segregated CI.** Exactly one workflow per module, at the **repository root**, with `paths:`
   filters scoped to that module's folder.
4. **Safety first.** Anything that deletes, restarts, kills, mutates or notifies must ship
   guardrails, a dry-run mode where feasible, and a non-zero exit code on violation.
5. **English only.** All code, comments, identifiers, docs and commit messages.

`docs/` also carries `ARCHITECTURE_COMPARISON.md`, `SCENARIOS.md` and `labs/LAB1…LAB3.md`. **Labs are
executable documentation** — every command must actually run, and the expected output must be real.

---

## 4. Branching and Commits

Branch from `main` with `feat/<n>-<slug>` · `fix/<slug>` · `docs/<slug>` · `ci/<slug>` — `<n>` is the
module number when the work targets one module; `kebab-case` for the slug. Commits are
`<type>(<scope>): <imperative summary under 72 chars>` + an optional body explaining **WHY**, not what.

Types: `feat` `fix` `docs` `ci` `test` `refactor` `chore`. Scope is the module name. Imperative mood;
one logical change per commit, each buildable and CI-green on its own; the body explains **why**;
tests and docs ship in the same commit; **no** `Co-Authored-By` trailer and **no** AI attribution.

**Merge flow:** `feature branch → local fast-forward merge into main → push`. `main` has **no branch
protection and no rulesets**, so CI-green-before-merge is a **manual** obligation — check it with
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
- **Pin OS versions explicitly** (`ubuntu-24.04`, `macos-14`, `windows-2022`) — do not use
  `-latest` aliases for the matrix.
- **Never** bake credentials into the workflow. Use repository secrets. →
[`wiki/08-CI-CD-Pipelines.md`](wiki/08-CI-CD-Pipelines.md)

---

## 6. Testing Conventions

Suites live in `<module>/tests/` — Bash, `pwsh`, `pytest`, `go test`. Runners → [`CONTRIBUTING.md`](CONTRIBUTING.md) §Testing.

- Tests exercise the **public interface** (CLI flags, exit codes, emitted files), not internals.
- Every test must be **deterministic**: pin timestamps, isolate the filesystem under a temp dir,
  never depend on the host's real services, disk layout, or locale, and clean up after themselves.
- A test that cannot be run in CI does not belong in the suite.
- When a change touches an existing command or option, add a **regression test** proving the old
  behaviour still holds (§2.5).

---

## 7. Code Standards

Authoritative source: each module's `CODESTYLE.md`. Full baseline in
[`CONTRIBUTING.md`](CONTRIBUTING.md) §Code Standards and [`wiki/09`](wiki/09-Code-Style-and-Standards.md).
The rules that break things most often:

- **English only** — code, comments, identifiers, docs, commit messages. **B2 English**, lines under
  **100 characters**. Python **PEP 8**; PowerShell **Approved Verb-Noun** naming. `snake_case`
  variables and functions, `PascalCase` types, `UPPER_SNAKE_CASE` constants, `kebab-case` CLI flags.
- **No `print()` in production code** — structured logging instead. Catch **specific** exceptions,
  never a bare `except Exception:`. Every destructive action writes an **audit line**. Comments explain
  **why**, not what; no commented-out code in `main`, no `TODO` without a linked issue.
- **Exit codes are a public contract:** `0` success, `1` configuration/safety violation,
  `2` partial failure. Document them in the README.
- **Never hardcode secrets.** Read from the environment and fail loudly when unset. Validate and
  sanitise every external input — paths, arguments, JSON payloads, webhook bodies.
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
| Know what changed and when | [`CHANGELOG.md`](CHANGELOG.md) |
| Contribute code | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Report a vulnerability | [`SECURITY.md`](SECURITY.md) |
| Ask a question | [`SUPPORT.md`](SUPPORT.md) |

---

## 9. Known State and Gotchas

Verified on **2026-10-21**. These are real, current, and will bite you.

| # | Gotcha |
| :-- | :--- |
| 1 | **Modules 1, 3, 4, 6, 7, 8, 9, 10 are not in git.** On the working disk only; `git log --all` shows zero history. They also miss `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, tests and CI — so they violate the module contract (§3). |
| 2 | **Module 1 is the next ship.** The seed modules are raw script pairs with no CLI parser, guardrails, tests, docs or CI. The checklist is in [`MODULES.md`](MODULES.md). |
| 3 | **Path filters create a blind spot.** Changes under `wiki/`, `MODULES.md`, `AGENTS.md` and the other root docs match no workflow, so they trigger **no CI run**. Documentation changes are never automatically validated. |
| 4 | **The wiki lives in two places** — committed to `main:wiki/` **and** published as the GitHub Wiki (a separate `Scripts-DevOps-Practice.wiki.git` repo). Verified byte-identical on 2026-10-20, but nothing enforces it. **When you edit a wiki page, push it to both.** |
| 5 | **`main` is unprotected.** No branch protection, no rulesets, no required checks. |
| 6 | **`.gitattributes` normalizes line endings, so the index and the working tree disagree for `.ps1`.** PowerShell files are stored as LF and checked out as CRLF. Any byte-identity or checksum comparison against the committed blob will differ for files that have been re-checked out — compare with `git show HEAD:<path>`, not with the working file. |
| 7 | **Go version drift.** CI pins Go `1.22`; newer toolchains work, but keep the pin current. |
| 8 | **Private vulnerability reporting is not enabled on the remote yet.** It needs one click in the GitHub UI (*Settings → Code security*) and cannot be toggled through the REST API. Until it is on, [`SECURITY.md`](SECURITY.md) directs reporters to the maintainer's email. |

---

## 10. Working Agreements

- **One question at a time.** Ask, then stop and wait. Never bundle menus of options unless there is
  a real fork with meaningful trade-offs.
- **Never agree without verifying.** Check the code, docs, or run output before confirming a claim.
- **Prose in artifacts is English.** Chat replies follow the user's language; repository artifacts
  stay English.
- **Preserve human control.** Push, PR creation, merges and releases are the user's decisions.
- **Report faithfully.** State failed, skipped and pending checks honestly. A hedge is not a stop.
- **Match the harness to the work.** Small understood change → inline. Large, tracked, or genuinely
  parallel → the ODD machinery.

---

*Last reviewed: 2026-10-20 · Methodology: ODD (Organic Driven Development) via gentle-ai*
