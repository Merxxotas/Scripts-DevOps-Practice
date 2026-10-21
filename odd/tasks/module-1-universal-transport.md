# Module 1 — Universal Notification Transport

**Objective:** Give module 1 a transport and a configuration model that work on any Linux
distribution or version, and on Windows, using only free tooling — so the pattern can be inherited
by the seven remaining seed modules instead of being retrofitted into each of them.
**Branch:** `feat/1-universal-transport`
**Delivery strategy:** `ask-on-risk` (default) — re-evaluate when the running authored-change count
crosses ~400 lines.
**Test runner:** `bash` (tests/test_disk_monitor.sh) · `pwsh` (tests/test_disk_monitor.ps1) ·
`shellcheck -x` · `PSScriptAnalyzer`.

> **Read this document until `## Log` before editing.** It is the specification for this work.
> Report which `S#` each task covers.

---

## Specs

Numbered requirements, quoted verbatim from their authoritative source.

### Identity, authorization and constraints

**S1** — The work generalises module 1's notification transport, quoted from the user:
> "I just want to do with tools, tech and providers that are free to use"

> "I think than more that a specific vps, project should be universal to any vps, based on linux or
> windows, and despite the distro or version (Linux and Windows). IDK what do you think, is doable do
> that, is a huge work?"

**S2** — Everything must be free to use. No paid service, no paid tier, and no provider that
requires a paid plan to function. A free tier that exists but is not guaranteed to remain free is
acceptable; a paid requirement is not.

**S3** — The result must work on any VPS, on Linux and on Windows, regardless of the distribution
or the version. The module must not depend on a distribution package manager, on a specific release,
or on a tool that is absent by default.

**S4** — The transport set is fixed, chosen by the user:
> "HTTP transport + config file + doctor (Recommended)"

### The HTTP transport

**S5** — One HTTP transport covers every HTTP notification service, because ntfy, Telegram, Discord,
Slack and a self-hosted receiver are all the same primitive: a request with a body to a URL. The
transport must therefore not carry provider-specific code.

**S6** — The transport's contract:

| Setting | Flag | Environment | Config key | Default |
| :-- | :-- | :-- | :-- | :-- |
| The endpoint | `--url <url>` | `DISK_MONITOR_URL` | `url` | none — required |
| The request body | `--body-template <text>` | `DISK_MONITOR_BODY_TEMPLATE` | `body_template` | the plain-text message |
| Extra headers | `--header 'Name: value'` | `DISK_MONITOR_HEADER` | `header` | none |
| The method | — | — | `method` | `POST` |
| The timeout in seconds | `--timeout <seconds>` | `DISK_MONITOR_TIMEOUT` | `timeout` | `10` |

The body template supports the placeholders `{subject}`, `{body}`, `{partition}`, `{usage}`,
`{threshold}`, `{recipient}`, `{host}` and `{timestamp}`. A JSON template therefore lets the same
transport speak to Telegram, Discord and Slack without provider-specific code.

The transport invokes an external HTTP client as a command, so the same client is used on every
platform and the test suite can replace it on `PATH`. The resolution order is
`--http-command` → `DISK_MONITOR_HTTP_COMMAND` → `curl`. On Windows the resolution must reach the
real `curl.exe` and must not be captured by the legacy PowerShell `curl` alias.

**S7** — The transport never logs or reports a header value. A header may carry a bearer token, and
the audit log is a durable file.

**S8** — The exit codes extend without changing their meaning, quoted from
[`AGENTS.md` §7](../../AGENTS.md):
> "**Exit codes are a public contract:** `0` success, `1` configuration/safety violation,
> `2` partial failure. Document them in the README."

A missing endpoint, a missing HTTP client, an unreadable config file and a malformed config value
are configuration errors: exit `1`. A request that was attempted and failed is a partial failure:
exit `2`. A successful check is exit `0` whatever the transport decided.

### The configuration file

**S9** — Both implementations read the same configuration file, in a minimal `key = value` format
that needs no parser library, because a minimal Linux image has no `jq` and no `toml` library, and
Windows PowerShell has no TOML parser.

```
# .diskmonitor.conf
url = https://ntfy.sh/your-topic
partition = /
threshold = 85
body_template = {body}
header = Authorization: Bearer your-token
```

**S10** — The precedence is: **command line flag → environment variable → configuration file →
built-in default**. The configuration file path is `--config <file>` → `DISK_MONITOR_CONFIG` →
`./.diskmonitor.conf` → `~/.config/disk-monitor/config`.

**S11** — A configuration file may hold a secret, in a header. It must therefore be treated as
sensitive: the repository ignores it, the doctor reports a file that is readable by others, and
nothing ever copies its contents into a log.

### The doctor command

**S12** — `--doctor` reports what is configured and what is missing, and changes nothing. It must
not measure the disk and must not send anything.

The report covers: the resolved configuration and where each value came from, whether the
measurement command is resolvable, whether the transport client is resolvable, and whether the
recipient or endpoint is set. It exits `0` when the tool is ready to run and `1` when something is
missing, with a one-line remedy for each thing that is missing.

**S13** — The doctor names the remedy per platform, because that is the whole point of it: the
missing dependency is reported with the install command for the platform it was found on, not a
generic suggestion.

### Scope

**S14** — Out of scope, and deliberately so: an SMTP transport and a local mail agent transport.
The first needs an account and a domain, the second is absent on Windows. Both are deferred until
a real requirement appears, and the seam stays open for them.

**S15** — The existing `mail` transport keeps working. This work adds to the transport set; it
removes nothing. Every deployment that works today keeps working.

**S16** — The pattern established here is the template for modules 3, 4, 6, 7, 8, 9 and 10. The
specification must be written so that it can be lifted, not rewritten.

### Constraints carried over from module 1

**S17** — The test-first policy applies, quoted from [`odd/METHODOLOGY.md`](METHODOLOGY.md) §2.5:
> "Observe RED before implementing, implement GREEN, then refactor while tests stay green."

**S18** — Tests remain deterministic, quoted from [`AGENTS.md` §6](../../AGENTS.md):
> "Every test must be **deterministic**: pin timestamps, isolate the filesystem under a temp dir,
> never depend on the host's real services, disk layout, or locale, and clean up after themselves."

**S19** — The PowerShell traps that cost module 1 three defects are constraints on this work, not
lessons to be rediscovered:
> "Variable names are case-insensitive, so a local that differs from a parameter only in case is the
> same variable, and a script-scoped variable whose name differs from an automatic variable only in
> case still shadows it."

No local may share a name with a parameter or an automatic variable, and the harness state must not
be named `$LASTEXITCODE`.

**S20** — The module contract still holds, quoted from [`AGENTS.md` §3](../../AGENTS.md):
> "**Parity across platforms.** Bash and PowerShell must implement the **same flags, defaults, exit
> codes and safety guardrails**. A flag on only one side is a defect."

---

## Environment Setup

| Tool | This machine | Consequence |
| :-- | :-- | :-- |
| `bash` | 5.3.20, present | Bash suite runs locally |
| `curl` | present | The HTTP client resolves locally |
| `shellcheck` | **not installed** | The Bash lint gate is CI-only |
| `pwsh` | **not installed** | The PowerShell suite is a CI-only gate |

The PowerShell suite runs in CI on `windows-2022` and on `ubuntu-24.04`, which is what makes the
Windows behaviour of the HTTP transport provable rather than asserted.

---

## Tasks

| ID | Specs | Task | Route | Status | Evidence |
| :--- | :--- | :-- | :-- | :-- | :-- |
| T0 | S1, S4 | Create the branch; record the module 1 baseline | Inline | ✅ | `feat/1-universal-transport`, baseline 55 passed, 0 failed |
| T1 | S9, S10, S11 | The configuration file: parser, precedence, secret handling, both implementations | Inline | ✅ | `a3cea7a` + three fixes — **77 passed, 0 failed** on all four suite jobs in run `39646002248` |
| T2 | S5, S6, S7, S8 | The HTTP transport: both implementations, with a stub client on `PATH` | Inline | ✅ | `fd12e3e` + `aae787e` — **171 passed, 0 failed** on all four suite jobs in run `39654069737` |
| T3 | S12, S13 | The doctor command: both implementations, with the per-platform remedy | Inline | ✅ | `cc99bd4` + `df29e38` — **240 passed, 0 failed** on the Bash suite; the PowerShell suite is a CI-only gate on this host and stays unproven until the branch runs in CI |
| T4 | S14, S15, S20 | Parity proof across the two implementations, including the transports that already existed | Inline | ⬜ | — |
| T5 | S16, S19 | The CI pipeline: no new job needed, but the new behaviour must be proven on all three platforms | Inline | ⬜ | — |
| T6 | S2, S3, S16 | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md` | Delegated | ⬜ | — |
| T7 | S3, S5, S6 | `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md`, `docs/labs/LAB1-3.md` | Delegated | ⬜ | — |
| T8 | S3 | The wiki pages 13 to 15, the sidebar, the home page and the architecture page | Delegated | ⬜ | — |
| T9 | S3, S16 | `MODULES.md`, the root `README.md` and `CHANGELOG.md` | Delegated | ⬜ | — |
| T10 | S17, S18 | Full local matrix verification; close with a `Risk:` line | Inline | ⬜ | — |

> Task IDs are stable; the table is ordered by execution sequence.

### Route declaration and trigger evidence

**T1 to T5 are inline and sequential.** The PowerShell side mirrors the Bash side's observed
behaviour, exactly as in module 1, and T4 proves the mirror. The parallel trigger needs independent
units; these are not independent, and module 1 already paid for assuming they were.

**T6 to T9 are delegated, in parallel.** They are four independent units of documentation with
disjoint edit surfaces, each substantial enough to need more than a couple of minutes, and none
depends on another's output. The shared contract travels in the prompt, because units built in
parallel cannot see each other.

### Forecast

~1,200 authored changed lines, against module 1's 5,854. The code is the smaller half: the
documentation was roughly 60 % of module 1's volume and will be again.

---

## Log

**L1** — 2026-10-21. User request, verbatim:
> "I just want to do with tools, tech and providers that are free to use"

> "I think than more that a specific vps, project should be universal to any vps, based on linux or
> windows, and despite the distro or version (Linux and Windows). IDK what do you think, is doable do
> that, is a huge work?"

**L2** — 2026-10-21. The scoping question was put to the user as a single choice, and the answer
fixed the transport set:
> "HTTP transport + config file + doctor (Recommended)"

**L3** — 2026-10-21. The reason the set is this shape. There is no universal free email primitive:
a local mail agent exists on Linux and not on Windows, and self-hosting a mail server is blocked
by Oracle's outbound port 25 policy. HTTP is the universal primitive — ntfy, Telegram, Discord,
Slack and a self-hosted receiver are all the same request with a body to a URL — and `curl` ships
on every Linux distribution and on Windows 10 and later, so the transport needs no installation
anywhere. One implementation covers every provider, which is what makes "any provider" affordable
rather than a per-provider code path.

**L4** — 2026-10-21. The reason the timing is the decision. Module 1 is the only module that
exists. Generalising now means the seven remaining seed modules inherit the transport, the
configuration file and the documentation for free. Generalising later means each of them ships with
the local-mail-agent limitation and the retrofit is paid seven times, on code that has already
merged.

**L5** — 2026-10-21. Next step: **T0**.

**L6** — 2026-10-21. T0 and T1 executed on `feat/1-universal-transport`. The configuration file
lands with the precedence it participates in: a flag, then an environment variable, then the file,
then the built-in default, and every setting records where its value came from.

- **RED:** 61 passed, 16 failed against module 1, because `--config` did not exist. **GREEN:** 77
  passed, 0 failed, on all four suite jobs — Bash on Linux and macOS, PowerShell on Ubuntu and
  Windows — in run `39646002248`.
- **The binder knows which parameters were supplied, and it had to be captured in the script
  scope.** Inside a function `$PSBoundParameters` describes the function's own parameters, so the
  flags would have been silently ignored and only the environment variables would have worked.
- **A configuration file can supply a value the binder never saw**, so the threshold and the notify
  backend are validated again after the resolution, on both sides.
- **Four defects were found by the CI runs, none of them locally.** The new PowerShell tests called
  the environment helpers by names the file did not define. The measurement command default was the
  same on every platform, so Windows looked for `df` and failed. The default partition became the
  filesystem root on every platform, so Windows looked for a path that does not exist there and fell
  through to the volume API with the wrong device. The analyzer returns a single object when it
  finds a single issue, and adding a single object to an array fails.
- **The shell linter rejected the recorded sources as unused.** They are now reported by the
  verbose output, which is what the diagnostic flag is for and what the doctor will reuse.
- The HTTP settings are not parsed yet, on either implementation, because the transport that reads
  them is T2. The two sides stay in parity.

**L7** — 2026-10-21. Next step: **T2**. The HTTP transport: one implementation that covers every
HTTP notification service, with a stub client on `PATH` so the suite is deterministic on every
platform.

**L8** — 2026-10-21. T2 executed on `feat/1-universal-transport`. The HTTP transport lands on both
implementations. One request with a body to a URL is the same primitive for ntfy, Telegram,
Discord, Slack and a self-hosted receiver, so the transport carries no provider-specific code.

- **RED:** 96 passed, 51 failed against module 1, because `--notify http` did not exist.
  **GREEN:** 171 passed, 0 failed, on all four suite jobs — Bash on Linux and macOS, PowerShell
  on Ubuntu and Windows — in run `39654069737`. Both lint gates are green in the same run.
- **The client is an external command**, resolved as `--http-command` →
  `DISK_MONITOR_HTTP_COMMAND` → `curl`, so the same client is used on every platform and the
  suite can replace it on `PATH`. The PowerShell resolution asks for an *application*, so the
  legacy `curl` alias can never be captured and the real `curl.exe` is reached. The Windows
  runner proved it: the report names a file on disk, not an alias.
- **The body template is rendered in one pass**, so a substituted value is never substituted
  twice and a JSON template keeps its braces. `{usage}` and `{threshold}` carry the percent sign
  and `{recipient}` is the endpoint the alert is addressed to.
- **A header value never reaches an output.** It is not printed, not reported as an error and
  not written to the audit log; the transport reports the header *count* and its source instead.
  The independent verification traced every path that could leak one, on both sides.
- **Five defects came out of the CI runs and the verification, none of them locally.** The
  analyzer rejects a plural noun in a cmdlet name, so four test functions were renamed. The
  partition placeholder assertion assumed the root of the filesystem, and the default partition
  is the system drive on Windows: only the Windows runner saw it. An empty `--header` was
  demoted to the next precedence source on the Bash side while the PowerShell side honoured the
  flag, so the same command line sent two different requests. A malformed configuration line was
  echoed to the error stream, and a line pasted into the file by mistake may hold a bearer token:
  the line is now named by its number. The shared resolver read a value holding only whitespace
  as a value on one side and as an absence on the other.
- **One finding is recorded and deliberately not changed.** The header value is visible in the
  process argument list while the request runs, because that is how every HTTP client takes a
  header. The alternative writes the token to a file, which is worse. It is documented in the
  README (T6) instead of hidden.
- The verification also reported that the audit log only honours the `-LogFile` parameter on the
  PowerShell side. That is not a defect: the parameter lives in the script scope, so
  `$script:LogFile` and `$LogFile` are the same variable.
- The next step: **T3**, the doctor command: what is configured, what is missing, and the
  install command for the platform it was found on.

**L9** — 2026-10-21. Next step: **T3**. The doctor command: it reports what is configured and
where each value came from, what is missing, and the install command for the platform it was
found on, and it changes nothing.

**L10** — 2026-10-21. T3 executed on `feat/1-universal-transport`, in two commits and two
sessions. The first session shipped the doctor and stopped in the middle of a hardening pass:
the Bash side carried the new behaviour and the PowerShell side carried the helpers and never
called them, so the two implementations did not agree. The second session finished it.

- **RED:** 233 passed, 7 failed against `cc99bd4`, because the doctor reported none of the new
  behaviour. **GREEN:** 240 passed, 0 failed, on the Bash suite.
- **The report of a configuration file that other users can read is a warning and not a
  problem.** S12 ties the exit code `1` to something missing, and a new file is readable by
  others until it is restricted, so a doctor that answered "not ready" for a working setup
  would teach the reader to ignore the exit code. The warning carries the remedy.
- **The permission model of Windows is an access control list, and only the `Everyone`
  principal is reported there.** The built-in Users group holds read access on every file of a
  user profile, so reporting it would report every file of the platform.
- **A value that does not fit in an integer is judged by its digits and not by a comparison.**
  A 64-bit comparison wraps 2^64 + 1 to 1, and the threshold 1 was accepted as valid. The
  PowerShell side died on a conversion error with the same value. A timeout that does not fit
  in an integer is a malformed value and is rejected as one, which is what S8 asks for.
- **A measurement command that the configuration file names comes from no package**, so the
  remedy points at the setting and not at an install command.
- **The values and the problems of the report are stripped of the control characters**, so a
  value cannot rewrite the report.
- **The mode of a file is read from the group and the others and not from the owner**: a file
  restricted to its owner was reported as readable by others. The new test caught it.
- **The PowerShell side is unproven on this host.** The suite is a CI-only gate here, and the
  branch was never pushed, so the assertions of the PowerShell suite have not run. The commit
  message of `cc99bd4` claimed a PowerShell result that was never observed; that claim is
  withdrawn, and the evidence of this task is the Bash suite alone.
- The next step: **T4**, the parity proof across the two implementations.

---

## Close

Pending. Written at the end of the work, with the delivery record and the observed evidence.
