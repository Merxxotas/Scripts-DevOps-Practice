# Lab 2 — Threshold and Deletion

See which pods the Bash monitor would keep or delete at a restart threshold of 3,
and how it reports a failed deletion. No cluster, credentials or installed `kubectl`
are needed.

Open Bash on Linux or macOS and enter `10-Kubernetes-Pod-Monitor-and-Restart/`.
Copy and run the **whole block**. Do not run the monitor separately for this lab:
it defaults to live mode. The block clears the monitor's inherited environment
and sets its `PATH` to a directory containing only a newly created fake `kubectl`.
If the fake is missing, the monitor stops; it cannot fall back to your normal `PATH`.
A temporary path containing `:` is rejected because `PATH` treats it as a separator.
All lab files are removed when the block exits.

```bash
(
    set -euo pipefail
    IFS=$'\n\t'
    if [[ ! -f ./k8s_monitor.sh ]]; then
        printf '%s\n' 'Run this block from the Kubernetes Pod Monitor module directory.' >&2
        exit 1
    fi

    temp_root=${TMPDIR:-/tmp}
    if [[ "$temp_root" == *:* ]]; then
        printf '%s\n' "Lab 2 needs a temporary directory path without ':'." >&2
        exit 1
    fi
    lab_dir=$(mktemp -d "$temp_root/k8s-lab2.XXXXXX")
    trap 'rm -rf -- "$lab_dir"' EXIT
    mkdir "$lab_dir/bin"
    cat > "$lab_dir/bin/kubectl" <<'FAKE_KUBECTL'
#!/bin/bash
set -euo pipefail
case "${1:-} ${2:-}" in
    'get pods')
        [[ "$*" == 'get pods -n lab-demo -l app=lab -o jsonpath='* ]] || exit 1
        printf '%s\n' 'pod-below|Running|2,' 'pod-equal|Running|3,' 'pod-above|Running|5,'
        ;;
    'delete pod')
        printf '%s\n' "$*" >> "$LAB_DIR/attempts"
        [[ $# == 5 && "$3" == pod-above && "$4" == -n && "$5" == lab-demo ]] || exit 1
        if [[ "$LAB_CASE" == failure ]]; then
            printf '%s\n' 'Simulated API error' >&2
            exit 1
        fi
        ;;
    *) exit 1 ;;
esac
FAKE_KUBECTL
    chmod +x "$lab_dir/bin/kubectl"

    run_case() {
        local scenario=$1 expected_rc=$2 rc=0 attempts
        printf '\n%s\n' "$scenario"
        : > "$lab_dir/attempts"
        /usr/bin/env -i PATH="$lab_dir/bin" LC_ALL=C LAB_DIR="$lab_dir" LAB_CASE="$scenario" \
            /bin/bash ./k8s_monitor.sh -n lab-demo -l app=lab -r 3 \
            2> "$lab_dir/stderr" || rc=$?
        attempts=$(<"$lab_dir/attempts")
        printf 'Monitor exit: %s\nFake delete attempts:\n%s\n' "$rc" "$attempts"
        if [[ -s "$lab_dir/stderr" ]]; then
            cat "$lab_dir/stderr" >&2
        fi
        if [[ "$rc" != "$expected_rc" || -s "$lab_dir/stderr" ||
              "$attempts" != 'delete pod pod-above -n lab-demo' ]]; then
            printf 'Unexpected result: %s\n' "$scenario" >&2
            exit 1
        fi
    }

    run_case success 0
    run_case failure 2
)
```

Check the monitor's result block (colors omitted):

| Run | `pod-below` (2) and `pod-equal` (3) | `pod-above` (5) | Summary | Monitor exit |
| --- | --- | --- | --- | --- |
| `success` | `kept (below threshold)` | `deleted` | `Pods: 3  Deleted: 1  Failed: 0` | `0` |
| `failure` | `kept (below threshold)` | `delete FAILED` | `Pods: 3  Deleted: 0  Failed: 1` | `2` |

Both runs must record exactly `delete pod pod-above -n lab-demo`. The monitor keeps
pods **at or below** the threshold; neither is sent to the fake for deletion. The
monitor suppresses the fake's API error, so stderr is empty in both runs. The whole
block exits `0` when the two cases pass its checks, including the expected monitor
exit `2` in the failure case.
