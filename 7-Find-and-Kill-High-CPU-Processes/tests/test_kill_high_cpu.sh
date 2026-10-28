#!/bin/bash
# ==============================================================================
# Test Suite: test_kill_high_cpu.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KILLER_SCRIPT="$SCRIPT_DIR/kill_high_cpu.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_kill_high_cpu.XXXXXX")"
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

# Fake ps: prints lines from $TEST_SANDBOX/ps_output (format: "PID PPID PCPU COMM")
cat > "$FAKE_BIN/ps" <<'EOF'
#!/bin/bash
if [[ -f "$TEST_SANDBOX/ps_output" ]]; then
    cat "$TEST_SANDBOX/ps_output"
fi
exit 0
EOF
chmod +x "$FAKE_BIN/ps"

# Fake kill: succeeds unless $TEST_SANDBOX/kill_fail_<pid> exists
cat > "$FAKE_BIN/kill" <<'EOF'
#!/bin/bash
# args: [signal] pid  (e.g. -TERM 500, -0 500, -9 500)
pid="${!#}"
# kill -0 existence check
if [[ "$1" == "-0" ]]; then
    if grep -qx "$pid" "$TEST_SANDBOX/killed_pids" 2>/dev/null; then
        exit 1   # process gone
    fi
    # if a fail marker exists, process doesn't exist
    if [[ -f "$TEST_SANDBOX/kill_fail_${pid}" ]]; then
        exit 1
    fi
    exit 0
fi
# actual kill
if [[ -f "$TEST_SANDBOX/kill_fail_${pid}" ]]; then
    exit 1
fi
echo "$pid" >> "$TEST_SANDBOX/killed_pids" 2>/dev/null || true
exit 0
EOF
chmod +x "$FAKE_BIN/kill"

export TEST_SANDBOX
export PATH="$FAKE_BIN:$PATH"

setup() {
    rm -f "$TEST_SANDBOX"/ps_output "$TEST_SANDBOX"/killed_pids "$TEST_SANDBOX"/kill_fail_* "$TEST_SANDBOX"/stdout.txt "$TEST_SANDBOX"/stderr.txt
}

run_killer() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0
    "$KILLER_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
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
run_killer -h
assert_equals 0 "$LAST_EXIT_CODE" "Test 1a: -h exits 0"
assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"

# Test 2: invalid threshold (negative)
setup
echo "100 1 90.0 firefox" > "$TEST_SANDBOX/ps_output"
run_killer -t -5
assert_equals 1 "$LAST_EXIT_CODE" "Test 2: negative threshold exits 1"

# Test 3: non-numeric threshold
setup
echo "100 1 90.0 firefox" > "$TEST_SANDBOX/ps_output"
run_killer -t abc
assert_equals 1 "$LAST_EXIT_CODE" "Test 3: non-numeric threshold exits 1"

# Test 4: no candidates
setup
printf "1 0 1.0 init\n2 1 2.0 kthreadd\n" > "$TEST_SANDBOX/ps_output"
run_killer -t 50
assert_equals 0 "$LAST_EXIT_CODE" "Test 4a: no candidates exits 0"
assert_contains "$LAST_STDOUT" "No processes exceeding" "Test 4b: no-candidates message"

# Test 5: dry-run
setup
printf "100 1 90.0 firefox\n200 1 80.0 chrome\n" > "$TEST_SANDBOX/ps_output"
run_killer --dry-run
assert_equals 0 "$LAST_EXIT_CODE" "Test 5a: dry-run exits 0"
assert_contains "$LAST_STDOUT" "DRY RUN" "Test 5b: dry-run label"
# no kill recorded
if [[ -f "$TEST_SANDBOX/killed_pids" ]]; then
    printf "%b[FAIL]%b Test 5c: dry-run killed a process\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 5c: dry-run did not kill\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 6: guardrails exclude PID 1 and kernel threads
setup
printf "1 0 99.0 init\n2 1 90.0 [kthreadd]\n999 1 95.0 badproc\n" > "$TEST_SANDBOX/ps_output"
run_killer -t 50 --auto-kill
assert_equals 0 "$LAST_EXIT_CODE" "Test 6a: guardrails run exits 0"
# killed_pids should contain 999 only
if [[ -f "$TEST_SANDBOX/killed_pids" ]]; then
    kc=$(wc -l < "$TEST_SANDBOX/killed_pids")
    assert_equals "1" "$kc" "Test 6b: only one process killed (guardrails)"
    if grep -qx "999" "$TEST_SANDBOX/killed_pids"; then
        printf "%b[PASS]%b Test 6c: correct pid killed\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
    else
        printf "%b[FAIL]%b Test 6c: wrong pid killed\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
    fi
else
    printf "%b[FAIL]%b Test 6b: no kill recorded\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
fi

# Test 7: auto-kill success
setup
printf "500 1 88.0 runaway\n" > "$TEST_SANDBOX/ps_output"
run_killer -t 50 --auto-kill
assert_equals 0 "$LAST_EXIT_CODE" "Test 7a: auto-kill exits 0"
assert_contains "$LAST_STDOUT" "killed" "Test 7b: killed message"

# Test 8: kill failure -> exit 2
setup
printf "700 1 92.0 doomed\n" > "$TEST_SANDBOX/ps_output"
touch "$TEST_SANDBOX/kill_fail_700"
run_killer -t 50 --auto-kill
assert_equals 2 "$LAST_EXIT_CODE" "Test 8a: kill failure exits 2"
assert_contains "$LAST_STDERR" "Failed to kill" "Test 8b: failure message"

# Test 9: audit log
setup
printf "500 1 88.0 runaway\n" > "$TEST_SANDBOX/ps_output"
audit="$TEST_SANDBOX/audit.log"
run_killer -t 50 --auto-kill --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 9a: audit run exits 0"
assert_file_exists "$audit" "Test 9b: audit file created"

# Test 10: verbose
setup
printf "500 1 88.0 runaway\n" > "$TEST_SANDBOX/ps_output"
run_killer -t 50 --auto-kill -v
assert_equals 0 "$LAST_EXIT_CODE" "Test 10: verbose exits 0"

# Test 11: self/parent excluded (uses $$ and PPID guard)
setup
printf "%s 1 99.0 selfproc\n" "$$" > "$TEST_SANDBOX/ps_output"
run_killer -t 50 --auto-kill
assert_equals 0 "$LAST_EXIT_CODE" "Test 11a: self-only exits 0"
if [[ -f "$TEST_SANDBOX/killed_pids" ]]; then
    printf "%b[FAIL]%b Test 11b: self was killed\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 11b: self not killed\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 12: unknown option
setup
printf "500 1 88.0 runaway\n" > "$TEST_SANDBOX/ps_output"
run_killer --bogus
assert_equals 1 "$LAST_EXIT_CODE" "Test 12: unknown option exits 1"

# Summary
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS"
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

if [[ "$FAILED_TESTS" -gt 0 ]]; then exit 1; fi
exit 0