#!/bin/bash
# ==============================================================================
# Script Name: service_monitor.sh
# Description: Cross-platform service monitoring with automatic restart.
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ANSI color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_RESET='\033[0m'

# Default configuration
SERVICE_NAME="nginx"
MAX_RETRIES=3
RETRY_DELAY=5
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false

# Metrics / state
RESTARTED=false
RETRIES_USED=0
FAILED=false

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf "%bError: Option '%s' requires a value.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
        exit 1
    fi
}

is_nonneg_int() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_pos_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

valid_service_name() {
    [[ "${1:-}" =~ ^[a-zA-Z0-9_.@-]+$ ]]
}

show_help() {
    cat <<EOF
Service Monitor and Auto-Restart Utility (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -s, --service <name>     Target service name (default: nginx).
  -r, --max-retries <n>    Restart attempts when down (default: 3).
      --retry-delay <n>     Seconds between attempts (default: 5).
      --dry-run             Preview actions without touching the service.
      --audit-log <file>    Append ISO-8601 audit log entries.
  -v, --verbose            Enable diagnostic output.
  -h, --help               Show this help and usage documentation.

Examples:
  $0 -s nginx
  $0 -s nginx --dry-run
  $0 -s nginx -r 5 --retry-delay 10
EOF
}

log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"
    if [[ -n "$AUDIT_LOG" ]]; then
        printf "%s [%s] %s\n" "$timestamp" "$level" "$message" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
}

notify_restart() {
    local svc="$1"
    printf "Service %s was restarted on %s\n" "$svc" "$(date)" | logger 2>/dev/null || true
}

service_exists() {
    local svc="$1"
    local state
    state="$(systemctl show --property=LoadState --value "$svc" 2>/dev/null || true)"
    [[ "$state" == "loaded" ]]
}

service_active() {
    local svc="$1"
    systemctl is-active --quiet "$svc" 2>/dev/null
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--service)
                require_value "$1" "$#"
                SERVICE_NAME="$2"
                shift 2
                ;;
            -r|--max-retries)
                require_value "$1" "$#"
                MAX_RETRIES="$2"
                shift 2
                ;;
            --retry-delay)
                require_value "$1" "$#"
                RETRY_DELAY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --audit-log)
                require_value "$1" "$#"
                AUDIT_LOG="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                printf "%bError: Unknown option '%s'.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
                show_help
                exit 1
                ;;
            *)
                printf "%bError: Unexpected argument '%s'.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "$SERVICE_NAME" ]]; then
        printf "%bError: Service name is required.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if ! valid_service_name "$SERVICE_NAME"; then
        printf "%bError: Invalid service name '%s'.%b\n" "$COLOR_RED" "$SERVICE_NAME" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid service name: $SERVICE_NAME"
        exit 1
    fi
    if ! is_pos_int "$MAX_RETRIES"; then
        printf "%bError: Max retries must be a positive integer.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if ! is_nonneg_int "$RETRY_DELAY"; then
        printf "%bError: Retry delay must be a non-negative integer.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
}

main() {
    parse_arguments "$@"

    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b            DevOps Service Monitor Utility                 %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Service          : %b%s%b\n" "$COLOR_CYAN" "$SERVICE_NAME" "$COLOR_RESET"
    printf "Max Retries      : %b%s%b\n" "$COLOR_CYAN" "$MAX_RETRIES" "$COLOR_RESET"
    printf "Retry Delay      : %b%s s%b\n" "$COLOR_CYAN" "$RETRY_DELAY" "$COLOR_RESET"
    if [[ -n "$AUDIT_LOG" ]]; then
        printf "Audit Log        : %b%s%b\n" "$COLOR_CYAN" "$AUDIT_LOG" "$COLOR_RESET"
    fi
    printf "\n"

    # Existence check
    if ! service_exists "$SERVICE_NAME"; then
        printf "%bError: Service '%s' is not installed or not found.%b\n" "$COLOR_RED" "$SERVICE_NAME" "$COLOR_RESET" >&2
        log_message "ERROR" "Service not found: $SERVICE_NAME"
        exit 1
    fi

    # Status check
    if service_active "$SERVICE_NAME"; then
        printf "%b✓ Service '%s' is running.%b\n" "$COLOR_GREEN" "$SERVICE_NAME" "$COLOR_RESET"
        log_message "INFO" "Service '$SERVICE_NAME' is running."
        exit 0
    fi

    printf "%b✗ Service '%s' is not running.%b\n" "$COLOR_RED" "$SERVICE_NAME" "$COLOR_RESET"

    # Dry-run
    if [[ "$DRY_RUN" == true ]]; then
        printf "%b[DRY RUN]%b Would restart '%s' up to %s time(s), waiting %s s between attempts.\n" \
            "$COLOR_YELLOW" "$COLOR_RESET" "$SERVICE_NAME" "$MAX_RETRIES" "$RETRY_DELAY"
        log_message "INFO" "[DRY RUN] Restart planned for '$SERVICE_NAME'."
        exit 0
    fi

    # Auto-restart loop
    printf "%bAttempting to restart...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
    local attempt
    for (( attempt=1; attempt<=MAX_RETRIES; attempt++ )); do
        if [[ "$VERBOSE" == true ]]; then
            printf "  attempt %d/%d: restarting %s\n" "$attempt" "$MAX_RETRIES" "$SERVICE_NAME"
        fi
        if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
            sleep 2
            if service_active "$SERVICE_NAME"; then
                printf "%b✓ Service '%s' restarted successfully.%b\n" "$COLOR_GREEN" "$SERVICE_NAME" "$COLOR_RESET"
                notify_restart "$SERVICE_NAME"
                RESTARTED=true
                RETRIES_USED="$attempt"
                log_message "INFO" "Service '$SERVICE_NAME' restarted after $attempt attempt(s)."
                # Summary
                printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
                printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
                printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
                printf "Service          : %b%s%b\n" "$COLOR_BOLD" "$SERVICE_NAME" "$COLOR_RESET"
                printf "Result           : %brestarted%b\n" "$COLOR_GREEN" "$COLOR_RESET"
                printf "Retries Used     : %b%d%b\n" "$COLOR_BOLD" "$RETRIES_USED" "$COLOR_RESET"
                printf "Failed Steps     : %b0%b\n" "$COLOR_RED" "$COLOR_RESET"
                printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
                exit 0
            fi
        fi
        RETRIES_USED="$attempt"
        printf "%b✗ Restart attempt %d/%d failed.%b\n" "$COLOR_RED" "$attempt" "$MAX_RETRIES" "$COLOR_RESET" >&2
        log_message "ERROR" "Restart attempt $attempt/$MAX_RETRIES failed for '$SERVICE_NAME'."
        if [[ "$attempt" -lt "$MAX_RETRIES" ]]; then
            if [[ "$VERBOSE" == true ]]; then
                printf "  waiting %s s before next attempt\n" "$RETRY_DELAY"
            fi
            sleep "$RETRY_DELAY"
        fi
    done

    FAILED=true
    printf "%b✗ Failed to restart service '%s' after %s attempt(s).%b\n" "$COLOR_RED" "$SERVICE_NAME" "$MAX_RETRIES" "$COLOR_RESET" >&2
    log_message "ERROR" "Failed to restart '$SERVICE_NAME' after $MAX_RETRIES attempt(s)."
    # Summary
    printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Service          : %b%s%b\n" "$COLOR_BOLD" "$SERVICE_NAME" "$COLOR_RESET"
    printf "Result           : %bfailed%b\n" "$COLOR_RED" "$COLOR_RESET"
    printf "Retries Used     : %b%d%b\n" "$COLOR_BOLD" "$RETRIES_USED" "$COLOR_RESET"
    printf "Failed Steps     : %b1%b\n" "$COLOR_RED" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    exit 2
}

main "$@"
