# 12. CPU Monitor — Scenarios & Interactive Labs

> How module 5 is used in practice, and three hands-on labs that run the
> real commands.

---

## The scenarios

### A quick look at a host

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts
./system_monitor.sh
```

The display reads the CPU and memory percentages, lists the mounted
filesystems with a colour coded usage bar, and prints the twenty processes
with the highest resident memory. Anything above the threshold is marked
`(HIGH)` in red.

The memory figure is the one that matters on a host that has been up for a
while. A CPU figure near 100% is often a single runaway process; memory
that keeps climbing is a leak.

### Feeding a log collector

```bash
./system_monitor.sh --json --export /var/log/system-monitor/snapshot.json
```

For a rolling directory, where each run gets a timestamped name:

```bash
./system_monitor.sh --watch 60 --json --export /var/log/system-monitor/
```

The JSON is a single object with the timestamp in ISO 8601. In watch mode
with a JSON export the file holds a JSON array, and the array is closed
when the process is interrupted.

### A scheduled check

```cron
*/5 * * * * /opt/system-monitor/system_monitor.sh --json --export /var/log/system-monitor/snapshot.json
```

The container equivalent, for a host that runs services under Compose:

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage3-Containerization
docker compose --profile prod up -d
```

The production profile runs as UID 1000 with a read-only root filesystem, a
128 MB memory limit and no added capabilities beyond `SYS_PTRACE`, which is
the one the process listing needs.

### Investigating a runaway process

The process list is sorted by resident memory, which is usually where the
answer is.

```bash
./system_monitor.sh --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for proc in data['top_processes'][:5]:
    print(f\"{proc['ram_mb']:>10.1f} MB  {proc['name']}\")
"
```

The `aggregated_totals` section is the more useful view when the same
program runs many times. It sums the resident memory per program name, so a
browser with thirty tabs shows up as one line rather than thirty.

### Stopping a process safely

```bash
./system_monitor.sh --kill 1234
```

The action is written to the audit log before it is attempted:

```
[2026-10-20T14:05:11+00:00] [KILL] PID/Name: 1234 | Result: SUCCESS | Process: nginx, Signal: SIGTERM
```

The PowerShell implementation can also preview the action before taking it:

```powershell
.\system_monitor.ps1 -Kill 1234 -WhatIf
```

```
What if: Performing the operation "Stop" on target "Process 1234 (sleep)".
```

Nothing is stopped, and nothing is written to the audit log, because the
action never runs.

---

## The labs

Each lab runs real commands and shows real output. They live with the
module, in
[`5-CPU-and-Memory-Usage-Monitor/docs/labs/`](https://github.com/Merxxotas/Scripts-DevOps-Practice/tree/main/5-CPU-and-Memory-Usage-Monitor/docs/labs).

### LAB 1 — Native monitoring with Bash

Fifteen minutes. Covers the flag list, the JSON contract, the process
listing, the locale independence and the exit code contract.

```bash
cd 5-CPU-and-Memory-Usage-Monitor
bash tests/test_system_monitor.sh
```

```
==============================================
Tests Passed: 20
Tests Failed: 0
==============================================
```

### LAB 2 — The same tool in PowerShell

Fifteen minutes. Covers the parameter list, the parity with Bash, the
threshold flags the Bash script does not have, and the `-WhatIf` preview.

```powershell
pwsh -File 5-CPU-and-Memory-Usage-Monitor/tests/test_system_monitor.ps1
```

```
==============================================
Tests Passed: 18
Tests Failed: 0
==============================================
```

### LAB 3 — The unified Python package and the container

Twenty minutes. Covers the install, the thresholds, the test suite, the
lint gates, the container build and the compose profiles.

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv venv .venv && uv pip install -e ".[dev]"
uv run pytest
```

```
============================== 45 passed in 0.09s ==============================
```

---

## The CI pipeline

The module's pipeline lives at the repository root, in
`.github/workflows/ci-cpu-monitor.yml`, and is path-filtered to
`5-CPU-and-Memory-Usage-Monitor/**`.

| Job | Runner | Gate |
| :--- | :--- | :--- |
| `lint-bash` | `ubuntu-24.04` | ShellCheck and `bash -n` |
| `test-bash` | `ubuntu-24.04`, `macos-14` | the Bash suite |
| `lint-powershell` | `windows-2022` | PSScriptAnalyzer |
| `test-powershell` | `windows-2022`, `ubuntu-24.04` | the PowerShell suite |
| `test-python` | 3 OS × Python 3.9/3.12/3.13 | ruff and pytest, for Stage 2 and Stage 3 |
| `build-docker` | `ubuntu-24.04` | the container image builds and runs |

Stage 3 is tested separately from Stage 2 because the container image
installs the package from **its own** `src/` tree, so testing Stage 2 alone
would leave the shipped tree unverified.

See
[08. CI/CD Pipelines & Testing Philosophy](08-CI-CD-Pipelines) for the
monorepo-wide model.

---

## Where to go next

* [10. CPU & Memory Usage Monitor — Overview & Specs](10-CPU-Monitor-Overview)
* [11. Bash vs PowerShell vs Python](11-CPU-Monitor-Bash-vs-PowerShell)
