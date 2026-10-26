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
order, the transport hand-off and the exit-code mapping exist twice. The
benefit is that the module **has no runtime dependency beyond the platform it
already runs on**: no Python, no package manager, no container. The `http`
transport reaches the network, but through an external client that ships with
the platform, and only when that backend is chosen.

The duplication is only affordable because the contract is written down
first. The flags, the defaults, the validation rules, the exit codes, the
configuration keys and the report labels are the specification; the two
implementations are two renderings of it.

---

## Side by side

| Aspect | Bash | PowerShell |
| :--- | :--- | :--- |
| File | `disk_monitor.sh` | `disk_monitor.ps1` |
| Interpreter | `bash` 4+ | PowerShell 7+ |
| Strictness | `set -euo pipefail`, `IFS=$'\n\t'` | `Set-StrictMode -Version Latest` |
| Argument parsing | hand-written `while` loop with `case` | `param()` with typed parameters |
| Threshold validation | regex plus a manual range check | a tool-level check, after the binder |
| Notify validation | manual comparison | a tool-level check, after the binder |
| Verbose | dedicated `-v` / `--verbose` flag | the common `-Verbose` parameter |
| Help | `-h` / `--help`, a heredoc | `-Help`, a `Write-Host` block |
| Default partition | `/` | `/` off Windows, `$env:SystemDrive\` on Windows |
| Measurement (Unix) | `df -P` piped into `awk` | `df -P` output split into fields |
| Measurement (Windows) | not applicable | `Get-CimInstance Win32_LogicalDisk` |
| Capacity field | `$(NF-1)` of the POSIX line | the field before the mount point |
| Mail agent lookup | `command -v` | `Get-Command` |
| HTTP client lookup | `command -v`, or an existing file | `Get-Command -CommandType Application` |
| Configuration parsing | `while read` plus `case` | `Get-Content` plus `switch` |
| Template rendering | left-to-right scan, one pass | the same algorithm, one pass |
| Audit timestamp | `date -u +"%Y-%m-%dT%H:%M:%SZ"` | `(Get-Date).ToUniversalTime()` |
| Errors | `printf` to stderr | `[Console]::Error.WriteLine` |
| Functions | `snake_case` | Approved Verb-Noun (`Get-DiskUsagePercent`) |
| Dependency | coreutils (`df`, `awk`), a mail agent, `curl` | the OS, a mail agent, `curl` |

---

## What the shared contract guarantees

These hold on **both** sides, and each one is covered by the test suite.

* **The flag set and every default.** Partition, threshold, notify mode,
  recipient, mail command, log file, endpoint, body template, header,
  timeout, HTTP client, config file, doctor, verbose and help — the same
  names, the same defaults, the same meaning.
* **The validation rules.** The threshold is an integer in `1`–`100`. The
  notify backend is `none`, `mail` or `http`. The partition must exist. A
  missing recipient is an error when the backend is `mail` and an endpoint is
  required when it is `http`. The timeout is a whole number above zero, the
  method is a token, and every header is `Name: value`.
* **The exit codes.** `0` success, `1` configuration or safety error, `2`
  partial failure — with the same conditions mapped onto each code.
* **The comparison.** The alert fires when the usage is **strictly greater**
  than the threshold. A filesystem at exactly the threshold does not alert.
* **The order of operations.** Validate the configuration and resolve the
  transport client, *then* measure, *then* report, *then* hand the alert over.
* **The environment variable names.** All fourteen `DISK_MONITOR_*` names
  mean the same thing on both sides.
* **The configuration file.** The same thirteen keys, the same
  `key = value` syntax, and the same precedence: flag, environment, file,
  default. A malformed line and an unknown key are treated the same way.
* **The mail contract.** `<mail-command> -s <subject> <recipient>`, with the
  body on stdin, and the same candidate list — `mail`, then `msmtp`.
* **The HTTP contract.** The same request shape, the same eight placeholders,
  the same percent sign on `{usage}` and `{threshold}`, and the same
  one-pass rendering.
* **The doctor.** The same report fields, the same provenance labels, the
  same two exit codes, and the same rule that a header value is never shown.
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
./disk_monitor.sh -p /home -t 90 -n --notify none
```

PowerShell uses named parameters, and the value follows the parameter name:

```powershell
.\disk_monitor.ps1 -Partition C:\ -Threshold 90 -DryRun
```

The vocabulary is the same on both sides — `Partition`, `Threshold`,
`DryRun`, `Notify`, `To`, `MailCommand`, `LogFile`, `Config`, `Url`,
`BodyTemplate`, `Header`, `Timeout`, `HttpCommand`, `Doctor`, `Help`,
`Verbose` — so a script that drives one can be translated to the other by
changing the syntax and nothing else.

### Where the validation happens

Both sides validate a value **after** it has been resolved, in the tool, and
not in the argument parser. That is a consequence of the configuration file:
a value can arrive from a layer the binder never saw, so a range on the
parameter would either be bypassed or would refuse a value in a place the
user cannot see. The Bash side has always worked this way:

```bash
if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 ]] || [[ "$THRESHOLD" -gt 100 ]]; then
```

The PowerShell side used to delegate to the binder with a
`[ValidateRange(1, 100)]` on an `[int]`, and that attribute is gone. Both
parameters are strings now, and both sides apply the same checks to the
resolved value.

The **outcomes and the messages** are identical: a threshold outside
`1`–`100` prints the same sentence and exits `1` on either platform. The
suite asserts that.

### The HTTP client on Windows

The HTTP client is resolved as an **application**, not as a command name:

```powershell
$resolved = @(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)
```

That is the detail a naive translation misses. Windows PowerShell ships a
`curl` **alias** for `Invoke-WebRequest`, and resolving `curl` without
`-CommandType Application` returns the alias. The script would then call the
wrong tool with `curl`-shaped arguments. The application lookup skips the
alias and reaches the real `curl.exe`, which ships with Windows 10 and later.
The candidate list is `curl`, then `curl.exe`.

Bash has no such ambiguity: `command -v` returns an executable path, and a
file path is accepted as-is.

### Parsing the configuration file

Neither side uses a parser library, because the format is `key = value` and
the libraries are not guaranteed to exist.

Bash reads the file with `while IFS= read -r` and dispatches on the key with
`case`. PowerShell reads it with `Get-Content` and dispatches with `switch`.
Both trim the value, both strip a matching pair of quotes, both accumulate
`header` lines into an ordered list, and both name a malformed line by its
number instead of echoing it — because the line may hold a token.

The parity here is behavioural, not textual: the two parsers are separate
code, and the parity suite compares the *key sets*, not the parsing. The
suite also runs the same scenarios against each parser, which is what proves
that a quoted value, a comment and a malformed line behave the same way.

### Rendering the template

Both implementations substitute the eight placeholders in a single
left-to-right pass and never re-scan a substituted value. A partition named
`{usage}` therefore cannot be expanded twice, and a JSON body keeps its
braces because only known names are replaced.

This is the one place where the two implementations share an *algorithm* and
not only an outcome. Writing it twice was necessary; writing it two
different ways would have produced two different bodies for the same alert.

### Handling a secret

Both sides treat a header value as opaque. It is passed to the client, and
it is never printed, never echoed in an error and never written to the audit
log. The doctor reports a **count** and a provenance, not a value.

The remaining exposure is the same on both sides and cannot be fixed in the
script: the client receives the header as a command-line argument, so it is
visible in the process list while the request runs. That is the HTTP client's
interface, on every platform.

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

## The parity proof, and what it costs

Writing the contract twice is how module 5 shipped with the JSON keys
disagreeing between its implementations. Module 1 avoids that by deriving
the second implementation from the **observed behaviour of the first**: the
Bash suite ran, its outputs were recorded, and the PowerShell suite was
written to assert the same things against the same expectations.

That is why the two suites exist at all, and why neither is optional. A
test that only one implementation runs is a test that proves nothing about
parity.

### The suites read each other

The two suites cannot run under one interpreter, so each one reads the other
implementation **as a source file** and compares the declarations it finds.
The Bash suite extracts the long flags of the `case` block, the
`param` block parameters, the `DISK_MONITOR_*` names and the configuration
keys from both files; the PowerShell suite does the same in the other
direction. The comparison is **set equality in both directions**, so a flag
added to one side and forgotten on the other fails both suites.

Three tests carry that work:

| Test | What it asserts |
| :--- | :--- |
| 88a–88d | the extraction is not empty: `partition` and `doctor` were found on both sides |
| 88e | both implementations offer the same long flags |
| 88f | both read the same `DISK_MONITOR_*` environment variables |
| 88g | both accept the same configuration keys |
| 89a–89c | the Bash help, the PowerShell comment help and its usage text name the same backends |
| 90a–90d | `--notify smtp` exits `1` and the refusal names `none`, `mail` and `http` |

`-Verbose` is added to the PowerShell set **by hand**. It is a common
parameter of the binder and never appears in the `param` block, so no scrape
of the file can find it. That single exception is stated in the test rather
than hidden in the extractor.

Test 89 is not decoration. It is what found the defect that motivated the
suite: the PowerShell comment-based help offered `none` and `mail` and
omitted `http`, so `Get-Help` on Windows told the reader that the transport
this branch adds does not exist. Nothing behavioural failed; only a test that
compared the two help surfaces could see it.

### What it does not prove

The proof reads **declaration formatting**, not the CLI contract, and saying
otherwise would be dishonest:

* a parameter declared with a type the extractor does not know, or a `case`
  label shaped differently, is invisible to it;
* the PowerShell extraction anchors on a literal run of eight spaces, and the
  Bash comment-help extraction ends at a hardcoded `.PARAMETER MailCommand`
  line, so a reformat can widen or empty a block;
* the environment-variable and configuration-key extractions have no
  non-empty guard of their own, so a scrape that matched nothing would
  compare an empty string with an empty string and pass;
* it says nothing about runtime behaviour: not what a flag does, not what an
  exit code is, not whether a guardrail fires.

That last gap is closed **behaviourally**. Both suites run the same scenario
matrix against their own implementation — invalid flag, threshold, endpoint
and transport exit `1`; a failed measurement or hand-off exits `2`; a
successful check exits `0` — and the mail test of each side asserts the same
three effects: exit `0`, the recipient reached the agent, and the HTTP client
was never touched. A static claim about an exit code would be weaker than the
run itself, so the extractor deliberately does not make one.

### Why it is worth the cost

The proof costs six small extractors, duplicated once per interpreter, and it
has to be maintained when the declarations are reformatted. It buys the one
thing a two-runtime contract cannot otherwise have: **a defect in one side
fails a test in the other**, with no second runtime and no network.

On a host without `pwsh` — like the one this page was written on — the Bash
suite still runs, and its parity tests still read the PowerShell file. That
is what makes the proof cheap enough to keep. The PowerShell suite itself is
a CI-only gate on `windows-2022` and `ubuntu-24.04`, which is what proves
that the Windows client resolution and the Linux client resolution both
work.

---

## Where to go next

* [13. Disk Usage Monitor — Overview & Specs](13-Disk-Monitor-Overview.md)
* [15. Scenarios & Interactive Labs](15-Disk-Monitor-Scenarios-and-Labs.md)
* [06. Log Cleanup — Bash vs PowerShell](06-Log-Cleanup-Bash-vs-PowerShell.md)
* [09. Code Style & Engineering Standards](09-Code-Style-and-Standards.md)
