# Lab 2 — Skip Flags and Audit

**Goal:** exercise skip flags and audit logging.

1. Skip backup:
   ```bash
   ./git_deploy.sh --skip-backup
   ```
2. Skip post-deploy:
   ```bash
   ./git_deploy.sh --skip-post-deploy
   ```
3. Audit log:
   ```bash
   ./git_deploy.sh --audit-log /tmp/deploy.audit
   cat /tmp/deploy.audit
   ```