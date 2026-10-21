# 14. Disk Monitor — Bash vs PowerShell

> The same contract expressed in two languages: where the two implementations
> must agree, where they legitimately differ, and what the parity buys.

---

## The trade-off they encode

The repository's module contract asks for one behaviour and two runtimes:

> "**Parity across platforms.** Bash and PowerShell must implement the
> **same flags, defaults, exit codes and safety guardrails**. A flag on only
> one side is a defect."

Module 1 is the first module to take that seriously, and the reason is
practical rather than ideological: the fleets this module is meant to watch
are **mixed**. A fleet with a Linux VPS, a macOS laptop and a Windows file
server cannot be monitored by a Bash script alone, and a fleet that cannot
be monitored is a fleet nobody trusts.

The cost of that choice is duplication — the alert body, the validation
order and the exit-code mapping exist twice. The benefit is that the module
**has no runtime dependency beyond the platform it already runs on**: no
Python, no package manager, no network, no container. A host with nothing
installed can still watch itself.

The duplication is only affordable because the contract is written down
first. The flags, the defaults, the validation rules, the exit codes and the
report labels are the specification; the two implementations are two
renderings of it.

---

## Side by side

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| File | `disk_monitor.sh` | `disk_monitor.ps1` |
| Interpreter | `bash` 4+ | PowerShell 7+ |
| Strictness | `set -euo pipefail`, `IFS=$'\n\t'` | `Set-StrictMode -Version Latest` |
| Argument parsing | hand-written `while` loop with `case` | `param()` with validation attributes |
| Threshold validation | regex plus a manual range check | `[ValidateRange(1, 100)]` on an `[int]` |
| Notify validation | manual string comparison | `[ValidateSet("none", "mail")]` |
| Verbose | dedicated `-v` / `--verbose` flag | the common `-Verbose` parameter |
| Help | `-h` / `--help`, a heredoc | `-Help`, a `Write-Host` block |
| Default partition | `/` | `/` off Windows, `$env:SystemDrive\` on Windows |
| Measurement (Unix) | `df -P` piped into `awk` | `df -P` output split into fields |
| Measurement (Windows) | not applicable | `Get-CimInstance Win32_LogicalDisk` |
| Capacity field | `$(NF-1)` of the POSIX line | the field before the mount point |
| Mail agent lookup | `command -v` | `Get-Command` |
| Audit timestamp | `date -u +"%Y-%m-%dT%H:%M:%SZ"` | `(Get-Date).ToUniversalTime()` |
| Errors | `printf` to stderr | `[Console]::Error.WriteLine` |
| Functions | `snake_case` | Approved Verb-Noun (`Get-DiskUsagePercent`) |
| Dependency | coreutils (`df`, `awk`) and a mail agent | the OS and a mail agent |

---

## What the shared contract guarantees

These hold on **both** sides, and each one is covered by the test suite.

* **The flag set and every default.** Partition, threshold, notify mode,
  recipient, mail command, log file, verbose and help — the same names, the
  same defaults, the same meaning.
* **The validation rules.** The threshold is an integer in `1`–`100`. The
  notify backend is `none` or `mail`. The partition must exist. A missing
  recipient is an error when the backend is `mail` and irrelevant when it is
  `none`.
* **The exit codes.** `0` success, `1` configuration or safety error, `2`
  partial failure — with the same conditions mapped onto each code.
* **The comparison.** The alert fires when the usage is **strictly greater**
  than the threshold. A filesystem at exactly the threshold does not alert.
* **The order of operations.** Validate the configuration and resolve the
  mail agent, *then* measure, *then* report, *then* hand the alert over.
* **The environment variable names.** `DISK_MONITOR_TO`,
  `DISK_MONITOR_MAIL_COMMAND`, `DISK_MONITOR_USAGE_COMMAND` and
  `DISK_MONITOR_USAGE_OVERRIDE` mean the same thing on both sides.
* **The mail contract.** `<mail-command> -s <subject> <recipient>`, with the
  body on stdin, and the same candidate list — `mail`, then `msmtp`.
* **The audit log format.** One ISO-8601 line per run, carrying the usage,
  its source and the threshold.
* **The report labels.** `measured` and `overridden`, `DRY RUN (Simulation)`
  and `LIVE (Alerts Active)`, `WARNING: Disk usage exceeds the threshold.`
* **Errors go to stderr.** Standard output carries the report and nothing
  else, so `2>/dev/null` suppresses the errors and leaves the report intact.

---

## Where they legitimately differ

### The measurement source

This is the difference that matters, and it is not a choice — it is what
each platform provides.

**Bash** measures with `df -P` and reads the capacity from the fifth field:

```bash
capacity="$(printf '%s\n' "$output" | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"
```

**PowerShell** splits the same line into fields and takes the fifth one:

```powershell
$fields = $lines[1].Trim() -split '\s+'
$capacity = $fields[4].TrimEnd('%')
```

On **Windows**, PowerShell does not parse `df` output at all — it asks the
volume API, which is why the PowerShell implementation is the one that can
watch a Windows file server:

```powershell
$disk = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -eq $deviceId }
```

Bash has no equivalent path, because Bash is not the implementation that
runs on Windows.

Both read the same fixed position, so a filesystem mounted at a path
containing a space — `/mnt/My Backup` — is read exactly like any other. If
what they read is not a number, both **fail safe** and exit `2`, rather than
reporting a wrong number.

### The default partition

Bash hardcodes `/`. PowerShell resolves the partition at run time: the
system drive on Windows, `/` everywhere else. Both accept an explicit
partition, so the difference only shows when the flag is omitted.

### Parameter syntax

Bash uses the POSIX convention — a short flag and a long flag, with the
value in the next argument:

```bash
./disk_monitor.sh -p /home -t 90 -n
```

PowerShell uses named parameters, and the value follows the parameter name:

```powershell
.\disk_monitor.ps1 -Partition C:\ -Threshold 90 -DryRun
```

The vocabulary is the same on both sides — `Partition`, `Threshold`,
`DryRun`, `Notify`, `To`, `MailCommand`, `LogFile`, `Help`, `Verbose` — so
a script that drives one can be translated to the other by changing the
syntax and nothing else.

### Where the validation happens

Bash validates by hand, in a function that runs after the loop:

```bash
if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 ]] || [[ "$THRESHOLD" -gt 100 ]]; then
```

PowerShell delegates to the parameter binder:

```powershell
[ValidateRange(1, 100)]
[int]$Threshold = 80,
```

The **outcomes** are identical — the threshold outside `1`–`100` is a
configuration error and the run exits `1` — but the **message** is not. The
Bash script prints its own sentence; PowerShell prints the binder's. The
exit code is the contract; the wording is not.

### The verbose flag

PowerShell's `-Verbose` is a **common parameter**, which means it belongs to
the script and not to any function inside it. That has a consequence worth
knowing: inside a function, `$PSBoundParameters` describes the *function's*
parameters, so the script has to capture the flag while it is still in
scope:

```powershell
$script:VerboseEnabled = $PSBoundParameters.ContainsKey('Verbose') -and $Verbose
```

Without that line the flag would be accepted and silently ignored. The
suite asserts the exit code and that the report names the partition — not
that the diagnostics line was printed — so nothing would fail.

---

## What each one is better at

**Bash** — a Unix host with nothing installed. It also reads more naturally
to someone learning how a Unix system reports on itself: text streams, small
utilities, and a measurement taken with the same tool an administrator would
type by hand.

**PowerShell** — a Windows administrator. Object pipelines rather than text
streams, and the only one of the two that can reach the Windows volume API
directly.

Neither is the primary. The point of the pair is that **an operator on
either platform reads the same manual and runs the same mental model**.

---

## The parity risk, and how it is managed

Writing the contract twice is how module 5 shipped with the JSON keys
disagreeing between its implementations. Module 1 avoids that by deriving
the second implementation from the **observed behaviour of the first**: the
Bash suite ran, its outputs were recorded, and the PowerShell suite was
written to assert the same things against the same expectations.

That is why the two suites exist at all, and why neither is optional. A
test that only one implementation runs is a test that proves nothing about
parity.

---

## Where to go next

* [13. Disk Usage Monitor — Overview & Specs](13-Disk-Monitor-Overview.md)
* [15. Scenarios & Interactive Labs](15-Disk-Monitor-Scenarios-and-Labs.md)
* [06. Log Cleanup — Bash vs PowerShell](06-Log-Cleanup-Bash-vs-PowerShell.md)
* [09. Code Style & Engineering Standards](09-Code-Style-and-Standards.md)
