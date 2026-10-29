#!/bin/bash
# ==============================================================================
# Test Suite: test_k8s_monitor.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_SCRIPT="$SCRIPT_DIR/k8s_monitor.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_k8s_monitor.XXXXXX")"
FAKE_BIN="$TEST_SANDBOX/bin"
mkdir -p "$FAKE_BIN"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

LAST_STDOUT=""
LAST_EXIT_CODE=0

# Fake kubectl: prints $TEST_SANDBOX/kubectl_pods for `get pods`, records deleted
# pods and args to $TEST_SANDBOX/kubectl_deleted / kubectl_delete_args, and fails
# for pods listed in $TEST_SANDBOX/kubectl_delete_fail.
cat > "$FAKE_BIN/kubectl" <<'EOF'
#!/bin/bash
if [[ "$1" == "get" && "$2" == "pods" ]]; then
    if [[ -f "$TEST_SANDBOX/kubectl_pods" ]]; then
        cat "$TEST_SANDBOX/kubectl_pods"
    fi
    exit 0
fi
if [[ "$1" == "delete" && "$2" == "pod" ]]; then
    pod="$3"
    printf '%s %s\n' "$pod" "$*" >> "$TEST_SANDBOX/kubectl_delete_args" 2>/dev/null || true
    if [[ -f "$TEST_SANDBOX/kubectl_delete_fail" ]] && grep -qx "$pod" "$TEST_SANDBOX/kubectl_delete_fail" 2>/dev/null; then
        echo "error: not found" >&2
        exit 1
    fi
    echo "$pod" >> "$TEST_SANDBOX/kubectl_deleted" 2>/dev/null || true
    exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/kubectl"

export TEST_SANDBOX
export PATH="$FAKE_BIN:$PATH"

setup() {
    rm -f "$TEST_SANDBOX"/kubectl_pods "$TEST_SANDBOX"/kubectl_deleted \
          "$TEST_SANDBOX"/kubectl_delete_fail "$TEST_SANDBOX"/kubectl_delete_args \
          "$TEST_SANDBOX"/stdout.txt "$TEST_SANDBOX"/stderr.txt
}

run_k8s() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0
    "$K8S_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    LAST_STDOUT="$(cat "$stdout_file" 2>/dev/null || true)"
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
run_k8s -h
assert_equals 0 "$LAST_EXIT_CODE" "Test 1a: -h exits 0"
assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"

# Test 2: --help long form
setup
run_k8s --help
assert_equals 0 "$LAST_EXIT_CODE" "Test 2: --help exits 0"

# Test 3: kubectl missing -> exit 1
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s
# temporarily hide kubectl by emptying PATH (keep core utils)
PATH="/usr/bin:/bin" "$K8S_SCRIPT" >/dev/null 2>&1 || true
# replicate via run with PATH override not possible; instead assert binary check by removing fake
mv "$FAKE_BIN/kubectl" "$FAKE_BIN/kubectl.bak"
run_k8s
assert_equals 1 "$LAST_EXIT_CODE" "Test 3: kubectl missing exits 1"
mv "$FAKE_BIN/kubectl.bak" "$FAKE_BIN/kubectl"

# Test 4: invalid namespace (empty)
setup
run_k8s -n ""
assert_equals 1 "$LAST_EXIT_CODE" "Test 4: empty namespace exits 1"

# Test 5: invalid namespace (bad chars)
setup
run_k8s -n "Bad Name"
assert_equals 1 "$LAST_EXIT_CODE" "Test 5: bad namespace exits 1"

# Test 6: invalid label (empty)
setup
run_k8s -l ""
assert_equals 1 "$LAST_EXIT_CODE" "Test 6: empty label exits 1"

# Test 7: invalid threshold (negative)
setup
run_k8s -r -1
assert_equals 1 "$LAST_EXIT_CODE" "Test 7: negative threshold exits 1"

# Test 8: invalid threshold (non-numeric)
setup
run_k8s -r abc
assert_equals 1 "$LAST_EXIT_CODE" "Test 8: non-numeric threshold exits 1"

# Test 9: dry-run exits 0, no deletion
setup
printf 'pod-a|Running|5,\npod-b|Running|1,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s --dry-run
assert_equals 0 "$LAST_EXIT_CODE" "Test 9a: dry-run exits 0"
assert_contains "$LAST_STDOUT" "Dry run" "Test 9b: dry-run label"
assert_contains "$LAST_STDOUT" "would delete" "Test 9c: would delete shown"
# ensure no delete happened
if [[ -f "$TEST_SANDBOX/kubectl_deleted" ]]; then
    printf "%b[FAIL]%b Test 9d: delete happened during dry-run\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 9d: no delete during dry-run\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 10: no pods found -> exit 0
setup
printf '' > "$TEST_SANDBOX/kubectl_pods"
run_k8s
assert_equals 0 "$LAST_EXIT_CODE" "Test 10a: no pods exits 0"
assert_contains "$LAST_STDOUT" "No pods found" "Test 10b: no pods message"

# Test 11: healthy (no pod exceeds threshold) -> exit 0, no deletes
setup
printf 'pod-a|Running|1,\npod-b|Running|2,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s -r 3
assert_equals 0 "$LAST_EXIT_CODE" "Test 11a: below threshold exits 0"
assert_contains "$LAST_STDOUT" "kept (below threshold)" "Test 11b: kept message"

# Test 12: threshold exceeded -> delete, exit 0
setup
printf 'pod-a|Running|5,\npod-b|Running|1,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s -r 3
assert_equals 0 "$LAST_EXIT_CODE" "Test 12a: delete success exits 0"
assert_contains "$LAST_STDOUT" "-> deleted" "Test 12b: deleted message"
assert_contains "$LAST_STDOUT" "Deleted: 1" "Test 12c: deleted count"

# Test 13: multi-container restart sum (3+2=5 > 3 -> delete)
setup
printf 'pod-a|Running|3,2,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s -r 3
assert_equals 0 "$LAST_EXIT_CODE" "Test 13a: multi-container sum exits 0"
assert_contains "$LAST_STDOUT" "-> deleted" "Test 13b: deleted (sum 5 > 3)"

# Test 14: delete failure -> exit 2
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
echo "pod-a" > "$TEST_SANDBOX/kubectl_delete_fail"
run_k8s
assert_equals 2 "$LAST_EXIT_CODE" "Test 14a: delete failure exits 2"
assert_contains "$LAST_STDOUT" "delete FAILED" "Test 14b: failed message"

# Test 15: audit log
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
audit="$TEST_SANDBOX/audit.log"
run_k8s --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 15a: audit run exits 0"
assert_file_exists "$audit" "Test 15b: audit file created"
assert_contains "$(cat "$audit")" "outcome=success" "Test 15c: audit outcome success"

# Test 16: audit log dry-run
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
audit="$TEST_SANDBOX/audit2.log"
run_k8s --dry-run --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 16a: audit dry-run exits 0"
assert_file_exists "$audit" "Test 16b: audit file created on dry-run"
assert_contains "$(cat "$audit")" "outcome=dry-run" "Test 16c: audit outcome dry-run"

# Test 17: force flag passes --grace-period=0 --force
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
rm -f "$TEST_SANDBOX/kubectl_delete_args"
run_k8s --force
assert_equals 0 "$LAST_EXIT_CODE" "Test 17a: force run exits 0"
if grep -q -- "--grace-period=0" "$TEST_SANDBOX/kubectl_delete_args" 2>/dev/null; then
    printf "%b[PASS]%b Test 17b: force passes grace-period=0\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
else
    printf "%b[FAIL]%b Test 17b: force did not pass grace-period=0\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
fi

# Test 18: verbose prints diagnostic
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s -v
assert_equals 0 "$LAST_EXIT_CODE" "Test 18a: verbose exits 0"
assert_contains "$LAST_STDOUT" "Querying pods" "Test 18b: verbose diagnostic"

# Test 19: custom namespace/selector
setup
printf 'pod-a|Running|5,\n' > "$TEST_SANDBOX/kubectl_pods"
run_k8s -n kube-system -l app=api -r 2
assert_equals 0 "$LAST_EXIT_CODE" "Test 19: custom flags exit 0"

# Test 20: unknown option exits 1
setup
run_k8s --bogus
assert_equals 1 "$LAST_EXIT_CODE" "Test 20: unknown option exits 1"

# ---------- summary ----------
echo ""
echo "========================================"
echo "Tests Passed: $PASSED_TESTS"
echo "Tests Failed: $FAILED_TESTS"
echo "========================================"

rm -rf "$TEST_SANDBOX"

if [[ "$FAILED_TESTS" -gt 0 ]]; then
    exit 1
fi
exit 0
