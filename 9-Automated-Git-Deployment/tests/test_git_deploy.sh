#!/bin/bash
# ==============================================================================
# Test Suite: test_git_deploy.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/git_deploy.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_git_deploy.XXXXXX")"
trap 'rm -rf -- "$TEST_SANDBOX"' EXIT
FAKE_BIN="$TEST_SANDBOX/bin"
mkdir -p "$FAKE_BIN"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT_CODE=0

# Fake git
cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/bash
# Failure injection markers
if [[ -f "$TEST_SANDBOX/git_not_repo" ]]; then
    echo "fatal: not a git repository" >&2
    exit 128
fi
case "$1" in
    status)
        if [[ -f "$TEST_SANDBOX/git_status_dirty" ]]; then
            echo " M file.txt"
        fi
        exit 0
        ;;
    fetch)
        echo "fetch $2" >> "$TEST_SANDBOX/git_fetch_calls"
        if [[ -f "$TEST_SANDBOX/git_fetch_fail" ]]; then exit 1; fi
        exit 0
        ;;
    rev-parse)
        if [[ "$2" == "@" ]]; then
            cat "$TEST_SANDBOX/git_rev_local" 2>/dev/null || echo "local123"
        elif [[ "$2" == "@{u}" ]]; then
            cat "$TEST_SANDBOX/git_rev_remote" 2>/dev/null || echo "remote123"
        elif [[ "$2" == "--is-inside-work-tree" ]]; then
            echo "true"
        else
            echo "rev"
        fi
        exit 0
        ;;
    remote)
        # remote get-url origin
        if [[ -f "$TEST_SANDBOX/git_origin_url" ]]; then
            cat "$TEST_SANDBOX/git_origin_url"
            exit 0
        fi
        exit 1
        ;;
    reset)
        echo "reset $2 $3" >> "$TEST_SANDBOX/git_reset_calls"
        if [[ -f "$TEST_SANDBOX/git_reset_fail" ]]; then exit 1; fi
        exit 0
        ;;
    pull)
        echo "pull $2 $3" >> "$TEST_SANDBOX/git_pull_calls"
        if [[ -f "$TEST_SANDBOX/git_pull_fail" ]]; then exit 1; fi
        exit 0
        ;;
    stash)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$FAKE_BIN/git"

# Fake tar
cat > "$FAKE_BIN/tar" <<'EOF'
#!/bin/bash
if [[ -f "$TEST_SANDBOX/tar_fail" ]]; then exit 1; fi
echo "tar called" >> "$TEST_SANDBOX/tar_calls" 2>/dev/null || true
# create the -f target so downstream gzip verification has a file
prev=""
for arg in "$@"; do
    if [[ "$prev" =~ ^-[a-zA-Z]*f$ ]]; then touch "$arg"; fi
    prev="$arg"
done
exit 0
EOF
chmod +x "$FAKE_BIN/tar"

# Fake gzip (deploy backup verification uses `gzip -t`)
cat > "$FAKE_BIN/gzip" <<'EOF'
#!/bin/bash
if [[ -f "$TEST_SANDBOX/gzip_fail" ]]; then exit 1; fi
# verify shape: gzip -t <file>
file="${*: -1}"
if [[ ! -f "$file" ]]; then echo "gzip: $file: No such file or directory" >&2; exit 1; fi
exit 0
EOF
chmod +x "$FAKE_BIN/gzip"

# Fake npm
cat > "$FAKE_BIN/npm" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$FAKE_BIN/npm"

# Fake systemctl
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$FAKE_BIN/systemctl"

# Fake mkdir (real is fine, but ensure PATH)
export TEST_SANDBOX
export PATH="$FAKE_BIN:$PATH"

setup() {
    rm -f "$TEST_SANDBOX"/git_fetch_fail "$TEST_SANDBOX"/git_pull_fail "$TEST_SANDBOX"/tar_calls "$TEST_SANDBOX"/stdout.txt "$TEST_SANDBOX"/stderr.txt
    rm -f "$TEST_SANDBOX"/git_rev_local "$TEST_SANDBOX"/git_rev_remote
    rm -f "$TEST_SANDBOX"/git_fetch_calls "$TEST_SANDBOX"/git_pull_calls "$TEST_SANDBOX"/git_reset_calls
    rm -f "$TEST_SANDBOX"/git_not_repo "$TEST_SANDBOX"/git_origin_url "$TEST_SANDBOX"/git_reset_fail
    rm -f "$TEST_SANDBOX"/tar_fail "$TEST_SANDBOX"/gzip_fail "$TEST_SANDBOX"/git_status_dirty
    # default app dir
    rm -rf "$TEST_SANDBOX/appdir"
    mkdir -p "$TEST_SANDBOX/appdir"
}

run_deploy() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0
    # keep the suite hermetic: never write to the real default /backup/deployments
    if [[ " $* " != *" --backup-dir "* && " $* " != *" --skip-backup "* ]]; then
        set -- "$@" --backup-dir "$TEST_SANDBOX/backups"
    fi
    "$DEPLOY_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    LAST_STDOUT="$(cat "$stdout_file" 2>/dev/null || true)"
    LAST_STDERR="$(cat "$stderr_file" 2>/dev/null || true)"
    LAST_EXIT_CODE="$exit_code"
}

assert_equals() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (expected '%s', got '%s')\n" "$RED" "$RESET" "$label" "$expected" "$actual" >&2; ((FAILED_TESTS++)) || true
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (missing '%s')\n" "$RED" "$RESET" "$label" "$needle" >&2; ((FAILED_TESTS++)) || true
    fi
}

assert_file_exists() {
    local path="$1" label="$2"
    if [[ -f "$path" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (file missing: %s)\n" "$RED" "$RESET" "$label" "$path" >&2; ((FAILED_TESTS++)) || true
    fi
}

# ---------- tests ----------

# Test 1: help
setup
run_deploy -h
assert_equals 0 "$LAST_EXIT_CODE" "Test 1a: -h exits 0"
assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"

# Test 2: invalid app dir (nonexistent)
setup
run_deploy -a "$TEST_SANDBOX/nope"
assert_equals 1 "$LAST_EXIT_CODE" "Test 2: missing app dir exits 1"

# Test 3: protected app dir
setup
run_deploy -a /
assert_equals 1 "$LAST_EXIT_CODE" "Test 3: protected app dir exits 1"

# Test 4: invalid branch
setup
run_deploy -a "$TEST_SANDBOX/appdir" -b "bad branch"
assert_equals 1 "$LAST_EXIT_CODE" "Test 4: invalid branch exits 1"

# Test 5: dry-run
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
run_deploy -a "$TEST_SANDBOX/appdir" --dry-run
assert_equals 0 "$LAST_EXIT_CODE" "Test 5a: dry-run exits 0"
assert_contains "$LAST_STDOUT" "DRY RUN" "Test 5b: dry-run label"

# Test 6: up-to-date
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 0 "$LAST_EXIT_CODE" "Test 6a: up-to-date exits 0"
assert_contains "$LAST_STDOUT" "Already up to date" "Test 6b: up-to-date message"

# Test 7: deploy (behind)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 0 "$LAST_EXIT_CODE" "Test 7a: deploy exits 0"
assert_contains "$LAST_STDOUT" "Code updated" "Test 7b: updated message"

# Test 8: backup created
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 0 "$LAST_EXIT_CODE" "Test 8a: deploy exits 0"
# tar_calls should exist
if [[ -f "$TEST_SANDBOX/tar_calls" ]]; then
    printf "%b[PASS]%b Test 8b: backup created\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
else
    printf "%b[FAIL]%b Test 8b: backup not created\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
fi

# Test 9: skip-backup
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
rm -f "$TEST_SANDBOX/tar_calls"
run_deploy -a "$TEST_SANDBOX/appdir" --skip-backup
assert_equals 0 "$LAST_EXIT_CODE" "Test 9a: skip-backup exits 0"
if [[ -f "$TEST_SANDBOX/tar_calls" ]]; then
    printf "%b[FAIL]%b Test 9b: backup created despite skip\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 9b: no backup with skip\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 10: pull failure -> exit 2
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 2 "$LAST_EXIT_CODE" "Test 10a: pull failure exits 2"
assert_contains "$LAST_STDERR" "Git pull failed" "Test 10b: pull failure message"

# Test 11: fetch failure -> recorded (still maybe exit 2)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_fetch_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
# fetch failed -> FAILED_COUNT>0 -> up-to-date check: remote_rev empty != local -> deploy path; pull succeeds -> exit 0? Actually FAILED_COUNT>0 leads exit 2 at summary only if pull path. pull path summary checks FAILED_COUNT. So exit 2.
assert_equals 2 "$LAST_EXIT_CODE" "Test 11: fetch failure exits 2"

# Test 12: audit log
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
audit="$TEST_SANDBOX/audit.log"
run_deploy -a "$TEST_SANDBOX/appdir" --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 12a: audit run exits 0"
assert_file_exists "$audit" "Test 12b: audit file created"

# Test 13: verbose
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
run_deploy -a "$TEST_SANDBOX/appdir" -v
assert_equals 0 "$LAST_EXIT_CODE" "Test 13: verbose exits 0"

# Test 14: skip-post-deploy
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
# create package.json in appdir
echo "{}" > "$TEST_SANDBOX/appdir/package.json"
run_deploy -a "$TEST_SANDBOX/appdir" --skip-post-deploy
assert_equals 0 "$LAST_EXIT_CODE" "Test 14: skip-post-deploy exits 0"

# Test 15: unknown option
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
run_deploy --bogus
assert_equals 1 "$LAST_EXIT_CODE" "Test 15: unknown option exits 1"

# ---------- failure-safety: backup gate, rollback, repo-url verify (2026-11-06) ----------

# Test 16: backup failure aborts deploy (no fetch, exit 2)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/tar_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 2 "$LAST_EXIT_CODE" "Test 16a: backup failure exits 2"
assert_contains "$LAST_STDERR" "aborted" "Test 16b: deploy aborted message"
if [[ -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 16c: fetch happened despite backup failure\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 16c: no fetch after backup failure\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 17: backup verification failure aborts deploy (no fetch, exit 2)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/gzip_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 2 "$LAST_EXIT_CODE" "Test 17a: verification failure exits 2"
assert_contains "$LAST_STDERR" "aborted" "Test 17b: deploy aborted message"
if [[ -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 17c: fetch happened despite verification failure\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 17c: no fetch after verification failure\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 18: backup failure still emits a JSON failure envelope
setup
touch "$TEST_SANDBOX/tar_fail"
run_deploy -a "$TEST_SANDBOX/appdir" --json
assert_equals 2 "$LAST_EXIT_CODE" "Test 18a: backup failure exits 2"
assert_contains "$LAST_STDOUT" '"result": "failed"' "Test 18b: JSON result failed"
assert_contains "$LAST_STDOUT" '"failed": 1' "Test 18c: JSON failed count 1"

# Test 19: pull failure triggers rollback to pre-deploy revision (automatic)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 2 "$LAST_EXIT_CODE" "Test 19a: pull failure exits 2"
assert_contains "$LAST_STDOUT" "Rolled back" "Test 19b: rollback message printed"
assert_contains "$(cat "$TEST_SANDBOX/git_reset_calls" 2>/dev/null || true)" "reset --hard local1" "Test 19c: reset --hard to pre-deploy rev"

# Test 19d: rollback reported in JSON result
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail"
run_deploy -a "$TEST_SANDBOX/appdir" --json
assert_contains "$LAST_STDOUT" '"result": "rolled-back"' "Test 19d: JSON result rolled-back"

# Test 19e: rollback is audited
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail"
run_deploy -a "$TEST_SANDBOX/appdir" --audit-log "$TEST_SANDBOX/audit.log"
assert_contains "$(cat "$TEST_SANDBOX/audit.log" 2>/dev/null || true)" "Rolled back" "Test 19e: audit records rollback"

# Test 20: --no-rollback leaves the tree as-is
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail"
run_deploy -a "$TEST_SANDBOX/appdir" --no-rollback
assert_equals 2 "$LAST_EXIT_CODE" "Test 20a: pull failure exits 2"
assert_contains "$LAST_STDOUT" "Rollback disabled" "Test 20b: rollback disabled message"
if [[ -f "$TEST_SANDBOX/git_reset_calls" ]]; then
    printf "%b[FAIL]%b Test 20c: reset happened despite --no-rollback\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 20c: no reset with --no-rollback\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 21: rollback failure is reported, not swallowed
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
touch "$TEST_SANDBOX/git_pull_fail" "$TEST_SANDBOX/git_reset_fail"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 2 "$LAST_EXIT_CODE" "Test 21a: pull failure exits 2"
assert_contains "$LAST_STDERR" "Rollback failed" "Test 21b: rollback failure message"

# Test 22: explicit -r matches git@ origin against https flag (cross-form)
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" -r "git@github.com:acme/widgets.git"
assert_equals 0 "$LAST_EXIT_CODE" "Test 22: cross-form origin match proceeds"

# Test 23: explicit -r is case-insensitive and ignores .git suffix
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" -r "HTTPS://GITHUB.COM/Acme/Widgets"
assert_equals 0 "$LAST_EXIT_CODE" "Test 23: normalized origin match proceeds"

# Test 24: explicit -r mismatch aborts BEFORE any backup or fetch
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" -r "https://github.com/evil/other.git"
assert_equals 1 "$LAST_EXIT_CODE" "Test 24a: origin mismatch exits 1"
assert_contains "$LAST_STDERR" "does not match" "Test 24b: mismatch message"
if [[ -f "$TEST_SANDBOX/tar_calls" || -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 24c: mutation happened before origin check\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 24c: no backup or fetch on mismatch\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 25: origin with embedded credentials is not leaked in the mismatch error
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://secret-token@github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" -r "https://github.com/evil/other.git"
combined_out="$LAST_STDOUT$LAST_STDERR"
if [[ "$combined_out" == *"secret-token"* ]]; then
    printf "%b[FAIL]%b Test 25: credentials leaked in output\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 25: credentials not leaked\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 26: explicit -r with no origin configured aborts with a clear error
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
# no git_origin_url file -> fake git exits 1 for remote get-url origin
run_deploy -a "$TEST_SANDBOX/appdir" -r "https://github.com/acme/widgets.git"
assert_equals 1 "$LAST_EXIT_CODE" "Test 26a: missing origin exits 1"
assert_contains "$LAST_STDERR" "origin" "Test 26b: missing origin message"

# Test 27: without -r, output reports the actual origin (truthful, not decorative)
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" --json
assert_equals 0 "$LAST_EXIT_CODE" "Test 27a: run exits 0"
assert_contains "$LAST_STDOUT" '"repo_url": "https://github.com/acme/widgets.git"' "Test 27b: JSON reports actual origin"

# Test 28: without -r, credentials in origin are scrubbed from output
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://secret-token@github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" --json
combined_out="$LAST_STDOUT$LAST_STDERR"
if [[ "$combined_out" == *"secret-token"* ]]; then
    printf "%b[FAIL]%b Test 28: credentials leaked in JSON output\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 28: credentials scrubbed from output\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 29: not a git repository -> exit 1 with clear message (before backup/fetch)
setup
touch "$TEST_SANDBOX/git_not_repo"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 1 "$LAST_EXIT_CODE" "Test 29a: not a git repo exits 1"
assert_contains "$LAST_STDERR" "not a git repository" "Test 29b: clear not-a-repo message"
if [[ -f "$TEST_SANDBOX/tar_calls" || -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 29c: mutation happened before repo check\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 29c: no backup or fetch on non-repo\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 30: dry-run mentions rollback behavior
setup
run_deploy -a "$TEST_SANDBOX/appdir" --dry-run
assert_contains "$LAST_STDOUT" "roll back" "Test 30: dry-run mentions rollback"

# Test 31: explicit -r with credentials and a MATCHING origin does not leak them into output
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
echo "https://secret-token@github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" -r "https://secret-token@github.com/acme/widgets.git" --json
combined_out="$LAST_STDOUT$LAST_STDERR"
assert_equals 0 "$LAST_EXIT_CODE" "Test 31a: matching origin proceeds"
if [[ "$combined_out" == *"secret-token"* ]]; then
    printf "%b[FAIL]%b Test 31b: credentials leaked in output\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 31b: credentials scrubbed from output\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 32: dirty worktree (tracked) aborts BEFORE backup/fetch (protects rollback from destroying edits)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
touch "$TEST_SANDBOX/git_status_dirty"
run_deploy -a "$TEST_SANDBOX/appdir"
assert_equals 1 "$LAST_EXIT_CODE" "Test 32a: dirty worktree exits 1"
assert_contains "$LAST_STDERR" "uncommitted" "Test 32b: dirty worktree clear message"
if [[ -f "$TEST_SANDBOX/tar_calls" || -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 32c: mutation happened before dirty check\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 32c: no backup or fetch on dirty worktree\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 33: nested backup dir (BackupDir inside AppDir) aborts BEFORE backup/fetch
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
mkdir -p "$TEST_SANDBOX/appdir/backups-nested"
run_deploy -a "$TEST_SANDBOX/appdir" --backup-dir "$TEST_SANDBOX/appdir/backups-nested"
assert_equals 1 "$LAST_EXIT_CODE" "Test 33a: nested backup dir exits 1"
assert_contains "$LAST_STDERR" "inside" "Test 33b: nested backup clear message"
if [[ -f "$TEST_SANDBOX/tar_calls" || -f "$TEST_SANDBOX/git_fetch_calls" ]]; then
    printf "%b[FAIL]%b Test 33c: mutation happened before nested check\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 33c: no backup or fetch on nested backup dir\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 34: no origin + no -r reports truthful empty repo_url (no seed placeholder)
setup
echo "same" > "$TEST_SANDBOX/git_rev_local"
echo "same" > "$TEST_SANDBOX/git_rev_remote"
# no git_origin_url file => fake git remote fails => origin missing
run_deploy -a "$TEST_SANDBOX/appdir" --dry-run --json
assert_equals 0 "$LAST_EXIT_CODE" "Test 34a: no-origin dry-run exits 0"
assert_contains "$LAST_STDOUT" '"repo_url": ""' "Test 34b: JSON reports empty (truthful) repo_url"
if [[ "$LAST_STDOUT" == *"company/myapp"* ]]; then
    printf "%b[FAIL]%b Test 34c: seed placeholder leaked\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 34c: no seed placeholder\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 35: successful backup is audited as verified (parity with PS)
setup
echo "local1" > "$TEST_SANDBOX/git_rev_local"
echo "remote2" > "$TEST_SANDBOX/git_rev_remote"
echo "https://github.com/acme/widgets.git" > "$TEST_SANDBOX/git_origin_url"
run_deploy -a "$TEST_SANDBOX/appdir" --audit-log "$TEST_SANDBOX/audit35.log" --skip-post-deploy
assert_equals 0 "$LAST_EXIT_CODE" "Test 35a: deploy exits 0"
assert_contains "$(cat "$TEST_SANDBOX/audit35.log" 2>/dev/null || true)" "Backup verified" "Test 35b: audit records backup verified"

# Test 36: run the published block in a disposable module with an enforcing proxy.
setup
lab="$SCRIPT_DIR/docs/labs/LAB2_SKIP_FLAGS_AND_AUDIT.md"
block="$TEST_SANDBOX/lab2.sh"
lab_root="$TEST_SANDBOX/lab-case"
mkdir -p "$lab_root/module" "$lab_root/tmp" "$lab_root/home" "$lab_root/hooks"
lab_root="$(cd "$lab_root" && pwd -P)"
awk '/^```bash$/ { blocks++; inside=1; next } /^```$/ { inside=0; next }
    inside { print } END { if (blocks != 1) exit 1 }' "$lab" > "$block" || true
# Validate the complete argument vector and canonical owned paths before forwarding.
{
    printf '#!/bin/bash\nset -euo pipefail\n'
    printf 'root=%q\nreal=%q\n' "$lab_root/tmp" "$DEPLOY_SCRIPT"
    cat <<'PROXY'
[[ $# -ge 5 && $1 == --app-dir && $3 == --backup-dir && $5 == --dry-run ]] || exit 90
app=$2 backup=$4 workspace=${2%/app}
[[ $workspace == "$root"/git-deploy-lab2.* && ${workspace#"$root"/} != */* ]] || exit 91
[[ -d $workspace && ! -L $workspace && ! -L $app && ! -L $backup ]] || exit 91
[[ $(cd "$workspace" && pwd -P) == "$workspace" ]] || exit 91
[[ $(cd "$app" && pwd -P) == "$workspace/app" ]] || exit 91
[[ $(cd "$backup" && pwd -P) == "$workspace/backups" ]] || exit 91
calls=${root%/tmp}/calls
if [[ -f $calls ]]; then
    [[ $(head -n 1 "$calls") == "$workspace" ]] || exit 92
else
    printf '%s\n' "$workspace" > "$calls"
fi
count=$(wc -l < "$calls" | tr -d ' ')
shift 5
case $count in
    1) [[ $# == 0 ]] ;;
    2) [[ $# == 1 && $1 == --skip-backup ]] ;;
    3) [[ $# == 1 && $1 == --skip-post-deploy ]] ;;
    4) [[ $# == 1 && $1 == --no-rollback ]] ;;
    5) [[ $# == 2 && $1 == --audit-log && $2 == "$workspace/audit.log" && ! -e $2 && ! -L $2 ]] ;;
    *) exit 93 ;;
esac || exit 93
printf 'call\n' >> "$calls"
exec bash "$real" --app-dir "$app" --backup-dir "$backup" --dry-run "$@"
PROXY
} > "$lab_root/module/git_deploy.sh"
chmod +x "$lab_root/module/git_deploy.sh"
printf '#!/bin/bash\necho hook >> %q\nexit 1\n' "$lab_root/forbidden" > "$lab_root/hooks/pre-commit"
chmod +x "$lab_root/hooks/pre-commit"
printf '[core]\n\thooksPath = %s\n' "$lab_root/hooks" > "$lab_root/home/.gitconfig"
printf '#!/bin/bash\necho startup >> %q\n' "$lab_root/forbidden" > "$lab_root/startup"
printf 'preexisting fixture\n' > "$lab_root/fixture"
chmod 640 "$lab_root/fixture"
cp -p "$lab_root/fixture" "$lab_root/fixture-copy"
fixture_before="$(perl -e '@s=stat($ARGV[0]); print "$s[2] $s[9]"' "$lab_root/fixture")"
lab_exit=1
lab_out=""
lab_err=""
# Refuse baseline unsafe text rather than ever executing it.
if [[ $(head -n 1 "$block") == '# LAB2_ISOLATED_WALKTHROUGH' ]]; then
    lab_exit=0
    (
        cd "$lab_root/module"
        export HOME="$lab_root/home" TMPDIR="$lab_root/tmp"
        export GIT_CONFIG_GLOBAL="$lab_root/home/.gitconfig" GIT_CONFIG_COUNT=1
        export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$lab_root/hooks"
        export GIT_DIR="$lab_root/not-a-repo" GIT_WORK_TREE="$lab_root"
        export BASH_ENV="$lab_root/startup"
        sentinel_function() { printf 'caller function\n'; }
        [[ "$(sentinel_function)" == 'caller function' ]]
        before_pwd="$PWD"; before_env="$(export -p)"; before_options="$(set +o; shopt -p || true)"
        before_functions="$(declare -f)"
        # shellcheck source=/dev/null
        source "$block"
        [[ "$PWD" == "$before_pwd" && "$(export -p)" == "$before_env" ]] &&
            [[ "$(set +o; shopt -p || true)" == "$before_options" ]] &&
            [[ "$(declare -f)" == "$before_functions" ]]
    ) > "$TEST_SANDBOX/lab.out" 2> "$TEST_SANDBOX/lab.err" || lab_exit=$?
    lab_out="$(cat "$TEST_SANDBOX/lab.out")"
    lab_err="$(cat "$TEST_SANDBOX/lab.err")"
fi
assert_equals 0 "$lab_exit" "Test 36a: isolated walkthrough and caller state"
assert_equals 'Lab 2 checks passed' "$lab_out" "Test 36b: walkthrough confirms checks"
assert_equals '' "$lab_err" "Test 36c: walkthrough has no stderr"
fixture_bytes=0
cmp -s "$lab_root/fixture" "$lab_root/fixture-copy" || fixture_bytes=$?
assert_equals 0 "$fixture_bytes" "Test 36d: fixture bytes unchanged"
assert_equals "$fixture_before" "$(perl -e '@s=stat($ARGV[0]); print "$s[2] $s[9]"' "$lab_root/fixture")" "Test 36e: fixture mode and mtime unchanged"
assert_equals '' "$(cat "$lab_root/forbidden" 2>/dev/null || true)" "Test 36f: hostile Git hook and shell startup not invoked"
assert_equals 6 "$(wc -l < "$lab_root/calls" 2>/dev/null | tr -d ' ' || true)" "Test 36h: five exact guarded dry-run invocations"
assert_equals '' "$(ls -A "$lab_root/tmp")" "Test 36g: owned workspace removed"

# Summary
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS"
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

if [[ "$FAILED_TESTS" -gt 0 ]]; then exit 1; fi
exit 0