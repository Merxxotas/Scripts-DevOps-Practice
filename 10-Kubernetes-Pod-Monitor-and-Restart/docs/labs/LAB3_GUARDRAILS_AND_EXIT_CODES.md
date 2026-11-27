# Lab 3 — Guardrails and Exit Codes

Exercise three input errors and dry-run audit logging without contacting a cluster.
Run this block from the module directory. It uses a private workspace and a fake
`kubectl`; it does not read your Kubernetes configuration or change your shell environment.
Requires Bash and standard Unix tools. No cluster or credentials are needed.

```bash
(
    set -eu
    lab_dir=$(mktemp -d "${TMPDIR:-/tmp}/k8s-lab3.XXXXXX")
    trap 'rm -rf -- "$lab_dir"' EXIT
    case "$lab_dir" in
        *:*) printf "Lab 3 needs a temporary directory path without ':'.\n" >&2; exit 1 ;;
    esac
    lab_dir=$(cd -- "$lab_dir" && pwd -P)
    mkdir "$lab_dir/bin"
    ln -s "$(command -v date)" "$lab_dir/bin/date"
    cat > "$lab_dir/bin/kubectl" <<'FAKE'
#!/bin/bash
set -eu
printf '%s\n' "$1" >> "$LAB_CALLS"
if [[ "$1" == get && "$2" == pods ]]; then
    printf 'lab-pod|Running|5,\n'
else
    printf 'Unexpected fake kubectl operation\n' >&2
    exit 1
fi
FAKE
    chmod +x "$lab_dir/bin/kubectl"
    test -x "$lab_dir/bin/kubectl" && test -x "$lab_dir/bin/date" || {
        printf 'Lab 3 fake client or date helper is unavailable.\n' >&2
        exit 1
    }
    : > "$lab_dir/calls"
    monitor="$PWD/k8s_monitor.sh"
    check_invalid() {
        label=$1
        expected=$2
        shift 2
        status=0
        /usr/bin/env -i PATH="$lab_dir/bin" LAB_CALLS="$lab_dir/calls" \
            /bin/bash "$monitor" "$@" > "$lab_dir/out" 2> "$lab_dir/err" || status=$?
        if ! { test "$status" -eq 1 && test ! -s "$lab_dir/out" && \
            test ! -s "$lab_dir/calls" && test ! -e "$lab_dir/audit.log" && \
            grep -Fq "$expected" "$lab_dir/err"; }; then
                printf 'Unexpected validation result: %s\n' "$label" >&2
                exit 1
        fi
        printf '%s: exit 1\n' "$label"
    }
    check_invalid 'empty namespace' 'Invalid namespace:' -n ''
    check_invalid 'negative threshold' 'Invalid restart threshold:' -r -1
    check_invalid 'empty selector' 'Invalid label selector:' -l ''

    status=0
    /usr/bin/env -i PATH="$lab_dir/bin" LAB_CALLS="$lab_dir/calls" \
        /bin/bash "$monitor" --dry-run --audit-log "$lab_dir/audit.log" \
        > "$lab_dir/out" 2> "$lab_dir/err" || status=$?
    if ! { test "$status" -eq 0 && test ! -s "$lab_dir/err" && \
        test "$(cat "$lab_dir/calls")" = get && \
        grep -q 'would delete' "$lab_dir/out" && \
        test "$(wc -l < "$lab_dir/audit.log" | tr -d ' ')" = 1 && \
        grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z namespace=default label=app=web threshold=3 pods=1 deleted=0 outcome=dry-run$' \
            "$lab_dir/audit.log"; }; then
                printf 'Unexpected dry-run or audit result.\n' >&2
                exit 1
    fi
    printf 'audit dry-run: exit 0; pods=1 deleted=0 outcome=dry-run\n'
    printf 'Lab 3 passed.\n'
)
```

Expected output:

```text
empty namespace: exit 1
negative threshold: exit 1
empty selector: exit 1
audit dry-run: exit 0; pods=1 deleted=0 outcome=dry-run
Lab 3 passed.
```

The three invalid configurations exit before invoking even the fake client. The
valid example queries one fake pod above the threshold, previews deletion, and
checks one ISO-8601 audit line with zero deletions. Cleanup removes only this run's
workspace, including its audit file. A missing helper fails the exercise rather
than falling back to a real client.
