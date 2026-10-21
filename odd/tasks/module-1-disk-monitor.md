# Module 1 — Disk Usage Monitoring with Email Alert

**Objective:** Convert module 1 from an untracked seed script pair into a shipped module that
satisfies the repository's module contract, with a host-agnostic notification transport that hands
alerts to the host's mail agent.
**Branch:** `feat/1-disk-monitor`
**Delivery strategy:** `ask-on-risk` (default) — crossed at T1 with 754 authored changed lines in a
single work unit. Resolved to `single-pr`: one pull request at the end, carried by work-unit
commits on the feature branch, matching the repository's documented flow
([`AGENTS.md` §4](../../AGENTS.md)) and module 5's precedent. See L6.
**Test runner:** `bash` (tests/test_disk_monitor.sh) · `pwsh` (tests/test_disk_monitor.ps1) ·
`shellcheck -x` · `PSScriptAnalyzer`.

> **Read this document until `## Log` before editing.** It is the specification for this work.
> Report which `S#` each task covers.

---

## Specs

Numbered requirements, quoted verbatim from their authoritative source.

### Module identity and authorization

**S1** — The work targets module 1, `1-Disk-Usage-Monitoring-with-Email-Alert`, quoted from the
user:
> "Okay, then let's discuss about the module 1, what is this module, how can we deal with this one,
> which technologies can we use for this one?"

> "Okay, for now just do the step 0, we will discuss step 1 later"

**S2** — Writing this feature document is authorized, quoted from the user:
> "Great. So let's start with that, let's go."

### The module contract

**S3** — The module must ship the full contract, quoted from [`AGENTS.md` §3](../../AGENTS.md):
> "Every numbered module folder is self-contained and ships:
>
> ```
> <N>-<Module-Name>/
> ├── README.md              # usage, flags, scheduling examples, troubleshooting
> ├── SPECS.md               # technical specification & architecture
> ├── ROADMAP.md             # phased milestones, checkboxes = observed outcomes only
> ├── CODESTYLE.md           # module-specific coding conventions
> ├── <implementation>       # source: scripts, packages, binaries
> ├── tests/                 # automated test suites (see §6)
> └── docs/                  # ARCHITECTURE_COMPARISON.md, SCENARIOS.md, labs/LAB1-3.md
> ```"

**S4** — The two implementations must hold parity, quoted from [`AGENTS.md` §3.2](../../AGENTS.md):
> "**Parity across platforms.** Bash and PowerShell must implement the **same flags, defaults, exit
> codes and safety guardrails**. A flag on only one side is a defect."

**S5** — Because the module notifies, it ships guardrails, quoted from
[`AGENTS.md` §3.4](../../AGENTS.md):
> "**Safety first.** Anything that deletes, restarts, kills, mutates or notifies must ship
> guardrails, a dry-run mode where feasible, and a non-zero exit code on violation."

**S6** — All artifacts are English, quoted from [`AGENTS.md` §3.5](../../AGENTS.md):
> "**English only.** All code, comments, identifiers, docs and commit messages."

### The CLI contract

**S7** — The flag surface accepted on 2026-10-21. Both implementations expose the same set, with
the same defaults:

| Flag | Long form | PowerShell | Default | Meaning |
| :--- | :-- | :-- | :-- | :-- |
| `-p` | `--partition <path>` | `-Partition` | `/` (Unix) · system drive (Windows) | Mount point to watch |
| `-t` | `--threshold <percent>` | `-Threshold` | `80` | Alert when usage is **strictly greater** |
| `-n` | `--dry-run` | `-DryRun` | off | Report the alert, hand nothing to the mail agent |
| — | `--notify <none\|mail>` | `-Notify` | `mail` | `none` disables handing off entirely |
| — | `--to <address>` | `-To` | `DISK_MONITOR_TO` | Recipient of the alert |
| — | `--mail-command <cmd>` | `-MailCommand` | platform default | The mail agent to hand the alert to |
| `-l` | `--log-file <file>` | `-LogFile` | none | Append an audit line per run |
| `-v` | `--verbose` | `-Verbose` | off | Diagnostic output |
| `-h` | `--help` | `-Help` | — | Usage and examples |

Validation: `--threshold` accepts `1`–`100` only; anything else is a configuration error.
`--notify` accepts `none` or `mail` only. An unknown flag is a configuration error.

**S8** — Exit codes are a public contract, quoted from [`AGENTS.md` §7](../../AGENTS.md):
> "**Exit codes are a public contract:** `0` success, `1` configuration/safety violation,
> `2` partial failure. Document them in the README."

The precise mapping accepted on 2026-10-21:

| Code | Meaning | Condition |
| :--: | :-- | :-- |
| `0` | Success | The check ran, the threshold state was reported, and the alert was delivered, not needed, or deliberately suppressed. |
| `1` | Configuration / safety error | Unknown flag, threshold outside `1`–`100`, partition does not exist, recipient unset, or no mail agent could be resolved. |
| `2` | Partial failure | The usage could not be read, or the alert could not be handed to the mail agent. |

**Crossing the threshold is not a tool failure.** The tool did its job and reported the condition;
the alert is the product, not an error. A failed alert hand-off is `2` — the check worked, the
delivery did not.

**S9** — The notification transport is a hand-off to the host's mail agent, derived from the user's
infrastructure answer:
> "I have a vps that I use for projects like this, IDK if this could works, use the vps for that use
> case. Is a VPS based in ubuntu with arm arch, a VPS from oracle."

> "Oops the real architecture is this one: aarch64, IDK if is ARM or not"

The module composes the subject and body, then hands them to an external mail agent command. The
command is resolved in this order: `--mail-command` → `DISK_MONITOR_MAIL_COMMAND` → the platform
default candidate list. The module holds **no** credentials and performs no network call of its own.
The mail agent is resolved and the recipient validated **before** the check runs, so a broken
alerting path is reported immediately rather than at the moment an alert is needed.

The environment contract is identical on both sides, and it is what makes the
suite deterministic on a platform whose disk source cannot be stubbed:

| Variable | Purpose | Default |
| :-- | :-- | :-- |
| `DISK_MONITOR_TO` | The alert recipient | none — required when the backend is `mail` |
| `DISK_MONITOR_MAIL_COMMAND` | The mail agent | `mail`, then `msmtp` |
| `DISK_MONITOR_USAGE_COMMAND` | The measurement command | `df`, or the native volume API on Windows |
| `DISK_MONITOR_USAGE_OVERRIDE` | A forced usage percentage | none — the disk is measured |

A forced value is labelled `overridden` in both the report and the audit log, so
it can never be mistaken for a measured one.

**S10** — The module holds no secrets, quoted from [`AGENTS.md` §7](../../AGENTS.md):
> "**Never hardcode secrets.** Read from the environment and fail loudly when unset."

**S11** — The disk usage source must be portable. The seed reads:
> `USAGE=$(df -h $PARTITION | awk 'NR==2 {print $5}' | sed 's/%//')`

which is the exact column-layout trap that already broke module 5 on macOS. The implementation uses
the POSIX output format and takes the capacity from the **fifth** field, which is its fixed position
in that layout:
> `df -P <path>` → six fields: filesystem, blocks, used, available, capacity, mount point.

Verified on 2026-10-21: `df -P /` on GNU Linux yields `NF=6`, capacity at `$5`, mount point at `$NF`.
The mount point is last and may be several words long, so counting back from the end would read part
of the mount point instead of the capacity. The fifth field is fixed however many words the mount
point has, and a regression test drives a stub whose mount point contains a space.

**S12** — Tests exercise the public interface, quoted from [`AGENTS.md` §6](../../AGENTS.md):
> "Tests exercise the **public interface** (CLI flags, exit codes, emitted files), not internals."

> "Every test must be **deterministic**: pin timestamps, isolate the filesystem under a temp dir,
> never depend on the host's real services, disk layout, or locale, and clean up after themselves."

The test-first policy applies, quoted from [`odd/METHODOLOGY.md`](METHODOLOGY.md) §2.5:
> "Observe RED before implementing, implement GREEN, then refactor while tests stay green."

**S13** — The pipeline follows the CI model, quoted from [`AGENTS.md` §5.2](../../AGENTS.md):
> "**Always at the repository root** in `.github/workflows/`. GitHub ignores workflows in nested
> `.github/` folders — a module's pipeline placed inside its own folder **will never run**."

> "**Always path-filtered**, including the workflow file itself."

Gates are the language baselines from [`AGENTS.md` §5.1](../../AGENTS.md): `shellcheck -x` for Bash,
`PSScriptAnalyzer` for PowerShell, and the suites on a multi-OS matrix with pinned OS versions.

**S14** — The module is registered across the repository index, per the steps in
[`MODULES.md`](../../MODULES.md) §*Adding a New Module*:
> "3. Add a row to the inventory above **and** to the module table in [`README.md`](README.md).
> 4. Add a path-filtered workflow at the repository root.
> 5. Add the wiki page and the sidebar entry in `wiki/_Sidebar.md`.
> 6. Update the module count in `README.md` and `wiki/01-Monorepo-Architecture.md`."

Wiki pages are numbered `13`, `14` and `15`; pages `10`–`12` are taken by module 5.

### Scope

**S15** — Two stages, not four. The implementation is Bash and PowerShell only: no Python, no
container stage. Module 1's role is to be the cheap, repeatable template for the seven remaining
seed modules, and a template carrying a Python implementation and a container stage is one nobody
converts seven times.

**S16** — Out of scope, as a separate task with its own authorization: the VPS mail stack. The
module ships without it, because the module's contract — hand the alert to the host's mail agent —
does not depend on it. The VPS relay is infrastructure, and its credentials never enter the
repository.

**S17** — Out of scope, as a separate task: adding an ARM64 CI job. The repository's matrix is
x86-only, and `ubuntu-24.04-arm` is free for public repositories, so aarch64 coverage is worth
adding — but it touches a shipped module's pipeline, which is its own scope and its own risk line.

**S18** — The seed's real defects are fixed, not inherited. The four verified ones:

| # | Defect | Evidence |
| :-- | :-- | :-- |
| 1 | The PowerShell side never sends. The `Send-MailMessage` call is commented out, so it only prints "prepared", while the Bash side sends for real. | `disk_monitor.ps1:35` |
| 2 | `Get-WmiObject` was removed in PowerShell 7, but the file declares `#Requires -Version 7.0`. The fallback path is dead on the version it targets. | `disk_monitor.ps1:19` |
| 3 | The Bash side reads `df -h` column 5, the macOS column-layout trap. | `disk_monitor.sh:15` |
| 4 | The Bash side carries CRLF line endings, so the shebang reads `/bin/bash^M` and the script cannot execute at all. | verified 2026-10-21: `bad interpreter: /bin/bash^M` |

**S19** — Deliberate non-goals for v1, recorded so they are decisions rather than omissions:
one partition per invocation; no machine-readable output (`--json`/`--csv`); no direct SMTP or
webhook transport; no containerization; no Python implementation.

---

## Environment Setup (required before running any test)

| Tool | This machine | Consequence |
| :-- | :-- | :-- |
| `bash` | 5.3.20, present | Bash suite runs locally |
| `shellcheck` | **not installed** | Bash lint is a CI-only gate unless installed locally |
| `pwsh` | **not installed** | The PowerShell suite is a CI-only gate |
| `mail` | `/usr/bin/mail`, present | The default Unix mail agent is resolvable |

Because `pwsh` is absent locally and the CI matrix runs the PowerShell suite on **Ubuntu as well
as Windows**, the PowerShell implementation must work on Linux `pwsh` — which rules out
`Get-Volume` and `Get-CimInstance` as the only source of disk figures. The implementation needs a
cross-platform source, with the Windows-native path as a fallback.

This is module 5's lesson applied in advance: the runners catch what the development machine
cannot, so a design that only works on the author's Linux box is not a design yet.

---

## Tasks

| ID | Specs | Task | Route | Status | Evidence |
| :--- | :--- | :-- | :-- | :-- | :-- |
| T0 | S1, S2 | Create the branch; capture the seed baseline and the three defects | Inline | ✅ | `078dda1` — the branch `feat/1-disk-monitor` and the seed tracked as the baseline |
| T1 | S7, S8, S9, S10, S11, S12, S18 | Hardened Bash implementation + Bash test suite (RED → GREEN) | Inline | ✅ | `7572de6` — RED 16/26 against the seed, **GREEN 42 passed, 0 failed** |
| T2 | S4, S7, S8, S9, S10, S11, S12, S18 | Hardened PowerShell implementation + PowerShell test suite, mirroring T1's observed behaviour | Inline | ✅ | `94d716a` — 25 scenarios, 55 assertions, green on Windows and Ubuntu in CI |
| T3 | S4 | Parity proof: same flags, defaults, validation, exit codes and messages on both sides | Inline | ✅ | Both suites assert the same 25 scenarios and 55 assertions; the contract tables in `SPECS.md` and `docs/ARCHITECTURE_COMPARISON.md` are derived from the two implementations |
| T4 | S4 | Root CI workflow with path filters and a multi-OS matrix | Inline | ✅ | `3bd7446` — 6 jobs, all green in run `39639801166` |
| T5 | S3, S6, S7, S8, S13, S15 | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md` | Delegated | ✅ | All four written, every example executed and captured |
| T6 | S9, S16 | `docs/ARCHITECTURE_COMPARISON.md`, `docs/SCENARIOS.md`, `docs/labs/LAB1-3.md` | Delegated | ✅ | 41 command invocations captured; every output in the labs is real |
| T7 | S14 | Wiki pages 13–15, `_Sidebar.md`, `Home.md`, `wiki/01-Monorepo-Architecture.md` | Delegated | ✅ | Three pages plus the three shared pages; the shipped count moved from 3 to 4 |
| T8 | S14, S15 | `MODULES.md`, `README.md` and `CHANGELOG.md` registration | Delegated | ✅ | Module 1 moved to the shipped group with a defect table; the counts agree across all three files |
| T9 | S12, S13 | Full local matrix verification; close with a `Risk:` line | Inline | ✅ | Run `39639801166`: 6 of 6 jobs green, 55 assertions per suite on both platforms |

> Task IDs are stable; the table is ordered by execution sequence.

### Route declaration and trigger evidence

**T1 and T2 are inline, and sequential on purpose.** The parallelism trigger requires two
*independent* units of behaviour. These two are not independent: the PowerShell side exists to
mirror the Bash side's observed behaviour, and module 5 shipped with exactly this drift when the
data contract was written twice. T1 is the reference implementation, T2 mirrors it, and T3 proves
the mirror. The context backstop does not apply at this size, and no other named reason fires, so
the parent writes both.

**T6 and T7 are delegated, in parallel.** They are two independent units of behaviour with disjoint
edit surfaces (`docs/` inside the module folder versus `wiki/` at the repository root), each
substantial enough to need more than a couple of minutes, and neither depends on the other's
output. They are launched together, with the shared contract carried in the prompt, because units
built in parallel cannot see each other.

**Everything else is inline**, including the CI workflow and the repository index, because each is
one focused change with a single surface.

### Forecast

~2,450 authored changed lines (additions plus deletions, generated files excluded), against
module 2's comparable core at 1,310 lines. The budget crossing is handled at the first commit that
passes ~400 authored lines, per the delivery strategy in the header.

---

## Log

**L1** — 2026-10-21. User request, verbatim:
> "Okay, then let's discuss about the module 1, what is this module, how can we deal with this one,
> which technologies can we use for this one?"

> "Great. So let's start with that, let's go."

**L2** — 2026-10-21. Prior state reconciled before this document was written. The step 0 hygiene
pass shipped as two commits (`64a65e0`, `e32873b`) on `main`, pushed and merged by the local
fast-forward flow; `main` equals `origin/main`; the working tree holds only the eight untracked
seed modules; ten merged local branches were deleted and origin still carries their heads.

**L3** — 2026-10-21. Evidence recorded for this feature:
- The seed is 75 lines total: `disk_monitor.sh` 34, `disk_monitor.ps1` 41, both untracked.
- Seed defect 1 — `disk_monitor.ps1:35` has the `Send-MailMessage` call commented out.
- Seed defect 2 — `disk_monitor.ps1:19` calls `Get-WmiObject`, removed in PowerShell 7.
- Seed defect 3 — `disk_monitor.sh:15` reads `df -h` column 5.
- `df -P /` on this machine → `NF=6`, capacity at `$(NF-1)`, mount point at `$NF`.
- `df -h /` on this machine → also six fields; the divergence appears on macOS, which is where
  module 5 broke.
- Local toolchain: `bash` 5.3.20 present; `shellcheck`, `pwsh` absent; `mail` present;
  `python3` present.
- Module 2's comparable artifacts: `cleanup_logs.sh` 345, `cleanup_logs.ps1` 275,
  `test_cleanup_logs.sh` 191, `test_cleanup_monitor.ps1` 155, `SPECS.md` 210, `README.md` 134.

**L4** — 2026-10-21. Decisions taken, with their reasons:
- **Transport: hand-off to the host's mail agent.** It keeps the module credential-free, keeps both
  implementations in parity, and keeps the test suite deterministic by stubbing the command on
  `PATH`. Raw SMTP and webhook transports were considered and rejected: SMTP puts a credential
  lifecycle in every module, and a webhook backend would change the module's stated purpose.
- **Deployment: host-agnostic, VPS first.** The contract does not vary per host, so the module is
  written once and the host's mail agent configuration is what differs. The VPS is the reference
  deployment because it is where the user will run it.
- **Oracle Cloud note, verified 2026-10-21:** outbound TCP port 25 is blocked by default for
  tenancies created after 2021-06-23, and the block cannot be lifted from the VCN security list.
  The VPS therefore relays through a third-party provider on port 587, where the provider handles
  DKIM. This is recorded because it changes the LAB3 runbook, not because the module depends on it.
- **ARM64 note, verified 2026-10-21:** `aarch64` is ARM64. Module 5's `python:3.11-alpine` base
  image is a multi-arch manifest index that includes `arm64/v8`, and neither the Dockerfile nor
  the compose file pins a platform — so the image builds natively on the user's VPS. The metrics
  correctness on aarch64 remains unverified and belongs to the out-of-scope ARM CI task (S17).

**L5** — 2026-10-21. Next step: **T0**. Create `feat/1-disk-monitor` from `main` and record the
seed baseline in the first commit, then T1.

**L6** — 2026-10-21. T0 and T1 executed on `feat/1-disk-monitor`.

- **T0 — `078dda1`.** The seed entered git as the baseline, so the remediation has a visible before
  and after. A fourth defect was found while committing it, and it is the reason the seed had never
  worked: `disk_monitor.sh` carries **CRLF line endings**, so the shebang reads
  `/bin/bash^M` and the script cannot execute. The committed blob is LF because `.gitattributes`
  normalises it, but the module was never in git, so nobody ever ran the file. S18 is updated from
  three defects to four.
- **T1 — `7572de6`.** The Bash implementation and its suite. RED observed twice, and the two
  observations answer different questions: against the untouched seed the suite reported **1 passed,
  41 failed**, every failure caused by exit 126 (the CRLF shebang); with the line endings corrected
  the suite reported **16 passed, 26 failed**, isolating the missing features from the broken
  file. GREEN is **42 passed, 0 failed**. A real run against the actual disk reports 49 % and exits
  0; the dry-run path reports the pending alert and hands nothing to the mail agent.
- The first GREEN attempt was 38/42, and all four failures were in the test harness, not the
  implementation: the harness created the capture file itself, so "the mail agent was never
  invoked" could never be asserted by its absence. The assertion now checks the capture's
  contents.
- **The review budget was crossed here.** T1 is 754 authored changed lines (333 added, 28 removed
  in the implementation, 393 added in the suite). The unit is not splittable: the work-unit rules
  require the tests to ship with the behaviour they verify, and splitting a suite from its
  implementation is the explicitly named weak split. The budget constrains slicing, never the
  code, so the delivery shape was resolved instead: `single-pr`, one pull request at the end
  carried by work-unit commits, which is what [`AGENTS.md` §4](../../AGENTS.md) documents and what
  module 5 did with 21 work-unit commits. Stacked or chained pull requests remain available if the
  maintainer prefers them.
- **Local verification limit.** `shellcheck` and `pwsh` are both absent from this machine, so the
  Bash lint gate and the whole PowerShell suite are CI-only. The branch push triggers the new
  workflow on `feat/**`, which is how the PowerShell evidence will be obtained.

**L7** — 2026-10-21. Next step: **T2**. The PowerShell implementation mirrors T1's observed
behaviour, and T3 proves the parity.

**L8** — 2026-10-21. The first CI run on the real runners found four defects that the development
machine could not, and a delegated documentation writer found a fifth.

- **The capacity was read from the wrong field.** The implementation took the second-to-last field of
  the `df -P` output, which is only correct while the mount point is a single word: `awk` splits on
  whitespace, so `/mnt/my disk` makes the second-to-last field part of the mount point. The
  capacity is the **fifth** field, which is its fixed position in the POSIX layout. Both
  implementations were corrected and a regression test now drives a stub whose mount point
  contains a space. S11 was corrected to match.
- **A PowerShell parameter was silently discarded.** Variable names are case-insensitive, so the
  local `$mailCommand` and the parameter `$MailCommand` were the same variable, and the local was
  assigned an empty string before the parameter was read. `-MailCommand` did nothing; only the
  environment variable worked.
- **The test harness reported assertions it never ran.** Under the strict mode a mandatory string
  parameter rejects an empty value, so an assertion against empty output raised a binding error that
  was printed and skipped. The suite could report a pass it had not earned.
- **The harness shadowed the automatic `$LASTEXITCODE`.** A script-scoped variable whose name
  differs from an automatic variable only in case still shadows it, so the harness read its own
  zero instead of the exit code the tool had returned. Every exit-code assertion in the PowerShell
  suite saw a false success — 43 assertions passed for the wrong reason while 12 failed with
  `Got: '0'`.
- **The analyzer rejected the harness.** Two unapproved verbs, two plural nouns, thirty global
  variables and two state-changing verbs. The verbs were renamed to approved ones and the shared
  state moved to the script scope, which is what the analyzer itself recommends.

**L9** — 2026-10-21. The feature is complete on the branch. Run `39639801166` is green across all six
jobs: ShellCheck, the Bash suite on Ubuntu and macOS, PSScriptAnalyzer, and the PowerShell suite on
Windows and Ubuntu. Both suites assert the same 25 scenarios and 55 assertions. The module
contract is satisfied, the repository index agrees on 11 modules with 4 shipped, and the four
documentation tasks were delivered by delegated writers against disjoint edit surfaces.

**L10** — 2026-10-21. Next step: the pull request and the merge, both of which are the maintainer's
decision. Nothing else remains open inside this feature.

---

## Close

Module 1 ships. The module contract is satisfied, both implementations hold the same contract, and
the pipeline is green on Linux, macOS and Windows.

**What a reviewer should know.** The seed was 75 lines that had never been run, and the fourth
defect was only visible because the module was tracked: its line endings were CRLF, so the shebang
read `/bin/bash^M` and the script could not execute at all. The first CI run then found four more
defects that no amount of local testing would have found, including two that would have shipped a
suite reporting passes it never earned.

**What is deliberately left open**, and is recorded rather than hidden:

- The two implementations differ in how they measure. Bash reads `df -P`; PowerShell reads the
  native volume API on Windows. Both report the same number for the same filesystem, but they are
  two code paths.
- The Windows volume path is exercised by the CI runner, not by a developer machine.
- The mail hand-off contract is `<mail-command> -s <subject> <recipient>` with the body on stdin. An
  agent that does not honour it — `sendmail`, for instance, which wants `-t` — has to be wrapped.

**Delivery.** 13 work-unit commits on `feat/1-disk-monitor`, pushed. The pull request and the merge
are the maintainer's decision. The wiki pages are committed to `main:wiki/`; the published wiki
repository is a separate clone and is pushed separately, as it was for module 5.
