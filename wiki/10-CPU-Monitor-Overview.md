# 10. CPU & Memory Usage Monitor — Overview & Specs

> Module 5 of the [Scripts-DevOps-Practice](https://github.com/Merxxotas/Scripts-DevOps-Practice)
> monorepo: a cross-platform system resource monitor that reports CPU,
> memory, disk and process usage, and can stop or restart a process.

---

## What it is

A monitoring CLI with three implementations of the same tool and one shared
data contract:

| Stage | Implementation | Runtime |
| :--- | :--- | :--- |
| 1 | Native scripts | Bash 4+ / PowerShell 5.1+ |
| 2 | Unified package | Python 3.9+ |
| 3 | Container image | Alpine 3.18+ |

Stage 4 is the CI pipeline, which lives at the repository root.

The module ships four shells' worth of documentation: the
[`README.md`](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/5-CPU-and-Memory-Usage-Monitor/README.md),
[`SPECS.md`](https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/5-CPU-and-Memory-Usage-Monitor/SPECS.md),
a `docs/` folder with an architecture comparison, the operational scenarios
and three hands-on labs, and this wiki.

---

## The data contract

All three implementations emit the same JSON key names:

```json
{
  "timestamp": "2026-10-20T14:02:36.2626960-05:00",
  "os": "Linux",
  "cpu_percent": 10.64,
  "memory_percent": 38.70,
  "disk_usage": [
    { "mount_point": "/", "total": "672G", "used": "324G",
      "free": "347G", "percent_used": 49 }
  ],
  "disk_io": [
    { "device": "sda", "reads_completed": 84536,
      "writes_completed": 10736, "read_sectors": 19081,
      "write_sectors": 637 }
  ],
  "top_processes": [
    { "name": "python", "pid": 1234, "cpu_percent": 25.0, "ram_mb": 512.0 }
  ],
  "aggregated_totals": [
    { "name": "python", "total_ram_mb": 1024.0, "instances": 1 }
  ]
}
```

The CSV output carries the same eleven columns in the same order:

```
timestamp,os,metric_type,name,pid,cpu_percent,ram_mb,instances,mount_point,device,percent_used
```

A consumer can parse any of the three without knowing which produced the
output.

---

## The interface

| Concern | Bash | PowerShell | Python |
| :--- | :--- | :--- | :--- |
| Watch mode | `--watch [seconds]` | `-Watch -RefreshSeconds` | `--watch --interval` |
| Output format | `-j` / `-c` | `-Format` | `--format` |
| Export | `-e <path>` | `-ExportPath` | `--export` |
| Process count | fixed at 100 | `-TopProcesses` | `--top` |
| CPU threshold | fixed at 80 | `-CpuThreshold` | `--cpu-threshold` |
| Memory threshold | fixed at 80 | `-MemThreshold` | `--mem-threshold` |
| Stop a process | `--kill` | `-Kill` | `kill` subcommand |
| Restart a process | `--restart` | `-Restart` | `restart` subcommand |

Exit codes are a public contract across all three: **0** for success, **1**
for a configuration or safety violation such as an unknown flag, a value out
of range, or a target process that does not exist.

---

## Three defects worth knowing about

Every one of these was found while bringing the module up to the
repository's standard, and every one of them is now covered by a
regression test.

### The output followed the host locale

Under a locale whose decimal separator is a comma, `es_CO` or `de_DE` for
example, `awk` still produced a dot and `printf` rejected the value as an
invalid number. A run that should have succeeded exited 1.

Both native scripts now pin their locale — `LC_ALL=C` in Bash,
`InvariantCulture` in PowerShell — and the test suites run the tool under a
comma-decimal locale to prove it.

### The pipe closed early

`get_process_data` piped into `head -n $TOP_PROCESSES`. `head` closes the
pipe after N lines, `sort` takes a SIGPIPE, and `pipefail` turns that into
a failed pipeline. On any host running more than 100 processes the script
failed. The limit now lives inside the consumer.

### The container image had never been built

The Dockerfile's builder stage copied only `pyproject.toml`, so the
package metadata had no `README.md` to point at and hatchling had no
`src/system_monitor` to build. The install was also editable, which
resolves the package back to the builder stage that the runtime image does
not have. Both were fixed.

---

## Where to go next

* [11. Bash vs PowerShell vs Python](11-CPU-Monitor-Bash-vs-PowerShell.md)
* [12. Scenarios & Interactive Labs](12-CPU-Monitor-Scenarios-and-Labs.md)
* [08. CI/CD Pipelines & Testing Philosophy](08-CI-CD-Pipelines.md)
* [09. Code Style & Engineering Standards](09-Code-Style-and-Standards.md)
