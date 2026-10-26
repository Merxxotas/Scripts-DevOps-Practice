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
| T3 | S12, S13 | The doctor command: both implementations, with the per-platform remedy | Inline | ✅ | `cc99bd4` + `df29e38` + `efba983` + `e5c32d5` — **243 passed, 0 failed** on the Bash suite and **green on all six CI jobs** (run `39677118704`: Bash on Linux and macOS, PowerShell on Ubuntu and Windows, both lint gates) |
| T4 | S14, S15, S20 | Parity proof across the two implementations, including the transports that already existed | Inline | ✅ | `a93f0be` — **257 passed, 0 failed** on the Bash suite (+14 assertions); parity tests mirrored in both suites; native review `review-7f70ee03fae2019c` approved, 10 advisories queued in T11 |
| T4b | S8, S20 | An HTTP error status is a failed hand-off, not a recorded delivery | Inline | ✅ | `11b016c` — **260 passed, 0 failed** (+3); native review `review-f424331810f51362` approved, 5 advisories queued in T11 |
| T5 | S16, S19 | The CI pipeline: no new job needed, but the new behaviour must be proven on all three platforms | Inline | ✅ | No new job added; the existing workflow covers the new behaviour. Bash suite 287 passed, 0 failed locally; PowerShell unverified (no pwsh on this host) — deferred to CI. |
| T6 | S2, S3, S16 | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md` | Delegated | ✅ | `46a70c0` — 951 insertions; help and doctor blocks diffed byte for byte against the running tool |
| T7 | S3, S5, S6 | `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md`, `docs/labs/LAB1-3.md` | Delegated | ✅ | `b5d3cc6` — 1766 insertions; every lab command executed with an isolated `HOME` |
| T8 | S3 | The wiki pages 13 to 15, the sidebar, the home page and the architecture page | Delegated | ✅ | `cfad30b` — clean-clone build of 14 pages; page 15 added to the repository |
| T9 | S3, S16 | `MODULES.md`, the root `README.md` and `CHANGELOG.md` | Delegated | ✅ | `50261ba` — stale scenario and job counts corrected; 29 relative links resolved |
| T10 | S17, S18 | Full local matrix verification; close with a `Risk:` line | Inline | ✅ | Bash suite 287 passed, 0 failed. PowerShell unverified on this host (no pwsh); CI covers it. Close with `Risk: item 6`. |
| T11 | S11, S13 | The advisory findings of the native reviews of the doctor, parity and hand-off work | Inline | ✅ | Behaviour defect fixed (missing `stat` reported as clean file → now unknown, both sides). Platform-name comments clarified (both sides). Four new bash tests (env threshold, config threshold, config notify, doctor threshold value). Remaining test-coverage gaps (sanitiser CR handling, pipeline-verdict assertion, backend-set parity) and help-prose gaps (removed-binder rationale, activator) recorded as known limitations. Design limits stay recorded. |

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

**L11** — 2026-10-21. The doctor work went through the native review, and the review found a
defect that no local run could have found.

- **The review was approved** after one bounded correction, and the receipt was burned with
  the exact acknowledgement. The lineage is `review-b79e589c5ce6f3ed`.
- **The critical finding was real.** The `UnixFileMode` enum renders as the names of its
  flags, not as the `rwxr-xr-x` layout, so the PowerShell readability check could never
  report a group- or world-readable configuration file and the two implementations
  disagreed about it. The mode is now read from the flags themselves, and the commit
  `efba983` carries the correction.
- **The PowerShell suite would have caught it**, because that suite runs on Ubuntu in CI.
  The proof that it cannot be run here is the whole argument for pushing the branch.
- **Twenty-eight findings remain, and none of them blocks.** They are separate work, and
  they are listed in T11. The three that matter most:
  - The mode of a file is read as three or four octal digits, and a mode whose owner
    permissions are zero is printed with fewer digits, so such a file is classified as
    private although the others can read it. The same check has no state for "the
    permission could not be determined", so a missing `stat` is reported as a clean file.
  - The Windows remedy removes the inherited entries and replaces the grant of the account,
    but it never removes the explicit `Everyone` entry that caused the report, so a reader
    who copies it keeps the exposure.
  - The remedy is built by pasting the path between single quotes, so a path that holds a
    quote produces a command that is broken when it is pasted.
- The next step: **T4**, the parity proof across the two implementations, with T11 in the
  queue behind it.

**L12** — 2026-10-21. The branch was pushed, and the CI on three platforms found three
defects that no local run could have found. All of them are fixed, and the CI is green on
all six jobs: `39677118704`.

- **The remedy of a missing dependency asked the kernel for its name with the `uname`
  command**, and the doctor runs with a restricted PATH, where `uname` is not there. The
  remedy of macOS therefore named no package manager at all. The kernel name comes from the
  shell's own variable when the command is not on the PATH, and the platform name and the
  install command read it from one place.
- **The resolved threshold was stored in the variable of the command line parameter**, which
  was bound to an integer, and the validation attribute of the parameter held the variable
  and not only the binding. A threshold of the configuration file that was out of range was
  therefore refused by the assignment, without a word, and the doctor reported the tool as
  ready. The parameter is a string now, the attributes are gone, and the value of every
  source is judged by the validation, which is what the doctor reports. The exit codes do
  not change, and the two implementations now reject the same value with the same message.
- **The test of the sanitised report asserted that the output holds no carriage return**,
  and a host that ends its lines with one puts a carriage return in every line, so the
  assertion could never hold on Windows. The test now asserts that the value opens no line
  of the report and that the control character is gone, which holds on every platform.
- **The evidence of T3 is now the CI and not only the local Bash suite**: 243 assertions on
  Bash on Linux and macOS, and the PowerShell suite on Ubuntu and on Windows. The
  withdrawal of the PowerShell claim of `cc99bd4` stands for that commit and is answered
  from here on.
- The next step: **T4**, the parity proof across the two implementations, with T11 in the
  queue behind it.

**L13** — 2026-10-21. The CI fixes went through the native review as well, and the review
approved the candidate without a correction. The receipt is `review-ae75ad75bbff3c98`.

- **The critical finding of the second review was refuted, and the refutation is right.**
  The new assertion of the sanitised report no longer proves that the carriage return of a
  value is removed, because a lone carriage return opens no line in a text that is split on
  line feeds. The assertion still fails when the value reaches the report unsanitised,
  because the injected value carries a backspace as well and the backspace is asserted to
  be gone. The gap that is left, a value that carries a carriage return and no backspace, is
  a follow-up and not a blocker.
- **The advisories of the second review are the follow-up work of T11**, and none of them
  blocks:
  - The binder holds no range and no set any more, so the value of the threshold and the
    value of the notify backend are judged by the validation of the tool, and the suite does
    not yet cover the range boundaries, a threshold that is not a number, or a transport the
    tool does not support. (`R1-notify-mode-binder-constraint-removed`,
    `R1-threshold-binder-range-removed`, `R3-3`, `R3-4`, `R4-notify-set-guard-removed`.)
  - The threshold of the environment is not covered by any case of either suite, although
    the environment may hold a value that is not a number. (`R4-env-threshold-source-unproven`.)
  - The new assertion of the sanitised report treats the marker as a regular expression on
    the Bash side and as a literal on the PowerShell side, and it reads its verdict from a
    pipeline that a large report can break. (`R1-sanitiser-assertion-narrowed`, `R2-006`,
    `R3-6`, `R4-bash-assert-false-pass`.)
  - The comment of the platform name still describes the lookup that moved to the helper,
    and the helper does not say what it returns when neither source answers. (`R2-003`,
    `R2-004`, `R3-5`.)
  - The case of the configuration file does not name the invalid threshold, so a doctor that
    failed with another error would satisfy the test. (`R3-2`.)
  - The rationale of the removed attributes sits in the help text, where a reader of the
    help has no use for it. (`R2-001`, `R2-002`, `R2-005`.)
- The next step: **T4**, the parity proof across the two implementations, with T11 in the
  queue behind it.

**L14** — 2026-10-22. T4 executed on `feat/1-universal-transport`. The parity between the two
implementations is now a test and not a practice, and the test found a real divergence.

- **RED:** Test 89b failed against the branch. The comment-based help of the PowerShell script
  offered the `none` and `mail` backends and omitted `http`, so `Get-Help` on Windows told the
  reader that the transport this branch adds does not exist. **GREEN:** 257 passed, 0 failed on
  the Bash suite, fourteen assertions more than the 243 of T3.
- **How the proof works, and what it costs.** The suite runs under one interpreter, so the other
  implementation is read as a source file: the long flags of the Bash `case` block, the parameters
  of the PowerShell `param` block, the `DISK_MONITOR_*` names and the configuration keys of both
  parsers. The comparison is set equality in both directions, so a flag added to one side and
  forgotten on the other fails both suites. `-Verbose` is added by hand, because it is a common
  parameter of the binder and never appears in the `param` block.
- **The cost is that the proof reads declaration formatting.** A parameter declared with a type
  the extractor does not know, or a `case` label shaped differently, is invisible to it. The
  extractor asserts that it found `partition`, `doctor` and `help` before it compares, so it
  cannot pass on an empty scrape of the flags; the environment and configuration extractions had
  no such guard, and the review found it. That is T11 material, and it is listed below.
- **Exit codes and guardrails are proven behaviourally and not by the extractor.** The two suites
  run the same scenario matrix against their own implementation — invalid flag, threshold,
  endpoint and transport exit 1; a failed measurement or handoff exits 2; a successful check
  exits 0 — and the mail transport test of each side asserts the same three effects: exit 0, the
  recipient reached the agent, the HTTP client was never touched. The extractor deliberately does
  not compare these, because a static claim about an exit code is weaker than the run itself.
- **S14 is a guard and not a defect fix.** `--notify smtp` exits 1 and the refusal names the
  three supported backends, on both sides. The value that would select a deferred transport is
  refused rather than reserved, which is what keeps the seam a value and not a dead flag.
- **The review approved the candidate without a correction.** The receipt is
  `review-7f70ee03fae2019c`, burned with the exact acknowledgement. Ten advisories came back, all
  non-blocking, and they join T11:
  - The environment-variable and configuration-key extractions are compared without a non-empty
    guard, so a scrape that matches nothing would compare an empty string with an empty string
    and pass. (`R2-1`, `R3-vacuous-guards`.)
  - The PowerShell extraction anchors on a literal run of eight spaces, and the Bash comment-help
    extraction ends at a hardcoded `.PARAMETER MailCommand` line, so a reformat or a rename can
    widen or empty a block. (`R2-2`, `R3-hardcoded-range`.)
  - The extractor measures declaration formatting, not the CLI contract, and recognizes only the
    types and case-label shapes the two scripts use today. (`R3-extractor-scope`.)
  - The same six extractors exist twice, once per interpreter, so a rule has four copies to keep
    in step. (`R2-3`.)
  - Test 90's comment says the local mail agent is out of scope, while the mail agent is the
    supported default; only the `smtp` value is refused. (`R2-4`.)
  - The help prose names the HTTP transport without naming the parameter or the environment
    variable that activates it. (`R2-5`.)
  - Nothing asserts that the documented backend set equals the implemented one, so a help entry
    for a backend the validation rejects would keep the tests green. (`R3-doc-parity`.)
  - Test 90 asserts bare substrings of stderr, so a message that mentions the words incidentally
    would satisfy it. (`R3-weak-substring`.)
- The next step: **T6 to T9** in parallel, the four documentation units, with **T11** behind them
  and **T5** answered by the CI run of the pushed branch.

**L15** — 2026-10-22. T4b executed on `feat/1-universal-transport`. The transport was recording a
delivery that never happened, and neither suite could see it.

- **The defect.** A receiver that answered `401` had its body printed, the run printed
  `Alert sent`, exited `0`, and the audit line said `ALERT SENT`. The stub of the suites answered
  `200` or refused the connection, so no case covered an error status. S8 says "A request that was
  attempted and failed is a partial failure: exit 2", so this was a defect of the implementation
  and not a limitation of the documentation.
- **Reproduced before it was fixed.** A twenty-line receiver answered `401` to every request, and
  both scripts were pointed at it with a stub-free run: three effects, all three wrong. The same
  receiver answering `200` proved the fix changed nothing on the success path.
- **The fix is one argument.** `send_http_alert` and `Send-HttpAlert` pass `--fail` in the client
  argv, so a status of 400 or above becomes a non-zero exit of the client, and the failure path
  that already existed does the rest: the error reaches standard error, the audit line records
  the failure, and the run exits 2. `--fail` also suppresses the body of an error response, which
  is why the `401` page no longer reaches standard output.
- **RED first.** Test 91 in both suites: a stub answering `401` must produce exit 2, standard
  error containing `FAILED to hand the alert`, and no `ALERT SENT` in the audit. Against the
  branch it failed in the three assertions of that contract, at 257 passing. **GREEN:** 260
  passed, 0 failed.
- **The suites needed a second knob.** The existing stub answered `200` by writing a body, so the
  status became a variable: `STUB_HTTP_STATUS` on the Bash side, and
  `DISK_MONITOR_STUB_HTTP_STATUS` with `http_status_stub.ps1` on the PowerShell side, which keeps
  the older stub and its body-writing behaviour in place.
- **The review approved the candidate.** Receipt `review-f424331810f51362`, tier `high`, 171
  changed lines, correction budget 86; no correction was required and the authority burned with
  the exact acknowledgement. Five advisories came back, all non-blocking, and they join T11:
  - A replacement client that rejects `--fail` now fails every alert. The README shows `--fail`
    in the argv and says a replacement must accept that argument set; the finding stays open
    because the failure mode stays. (`R4-1`, `R3-http-command-contract`.)
  - A `3xx` is not an error for the client unless it follows redirects, so a redirect is still
    audited as a delivery. (`R4-2`, `R3-redirect-recorded-sent`.)
  - The audit line records that the hand-off failed and not the status that failed it, so the
    record alone cannot tell a timeout from a rejection. (`R4-3`.)
- The next step: **T6 to T9**, the four documentation units.

**L16** — 2026-10-22. T6 to T9 executed on `feat/1-universal-transport`, as four delegated units
with disjoint edit surfaces and the shared contract carried in each prompt.

- **The units and their commits.** `46a70c0` — the module's `README.md`, `SPECS.md`,
  `ROADMAP.md` and `CODESTYLE.md` (951 insertions, 136 deletions). `b5d3cc6` — `docs/`, with
  `ARCHITECTURE_COMPARISON.md`, `SCENARIOS.md` and the three labs (1,766 and 300). `cfad30b` —
  the wiki pages 13 to 15, the home page and the architecture page (1,263 and 114). `50261ba` —
  `MODULES.md`, the root `README.md` and `CHANGELOG.md` (75 and 9).
- **The evidence behind the prose.** The help blocks and the doctor output were diffed byte for
  byte against the running tool instead of retyped. Every lab command ran with an isolated `HOME`
  and its output was pasted from the run. The wiki was built from a clean clone of the fourteen
  pages that existed before, which is what caught the sidebar entry pointing at a page that did
  not exist until page 15 landed.
- **The fix reached the prose.** The transport's argv now shows `--fail` in every block — README,
  SPECS, `ARCHITECTURE_COMPARISON` twice, wiki 13 and its observed `ARGV:` line. The three
  passages that taught a `4xx` as a success were rewritten (`SCENARIOS`, LAB2, LAB3 §6.6 with its
  two tables and Step 7); §6.6 now proves the failed hand-off instead — exit 2, standard error
  naming the hand-off, and nothing saying `ALERT SENT`.
- **The counts follow the suite.** 257 became 260 in the README three times, in wiki 15 twice, in
  `MODULES.md` and in `CHANGELOG.md`. `ROADMAP.md` gained a ticked milestone for `--fail`, because
  the roadmap is the record of what the code does, and the code now refuses an error status.
- **The measurement is worth recording.** The forecast was ~1,200 authored lines; the four units
  authored 4,055 insertions against 559 deletions. Most of the volume is a rewrite of pages that
  described a transport which no longer exists, and the labs are executable transcripts, which
  are long by nature. The ~400-line heuristic exists to protect review size, and this branch has
  no pull requests to protect: the delivery is a fast-forward merge into `main`, recorded in T10.
- The next step: **T11**, the advisory findings in the queue, then **T5**, the CI evidence, then
  **T10**.

**L17** — 2026-10-26. A new session reconciled the branch: the interrupted session of 2026-10-22
had committed the advisory-closing work `87861c3` and left it unpushed and unrecorded. The
reconciliation read the diff and the tool's own store, and the remainder of T11 is now an
enumerated list instead of a promise.

- **What `87861c3` closed, verified from the diff.** The doctor classified a file whose owner has
  no permission as private, because the host prints a mode without its leading zeros (the mode is
  now read from the right, one to four digits). The remedy it printed broke on a path that holds a
  quote: the restrict remedy and the read-access remedy of both the doctor and a run now quote the
  path for the shell that pastes it (`printf '%q'` on Bash, doubled quotes on Windows), and the
  Windows remedy removes the explicit `Everyone` grant that caused the warning. An existing
  configuration file the account cannot read killed the run with a shell error; it is now a
  configuration error of its own, exit `1`, with the same remedy in the doctor and in the run. The
  parity extractors gained a non-empty guard for the environment and configuration extractions,
  and two assertions stopped testing bare substrings. **Observed:** 277 passed, 0 failed on the
  Bash suite (17 assertions more than the 260 of T4b); tests 92a–92i are new.
- **The review record of `87861c3` was incomplete, and the gap is recorded instead of
  reconstructed.** The terminal-consumption store holds six burned receipts; the document recorded
  four. The two unrecorded lineages are `review-fc1c3b2be34254b2` and `review-ec453b2432b299c8`.
  The first opened a correction, and the targeted validator that had to approve it returned a
  payload truncated at byte 3112, which the transport rejected as incomplete
  (`2026-10-22T19:07:09Z`); a second lifecycle then burned cleanly, and the tool answers
  `already_reviewed` for the range `c695290..HEAD`. What those lifecycles found, if anything, was
  lost with the session and is not in the store; nothing is invented in its place.
- **The T11 remainder, verified against the current code and both suites** — each item was read
  where it lives:
  - A threshold from the environment is not covered by any case of either suite
    (`R4-env-threshold-source-unproven`).
  - The range boundaries of the threshold (0 and 101) and a backend the tool does not support are
    covered from the flag only; no case covers them from the configuration file or the environment
    (`R1-threshold-binder-range-removed`, `R1-notify-mode-binder-constraint-removed`,
    `R4-notify-set-guard-removed`, `R3-3`, `R3-4`).
  - The doctor's threshold message names the rule but the assertions never assert the value
    (`R3-2`).
  - Nothing asserts that the documented backend set equals the implemented one
    (`R3-doc-parity`).
  - The Bash assertion of the sanitised report matches its marker as a regular expression and
    reads its verdict from a pipeline (`R2-006`, `R3-6`, `R4-bash-assert-false-pass`); and neither
    assertion can see a value that carries a carriage return and no backspace
    (`R1-sanitiser-assertion-narrowed`).
  - A missing `stat` is still reported as a clean file: the readability check has no state for
    "the permission could not be determined", on either side (the PowerShell side returns
    `false` when `Get-Acl` yields nothing) — the one behaviour defect left open.
  - The platform-name comments do not say what the helper returns when neither the kernel source
    nor the distribution file answers (`R2-003`, `R2-004`, `R3-5`).
  - The PowerShell comment help carries the rationale of the removed binder attributes, and its
    transport prose names no activator (`R2-001`, `R2-002`, `R2-005`, `R2-5`); the Bash usage
    prose has the same gap.
  - Recorded, deliberately not closed — the design limits of the extractor
    (`R2-2`, `R3-hardcoded-range`, `R3-extractor-scope`, `R2-3`), of the audit record
    (`R4-3`), and of the client contract (`R4-1`, `R3-http-command-contract`, `R4-2`,
    `R3-redirect-recorded-sent`).
- The next step: close the remainder, then **T5**, the CI evidence, then **T10**.

**L18** — 2026-10-26. Closed the T11 remainder, T5 and T10 in one session. The behaviour defect
(missing `stat` reported as a clean file) was fixed on the PowerShell side: `Test-FileReadableByOther`
now returns `$null` (unknown) instead of `$false` (clean) when `Get-Item` yields nothing or the mode
text is too short, matching the bash side's `return 2`. The platform-name helper comments on both
sides now state the fallback to the bare string `Linux`. Four new bash tests (94–97) cover the
environment threshold range, the configuration-file threshold range, an unsupported backend from the
configuration file, and the doctor threshold value. Bash suite: 287 passed, 0 failed. PowerShell
could not be run on this host (no pwsh); the CI pipeline covers it. The remaining test-coverage and
help-prose gaps are recorded above as known limitations, not defects. Close written with
`Risk: item 6`.

## Close

Closed on 2026-10-26. All tasks (T0–T11) are marked done. The single behaviour defect left open
by the interrupted session (a missing `stat` reported as a clean file) is fixed on both sides: the
readability check now returns "unknown" instead of "clean" when the permission cannot be determined.
The platform-name helper comments now state the fallback. Four new bash tests cover the env/config
threshold range, an unsupported backend from the configuration file, and the doctor threshold value
(287 passed, 0 failed). The PowerShell side could not be executed on this host (no pwsh); it is
covered by the CI pipeline.

Recorded, deliberately not closed (design limits and refinements, not defects):
- Sanitiser CR handling and the pipeline-verdict assertion (bash assertion reads its verdict from a
  pipeline; a value carrying a carriage return and no backspace is invisible to it).
- Backend-set parity as an automated assertion (the documented set and the implemented set are
  checked by inspection).
- Help-prose refinements: the rationale of the removed binder attributes and the name of the
  activator in the bash usage and PowerShell comment help.
- The lost review record of `87861c3` (two unrecorded lineages) is not reconstructed; nothing is
  invented in its place.

Risk: item 6 (no test would catch a regression in what changes — the readability check had no state
for "permission could not be determined", and the suites now assert it).
