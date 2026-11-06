# Automated Git Deployment 🚀

Cross-platform automated deployment from a Git repository. Available in **POSIX Bash**
(Linux/macOS) and **PowerShell** (Windows), with 100% feature parity.

---

## Key Features

- 🛡️ **Safety Guardrails**: validates app/backup dirs and branch name; refuses protected roots; app dir must be a git work tree.
- 🔐 **Origin Verification**: explicit `-r/--repo-url` is checked against `origin` (normalized comparison); mismatch aborts with exit 1 before any side effect.
- 🧪 **Dry-Run Simulation**: preview fetch/backup/pull/post-deploy without mutating.
- 💾 **Verified Pre-deploy Backup**: tar.gz (Bash, `gzip -t`) / zip (PS, .NET ZipArchive, entry-by-entry SHA-256), dotfiles included. Backup failure aborts the run — no fetch, no pull (exit 2).
- ↩️ **Automatic Rollback**: on pull failure the tree is restored to the pre-deploy revision (`git reset --hard`; `--no-rollback` / `-NoRollback` to disable).
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

The Bash suite stubs `git`, `tar`, `npm` and `systemctl` (59 tests); no real repo is touched. The
PowerShell suite exercises parsing, guardrails and the full failure-safety flow (41 tests) against
real, hermetic git repositories (local bare "remotes"; host git config isolated — no network).

---

## Documentation

- [SPECS.md](SPECS.md) — technical specification & architecture.
- [ROADMAP.md](ROADMAP.md) — phased milestones.
- [CODESTYLE.md](CODESTYLE.md) — module conventions.
- [docs/](docs/) — architecture comparison, scenarios, labs.