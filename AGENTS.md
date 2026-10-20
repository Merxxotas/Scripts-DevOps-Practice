# AGENTS.md — Scripts-DevOps-Practice

> **Read this file first.** It is the single source of truth for how this repository works.
> It replaces the need to load any global or user-level `AGENTS.md` for project context.

---

## 1. What This Repository Is

**Scripts-DevOps-Practice** is a multi-language **DevOps automation practice monorepo**. It collects
self-contained automation utilities, monitoring daemons, and system utilities — each one modelled as
a real production module with a full engineering lifecycle (spec → implementation → tests → CI →
documentation → hands-on labs).

It is a **learning and portfolio repository**. Every module is deliberately engineered to the same
standard you would meet in a production team, so the code doubles as a reference implementation.

| Property | Value |
| :--- | :--- |
| Repository | `Merxxotas/Scripts-DevOps-Practice` (public) |
| Default branch | `main` |
| License | MIT (see [`LICENSE`](LICENSE)) |
| Layout | Monorepo — one folder per numbered module |
| Languages | Bash, PowerShell, Python, Go |
| CI | GitHub Actions, one path-filtered workflow per module |
| Knowledge base | [`wiki/`](wiki/) — 9 topic pages plus Home, Sidebar and Footer |

### 1.1 The monorepo philosophy

There is **no single monolithic pipeline**. Each module owns its code, its tests, its
specification, and its CI workflow. Modifying module 2 must never trigger module 11's pipeline.
This isolation is enforced with GitHub Actions `paths:` filters.

**Polyglot by intent.** We do not force one language on every problem:

| Technology | Role | Why |
| :--- | :--- | :--- |
| **Bash** | Linux / macOS administration | Zero dependencies, instant start, coreutils portability. |
| **PowerShell** | Windows administration, cross-platform .NET | Object pipeline, native WMI/CIM, real cross-platform runtime. |
| **Python** | Cross-platform orchestration engines | Rich ecosystem (`watchdog`), rapid iteration, testability. |
| **Go** | Compiled standalone daemons | Static binaries, <5 MB RAM, ~2 ms startup, native goroutines. |

### 1.2 Module inventory

**→ Full status, ownership and build order live in [`MODULES.md`](MODULES.md).** Quick view:

| # | Module | Tech | CI | Shipped |
| :-- | :--- | :--- | :-- | :-- |
| 1 | Disk Usage Monitoring with Email Alert | Bash / PowerShell | — | Local only (seed) |
| 2 | Log Cleanup (files older than X days) | Bash / PowerShell | ✅ | **Yes** |
| 3 | Automated Database Backup with Timestamp | Bash / PowerShell | — | Local only (seed) |
| 4 | Service Monitor and Auto-Restart | Bash / PowerShell | — | Local only (seed) |
| 5 | CPU and Memory Usage Monitor | Bash / PowerShell / Python / Docker | — | Local only (capstone) |
| 6 | Website Availability (HTTP Health Check) | Bash / PowerShell | — | Local only (seed) |
| 7 | Find and Kill High-CPU Processes | Bash / PowerShell | — | Local only (seed) |
| 8 | Log Rotation and Compression | Bash / PowerShell | — | Local only (seed) |
| 9 | Automated Git Deployment | Bash / PowerShell | — | Local only (seed) |
| 10 | Kubernetes Pod Monitor and Restart | Bash / PowerShell | — | Local only (seed) |
| 11 | Scheduling and Automation (EventOps) | Python / Go | ✅ | **Yes** |

> **Note:** "Local only (seed)" means the folder exists on the working disk but was never committed.
> `git log --all` confirms modules 1, 3, 4, 5, 6, 7, 8, 9 and 10 have **zero history** in this
> repository. See [`MODULES.md`](MODULES.md) for the remediation plan.

---

## 2. Methodology: Organic Driven Development (ODD)

> **Change notice (2026-10-20):** this repository previously ran a *Spec-Driven Development* (SDD)
> flow. It now runs **ODD — Organic Driven Development**, the gentle-ai implementation.
> SDD and ODD are **not** in conflict; the relationship is explained in §2.3.

### 2.1 What ODD actually is

ODD is a **smallest-safe-harness** way of shipping: explore before writing, track only what
survives a compaction, implement one task at a time, and close every change with observed proof.

The seven-step protocol, in order, on every request:

1. **Authorize.** Establish whether the request actually authorizes a change. Investigation,
   explanation, review, audit and planning are **read-only** unless implementation was explicitly
   requested. If intent is ambiguous, ask **one** question and stay read-only.
2. **Explore.** Inspect the existing code and requirements first, proportionately. Never explore files
   you are about to read anyway before writing inline.
3. **Resolve uncertainty.** Recommend research only for a named uncertainty. Ask **one** focused
   question only for a genuine product decision, then stop and wait.
4. **Classify.** Size the task (see §2.4). Size is decided by whether the work is resumable from the
   original request plus `git diff` — **never** by file count, line count or todo-list length.
5. **Track before the first write.** Only for **large** work: create `odd/tasks/<feature-name>.md`
   plus its Engram mirror. Small work creates no durable artifacts.
6. **Implement task by task.** Hand off by reference, never by paraphrase. Observe RED before the
   fix, reach GREEN, then refactor. Check off a task only after its outcome and checks were observed.
7. **Close.** Report the verified outcome, every failed / skipped / pending check, and the next step.
   **Every code change closes with a `Risk:` line** (§2.6).

### 2.2 The ODD feature document (large work only)

Created **automatically before the first source write** — no permission prompt for tasks or storage.

```
odd/tasks/<feature-name>.md          # the specification subagents read, by reference
```

Fixed section order, stable content first, growing log last:

| Section | Contents |
| :--- | :--- |
| *Header* | Two or three lines: objective, branch, delivery strategy, test runner. |
| `## Specs` | Numbered `S1..Sn`. **Quote the user's exact strings, commands, error messages and examples verbatim.** Never reword them. Never add requirements the user did not ask for. Mark assumptions as assumptions. |
| `## Tasks` | One line per task: stable ID, linked `S#`, route (inline or delegated), status, commit identity or RED/GREEN evidence. |
| `## Log` | `L1` holds the user's original request **verbatim**. Later user corrections, evidence and decisions are appended. A requirement change rewrites only the affected `S#` and reopens only its linked task. |

An **Engram mirror** is kept under topic `odd/<feature-name>/tasks`, scoped to this project. It
stores the full current document plus its repository-relative locator. If Engram is unavailable,
preserve local progress and mark the mirror pending — never claim success.

### 2.3 How ODD relates to the module artifacts (SDD)

This is the part that trips people up, so be explicit:

| | **ODD (process)** | **Module artifacts (deliverable)** |
| :--- | :--- | :--- |
| Question answered | *How do we get this built safely?* | *What exactly did we build, and how is it used?* |
| Lifetime | Per feature, per session | Per module, permanent |
| Content | Numbered `S#` specs derived from the **actual request**, task breakdown, risk lines, evidence log | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`, `docs/` |
| Written when | Immediately before the first write, not weeks in advance | As the module is developed |

**Rule of thumb:** ODD governs *how the work happens*; `SPECS.md` / `ROADMAP.md` govern *what the
module is*. A module still ships `SPECS.md` and `ROADMAP.md` — they are the module's public
contract with a human reader. But you no longer write a 200-line specification **before** anyone has
looked at the code; ODD lets the specification crystallize from the real request as the work lands.

**Module contract (unchanged, still mandatory):** every module folder ships its own
`SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`, tests, and `docs/`.

### 2.4 Task size — how to classify

A task is **small** when all three hold:

1. **Understood** — outcome, location and change are known; provable within one bounded read batch.
2. **Contained risk** — touches no high-risk item (§2.6).
3. **Resumable from the diff** — someone could finish it from the original request plus `git diff`.

A task is **large** only when the resume test fails: several sessions, waiting on something
external, separate deliverables, or requirements too long to survive a compaction.

| | Small | Large |
| :--- | :--- | :--- |
| Route | Direct inline | Inline **or** delegated (see §5) |
| Feature document | None | `odd/tasks/<feature>.md` + Engram mirror |
| Commits | Only if asked | Work-unit commits on a feature branch |
| Engram mirror | Optional | Required |

### 2.5 Test-first policy

Apply to **behaviour changes** when a runnable deterministic test and a clear expected outcome exist:

- **Observe RED** before implementing. **Implement GREEN.** Then **refactor** while tests stay green.
- **One RED test per requested rule.** Each test asserts *every* observable effect of the rule —
  output, exit code, persisted data — and goes through the **public interface**, not internals.
- **For every existing command or option the change touches**, add one test proving the previous
  behaviour still holds. Add no other cases.
- An existing behaviour counts as *touched* when it shares code you changed (shared options, parsers,
  helpers, validation). The presence of a test framework alone does **not** establish applicability.
- For passive documentation, an unavailable runner, or no meaningful runnable RED: **explain the
  exception** and run proportionate functional or structural checks.
- **Never invent RED/GREEN evidence or a runner.** Record what was actually observed.

### 2.6 Risk line — mandatory on every code change

Close every code change, inline or delegated, with exactly one of:

```
Risk: none
Risk: item 3 (removed public API without a deprecation path)
```

**High-risk items** — any of these raises the verification tier and forces an independent verifier:

| # | Item |
| :-- | :--- |
| 1 | **Data / irreversible effects** — migrations, changing or deleting existing stored data, persisted format changes. |
| 2 | **Security** — auth, permissions, credentials, secrets, guards, sandbox. |
| 3 | **Contracts others consume** — changing or removing a public API, CLI flag, config format, published export, or mirrored prompt/contract. (Adding a flag, command or optional field is *not* high risk.) |
| 4 | **Concurrency** — locks, races, async ordering. |
| 5 | **Delivery / environment** — installers, release, CI, deploy, dependencies. |
| 6 | **No test would catch a regression** in what changes. |

Before writing `Risk: none`, check whether the diff changes code that **existing behaviour the
request did not mention** also uses. If it does, that is **item 3**.

### 2.7 Routing — inline versus delegated

| Action | Direct inline | Delegated worker |
| :--- | :--- | :--- |
| Read to decide or route | ✅ one bounded batch (≤3 calls, ~10k tokens) | — |
| Understanding beyond that budget, or ~5+ sequential lookups | — | ✅ one read-only explorer |
| One understood change (any number of files) | ✅ | — |
| A write with a **writer reason** | — | ✅ one bounded writer per unit |
| Tests, builds, installs, native review actions | ✅ | ✅ fresh worker is allowed |
| High-risk change | ✅ own checks | ✅ independent verifier required |

**Mandatory delegation triggers** — fire the moment they apply, do not continue inline past them:

- **Ask trigger** — one genuine product decision → ask one question, then stop and wait.
- **Mapping trigger** — understanding exceeds the inline budget → delegate one read-only explorer,
  return at most ~2k tokens with `path:line` evidence, plus one parent spot check.
- **Verification trigger** — a high-risk change → independent verifier after the change's own checks.
- **Tracking trigger** — a large task → feature document, mirror, and work-unit commits.
- **Writer trigger** — delegate a writer **only** for a named reason: parallelism (2+ independent
  units with disjoint edit surfaces) or the long-session context backstop. **Never** for size, a
  large task alone, file count, or price ratio.
- **Preparation trigger** — when a write is delegated, delegate the reading that prepares it too.
- **Output budget** — keep parent shell output to counts, `--stat`, `tail` or summaries.
- **Route declaration** — record the chosen route per task in the feature document.

### 2.8 Delivery strategy

- **Work-unit commits** on a feature branch, one per coherent behaviour change, with tests and docs
  alongside the behaviour.
- **Conventional Commits**, scoped by module: `feat(log-cleanup):`, `fix(eventops-go):`,
  `docs(log-cleanup):`, `ci(eventops):`, `test(eventops):`.
- **Never** add `Co-Authored-By` or AI attribution trailers.
- **Delivery strategies** (one per feature): `ask-on-risk` *(default)*, `auto-chain`, `single-pr`,
  `exception-ok`. Above roughly **400 authored changed lines** (additions + deletions, generated
  files excluded), apply the chosen strategy before the next commit. This is a planning heuristic,
  **not** a hard cap — never shrink scope to hit it, and never drop tests to hit it.
- **Push, PR creation and merge remain human decisions.** Never force-push, never amend published
  history, never open a PR unprompted.

### 2.9 Native review (receipt-driven development)

The review switch is **user-owned**:

```bash
gentle-ai review mode status   # read-only
gentle-ai review mode enable   # only when the user explicitly asks
gentle-ai review mode disable  # when the user asks to stop
```

- It is **on by default and opt-out**. An unset preference permits review without recording a
  decision; explicit global or clone-local **OFF** wins.
- Candidate **consent is separate** from the mode default. Global RDD enabled permits review; it
  never grants consent for a candidate.
- The candidate is a **work-unit commit or a PR slice** — never a TODO checkbox, never the
  accumulated feature branch.
- Do not substitute model judgement, task size, or defect severity to lower prospective candidate
  risk. Never infer low risk from a failed assessment.
- When RDD is disabled: do not start reviews, do not retry, do not reactivate it, and deliver under
  ordinary repository policy, reporting `disabled/unmanaged`.

### 2.10 Memory

Engram is the cross-session memory layer for this project. Project key: `scripts-devops-practice`.

- Save proactively: decisions, bug fixes with root cause, non-obvious discoveries, conventions,
  configuration changes, user preferences.
- Format: `**What**` / `**Why**` / `**Where**` / `**Learned**`.
- On resume: `mem_context` → project-scoped `mem_search` → `mem_get_observation` → then read the
  actual feature document. Do not infer active work from the newest global memory.
- Close a session with `mem_session_summary`.

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

**Non-negotiable invariants**

1. **Self-contained.** A module never reaches into another module's code. Cross-module *references
   in documentation* are fine; code dependencies are not.
2. **Parity across platforms.** Where a module ships both Bash and PowerShell, both implement the
   **same flags, defaults, exit codes and safety guardrails**. A flag that exists only on one side
   is a defect.
3. **Segregated CI.** Exactly one workflow per module, at the **repository root**, with `paths:`
   filters scoped to that module's folder.
4. **Safety first.** Anything that deletes, restarts, kills, mutates or notifies must ship
   guardrails, a dry-run mode where feasible, and a non-zero exit code on violation.
5. **English only.** All code, comments, identifiers, docs and commit messages.

### 3.1 `docs/` contents

| File | Purpose |
| :--- | :--- |
| `ARCHITECTURE_COMPARISON.md` | Deep dive comparing the implementations (e.g. POSIX byte streams vs .NET object pipelines), with a feature/architecture matrix. |
| `SCENARIOS.md` | Real production deployments: Problem → Solution Architecture → Directory Layout → exact commands → verification. |
| `labs/LAB1…LAB3.md` | Hands-on, step-by-step guides with prerequisites, sandbox setup, expected output and cleanup. |

Labs are **executable documentation**. Every command in a lab must actually run, and the stated
expected output must match reality.

---

## 4. Branching and Commits

### 4.1 Branch naming

| Pattern | Use |
| :--- | :--- |
| `feat/<n>-<slug>` | New module or new feature: `feat/2-log-cleanup-spec-and-docs` |
| `fix/<slug>` | Defect fix: `fix/windows-ci-compat` |
| `docs/<slug>` | Documentation-only change |
| `ci/<slug>` | Pipeline-only change |

`<n>` is the module number when the work targets one module (`feat/11-...`).

### 4.2 Commit format

```
<type>(<scope>): <imperative summary under 72 chars>

<optional body: WHY, not WHAT>
```

| Type | Use |
| :--- | :--- |
| `feat` | New capability |
| `fix` | Defect correction |
| `docs` | Documentation |
| `ci` | Workflows, matrices, linters |
| `test` | Test suites and fixtures |
| `refactor` | Behaviour-preserving restructuring |
| `chore` | Tooling, dependencies, housekeeping |

`<scope>` is the module name (`log-cleanup`, `eventops`, `eventops-go`, `rule-engine`, `ci`, `wiki`).

**Rules**

- Imperative mood: *"add webhook debouncing"*, not *"added"*.
- One logical change per commit. A commit must build and pass CI on its own.
- Body explains **why**; the diff already shows **what**.
- **No** `Co-Authored-By` trailer and **no** AI attribution.
- Update the docs in the **same commit** as the behaviour change.

### 4.3 Merge flow

```
feature branch  →  local fast-forward merge into main  →  push
```

This is the flow actually used to date. `main` currently has **no branch protection and no
rulesets**, so CI-green-before-merge is a **manual** obligation — check the run list yourself:

```bash
gh run list --limit 10
gh run list --workflow ci-cleanup-logs.yml --branch main --limit 1
```

---

## 5. CI/CD Model

Two workflows ship today, one per built module, both at the repository root:

| Workflow | Module | Trigger paths |
| :--- | :--- | :--- |
| `.github/workflows/ci-cleanup-logs.yml` | 2 — Log Cleanup | `2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/**` |
| `.github/workflows/ci-eventops.yml` | 11 — EventOps | `11-Scheduling-And-Automation/**` |

Both trigger on `push` to `main`, `feat/**`, `fix/**`, and on `pull_request` to `main`, and both
include their own workflow file in the `paths:` list so a pipeline edit still runs the pipeline.

### 5.1 Matrices and gates

| Workflow | Jobs |
| :--- | :--- |
| Log Cleanup | ShellCheck · Bash on `ubuntu-24.04` + `macos-14` · PowerShell on `windows-2022` + `ubuntu-24.04` |
| EventOps | `ubuntu-24.04` + `macos-14` + `windows-2022` × Python `3.10` / `3.11` / `3.12` |

Gates, by language:

| Language | Gate |
| :--- | :--- |
| Bash | `shellcheck -x` |
| PowerShell | `PSScriptAnalyzer` |
| Python | `ruff check` + `ruff format --check` + `pytest` |
| Go | `go vet ./...` + `go test ./...` |

### 5.2 Rules when adding a workflow

- **One workflow per module.** Never a "monolithic" build for the whole repo.
- **Always at the repository root** in `.github/workflows/`. GitHub ignores workflows in nested
  `.github/` folders — a module's pipeline placed inside its own folder **will never run**.
- **Always path-filtered**, including the workflow file itself.
- **Pin OS versions explicitly** (`ubuntu-24.04`, `macos-14`, `windows-2022`) — do not use
  `-latest` aliases for the matrix.
- **Never** bake credentials into the workflow. Use repository secrets.

---

## 6. Testing Conventions

| Suite | Location | Runner |
| :--- | :--- | :--- |
| Bash | `<module>/tests/test_*.sh` | Plain Bash, exit-code assertions, temp-dir fixtures |
| PowerShell | `<module>/tests/test_*.ps1` | Pester-free plain `pwsh`, exit-code assertions |
| Python | `<module>/tests/test_*.py` | `pytest`, unit + integration |
| Go | `<module>/**/*_test.go` | `go test`, unit + `tests/` integration |

**Rules**

- Tests exercise the **public interface** (CLI flags, exit codes, emitted files), not internals.
- Every test must be **deterministic**: pin timestamps, isolate the filesystem under a temp dir,
  never depend on the host's real services, disk layout, or locale.
- Tests must not mutate state outside their sandbox, and must clean up after themselves.
- A test that cannot be run in CI does not belong in the suite.
- When a change touches an existing command or option, add a **regression test** proving the old
  behaviour still holds (§2.5).

---

## 7. Code Standards

Authoritative source: each module's `CODESTYLE.md`. The shared baseline:

### 7.1 Language and naming

- **English only** — code, comments, identifiers, docs, commit messages.
- **B2 English** — clear, simple, direct. Avoid ornate idioms; optimize for global readability.
- `snake_case` for variables and functions, `PascalCase` for types/classes, `UPPER_SNAKE_CASE` for
  constants, `kebab-case` for CLI flags, `PascalCase` for PowerShell parameters.
- Lines under **100 characters**. Python: **PEP 8**. PowerShell: **Approved Verb-Noun** naming.

### 7.2 Debugging and observability

- **No `print()` in production code.** Use the language's structured logging (`logging` in Python,
  `Write-Information`/`Write-Warning` in PowerShell, `log/slog` in Go, a `log()` helper in Bash).
- Log levels: `DEBUG` (troubleshooting), `INFO` (normal behaviour), `WARNING` (unexpected but
  survivable), `ERROR` (needs attention).
- Catch **specific** exceptions, never a bare `except Exception:`.
- Every destructive or long-running action writes an **audit line**.

### 7.3 Commenting

- Brief, precise, technical. Explain **why**, not what.
- No commented-out code in `main`. No `TODO` without a linked issue.
- Docstrings on every class and public function: inputs, outputs, raised errors.

### 7.4 Shell specifics

- `set -euo pipefail` at the top of every Bash script, plus `IFS=$'\n\t'`.
- Quote every expansion. Use `[[ ]]` for tests. Prefer `$(...)` over backticks.
- `--help` must exist and exit `0`.
- **Exit codes are a public contract:** `0` success, `1` configuration/safety violation,
  `2` partial failure. Document them in the README.

### 7.5 Security basics for contributors

- **Never hardcode secrets.** Read from the environment and fail loudly when unset.
- Validate and sanitise every external input — paths, arguments, JSON payloads, webhook bodies.
- **Guardrail destructive paths.** Refuse to operate on `/`, `C:\`, `/etc`, `/var`, system directories.
- Prefer **dry-run** modes and non-destructive defaults.
- Never log credentials, tokens or full secret-bearing payloads.

---

## 8. Navigation Map

| I want to… | Go to |
| :--- | :--- |
| Understand the architecture | [`wiki/01-Monorepo-Architecture.md`](wiki/01-Monorepo-Architecture.md) |
| Understand EventOps | [`wiki/02-EventOps-Overview.md`](wiki/02-EventOps-Overview.md) |
| Compare Python vs Go | [`wiki/03-EventOps-Python-vs-Go.md`](wiki/03-EventOps-Python-vs-Go.md) |
| See EventOps scenarios & labs | [`wiki/04-EventOps-Scenarios-and-Labs.md`](wiki/04-EventOps-Scenarios-and-Labs.md) |
| Understand Log Cleanup | [`wiki/05-Log-Cleanup-Overview.md`](wiki/05-Log-Cleanup-Overview.md) |
| Compare Bash vs PowerShell | [`wiki/06-Log-Cleanup-Bash-vs-PowerShell.md`](wiki/06-Log-Cleanup-Bash-vs-PowerShell.md) |
| See Log Cleanup scenarios & labs | [`wiki/07-Log-Cleanup-Scenarios-and-Labs.md`](wiki/07-Log-Cleanup-Scenarios-and-Labs.md) |
| Understand the CI/CD philosophy | [`wiki/08-CI-CD-Pipelines.md`](wiki/08-CI-CD-Pipelines.md) |
| Read the style standards | [`wiki/09-Code-Style-and-Standards.md`](wiki/09-Code-Style-and-Standards.md) |
| Know a module's status | [`MODULES.md`](MODULES.md) |
| Know what changed and when | [`CHANGELOG.md`](CHANGELOG.md) |
| Contribute code | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Report a vulnerability | [`SECURITY.md`](SECURITY.md) |
| Ask a question | [`SUPPORT.md`](SUPPORT.md) |

---

## 9. Known State and Gotchas

Verified on **2026-10-20**. These are real, current, and will bite you.

1. **Modules 1, 3, 4, 5, 6, 7, 8, 9, 10 are not in git.** They exist only on the working disk.
   `git log --all` shows zero history for them. They are also missing `SPECS.md`, `ROADMAP.md`,
   `CODESTYLE.md`, tests and CI — so they violate the module contract (§3).
2. **Module 5 has two failing tests**, both test-vs-implementation drift rather than product bugs:
   `Stage2-Python-Unified/tests/test_cli.py` (the CLI reads `snapshot.cpu_percent` while the test
   only stubs `to_dict()`, so a `Mock` reaches a numeric comparison) and
   `tests/test_monitor.py` (expects `get_process_data(top_n=10)`, implementation calls it
   positionally). **2 failed, 40 passed** as of the last run.
3. **Module 5's committed `.venv` is broken.** `.venv/bin/python` symlinks to a uv-managed
   CPython 3.12 that no longer exists on disk. Rebuild instead of reusing it:
   ```bash
   cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
   uv venv --python 3.13 .venv && uv pip install -e ".[dev]"
   ```
4. **Module 5's CI would never run.** Its three workflows sit in
   `Stage4-CI-CD-Pipeline/.github/workflows/`, a nested path GitHub does not execute. They must
   move to the repository root with `paths:` filters.
5. **Module 5's `.gitignore` ignores its own `AGENTS.md`.** Reconsider before committing that module.
6. **Path filters create a blind spot.** Changes under `wiki/`, `MODULES.md`, `AGENTS.md` and the
   other root docs match no workflow, so they trigger **no CI run**. That is intentional isolation,
   but it means documentation changes are never automatically validated.
7. **Go version drift.** CI pins Go `1.22`; newer toolchains work, but keep the pin current.
8. **No `.gitattributes`.** Line endings are not normalized, so Windows checkouts can turn Bash
   shebangs into CRLF and break the scripts. Adding one is a recommended next step:
   ```
   *.sh text eol=lf
   *.ps1 text eol=crlf
   *.py text eol=lf
   ```
9. **`main` is unprotected.** No branch protection, no rulesets, no required checks.
10. **The wiki lives in two places.** The content is committed to `main:wiki/` **and** published as
    the repository's GitHub Wiki (a separate `Scripts-DevOps-Practice.wiki.git` repository). They
    were verified byte-identical on 2026-10-20, but nothing enforces that. **When you edit a wiki
    page, push it to both** — otherwise the rendered GitHub Wiki and the versioned copy in `main`
    drift apart.
11. **Private vulnerability reporting is not enabled on the remote yet.** It requires one click in
    the GitHub UI (*Settings → Code security → Private vulnerability reporting*) and cannot be
    toggled through the REST API with a standard token. Until it is on, [`SECURITY.md`](SECURITY.md)
    directs reporters to the maintainer's email as the always-available channel.

---

## 10. Working Agreements

- **One question at a time.** Ask, then stop and wait. Never bundle menus of options unless there
  is a real fork with meaningful trade-offs.
- **Never agree without verifying.** Check the code, the docs, or the run output before confirming a
  claim.
- **Prose in artifacts is English.** Chat replies follow the user's language; repository artifacts
  stay English.
- **Preserve human control.** Push, PR creation, merges and releases are the user's decisions.
- **Report faithfully.** State failed, skipped and pending checks honestly. A hedge is not a stop.
- **Match the harness to the work.** Small understood change → inline. Large, tracked, or genuinely
  parallel → the ODD machinery.

---

*Last reviewed: 2026-10-20 · Methodology: ODD (Organic Driven Development) via gentle-ai*
