# Contributing

Thanks for working on **Scripts-DevOps-Practice**. This repository is a learning and portfolio
project: every module is meant to look like production engineering — real specs, real tests, real
CI, real documentation.

That standard is the point. A contribution that only "works" but skips the tests and docs makes
the module less useful than it was.

> **Read [`AGENTS.md`](AGENTS.md) first.** It is the router for this repository: the module contract,
> the CI model, the code standards baseline and the known gotchas, with pointers to every detailed
> document. This file is the contributor-facing summary; the full ODD protocol lives in
> [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md).

---

## The Short Version

1. **Open an issue first** for anything beyond a trivial fix — design before code.
2. **Branch** per [§ Branching](#branching).
3. **Write the failing test first**, then the fix, then refactor.
4. **Update the docs in the same commit** as the behaviour change.
5. **Make CI green** — all jobs, on all three operating systems.
6. **Open a pull request** and fill in the checklist.
7. **One logical change per commit.**

---

## Workflow: Organic Driven Development (ODD)

This repository runs **ODD**, the gentle-ai implementation of Organic Driven Development. It
replaced the older Spec-Driven Development flow on **2026-10-20**.

### What that means in practice

Seven phases, in order, on every request: **Authorize → Explore → Resolve uncertainty → Classify →
Track → Implement → Close.** Detail and repository-local rules live in [`odd/METHODOLOGY.md`](odd/METHODOLOGY.md).

| Phase | What happens |
| :--- | :--- |
| **Authorize** | Confirm the request actually authorizes a change. Investigations and reviews are read-only. |
| **Explore** | Read the existing code and requirements first, proportionately. |
| **Classify** | Decide small vs large by the **resume test** (could someone finish from the request plus `git diff`?). Never by file count. |
| **Track** | Large work gets a feature document at `odd/tasks/<feature-name>.md` plus an Engram mirror. Small work gets no durable artifacts. |
| **Implement** | Task by task, handed off by reference. Observe RED, reach GREEN, then refactor. |
| **Close** | Report the verified outcome, every failed/skipped/pending check, and a `Risk:` line. |

**The module artifacts survive the change.** ODD governs *how the work happens*; `SPECS.md`/`ROADMAP.md`
govern *what the module is*. You still ship them — they are the module's public contract with a human
reader. The spec now crystallizes from the actual request as the work lands, instead of being a
200-line document written before anyone has looked at the code.

### The `Risk:` line

Every code change closes with exactly one of:

```
Risk: none
Risk: item 3 (removed public API without a deprecation path)
```

The six high-risk items are listed in [`AGENTS.md` §2.6](AGENTS.md). Any of them raises the
verification tier and requires an independent verifier before the change is considered done.

---

## Branching

| Pattern | Use | Example |
| :--- | :--- | :--- |
| `feat/<n>-<slug>` | New module or feature | `feat/2-log-cleanup-spec-and-docs` |
| `fix/<slug>` | Defect fix | `fix/windows-ci-compat` |
| `docs/<slug>` | Documentation only | `docs/wiki-navigation` |
| `ci/<slug>` | Pipeline only | `ci/pin-os-versions` |

`<n>` = module number when targeting a single module; `kebab-case` slug. **Branch from `main`**, always:
`git checkout main && git pull --ff-only && git checkout -b feat/2-log-cleanup-add-size-filter`.

### Merge flow

`feature branch → local fast-forward merge into main → push`. `main` has **no branch protection
or rulesets**, so "CI green before merge" is a manual obligation — check it yourself:

```bash
gh run list --workflow ci-cleanup-logs.yml --branch main --limit 1
gh run list --workflow ci-eventops.yml --branch main --limit 1
```

---

## Commits

```
<type>(<scope>): <imperative summary, under 72 characters>

<optional body explaining WHY>
```

**Types:** `feat` · `fix` · `docs` · `ci` · `test` · `refactor` · `chore`

**Scopes:** the module name — `log-cleanup`, `eventops`, `eventops-go`, `rule-engine`, `ci`, `wiki`.

```bash
# good
fix(log-cleanup): resolve shellcheck SC2059 warnings
feat(eventops): add file watcher debouncing
# bad
Fixed stuff / update / feat: added new feature to eventops
```

**Rules**

- Imperative mood (*"add debouncing"*, not *"added"*). **One logical change per commit**, each
  buildable and CI-green on its own. The body explains **why**; the diff shows **what**.
- **Never** add a `Co-Authored-By` trailer or any AI attribution. Tests and docs ship **in the
  same commit** as the behaviour. Update [`CHANGELOG.md`](CHANGELOG.md) when user-visible.

---

## Testing

| Language | Command | Gate |
| :--- | :--- | :--- |
| Bash | `bash <module>/tests/test_<module>.sh` | ShellCheck + Bash on Ubuntu & macOS |
| PowerShell | `pwsh <module>/tests/test_<module>.ps1` | PSScriptAnalyzer + PowerShell on Windows & Ubuntu |
| Python | `pytest` inside the module | `ruff check` + `ruff format --check` + pytest |
| Go | `go test ./...` inside the module | `go vet ./...` + `go test ./...` |

### Rules

- **Write the failing test first.** Observe it fail for the right reason, then implement, then refactor
  with the test green.
- **One test per requested rule**, asserting *every* observable effect: output, exit code, persisted state.
- **For every existing command or option your change touches**, add a test proving the old behaviour
  still holds. Add no other cases.
- **Test the public interface** — CLI flags, exit codes, emitted files — not internal functions.
- **Be deterministic.** Pin timestamps, isolate the filesystem in a temp dir, never depend on the host's
  real services, disk layout or locale. Clean up after yourself.
- **A test that cannot run in CI does not belong in the suite.**

---

## Code Standards

This is the **full shared baseline**. Module-specific conventions live in each module's
`CODESTYLE.md`; the short must-know summary is in [`AGENTS.md` §7](AGENTS.md) and the wider style
guide in [`wiki/09`](wiki/09-Code-Style-and-Standards.md).

### Language and naming

- **English only**, **B2 English** (clear, simple, direct). Lines under **100 characters**. Python follows
  **PEP 8**; PowerShell uses **Approved Verb-Noun** naming.
- `snake_case` variables/functions, `PascalCase` types/classes, `UPPER_SNAKE_CASE` constants,
  `kebab-case` CLI flags, `PascalCase` PowerShell parameters.

### Debugging, comments and shell

- **No `print()` in production code** — use structured logging (`logging`/`Write-Information`/`slog`/`log()`).
  Levels: DEBUG/INFO/WARNING/ERROR. Catch **specific** exceptions, never bare `except`. Every destructive
  or long-running action writes an **audit line**.
- Comments explain **why**, not what. No commented-out code, no orphan `TODO`s. Docstrings on every class
  and public function (inputs, outputs, raised errors).
- Bash: `set -euo pipefail`, `IFS=$'\n\t'`, quote expansions, `[[ ]]`, `$(...)`. `--help` exits `0`.
- **Exit codes are a public contract:** `0` success, `1` configuration/safety violation, `2` partial
  failure — documented in the README.

### Security

- **Never hardcode secrets** — read from the environment, fail loudly when unset. Validate and sanitise
  every external input (paths, arguments, JSON payloads, webhook bodies).
- **Guardrail destructive paths** (`/`, `C:\`, `/etc`, `/var`, system dirs). Prefer dry-run and
  non-destructive defaults. Never log credentials, tokens or secret-bearing payloads.

---

## Module Contract

A module is not done until it ships:

```
<N>-<Module-Name>/
├── README.md · SPECS.md · ROADMAP.md · CODESTYLE.md
├── <implementation> · tests/ · docs/ (ARCHITECTURE_COMPARISON.md, SCENARIOS.md, labs/LAB1…LAB3.md)
```

Plus, at the **repository root**:

- `.github/workflows/ci-<module>.yml` — path-filtered to `'<module-folder>/**'`, multi-OS matrix.
- A row in [`MODULES.md`](MODULES.md) and the module table in [`README.md`](README.md).
- A wiki page and a `wiki/_Sidebar.md` entry.

**Labs are executable documentation.** Every command in a lab must actually run, and the stated
expected output must match reality.

---

## Pull Request Checklist

Copy this into your PR description:

```markdown
### What changed / Module
<!-- What does this PR do, why, and which module (e.g. 2 — Log Cleanup)? -->

### Verification
- [ ] Bash suite / PowerShell suite / Python pytest / Go test ./... / linters → ___

### Documentation
- [ ] README · SPECS.md/ROADMAP.md · CHANGELOG.md (if user-visible) updated
- [ ] Tests added; regression test for every existing command/option touched

### Risk
`Risk: <item N (reason)>` or `Risk: none`

### Notes for reviewers
<!-- Anything a reviewer should look at first. -->
```

**A pull request is not ready until every applicable box is honestly checked.** An unchecked box
that does not apply is fine — say why. A silently false box is not.

---

## Adding a New Module

1. Pick the next free number: folder `<n>-<Descriptive-Name>`.
2. Build against the module contract above, in the style of modules 2 and 11.
3. Add the path-filtered workflow at the **repository root** (never nested in the module).
4. Register in [`MODULES.md`](MODULES.md), `README.md`, `wiki/01-Monorepo-Architecture.md` and `wiki/_Sidebar.md`.
5. Write three labs a stranger can follow end to end.

---

## Reporting Bugs and Asking Questions

- **Bug** → [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). **Feature** → [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).
- **Security** → **do not** open a public issue; see [`SECURITY.md`](SECURITY.md). **Question** → [`SUPPORT.md`](SUPPORT.md).

A good bug report includes the module, OS, exact command, observed vs expected output, and exit code.

---

## Code of Conduct / License

Participation is governed by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Contributions are accepted
under the [MIT License](LICENSE).
