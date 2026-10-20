# CI/CD Pipeline with GitHub Actions

> **Automated testing and deployment** for all three stages of the System Resource Monitor project.

---

## What is CI/CD?

**CI/CD = Continuous Integration / Continuous Deployment**

Think of it like an **automated assembly line** for your code:

```
You push code → GitHub Actions tests it → If tests pass → Deploy automatically
```

### Continuous Integration (CI)
- Automatically test code when you push changes
- Catch bugs before they reach production
- Ensure code quality with automated checks

### Continuous Deployment (CD)
- Automatically deploy working code
- Build Docker images and push to registry
- Create releases with version tags

---

## Prerequisites

1. **GitHub Account** (free at https://github.com)
2. **Repository** with your code
3. **Docker Hub Account** (optional, for image publishing)

---

## Quick Setup (5 Minutes)

### Step 1: Copy Workflow Files

```bash
# Copy the .github directory to your project root
cp -r GitHub-Actions-CI-CD/.github /path/to/your/project/

# Or manually create the structure:
# .github/workflows/
#   ├── ci-cd-pipeline.yml    # Main CI/CD pipeline
#   ├── pr-validation.yml     # PR checks
#   └── release.yml           # Release automation
```

### Step 2: Configure Repository Secrets

For Docker Hub publishing (optional):

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these secrets:

| Secret Name | Value | Required? |
|-------------|-------|-----------|
| `DOCKER_USERNAME` | Your Docker Hub username | Only for Docker push |
| `DOCKER_PASSWORD` | Your Docker Hub password/token | Only for Docker push |
| `SLACK_WEBHOOK_URL` | Slack webhook for notifications | Optional |

### Step 3: Push to GitHub

```bash
git add .github/
git commit -m "Add GitHub Actions CI/CD pipeline"
git push origin main
```

### Step 4: Watch It Run!

1. Go to your repository on GitHub
2. Click **Actions** tab
3. You should see the workflow running!

---

## Workflow Overview

### 1. Main CI/CD Pipeline (`ci-cd-pipeline.yml`)

**Triggers:**
- Push to `main` branch
- Pull requests
- Every Sunday at 2 AM (scheduled)
- Manual trigger (workflow_dispatch)

**Jobs:**

| Job | Description | Platforms |
|-----|-------------|-----------|
| `test-stage1-bash` | Tests Bash script with ShellCheck | Ubuntu |
| `test-stage1-powershell` | Tests PowerShell script | Windows |
| `test-stage2-python` | Runs Python tests with pytest | Ubuntu, Windows, macOS |
| `test-stage3-docker` | Builds and tests Docker image | Ubuntu |
| `build-and-push` | Pushes Docker image to registry | Ubuntu |
| `notify` | Sends completion notification | Ubuntu |

### 2. PR Validation (`pr-validation.yml`)

**Triggers:**
- Pull requests to `main` branch

**Jobs:**
- Quick syntax checks
- Python linting (ruff)
- Type checking (mypy)
- Docker build test

**Purpose:** Fast feedback on PRs before merging

### 3. Release Workflow (`release.yml`)

**Triggers:**
- Push of version tags (e.g., `v2.0.0`)

**Jobs:**
- Creates GitHub Release
- Builds multi-arch Docker images
- Pushes to Docker Hub

---

## Understanding the Workflows

### Visual Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        PUSH TO MAIN                         │
└────────────────────────────┬────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  Stage 1      │   │  Stage 2      │   │  Stage 3      │
│  Bash Tests   │   │  Python Tests │   │  Docker Tests │
│               │   │               │   │               │
│ • Syntax      │   │ • Type check  │   │ • Build       │
│ • ShellCheck  │   │ • Linting     │   │ • Run tests   │
│ • Execution   │   │ • Unit tests  │   │ • Security    │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                             ▼
                  ┌──────────────────┐
                  │  All Tests Pass? │
                  └────────┬─────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
        ┌──────────┐            ┌──────────┐
        │   YES    │            │    NO    │
        └────┬─────┘            └────┬─────┘
             │                       │
             ▼                       ▼
   ┌────────────────┐       ┌────────────────┐
   │ Build & Push   │       │    FAILED      │
   │ Docker Image   │       │    ❌          │
   │                │       └────────────────┘
   │ • Multi-arch   │
   │ • Tag: latest  │
   │ • Tag: version │
   └────────────────┘
```

---

## Workflow Configuration

### Manual Trigger with Options

You can manually trigger the workflow with specific options:

1. Go to **Actions** tab
2. Select **CI/CD Pipeline**
3. Click **Run workflow**
4. Choose which stage to run:
   - `all` (default) - Run everything
   - `stage1` - Only test Bash/PowerShell scripts
   - `stage2` - Only test Python implementation
   - `stage3` - Only test Docker containerization

### Matrix Testing

The Python tests run on multiple configurations:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    python-version: ['3.9', '3.10', '3.11', '3.12']
```

This ensures your code works on:
- **Operating Systems**: Linux, Windows, macOS
- **Python Versions**: 3.9 through 3.12

**Total test combinations**: 3 OS × 4 Python versions = **12 parallel jobs**

---

## Test Reports

### Viewing Test Results

1. Go to **Actions** tab
2. Click on a workflow run
3. Click on a specific job to see logs
4. Download artifacts for detailed reports

### Artifacts Generated

| Artifact | Contents |
|----------|----------|
| `bash-test-results` | JSON output from Bash tests |
| `python-test-results-*` | Coverage reports per OS/Python version |
| `docker-test-results` | Container logs and security scan |

### Code Coverage

Coverage reports are uploaded to Codecov (if configured):
- View coverage trends over time
- See which lines are not covered by tests
- Get coverage badges for your README

---

## Security Features

### Trivy Security Scan

The pipeline includes Trivy for vulnerability scanning:

```yaml
- name: Scan Docker image with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'system-monitor:test'
    severity: 'CRITICAL,HIGH'
```

This scans for:
- OS vulnerabilities (Alpine packages)
- Python package vulnerabilities
- Configuration issues

Results are uploaded to GitHub Security tab.

### Secret Scanning

GitHub automatically scans for secrets:
- API keys
- Passwords
- Tokens

If found, the push is blocked and you're notified.

---

## Common Use Cases

### Use Case 1: Developer Pushes Code

```bash
# Developer pushes to feature branch
git push origin feature/my-feature

# GitHub Actions automatically:
# 1. Runs PR validation
# 2. Comments on PR with test results
# 3. Blocks merge if tests fail
```

### Use Case 2: Merge to Main

```bash
# PR is merged to main
git checkout main
git merge feature/my-feature
git push origin main

# GitHub Actions automatically:
# 1. Runs full test suite
# 2. Builds Docker image
# 3. Pushes to Docker Hub
```

### Use Case 3: Create Release

```bash
# Tag a release
git tag -a v2.1.0 -m "Release version 2.1.0"
git push origin v2.1.0

# GitHub Actions automatically:
# 1. Creates GitHub Release
# 2. Builds multi-arch Docker images
# 3. Pushes with version tag
```

---

## Customization

### Adding a New Test

Edit `.github/workflows/ci-cd-pipeline.yml`:

```yaml
# Add a new job
my-custom-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    
    - name: My custom test
      run: |
        echo "Running custom test"
        # Your test commands here
```

### Changing Python Versions

Edit the matrix in `ci-cd-pipeline.yml`:

```yaml
strategy:
  matrix:
    python-version: ['3.9', '3.10', '3.11', '3.12', '3.13']  # Add 3.13
```

### Adding Slack Notifications

1. Create a Slack webhook: https://api.slack.com/messaging/webhooks
2. Add `SLACK_WEBHOOK_URL` to repository secrets
3. The workflow will automatically send notifications

---

## Troubleshooting

### Issue: Workflow Not Triggering

**Cause**: Workflow files must be in `.github/workflows/` on the default branch

**Solution**:
```bash
# Ensure files are committed to main
git add .github/
git commit -m "Add workflows"
git push origin main
```

### Issue: Docker Push Fails

**Cause**: Missing or incorrect Docker Hub credentials

**Solution**:
1. Verify secrets are set: Settings → Secrets → Actions
2. Check Docker Hub token hasn't expired
3. Ensure repository name is lowercase

### Issue: Tests Pass Locally but Fail in CI

**Common causes:**
- **Different OS**: CI runs on Ubuntu/Windows/macOS
- **Missing dependencies**: CI environment is fresh
- **Environment variables**: Not set in CI

**Debug:**
```yaml
- name: Debug environment
  run: |
    echo "Current directory: $(pwd)"
    echo "Files: $(ls -la)"
    echo "Environment: $(env)"
```

### Issue: Slow Builds

**Optimization:**
- Use `cache-from` and `cache-to` for Docker builds
- Use `actions/cache` for pip/uv dependencies
- Parallelize independent jobs

---

## GitHub Actions Concepts

### Key Terms

| Term | Explanation |
|------|-------------|
| **Workflow** | A configurable automated process (YAML file) |
| **Job** | A set of steps that execute on the same runner |
| **Step** | An individual task (can run commands or actions) |
| **Runner** | A server that runs your workflows (GitHub-hosted or self-hosted) |
| **Action** | A reusable extension (e.g., `actions/checkout@v4`) |
| **Event** | A specific activity that triggers a workflow (push, PR, etc.) |

### Event Triggers

```yaml
on:
  push:                    # Push to any branch
  pull_request:           # Pull request opened/updated
  schedule:               # Cron schedule
    - cron: '0 2 * * 0'   # Every Sunday 2 AM
  workflow_dispatch:      # Manual trigger
```

### Contexts

Access information about the workflow run:

```yaml
${{ github.repository }}    # Repository name
${{ github.ref }}           # Branch or tag
${{ github.sha }}           # Commit SHA
${{ secrets.MY_SECRET }}    # Repository secret
```

---

## Learning Resources

### GitHub Actions Documentation
- [Official Docs](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Marketplace](https://github.com/marketplace?type=actions) - Pre-built actions

### Best Practices
- [Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Caching Dependencies](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Matrix Builds](https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs)

---

## Workflow Badges

Add these badges to your main README.md:

```markdown
![CI/CD Pipeline](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/ci-cd-pipeline.yml/badge.svg)
![PR Validation](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/pr-validation.yml/badge.svg)
![Release](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/release.yml/badge.svg)
```

---

**Need Help?**
- Check the [GitHub Actions documentation](https://docs.github.com/en/actions)
- Look at example runs in the **Actions** tab
- Review workflow logs for error details