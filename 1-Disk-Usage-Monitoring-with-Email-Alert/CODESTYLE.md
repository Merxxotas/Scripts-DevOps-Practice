# Disk Usage Monitor — Code Style & Best Practices

This document establishes the coding standards, design patterns and engineering conventions for
the Disk Usage Monitor. All contributions must adhere to these rules to keep the two
implementations identical in behaviour and safe to run unattended.

---

## 1. Language & Global Conventions

- **English Only:** All code, identifiers, comments, log messages, documentation and commit
  messages must be written in English.
- **B2 Level English:** Keep the language clear, simple and direct. The audience is a distributed
  engineering team reading a monitor's output at 03:00.
- **Line length:** keep source lines under **100 characters**. The named exception is a line
  whose length is fixed by the message contract rather than by the formatting — the
  ANSI-coloured report strings and the audit message templates. Split those only by extracting
  the message into a variable, never by truncating the message.
- **Parity is a review gate:** the Bash and the PowerShell implementation must expose the same
  flags, the same defaults, the same validation, the same exit codes and the same messages. A
  change to one side is a change to both, in the same commit.
- **Branching & PR workflow:**
  - Direct commits to `main` are prohibited.
  - Work is performed on dedicated branches: `feat/<n>-<slug>`, `fix/<slug>`, `docs/<slug>`,
    `ci/<slug>`.
  - Merges into `main` require passing the module's CI pipeline.

---

## 2. Bash Coding Standards (`disk_monitor.sh`)

- **Strict mode:** `set -euo pipefail` and `IFS=$'\n\t'` are the first two statements after the
  shebang, without exception. `IFS` is restricted so that a path containing a space is never
  split into words.
- **Naming conventions:**
  - Functions: `snake_case` with a verb prefix (`get_disk_usage`, `resolve_mail_command`,
    `validate_configuration`).
  - Function-local variables: `snake_case`, declared with `local` **before** they are used.
  - Module-level configuration: `UPPER_SNAKE_CASE` (`PARTITION`, `THRESHOLD`, `LOG_FILE`).
  - Constants: `readonly` (`COLOR_RED`, `COLOR_RESET`).
- **Quoting:** quote every expansion — `"$PARTITION"`, "$MAIL_COMMAND"`. An unquoted expansion
  is a defect, because every value in this module can come from the outside world.
- **`printf`, not `echo`:** the report and the audit line are written with `printf` and an
  explicit format string, so a value containing `%` or a backslash cannot corrupt the output.
  `echo` appears only as a last-resort fallback for a value that has no better source.
- **Portable utilities only:** `df -P`, never `df -h`. The human-readable format is not
  guaranteed to be stable across GNU and macOS.
- **Explicit failure:** a function that can fail returns a non-zero status and lets the caller
  decide. The caller decides, because the exit code is a public contract.
- **Static analysis:** the script and the suite pass `shellcheck -x` with zero findings.

### The `local` discipline

Every variable that belongs to a function is declared with `local` inside that function. Two
reasons, both of them contractual:

1. A function must not be able to overwrite a module-level variable by accident.
2. Two functions that both declare `local capacity` cannot collide.

```bash
get_disk_usage() {
    local output
    local capacity

    if [[ -n "$USAGE_OVERRIDE" ]]; then
        printf '%s' "$USAGE_OVERRIDE"
        return 0
    fi

    if ! output="$("$USAGE_COMMAND_OVERRIDE" -P "$PARTITION" 2>/dev/null)"; then
        return 1
    fi
    ...
}
```

---

## 3. PowerShell Coding Standards (`disk_monitor.ps1`)

- **Version gate:** `#Requires -Version 7.0` is the first line. `Get-WmiObject` was removed in
  PowerShell 7 and `Send-MailMessage` is deprecated, so the version is a contract, not a
  suggestion.
- **Script shape:** `[CmdletBinding()]` plus a strongly typed `param()` block, with
  `[ValidateRange]` and `[ValidateSet]` carrying the validation that the Bash side performs at
  run time.
- **Strict mode:** `Set-StrictMode -Version Latest` and an explicit `$ErrorActionPreference`.
  A typo in a variable name must fail loudly.
- **Approved verbs:** every function uses an approved verb and a **singular** noun —
  `Show-Help`, `Write-AuditLog`, `Write-ErrorLine`, `Read-PosixUsage`, `Get-DiskUsagePercent`,
  `Get-WindowsVolumeUsage`, `Resolve-MailCommand`, `Send-Alert`, `Invoke-DiskMonitor`.
- **Shared state lives in the script scope:** counters, captured output and the verbose flag
  are `$script:` variables. A `$global:` variable is a cross-script side effect and is not
  allowed.
  - The **one documented exception** is `$global:LASTEXITCODE = 0`. `$LASTEXITCODE` is an
    automatic variable that PowerShell creates in the global scope, so the strict mode would
    trip over it before the first external call unless it is initialised there.
- **The common parameters are captured once, in the script scope.** Inside a function
  `$PSBoundParameters` describes the function's own parameters, not the script's, so `-Verbose`
  would never be visible there.
- **Errors go to the error stream, not into the pipeline:** configuration errors are written
  with `[Console]::Error.WriteLine` through a single helper. `Write-Error` is not used, because
  it would turn a configuration error into a terminating error in the caller's session.

```powershell
$script:VerboseEnabled = $PSBoundParameters.ContainsKey('Verbose') -and $Verbose

function Write-ErrorLine {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
}
```

- **Error handling:** `try { ... } catch { ... }` around every I/O operation and every call to
  an external program. `-ErrorAction SilentlyContinue` is used only where the failure is
  deliberate and is reported elsewhere.
- **Static analysis:** the script and the suite pass `PSScriptAnalyzer` with the module's
  `PSScriptAnalyzerSettings.psd1`.

---

## 4. Observability & the Exit-Code Contract

- **Exit codes are a public contract:**
  - `0` — the check ran; the alert was delivered, not needed, or deliberately suppressed.
  - `1` — configuration or safety violation.
  - `2` — partial failure: the usage could not be read, or the alert could not be handed to
    the mail agent.
  - Every termination path uses one of those three codes. There is no fourth code.
- **The help text documents the exit codes.** A user who reads `-h` must not have to open this
  document to learn what a non-zero exit means.
- **Structured logging, not ad-hoc printing:** every audit line goes through the single writer
  — `log_message` in Bash, `Write-AuditLog` in PowerShell — in the format
  `YYYY-MM-DDTHH:MM:SSZ [LEVEL] Message`. The report itself has a fixed field layout, so a
  reader can parse it. There is no free-form printing anywhere else in the module.
- **One audit line per run.** A run either appends exactly one line or exits before the audit
  path is known — an unknown flag leaves no trace, because the parser rejects it first.
- **A fired alert is `INFO`, not `ERROR`.** The disk being full is not the tool's fault.

---

## 5. Secrets & Credentials

- **Never hardcode a secret.** The module holds no credential, reads no credential file and
  logs no credential. The alert recipient is an address, not a secret.
- **Read the configuration from the environment** and fail loudly when it is unset:
  `DISK_MONITOR_TO`, `DISK_MONITOR_MAIL_COMMAND`, `DISK_MONITOR_USAGE_COMMAND`,
  `DISK_MONITOR_USAGE_OVERRIDE`.
- **The relay credential belongs to the mail agent.** It lives in the mail agent's own
  configuration, with restrictive permissions, outside this repository. It must never appear in
  a file, a command line, a log or a commit in this repository.
- **Never log the body of an alert.** The audit line records the partition, the percentage, the
  source, the threshold and the recipient — the minimum that proves the run happened.

---

## 6. Commenting Strategy

- **Explain the "Why", not the "What":** the code is self-documenting. A comment earns its
  place only when it explains a non-obvious decision, an operating-system quirk, a platform
  workaround or a contract that is not visible in the code.
- **Zero dead code:** no commented-out blocks, no orphaned debugging lines, no `TODO` without a
  linked issue.
- **Header documentation:** each script starts with a synopsis of its purpose, its parameters
  and its example invocations.
- **Comments are English, in the same register as the rest of the module.** No jargon, no
  exclamation marks, no references to the author or the tooling that produced the file.

```bash
# Reads the usage percentage of the watched partition as an integer.
# The POSIX output format is used because it is the only one whose column
# layout is identical on GNU and macOS. The capacity is read from the fifth
# field, which is its fixed position in that layout, so a mount point
# containing spaces cannot shift it.
```

---

## 7. Examples of Production Standards

### Good Bash style example

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

PARTITION="/"
THRESHOLD=80

# Resolves the mail agent that receives the alert. The contract is:
#   <mail-command> -s <subject> <recipient>   with the body on stdin.
resolve_mail_command() {
    local candidate

    if [[ -n "$MAIL_COMMAND_OVERRIDE" ]]; then
        if command -v "$MAIL_COMMAND_OVERRIDE" >/dev/null 2>&1; then
            printf '%s' "$MAIL_COMMAND_OVERRIDE"
            return 0
        fi
        return 1
    fi

    for candidate in mail msmtp; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    return 1
}
```

### Good PowerShell style example

```powershell
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Threshold = 80,

    [Parameter(Mandatory = $false)]
    [ValidateSet("none", "mail")]
    [string]$Notify = "mail",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# The verbose flag is a common parameter, so it is captured here in the script
# scope. Inside a function $PSBoundParameters would describe the function's
# own parameters, not the script's, and the flag would never be seen.
$script:VerboseEnabled = $PSBoundParameters.ContainsKey('Verbose') -and $Verbose

# Writes a message to the error stream without touching the error pipeline
function Write-ErrorLine {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
}
```

---

## 8. Related Documents

- The contract these rules serve: [`SPECS.md`](SPECS.md)
- The milestones: [`ROADMAP.md`](ROADMAP.md)
- Usage and troubleshooting: [`README.md`](README.md)
- Repository standards: [`../AGENTS.md`](../AGENTS.md),
  [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
