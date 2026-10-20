# LAB 1 — Native Monitoring with Bash

> **Goal:** run the Stage 1 Bash implementation, read its output, and prove
> that the output does not depend on the host.
>
> **Time:** 15 minutes · **Prerequisites:** Linux or macOS with Bash 4+.

---

## Step 1 — Meet the tool

```bash
cd 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts
./system_monitor.sh --help
```

Expected:

```
System Resource Monitor v1.3.0
Usage: system_monitor.sh [OPTIONS]

Display Options:
  -w, --watch [seconds]  Enable watch mode (default: 2s, range: 0.1-300)
  -j, --json             Output JSON to stdout
  -c, --csv              Output CSV to stdout
  -h, --help             Display this help and exit
  -v, --version          Display version information and exit

Process Management Options:
  -k, --kill <pid|name>  Kill process by PID or name
```

Every flag in that list is part of the public contract. Compare it with the
PowerShell parameter list in [`../../SPECS.md`](../../SPECS.md) §4.2.

---

## Step 2 — Take a snapshot

```bash
./system_monitor.sh
```

Expected:

```
=== System Resource Monitor ===
2026-10-20 14:13:08
OS: Linux

CPU Usage: 8.71%
Memory Usage: 38.61%

Disk Usage:
/                   324G used /     672G total ( 49%)
/home               324G used /     672G total ( 49%)
```

The figures move between runs; the shape does not. A CPU figure above the
threshold is marked `(HIGH)` in red.

---

## Step 3 — Read it as a machine

```bash
./system_monitor.sh --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(', '.join(sorted(data.keys())))
"
```

Expected:

```
aggregated_totals, cpu_percent, disk_io, disk_usage, memory_percent, os, timestamp, top_processes
```

The same eight keys come out of the PowerShell and the Python
implementations. That is the contract, and
[`../../docs/ARCHITECTURE_COMPARISON.md`](../../docs/ARCHITECTURE_COMPARISON.md) §3
lists what else they agree on.

---

## Step 4 — Find the memory hog

The process list is sorted by resident memory:

```bash
./system_monitor.sh --json | python3 -c "
import json, sys
for proc in json.load(sys.stdin)['top_processes'][:3]:
    print(f\"{proc['ram_mb']:>10.1f} MB  {proc['name']}\")
"
```

Expected:

```
     696.0 MB  brave
     683.0 MB  brave
     659.0 MB  brave
```

The same program often appears several times, once per process. For the
total per program, read `aggregated_totals` instead.

---

## Step 5 — Prove the output is locale independent

This is the step worth remembering. The script used to inherit the host
locale, and under a locale whose decimal separator is a comma it failed:

```bash
LC_ALL=es_CO.UTF-8 ./system_monitor.sh --json > /dev/null
echo "exit=$?"
```

Expected:

```
exit=0
```

If that locale is not installed the command still succeeds, because the
script pins `LC_ALL=C` itself. To watch the failure it would have been,
try the same command against a program that does not pin the locale:

```bash
LC_ALL=es_CO.UTF-8 python3 -c "print(f'{15337.15:.2f}')"
```

The test suite carries this as a regression test:

```bash
cd ..
bash tests/test_system_monitor.sh
```

Expected:

```
==============================================
Tests Passed: 20
Tests Failed: 0
==============================================
```

---

## Step 6 — Check the exit code contract

```bash
./system_monitor.sh --no-such-flag > /dev/null 2>&1
echo "exit=$?"
```

Expected:

```
exit=1
```

| Code | Meaning |
| :--- | :--- |
| 0 | Success |
| 1 | Configuration or safety violation |

---

## What you learned

* The tool has three implementations that share one data contract.
* The output has to be pinned to a locale, or a host configuration can turn
  a successful run into a failed one.
* Exit codes are part of the interface, not an implementation detail.

---

## Next

* [LAB 2 — The same tool in PowerShell](LAB2_POWERSHELL_PARITY.md)
* [LAB 3 — The unified Python package and the container](LAB3_PYTHON_PACKAGE.md)
