#!/bin/bash
# Run the two Bash walkthroughs without accessing host service or logging facilities.
set -euo pipefail
IFS=$'
	'

if [[ $# -ne 1 || ( $1 != 1 && $1 != 2 ) ]]; then
    printf '%s
' 'Usage: bash docs/labs/run_service_monitor_lab.sh {1|2}' >&2
    exit 1
fi
lab=$1
monitor="$PWD/service_monitor.sh"
if [[ ! -x "$monitor" ]]; then
    printf '%s
' 'Run the lab from the Service Monitor module directory.' >&2
    exit 1
fi

temp_root=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P)
scratch=$(mktemp -d "$temp_root/service-monitor-lab.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
cd -- "$scratch"

cat > systemctl <<'EOF'
#!/bin/bash
set -euo pipefail
svc="${!#}"
case "$svc" in
    lab-running|lab-down|lab-recover|lab-stuck) ;;
    *) exit 1 ;;
esac
case "$1" in
    show) printf 'loaded
' ;;
    is-active) [[ "$svc" == lab-running || -f "$svc.active" ]] ;;
    restart)
        printf '%s
' "$svc" >> restarts
        [[ "$svc" == lab-recover ]] || exit 1
        if [[ ! -f recover-attempted ]]; then
            : > recover-attempted
            exit 1
        fi
        : > "$svc.active"
        ;;
    *) exit 1 ;;
esac
EOF
cat > ./logger <<'EOF'
#!/bin/bash
IFS= read -r message
case "$message" in
    'Service lab-recover was restarted on '*) printf 'lab-recover
' >> notifications ;;
    *) printf 'unexpected notification
' >> notifications; exit 1 ;;
esac
EOF
chmod u+x systemctl logger
if [[ ! -x ./systemctl || ! -x ./logger ]]; then
    printf '%s
' 'Lab requires both private service helpers.' >&2
    exit 1
fi

# Allow only the two harmless external utilities the monitor needs in addition to the mocks.
date_path=$(command -p -v date)
sleep_path=$(command -p -v sleep)
[[ "$date_path" == /* && "$sleep_path" == /* ]]
ln -s -- "$date_path" date
ln -s -- "$sleep_path" sleep

run_monitor() {
    # An empty environment excludes imported functions and startup files. The scratch-only
    # PATH cannot resolve the host's systemctl or logger, even if a mock goes missing.
    command -p env -i PATH=. LC_ALL=C "$monitor" "$@"
}

if [[ "$lab" == 1 ]]; then
    run_monitor -s lab-running --dry-run --csv
    run_monitor -s lab-down --dry-run --csv
    [[ ! -e restarts && ! -e notifications ]]
else
    run_monitor -s lab-recover -r 3 --retry-delay 0 --csv
    status=0
    run_monitor -s lab-stuck -r 2 --retry-delay 0 --csv || status=$?
    [[ "$status" == 2 ]]
    [[ $(< restarts) == $'lab-recover
lab-recover
lab-stuck
lab-stuck' ]]
    [[ $(< notifications) == lab-recover ]]
fi
