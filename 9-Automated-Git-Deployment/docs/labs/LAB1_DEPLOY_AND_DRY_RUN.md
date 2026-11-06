# Lab 1 — Deploy and Dry Run

**Goal:** run a deployment and preview one.

1. Dry run:
   ```bash
   ./git_deploy.sh --dry-run
   ```
   Expected: the preview lists what would happen and reminds you about rollback
   (skipped when `--no-rollback` is passed):
   ```
   [DRY RUN] Would roll back to the pre-deploy revision if the pull fails (disable with --no-rollback).
   ```
   Dry-run never mutates and exits 0. Note: the app directory must be a git work tree —
   anything else exits 1 with a clear message.
2. Real deploy (requires a git repo in the app dir; use a scratch path for testing):
   ```bash
   ./git_deploy.sh -a /path/to/app --backup-dir /path/to/backups
   ```
3. Help:
   ```bash
   ./git_deploy.sh -h
   ```
