# LAB 3 — The Unified Python Package and the Container

> **Goal:** install the Python package, verify its tests, and build the
> container image that ships it.
>
> **Time:** 20 minutes · **Prerequisites:** Python 3.9 or newer, `uv`,
> and Docker for the last step.

---

## Step 1 — Install it

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv venv .venv
uv pip install -e ".[dev]"
```

Expected:

```
Using CPython 3.13.16
Creating virtual environment at: .venv
...
 + system-monitor==2.0.0 (from file:///.../Stage2-Python-Unified)
```

The virtual environment is never committed. It is listed in the module's
`.gitignore` and in the repository's.

---

## Step 2 — Run it

```bash
uv run -m system_monitor
```

Expected:

```
=== System Resource Monitor ===
2026-10-20 14:13:32
OS: Linux

CPU Usage: 13.6%
Memory Usage: 38.6%

Disk Usage:
```

The layout matches the native scripts. The values are the same shape, and
the JSON contract is identical:

```bash
uv run -m system_monitor --format json | python3 -c "
import json, sys
print(', '.join(sorted(json.load(sys.stdin).keys())))
"
```

Expected:

```
aggregated_totals, cpu_percent, disk_io, disk_usage, memory_percent, os, timestamp, top_processes
```

---

## Step 3 — Use the thresholds

```bash
uv run -m system_monitor --cpu-threshold 5 --mem-threshold 5
```

Expected:

```
CPU Usage: 13.6% (HIGH)
Memory Usage: 38.6% (HIGH)
```

This is the flag the native Bash script does not have, and the one that
used to do nothing at all in the Python package: the exporter hardcoded 80
and ignored the value the CLI had parsed. There is a regression test for
it in `tests/test_cli.py`:

```bash
uv run pytest tests/test_cli.py -v -k threshold
```

---

## Step 4 — Run the tests

```bash
uv run pytest
```

Expected:

```
============================== 45 passed in 0.09s ==============================
```

The suite is deterministic. It pins the timestamps, isolates the filesystem
and never depends on the host's processes.

---

## Step 5 — Run the gates

```bash
uv run ruff check src tests
uv run ruff format --check src tests
```

Expected:

```
All checks passed!
11 files already formatted
```

Both gates run in CI, on three operating systems and three Python
versions. Python 3.9 is always in the matrix because it is the floor
declared in `pyproject.toml`.

---

## Step 6 — Build the container image

```bash
cd ../Stage3-Containerization
docker build -t system-monitor:lab .
```

Expected:

```
#11 [builder 5/6] RUN uv venv /opt/venv && uv pip install --python /opt/venv/bin/python .
...
#16 exporting to image
Successfully built ...
```

Two details in that Dockerfile are worth knowing, because both were broken
once:

* The builder stage copies `pyproject.toml`, `README.md` **and** `src/`.
  The package metadata names `README.md` as the readme and hatchling builds
  the wheel from `src/system_monitor`, so the install fails without all
  three.
* The install is not editable. An editable install resolves the package
  back to the builder stage, which the runtime image does not have, so the
  copied virtual environment would import nothing.

---

## Step 7 — Run the container

```bash
docker run --rm system-monitor:lab --version
docker run --rm system-monitor:lab --format json | python3 -c "
import json, sys
json.load(sys.stdin)
print('valid JSON')
"
```

Expected:

```
system-monitor, version 2.0.0
valid JSON
```

The image runs as the non-root user `monitor` with UID 1000.

---

## Step 8 — The compose profiles

```bash
docker compose --profile prod up -d
docker compose ps
```

The production profile adds a read-only root filesystem, a 128 MB memory
limit, `cap_drop: ALL` with only `SYS_PTRACE` added back, and
`no-new-privileges`.

Tear it down with:

```bash
docker compose --profile prod down
```

---

## What you learned

* A Python package with a real CLI, type hints and a deterministic suite is
  the maintainable form of a script.
* A multi-stage container build has exactly two sharp edges: the build
  context has to contain everything the package metadata names, and the
  install must not point back at a stage that is not in the final image.
* The same test suite runs on three operating systems and three Python
  versions, which is what makes a portability claim credible.

---

## Related

* [LAB 1 — Native monitoring with Bash](LAB1_NATIVE_BASH_MONITORING.md)
* [LAB 2 — The same tool in PowerShell](LAB2_POWERSHELL_PARITY.md)
