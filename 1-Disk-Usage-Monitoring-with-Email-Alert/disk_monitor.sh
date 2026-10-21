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
MAIL_TO=""
MAIL_COMMAND_OVERRIDE=""
USAGE_OVERRIDE=""
USAGE_COMMAND_OVERRIDE=""
LOG_FILE=""
VERBOSE=false

# The configuration file and the values it supplied
CONFIG_FILE=""
CONFIG_PARTITION=""
CONFIG_THRESHOLD=""
CONFIG_NOTIFY=""
CONFIG_TO=""
CONFIG_MAIL_COMMAND=""
CONFIG_LOG_FILE=""
CONFIG_USAGE_COMMAND=""
CONFIG_USAGE_OVERRIDE=""
CONFIG_HEADERS=""

# Whether the command line supplied each setting
FLAG_PARTITION_SET=false
FLAG_THRESHOLD_SET=false
FLAG_NOTIFY_SET=false
FLAG_TO_SET=false
FLAG_MAIL_COMMAND_SET=false
FLAG_LOG_FILE_SET=false
FLAG_CONFIG_SET=false

# Where each resolved value came from
SOURCE_PARTITION="default"
SOURCE_THRESHOLD="default"
SOURCE_NOTIFY="default"
SOURCE_TO="default"
SOURCE_MAIL_COMMAND="default"
SOURCE_LOG_FILE="default"
SOURCE_USAGE_COMMAND="default"
SOURCE_USAGE_OVERRIDE="default"

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
      --config <file>       Configuration file to read (default: ./.diskmonitor.conf).
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Configuration:
  A flag wins over an environment variable, which wins over the
  configuration file, which wins over the built-in default. The environment
  variables are DISK_MONITOR_PARTITION, DISK_MONITOR_THRESHOLD,
  DISK_MONITOR_NOTIFY, DISK_MONITOR_TO, DISK_MONITOR_MAIL_COMMAND,
  DISK_MONITOR_LOG_FILE, DISK_MONITOR_USAGE_COMMAND,
  DISK_MONITOR_USAGE_OVERRIDE and DISK_MONITOR_CONFIG.

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

# Removes leading and trailing whitespace
trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Resolves one setting: the command line wins, then the environment, then the
# configuration file, then the built-in default. The value and the source it
# came from are printed, separated by a tab.
resolve_value() {
    local flag_value="$1"
    local flag_set="$2"
    local env_value="$3"
    local config_value="$4"
    local default_value="$5"

    if [[ "$flag_set" == "true" ]]; then
        printf '%s\t%s' "$flag_value" "flag"
    elif [[ -n "$env_value" ]]; then
        printf '%s\t%s' "$env_value" "environment"
    elif [[ -n "$config_value" ]]; then
        printf '%s\t%s' "$config_value" "config"
    else
        printf '%s\t%s' "$default_value" "default"
    fi
}

# Assigns a resolved setting and the source it came from
apply_setting() {
    local target="$1"
    local source_target="$2"
    local resolved

    resolved="$(resolve_value "$3" "$4" "$5" "$6" "$7")"
    printf -v "$target" '%s' "${resolved%%$'\t'*}"
    printf -v "$source_target" '%s' "${resolved##*$'\t'}"
}

# Parses the configuration file. A key is separated from its value by the
# first equals sign. A line may be a comment, and a value may be quoted to
# protect spaces or a hash.
parse_config_file() {
    local file="$1"
    local line
    local key
    local value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # A configuration file edited on Windows may carry carriage returns.
        line="${line%$'\r'}"
        line="$(trim "$line")"

        if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
            continue
        fi

        if [[ "$line" != *"="* ]]; then
            printf "%bWarning: ignoring malformed line in '%s': '%s'%b\n" \
                "$COLOR_YELLOW" "$CONFIG_FILE" "$line" "$COLOR_RESET" >&2
            continue
        fi

        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"

        if [[ "${value:0:1}" == '"' ]]; then
            value="${value#\"}"
            value="${value%%\"*}"
        elif [[ "${value:0:1}" == "'" ]]; then
            value="${value#\'}"
            value="${value%%\'*}"
        fi

        case "$key" in
            partition) CONFIG_PARTITION="$value" ;;
            threshold) CONFIG_THRESHOLD="$value" ;;
            notify) CONFIG_NOTIFY="$value" ;;
            to) CONFIG_TO="$value" ;;
            mail_command) CONFIG_MAIL_COMMAND="$value" ;;
            log_file) CONFIG_LOG_FILE="$value" ;;
            usage_command) CONFIG_USAGE_COMMAND="$value" ;;
            usage_override) CONFIG_USAGE_OVERRIDE="$value" ;;
            header)
                if [[ -n "$CONFIG_HEADERS" ]]; then
                    CONFIG_HEADERS="${CONFIG_HEADERS}"$'\n'"${value}"
                else
                    CONFIG_HEADERS="$value"
                fi
                ;;
            *)
                printf "%bWarning: ignoring unknown configuration key '%s' in '%s'.%b\n" \
                    "$COLOR_YELLOW" "$key" "$CONFIG_FILE" "$COLOR_RESET" >&2
                ;;
        esac
    done < "$file"
}

# Loads the configuration file, if one was selected or found. A file named
# explicitly must exist; a default one that is absent is not an error.
load_configuration() {
    local candidate=""
    local explicit=false

    if [[ "$FLAG_CONFIG_SET" == "true" ]]; then
        candidate="$CONFIG_FILE"
        explicit=true
    elif [[ -n "${DISK_MONITOR_CONFIG:-}" ]]; then
        candidate="$DISK_MONITOR_CONFIG"
        explicit=true
    elif [[ -f "./.diskmonitor.conf" ]]; then
        candidate="./.diskmonitor.conf"
    elif [[ -f "${HOME:-.}/.config/disk-monitor/config" ]]; then
        candidate="${HOME:-.}/.config/disk-monitor/config"
    fi

    if [[ -z "$candidate" ]]; then
        return 0
    fi

    if [[ ! -f "$candidate" ]]; then
        if [[ "$explicit" == true ]]; then
            printf "%bError: Configuration file '%s' does not exist.%b\n" \
                "$COLOR_RED" "$candidate" "$COLOR_RESET" >&2
            exit 1
        fi
        return 0
    fi

    CONFIG_FILE="$candidate"
    parse_config_file "$candidate"
}

# Applies the precedence to every setting and records where each value came
# from, so the doctor can report it.
apply_precedence() {
    apply_setting PARTITION SOURCE_PARTITION "$PARTITION" "$FLAG_PARTITION_SET" \
        "${DISK_MONITOR_PARTITION:-}" "$CONFIG_PARTITION" "/"
    apply_setting THRESHOLD SOURCE_THRESHOLD "$THRESHOLD" "$FLAG_THRESHOLD_SET" \
        "${DISK_MONITOR_THRESHOLD:-}" "$CONFIG_THRESHOLD" "80"
    apply_setting NOTIFY_MODE SOURCE_NOTIFY "$NOTIFY_MODE" "$FLAG_NOTIFY_SET" \
        "${DISK_MONITOR_NOTIFY:-}" "$CONFIG_NOTIFY" "mail"
    apply_setting MAIL_TO SOURCE_TO "$MAIL_TO" "$FLAG_TO_SET" \
        "${DISK_MONITOR_TO:-}" "$CONFIG_TO" ""
    apply_setting MAIL_COMMAND_OVERRIDE SOURCE_MAIL_COMMAND "$MAIL_COMMAND_OVERRIDE" \
        "$FLAG_MAIL_COMMAND_SET" "${DISK_MONITOR_MAIL_COMMAND:-}" "$CONFIG_MAIL_COMMAND" ""
    apply_setting LOG_FILE SOURCE_LOG_FILE "$LOG_FILE" "$FLAG_LOG_FILE_SET" \
        "${DISK_MONITOR_LOG_FILE:-}" "$CONFIG_LOG_FILE" ""
    apply_setting USAGE_COMMAND_OVERRIDE SOURCE_USAGE_COMMAND "$USAGE_COMMAND_OVERRIDE" \
        "false" "${DISK_MONITOR_USAGE_COMMAND:-}" "$CONFIG_USAGE_COMMAND" "df"
    apply_setting USAGE_OVERRIDE SOURCE_USAGE_OVERRIDE "$USAGE_OVERRIDE" \
        "false" "${DISK_MONITOR_USAGE_OVERRIDE:-}" "$CONFIG_USAGE_OVERRIDE" ""
}

# Reads the usage percentage of the watched partition as an integer.
# The POSIX output format is used because it is the only one whose column
# layout is identical on GNU and macOS. The capacity is read from the fifth
# field, which is its fixed position in that layout, so a mount point
# containing spaces cannot shift it.
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

    capacity="$(printf '%s\n' "$output" | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"

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
                FLAG_PARTITION_SET=true
                shift 2
                ;;
            -t|--threshold)
                require_value "$1" "$#"
                THRESHOLD="$2"
                FLAG_THRESHOLD_SET=true
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --notify)
                require_value "$1" "$#"
                NOTIFY_MODE="$2"
                FLAG_NOTIFY_SET=true
                shift 2
                ;;
            --to)
                require_value "$1" "$#"
                MAIL_TO="$2"
                FLAG_TO_SET=true
                shift 2
                ;;
            --mail-command)
                require_value "$1" "$#"
                MAIL_COMMAND_OVERRIDE="$2"
                FLAG_MAIL_COMMAND_SET=true
                shift 2
                ;;
            -l|--log-file)
                require_value "$1" "$#"
                LOG_FILE="$2"
                FLAG_LOG_FILE_SET=true
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --config)
                require_value "$1" "$#"
                CONFIG_FILE="$2"
                FLAG_CONFIG_SET=true
                shift 2
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
    load_configuration
    apply_precedence
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
        printf "%bDiagnostics        : %bpartition %s, threshold %s, notify %s, recipient %s, mail command %s, log file %s, usage command %s, usage override %s%b\n" \
            "$COLOR_BLUE" "$COLOR_RESET" \
            "$SOURCE_PARTITION" "$SOURCE_THRESHOLD" "$SOURCE_NOTIFY" "$SOURCE_TO" \
            "$SOURCE_MAIL_COMMAND" "$SOURCE_LOG_FILE" "$SOURCE_USAGE_COMMAND" "$SOURCE_USAGE_OVERRIDE" \
            "$COLOR_RESET"
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
