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

## Scenario 6: Pull failure → automatic rollback

```bash
./git_deploy.sh
# → pull fails → "Rolled back to <rev> (files restored; service NOT restarted)." exit 2
# → disable with --no-rollback / -NoRollback
# → JSON/CSV: "result": "rolled-back"
```

## Scenario 7: Backup failure → deploy aborted

```bash
./git_deploy.sh --backup-dir /unwritable/path
# → "Deploy aborted: backup failed." exit 2 — no fetch, no pull, app untouched
```

## Scenario 8: Explicit repository URL mismatch

```bash
./git_deploy.sh -r https://github.com/evil/other.git
# → "Error: -r/--repo-url does not match the configured origin (...)" exit 1
# → no backup, no fetch — exits before any mutation
# → normalized comparison: git@github.com:acme/x.git ≡ https://github.com/acme/x(.git),
#   case-insensitive, credentials stripped from displayed output
```

## Scenario 9: Not a git repository

```bash
./git_deploy.sh -a /some/plain/directory
# → "Error: App directory '/some/plain/directory' is not a git repository." exit 1
```

## Scenario 10: Audit log

```bash
./git_deploy.sh --audit-log /tmp/deploy.audit
```