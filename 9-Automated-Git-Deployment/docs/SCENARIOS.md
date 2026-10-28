# Scenarios — Automated Git Deployment

## Scenario 1: Already up to date

```bash
./git_deploy.sh
# → "✓ Already up to date" exit 0
```

## Scenario 2: Deploy

```bash
./git_deploy.sh
# → backup, pull, post-deploy, exit 0
```

## Scenario 3: Dry run

```bash
./git_deploy.sh --dry-run
# → preview, no mutation, exit 0
```

## Scenario 4: Guardrails

```bash
./git_deploy.sh -a /          # exit 1
./git_deploy.sh -b "bad branch"  # exit 1
```

## Scenario 5: Skip post-deploy

```bash
./git_deploy.sh --skip-post-deploy
```

## Scenario 6: Pull failure

```bash
# (simulated) → exit 2
```

## Scenario 7: Audit log

```bash
./git_deploy.sh --audit-log /tmp/deploy.audit
```