#!/bin/bash
# ==============================================================================
# Test Suite: test_health_check.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HC_SCRIPT="$SCRIPT_DIR/health_check.sh"
TEST_SANDBOX="$(mktemp -d "/tmp/test_health_check.XXXXXX")"
FAKE_BIN="$TEST_SANDBOX/bin"
mkdir -p "$FAKE_BIN"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly RESET='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

LAST_STDOUT=""
LAST_EXIT_CODE=0

# Fake curl: prints $TEST_SANDBOX/curl_response (format: code|time|size),
# exits with $TEST_SANDBOX/curl_exit (default 0). If curl_response missing,
# prints "000|0.000|0" and exits 7 (connection failure).
cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
resp_file="${TEST_SANDBOX}/curl_response"
exit_file="${TEST_SANDBOX}/curl_exit"
if [[ -f "$resp_file" ]]; then
    cat "$resp_file"
else
    printf '000|0.000|0'
fi
if [[ -f "$exit_file" ]]; then
    exit "$(cat "$exit_file")"
fi
exit 0
EOF
chmod +x "$FAKE_BIN/curl"

# Fake openssl for SSL tests: prints a fixed notAfter date.
cat > "$FAKE_BIN/openssl" <<'EOF'
#!/bin/bash
# s_client path: just succeed
if [[ "$*" == *"s_client"* ]]; then
    exit 0
fi
# x509 path: print notAfter
if [[ "$*" == *"x509"* ]]; then
    printf 'notAfter=Dec 31 23:59:59 2030 GMT\n'
    exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/openssl"

export TEST_SANDBOX
export PATH="$FAKE_BIN:$PATH"

setup() {
    rm -f "$TEST_SANDBOX"/curl_response "$TEST_SANDBOX"/curl_exit "$TEST_SANDBOX"/stdout.txt "$TEST_SANDBOX"/stderr.txt
}

run_hc() {
    local stdout_file="$TEST_SANDBOX/stdout.txt"
    local stderr_file="$TEST_SANDBOX/stderr.txt"
    local exit_code=0
    "$HC_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
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
run_hc -h
assert_equals 0 "$LAST_EXIT_CODE" "Test 1a: -h exits 0"
assert_contains "$LAST_STDOUT" "Usage" "Test 1b: help shows usage"

# Test 2: --help long form
setup
run_hc --help
assert_equals 0 "$LAST_EXIT_CODE" "Test 2: --help exits 0"

# Test 3: invalid URL scheme
setup
run_hc -u ftp://example.com
assert_equals 1 "$LAST_EXIT_CODE" "Test 3: bad scheme exits 1"

# Test 4: missing http(s) prefix
setup
run_hc -u example.com
assert_equals 1 "$LAST_EXIT_CODE" "Test 4: no scheme exits 1"

# Test 5: invalid timeout (zero)
setup
run_hc -t 0
assert_equals 1 "$LAST_EXIT_CODE" "Test 5: zero timeout exits 1"

# Test 6: invalid timeout (negative)
setup
run_hc -t -5
assert_equals 1 "$LAST_EXIT_CODE" "Test 6: negative timeout exits 1"

# Test 7: invalid timeout (non-numeric)
setup
run_hc -t abc
assert_equals 1 "$LAST_EXIT_CODE" "Test 7: non-numeric timeout exits 1"

# Test 8: invalid expected code (too low)
setup
run_hc -e 99
assert_equals 1 "$LAST_EXIT_CODE" "Test 8: expected code 99 exits 1"

# Test 9: invalid expected code (too high)
setup
run_hc -e 600
assert_equals 1 "$LAST_EXIT_CODE" "Test 9: expected code 600 exits 1"

# Test 10: invalid expected code (non-numeric)
setup
run_hc -e abc
assert_equals 1 "$LAST_EXIT_CODE" "Test 10: non-numeric expected code exits 1"

# Test 11: dry-run exits 0 and makes no request
setup
printf '000|0.000|0' > "$TEST_SANDBOX/curl_response"
printf '7' > "$TEST_SANDBOX/curl_exit"
run_hc --dry-run
assert_equals 0 "$LAST_EXIT_CODE" "Test 11a: dry-run exits 0"
assert_contains "$LAST_STDOUT" "Dry run" "Test 11b: dry-run label"

# Test 12: healthy (status matches)
setup
printf '200|0.123|1024' > "$TEST_SANDBOX/curl_response"
run_hc -u https://example.com -e 200
assert_equals 0 "$LAST_EXIT_CODE" "Test 12a: healthy exits 0"
assert_contains "$LAST_STDOUT" "200 OK" "Test 12b: status 200 OK"
assert_contains "$LAST_STDOUT" "Healthy" "Test 12c: Healthy label"

# Test 13: mismatch (500 vs 200) -> exit 2
setup
printf '500|0.500|256' > "$TEST_SANDBOX/curl_response"
run_hc -u https://example.com -e 200
assert_equals 2 "$LAST_EXIT_CODE" "Test 13a: mismatch exits 2"
assert_contains "$LAST_STDOUT" "500" "Test 13b: shows 500"
assert_contains "$LAST_STDOUT" "Unhealthy" "Test 13c: Unhealthy label"

# Test 14: connection failure (000) -> exit 2
setup
printf '000|0.000|0' > "$TEST_SANDBOX/curl_response"
printf '7' > "$TEST_SANDBOX/curl_exit"
run_hc -u https://example.com
assert_equals 2 "$LAST_EXIT_CODE" "Test 14a: connection failure exits 2"
assert_contains "$LAST_STDOUT" "CONNECTION FAILED" "Test 14b: connection failed label"

# Test 15: custom expected code (204)
setup
printf '204|0.050|0' > "$TEST_SANDBOX/curl_response"
run_hc -e 204
assert_equals 0 "$LAST_EXIT_CODE" "Test 15: 204 matches expected 204"

# Test 16: audit log written
setup
printf '200|0.100|512' > "$TEST_SANDBOX/curl_response"
audit="$TEST_SANDBOX/audit.log"
run_hc --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 16a: audit run exits 0"
assert_file_exists "$audit" "Test 16b: audit file created"
assert_contains "$(cat "$audit")" "outcome=healthy" "Test 16c: audit outcome healthy"

# Test 17: audit log dry-run
setup
audit="$TEST_SANDBOX/audit2.log"
run_hc --dry-run --audit-log "$audit"
assert_equals 0 "$LAST_EXIT_CODE" "Test 17a: audit dry-run exits 0"
assert_file_exists "$audit" "Test 17b: audit file created on dry-run"
assert_contains "$(cat "$audit")" "outcome=dry-run" "Test 17c: audit outcome dry-run"

# Test 18: SSL check prints expiry
setup
printf '200|0.100|512' > "$TEST_SANDBOX/curl_response"
run_hc -u https://example.com --ssl-check
assert_equals 0 "$LAST_EXIT_CODE" "Test 18a: ssl-check exits 0"
assert_contains "$LAST_STDOUT" "SSL expiry" "Test 18b: SSL expiry line"
assert_contains "$LAST_STDOUT" "2030" "Test 18c: expiry year shown"

# Test 19: SSL check not shown for http URL
setup
printf '200|0.100|512' > "$TEST_SANDBOX/curl_response"
run_hc -u http://example.com --ssl-check
assert_equals 0 "$LAST_EXIT_CODE" "Test 19a: http + ssl-check exits 0"
# SSL expiry line should not appear for http
if [[ "$LAST_STDOUT" == *"SSL expiry"* ]]; then
    printf "%b[FAIL]%b Test 19b: SSL expiry shown for http URL\n" "$RED" "$RESET" >&2; ((FAILED_TESTS++)) || true
else
    printf "%b[PASS]%b Test 19b: no SSL expiry for http URL\n" "$GREEN" "$RESET"; ((PASSED_TESTS++)) || true
fi

# Test 20: verbose prints diagnostic
setup
printf '200|0.100|512' > "$TEST_SANDBOX/curl_response"
run_hc -v
assert_equals 0 "$LAST_EXIT_CODE" "Test 20a: verbose exits 0"
assert_contains "$LAST_STDOUT" "Performing GET" "Test 20b: verbose diagnostic"

# Test 21: response time and size shown
setup
printf '200|0.456|2048' > "$TEST_SANDBOX/curl_response"
run_hc
assert_contains "$LAST_STDOUT" "0.456s" "Test 21a: response time shown"
assert_contains "$LAST_STDOUT" "2048 bytes" "Test 21b: size shown"

# Test 22: unknown option exits 1
setup
run_hc --bogus
assert_equals 1 "$LAST_EXIT_CODE" "Test 22: unknown option exits 1"

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
