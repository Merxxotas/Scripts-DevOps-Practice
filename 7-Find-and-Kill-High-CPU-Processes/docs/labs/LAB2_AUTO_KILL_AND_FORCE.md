# Lab 2 — Preview termination and verify the audit log

Preview a synthetic high-CPU process, then simulate SIGTERM and SIGKILL. The lab never lists or
signals real processes: it runs the unchanged Bash utility with a fake `ps` and a recording `kill`.
Do not run the automatic termination flags separately on your host.

## Run the isolated lab

From the High-CPU Processes module directory, paste the whole block into Bash. The subshell keeps
your working directory and `PATH` unchanged. Its private scratch directory contains all fixtures
and the audit log, and is removed on exit.

```bash
# lab2-isolated-example
(
    set -euo pipefail
    unset BASH_ENV
    export LC_ALL=C

    utility="$PWD/kill_high_cpu.sh"
    [[ -x "$utility" ]] || {
        printf '%s\n' 'Run Lab 2 from the High-CPU Processes module directory.' >&2
        exit 1
    }

    temp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
    scratch=$(mktemp -d "$temp_root/high-cpu-lab2.XXXXXXXX")
    trap 'rm -rf -- "$scratch"' EXIT
    cd -- "$scratch"
    export TMPDIR="$scratch"
    mkdir bin

    cat > bin/ps <<'EOF'
#!/bin/bash
printf '%s\n' '987654321 1 95.0 lab-worker'
EOF
    cat > bin/kill <<'EOF'
#!/bin/bash
set -euo pipefail
[[ $# -eq 2 && $2 == 987654321 ]] || exit 1
printf '%s %s\n' "$1" "$2" >> signals.log
case "$1" in
    -TERM|-9) exit 0 ;;
    -0) exit 1 ;; # The synthetic process is gone after SIGTERM.
    *) exit 1 ;;
esac
EOF
    chmod u+x bin/ps bin/kill
    export PATH="./bin:$PATH"

    # The utility resolves external commands through PATH; refuse any fallback.
    if [[ $(type -P ps) != ./bin/ps || $(type -P kill) != ./bin/kill ]]; then
        printf '%s\n' 'Lab 2 requires both private process helpers.' >&2
        exit 1
    fi

    "$utility" -t 80 --auto-kill --dry-run --csv
    [[ ! -e signals.log ]]

    "$utility" -t 80 --auto-kill --csv --audit-log audit.log
    "$utility" -t 90 --auto-kill --force --csv --audit-log audit.log

    [[ $(< signals.log) == $'-TERM 987654321\n-0 987654321\n-9 987654321' ]]
    grep -Fq '[INFO] Killed PID 987654321 (lab-worker) SIGTERM.' audit.log
    grep -Fq '[INFO] Killed PID 987654321 (lab-worker) SIGKILL.' audit.log
    printf '%s\n' 'Verified mock SIGTERM, SIGKILL, and audit entries.'
)
```

The first CSV row reports `would-kill`, with no signal recorded. The next two runs report `killed`
for the synthetic worker. The final line confirms that both simulated signals reached the recorder
and both were written to the private audit log.
