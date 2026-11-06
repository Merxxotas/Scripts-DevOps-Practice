# Lab 3 — Guardrails and Exit Codes

**Goal:** verify the safety contract, including the backup gate and rollback.

1. Protected app dir:
   ```bash
   ./git_deploy.sh -a /; echo "exit=$?"
   ```
   Expected: exit 1.
2. Invalid branch:
   ```bash
   ./git_deploy.sh -b "bad branch"; echo "exit=$?"
   ```
   Expected: exit 1.
3. Help:
   ```bash
   ./git_deploy.sh -h; echo "exit=$?"
   ```
   Expected: exit 0.

## Failure safety (backup gate & rollback)

The steps below use a fully local, disposable setup (no network). Run them in a scratch
directory and remove it afterwards:

1. Build a bare remote, a seed clone and an app clone:
   ```bash
   WORK=$(mktemp -d)
   git init --bare -b main "$WORK/remote.git"
   git clone -q "$WORK/remote.git" "$WORK/seed"
   ( cd "$WORK/seed" && git config user.name Lab && git config user.email lab@example.com \
     && echo v1 > file.txt && git add . && git commit -qm init && git push -q origin HEAD:main )
   git clone -q "$WORK/remote.git" "$WORK/app"
   ```
2. Backup gate — make the backup impossible and watch the deploy refuse to run:
   ```bash
   touch "$WORK/blocker"
   ./git_deploy.sh -a "$WORK/app" --backup-dir "$WORK/blocker"; echo "exit=$?"
   ```
   Expected: exit 2, `Deploy aborted: backup failed.` — nothing is fetched, pulled or restarted.
3. Rollback on pull failure — diverge the local and remote histories, then deploy:
   ```bash
   ( cd "$WORK/app"  && git config user.name Lab && git config user.email lab@example.com \
     && git config pull.rebase false && echo local  > file.txt && git commit -qam local )
   ( cd "$WORK/seed" && echo remote > file.txt && git commit -qam remote \
     && git push -q origin HEAD:main )
   ./git_deploy.sh -a "$WORK/app" -b main --skip-post-deploy --backup-dir "$WORK/backups"; echo "exit=$?"
   ```
   Expected: exit 2, `Rolled back to <rev> (files restored; service NOT restarted).`
   ```bash
   git -C "$WORK/app" status --porcelain   # (empty — tree restored)
   ```
   With `--no-rollback` instead, the conflicted tree is left untouched for inspection.
4. Explicit repository URL mismatch:
   ```bash
   ./git_deploy.sh -a "$WORK/app" -r https://github.com/evil/other.git --dry-run; echo "exit=$?"
   ```
   Expected: exit 1, `does not match the configured origin` — exits before any mutation.
5. Cleanup:
   ```bash
   rm -rf "$WORK"
   ```
