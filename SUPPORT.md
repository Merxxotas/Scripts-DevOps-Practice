# Support

## Where to Ask

| I want to… | Go to |
| :--- | :--- |
| Report a **bug** | [Open an issue](.github/ISSUE_TEMPLATE/bug_report.md) |
| Request a **feature** | [Open an issue](.github/ISSUE_TEMPLATE/feature_request.md) |
| Report a **security vulnerability** | **[SECURITY.md](SECURITY.md)** — private reporting, do not open a public issue |
| Ask a **how-to** question | [GitHub Discussions → Q&A](https://github.com/Merxxotas/Scripts-DevOps-Practice/discussions/categories/q-a) |
| Read the **rendered knowledge base** | [GitHub Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki) |
| Understand a module | [`MODULES.md`](MODULES.md), then the module's own `README.md` |
| Understand the architecture | [`wiki/01-Monorepo-Architecture.md`](wiki/01-Monorepo-Architecture.md) |
| Contribute code | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

> **Prefer Discussions for questions.** Issues are for concrete, reproducible problems and feature
> proposals. A "how do I…" question belongs in the **Q&A** category, where it gets a better answer
> and does not clutter the issue tracker.
>
> The wiki is published twice — as [`wiki/`](wiki/) in this repository and as the
> [GitHub Wiki](https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki). The two are currently
> byte-identical.

> **Prefer Discussions for questions.** Issues are for concrete, reproducible problems and feature
> proposals. A "how do I…" question is a better fit for Discussions and gets a better answer.

---

## Before You Ask

Most questions are answered by the documentation. Check these first:

1. **The module's `README.md`** — usage, flags, defaults, exit codes, cron and Task Scheduler
   examples, troubleshooting table.
2. **The module's `SPECS.md`** — what the tool is designed to do, and its architecture.
3. **The module's `docs/`** — production scenarios and step-by-step labs.
4. **The module's `--help` output** — the authoritative flag list.

```bash
# Bash
./cleanup_logs.sh --help

# PowerShell
.\cleanup_logs.ps1 -? | Out-String

# Python (EventOps)
python eventops.py --help

# Go (EventOps)
go run . --help
```

---

## Scope of Support

**What you can expect:**

- Help understanding how a module works and why it is designed that way.
- Help reproducing and diagnosing a failure, including reading the audit log.
- Help understanding a CI failure on a specific operating system.

**What is out of scope:**

- **Production deployment and operations.** These utilities are designed for Linux, macOS and
  Windows servers, but adapting them to *your* infrastructure — a specific database engine, a
  specific service manager, a specific Kubernetes distribution — is your responsibility.
- **24/7 incident response.** There is no on-call rotation and no response SLA.
- **Commercial support, warranties, or SLAs.**
- **Custom feature development on request.** Feature proposals are welcome; commissioned work is
  not something this project takes on.

---

## Environment Notes

Reporting a bug is far faster if you include these:

| Detail | Why it matters |
| :--- | :--- |
| **Module and file** | Modules are independent; the wrong one sends the question nowhere. |
| **Operating system and version** | `uname -a` on Linux/macOS, `[System.Environment]::OSVersion` on Windows. |
| **Shell and version** | `bash --version`, `$PSVersionTable.PSVersion`. |
| **Runtime and version** | `python3 --version`, `go version`. |
| **Exact command** | Copy-paste, including flags. |
| **Observed vs expected output** | Both, in full. |
| **Exit code** | `echo $?` — these modules use a documented exit-code contract. |
| **Audit log** | If the module writes one, the relevant lines explain what it actually did. |

### Common environment causes

| Symptom | Likely cause |
| :--- | :--- |
| `command not found: shellcheck` / `PSScriptAnalyzer` | Linter not installed locally. CI installs them; you do not need them to run the tests. |
| Bash script fails immediately on Windows | Line-ending problem — CRLF shebang. See the `.gitattributes` note in [`AGENTS.md` §9](AGENTS.md). |
| `Permission denied` on a target directory | The tool needs write and delete permission on the directory it is given. |
| Tool refuses to run at all | A guardrail triggered — it refuses `/`, `C:\`, `/etc`, `/var` and other system paths. This is intentional. |
| Module 5 Python tests fail to start | The committed `.venv` is stale. Rebuild it — see [`AGENTS.md` §9](AGENTS.md). |

---

## Reporting a Security Issue

**Do not open a public issue for a security vulnerability.** Use the private reporting channel
described in [`SECURITY.md`](SECURITY.md).

---

## What Happens Next

- **Bugs** — confirmed defects get a `fix/<slug>` branch, a regression test, and a pull request.
- **Feature requests** — discussed first, then scheduled into a module's roadmap. A proposal for a
  new module is usually better raised as an issue before any code is written.
- **Questions** — answered in Discussions, and the answer usually gets folded back into the
  module's `README.md` so the next person does not have to ask again.

---

## Related

- [`AGENTS.md`](AGENTS.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`SECURITY.md`](SECURITY.md) · [`MODULES.md`](MODULES.md)
