# 11. CPU Monitor — Bash vs PowerShell vs Python

> How the three implementations of module 5 differ, and what each one is
> better at.

---

## The trade-off they encode

The module started as two scripts that had to work on a Unix host and on a
Windows host. That constraint produced the native pair first, and the
unified Python package second, once the duplication was judged to cost more
than it bought.

The scripts have **no runtime dependency**. A host with no Python, no
package manager and no network can still monitor itself. That is the
property they exist to demonstrate, and it is the reason they were not
deleted when the package arrived.

---

## Side by side

| Aspect | Bash | PowerShell | Python |
| :--- | :--- | :--- | :--- |
| Lines of implementation | ~950 | ~830 | ~1,050 |
| Argument parsing | hand-written loop | `param()` + validation attributes | Click |
| Dependency | coreutils | the OS | `click`, `psutil` |
| Tests | 20 | 18 | 45 |
| Static analysis | ShellCheck, clean | PSScriptAnalyzer, clean | ruff, clean |
| Error handling | `set -euo pipefail`, `ERR` trap | `$ErrorActionPreference = "Stop"` | typed exceptions |
| Audit log | `/tmp` by default | the platform temp path | the platform temp path |
| Confirmation before acting | none | `-WhatIf`, `-Confirm` | none |

---

## Where they agree

* The JSON key names, at every level of nesting.
* The CSV column order.
* The exit codes: 0 for success, 1 for a configuration or safety violation.
* The locale independence. The scripts pin `LC_ALL=C`, PowerShell pins
  `InvariantCulture`, and Python formats floats without consulting the
  locale at all.
* The HIGH marker. Above the threshold the display reads `42.0% (HIGH)`,
  with the same comparison and the same wording in all three.

---

## Where they differ

### Configuration surface

The Bash script has the smallest surface: the thresholds and the process
count are compile-time constants. The other two expose them. This is the
largest remaining parity gap, and it is a gap in the Bash script rather
than in the others.

### Disk I/O semantics

| | Bash | PowerShell | Python |
| :--- | :--- | :--- | :--- |
| `reads_completed`, `writes_completed` | yes | no | yes |
| `read_sectors`, `write_sectors` | yes | no | yes |
| `reads_per_sec`, `writes_per_sec` | no | yes | yes |
| `read_bytes_per_sec`, `write_bytes_per_sec` | no | yes | yes |

The reason is the source. `/proc/diskstats` reports cumulative counters,
which is what the Bash script reads, while the Windows performance
counters report rates. `psutil` exposes both families, so the Python
package reports both.

**The values are not interchangeable.** A consumer that reads the Bash
output and the PowerShell output as the same field is reading two
different things.

### Disk usage values

The scripts report disk sizes as strings with a unit suffix, `"672G"`. The
Python package reports numbers, `total_gb = 672.0`.

### CSV quoting

The Bash and Python implementations write bare fields. PowerShell's
`Export-Csv` quotes every field. Both are valid CSV and parse to the same
values; only the bytes differ.

### Argument validation

The Bash script parses arguments in a loop and prints its own usage on an
unknown flag. PowerShell lets the parameter binder reject an invalid value
and Python lets Click do the same. The messages differ in wording; the exit
codes do not.

---

## What each one is better at

**Bash** — a host with nothing installed. It also reads more naturally to
someone learning how a Unix system reports on itself: text streams, pipes,
small utilities.

**PowerShell** — a Windows administrator. Object pipelines rather than text
streams, and the only one of the three that can preview an action before
taking it with `-WhatIf`.

**Python** — anything that has to be maintained or distributed. Type hints,
a real test suite, a package that installs, and a container image that
ships the same code.

---

## Where to go next

* [10. CPU & Memory Usage Monitor — Overview & Specs](10-CPU-Monitor-Overview.md)
* [12. Scenarios & Interactive Labs](12-CPU-Monitor-Scenarios-and-Labs.md)
* [06. Bash vs PowerShell Architecture Comparison](06-Log-Cleanup-Bash-vs-PowerShell.md)
* [03. Python vs Go Architecture Comparison](03-EventOps-Python-vs-Go.md)
