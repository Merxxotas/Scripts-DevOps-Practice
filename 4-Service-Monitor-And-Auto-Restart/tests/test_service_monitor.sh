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

# Test 13: --json outputs valid JSON (running)
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.active"
run_monitor -s nginx --json
assert_equals 0 "$LAST_EXIT_CODE" "Test 13a: --json exits 0"
assert_contains "$LAST_STDOUT" '"outcome": "running"' "Test 13b: json outcome running"
assert_contains "$LAST_STDOUT" '"service": "nginx"' "Test 13c: json service"

# Test 14: --json dry-run
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx --dry-run --json
assert_equals 0 "$LAST_EXIT_CODE" "Test 14a: --json dry-run exits 0"
assert_contains "$LAST_STDOUT" '"outcome": "dry-run"' "Test 14b: json dry-run outcome"

# Test 15: --csv outputs header + row
setup
touch "$TEST_SANDBOX/nginx.installed" "$TEST_SANDBOX/nginx.active"
run_monitor -s nginx --csv
assert_equals 0 "$LAST_EXIT_CODE" "Test 15a: --csv exits 0"
assert_contains "$LAST_STDOUT" 'service,max_retries,retry_delay' "Test 15b: csv header"
assert_contains "$LAST_STDOUT" 'running' "Test 15c: csv outcome"

# Test 16: --json and --csv mutually exclusive
setup
touch "$TEST_SANDBOX/nginx.installed"
run_monitor -s nginx --json --csv
assert_equals 1 "$LAST_EXIT_CODE" "Test 16: mutual exclusion exits 1"

# Run only the new, recognized lab entry points, never the old host commands.
run_lab() {
    local number="$1" doc="$2" status=0 expected extracted
    expected="bash docs/labs/run_service_monitor_lab.sh $number"
    extracted=$(awk '/^```bash$/ { getline; print }' "$SCRIPT_DIR/docs/labs/$doc")
    : > "$TEST_SANDBOX/stdout.txt"
    : > "$TEST_SANDBOX/stderr.txt"
    if [[ "$extracted" == "$expected" && -f "$SCRIPT_DIR/docs/labs/run_service_monitor_lab.sh" ]]; then
        (cd "$SCRIPT_DIR"; bash docs/labs/run_service_monitor_lab.sh "$number") \
            > "$TEST_SANDBOX/stdout.txt" 2> "$TEST_SANDBOX/stderr.txt" || status=$?
    else
        status=1
        printf '%s\n' 'No recognized isolated walkthrough; did not run the lab.' \
            > "$TEST_SANDBOX/stderr.txt"
    fi
    LAST_STDOUT=$(< "$TEST_SANDBOX/stdout.txt")
    LAST_STDERR=$(< "$TEST_SANDBOX/stderr.txt")
    LAST_EXIT_CODE=$status
}

# Test 17: observation and dry run never request restart or notification.
lab_tmp="$TEST_SANDBOX/lab scratch"
mkdir -p "$lab_tmp/keep"
printf '%s\n' 'untouched' > "$lab_tmp/keep/service.log"
TMPDIR="$lab_tmp" run_lab 1 LAB1_MONITORING_AND_DRY_RUN.md
assert_equals 0 "$LAST_EXIT_CODE" 'Test 17a: Lab 1 exits 0'
lab_csv='service,max_retries,retry_delay,retries_used,outcome'
assert_equals "$lab_csv"$'\n"lab-running",3,5,0,"dry-run"\n'"$lab_csv"\
$'\n"lab-down",3,5,0,"dry-run"' "$LAST_STDOUT" 'Test 17b: both Lab 1 previews'
assert_equals '' "$LAST_STDERR" 'Test 17c: Lab 1 stderr is empty'
assert_equals "$lab_tmp/keep" "$(printf '%s\n' "$lab_tmp"/*)" 'Test 17d: Lab 1 cleans up'

# Test 18: recovery on the second attempt; a separate service exhausts its attempts.
TMPDIR="$lab_tmp" run_lab 2 LAB2_RESTART_AND_RETRIES.md
assert_equals 0 "$LAST_EXIT_CODE" 'Test 18a: Lab 2 verifies exit 2 and succeeds'
assert_equals "$lab_csv"$'\n"lab-recover",3,0,2,"restarted"\n'"$lab_csv"\
$'\n"lab-stuck",2,0,2,"failed"' "$LAST_STDOUT" 'Test 18b: simulated retry outcomes'
assert_equals $'\033[0;31m✗ Restart attempt 1/3 failed.\033[0m\n'\
$'\033[0;31m✗ Restart attempt 1/2 failed.\033[0m\n'\
$'\033[0;31m✗ Restart attempt 2/2 failed.\033[0m\n'\
$'\033[0;31m✗ Failed to restart service \'lab-stuck\' after 2 attempt(s).\033[0m' \
    "$LAST_STDERR" 'Test 18c: exact retry diagnostics'
assert_equals "$lab_tmp/keep" "$(printf '%s\n' "$lab_tmp"/*)" 'Test 18d: Lab 2 cleans up'
assert_equals 'untouched' "$(< "$lab_tmp/keep/service.log")" 'Test 18e: existing log unchanged'

# Test 19: a setup tool succeeds but leaves the private service manager disabled.
mkdir "$TEST_SANDBOX/lab-fault-bin"
cat > "$TEST_SANDBOX/lab-fault-bin/chmod" <<'EOF'
#!/bin/bash
command -p chmod u+x logger
EOF
chmod u+x "$TEST_SANDBOX/lab-fault-bin/chmod"
PATH="$TEST_SANDBOX/lab-fault-bin:$PATH" TMPDIR="$lab_tmp" run_lab 2 LAB2_RESTART_AND_RETRIES.md
assert_equals 1 "$LAST_EXIT_CODE" 'Test 19a: missing private service manager aborts'
assert_equals '' "$LAST_STDOUT" 'Test 19b: no service monitor output'
assert_equals 'Lab requires both private service helpers.' "$LAST_STDERR" \
    'Test 19c: missing helper diagnostic'
assert_equals "$lab_tmp/keep" "$(printf '%s\n' "$lab_tmp"/*)" 'Test 19d: failed setup cleans up'
assert_equals 'untouched' "$(< "$lab_tmp/keep/service.log")" 'Test 19e: existing log unchanged'

# Summary
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS" 
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

if [[ "$FAILED_TESTS" -gt 0 ]]; then exit 1; fi
exit 0