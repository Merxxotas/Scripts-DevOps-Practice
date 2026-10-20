# ROADMAP — CPU and Memory Usage Monitor

> Phased milestones. A checkbox is ticked only when the outcome has been
> observed, never because the work was planned.

---

## Phase 1 — Native scripts

The Bash and PowerShell implementations of the monitor, with the same
flags, the same defaults and the same exit codes.

- [x] Bash script with CPU, memory, disk and process monitoring
- [x] PowerShell script with the same feature set
- [x] JSON and CSV output
- [x] Watch mode
- [x] Export to a file or a directory with a generated name
- [x] Strict mode in the Bash script (`set -euo pipefail`, restricted `IFS`)
- [x] Structured logging with timestamps
- [x] Input validation for the numeric parameters
- [x] Kill and restart by PID or by name, with an audit log
- [x] `shellcheck -x` reports no findings
- [x] PSScriptAnalyzer reports no findings against the module settings file
- [x] The output does not depend on the host locale

## Phase 2 — Unified Python package

One Click-based CLI that replaces the two scripts, with type hints and a
test suite.

- [x] Click CLI with six modules
- [x] Type hints throughout
- [x] `pyproject.toml` with the uv workflow
- [x] pytest suite, 45 tests
- [x] `ruff check` and `ruff format --check` report no findings
- [x] The suite passes on Python 3.9, the declared floor
- [x] The `--cpu-threshold` and `--mem-threshold` options reach the output

## Phase 3 — Containerization

The Stage 2 package shipped as a hardened container image.

- [x] Multi-stage Dockerfile with a builder and a minimal runtime stage
- [x] Non-root execution as UID 1000
- [x] Read-only root filesystem in the production compose profile
- [x] `docker-compose.yml` with the dev, prod, monitor and watch profiles
- [x] Health check
- [x] `.dockerignore` that keeps the build context minimal
- [x] The image builds and the package imports from the installed venv

## Phase 4 — CI/CD pipeline

One workflow at the repository root, path-filtered to this module.

- [x] The pipeline lives at `.github/workflows/ci-cpu-monitor.yml`
- [x] Bash linting and tests on Linux and macOS
- [x] PowerShell analysis and tests on Windows and Linux
- [x] Python linting and tests across three operating systems and three
      Python versions, for Stage 2 and Stage 3
- [x] Container build and smoke test
- [x] The operating system versions are pinned

## Phase 5 — Documentation

The module contract documents.

- [x] `README.md` with usage, flags, scheduling and troubleshooting
- [x] `SPECS.md` with the architecture and the data contract
- [x] `CODESTYLE.md` with the module conventions
- [x] `docs/ARCHITECTURE_COMPARISON.md`
- [x] `docs/SCENARIOS.md`
- [x] `docs/labs/LAB1` to `LAB3`

## Not yet done

These are known gaps, recorded so they are not lost.

- [ ] **The disk I/O fields differ between the native implementations.**
      The Bash script reports cumulative counters, the PowerShell script
      reports per-second rates, and the Python package reports both. The
      values are not interchangeable.
- [ ] **The Bash script has no options for the thresholds or the process
      count.** Both are fixed at 80 and 100, while the other two
      implementations expose them.
- [ ] **The exit code 2 is reserved but unused.** The repository standard
      defines it for partial failure.
- [ ] **Stage 1 has no test for the watch mode**, because the mode runs
      until it is interrupted.
