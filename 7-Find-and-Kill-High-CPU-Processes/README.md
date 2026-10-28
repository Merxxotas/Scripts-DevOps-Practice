# Find and Kill High-CPU Processes 🔪

Cross-platform detection and termination of runaway CPU processes. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: never targets PID 0/1, self, parent, or kernel threads.
- 🧪 **Dry-Run Simulation**: list candidates and preview kills without signaling.
- 🔁 **Interactive by default**: prompts per candidate; `--auto-kill` for unattended use.
- ⚡ **Force mode**: SIGKILL / `Stop-Process -Force` when graceful termination fails.
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- ⚙️ **Zero Dependencies** beyond the shell and the platform process tools.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x kill_high_cpu.sh

# List candidates above 50% CPU (interactive)
./kill_high_cpu.sh

# Auto-kill all candidates above 80%
./kill_high_cpu.sh -t 80 --auto-kill

# Dry run
./kill_high_cpu.sh --dry-run

# Force (SIGKILL)
./kill_high_cpu.sh -t 90 --auto-kill --force
```

### Windows (PowerShell)

```powershell
# List candidates above 50% CPU (interactive)
.\kill_high_cpu.ps1

# Auto-kill all candidates above 80%
.\kill_high_cpu.ps1 -CpuThreshold 80 -AutoKill

# Dry run
.\kill_high_cpu.ps1 -DryRun

# Force
.\kill_high_cpu.ps1 -CpuThreshold 90 -AutoKill -Force
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success · `1` configuration or safety violation · `2` partial failure (a kill failed).

---

## Tests

```bash
bash tests/test_kill_high_cpu.sh
pwsh tests/test_kill_high_cpu.ps1
```

The Bash suite stubs `ps` and `kill`; no real process is signaled. The PowerShell suite
exercises parsing, guardrails and dry-run.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.