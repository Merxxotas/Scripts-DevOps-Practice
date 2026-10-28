#!/bin/bash
# ==============================================================================
# Script Name: git_deploy.sh
# Description: Automated Git deployment.
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
APP_DIR="/var/www/myapp"
REPO_URL="git@github.com:company/myapp.git"
BRANCH="main"
BACKUP_DIR="/backup/deployments"
SKIP_BACKUP=false
SKIP_POST_DEPLOY=false
SERVICE_NAME="myapp"
DRY_RUN=false
AUDIT_LOG=""
VERBOSE=false

# Metrics / state
DEPLOYED=false
FAILED_COUNT=0

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

require_value() {
    if [[ $# -lt 2 || -z "${2:-}" ]]; then
        printf "%bError: Option '%s' requires a value.%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
        exit 1
    fi
}

is_protected_path() {
    local target="$1"
    local resolved dir norm_dir
    if command -v realpath >/dev/null 2>&1; then
        resolved="$(realpath "$target" 2>/dev/null || echo "$target")"
    else
        resolved="$target"
    fi
    dir="$(dirname "$resolved")"
    norm_dir="$dir"
    [[ "$norm_dir" != "/" ]] && norm_dir="${norm_dir%/}"

    local -a protected=(
        "/" "/bin" "/sbin" "/usr" "/etc" "/dev" "/proc" "/sys" "/boot" "/root"
        "/var" "/tmp" "/home" "/private" "/Library" "/System" "/Applications" "/Volumes"
    )
    for p in "${protected[@]}"; do
        if [[ "$norm_dir" == "$p" ]]; then
            return 0
        fi
    done
    return 1
}

valid_branch() {
    [[ "${1:-}" =~ ^[a-zA-Z0-9._/-]+$ ]]
}

show_help() {
    cat <<EOF
Automated Git Deployment Utility (Bash)
Usage: $0 [OPTIONS]

Optional Arguments:
  -a, --app-dir <path>      Application directory (default: /var/www/myapp).
  -r, --repo-url <url>      Repository URL.
  -b, --branch <name>       Branch to deploy (default: main).
      --backup-dir <path>    Backup directory (default: /backup/deployments).
      --skip-backup          Skip pre-deploy backup.
      --skip-post-deploy     Skip npm install and service restart.
      --service <name>       Service to restart (default: myapp).
      --dry-run              Preview only.
      --audit-log <file>     Append ISO-8601 audit log entries.
  -v, --verbose            Enable diagnostic output.
  -h, --help               Show this help and usage documentation.

Examples:
  $0
  $0 -a /var/www/myapp -b develop
  $0 --dry-run
  $0 --skip-post-deploy
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

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--app-dir)
                require_value "$1" "$#"
                APP_DIR="$2"
                shift 2
                ;;
            -r|--repo-url)
                require_value "$1" "$#"
                REPO_URL="$2"
                shift 2
                ;;
            -b|--branch)
                require_value "$1" "$#"
                BRANCH="$2"
                shift 2
                ;;
            --backup-dir)
                require_value "$1" "$#"
                BACKUP_DIR="$2"
                shift 2
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --skip-post-deploy)
                SKIP_POST_DEPLOY=true
                shift
                ;;
            --service)
                require_value "$1" "$#"
                SERVICE_NAME="$2"
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

    if [[ -z "$APP_DIR" ]]; then
        printf "%bError: App directory is required.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if [[ -z "$BRANCH" ]]; then
        printf "%bError: Branch is required.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        exit 1
    fi
    if ! valid_branch "$BRANCH"; then
        printf "%bError: Invalid branch name '%s'.%b\n" "$COLOR_RED" "$BRANCH" "$COLOR_RESET" >&2
        exit 1
    fi
    if is_protected_path "$APP_DIR"; then
        printf "%bError: App directory '%s' is in a protected system directory.%b\n" "$COLOR_RED" "$APP_DIR" "$COLOR_RESET" >&2
        exit 1
    fi
    if [[ ! -d "$APP_DIR" ]]; then
        printf "%bError: App directory '%s' does not exist or is not a directory.%b\n" "$COLOR_RED" "$APP_DIR" "$COLOR_RESET" >&2
        exit 1
    fi
    if is_protected_path "$BACKUP_DIR"; then
        printf "%bError: Backup directory '%s' is in a protected system directory.%b\n" "$COLOR_RED" "$BACKUP_DIR" "$COLOR_RESET" >&2
        exit 1
    fi
}

main() {
    parse_arguments "$@"

    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b            DevOps Git Deployment Utility                  %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "App Directory    : %b%s%b\n" "$COLOR_CYAN" "$APP_DIR" "$COLOR_RESET"
    printf "Repository       : %b%s%b\n" "$COLOR_CYAN" "$REPO_URL" "$COLOR_RESET"
    printf "Branch           : %b%s%b\n" "$COLOR_CYAN" "$BRANCH" "$COLOR_RESET"
    printf "Backup Directory : %b%s%b\n" "$COLOR_CYAN" "$BACKUP_DIR" "$COLOR_RESET"
    printf "Skip Backup      : %b%s%b\n" "$COLOR_CYAN" "$SKIP_BACKUP" "$COLOR_RESET"
    printf "Skip Post-Deploy : %b%s%b\n" "$COLOR_CYAN" "$SKIP_POST_DEPLOY" "$COLOR_RESET"
    if [[ "$VERBOSE" == true ]]; then
        printf "%b[VERBOSE]%b app_dir=%s branch=%s service=%s\n" "$COLOR_CYAN" "$COLOR_RESET" "$APP_DIR" "$BRANCH" "$SERVICE_NAME"
    fi
    if [[ -n "$AUDIT_LOG" ]]; then
        printf "Audit Log        : %b%s%b\n" "$COLOR_CYAN" "$AUDIT_LOG" "$COLOR_RESET"
    fi
    printf "\n"

    # Dry-run
    if [[ "$DRY_RUN" == true ]]; then
        printf "%b[DRY RUN]%b Would deploy '%s' from %s (%s).\n" "$COLOR_YELLOW" "$COLOR_RESET" "$APP_DIR" "$REPO_URL" "$BRANCH"
        if [[ "$SKIP_BACKUP" != true ]]; then
            printf "%b[DRY RUN]%b Would create backup in %s.\n" "$COLOR_YELLOW" "$COLOR_RESET" "$BACKUP_DIR"
        fi
        printf "%b[DRY RUN]%b Would git fetch origin %s.\n" "$COLOR_YELLOW" "$COLOR_RESET" "$BRANCH"
        printf "%b[DRY RUN]%b Would git pull origin %s if behind.\n" "$COLOR_YELLOW" "$COLOR_RESET" "$BRANCH"
        if [[ "$SKIP_POST_DEPLOY" != true ]]; then
            printf "%b[DRY RUN]%b Would run post-deploy (npm install if package.json; restart %s).\n" "$COLOR_YELLOW" "$COLOR_RESET" "$SERVICE_NAME"
        fi
        log_message "INFO" "[DRY RUN] Deploy planned for '$APP_DIR'."
        exit 0
    fi

    cd "$APP_DIR" || { printf "%bError: cannot cd to %s.%b\n" "$COLOR_RED" "$APP_DIR" "$COLOR_RESET" >&2; exit 1; }

    # Backup
    if [[ "$SKIP_BACKUP" != true ]]; then
        printf "%bCreating backup...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
        local timestamp backup_file
        timestamp="$(date +%Y%m%d_%H%M%S)"
        backup_file="$BACKUP_DIR/backup_$timestamp.tar.gz"
        mkdir -p "$BACKUP_DIR" 2>/dev/null || true
        if tar -czf "$backup_file" -C "$APP_DIR" . 2>/dev/null; then
            printf "%b✓ Backup created: %s%b\n" "$COLOR_GREEN" "$backup_file" "$COLOR_RESET"
            log_message "INFO" "Backup created: $backup_file"
        else
            printf "%b✗ Backup failed.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
            FAILED_COUNT=$((FAILED_COUNT + 1))
            log_message "ERROR" "Backup failed."
        fi
    fi

    # Fetch
    printf "\n%bFetching updates...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
    if ! git fetch origin "$BRANCH" 2>/dev/null; then
        printf "%b✗ Git fetch failed.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
        log_message "ERROR" "Git fetch failed."
    fi

    local local_rev remote_rev
    local_rev="$(git rev-parse @ 2>/dev/null || echo "")"
    remote_rev="$(git rev-parse "@{u}" 2>/dev/null || echo "")"

    if [[ -n "$local_rev" && "$local_rev" == "$remote_rev" ]]; then
        printf "%b✓ Already up to date%b\n" "$COLOR_GREEN" "$COLOR_RESET"
        log_message "INFO" "Already up to date ($APP_DIR)."
        # Summary
        printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        printf "App Directory    : %b%s%b\n" "$COLOR_BOLD" "$APP_DIR" "$COLOR_RESET"
        printf "Result           : %balready up to date%b\n" "$COLOR_GREEN" "$COLOR_RESET"
        printf "Failed Steps     : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
        printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
        if [[ "$FAILED_COUNT" -gt 0 ]]; then exit 2; fi
        exit 0
    fi

    printf "%bChanges detected. Deploying...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"

    # Pull
    if git pull origin "$BRANCH" 2>/dev/null; then
        printf "%b✓ Code updated%b\n" "$COLOR_GREEN" "$COLOR_RESET"
        DEPLOYED=true
        log_message "INFO" "Code updated ($APP_DIR)."

        # Post-deploy
        if [[ "$SKIP_POST_DEPLOY" != true ]]; then
            printf "\n%bRunning post-deployment tasks...%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
            if [[ -f "package.json" ]]; then
                if command -v npm >/dev/null 2>&1; then
                    if npm install 2>/dev/null; then
                        printf "%b✓ Dependencies installed%b\n" "$COLOR_GREEN" "$COLOR_RESET"
                    else
                        printf "%b✗ npm install failed.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                        log_message "ERROR" "npm install failed."
                    fi
                else
                    printf "%b⚠ npm not found, skipping.%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
                fi
            fi
            # Service restart
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
                    printf "%b✓ Service %s restarted%b\n" "$COLOR_GREEN" "$SERVICE_NAME" "$COLOR_RESET"
                else
                    printf "%b✗ Service restart failed.%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    log_message "ERROR" "Service restart failed ($SERVICE_NAME)."
                fi
            else
                printf "%b⚠ systemctl not found, skipping service restart.%b\n" "$COLOR_YELLOW" "$COLOR_RESET"
            fi
        fi
    else
        printf "%b✗ Git pull failed%b\n" "$COLOR_RED" "$COLOR_RESET" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
        log_message "ERROR" "Git pull failed ($APP_DIR)."
    fi

    # Summary
    printf "\n%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b                    Execution Summary                       %b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"
    printf "App Directory    : %b%s%b\n" "$COLOR_BOLD" "$APP_DIR" "$COLOR_RESET"
    printf "Result           : %b%s%b\n" "$COLOR_BOLD" "$([[ "$DEPLOYED" == true ]] && echo deployed || echo failed)" "$COLOR_RESET"
    printf "Failed Steps     : %b%d%b\n" "$COLOR_RED" "$FAILED_COUNT" "$COLOR_RESET"
    printf "%b============================================================%b\n" "$COLOR_BLUE" "$COLOR_RESET"

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        log_message "ERROR" "Completed with failures (failed=$FAILED_COUNT)."
        exit 2
    fi
    log_message "INFO" "Deployment completed ($APP_DIR)."
    exit 0
}

main "$@"
