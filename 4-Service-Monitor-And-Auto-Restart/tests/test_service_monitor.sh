#!/bin/bash
# ==============================================================================
# Test Suite: test_service_monitor.sh
# Description: Automated integration and unit test suite for service_monitor.sh.
#              Every test drives the public interface: flags, exit codes and
#              emitted files. All activity happens under a temp dir; the
#              systemctl binary is stubbed so no real service is touched.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/service_monitor.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_service_monitor.XXXXXX")"
FAKE_BIN="$TEST_SANDBOX/bin"
mkdir -p "$FAKE_BIN"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

LAST_STDOUT=""
LAST_STDERR=""
LAST_EXIT_CODE=0

# Build a fake systemctl that is controlled by files in the sandbox.
cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/bin/bash
# Fake systemctl controlled by $TEST_SANDBOX state files.
# Service name is the last argument.
svc="${!#}"
case "$1" in
    show)
        if [[ -f "$TEST_SANDBOX/${svc}.installed" ]]; then
            echo "loaded"
        else
            echo "not-found"
        fi
        exit 0
        ;;
    is-active)
        if [[ -f "$TEST_SANDBOX/${svc}.active" ]]; then
            exit 0
        else
            exit 3
        fi
        ;;
    restart)
        if [[ -f "$TEST_SANDBOX/${svc}.restart_fail" ]]; then
            exit 1
        fi
        touch "$TEST_SANDBOX/${svc}.active"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$FAKE_BIN/systemctl"

# Also stub logger to a no-op.
cat > "$FAKE_BIN/logger" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$FAKE_BIN/logger"

export TEST_SANDBOX
export PATH="$FAKE_BIN:$PATH"

setup() {
    rm -rf "$TEST_SANDBOX"/*.installed "$TEST_SANDBOX"/*.active "$TEST_SANDBOX"/*.restart_fail
    rm -f "$TEST_SANDBOX/stdout.txt" "$TEST_SANDBOX/stderr.txt"
}

run_monitor() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0

    "$MONITOR_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

    LAST_STDOUT="$(cat "$stdout_file" 2>/dev/null || true)"
    LAST_STDERR="$(cat "$stderr_file" 2>/dev/null || true)"
    LAST_EXIT_CODE="$exit_code"
}

assert_equals() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (expected '%s', got '%s')\n" "$RED" "$RESET" "$label" "$expected" "$actual" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (missing '%s')\n" "$RED" "$RESET" "$label" "$needle" >&2
        ((FAILED_TESTS++)) || true
    fi
}

assert_file_exists() {
    local path="$1" label="$2"
    if [[ -f "$path" ]]; then
        printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$label"
        ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b %s (file missing: %s)\n" "$RED" "$RESET" "$label" "$path" >&2
        ((FAILED_TESTS++)) || true
    fi
}

# ---------- tests ----------

# Test 1: help
setup
run_monitor -h
assert_equals 0 "$LAST_EXIT_CODE" "Test 1a: -h exits 0"
assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"

# Test 2: invalid service name
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s "bad/name"
assert_equals 1 "$LAST_EXIT_CODE" "Test 2: invalid service name exits 1"

# Test 3: service not found
setup
run_monitor -s nginx
assert_equals 1 "$LAST_EXIT_CODE" "Test 3: missing service exits 1"

# Test 4: running service (no restart)
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.active"
run_monitor -s nginx
assert_equals 0 "$LAST_EXIT_CODE" "Test 4a: running service exits 0"
assert_contains "$LAST_STDOUT" "is running" "Test 4b: running message"

# Test 5: restart success
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx --retry-delay 0
assert_equals 0 "$LAST_EXIT_CODE" "Test 5a: restart success exits 0"
assert_contains "$LAST_STDOUT" "restarted successfully" "Test 5b: restarted message"
# active file created
assert_file_exists "$TEST_SANDBOX/nginx.active" "Test 5c: service marked active"

# Test 6: restart failure
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.restart_fail"
run_monitor -s nginx -r 2 --retry-delay 0
assert_equals 2 "$LAST_EXIT_CODE" "Test 6a: restart failure exits 2"
assert_contains "$LAST_STDERR" "Failed to restart" "Test 6b: failure message"

# Test 7: dry-run
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx --dry-run
assert_equals 0 "$LAST_EXIT_CODE" "Test 7a: dry-run exits 0"
assert_contains "$LAST_STDOUT" "DRY RUN" "Test 7b: dry-run label"
# no active file created
if [[ -f "$TEST_SANDBOX/nginx.active" ]]; then
    printf "%b[FAIL]%b Test 7c: dry-run created active file\n" "$RED" "$RESET" >&2
    ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 7c: dry-run did not mutate\n" "$GREEN" "$RESET"
    ((PASSED_TESTS++)) || true
fi

# Test 8: bad max-retries
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx -r 0
assert_equals 1 "$LAST_EXIT_CODE" "Test 8: zero max-retries exits 1"

# Test 9: bad retry-delay
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx --retry-delay -1
assert_equals 1 "$LAST_EXIT_CODE" "Test 9: negative retry-delay exits 1"

# Test 10: audit log
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.active"
audit="$TEST_SANDBOX/audit.log"
run_monitor -s nginx --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 10a: audit run exits 0"
assert_file_exists "$audit" "Test 10b: audit file created"

# Test 11: verbose
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.active"
run_monitor -s nginx -v
assert_equals 0 "$LAST_EXIT_CODE" "Test 11: verbose exits 0"

# Test 12: unknown option
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor --bogus
assert_equals 1 "$LAST_EXIT_CODE" "Test 12: unknown option exits 1"

# Summary
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS" 
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

if [[ "$FAILED_TESTS" -gt 0 ]]; then exit 1; fi
exit 0