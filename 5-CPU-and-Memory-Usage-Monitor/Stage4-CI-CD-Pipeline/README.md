# Stage 4: CI/CD Pipeline

> The pipeline for this module lives at the **repository root**, not in this
> folder: `.github/workflows/ci-cpu-monitor.yml`.

---

## Why the pipeline moved

This folder used to hold three workflow files under
`Stage4-CI-CD-Pipeline/.github/workflows/`:

| Old file | Purpose |
| :--- | :--- |
| `ci-cd-pipeline.yml` | Main pipeline: native scripts, Python, Docker |
| `pr-validation.yml` | Pull-request checks |
| `release.yml` | Docker Hub push and release tags |

**GitHub never executed any of them.** A workflow only runs when it sits in
`.github/workflows/` at the root of the repository. A `.github` folder nested
inside a subdirectory is not a workflow directory, so the module looked
CI-covered on paper while nothing ever ran.

The repository's CI model settles the shape as well: *exactly one workflow
per module, at the repository root, path-filtered to that module's folder*.
So the three files were consolidated into one root workflow, and this folder
now documents the pipeline instead of carrying it.

---

## The workflow

`.github/workflows/ci-cpu-monitor.yml` — **CPU Monitor CI/CD**.

### Triggers

| Event | Branches | Paths |
| :--- | :--- | :--- |
| `push` | `main`, `feat/**`, `fix/**` | `5-CPU-and-Memory-Usage-Monitor/**` |
| `pull_request` | `main` | `5-CPU-and-Memory-Usage-Monitor/**` |

The workflow file itself is included in the path filter, so a change to the
pipeline also triggers a run.

### Jobs

| Job | Runner | Gate |
| :--- | :--- | :--- |
| `lint-bash` | `ubuntu-24.04` | `shellcheck -x` and `bash -n` on the native script |
| `test-bash` | `ubuntu-24.04`, `macos-14` | the Bash test suite |
| `lint-powershell` | `windows-2022` | PSScriptAnalyzer against the module settings file |
| `test-powershell` | `windows-2022`, `ubuntu-24.04` | the PowerShell test suite |
| `test-python` | 3 OS × Python 3.9/3.12/3.13 | `ruff check`, `ruff format --check` and `pytest` for Stage 2 **and** Stage 3 |
| `build-docker` | `ubuntu-24.04` | builds the container image and smoke tests it |

Python 3.9 is the floor declared in `pyproject.toml`, so it is always in the
matrix. The OS versions are pinned explicitly rather than tracked as
`-latest`, so a runner update cannot change the result of a run.

### Why Stage 3 is tested separately from Stage 2

`Stage2-Python-Unified` and `Stage3-Containerization` each carry their own
copy of the `system_monitor` package, and the Stage 3 Dockerfile installs
the package from **its own** `src/`. Testing only Stage 2 would leave the
tree the container actually ships completely unverified, so both are linted
and tested.

---

## Reproducing the gates locally

Every gate can be run before pushing.

```bash
# Stage 1 - native scripts
shellcheck -x 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts/system_monitor.sh
bash -n 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts/system_monitor.sh
bash 5-CPU-and-Memory-Usage-Monitor/tests/test_system_monitor.sh
pwsh -File 5-CPU-and-Memory-Usage-Monitor/tests/test_system_monitor.ps1

# Stage 1 - PowerShell analysis
pwsh -Command "Invoke-ScriptAnalyzer \
  -Path 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts/system_monitor.ps1 \
  -Settings 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts/PSScriptAnalyzerSettings.psd1"

# Stage 2 and Stage 3 - Python
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv venv .venv && uv pip install -e ".[dev]"
uv run ruff check src tests
uv run ruff format --check src tests
uv run pytest

# Stage 3 - container image
cd 5-CPU-and-Memory-Usage-Monitor/Stage3-Containerization
docker build -t system-monitor:local .
docker run --rm system-monitor:local --version
```

---

## What this pipeline deliberately does not do

The previous `release.yml` built and pushed a multi-architecture image to
Docker Hub on every push to `main`, using secrets the repository does not
have. That job was removed rather than relocated.

Publishing an image is a delivery decision, and this repository keeps those
with the maintainer: push, pull request and merge are manual decisions, and
the same applies to releases. The pipeline builds the image and proves it
works; it never publishes it.

---

## Related

- Module documentation: [`../README.md`](../README.md)
- Technical specification: [`../SPECS.md`](../SPECS.md)
- Repository CI model: [`../../../../AGENTS.md`](../../../../AGENTS.md) §5
