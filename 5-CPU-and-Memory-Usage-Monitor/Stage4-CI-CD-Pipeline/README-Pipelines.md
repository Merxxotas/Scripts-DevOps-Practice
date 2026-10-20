# Stage 4: CI/CD Pipelines Explained

> Understanding and executing the Continuous Integration and Deployment pipelines.

---

## What is CI/CD?

**CI/CD = Continuous Integration / Continuous Deployment**

Think of it as an **automated assembly line** for your code:

```
You push code → GitHub Actions tests it → If tests pass → Deploy automatically
```

### Why CI/CD is Important

| Benefit | Description | Impact |
|---------|-------------|--------|
| **Catch Bugs Early** | Automated tests run on every change | Reduces production issues by 70%+ |
| **Faster Releases** | No manual testing bottlenecks | Deploy multiple times per day |
| **Consistency** | Same tests run every time | No "works on my machine" |
| **Documentation** | Pipeline serves as executable documentation | New team members onboard faster |
| **Confidence** | Green checkmarks = safe to deploy | Reduce deployment anxiety |

---

## Our Pipeline Architecture

### Three Workflow Files

| Workflow | File | Purpose | When It Runs |
|----------|------|---------|--------------|
| **Main CI/CD** | `ci-cd-pipeline.yml` | Full testing and deployment | Push to main, PRs, schedule |
| **PR Validation** | `pr-validation.yml` | Fast feedback on PRs | Pull requests |
| **Release** | `release.yml` | Versioned releases | Git tags (v*) |

### Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEVELOPER PUSHES CODE                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │  Stage 1 │    │  Stage 2 │    │  Stage 3 │
    │  Native  │    │  Python  │    │  Docker  │
    │  Scripts │    │  Unified │    │  Images  │
    └────┬─────┘    └────┬─────┘    └────┬─────┘
         │               │               │
         │   ┌───────────┴───────────┐   │
         │   │                       │   │
         ▼   ▼                       ▼   ▼
    ┌───────────────────────────────────────┐
    │         ALL TESTS PASSED?             │
    └────────────────┬──────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
   ┌──────────┐           ┌──────────┐
   │   YES    │           │    NO    │
   └────┬─────┘           └────┬─────┘
        │                      │
        ▼                      ▼
┌──────────────┐      ┌────────────────┐
│ BUILD & PUSH │      │  NOTIFY FAILURE│
│ DOCKER IMAGE │      │  ❌ BLOCKED    │
│              │      └────────────────┘
│ • Multi-arch │
│ • Latest tag │
│ • Version tag│
└──────────────┘
```

---

## How to Execute Pipelines

### Automatic Execution (Default)

Pipelines run automatically on these events:

```yaml
on:
  push:
    branches: [main]        # Push to main branch
  pull_request:
    branches: [main]        # Pull request to main
  schedule:
    - cron: '0 2 * * 0'     # Every Sunday at 2 AM
  workflow_dispatch:        # Manual trigger
```

### Manual Execution

To manually trigger a pipeline:

1. **Go to Actions Tab**
   ```
   GitHub Repository → Actions tab
   ```

2. **Select Workflow**
   ```
   Click on "CI/CD Pipeline"
   ```

3. **Run Workflow**
   ```
   Click "Run workflow" button
   Select branch (main)
   Choose stage: all | stage1 | stage2 | stage3
   Click "Run workflow"
   ```

### Local Testing (Before Pushing)

Test changes locally to avoid pipeline failures:

```bash
# Stage 1 - Test scripts
cd Stage1-Native-Scripts

# Bash
shellcheck system_monitor.sh
bash -n system_monitor.sh
./system_monitor.sh --help

# PowerShell
Invoke-ScriptAnalyzer -Path system_monitor.ps1
.\system_monitor.ps1 -Help

# Stage 2 - Test Python
cd Stage2-Python-Unified
uv run pytest
uv run mypy src/system_monitor/
uv run ruff check src/

# Stage 3 - Test Docker
cd Stage3-Containerization
docker build -t test-build .
docker run --rm test-build --help
```

---

## Pipeline Stages Explained

### Stage 1: Native Script Testing

**Job:** `test-stage1-bash` and `test-stage1-powershell`

**What It Tests:**
```yaml
Test Steps:
  1. Checkout code
  2. Install ShellCheck (Bash) or PSScriptAnalyzer (PowerShell)
  3. Run static analysis
  4. Test script syntax
  5. Execute script with various options
  6. Verify outputs
```

**Example Output:**
```
✅ ShellCheck passed
✅ Syntax validation passed
✅ Execution test passed (help output)
✅ Execution test passed (JSON output)
✅ Execution test passed (watch mode)
```

**On Failure:**
```
❌ ShellCheck found issues:
   system_monitor.sh:45:1: warning: Prefer putting braces around variable references
```

### Stage 2: Python Testing

**Job:** `test-stage2-python`

**Matrix Testing:**
```yaml
OS: [ubuntu-latest, windows-latest, macos-latest]
Python: ['3.9', '3.10', '3.11', '3.12']
```

**What It Tests:**
```yaml
Test Steps:
  1. Setup Python
  2. Install UV
  3. Install dependencies
  4. Run type checking (mypy)
  5. Run linting (ruff)
  6. Run unit tests (pytest)
  7. Check code coverage
```

**Example Output:**
```
✅ Type checking passed (mypy)
✅ Linting passed (ruff)
✅ Tests passed (pytest)
   - test_models.py: 12 passed
   - test_monitor.py: 18 passed
   - test_exporters.py: 8 passed
   - test_cli.py: 15 passed
✅ Coverage: 87%
```

### Stage 3: Docker Testing

**Job:** `test-stage3-docker`

**What It Tests:**
```yaml
Test Steps:
  1. Checkout code
  2. Set up Docker Buildx
  3. Build Docker image
  4. Test image runs
  5. Run Trivy security scan
  6. Check for vulnerabilities
```

**Example Output:**
```
✅ Docker build successful (system-monitor:latest)
✅ Container starts successfully
✅ Health check passes
✅ Trivy scan: No CRITICAL or HIGH vulnerabilities
✅ Image size: 58MB (acceptable)
```

**On Failure:**
```
❌ Trivy found vulnerabilities:
   CRITICAL: CVE-2024-XXXX in package XYZ
   HIGH: CVE-2024-YYYY in package ABC
```

### Build and Push Stage

**Job:** `build-and-push`

**Only runs if all tests pass**

**What It Does:**
```yaml
Build Steps:
  1. Set up QEMU (for multi-arch)
  2. Set up Docker Buildx
  3. Login to Docker Hub
  4. Build multi-arch images:
     - linux/amd64
     - linux/arm64
     - linux/arm/v7
  5. Push with tags:
     - latest
     - v2.0.0 (version)
     - sha-abc123 (commit)
```

---

## Required Secrets

Configure these in GitHub Settings → Secrets and variables → Actions:

| Secret | Purpose | Required For |
|--------|---------|--------------|
| `DOCKER_USERNAME` | Docker Hub login | Pushing images |
| `DOCKER_PASSWORD` | Docker Hub token | Pushing images |
| `SLACK_WEBHOOK_URL` | Notifications | Slack alerts (optional) |

### Setting Up Secrets

1. Go to your GitHub repository
2. Click **Settings** tab
3. Select **Secrets and variables** → **Actions**
4. Click **New repository secret**
5. Add each secret

---

## Monitoring Pipeline Health

### GitHub Actions Dashboard

```
Repository → Actions tab

Shows:
├── Workflow runs (pass/fail history)
├── Duration trends
├── Success rate
└── Recent failures
```

### Status Badges

Add to README.md:

```markdown
![CI/CD Pipeline](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/ci-cd-pipeline.yml/badge.svg)
![PR Validation](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/pr-validation.yml/badge.svg)
```

### Notifications

Configure Slack notifications:

```yaml
- name: Notify Slack
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    channel: '#devops-alerts'
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## Troubleshooting Failed Pipelines

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| **ShellCheck fails** | Script syntax/style issues | Run `shellcheck` locally, fix warnings |
| **pytest fails** | Code changes broke tests | Run `pytest` locally, update tests |
| **mypy fails** | Type hint errors | Run `mypy` locally, add/fix type hints |
| **Docker build fails** | Dockerfile issues | Run `docker build` locally |
| **Trivy finds CVEs** | Vulnerable dependencies | Update base image, run `apt update` |
| **Push fails** | Missing/wrong secrets | Check DOCKER_USERNAME/PASSWORD |

### Debugging Steps

1. **Check Logs**
   ```
   Actions tab → Failed workflow → Failed job → View logs
   ```

2. **Reproduce Locally**
   ```bash
   # Run the same command as the pipeline
   shellcheck system_monitor.sh
   pytest
   docker build -t test .
   ```

3. **Enable Debug Logging**
   ```bash
   # Re-run job with debug logging
   Actions tab → Re-run jobs → Enable debug logging
   ```

---

## Best Practices

### Before Pushing Code

```bash
# 1. Run all tests locally
./test-all.sh  # Create this script

# 2. Check code quality
shellcheck *.sh
pylint src/

# 3. Verify Docker builds
docker build -t test .
```

### Commit Message Format

```
feat: Add disk I/O monitoring
fix: Correct CPU calculation on macOS
docs: Update README with new examples
test: Add unit tests for process kill
ci: Update GitHub Actions workflow
```

### Branch Protection

Configure in GitHub Settings → Branches:

```
Protect main branch:
  Require pull request reviews
  Require status checks to pass
     - ci-cd-pipeline / test-stage1-bash
     - ci-cd-pipeline / test-stage2-python
     - ci-cd-pipeline / test-stage3-docker
  Require branches to be up to date
  Include administrators
```

---

##  Additional Resources

- [Main README](README.md) - Quick setup guide
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Trivy Security Scanner](https://aquasecurity.github.io/trivy/)