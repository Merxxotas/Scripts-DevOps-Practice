# Automated Git Deployment 🚀

Cross-platform automated deployment from a Git repository. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: validates app/backup dirs and branch name; refuses protected roots.
- 🧪 **Dry-Run Simulation**: preview fetch/backup/pull/post-deploy without mutating.
- 💾 **Pre-deploy Backup**: tar.gz (Bash) / zip (PS), timestamped.
- 🔁 **Up-to-date Detection**: skips deploy when local matches remote.
- ⚙️ **Post-deploy Tasks**: npm install (if `package.json`), service restart (configurable).
- 📝 **Audit Logging**: optional ISO-8601 log of every run.
- ⚙️ **Zero Dependencies** beyond `git` and standard tooling.

---

## Quick Start

### Linux / macOS (Bash)

```bash
chmod +x git_deploy.sh

# Deploy (interactive defaults)
./git_deploy.sh

# Dry run
./git_deploy.sh --dry-run

# Custom app dir and branch
./git_deploy.sh -a /var/www/myapp -b develop

# Skip post-deploy
./git_deploy.sh --skip-post-deploy
```

### Windows (PowerShell)

```powershell
# Deploy
.\git_deploy.ps1

# Dry run
.\git_deploy.ps1 -DryRun

# Custom
.\git_deploy.ps1 -AppDir C:\inetpub\wwwroot\myapp -Branch develop

# Skip post-deploy
.\git_deploy.ps1 -SkipPostDeploy
```

---

## CLI Reference

See [SPECS.md §3](SPECS.md).

---

## Exit Codes

`0` success · `1` configuration or safety violation · `2` partial failure.

---

## Tests

```bash
bash tests/test_git_deploy.sh
pwsh tests/test_git_deploy.ps1
```

The Bash suite stubs `git`, `tar`, `npm` and `systemctl`; no real repo is touched. The
PowerShell suite exercises parsing, guardrails and dry-run.

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.