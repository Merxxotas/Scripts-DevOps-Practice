# Lab 2 — Skip Flags and Audit

Run the complete block below from `9-Automated-Git-Deployment`, with Bash and Git
installed. It creates and removes a private local fixture; it does not deploy or
contact a remote. The dry-run audit example does write a log inside that fixture,
which is removed with the workspace. No caller shell settings are changed.

The checks compare the normal preview with each skip flag and the rollback
switch, then verify the private audit entry. Rollback is only a preview here:
`--no-rollback` disables automatic rollback on a real pull failure.

```bash
# LAB2_ISOLATED_WALKTHROUGH
(
    set -euo pipefail
    umask 077
    deploy="$PWD/git_deploy.sh"
    [[ -f "$deploy" ]] || { echo 'Run from the module directory' >&2; exit 1; }
    workspace="$(mktemp -d "${TMPDIR:-/tmp}/git-deploy-lab2.XXXXXX")"
    trap 'rm -rf -- "$workspace"' EXIT
    mkdir -p "$workspace/app" "$workspace/backups" "$workspace/bin" "$workspace/home"

    # Start with a clean environment, including Git configuration and shell hooks.
    env -i PATH=/usr/bin:/bin HOME="$workspace/home" WORKSPACE="$workspace" \
        DEPLOY="$deploy" bash --noprofile --norc <<'LAB2'
set -euo pipefail
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Lab GIT_AUTHOR_EMAIL=lab@example.invalid
export GIT_COMMITTER_NAME=Lab GIT_COMMITTER_EMAIL=lab@example.invalid
real_git="$(command -v git)"
export REAL_GIT="$real_git"

# Reject any Git operation beyond fixture setup and deployment preflight.
cat > "$WORKSPACE/bin/git" <<'GIT'
#!/bin/bash
case "$1" in
    init|add|commit|rev-parse|status|remote) exec "$REAL_GIT" "$@" ;;
    *) echo "blocked git $*" >> "$WORKSPACE/blocked"; exit 1 ;;
esac
GIT
for command in npm systemctl tar gzip; do
    # The sentinel expands WORKSPACE when invoked, not when written.
    # shellcheck disable=SC2016
    printf '#!/bin/bash\necho blocked >> "$WORKSPACE/blocked"\nexit 1\n' > "$WORKSPACE/bin/$command"
done
chmod +x "$WORKSPACE/bin/"*
export PATH="$WORKSPACE/bin:$PATH"

"$REAL_GIT" -C "$WORKSPACE/app" init -q
printf 'fixture\n' > "$WORKSPACE/app/file.txt"
"$REAL_GIT" -C "$WORKSPACE/app" add file.txt
"$REAL_GIT" -C "$WORKSPACE/app" -c core.hooksPath=/dev/null commit -qm fixture

preview() {
    bash "$DEPLOY" --app-dir "$WORKSPACE/app" --backup-dir "$WORKSPACE/backups" \
        --dry-run "$@"
}
base="$(preview)"
no_backup="$(preview --skip-backup)"
no_post="$(preview --skip-post-deploy)"
no_rollback="$(preview --no-rollback)"
audit="$(preview --audit-log "$WORKSPACE/audit.log")"
[[ "$base" == *'Would create backup'* && "$no_backup" != *'Would create backup'* ]]
[[ "$base" == *'Would run post-deploy'* && "$no_post" != *'Would run post-deploy'* ]]
[[ "$base" == *'Would roll back'* && "$no_rollback" == *'Rollback disabled'* ]]
[[ "$audit" == *'[DRY RUN]'* ]]
grep -F '[DRY RUN] Deploy planned' "$WORKSPACE/audit.log" >/dev/null
[[ ! -e "$WORKSPACE/blocked" ]]
[[ -z "$("$REAL_GIT" -C "$WORKSPACE/app" status --porcelain)" ]]
[[ -z "$(ls -A "$WORKSPACE/backups")" ]]
printf 'Lab 2 checks passed\n'
LAB2
)
```
