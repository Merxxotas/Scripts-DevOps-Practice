# Lab 2: Exit Codes & Retention

Run the Bash backup utility against disposable files to see exit codes `0`, `1`, and `2`,
retention pruning, and audit records. You do not need a database, database client, or credentials.

From the module directory, paste the **whole block** into Bash. It runs in a child shell with a
private temporary directory under `${TMPDIR:-/tmp}`. The fake `mysqldump`, backups, and audit log are
removed when that shell exits. Your shell environment and existing backups are not changed.

```bash
BASH_ENV=/dev/null bash <<'LAB'
set -euo pipefail
IFS=$'\n\t'

fail() { printf 'Lab 2: %s\n' "$*" >&2; exit 1; }
backup="$PWD/db_backup.sh"
[[ -f "$backup" ]] || fail 'Run from the Database Backup module directory.'

umask 077
scratch=$(mktemp -d "${TMPDIR:-/tmp}/db-backup-lab2.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Resolve a relative TMPDIR before changing directory.
[[ "$scratch" == /* ]] || scratch="$PWD/$scratch"
cd -- "$scratch"

mkdir bin
cat > bin/mysqldump <<'FAKE'
#!/bin/sh
set -eu
printf 'called\n' >> dump-calls
printf '%s\n' '-- MySQL dump stub'
exit "${LAB_DUMP_STATUS:-0}"
FAKE
chmod 700 bin/mysqldump
export PATH="$PWD/bin:$PATH"
[[ $(command -v mysqldump) == "$PWD/bin/mysqldump" ]] || fail 'Fake client did not resolve.'
unset DB_BACKUP_PASSWORD LAB_DUMP_STATUS
password=lab-placeholder-not-a-credential

run_case() {
    local expected=$1 status=0
    shift
    bash "$backup" -t mysql -n labdb "$@" >stdout 2>stderr || status=$?
    if [[ "$status" != "$expected" ]]; then
        cat stdout stderr >&2
        fail "Expected exit $expected, got $status."
    fi
}

reject() {
    local label=$1 diagnostic=$2
    shift 2
    # Dry run prevents writes even if the safety/configuration check regresses.
    run_case 1 --dry-run "$@"
    [[ ! -s stdout ]] || fail "Unexpected stdout for $label."
    grep -Fq -- "Error: $diagnostic" stderr || fail "Missing error for $label."
    printf '%s: exit=1\n' "$label"
}

shopt -s nullglob dotglob
run_case 0 -d success --db-password "$password"
archives=(success/*)
[[ ${#archives[@]} == 1 && ${archives[0]} == *.sql.gz ]] || fail 'Expected one archive.'
[[ $(gzip -cd -- "${archives[0]}") == '-- MySQL dump stub' ]] || fail 'Unexpected dump data.'
[[ ! -s stderr ]] || fail 'Unexpected stderr on success.'
grep -Fq 'Backup complete. Pruned 0 old backup(s).' stdout || fail 'Missing success summary.'
printf '%s\n' 'Success: exit=0 (compressed fake dump)'

reject 'Missing password' \
    'Database password is required. Pass --db-password or set DB_BACKUP_PASSWORD.' -d rejected
reject 'System path' "Refusing to use a system path as the backup directory: '/etc'." \
    -d /etc --db-password "$password"
reject 'Bad retention' 'Retention days must be an integer between 0 and 3650.' \
    -d rejected -r abc --db-password "$password"
[[ ! -e rejected && $(cat dump-calls) == called ]] || fail 'A rejected case had side effects.'

LAB_DUMP_STATUS=3 run_case 2 -d failed --db-password "$password" -l audit.log
partial=(failed/*)
[[ -d failed && ${#partial[@]} == 0 ]] || fail 'Partial dump was not removed.'
grep -Fq 'Error: Database dump failed (exit 3).' stderr || fail 'Missing dump error.'
grep -Eq '^[0-9TZ:-]+ \[ERROR\] Dump failed for mysql/labdb \(exit 3\)\.$' audit.log \
    || fail 'Missing failure audit record.'
printf '%s\n' 'Failed dump: exit=2 (partial file removed; failure audited)'

mkdir retention
old=(retention/old-1.sql retention/old-2.sql.gz retention/old-3.sql.gz)
printf 'keep recent\n' > retention/recent.sql.gz
printf 'keep unrelated\n' > retention/notes.txt
for file in "${old[@]}"; do printf 'old archive\n' > "$file"; done
touch -t 200001010000 "${old[@]}" retention/notes.txt
run_case 0 -d retention -r 7 --db-password "$password" -l audit.log
[[ ! -s stderr ]] || fail 'Unexpected stderr during retention.'
grep -Fq 'Backup complete. Pruned 3 old backup(s).' stdout || fail 'Wrong prune count.'
for file in "${old[@]}"; do
    [[ ! -e "$file" ]] || fail "Old archive survived: $file"
    grep -Fq "[INFO] Pruned old backup: $file" audit.log || fail "Missing prune record: $file"
done
entries=(retention/*)
archives=(retention/mysql_labdb_*.sql.gz)
[[ ${#entries[@]} == 3 && ${#archives[@]} == 1 ]] || fail 'Unexpected retention survivors.'
[[ $(gzip -cd -- "${archives[0]}") == '-- MySQL dump stub' ]] || fail 'New dump is missing.'
[[ $(<retention/recent.sql.gz) == 'keep recent' && $(<retention/notes.txt) == 'keep unrelated' ]] ||
    fail 'A kept fixture changed.'
grep -Fq '[INFO] Backup complete for mysql/labdb. Pruned 3 old backup(s).' audit.log \
    || fail 'Missing completion audit record.'
if grep -Fq -- "$password" audit.log; then fail 'Password appeared in the audit log.'; fi
printf '%s\n' 'Retention: exit=0 (pruned 3; kept recent and unrelated files)'
printf '%s\n' 'Lab 2 checks passed.'
LAB
```

## What the checks show

| Check | Expected result |
| :--- | :--- |
| Success | Exit `0`; one `.sql.gz` containing the fake dump. |
| Missing password, system path, bad retention | Exit `1`; no dump or backup writes. |
| Fake client exits `3` after emitting data | Utility exits `2`, removes the partial dump, and logs the failure. |
| Seven-day retention | Exit `0`; three old matching files are deleted and logged. The new archive, a recent matching file, and an old unrelated file remain. |
| Audit log | Contains failure, prune, and completion records, but not the fake password. |

Bash retention uses `find -mtime +N`, which counts whole 24-hour periods. A retention value of
`0` does **not** mean “delete all archives.” The lab uses clearly old fixtures and a fresh file to
avoid depending on the exact seven-day boundary.

## Related documents

- [Lab 1 — Backup & Dry Run](LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 3 — Scheduling in Production](LAB3_PRODUCTION_SCHEDULING.md)
- [Scenarios](../SCENARIOS.md)
