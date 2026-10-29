#!/usr/bin/env bash
#
# health_check.sh — Website Availability (HTTP Health Check)
#
# Performs a single HTTP GET against a target URL and reports whether the
# response status matches the expected code, along with response time, size
# and (optionally) SSL certificate expiry.
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Color constants (curlie-inspired)
# ---------------------------------------------------------------------------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RED='\033[31m'
readonly C_GREEN='\033[32m'
readonly C_YELLOW='\033[33m'
readonly C_BLUE='\033[34m'
readonly C_CYAN='\033[36m'
readonly C_MAGENTA='\033[35m'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_URL="https://example.com"
DEFAULT_TIMEOUT=10
DEFAULT_EXPECTED=200

URL="$DEFAULT_URL"
TIMEOUT="$DEFAULT_TIMEOUT"
EXPECTED_CODE="$DEFAULT_EXPECTED"
SSL_CHECK=false
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false
OUTPUT_MODE="human"
JSON_OUTPUT=false
CSV_OUTPUT=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { if [[ "$OUTPUT_MODE" == "human" ]]; then printf '%b\n' "$*"; fi; }
err() { printf '%b\n' "${C_RED}$*${C_RESET}" >&2; }
vlog() { if [[ "$OUTPUT_MODE" == "human" ]] && $VERBOSE; then printf '%b\n' "${C_DIM}$*${C_RESET}"; fi; }

usage() {
    cat <<'EOF'
Usage: health_check.sh [options]

Website Availability (HTTP Health Check) - single HTTP GET probe.

Options:
  -u, --url <URL>          Target URL (default: https://example.com)
  -t, --timeout <SEC>       Request timeout in seconds (default: 10)
  -e, --expected-code <N>   HTTP status code considered healthy (default: 200)
      --ssl-check           Report SSL certificate expiry (HTTPS only)
      --dry-run             Print target/expected/timeout, no request
      --audit-log <PATH>     Append an ISO-8601 audit line per run
      --json                 Output result as JSON
      --csv                  Output result as CSV
  -v, --verbose             Diagnostic output
  -h, --help                Show this help and exit

Exit codes:
  0  Healthy (status matches expected) or dry-run
  1  Configuration or safety violation
  2  Unhealthy (status mismatch or connection failure)
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--url)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                URL="$2"; shift 2 ;;
            -t|--timeout)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                TIMEOUT="$2"; shift 2 ;;
            -e|--expected-code)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                EXPECTED_CODE="$2"; shift 2 ;;
            --ssl-check)
                SSL_CHECK=true; shift ;;
            --json)
                JSON_OUTPUT=true; shift ;;
            --csv)
                CSV_OUTPUT=true; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            --audit-log)
                [[ $# -ge 2 ]] || { err "Missing value for $1"; exit 1; }
                AUDIT_LOG="$2"; shift 2 ;;
            -v|--verbose)
                VERBOSE=true; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                err "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
validate() {
    if $JSON_OUTPUT && $CSV_OUTPUT; then
        err "Cannot use --json and --csv together"
        exit 1
    fi
    if $JSON_OUTPUT; then
        OUTPUT_MODE="json"
    elif $CSV_OUTPUT; then
        OUTPUT_MODE="csv"
    else
        OUTPUT_MODE="human"
    fi
    # URL scheme
    if [[ ! "$URL" =~ ^https?:// ]]; then
        err "Invalid URL: must start with http:// or https://"
        exit 1
    fi
    # Timeout positive integer
    if [[ ! "$TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
        err "Invalid timeout: must be a positive integer"
        exit 1
    fi
    # Expected code 100-599
    if [[ ! "$EXPECTED_CODE" =~ ^[0-9]+$ ]] || \
       (( EXPECTED_CODE < 100 || EXPECTED_CODE > 599 )); then
        err "Invalid expected code: must be between 100 and 599"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Host extraction (for SSL check)
# ---------------------------------------------------------------------------
extract_host() {
    printf '%s' "$URL" | sed -E 's#^https?://([^/:]+).*#\1#'
}

# ---------------------------------------------------------------------------
# SSL expiry (best-effort)
# ---------------------------------------------------------------------------
ssl_expiry() {
    local host expiry
    host="$(extract_host)"
    if command -v openssl >/dev/null 2>&1; then
        expiry="$( (printf '' | openssl s_client -servername "$host" \
            -connect "${host}:443" 2>/dev/null) \
            | openssl x509 -noout -enddate 2>/dev/null \
            | sed 's/^notAfter=//' )" || expiry=""
    else
        expiry=""
    fi
    if [[ -z "$expiry" ]]; then
        printf 'unavailable'
    else
        printf '%s' "$expiry"
    fi
}

# ---------------------------------------------------------------------------
# Audit log (best-effort)
# ---------------------------------------------------------------------------
write_audit() {
    local status="$1" time="$2" size="$3" outcome="$4"
    [[ -z "$AUDIT_LOG" ]] && return 0
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s url=%s status=%s time=%ss size=%s outcome=%s\n' \
        "$ts" "$URL" "$status" "$time" "$size" "$outcome" \
        >>"$AUDIT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate

    log "${C_BOLD}${C_BLUE}=== HTTP Health Check ===${C_RESET}"
    log "  ${C_DIM}Target:${C_RESET}   ${C_CYAN}${URL}${C_RESET}"
    log "  ${C_DIM}Expected:${C_RESET} ${C_GREEN}${EXPECTED_CODE}${C_RESET}"
    log "  ${C_DIM}Timeout:${C_RESET}  ${C_YELLOW}${TIMEOUT}s${C_RESET}"
    if $SSL_CHECK; then
        log "  ${C_DIM}SSL:${C_RESET}     ${C_MAGENTA}enabled${C_RESET}"
    fi

    if $DRY_RUN; then
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            printf '{\n  "url": "%s",\n  "expected_code": %s,\n  "status_code": null,\n  "healthy": null,\n  "response_time_seconds": null,\n  "size_bytes": null,\n  "ssl_expiry": null,\n  "outcome": "dry-run"\n}\n' "$URL" "$EXPECTED_CODE"
        elif [[ "$OUTPUT_MODE" == "csv" ]]; then
            printf 'url,expected_code,status_code,healthy,response_time_seconds,size_bytes,ssl_expiry,outcome\n'
            printf '"%s",%s,,,,,,"dry-run"\n' "$URL" "$EXPECTED_CODE"
        else
            log ""
            log "${C_GREEN}Dry run - no request made.${C_RESET}"
        fi
        write_audit "-" "-" "-" "dry-run"
        exit 0
    fi

    vlog "Performing GET request (no redirects)..."
    local raw http_code resp_time size curl_exit
    curl_exit=0
    raw="$(curl -s -o /dev/null \
        -w "%{http_code}|%{time_total}|%{size_download}" \
        --max-time "$TIMEOUT" "$URL" 2>/dev/null)" || curl_exit=$?

    IFS='|' read -r http_code resp_time size <<<"$raw"
    http_code="${http_code:-000}"
    resp_time="${resp_time:-0}"
    size="${size:-0}"

    vlog "curl exit: $curl_exit | raw: $raw"

    # Determine health
    local outcome exit_code
    if [[ "$curl_exit" -ne 0 || "$http_code" == "000" ]]; then
        outcome="unhealthy"
        exit_code=2
    elif [[ "$http_code" == "$EXPECTED_CODE" ]]; then
        outcome="healthy"
        exit_code=0
    else
        outcome="unhealthy"
        exit_code=2
    fi

    # Output
    log ""
    log "${C_BOLD}Result${C_RESET}"
    if [[ "$OUTPUT_MODE" == "human" ]]; then
        printf '  %-12s' "Status:"
        if [[ "$outcome" == "healthy" ]]; then
            printf '%b\n' "${C_GREEN}${http_code} OK${C_RESET}"
        elif [[ "$http_code" == "000" ]]; then
            printf '%b\n' "${C_RED}CONNECTION FAILED${C_RESET}"
        else
            printf '%b\n' "${C_YELLOW}${http_code} (unexpected, expected ${EXPECTED_CODE})${C_RESET}"
        fi
    fi
    log "  ${C_DIM}Time:${C_RESET}     ${C_CYAN}${resp_time}s${C_RESET}"
    log "  ${C_DIM}Size:${C_RESET}     ${C_CYAN}${size} bytes${C_RESET}"

    if $SSL_CHECK && [[ "$URL" == https* ]]; then
        local expiry
        expiry="$(ssl_expiry)"
        log "  ${C_DIM}SSL expiry:${C_RESET} ${C_MAGENTA}${expiry}${C_RESET}"
    fi

    if [[ "$outcome" == "healthy" ]]; then
        log ""
        log "${C_GREEN}Healthy.${C_RESET}"
    else
        log ""
        log "${C_RED}Unhealthy.${C_RESET}"
    fi

    # SSL expiry value for structured output
    local ssl_val="null"
    if $SSL_CHECK && [[ "$URL" == https* ]]; then
        ssl_val="\"$(ssl_expiry)\""
    fi

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        printf '{\n  "url": "%s",\n  "expected_code": %s,\n  "status_code": %s,\n  "healthy": %s,\n  "response_time_seconds": %s,\n  "size_bytes": %s,\n  "ssl_expiry": %s,\n  "outcome": "%s"\n}\n' \
            "$URL" "$EXPECTED_CODE" "$http_code" \
            "$([[ "$outcome" == "healthy" ]] && echo true || echo false)" \
            "$resp_time" "$size" "$ssl_val" "$outcome"
    elif [[ "$OUTPUT_MODE" == "csv" ]]; then
        printf 'url,expected_code,status_code,healthy,response_time_seconds,size_bytes,ssl_expiry,outcome\n'
        local healthy_csv
        healthy_csv="$([[ "$outcome" == "healthy" ]] && echo true || echo false)"
        local ssl_csv=""
        if $SSL_CHECK && [[ "$URL" == https* ]]; then
            ssl_csv="$(ssl_expiry)"
        fi
        printf '"%s",%s,%s,%s,%s,%s,"%s","%s"\n' \
            "$URL" "$EXPECTED_CODE" "$http_code" "$healthy_csv" "$resp_time" "$size" "$ssl_csv" "$outcome"
    fi

    write_audit "$http_code" "$resp_time" "$size" "$outcome"
    exit "$exit_code"
}

main "$@"
