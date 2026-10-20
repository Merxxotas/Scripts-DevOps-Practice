# Scenarios — CPU and Memory Usage Monitor

> How this module is used in practice, and what to expect when it runs.

---

## Scenario 1 — A quick look at a host

The most common case: find out what a machine is doing right now.

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts
./system_monitor.sh
```

The display reads the CPU and memory percentages, lists the mounted
filesystems with a colour coded usage bar, and prints the twenty processes
with the highest resident memory. Anything above the threshold is marked
`(HIGH)` in red.

On Windows the same thing is:

```powershell
cd 5-CPU-and-Memory-Usage-Monitor\Stage1-Native-Scripts
.\system_monitor.ps1
```

The Python package behaves the same way:

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv run -m system_monitor
```

**What to watch.** The memory figure is the one that matters on a host that
has been up for a while. A CPU figure near 100% is often a single runaway
process; memory that keeps climbing is a leak.

---

## Scenario 2 — Feeding a log collector

The tool emits JSON so the output can be ingested by a log collector rather
than read by a human.

```bash
./system_monitor.sh --json --export /var/log/system-monitor/snapshot.json
```

The same for a rolling directory, where each run gets a timestamped name:

```bash
./system_monitor.sh --watch 60 --json --export /var/log/system-monitor/
```

**What to watch.** The JSON is written as a single object, with the
timestamp in ISO 8601. In watch mode with a JSON export the file holds a
JSON array, and the array is closed when the process is interrupted.

---

## Scenario 3 — A scheduled check

A cron job that captures a snapshot every five minutes and keeps a week of
history.

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

---

## Scenario 4 — Investigating a runaway process

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

**What to watch.** The `aggregated_totals` section is the more useful view
when the same program runs many times. It sums the resident memory per
program name, so a browser with thirty tabs shows up as one line rather
than thirty.

---

## Scenario 5 — Stopping a process safely

```bash
./system_monitor.sh --kill 1234
```

The action is written to the audit log before it is attempted:

```
[2026-10-20T14:05:11+00:00] [KILL] PID/Name: 1234 | Result: SUCCESS | Process: nginx, Signal: SIGTERM
```

To ask the tool what it would do without doing it, the PowerShell
implementation supports `-WhatIf`:

```powershell
.\system_monitor.ps1 -Kill 1234 -WhatIf
```

To restart a service under a specific command:

```bash
./system_monitor.sh --restart nginx --restart-cmd "nginx -c /etc/nginx/nginx.conf"
```

**What to watch.** A missing PID is an error, not a success. Both native
implementations exit 1 when the target does not exist, so a script that
watches the exit code notices the difference.

---

## Scenario 6 — A host whose locale uses a comma

This is the failure that motivated the locale pinning, and it is worth
knowing because it looks like a random crash.

```bash
$ locale
LC_NUMERIC=es_CO.UTF-8

$ ./system_monitor.sh --json
printf: 15337.15: invalid number
```

The script used to inherit the host locale, the values it produced carried
a dot, and `printf` rejected them because the locale expected a comma. The
run failed with a non-zero exit even though nothing had actually gone
wrong.

Both native scripts now pin their locale, and the test suites carry a
regression test that runs the tool under a comma-decimal locale and asserts
that the output still parses.

---

## Scenario 7 — Verifying a release

Before shipping a change to this module, the gates can be reproduced
locally:

```bash
# Bash
shellcheck -x 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts/system_monitor.sh
bash 5-CPU-and-Memory-Usage-Monitor/tests/test_system_monitor.sh

# PowerShell
pwsh -File 5-CPU-and-Memory-Usage-Monitor/tests/test_system_monitor.ps1

# Python
cd 5-CPU-and-Memory-Usage-Monitor/Stage2-Python-Unified
uv run ruff check src tests && uv run ruff format --check src tests && uv run pytest
```

The same commands run in CI. See
[`../Stage4-CI-CD-Pipeline/README.md`](../Stage4-CI-CD-Pipeline/README.md).

---

## Related

* Architecture comparison: [`ARCHITECTURE_COMPARISON.md`](ARCHITECTURE_COMPARISON.md)
* Hands-on labs: [`labs/`](labs/)
* Flag reference: [`../SPECS.md`](../SPECS.md)
