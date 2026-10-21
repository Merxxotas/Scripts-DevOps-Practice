#!/bin/bash
# ==============================================================================
# Script Name: disk_monitor.sh
# Description: Disk usage monitor with threshold alerting. Measures the usage
#              of a mounted filesystem and hands an alert to the host's mail
#              agent when the usage crosses a threshold.
#
#              The module holds no credentials and opens no socket of its own.
#              It composes the alert and hands it to a mail agent that the
#              host already provides.
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
PARTITION="/"
THRESHOLD=80
DRY_RUN=false
NOTIFY_MODE="mail"
MAIL_TO="${DISK_MONITOR_TO:-}"
MAIL_COMMAND_OVERRIDE="${DISK_MONITOR_MAIL_COMMAND:-}"
USAGE_OVERRIDE="${DISK_MONITOR_USAGE_OVERRIDE:-}"
USAGE_COMMAND_OVERRIDE="${DISK_MONITOR_USAGE_COMMAND:-df}"
LOG_FILE=""
VERBOSE=false

# Resolved during the configuration check
MAIL_COMMAND=""

# Prints usage and help message
show_help() {
    cat <<EOF
Disk Usage Monitor (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -p, --partition <path>    Mount point to watch (default: /).
  -t, --threshold <percent> Alert when usage is strictly greater (default: 80).
  -n, --dry-run             Report the alert without handing it to the mail agent.
      --notify <none|mail>  Notification backend (default: mail).
      --to <address>        Alert recipient (default: \$DISK_MONITOR_TO).
      --mail-command <cmd>  Mail agent to hand the alert to.
  -l, --log-file <file>     Path to append ISO-8601 audit records.
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     or mail agent).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent).

Examples:
  $0 -p / -t 80 --to ops@example.com
  $0 -p /home -t 90 -n -v
EOF
}

# Writes a message to the audit log with an ISO-8601 timestamp
log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    local log_parent

    if [[ -z "$LOG_FILE" ]]; then
        return 0
    fi

    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")"
    log_parent="$(dirname "$LOG_FILE")"
    if [[ ! -d "$log_parent" ]]; then
        mkdir -p "$log_parent" 2>/dev/null || true
    fi

    printf "%s [%s] %s\n" "$timestamp" "$level" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# Reads the usage percentage of the watched partition as an integer.
# The POSIX output format is used because it is the only one whose column
# layout is identical on GNU and macOS. The capacity is read from the
# second-to-last field, so a mount point containing spaces cannot shift it.
# A forced value short-circuits the measurement and is reported as such.
get_disk_usage() {
    local output
    local capacity

    if [[ -n "$USAGE_OVERRIDE" ]]; then
        printf '%s' "$USAGE_OVERRIDE"
        return 0
    fi

    if ! output="$("$USAGE_COMMAND_OVERRIDE" -P "$PARTITION" 2>/dev/null)"; then
        return 1
    fi

    capacity="$(printf '%s\n' "$output" | awk 'NR==2 { gsub(/%/, "", $(NF-1)); print $(NF-1) }')"

    if [[ ! "$capacity" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    printf '%s' "$capacity"
}

# Resolves the mail agent that receives the alert. The contract is:
#   <mail-command> -s <subject> <recipient>   with the body on stdin.
# The candidate list covers the agents that honour that contract.
resolve_mail_command() {
    local candidate

    if [[ -n "$MAIL_COMMAND_OVERRIDE" ]]; then
        if [[ -x "$MAIL_COMMAND_OVERRIDE" ]] || command -v "$MAIL_COMMAND_OVERRIDE" >/dev/null 2>&1; then
            printf '%s' "$MAIL_COMMAND_OVERRIDE"
            return 0
        fi
        return 1
    fi

    for candidate in mail msmtp; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    return 1
}

# Hands the alert to the resolved mail agent
send_alert() {
    local subject="$1"
    local body="$2"

    printf '%s\n' "$body" | "$MAIL_COMMAND" -s "$subject" "$MAIL_TO"
}

# Fails when an option was given without its value
require_value() {
    if [[ "$2" -lt 2 ]]; then
        printf "%bError: Option %s requires a value.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
        exit 1
    fi
}

# Parses and validates command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--partition)
                require_value "$1" "$#"
                PARTITION="$2"
                shift 2
                ;;
            -t|--threshold)
                require_value "$1" "$#"
                THRESHOLD="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --notify)
                require_value "$1" "$#"
                NOTIFY_MODE="$2"
                shift 2
                ;;
            --to)
                require_value "$1" "$#"
                MAIL_TO="$2"
                shift 2
                ;;
            --mail-command)
                require_value "$1" "$#"
                MAIL_COMMAND_OVERRIDE="$2"
                shift 2
                ;;
            -l|--log-file)
                require_value "$1" "$#"
                LOG_FILE="$2"
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
}

# Validates the configuration and resolves the notification path.
# Everything is checked before the disk is measured, so a broken alerting
# path is reported immediately instead of at the moment an alert is needed.
validate_configuration() {
    if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 ]] || [[ "$THRESHOLD" -gt 100 ]]; then
        printf "%bError: Threshold must be an integer between 1 and 100.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid threshold: '$THRESHOLD'."
        exit 1
    fi

    if [[ "$NOTIFY_MODE" != "none" && "$NOTIFY_MODE" != "mail" ]]; then
        printf "%bError: Notify backend must be 'none' or 'mail'.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid notify backend: '$NOTIFY_MODE'."
        exit 1
    fi

    if [[ -n "$USAGE_OVERRIDE" ]]; then
        if [[ ! "$USAGE_OVERRIDE" =~ ^[0-9]+$ ]] || [[ "$USAGE_OVERRIDE" -gt 100 ]]; then
            printf "%bError: DISK_MONITOR_USAGE_OVERRIDE must be an integer between 0 and 100.%b\n" \
                "$COLOR_RED" "$COLOR_RESET" >&2
            log_message "ERROR" "Invalid usage override: '$USAGE_OVERRIDE'."
            exit 1
        fi
    fi

    if [[ ! -d "$PARTITION" ]]; then
        printf "%bError: Partition '%s' does not exist.%b\n" \
            "$COLOR_RED" "$PARTITION" "$COLOR_RESET" >&2
        log_message "ERROR" "Partition does not exist: '$PARTITION'."
        exit 1
    fi

    if ! command -v "$USAGE_COMMAND_OVERRIDE" >/dev/null 2>&1; then
        printf "%bError: Measurement command '%s' was not found.%b\n" \
            "$COLOR_RED" "$USAGE_COMMAND_OVERRIDE" "$COLOR_RESET" >&2
        log_message "ERROR" "Measurement command not found: '$USAGE_COMMAND_OVERRIDE'."
        exit 1
    fi

    if [[ "$NOTIFY_MODE" != "mail" ]]; then
        return 0
    fi

    if [[ -z "$MAIL_TO" ]]; then
        printf "%bError: No recipient. Use --to, or set DISK_MONITOR_TO.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "No alert recipient configured."
        exit 1
    fi

    if ! MAIL_COMMAND="$(resolve_mail_command)"; then
        printf "%bError: No mail agent found. Install one, or set --mail-command or DISK_MONITOR_MAIL_COMMAND.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "No mail agent could be resolved."
        exit 1
    fi
}

# Main execution entrypoint
main() {
    parse_arguments "$@"
    validate_configuration

    local used_percent
    if ! used_percent="$(get_disk_usage)"; then
        printf "%bError: Could not read the disk usage of '%s'.%b\n" \
            "$COLOR_RED" "$PARTITION" "$COLOR_RESET" >&2
        log_message "ERROR" "Could not read the disk usage of '$PARTITION'."
        exit 2
    fi

    local usage_source="measured"
    if [[ -n "$USAGE_OVERRIDE" ]]; then
        usage_source="overridden"
    fi

    local mode_label
    if [[ "$DRY_RUN" == true ]]; then
        mode_label="$(printf "%bDRY RUN (Simulation)%b" "$COLOR_YELLOW" "$COLOR_RESET")"
    else
        mode_label="$(printf "%bLIVE (Alerts Active)%b" "$COLOR_GREEN" "$COLOR_RESET")"
    fi

    local mail_label
    if [[ -z "$MAIL_COMMAND" ]]; then
        mail_label="(not resolved: notification disabled)"
    else
        mail_label="$MAIL_COMMAND"
    fi

    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                DevOps Disk Usage Monitor                  %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "Partition         : %b%s%b\n" "$COLOR_CYAN" "$PARTITION" "$COLOR_RESET"
    printf "Usage             : %b%s%%%b (%s)\n" "$COLOR_BOLD" "$used_percent" "$COLOR_RESET" "$usage_source"
    printf "Threshold         : %b%s%%%b\n" "$COLOR_YELLOW" "$THRESHOLD" "$COLOR_RESET"
    printf "Mail Agent        : %b%s%b\n" "$COLOR_CYAN" "$mail_label" "$COLOR_RESET"
    if [[ "$NOTIFY_MODE" == "mail" ]]; then
        printf "Recipient         : %b%s%b\n" "$COLOR_CYAN" "$MAIL_TO" "$COLOR_RESET"
    fi
    printf "Execution Mode    : %b\n" "$mode_label"
    if [[ -n "$LOG_FILE" ]]; then
        printf "Audit Log File    : %b%s%b\n" "$COLOR_CYAN" "$LOG_FILE" "$COLOR_RESET"
    fi

    if [[ "$VERBOSE" == true ]]; then
        printf "%bDiagnostics        : %bmail agent '%s', recipient '%s', dry-run '%s'%b\n" \
            "$COLOR_BLUE" "$COLOR_RESET" "$mail_label" "$MAIL_TO" "$DRY_RUN" "$COLOR_RESET"
    fi

    if [[ "$used_percent" -gt "$THRESHOLD" ]]; then
        printf "%bWARNING: Disk usage exceeds the threshold.%b\n" "$COLOR_RED" "$COLOR_RESET"

        local host
        host="$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "unknown-host")"
        local subject="Disk Alert: ${PARTITION} at ${used_percent}%"
        local body
        body="$(printf 'Disk usage on %s is at %s%% (threshold: %s%%).\n\nPartition : %s\nUsage    : %s%%\nThreshold: %s%%\nTime     : %s' \
            "$host" "$used_percent" "$THRESHOLD" "$PARTITION" "$used_percent" "$THRESHOLD" \
            "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")"

        if [[ "$DRY_RUN" == true ]]; then
            printf "%b[DRY RUN]%b Would send an alert to %s\n" \
                "$COLOR_YELLOW" "$COLOR_RESET" "$MAIL_TO"
            log_message "INFO" "[DRY RUN] Would send an alert to $MAIL_TO (Usage: ${used_percent}%, Source: ${usage_source}, Threshold: ${THRESHOLD}%)"
        elif [[ "$NOTIFY_MODE" == "mail" ]]; then
            if send_alert "$subject" "$body"; then
                printf "%bAlert sent to %s%b\n" "$COLOR_GREEN" "$MAIL_TO" "$COLOR_RESET"
                log_message "INFO" "ALERT SENT to $MAIL_TO (Usage: ${used_percent}%, Source: ${usage_source}, Threshold: ${THRESHOLD}%)"
            else
                printf "%bError: The alert could not be handed to the mail agent.%b\n" \
                    "$COLOR_RED" "$COLOR_RESET" >&2
                log_message "ERROR" "FAILED to hand the alert to the mail agent (Usage: ${used_percent}%, Source: ${usage_source})"
                exit 2
            fi
        else
            printf "%bAlert suppressed by --notify none.%b\n" "$COLOR_CYAN" "$COLOR_RESET"
            log_message "INFO" "Alert suppressed by --notify none (Usage: ${used_percent}%, Source: ${usage_source})"
        fi
    else
        printf "%bDisk usage is within the threshold.%b\n" "$COLOR_GREEN" "$COLOR_RESET"
        log_message "INFO" "Usage within threshold (Usage: ${used_percent}%, Source: ${usage_source}, Threshold: ${THRESHOLD}%)"
    fi

    exit 0
}

main "$@"
