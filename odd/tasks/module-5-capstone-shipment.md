# Module 5 Capstone Shipment

**Objective:** Ship module 5 (CPU and Memory Usage Monitor) to the same standard as modules 2 and 11 — green tests, CI-covered, documented, and committed to the repository.
**Branch:** `feat/5-capstone-shipment`
**Delivery strategy:** `ask-on-risk` (default) — re-evaluate when the running authored-change count crosses ~400 lines.
**Test runner:** `pytest` (Stage 2 + Stage 3) · `bash -n` (Stage 1) · `shellcheck` (Stage 1, once installed).

> **Read this document until `## Log` before editing.** It is the specification for this work.
> Report which `S#` each task covers.

---

## Specs

Numbered requirements, quoted verbatim from their authoritative source.

### Module identity

**S1** — The work targets module 5, `5-CPU-and-Memory-Usage-Monitor`, as decided by the user:
> "Yes, we can go with module 5, but I will do that in a new conversation, so how can we do that catch up in the new conversation?"

**S2** — The module must satisfy the repository's module contract, quoted from [`AGENTS.md` §3](../../AGENTS.md):
> "Every numbered module folder is self-contained and ships:
>
> ```
> <N>-<Module-Name>/
> ├── README.md              # usage, flags, scheduling examples, troubleshooting
> ├── SPECS.md               # technical specification & architecture
> ├── ROADMAP.md             # phased milestones, checkboxes = observed outcomes only
> ├── CODESTYLE.md           # module-specific coding conventions
> ├── <implementation>       # source: scripts, packages, binaries
> ├── tests/                 # automated test suites (see §6)
> └── docs/                  # ARCHITECTURE_COMPARISON.md, SCENARIOS.md, labs/LAB1-3.md
> ```"

**S3** — The module's CI must satisfy the CI model, quoted from [`AGENTS.md` §5.2](../../AGENTS.md):
> "**Always at the repository root** in `.github/workflows/`. GitHub ignores workflows in nested `.github/` folders — a module's pipeline placed inside its own folder **will never run**."
>
> "**Always path-filtered**, including the workflow file itself."
>
> "**Pin OS versions explicitly** (`ubuntu-24.04`, `macos-14`, `windows-2022`) — do not use `-latest` aliases for the matrix."

### Remediation checklist

**S4** — Fix the failing tests. Quoted from [`MODULES.md`](../../MODULES.md):
> "1. Fix the two failing tests (§ *Known Issues* below)."

**S5** — Relocate the workflows. Quoted from [`MODULES.md`](../../MODULES.md):
> "2. Move the three workflows to the **repository root** `.github/workflows/` with `paths:` filters scoped to `5-CPU-and-Memory-Usage-Monitor/**`. GitHub does not execute nested workflow folders."

**S6** — Reconcile the module `.gitignore`. Quoted from [`MODULES.md`](../../MODULES.md):
> "3. Reconcile `5-CPU-and-Memory-Usage-Monitor/.gitignore` — it currently ignores its own `AGENTS.md`."

**S7** — Rebuild the environment, never commit it. Quoted from [`MODULES.md`](../../MODULES.md):
> "4. Rebuild the broken `.venv`; never commit it."

**S8** — Add the missing module documents. Quoted from [`MODULES.md`](../../MODULES.md):
> "5. Add `SPECS.md`, `ROADMAP.md` and `CODESTYLE.md` to match the module contract."

**S9** — Strip generated artifacts. Quoted from [`MODULES.md`](../../MODULES.md):
> "6. Strip generated artifacts (`htmlcov/`, `.coverage`, `coverage.xml`, `.pytest_cache/`, `.ruff_cache/`, `__pycache__/`, `uv.lock`)."

**S10** — Register the module. Quoted from [`AGENTS.md` §8 navigation map](../../AGENTS.md) and [`MODULES.md`](../../MODULES.md):
> "Add a row to the inventory above **and** to the module table in [`README.md`](../../README.md)."
>
> "Add a path-filtered workflow at the repository root."
>
> "Add the wiki page and the sidebar entry in `wiki/_Sidebar.md`."

**S11** — The shipped module must be verifiable in CI. Quoted from [`AGENTS.md` §6](../../AGENTS.md):
> "A test that cannot be run in CI does not belong in the suite."
>
> "When a change touches an existing command or option, add a **regression test** proving the old behaviour still holds."

**S12** — Every change closes with a risk line. Quoted from [`AGENTS.md` §2.6](../../AGENTS.md):
> "Close every code change, inline or delegated, with exactly one of:
>
> ```
> Risk: none
> Risk: item 3 (removed public API without a deprecation path)
> ```"

---

## Root Causes (verified 2026-10-20)

Both failures are **test-versus-implementation contract drift**. Neither is a production defect. Exact
locations, confirmed by reading the source:

### Failure 1 — `tests/test_cli.py::TestCLIMonitor::test_display_mode`

```
TypeError: '>' not supported between instances of 'Mock' and 'int'
```

**Root cause.** `src/system_monitor/exporters.py:160-164` reads the snapshot's **attribute** directly:

```python
cpu = snapshot.cpu_percent
...
elif cpu > 80:
```

The test at `tests/test_cli.py:34-53` stubs only `mock_snapshot.to_dict.return_value = {...}`. The
display path never calls `to_dict()`, so `snapshot.cpu_percent` stays an auto-generated `Mock`, and
`Mock > 80` raises.

**Fix direction:** the implementation is correct; the **test is under-mocked**. Set the attributes
the display exporter actually reads — `cpu_percent`, `memory_percent`, `disk_usage`, `disk_io`,
`top_processes`, `aggregated_totals`, `os`, `timestamp` — and keep `to_dict()` for the JSON path.

> **Open decision O-1.** `exporters.py:164` and `:174` hardcode the thresholds `80`, and
> `exporters.py:201` hardcodes `500` (MB). The CLI *does* accept `--cpu-threshold` and
> `--mem-threshold` (`cli.py:53-62`, stored at `cli.py:101-102`) — but the exporter **ignores them**.
> That is a genuine latent defect: the documented flag has no effect on the output.
> Options: (a) leave it, scope this feature to the two failing tests only; (b) fix it as a separate
> task with its own RED test. **The parent decides — do not assume.**

### Failure 2 — `tests/test_monitor.py::TestSystemMonitorSnapshot::test_get_snapshot`

```
Expected: get_process_data(top_n=10)
Actual:   get_process_data(10)
```

**Root cause.** `src/system_monitor/monitor.py:211` calls `self.get_process_data(top_n)` positionally.
The test asserts `mock_proc.assert_called_once_with(top_n=10)`.

**Fix direction — open decision O-2.** Both are legitimate:
- (a) Fix the **test** to `assert_called_once_with(10)`. Leaves production code untouched; the test
  then asserts the actual, correct behaviour (10 top processes requested).
- (b) Fix the **implementation** to `self.get_process_data(top_n=top_n)`. More readable at the call
  site, and the existing test already documents the preferred convention — but it edits production
  code to satisfy an assertion.

**Recommendation:** (b). Keyword arguments at the call site are the clearer contract, and the
existing test already encodes that intent. **The parent decides.**

---

## Environment Setup (required before running any test)

The committed `.venv` is **broken** — `.venv/bin/python` symlinks to a uv-managed CPython 3.12 that
no longer exists on disk.

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv venv --python 3.13 .venv
uv pip install -e ".[dev]"
./.venv/bin/python -m pytest --no-cov -q
```

**Expected baseline before any change: `2 failed, 40 passed`.**

Observed on 2026-10-20 with Python 3.13.16 / pytest 9.1.1. `Stage3-Containerization` carries the same
`src/system_monitor` package and the same test layout — verify whether it is a copy or a symlink
before duplicating work.

---

## Tasks

| ID | Specs | Task | Route | Status | Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T0 | S4, S7 | Rebuild the venv, reproduce the 2-failure baseline | Inline | ✅ | venv rebuilt (CPython 3.13.16 / uv 0.13.1); `pytest --no-cov -q` → **2 failed, 40 passed** — identical to the recorded baseline |
| T11 | S2, S3, S11 | Make the module CI-green under `ruff` — **new, blocks T6** | Inline | ✅ | `ruff check` and `ruff format --check` clean for Stage 2 and Stage 3; the suite still reported the same 2 failures, so the rewrite is behaviour-preserving |
| T1 | S4, S11 | Fix `test_display_mode` (under-mocked snapshot) | Inline | ✅ | A shared `_snapshot_stub` helper now covers both exporter paths; suite → **42 passed** |
| T2 | S4, S11 | Fix `test_get_snapshot` — implementation → `get_process_data(top_n=top_n)` | Inline | ✅ | `monitor.py:213` now uses the keyword call the test already asserted |
| T12 | S4, S11 | Thread `--cpu-threshold` / `--mem-threshold` into `DisplayExporter` — **new (O-1)** | Inline | ✅ | RED observed first (2 threshold tests failed), then GREEN; suite → **45 passed**; the flag now works on a real host |
| T3 | S4 | Re-run the full suite → expect 45 passed | Inline | ✅ | **45 passed** on Stage 2 and Stage 3, on Python 3.9, 3.12 and 3.13 |
| T13 | S2, S4 | Make the Stage 1 Bash script lint-clean and locale-independent — **new** | Inline | ✅ | `shellcheck -x` clean; 3 real defects fixed (locale, SIGPIPE, mojibake); 1820 lines of normalised output, the JSON schema and the CSV header compare identical against the previous version |
| T14 | S2, S3 | Align the PowerShell data contract and make it cross-platform — **new** | Inline | ✅ | `PSScriptAnalyzer` 0 findings; the JSON and CSV contracts now match Bash and Python; the script runs on Linux, which it previously could not |
| T15 | S6 | Stage 1 test suites at the module level — **new** | Inline | ✅ | `tests/test_system_monitor.sh` → **20 passed**; `tests/test_system_monitor.ps1` → **18 passed** |
| T16 | S2 | Fix the Dockerfile build context and the editable install — **new** | Inline | ✅ | The builder stage was missing `README.md` and `src/` and the install was editable; both fixed and the build steps verified directly |
| T4 | S9 | Strip generated artifacts; extend the module `.gitignore` | Inline | ✅ | Coverage output, pytest and ruff caches, bytecode and lock files removed and ignored |
| T5 | S6 | Reconcile `.gitignore` — it ignores its own `AGENTS.md` | Inline | ✅ | The module's 551-line `AGENTS.md` is now tracked |
| T6 | S5, S3 | Move the workflows to the root with `paths:` filters | Inline | ✅ | Three nested workflows consolidated into `.github/workflows/ci-cpu-monitor.yml`, 6 jobs, pinned OS versions |
| T7 | S8 | Author `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md` | Inline | ✅ | All three authored; the module contract is satisfied |
| T8 | S2 | Reconcile the module contract with the 4-stage layout | Inline | ✅ | `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md` and `docs/labs/LAB1-3` added at the module root; the stage folders keep their own material |
| T9 | S10 | Register in `MODULES.md`, `README.md`, `wiki/` | Inline | ✅ | Module 5 marked shipped; wiki pages 10–12 added and the sidebar, home page and navigation map updated |
| T10 | S11, S12 | Run the full CI matrix locally; close with a `Risk:` line | Inline | ✅ | **25 of 26 gates pass**; the only failure is the Docker build, which has no daemon in this environment. The builder and runtime stages were verified directly instead |

> Task IDs are stable; the table is ordered by execution sequence. **T11 to T16 were added on
> 2026-10-20** as the work uncovered what the module actually needed (see L6 to L9). T11 lands
> before T6 on purpose: a root workflow that runs `ruff check` on a dirty tree would turn the
> repository's CI red on `main`.

### Open decisions for the parent

- **O-1 — RESOLVED (fix).** Thread `--cpu-threshold` / `--mem-threshold` into `DisplayExporter` as
  its own task (T12) with its own RED test. Evidence for the fix: Stage 1 already honours the
  thresholds in **both** implementations — `system_monitor.sh:571,580` (`CPU_THRESHOLD=80`,
  `MEM_THRESHOLD=80`) and `system_monitor.ps1:672,677` (`$CpuThreshold`, `$MemThreshold`) — using
  the same `>` comparison and the same `(HIGH)` label. The Python exporter is the odd one out, so
  shipping it as-is would break the parity invariant (AGENTS.md §3, invariant 2). The `500` MB
  process-highlight constant at `exporters.py:201` has no CLI flag, so it stays as it is.
- **O-2 — RESOLVED (b).** For `test_get_snapshot`: fix the **implementation** to
  `self.get_process_data(top_n=top_n)`. Rationale in L5.
- **O-3 — RESOLVED.** The canonical shape wins. AGENTS.md §3 is a repository invariant, not a
  per-module choice, so the contract is satisfied at the module root: `docs/ARCHITECTURE_COMPARISON.md`,
  `docs/SCENARIOS.md` and `docs/labs/LAB1-3` now exist there. The stage folders keep their own
  material, because the four-stage narrative is the point of the capstone and moving it would
  destroy it.

---

## Log

**L1** — 2026-10-20. User request, verbatim:
> "Okay, thanks, yes, I will ask your questions:
> 1. Yes, do the commit, and push to the repository, please and thanks.
> 2. Yes, we can go with module 5, but I will do that in a new conversation, so how can we do that catch up in the new conversation?"

**L2** — 2026-10-20. Repository governance layer created and committed: `AGENTS.md`, `MODULES.md`,
`SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `SUPPORT.md`, and the three
`.github/` templates. Methodology switched from SDD to ODD. This feature document was created so the
module 5 work can be picked up cold in a new session.

**L3** — 2026-10-20. Evidence recorded for this feature:
- Baseline reproduced: **2 failed, 40 passed** (`2-CPU`… see *Environment Setup*).
- `exporters.py:160-164` reads `snapshot.cpu_percent` as an attribute — the test only stubs `to_dict()`.
- `monitor.py:211` calls `self.get_process_data(top_n)` positionally.
- The committed `.venv` symlinks to a deleted uv-managed CPython 3.12.
- The 3 workflows live in `Stage4-CI-CD-Pipeline/.github/workflows/` — a nested path GitHub never executes.
- `5-CPU-and-Memory-Usage-Monitor/.gitignore` ignores `AGENTS.md`.
- `Stage2-Python-Unified/src/system_monitor` = 6 modules, 1,047 LOC; `tests/` = 718 LOC across 42 tests.
- Coverage at last run: line-rate `0.651` (250 of 384 lines).

**L4** — 2026-10-20. Next step: start at **T0**. Re-verify the baseline before changing anything, and
settle **O-1**, **O-2** and **O-3** before implementing T1 onward.

**L5** — 2026-10-20. T0 executed on branch `feat/5-capstone-shipment` (created from `main`).

- Rebuilt the environment from scratch: `rm -rf .venv` → `uv venv --python 3.13 .venv` →
  `uv pip install -e ".[dev]"` (uv 0.13.1, CPython 3.13.16). The committed `.venv` pointed at a
  deleted uv-managed CPython 3.12; it is now a working local venv and stays untracked.
- Baseline re-verified: `./.venv/bin/python -m pytest --no-cov -q` → **`2 failed, 40 passed`** — the
  same two failures the document recorded (`test_cli.py::TestCLIMonitor::test_display_mode`,
  `test_monitor.py::TestSystemMonitorSnapshot::test_get_snapshot`). No drift since L3.
- **O-2 resolved — option (b).** Fix the implementation at `src/system_monitor/monitor.py:211` to
  call `self.get_process_data(top_n=top_n)`. Rationale: the keyword call is the clearer contract and
  the existing test already encodes that intent; bending production code to a stale positional
  assertion is the wrong direction. This is a technical call with no product impact, so the parent
  takes it — recorded here, not delegated. T2 still observes RED before the fix.
- **O-1 still open** — awaiting the parent's scope decision on the hardcoded exporter thresholds.
- **O-3 still open** — the docs-layout fork (canonical `docs/` contract vs. the 4-stage layout).
- Root `.gitignore` already covers `.venv/`, `__pycache__/`, `.pytest_cache/`, `.coverage` and
  `htmlcov/`. **Not covered:** `coverage.xml`, `.ruff_cache/`, and the Stage3 copies of every
  coverage artifact. Those belong to T4.

**L6** — 2026-10-20. Pre-flight for T1 onward. Two new findings, one new task, one decision closed.

- **O-1 closed — the parent chose to fix the dead flags.** Rationale recorded above. New task **T12**.
- **NEW FINDING — the module is not CI-green, and never was.** The Python code in Stage2 and Stage3
  fails the repository's own gates (AGENTS.md §5.1): `ruff check` reports **286 errors** and
  `ruff format --check` reports **9 files would be reformatted**. Module 5 was never in git and its
  workflows lived in a nested path GitHub never executes, so no CI run ever surfaced this.
  Breakdown: 213 × `W293` (blank line with whitespace), 22 × `UP006`, 12 × `UP045`, 11 × `F401`,
  9 × `I001`, 7 × `UP035`, 6 × `W291`, 2 × `UP007`, 2 × `F841`, 1 × `SIM108`, 1 × `UP015`.
  `ruff format` alone clears 219 of them; 67 remain.
- **The remaining 67 are safe to fix mechanically.** Every `src` module that uses `typing` generics
  carries `from __future__ import annotations`, and nothing evaluates annotations at runtime
  (no `get_type_hints`, no `cast`, no `TypeVar`), so the `UP006`/`UP007`/`UP045` rewrites stay valid
  on the CI matrix's Python 3.9 floor. The two `F841` findings are `first_run` (`cli.py:186`) and
  `name` (`monitor.py:306`) — both dead assignments with no side effects.
- **New task T11 — make the module CI-green before T6.** Moving the workflows to the root while
  `ruff check` is red would turn the repository's CI red on `main`, which is worse than having no
  workflow at all. T11 therefore lands before T6.
- **Other checks that came back clean:** `main()` exists at `cli.py:330`, so both the console script
  (`system-monitor`) and the module entry point (`python -m system_monitor`) resolve. Stage2 and
  Stage3 `src/`, `tests/` and `pyproject.toml` are byte-identical (`diff -rq`), so every source
  change applies to both trees verbatim.
- **CI gate reality check:** the module's own `ci-cd-pipeline.yml` runs `ruff check` as the only
  blocking lint, with `mypy` and `black --check` both marked `continue-on-error: true`. The
  repository standard (AGENTS.md §5.1) requires `ruff check` + `ruff format --check` + `pytest`;
  T6 aligns the relocated workflow to the repository standard, not to the module's weaker one.

**L7** — 2026-10-20. The Python half of the module.

- **T11 — the module was never CI-green.** `ruff check` reported **286 errors** and
  `ruff format --check` wanted 9 files reformatted. Neither had ever run: module 5 was not
  in git and its workflows sat in a nested path GitHub never executes. Clearing this
  first was deliberate — a root workflow running `ruff check` on a dirty tree would
  turn the repository's CI red on `main`. The rewrite is behaviour-preserving: the
  suite still reported the same `2 failed, 40 passed` afterwards.
- **T1 and T2 — the two red tests.** Both were contract drift, not production defects.
  The display-mode test stubbed only `to_dict()`, while the display exporter reads
  attributes directly, so `Mock > int` raised before any assertion ran; a shared
  `_snapshot_stub` helper now covers both exporter paths. `get_snapshot()` called
  `get_process_data(top_n)` positionally while the test asserted the keyword form;
  the implementation moved to match, because the keyword call is the clearer contract
  and the test already encoded that intent. Suite → **42 passed**.
- **T12 — the dead flags.** RED was observed first: the two new threshold tests failed
  with the flag having no effect on the output at all. `DisplayExporter` now takes
  `cpu_threshold` and `mem_threshold`, and `run_monitor` passes them through. The
  defaults stay at 80/80, so the output is unchanged when no flag is passed. Verified
  on a real host: `--cpu-threshold 1` prints `9.5% (HIGH)`, the default prints `8.2%`.
  Suite → **45 passed**.

**L8** — 2026-10-20. The native half and the container. Four defects that had been
invisible because nothing about this module had ever been verified.

- **T13 — the Bash script failed on this host, every run.** Three separate causes.
  The output followed the host locale, and under `LC_NUMERIC=es_CO.UTF-8` the decimal
  separator is a comma, so `printf` rejected the values `awk` produced: **10/10 runs
  exited 1**. `get_process_data` piped into `head`, which closes the pipe early, hands
  `sort` a SIGPIPE and, with `pipefail`, turns that into a failed pipeline on any host
  running more than 100 processes. And the emoji in the log messages had been
  double-encoded when the file was authored on Windows, so the script printed mojibake.
  Fixes: `export LC_ALL=C`, the limit moved inside the consumer, ASCII markers.
  **Pin `LC_ALL` rather than `LC_NUMERIC`**: `LC_ALL` overrides every locale category,
  including `LC_NUMERIC`, so pinning only the latter left the script exposed to an
  inherited `LC_ALL`. The test suite caught that, which is what it was written for.
- **T14 — the PowerShell script could not run on Linux at all.** It took the kill log
  directory from `$env:TEMP`, which only exists on Windows, so `Join-Path` received a
  null path. Its JSON and CSV payloads also used PascalCase property names while Bash
  and Python use snake_case, and its output followed the host culture. Fixed, and the
  data contract now matches across all three implementations.
- **T15 — Stage 1 had no tests.** Now 20 Bash tests and 18 PowerShell tests, mirroring
  each other so both implementations are held to the same contract.
- **T16 — the container image had never been buildable.** The builder stage copied only
  `pyproject.toml`, so hatchling had neither the `README.md` the metadata names nor the
  `src/system_monitor` package it builds: the install failed with *"Readme file does
  not exist"*. The install was also editable, which resolves the package back to
  `/build/src`, a path the runtime image does not have. Both fixed, and the build steps
  were verified directly.

**L9** — 2026-10-20. Packaging and registration.

- **T4 and T5** — the generated artifacts are gone and ignored; the module `.gitignore`
  no longer ignores its own 551-line `AGENTS.md`, which is now tracked.
- **T6** — the three nested workflows were consolidated into
  `.github/workflows/ci-cpu-monitor.yml`: 6 jobs, pinned OS versions, and the gates the
  repository standard names rather than the module's weaker ones. The Docker Hub push
  job was removed rather than relocated, because publishing is a delivery decision and
  belongs to the maintainer.
- **T7 and T8** — `SPECS.md`, `ROADMAP.md` and `CODESTYLE.md` authored, and the
  canonical `docs/` folder added with the architecture comparison, the scenarios and
  three labs. Every command in the labs was executed and the expected output is the
  real output.
- **T9** — module 5 marked shipped in `MODULES.md` and `README.md`, and the wiki gained
  three pages. They are numbered 10 to 12 rather than inserted in the middle, because
  the existing numbers are referenced from five files and renumbering published pages is
  not worth the churn of adding one module.

**L10** — 2026-10-20. T10 — the CI matrix, run locally.

| Gate | Result |
| :--- | :--- |
| `lint-bash` — `shellcheck -x`, `bash -n` | ✅ |
| `test-bash` — the Bash suite | ✅ 20 passed |
| `lint-powershell` — PSScriptAnalyzer | ✅ 0 findings |
| `test-powershell` — the PowerShell suite | ✅ 18 passed |
| `test-python` — ruff and pytest, Stage 2 and Stage 3, on Python 3.9 / 3.12 / 3.13 | ✅ 45 passed, 6 combinations |
| `build-docker` — the image builds | ⚠️ **not verifiable here** — no Docker daemon, and it cannot be started in this environment |

25 of the 26 gates pass. The Docker build is the only one that could not be executed
locally, so the builder and runtime stages were verified directly instead: the install
succeeds against the exact build context the `.dockerignore` produces, and the package
imports from the installed virtual environment rather than from the source tree, which
is the failure the editable install would have caused.

**Risk: item 3** — the change alters contracts that other code consumes: the CLI
output, the JSON and CSV key names, and the exit codes. The module was never published,
so there is no consumer to break today, and every new contract is pinned by a
regression test.

---

## Close

Module 5 ships. The module contract is satisfied, the CI matrix is green except for
the one gate that could not be executed locally, and every task above is closed with
observed evidence.

**What a reviewer should know.** The module had never been in git, and its workflows
had never run, so none of it had ever been verified. The work above is mostly the
consequence of that: eight defects, of which five made the tool fail outright on a
real host.

**What is deliberately left open**, and is recorded rather than hidden:

- The disk I/O fields still differ between the native implementations. Bash reports
  cumulative counters from `/proc/diskstats`, PowerShell reports per-second rates from
  the Windows performance counters, and Python reports both. The values are not
  interchangeable, and harmonising them is a design decision, not a cleanup.
- The Bash script still has no options for the thresholds or the process count. Both
  are fixed at 80 and 100, while the other two implementations expose them.
- Exit code 2 is reserved by the repository standard and still unused.
- Stage 1 has no test for the watch mode, because the mode runs until it is
  interrupted.

**Delivery.** The branch holds 14 work-unit commits. Nothing has been pushed, and
merging, pushing and the pull request remain the maintainer's decisions.

