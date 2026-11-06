# 30. Automated Git Deployment — Scenarios & Labs

## Scenarios

- Already up to date → exit 0.
- Deploy → verified backup, pull, post-deploy, exit 0.
- Dry run → exit 0, no mutation (mentions rollback behavior).
- Guardrails → exit 1.
- Backup failure → `Deploy aborted: backup failed.` exit 2 — no fetch, no pull.
- Pull failure → automatic rollback to the pre-deploy revision, exit 2 (`--no-rollback` to
  leave the tree conflicted instead). JSON/CSV: `"result": "rolled-back"`.
- Explicit `-r` mismatch → exit 1, nothing runs (normalized comparison; credentials stripped).
- Not a git repository → exit 1 with a clear message.
- Skip post-deploy.
- Audit log (includes `Backup verified` and `Rolled back` entries).

## Labs

See `9-Automated-Git-Deployment/docs/labs/`:
- LAB1_DEPLOY_AND_DRY_RUN.md
- LAB2_SKIP_FLAGS_AND_AUDIT.md
- LAB3_GUARDRAILS_AND_EXIT_CODES.md — includes a fully local, disposable walk-through of the
  backup gate and the rollback (no network).
