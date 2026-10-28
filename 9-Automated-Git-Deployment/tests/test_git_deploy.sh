#!/bin/bash
# ==============================================================================
# Test Suite: test_git_deploy.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/git_deploy.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_git_deploy.XXXXXX")"
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
# args handling
case "$1" in
    fetch)
        if [[ -f "$TEST_SANDBOX/git_fetch_fail" ]]; then exit 1; fi
        exit 0
        ;;
    rev-parse)
        if [[ "$2" == "@" ]]; then
            cat "$TEST_SANDBOX/git_rev_local" 2>/dev/null || echo "local123"
        elif [[ "$2" == "@{u}" ]]; then
            cat "$TEST_SANDBOX/git_rev_remote" 2>/dev/null || echo "remote123"
        else
            echo "rev"
        fi
        exit 0
        ;;
    pull)
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
echo "tar called" >> "$TEST_SANDBOX/tar_calls" 2>/dev/null || true
exit 0
EOF
chmod +x "$FAKE_BIN/tar"

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
    # default app dir
    rm -rf "$TEST_SANDBOX/appdir"
    mkdir -p "$TEST_SANDBOX/appdir"
}

run_deploy() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0
    # point app-dir to sandbox appdir unless overridden via args
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

# Summary
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS"
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

if [[ "$FAILED_TESTS" -gt 0 ]]; then exit 1; fi
exit 0