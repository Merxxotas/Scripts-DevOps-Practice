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
| T0 | S4, S7 | Rebuild the venv, reproduce the 2-failure baseline | Inline | ⬜ | |
| T1 | S4, S11 | Fix `test_display_mode` (under-mocked snapshot) | Inline | ⬜ | |
| T2 | S4, S11 | Fix `test_get_snapshot` — **needs O-2 decision** | Inline | ⬜ | |
| T3 | S4 | Re-run the full suite → expect 42 passed | Inline | ⬜ | |
| T4 | S9 | Strip generated artifacts; extend the module `.gitignore` | Inline | ⬜ | |
| T5 | S6 | Reconcile `.gitignore` — it ignores its own `AGENTS.md` | Inline | ⬜ | |
| T6 | S5, S3 | Move the 3 workflows to root with `paths:` filters | Inline | ⬜ | |
| T7 | S8 | Author `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md` | Inline | ⬜ | |
| T8 | S2 | Reconcile the module contract with the 4-stage layout — **needs O-3 decision** | Inline | ⬜ | |
| T9 | S10 | Register in `MODULES.md`, `README.md`, `wiki/` | Inline | ⬜ | |
| T10 | S11, S12 | Run the full CI matrix locally; close with a `Risk:` line | Inline | ⬜ | |

### Open decisions for the parent

- **O-1** — Fix the hardcoded thresholds in `exporters.py` (`80`, `80`, `500`) so the CLI's
  `--cpu-threshold` / `--mem-threshold` flags actually apply? Or scope this feature to the two
  failing tests only?
- **O-2** — For `test_get_snapshot`: fix the test (a) or the implementation (b)?
- **O-3** — Module 5's docs live *inside* its Stage folders (`Stage1-Native-Scripts/docs/README-*.md`),
  not in a top-level `docs/`. Adapt the module contract to the 4-stage layout, or restructure toward
  the canonical `docs/ARCHITECTURE_COMPARISON.md` + `docs/SCENARIOS.md` + `docs/labs/` shape?

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
