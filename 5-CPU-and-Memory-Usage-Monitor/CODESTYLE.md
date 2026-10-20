# CODESTYLE — CPU and Memory Usage Monitor

> The conventions this module follows. The repository-wide baseline lives in
> [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) §Code Standards and
> [`../../wiki/09-Code-Style-and-Standards.md`](../../wiki/09-Code-Style-and-Standards.md);
> this file records the rules that are specific to this module.

---

## 1. English only

All code, comments, identifiers, documentation and commit messages are
English. The scripts are plain ASCII: no emoji, no typographic quotes, no
smart dashes. A file that was authored on Windows and picked up
double-encoded characters once printed mojibake in every message, and the
module now stays ASCII on purpose.

---

## 2. Bash

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C
```

* The shebang is `#!/usr/bin/env bash`, so the script runs wherever bash
  lives rather than only at `/bin/bash`.
* `LC_ALL=C` is not optional. See [`SPECS.md`](SPECS.md) §3.
* Declare a variable before assigning a command's output to it. Assigning
  and declaring in one statement, `local x=$(cmd)`, hides the command's
  exit status.
* Quote every expansion. `set -u` catches an unset variable, not an
  unintended word split.
* Do not pipe into `head` to limit the output. `head` closes the pipe
  early, the writer takes a SIGPIPE, and `pipefail` turns that into a
  failed pipeline. Limit the rows inside the consumer instead.
* Every function that reads a command's output returns it on standard
  output, never through a global.

---

## 3. PowerShell

* `#Requires -Version 5.1` at the top of every script.
* `[CmdletBinding()]` on every script and on every advanced function.
* Approved verb-noun names: `Get-`, `Stop-`, `Restart-`, `Write-`,
  `Show-`, `Test-`.
* `$ErrorActionPreference = "Stop"`, so a failure is an exception rather
  than a silent wrong answer.
* A function that changes system state supports `ShouldProcess`, so
  `-WhatIf` and `-Confirm` work.
* `Write-Host` is the right output channel here: this is a terminal
  display tool. The PSScriptAnalyzer settings file records that decision.
* Never evaluate an expression that mixes a null check with a comparison
  in the wrong order: `$null -ne $value`, not `$value -ne $null`.
* An empty `catch` block is never acceptable. Say what went wrong.

---

## 4. Python

* PEP 8, with a 100 character line limit.
* `snake_case` for functions and variables, `PascalCase` for classes,
  `UPPER_SNAKE_CASE` for constants.
* Type hints on every public function. `from __future__ import annotations`
  keeps the modern annotation syntax valid on Python 3.9.
* `ruff check` and `ruff format --check` must both pass.
* No `print()`. Use the logger.
* Catch specific exceptions, never a bare `except Exception`.
* Structured logging, not interpolated strings.

---

## 5. Tests

* The suite lives in [`tests/`](tests/) for the native scripts and in
  `Stage2-Python-Unified/tests/` and `Stage3-Containerization/tests/` for
  the Python package.
* Every test exercises the public interface: the flags, the exit codes and
  the files the tool emits. Nothing asserts on internals.
* Every test is deterministic. The filesystem is isolated under a
  temporary directory, and no test depends on the host's disk layout, its
  running processes, its locale or its culture.
* A test that cannot run in CI does not belong in the suite.

---

## 6. Exit codes

Exit codes are a public contract:

| Code | Meaning |
| :--- | :--- |
| 0 | Success |
| 1 | Configuration or safety violation |
| 2 | Partial failure — reserved, not used yet |

The native scripts and the Python package return the same code for the
same request.

---

## 7. Commits

Conventional Commits, scoped by module:

```
feat(cpu-monitor): add the Stage 3 compose profiles
fix(cpu-monitor): apply --cpu-threshold to the display output
docs(cpu-monitor): document the data contract
ci(cpu-monitor): relocate the pipeline to the repository root
test(cpu-monitor): cover the native scripts
```

The subject line is imperative and under 72 characters. The body explains
**why**, not what. Never add a `Co-Authored-By` trailer or any other AI
attribution.

---

## 8. Line endings

The repository pins them in [`.gitattributes`](../../.gitattributes):

| Pattern | Stored | Checked out |
| :--- | :--- | :--- |
| `*.sh`, `*.py`, `*.yml`, `*.md`, `*.toml`, `*.txt` | LF | LF |
| `*.ps1` | LF | CRLF |

PowerShell 5.1 reads a file without a byte order mark as ANSI, so the
PowerShell scripts keep their UTF-8 BOM. Do not strip it.

---

## 9. Repository layout

* One numbered folder per module, self-contained.
* No module reaches into another module's code.
* Exactly one CI workflow per module, at the repository root, path-filtered
  to that module's folder.
* Documentation about a module lives inside that module.
