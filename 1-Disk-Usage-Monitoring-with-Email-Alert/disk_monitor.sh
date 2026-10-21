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
CONFIG_URL=""
CONFIG_BODY_TEMPLATE=""
CONFIG_METHOD=""
CONFIG_TIMEOUT=""

# Whether the command line supplied each setting
FLAG_PARTITION_SET=false
FLAG_THRESHOLD_SET=false
FLAG_NOTIFY_SET=false
FLAG_TO_SET=false
FLAG_MAIL_COMMAND_SET=false
FLAG_LOG_FILE_SET=false
FLAG_CONFIG_SET=false
FLAG_URL_SET=false
FLAG_BODY_TEMPLATE_SET=false
FLAG_TIMEOUT_SET=false
FLAG_HTTP_COMMAND_SET=false
FLAG_HEADER_SET=false

# Where each resolved value came from
SOURCE_PARTITION="default"
SOURCE_THRESHOLD="default"
SOURCE_NOTIFY="default"
SOURCE_TO="default"
SOURCE_MAIL_COMMAND="default"
SOURCE_LOG_FILE="default"
SOURCE_USAGE_COMMAND="default"
SOURCE_USAGE_OVERRIDE="default"
SOURCE_URL="default"
SOURCE_BODY_TEMPLATE="default"
SOURCE_METHOD="default"
SOURCE_TIMEOUT="default"
SOURCE_HTTP_COMMAND="default"
SOURCE_HEADER="default"

# Resolved during the configuration check
MAIL_COMMAND=""
HTTP_CLIENT=""

# The HTTP transport settings and the headers it carries
HTTP_URL=""
HTTP_BODY_TEMPLATE=""
HTTP_METHOD=""
HTTP_TIMEOUT=""
HTTP_COMMAND_OVERRIDE=""
HTTP_HEADER_ARGS=()
HTTP_HEADERS=()

# The rendered request body
RENDERED_BODY=""

# The doctor mode
DOCTOR_MODE=false

# The configuration file was named explicitly but does not exist
CONFIG_FILE_MISSING=false

# The problem found in the resolved headers, and the audit line it writes
HEADER_PROBLEM=""
HEADER_AUDIT_MESSAGE=""

# The problems the doctor found
DOCTOR_PROBLEMS=()

# Prints usage and help message
show_help() {
    cat <<EOF
Disk Usage Monitor (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -p, --partition <path>    Mount point to watch (default: /).
  -t, --threshold <percent> Alert when usage is strictly greater (default: 80).
  -n, --dry-run             Report the alert without handing it to the mail agent.
      --notify <none|mail|http>
                             Notification backend (default: mail).
      --to <address>        Alert recipient (default: \$DISK_MONITOR_TO).
      --mail-command <cmd>  Mail agent to hand the alert to.
      --url <url>           HTTP endpoint to post the alert to.
      --body-template <text>
                             HTTP request body (default: the plain-text message).
      --header 'Name: value'
                             Extra HTTP header. One value may carry several
                             headers, one per line, and the flag may be
                             repeated.
      --timeout <seconds>   HTTP request timeout in seconds (default: 10).
      --http-command <cmd>  HTTP client to send the request with (default: curl).
  -l, --log-file <file>     Path to append ISO-8601 audit records.
      --config <file>       Configuration file to read (default: ./.diskmonitor.conf).
      --doctor              Report what is configured and what is missing.
  -v, --verbose             Enable diagnostic output.
  -h, --help                Show this help and usage documentation.

Configuration:
  A flag wins over an environment variable, which wins over the
  configuration file, which wins over the built-in default. The environment
  variables are DISK_MONITOR_PARTITION, DISK_MONITOR_THRESHOLD,
  DISK_MONITOR_NOTIFY, DISK_MONITOR_TO, DISK_MONITOR_MAIL_COMMAND,
  DISK_MONITOR_LOG_FILE, DISK_MONITOR_USAGE_COMMAND,
  DISK_MONITOR_USAGE_OVERRIDE, DISK_MONITOR_CONFIG, DISK_MONITOR_URL,
  DISK_MONITOR_BODY_TEMPLATE, DISK_MONITOR_HEADER, DISK_MONITOR_TIMEOUT and
  DISK_MONITOR_HTTP_COMMAND.

HTTP transport:
  One transport covers every HTTP notification service, because a request
  with a body to a URL is the same primitive everywhere. The body template
  supports {subject}, {body}, {partition}, {usage}, {threshold},
  {recipient}, {host} and {timestamp}; a JSON template therefore speaks to
  Telegram, Discord and Slack without provider-specific code. {recipient} is
  the endpoint the alert is addressed to, and {usage} and {threshold} carry
  the percent sign. The rendered body is written to the client's standard
  input, followed by a newline. A header value is never printed and never
  written to the audit log, because it may carry a token.

Doctor:
  --doctor reports the resolved configuration and where each value came
  from, whether the measurement command and the transport client can be
  resolved, and whether the recipient or the endpoint is set. It measures
  nothing and sends nothing. It exits 0 when the tool is ready to run and 1
  when something is missing, with one line per problem and the remedy for
  it. A missing dependency is named with the install command of the platform
  the tool was found on.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     mail agent, endpoint, timeout, method, header or HTTP client).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent or the HTTP client).

Examples:
  $0 -p / -t 80 --to ops@example.com
  $0 -p /home -t 90 -n -v
  $0 --notify http --url https://ntfy.sh/disk-alerts
  $0 --doctor
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
    local line_number=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        # A configuration file edited on Windows may carry carriage returns.
        line="${line%$'\r'}"
        line="$(trim "$line")"

        if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
            continue
        fi

        if [[ "$line" != *"="* ]]; then
            # The line is named, never shown: a line pasted into the file by
            # mistake may hold a bearer token.
            report_config_problem "malformed" "$line_number" ""
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
            url) CONFIG_URL="$value" ;;
            body_template) CONFIG_BODY_TEMPLATE="$value" ;;
            method) CONFIG_METHOD="$value" ;;
            timeout) CONFIG_TIMEOUT="$value" ;;
            header)
                if [[ -n "$CONFIG_HEADERS" ]]; then
                    CONFIG_HEADERS="${CONFIG_HEADERS}"$'\n'"${value}"
                else
                    CONFIG_HEADERS="$value"
                fi
                ;;
            *)
                report_config_problem "unknown" "$line_number" "$key"
                ;;
        esac
    done < "$file"
}

# Reports one problem found in the configuration file. A malformed line is
# named by its number and never shown, because a line pasted into the file by
# mistake may hold a bearer token. The doctor carries the problem in its own
# report; a run reports it as a warning.
report_config_problem() {
    local kind="$1"
    local line_number="$2"
    local key="$3"

    if [[ "$kind" == "malformed" ]]; then
        if [[ "$DOCTOR_MODE" == true ]]; then
            DOCTOR_PROBLEMS+=("The configuration file has a malformed line at line $line_number, which was ignored. Fix the line, or remove it.")
        else
            printf "%bWarning: ignoring malformed line %d in '%s'.%b\n" \
                "$COLOR_YELLOW" "$line_number" "$CONFIG_FILE" "$COLOR_RESET" >&2
        fi
        return 0
    fi

    if [[ "$DOCTOR_MODE" == true ]]; then
        DOCTOR_PROBLEMS+=("The configuration file has an unknown key '$key' at line $line_number, which was ignored. Remove the key, or check its spelling.")
    else
        printf "%bWarning: ignoring unknown configuration key '%s' in '%s'.%b\n" \
            "$COLOR_YELLOW" "$key" "$CONFIG_FILE" "$COLOR_RESET" >&2
    fi
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
            CONFIG_FILE="$candidate"
            CONFIG_FILE_MISSING=true
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
    apply_setting HTTP_URL SOURCE_URL "$HTTP_URL" "$FLAG_URL_SET" \
        "${DISK_MONITOR_URL:-}" "$CONFIG_URL" ""
    apply_setting HTTP_BODY_TEMPLATE SOURCE_BODY_TEMPLATE "$HTTP_BODY_TEMPLATE" \
        "$FLAG_BODY_TEMPLATE_SET" "${DISK_MONITOR_BODY_TEMPLATE:-}" "$CONFIG_BODY_TEMPLATE" ""
    apply_setting HTTP_METHOD SOURCE_METHOD "$HTTP_METHOD" "false" "" "$CONFIG_METHOD" "POST"
    apply_setting HTTP_TIMEOUT SOURCE_TIMEOUT "$HTTP_TIMEOUT" "$FLAG_TIMEOUT_SET" \
        "${DISK_MONITOR_TIMEOUT:-}" "$CONFIG_TIMEOUT" "10"
    apply_setting HTTP_COMMAND_OVERRIDE SOURCE_HTTP_COMMAND "$HTTP_COMMAND_OVERRIDE" \
        "$FLAG_HTTP_COMMAND_SET" "${DISK_MONITOR_HTTP_COMMAND:-}" "" ""
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

# Appends a header value to the header list. A value may carry several
# headers, one per line, which is the same shape the environment variable
# and the configuration file use. The flag may also be repeated.
append_header_value() {
    local value="$1"
    local header_line=""

    while IFS= read -r header_line; do
        header_line="${header_line%$'\r'}"
        if [[ -n "$header_line" ]]; then
            HTTP_HEADER_ARGS+=("$header_line")
        fi
    done <<< "$value"
}

# Resolves the headers the request carries. A command line header wins over
# an environment header, which wins over the headers in the configuration
# file, which wins over no header at all. Both the environment variable and
# the configuration file accept one header per line.
resolve_headers() {
    local env_header="${DISK_MONITOR_HEADER:-}"
    local config_header="$CONFIG_HEADERS"
    local header_line=""

    if [[ "$FLAG_HEADER_SET" == "true" ]]; then
        HTTP_HEADERS=()
        if [[ "${#HTTP_HEADER_ARGS[@]}" -gt 0 ]]; then
            HTTP_HEADERS=("${HTTP_HEADER_ARGS[@]}")
        fi
        SOURCE_HEADER="flag"
        return 0
    fi

    if [[ -n "$env_header" ]]; then
        HTTP_HEADERS=()
        while IFS= read -r header_line; do
            header_line="${header_line%$'\r'}"
            if [[ -n "$header_line" ]]; then
                HTTP_HEADERS+=("$header_line")
            fi
        done <<< "$env_header"
        SOURCE_HEADER="environment"
        return 0
    fi

    if [[ -n "$config_header" ]]; then
        HTTP_HEADERS=()
        while IFS= read -r header_line; do
            if [[ -n "$header_line" ]]; then
                HTTP_HEADERS+=("$header_line")
            fi
        done <<< "$config_header"
        SOURCE_HEADER="config"
        return 0
    fi

    HTTP_HEADERS=()
    SOURCE_HEADER="default"
}

# Validates the resolved headers. A header is a name and a value, and it must
# not carry a line break, which would let it inject a second header. The
# value is never reported: it may carry a bearer token. The problem is handed
# to the caller, which decides whether to fail the run or to report it.
check_headers() {
    local header=""
    local header_number=0

    HEADER_PROBLEM=""
    HEADER_AUDIT_MESSAGE=""

    if [[ "${#HTTP_HEADERS[@]}" -eq 0 ]]; then
        return 0
    fi

    for header in "${HTTP_HEADERS[@]}"; do
        header_number=$((header_number + 1))

        if [[ "$header" == *$'\n'* || "$header" == *$'\r'* ]]; then
            HEADER_PROBLEM="Header $header_number carries a line break."
            HEADER_AUDIT_MESSAGE="Malformed HTTP header: it carries a line break."
            return 1
        fi

        if [[ ! "$header" =~ ^[^:[:space:]]+:.*$ ]]; then
            HEADER_PROBLEM="Header $header_number is malformed. Expected 'Name: value'."
            HEADER_AUDIT_MESSAGE="Malformed HTTP header."
            return 1
        fi
    done

    return 0
}

# Fails the run when a header is malformed
validate_headers() {
    if check_headers; then
        return 0
    fi

    printf "%bError: %s%b\n" "$COLOR_RED" "$HEADER_PROBLEM" "$COLOR_RESET" >&2
    log_message "ERROR" "$HEADER_AUDIT_MESSAGE"
    exit 1
}

# Resolves the HTTP client that carries the request. The contract is:
#   --http-command  ->  DISK_MONITOR_HTTP_COMMAND  ->  curl
# An override may be a path to a file or the name of a command on PATH. The
# file is accepted when it exists: whether it can be run is decided when the
# request is made, which is the same rule the other implementation follows.
resolve_http_command() {
    local candidate=""

    if [[ -n "$HTTP_COMMAND_OVERRIDE" ]]; then
        if [[ -f "$HTTP_COMMAND_OVERRIDE" ]]; then
            printf '%s' "$HTTP_COMMAND_OVERRIDE"
            return 0
        fi
        if command -v "$HTTP_COMMAND_OVERRIDE" >/dev/null 2>&1; then
            command -v "$HTTP_COMMAND_OVERRIDE"
            return 0
        fi
        return 1
    fi

    candidate="$(command -v curl 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    return 1
}

# Resolves the measurement command to the program that runs it. The command
# is an external program, so it is resolved the way the mail agent and the
# HTTP client are resolved: by name on PATH.
resolve_usage_command() {
    local candidate="$1"

    if [[ -z "$candidate" ]]; then
        return 1
    fi

    if command -v "$candidate" >/dev/null 2>&1; then
        command -v "$candidate"
        return 0
    fi

    return 1
}

# Reads the identifier of the distribution from the os-release file. The file
# is only read: the tool does not need it, it names the system in the report.
read_os_release_identifier() {
    local line=""

    if [[ ! -r /etc/os-release ]]; then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == ID=* ]]; then
            line="${line#ID=}"
            line="${line%\"}"
            line="${line#\"}"
            line="${line%\'}"
            line="${line#\'}"
            printf '%s' "$line"
            return 0
        fi
    done < /etc/os-release

    return 1
}

# Names the platform the tool is running on. The distribution is read from
# the file every Linux distribution ships, so the report names the system the
# tool was found on and not only the kernel.
resolve_platform_name() {
    local kernel=""
    local identifier=""

    kernel="$(uname -s 2>/dev/null || printf 'unknown')"

    case "$kernel" in
        Darwin)
            printf 'macOS'
            return 0
            ;;
        Linux)
            ;;
        *)
            printf '%s' "$kernel"
            return 0
            ;;
    esac

    identifier="$(read_os_release_identifier || true)"
    if [[ -n "$identifier" ]]; then
        printf 'Linux (%s)' "$identifier"
        return 0
    fi

    printf 'Linux'
}

# Prints the command that installs a package on this platform. The package
# manager is the one that is installed, so the remedy names a command the
# reader can run. The package name is the same on every distribution, only
# the syntax of the command differs.
resolve_install_command() {
    local package="$1"
    local kernel=""
    local manager=""

    kernel="$(uname -s 2>/dev/null || printf 'unknown')"

    if [[ "$kernel" == "Darwin" ]]; then
        printf 'brew install %s' "$package"
        return 0
    fi

    for manager in apt-get dnf yum pacman apk zypper; do
        if command -v "$manager" >/dev/null 2>&1; then
            case "$manager" in
                apt-get) printf 'sudo apt-get install %s' "$package" ;;
                dnf) printf 'sudo dnf install %s' "$package" ;;
                yum) printf 'sudo yum install %s' "$package" ;;
                pacman) printf 'sudo pacman -S %s' "$package" ;;
                apk) printf 'sudo apk add %s' "$package" ;;
                zypper) printf 'sudo zypper install %s' "$package" ;;
            esac
            return 0
        fi
    done

    return 1
}

# The remedy for a dependency that is not installed. The install command is
# the one of the platform the tool was found on, because a generic suggestion
# is not an instruction the reader can run.
dependency_remedy() {
    local dependency="$1"
    local package="coreutils"
    local alternative="or set DISK_MONITOR_USAGE_COMMAND to another measurement command"
    local install_command=""

    case "$dependency" in
        curl)
            package="curl"
            alternative="or set --http-command to another HTTP client"
            ;;
        msmtp)
            package="msmtp"
            alternative="or set --mail-command to another mail agent"
            ;;
    esac

    if install_command="$(resolve_install_command "$package")"; then
        printf 'Install it with: %s' "$install_command"
        return 0
    fi

    printf 'Install %s with your package manager, %s.' "$package" "$alternative"
}

# Renders the body template into the target variable.
# The template is scanned from left to right and the earliest known
# placeholder is replaced wherever it appears. A value is never re-scanned, so
# a partition named "{usage}" cannot be substituted a second time. An unknown
# placeholder is copied verbatim, which is what keeps a JSON template intact:
# only the known names are substituted, the JSON braces are not.
# The arguments are the target, the template, and then the value of each
# placeholder in the order the contract defines: subject, body, partition,
# usage, threshold, recipient, host and timestamp.
render_body_template() {
    local target="$1"
    local template="$2"
    local subject_value="$3"
    local body_value="$4"
    local partition_value="$5"
    local usage_value="$6"
    local threshold_value="$7"
    local recipient_value="$8"
    local host_value="$9"
    local timestamp_value="${10}"

    local rendered=""
    local rest="$template"
    local key=""
    local prefix=""
    local position=0
    local best_key=""
    local best_position=-1
    local value=""

    while [[ -n "$rest" ]]; do
        best_key=""
        best_position=-1

        for key in subject body partition usage threshold recipient host timestamp; do
            prefix="${rest%%"{$key}"*}"
            if [[ "$prefix" != "$rest" ]]; then
                position=${#prefix}
                if [[ "$best_position" -lt 0 || "$position" -lt "$best_position" ]]; then
                    best_position=$position
                    best_key="$key"
                fi
            fi
        done

        if [[ "$best_position" -lt 0 ]]; then
            rendered="${rendered}${rest}"
            break
        fi

        rendered="${rendered}${rest:0:$best_position}"

        case "$best_key" in
            subject) value="$subject_value" ;;
            body) value="$body_value" ;;
            partition) value="$partition_value" ;;
            usage) value="$usage_value" ;;
            threshold) value="$threshold_value" ;;
            recipient) value="$recipient_value" ;;
            host) value="$host_value" ;;
            timestamp) value="$timestamp_value" ;;
        esac

        rendered="${rendered}${value}"
        rest="${rest:$((best_position + ${#best_key} + 2))}"
    done

    printf -v "$target" '%s' "$rendered"
}

# Hands the alert to the resolved HTTP client. The contract is:
#   <http-command> --silent --show-error --max-time <seconds>
#                   --request <method> --header <name: value>...
#                   --data-binary @- <url>
# with the rendered body on standard input.
send_http_alert() {
    local url="$1"
    local body="$2"
    local method="$3"
    local timeout="$4"
    local header=""
    local -a client_args

    client_args=(--silent --show-error --max-time "$timeout" --request "$method")
    if [[ "${#HTTP_HEADERS[@]}" -gt 0 ]]; then
        for header in "${HTTP_HEADERS[@]}"; do
            client_args+=(--header "$header")
        done
    fi
    client_args+=(--data-binary "@-" "$url")

    printf '%s\n' "$body" | "$HTTP_CLIENT" "${client_args[@]}"
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
            --url)
                require_value "$1" "$#"
                HTTP_URL="$2"
                FLAG_URL_SET=true
                shift 2
                ;;
            --body-template)
                require_value "$1" "$#"
                HTTP_BODY_TEMPLATE="$2"
                FLAG_BODY_TEMPLATE_SET=true
                shift 2
                ;;
            --header)
                require_value "$1" "$#"
                append_header_value "$2"
                FLAG_HEADER_SET=true
                shift 2
                ;;
            --timeout)
                require_value "$1" "$#"
                HTTP_TIMEOUT="$2"
                FLAG_TIMEOUT_SET=true
                shift 2
                ;;
            --http-command)
                require_value "$1" "$#"
                HTTP_COMMAND_OVERRIDE="$2"
                FLAG_HTTP_COMMAND_SET=true
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
            --doctor)
                DOCTOR_MODE=true
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

    if [[ "$NOTIFY_MODE" != "none" && "$NOTIFY_MODE" != "mail" && "$NOTIFY_MODE" != "http" ]]; then
        printf "%bError: Notify backend must be 'none', 'mail' or 'http'.%b\n" \
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

    if ! resolve_usage_command "$USAGE_COMMAND_OVERRIDE" >/dev/null; then
        printf "%bError: Measurement command '%s' was not found.%b\n" \
            "$COLOR_RED" "$USAGE_COMMAND_OVERRIDE" "$COLOR_RESET" >&2
        log_message "ERROR" "Measurement command not found: '$USAGE_COMMAND_OVERRIDE'."
        exit 1
    fi

    if [[ "$NOTIFY_MODE" != "mail" && "$NOTIFY_MODE" != "http" ]]; then
        return 0
    fi

    if [[ "$NOTIFY_MODE" == "mail" ]]; then
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

        return 0
    fi

    if [[ -z "$HTTP_URL" ]]; then
        printf "%bError: No endpoint. Use --url, or set DISK_MONITOR_URL.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "No HTTP endpoint configured."
        exit 1
    fi

    if [[ ! "$HTTP_URL" =~ ^https?://[^[:space:]]+$ ]]; then
        printf "%bError: Endpoint '%s' is not a valid http or https URL.%b\n" \
            "$COLOR_RED" "$HTTP_URL" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid HTTP endpoint: '$HTTP_URL'."
        exit 1
    fi

    if [[ ! "$HTTP_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$HTTP_TIMEOUT" -lt 1 ]]; then
        printf "%bError: Timeout must be an integer of seconds greater than zero.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid HTTP timeout: '$HTTP_TIMEOUT'."
        exit 1
    fi

    if [[ ! "$HTTP_METHOD" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
        printf "%bError: HTTP method must be a token, for example POST.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "Invalid HTTP method: '$HTTP_METHOD'."
        exit 1
    fi

    if ! HTTP_CLIENT="$(resolve_http_command)"; then
        printf "%bError: No HTTP client found. Install one, or set --http-command or DISK_MONITOR_HTTP_COMMAND.%b\n" \
            "$COLOR_RED" "$COLOR_RESET" >&2
        log_message "ERROR" "No HTTP client could be resolved."
        exit 1
    fi

    validate_headers
}

# Prints one field of the doctor report. The source of the value is shown
# with it, so the reader can see where a setting came from.
doctor_field() {
    local label="$1"
    local value="$2"
    local source="${3:-}"

    if [[ -n "$source" ]]; then
        printf "%-20s: %s (%s)\n" "$label" "$value" "$source"
        return 0
    fi

    printf "%-20s: %s\n" "$label" "$value"
}

# Records one problem the doctor found. Every problem carries its own
# remedy, on one line.
add_doctor_problem() {
    DOCTOR_PROBLEMS+=("$1")
}

# Reports what is configured and what is missing, and changes nothing. The
# disk is not measured and nothing is sent: the report is the whole point.
# The exit code tells the reader whether the tool is ready to run.
run_doctor() {
    local platform=""
    local usage_command=""
    local http_client=""
    local mail_command=""

    platform="$(resolve_platform_name)"

    # The configuration file
    if [[ "$CONFIG_FILE_MISSING" == true ]]; then
        add_doctor_problem "The configuration file '$CONFIG_FILE' was not found. Create it, or point --config at a file that exists."
    fi

    # The threshold
    if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 ]] || [[ "$THRESHOLD" -gt 100 ]]; then
        add_doctor_problem "The threshold '$THRESHOLD' is not an integer between 1 and 100. Set --threshold to a number between 1 and 100."
    fi

    # The notify backend
    if [[ "$NOTIFY_MODE" != "none" && "$NOTIFY_MODE" != "mail" && "$NOTIFY_MODE" != "http" ]]; then
        add_doctor_problem "The notify backend '$NOTIFY_MODE' is not supported. Set --notify to none, mail or http."
    fi

    # The partition
    if [[ ! -d "$PARTITION" ]]; then
        add_doctor_problem "The partition '$PARTITION' does not exist. Set --partition to a mount point that exists."
    fi

    # The measurement command
    if ! usage_command="$(resolve_usage_command "$USAGE_COMMAND_OVERRIDE")"; then
        add_doctor_problem "The measurement command '$USAGE_COMMAND_OVERRIDE' was not found. $(dependency_remedy coreutils)"
    fi

    # The transport
    if [[ "$NOTIFY_MODE" == "mail" ]]; then
        if [[ -z "$MAIL_TO" ]]; then
            add_doctor_problem "No recipient is configured. Set --to, or DISK_MONITOR_TO, or the 'to' key in the configuration file."
        fi

        if ! mail_command="$(resolve_mail_command)"; then
            add_doctor_problem "No mail agent was found. $(dependency_remedy msmtp)"
        fi
    elif [[ "$NOTIFY_MODE" == "http" ]]; then
        if [[ -z "$HTTP_URL" ]]; then
            add_doctor_problem "No endpoint is configured. Set --url, or DISK_MONITOR_URL, or the 'url' key in the configuration file."
        elif [[ ! "$HTTP_URL" =~ ^https?://[^[:space:]]+$ ]]; then
            add_doctor_problem "The endpoint '$HTTP_URL' is not a valid http or https URL. Set --url to a URL that starts with http:// or https://."
        fi

        if [[ ! "$HTTP_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$HTTP_TIMEOUT" -lt 1 ]]; then
            add_doctor_problem "The HTTP timeout '$HTTP_TIMEOUT' is not a whole number of seconds above zero. Set --timeout to a whole number of seconds."
        fi

        if [[ ! "$HTTP_METHOD" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
            add_doctor_problem "The HTTP method '$HTTP_METHOD' is not a valid token. Set the method to a name such as POST."
        fi

        if ! check_headers; then
            add_doctor_problem "$HEADER_PROBLEM"
        fi

        if ! http_client="$(resolve_http_command)"; then
            if [[ -n "$HTTP_COMMAND_OVERRIDE" ]]; then
                add_doctor_problem "The HTTP client '$HTTP_COMMAND_OVERRIDE' was not found. Install it, or set --http-command to another HTTP client."
            else
                add_doctor_problem "curl was not found. $(dependency_remedy curl)"
            fi
        fi
    fi

    # The report
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                 Disk Usage Monitor - Doctor                 %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    doctor_field "Platform" "$platform"

    if [[ "$CONFIG_FILE_MISSING" == true ]]; then
        doctor_field "Config file" "(not found: $CONFIG_FILE)"
    elif [[ -n "$CONFIG_FILE" ]]; then
        doctor_field "Config file" "$CONFIG_FILE"
    else
        doctor_field "Config file" "(none found)"
    fi

    doctor_field "Partition" "$PARTITION" "$SOURCE_PARTITION"
    doctor_field "Threshold" "${THRESHOLD}%" "$SOURCE_THRESHOLD"
    doctor_field "Notify backend" "$NOTIFY_MODE" "$SOURCE_NOTIFY"

    if [[ "$NOTIFY_MODE" == "http" ]]; then
        if [[ -n "$HTTP_URL" ]]; then
            doctor_field "Endpoint" "$HTTP_URL" "$SOURCE_URL"
        else
            doctor_field "Endpoint" "(not set)"
        fi
        doctor_field "Recipient" "(not required)"
        if [[ -n "$http_client" ]]; then
            doctor_field "HTTP client" "$http_client" "$SOURCE_HTTP_COMMAND"
        else
            doctor_field "HTTP client" "(not found)"
        fi
    elif [[ "$NOTIFY_MODE" == "mail" ]]; then
        doctor_field "Endpoint" "(not required)"
        if [[ -n "$MAIL_TO" ]]; then
            doctor_field "Recipient" "$MAIL_TO" "$SOURCE_TO"
        else
            doctor_field "Recipient" "(not set)"
        fi
        doctor_field "HTTP client" "(not required)"
    else
        doctor_field "Endpoint" "(not required)"
        doctor_field "Recipient" "(not required)"
        doctor_field "HTTP client" "(not required)"
    fi

    if [[ "$NOTIFY_MODE" == "mail" ]]; then
        if [[ -n "$mail_command" ]]; then
            doctor_field "Mail agent" "$mail_command" "$SOURCE_MAIL_COMMAND"
        else
            doctor_field "Mail agent" "(not found)"
        fi
    else
        doctor_field "Mail agent" "(not required)"
    fi

    if [[ -n "$usage_command" ]]; then
        doctor_field "Measurement command" "$usage_command" "$SOURCE_USAGE_COMMAND"
    else
        doctor_field "Measurement command" "(not found)"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        doctor_field "Audit log file" "$LOG_FILE" "$SOURCE_LOG_FILE"
    else
        doctor_field "Audit log file" "(not set)"
    fi

    doctor_field "HTTP headers" "${#HTTP_HEADERS[@]}" "$SOURCE_HEADER"

    printf "%b------------------------------------------------------------%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    if [[ "${#DOCTOR_PROBLEMS[@]}" -eq 0 ]]; then
        printf "%-20s: %bREADY%b\n" "Status" "$COLOR_GREEN" "$COLOR_RESET"
        return 0
    fi

    printf "%-20s: %bNOT READY%b\n" "Status" "$COLOR_YELLOW" "$COLOR_RESET"
    for problem in "${DOCTOR_PROBLEMS[@]}"; do
        printf "  - %s\n" "$problem"
    done

    return 1
}

# Main execution entrypoint
main() {
    parse_arguments "$@"
    DOCTOR_PROBLEMS=()
    load_configuration

    if [[ "$CONFIG_FILE_MISSING" == true && "$DOCTOR_MODE" != true ]]; then
        printf "%bError: Configuration file '%s' does not exist.%b\n" \
            "$COLOR_RED" "$CONFIG_FILE" "$COLOR_RESET" >&2
        exit 1
    fi

    apply_precedence
    resolve_headers

    if [[ "$DOCTOR_MODE" == true ]]; then
        if run_doctor; then
            exit 0
        fi
        exit 1
    fi

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
    if [[ "$NOTIFY_MODE" == "http" ]]; then
        printf "Endpoint          : %b%s%b\n" "$COLOR_CYAN" "$HTTP_URL" "$COLOR_RESET"
        printf "HTTP Client       : %b%s%b\n" "$COLOR_CYAN" "$HTTP_CLIENT" "$COLOR_RESET"
    else
        printf "Mail Agent        : %b%s%b\n" "$COLOR_CYAN" "$mail_label" "$COLOR_RESET"
        if [[ "$NOTIFY_MODE" == "mail" ]]; then
            printf "Recipient         : %b%s%b\n" "$COLOR_CYAN" "$MAIL_TO" "$COLOR_RESET"
        fi
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
        if [[ "$NOTIFY_MODE" == "http" ]]; then
            printf "%bTransport          : %bendpoint %s, body template %s, method %s, timeout %s, http command %s, headers %s (%s)%b\n" \
                "$COLOR_BLUE" "$COLOR_RESET" \
                "$SOURCE_URL" "$SOURCE_BODY_TEMPLATE" "$SOURCE_METHOD" "$SOURCE_TIMEOUT" \
                "$SOURCE_HTTP_COMMAND" "${#HTTP_HEADERS[@]}" "$SOURCE_HEADER" \
                "$COLOR_RESET"
        fi
    fi

    if [[ "$used_percent" -gt "$THRESHOLD" ]]; then
        printf "%bWARNING: Disk usage exceeds the threshold.%b\n" "$COLOR_RED" "$COLOR_RESET"

        local host
        host="$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "unknown-host")"
        local timestamp
        timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        local subject="Disk Alert: ${PARTITION} at ${used_percent}%"
        local body
        body="$(printf 'Disk usage on %s is at %s%% (threshold: %s%%).\n\nPartition : %s\nUsage    : %s%%\nThreshold: %s%%\nTime     : %s' \
            "$host" "$used_percent" "$THRESHOLD" "$PARTITION" "$used_percent" "$THRESHOLD" \
            "$timestamp")"

        local notification_target="$MAIL_TO"
        if [[ "$NOTIFY_MODE" == "http" ]]; then
            notification_target="$HTTP_URL"
        fi

        if [[ "$DRY_RUN" == true ]]; then
            printf "%b[DRY RUN]%b Would send an alert to %s\n" \
                "$COLOR_YELLOW" "$COLOR_RESET" "$notification_target"
            log_message "INFO" "[DRY RUN] Would send an alert to $notification_target (Usage: ${used_percent}%, Source: ${usage_source}, Threshold: ${THRESHOLD}%)"
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
        elif [[ "$NOTIFY_MODE" == "http" ]]; then
            local template="$HTTP_BODY_TEMPLATE"
            if [[ -z "$template" ]]; then
                template="$body"
            fi
            render_body_template RENDERED_BODY "$template" "$subject" "$body" "$PARTITION" \
                "${used_percent}%" "${THRESHOLD}%" "$HTTP_URL" "$host" "$timestamp"

            if send_http_alert "$HTTP_URL" "$RENDERED_BODY" "$HTTP_METHOD" "$HTTP_TIMEOUT"; then
                printf "%bAlert sent to %s%b\n" "$COLOR_GREEN" "$HTTP_URL" "$COLOR_RESET"
                log_message "INFO" "ALERT SENT to $HTTP_URL (Usage: ${used_percent}%, Source: ${usage_source}, Threshold: ${THRESHOLD}%)"
            else
                printf "%bError: The alert could not be handed to the HTTP client.%b\n" \
                    "$COLOR_RED" "$COLOR_RESET" >&2
                log_message "ERROR" "FAILED to hand the alert to the HTTP client (Usage: ${used_percent}%, Source: ${usage_source})"
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
