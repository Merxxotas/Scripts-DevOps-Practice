# 30. Automated Git Deployment — Scenarios & Labs

## Scenarios

- Already up to date → exit 0.
- Deploy → backup, pull, post-deploy, exit 0.
- Dry run → exit 0, no mutation.
- Guardrails → exit 1.
- Skip post-deploy.
- Pull failure → exit 2.
- Audit log.

## Labs

See `9-Automated-Git-Deployment/docs/labs/`:
- LAB1_DEPLOY_AND_DRY_RUN.md
- LAB2_SKIP_FLAGS_AND_AUDIT.md
- LAB3_GUARDRAILS_AND_EXIT_CODES.md