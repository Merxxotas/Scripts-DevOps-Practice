#!/bin/bash
# Open a child shell with a fresh scratch directory for the walkthrough.
set -euo pipefail
IFS=$'\n\t'

if ! parent=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P) ||
   ! scratch=$(mktemp -d "${parent%/}/disk-monitor-lab.XXXXXXXX"); then
    printf '%s\n' 'Could not create a private lab directory.' >&2
    exit 1
fi

# Only this process owns the cleanup path. The child can change LAB without affecting it.
readonly scratch
trap 'rm -rf -- "$scratch"' EXIT
export LAB="$scratch"
unset BASH_ENV
/bin/bash --noprofile --norc
