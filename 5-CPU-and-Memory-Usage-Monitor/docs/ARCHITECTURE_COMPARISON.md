# Architecture Comparison — CPU and Memory Usage Monitor

> How the three implementations of this module differ, and why.

---

## 1. The shape of the problem

The module started as two scripts that had to work on a Unix host and on a
Windows host. That constraint produced the native pair first, and the
unified Python package second, once the duplication was judged to cost more
than it bought.

The three implementations are not three builds of the same program. They
are three answers to the same question, written at different times by
different hands, and they still disagree in a few places. This document is
the map of those disagreements.

---

## 2. Side by side

| Aspect | Stage 1 — Bash | Stage 1 — PowerShell | Stage 2/3 — Python |
| :--- | :--- | :--- | :--- |
| Lines of implementation | ~950 | ~830 | ~1,050 |
| Argument parsing | hand-written `while` loop | `param()` with `ValidateRange` and `ValidateSet` | Click |
| Dependency | none beyond coreutils | none beyond the OS | `click`, `psutil` |
| Output modes | display, JSON, CSV | display, JSON, CSV | display, JSON, CSV |
| Watch mode | `--watch [seconds]` | `-Watch -RefreshSeconds` | `--watch --interval` |
| Process limits | fixed at 100 | `-TopProcesses` | `--top` |
| CPU threshold | fixed at 80 | `-CpuThreshold` | `--cpu-threshold` |
| Memory threshold | fixed at 80 | `-MemThreshold` | `--mem-threshold` |
| Kill method | signal name | graceful, terminate, kill | graceful, then force |
| Error handling | `set -euo pipefail`, `ERR` trap | `$ErrorActionPreference = "Stop"` | typed exceptions |
| Audit log | `KILL_LOG_DIR`, default `/tmp` | `KILL_LOG_DIR`, default the platform temp path | `KILL_LOG_DIR`, default the platform temp path |
| Tests | `tests/test_system_monitor.sh` | `tests/test_system_monitor.ps1` | `tests/test_*.py`, 45 tests |
| Static analysis | ShellCheck, clean | PSScriptAnalyzer, clean | ruff, clean |

---

## 3. Where the implementations agree

* The JSON key names. All three emit `timestamp`, `os`, `cpu_percent`,
  `memory_percent`, `disk_usage`, `disk_io`, `top_processes` and
  `aggregated_totals`, with the same nested names.
* The CSV column order: `timestamp, os, metric_type, name, pid,
  cpu_percent, ram_mb, instances, mount_point, device, percent_used`.
* The exit codes: 0 for success, 1 for a configuration or safety violation.
* The locale independence. The scripts pin `LC_ALL=C`, PowerShell pins
  `InvariantCulture`, and Python formats floats without consulting the
  locale at all.
* The HIGH marker. Above the threshold the display reads `42.0% (HIGH)`,
  with the same comparison and the same wording in all three.

---

## 4. Where they differ

### 4.1 Configuration surface

The Bash script has the smallest surface: the thresholds and the process
count are compile-time constants. The other two expose them. This is the
largest remaining parity gap, and it is a gap in the Bash script rather
than in the others.

### 4.2 Disk I/O semantics

| | Bash | PowerShell | Python |
| :--- | :--- | :--- | :--- |
| `reads_completed`, `writes_completed` | yes | no | yes |
| `read_sectors`, `write_sectors` | yes | no | yes |
| `reads_per_sec`, `writes_per_sec` | no | yes | yes |
| `read_bytes_per_sec`, `write_bytes_per_sec` | no | yes | yes |

The reason is the source. `/proc/diskstats` reports cumulative counters,
which is what the Bash script reads, while the Windows performance counters
report rates. The Python package uses `psutil`, which exposes both
families, so it reports both.

**The values are not interchangeable.** A consumer that reads the Bash
output and the PowerShell output as the same field is reading two
different things.

### 4.3 Disk usage values

The Bash script and the PowerShell script report disk sizes as strings
with a unit suffix, `"672G"`. The Python package reports numbers,
`total_gb = 672.0`.

### 4.4 CSV quoting

The Bash and Python implementations write bare fields. PowerShell's
`Export-Csv` quotes every field. Both are valid CSV and parse to the same
values; only the bytes differ.

### 4.5 Argument parsing philosophy

The Bash script parses arguments in a `while` loop and prints its own
usage on an unknown flag. The PowerShell script lets the parameter binder
reject an invalid value, and the Python package lets Click do the same. The
error messages therefore differ in wording, though they agree on the exit
code.

---

## 5. Why the stages are not merged

The tempting move is to delete the native scripts and keep the Python
package. That is not what this module is for.

* **The scripts have no runtime dependency.** A host with no Python, no
  package manager and no network can still monitor itself. That is the
  property the scripts exist to demonstrate.
* **They teach different things.** Shell and PowerShell are where a
  junior engineer learns how a system reports on itself. The Python
  package is where they learn when an abstraction layer pays for itself.
* **The container stage needs a package.** Stage 3 installs a distribution,
  which is something Python does well and a shell script does not.

The cost is the divergence documented above, and it is paid knowingly.

---

## 6. Related

* Technical specification: [`../SPECS.md`](../SPECS.md)
* Operational scenarios: [`SCENARIOS.md`](SCENARIOS.md)
* Hands-on labs: [`labs/`](labs/)
