# Security Policy

Security matters for a repository whose entire purpose is running privileged automation on other people's
machines. This document defines what counts as a vulnerability here, how to report one, and what we commit
to in response.

> **Do not open a public issue for a security problem.** See [Reporting a Vulnerability](#reporting-a-vulnerability).

---

## Supported Versions

Security fixes are applied to the **default branch (`main`)** and to the two shipped modules.

| Module | Path | Supported | Status |
| :--- | :--- | :-- | :--- |
| Log Cleanup | `2-Log-Cleanup-Script-(Delete-Files-Older-Than-X-Days)/` | ✅ | Shipped, CI-covered |
| EventOps | `11-Scheduling-And-Automation/` | ✅ | Shipped, CI-covered |
| CPU and Memory Usage Monitor | `5-CPU-and-Memory-Usage-Monitor/` | ⚠️ | Local only — not yet released |
| Seed modules | `1-`, `3-`, `4-`, `6-`, `7-`, `8-`, `9-`, `10-` | ❌ | Not released; no support commitment |

Modules marked **not released** are still worth reporting — a seed script with a real flaw may be
inherited by someone who copies it. We triage those as best-effort.

There are **no tagged releases yet**, so "supported version" means "the current tip of `main`".

---

## Reporting a Vulnerability

Use **one** of the two channels below. Both reach the maintainer privately. **Never** open a public
issue or a public discussion for a security problem.

### Channel 1 — GitHub Security Advisory *(preferred)*

This opens a private advisory visible only to the maintainer, and it does not attach your name to a
public issue.

1. Go to **Security** → **Report a vulnerability** on the repository page.
   <https://github.com/Merxxotas/Scripts-DevOps-Practice/security/advisories/new>
2. Describe the issue, the module, the affected file and line, and the impact.
3. You will get an acknowledgement within **7 days**.

> If the **Report a vulnerability** button is not shown, private vulnerability reporting is not
> enabled on this repository yet — use **Channel 2** instead. It reaches the same person, with the
> same discretion.

### Channel 2 — Encrypted or plain email *(always available)*

Email **brayan6590@gmail.com** with the same details as below. For anything sensitive, encrypt the
message with the maintainer's public key (published in the repository's security tab) or send it as
a PGP message — do not rely on the transport alone.

> For a **social-engineering or credential-phishing** report, prefer this channel: a private
> advisory is tied to the repository and may be visible to repository collaborators in a way that a
> plain email is not.

**Please do not** test against other people's systems, do not exfiltrate data, and do not run a
proof-of-concept against infrastructure you do not own.

### What to include

| Field | Detail |
| :--- | :--- |
| Module | Which numbered folder |
| File and line | Exact location |
| Impact | What an attacker gains — code execution, arbitrary deletion, credential exposure, DoS |
| Prerequisites | Privileges, network position, configuration needed |
| Reproduction | Minimal steps or a script, runnable in a sandbox |
| Suggested fix | If you have one |

---

## Response Process

| Stage | Target |
| :--- | :--- |
| Acknowledgement | 7 days |
| Initial assessment (valid / not valid / needs more info) | 14 days |
| Fix released or mitigation published | 30 days for high severity, 90 days for moderate |
| Public advisory | On fix release, or 90 days after the report, whichever comes first |

We will keep you updated, credit you in the advisory unless you prefer otherwise, and coordinate
disclosure so you are not left exposed. Coordinated disclosure: fix first, publish second.

If a report is declined, we will explain why in detail.

---

## What Counts as a Vulnerability

These modules **intend** to do powerful things. The design is documented; the behaviour is the
contract. A report that only describes intended, documented behaviour is not a vulnerability.

### ✅ In scope

- **Command or argument injection** — a crafted path, filename, webhook body, or rule value that
  escapes its intended boundary and executes unintended commands.
- **Path traversal** — escaping the target directory to read or delete files outside it, including
  via symbolic links.
- **Guardrail bypass** — a documented safety refusal (root/system directory blacklist, root-check,
  protected-path list) that a crafted input defeats.
- **Destructive overreach** — deleting, truncating, or modifying files beyond the documented scope
  of a command, including the recursive and dry-run modes.
- **Secret exposure** — credentials, tokens or sensitive payloads written to logs, committed to the
  repository, or exposed through a webhook response or HTTP error.
- **Unauthenticated remote code execution** — especially in EventOps, whose webhook server is
  designed to receive remote requests. Missing authentication on a privileged endpoint is in scope.
- **Privilege escalation** — a script obtaining capabilities beyond what its documented run mode
  implies.
- **Unsafe defaults** — a documented safe mode that is not actually safe by default, or a
  documented dry-run that mutates state.
- **Supply-chain issues** — a workflow that executes untrusted code, downloads without integrity
  verification, or leaks secrets into logs.

### ❌ Out of scope

- **Documented behaviour.** Deleting files older than N days in a directory you pointed it at.
  Restarting a service you named. Killing a process you selected. These are the product.
- **Running as root.** Several scripts need elevated privileges by design. Running a script as root
  and then trusting it is the documented operating model, not a vulnerability.
- **Missing hardening for a hostile local administrator.** Anyone who can edit the script or its
  config already has equivalent or greater access.
- **Denial of service through resource exhaustion** on a self-hosted instance, unless it crosses a
  documented trust boundary (for example, an unauthenticated remote flood against the webhook
  endpoint).
- **Lab and scenario documentation** — the labs deliberately demonstrate risky operations in a
  sandbox. Follow the setup steps exactly.
- **Vulnerabilities in upstream dependencies** — report those to the upstream project. We will
  happily upgrade the dependency.
- **Automated scanner output with no demonstrated impact.** Report it, but expect it to be
  triaged as low priority.
- **Theoretical attacks with no practical path** in the documented deployment model.
- **Missing hardening on a machine the owner does not control** — this is a local privilege
  problem, not a repository vulnerability.

---

## Security Guidance for Users

These utilities run with real privileges. Before deploying one:

1. **Read the guardrails first.** Know exactly which paths it refuses to touch.
2. **Start in dry-run.** Both shipped modules support a non-destructive preview mode; use it until the
   output matches your expectation.
3. **Run with the least privilege that works.** Prefer a dedicated service account over root.
4. **Scope the target narrowly.** Point it at a specific directory, never at a parent of one.
5. **Enable audit logging** (ISO-8601 trail of every action) and **test the exit codes** (`0` success,
   `1` configuration/safety violation, `2` partial failure).
6. **Keep secrets out of the script.** Pass credentials through the environment.

---

## Security Guidance for Contributors

Before opening a pull request, confirm:

- [ ] **No hardcoded secrets.** No API keys, tokens, passwords, or real hostnames in source, tests,
      fixtures, docs, or labs. Use obvious placeholders (`admin@example.com`).
- [ ] **No secrets in CI.** Workflows read credentials from repository secrets, never literals.
- [ ] **Inputs are validated.** Paths, arguments, JSON payloads, and webhook bodies are checked
      before use.
- [ ] **Destructive operations are guarded.** A path blacklist, a root check, or an equivalent
      refusal exists wherever files are deleted, processes are killed, or services are restarted.
- [ ] **A dry-run mode exists** for anything destructive, and it genuinely does not mutate state.
- [ ] **Exit codes follow the contract** — `0` / `1` / `2` — and are documented in the README.
- [ ] **Logs contain no sensitive values.** Never log credentials or full secret-bearing payloads.
- [ ] **Dependencies are pinned** where reproducibility matters, and updates are deliberate.
- [ ] **A test covers the new behaviour**, including a regression test for every existing command
      or option the change touches.

---

## Hardening Notes for EventOps

EventOps is the module with a **network-facing surface** and therefore the highest review priority.

- The webhook server binds a port and accepts `POST` requests. Treat it as an unauthenticated
  endpoint **until you deploy it behind an authenticating proxy** — and prefer doing so.
- `rules.json` maps request paths to shell commands. Anyone who can write that file, or reach an
  unmatched-but-accepted path, controls execution. Keep it out of untrusted hands.
- The file watcher triggers on path changes. A write to a watched path is equivalent to firing a
  webhook.
- Debouncing limits duplicate triggers but is **not** an authorization mechanism.
- Run the daemon as an unprivileged user with access only to the paths it must act on.

---

## Related

- [`AGENTS.md`](AGENTS.md) — repository standards, including the security rules for contributors
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — the development workflow
- [`SUPPORT.md`](SUPPORT.md) — non-security questions
