# LAB 2 — The Same Tool in PowerShell

> **Goal:** run the Stage 1 PowerShell implementation, check that it agrees
> with the Bash one, and see the places where it does not.
>
> **Time:** 15 minutes · **Prerequisites:** PowerShell 7 on Linux or
> macOS, or Windows PowerShell 5.1 on Windows.

---

## Step 1 — Meet the tool

```powershell
cd 5-CPU-and-Memory-Usage-Monitor/Stage1-Native-Scripts
.\system_monitor.ps1 -Version
```

Expected:

```
System Resource Monitor v1.3.0
```

The Bash implementation answers the same question with `--version`, and
prints the operating system on the second line. The PowerShell one prints
only the version.

The parameter list is documented in
[`../../SPECS.md`](../../SPECS.md) §4.2. Compare it with the Bash flag
list in §4.1: the PowerShell script exposes the CPU and memory thresholds
and the process count as parameters, while the Bash script fixes them.

---

## Step 2 — Take a snapshot

```powershell
.\system_monitor.ps1
```

Expected:

```
=== System Resource Monitor ===
2026-10-20 14:13:23
 OS: Linux

CPU Usage: 14.39%
Memory Usage: 38.90%

Disk Usage:
```

---

## Step 3 — Check the data contract

```powershell
.\system_monitor.ps1 -Format Json | python3 -c "
import json, sys
print(', '.join(sorted(json.load(sys.stdin).keys())))
"
```

Expected:

```
aggregated_totals, cpu_percent, disk_io, disk_usage, memory_percent, os, timestamp, top_processes
```

Identical to the Bash output in [LAB 1](LAB1_NATIVE_BASH_MONITORING.md)
and to the Python output in
[LAB 3](LAB3_PYTHON_PACKAGE.md). All three implementations speak the
same machine-readable contract.

---

## Step 4 — Use the threshold the Bash script does not expose

```powershell
.\system_monitor.ps1 -CpuThreshold 5 -MemThreshold 5
```

Every reading is now above the threshold, so every line is marked
`(HIGH)`:

```
CPU Usage: 14.39% (HIGH)
Memory Usage: 38.90% (HIGH)
```

The Bash script cannot do this: its threshold is fixed at 80.

---

## Step 5 — Ask before acting

The three functions that stop and restart processes support `-WhatIf` and
`-Confirm`.

```powershell
.\system_monitor.ps1 -Kill 1234 -WhatIf
```

Expected:

```
What if: Performing the operation "Stop" on target "Process 1234 (sleep)".
```

Nothing is stopped, and nothing is written to the audit log, because the
action never runs.

Without `-WhatIf` the tool acts immediately and records the attempt in the
audit log. `-Confirm` asks before it acts, which is what an interactive
operator usually wants.

```powershell
.\system_monitor.ps1 -Kill 1234 -Confirm
```

Expected:

```
Confirm
Are you sure you want to perform this action?
```

The Bash implementation has no equivalent of either switch. It always acts
and always records the attempt.

---

## Step 6 — Check the exit code contract

```powershell
.\system_monitor.ps1 -NoSuchParameter > $null
$LASTEXITCODE
```

Expected:

```
1
```

A missing parameter, an out-of-range value and a target process that does
not exist all exit 1, exactly as the Bash script does.

---

## Step 7 — Run the suite

```powershell
cd ../tests
pwsh -File test_system_monitor.ps1
```

Expected:

```
==============================================
Tests Passed: 16
Tests Failed: 0
==============================================
```

The suite mirrors the Bash one, so the two implementations are held to the
same contract.

---

## Where the two differ

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| Thresholds | Fixed at 80 | `-CpuThreshold`, `-MemThreshold` |
| Process count | Fixed at 100 | `-TopProcesses` |
| Output format | `-j` and `-c` | `-Format` |
| Kill method | Signal name | Graceful, terminate, kill |
| Dry run | Not available | `-WhatIf`, `-Confirm` |
| CSV quoting | Bare fields | Every field quoted |
| Disk I/O fields | Cumulative counters | Per-second rates |

The full list, with the reasons, is in
[`../ARCHITECTURE_COMPARISON.md`](../ARCHITECTURE_COMPARISON.md) §4.

---

## What you learned

* Two implementations of one tool can share a data contract while differing
  in everything else, and the differences are worth writing down.
* `-WhatIf` is the cheapest safety feature in PowerShell, and it costs one
  attribute and one guard.

---

## Next

* [LAB 3 — The unified Python package and the container](LAB3_PYTHON_PACKAGE.md)
