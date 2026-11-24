# Lab 1: Backup & Dry Run

Create a compressed MySQL backup and an uncompressed PostgreSQL backup using fake clients.
Then verify that a dry run previews the work without changing any backup fixtures.
No database, database client, or credentials are needed.

From `3-Automated-Database-Backup-with-Timestamp/`, paste the **whole block** into Bash on Linux
or macOS. It runs in a child shell and uses a private temporary directory under `${TMPDIR:-/tmp}`.
The child removes only that directory on exit. Your shell and existing backups stay unchanged.

```bash
BASH_ENV=/dev/null bash <<'LAB'
set -euo pipefail
IFS=$'\n\t'
shopt -u failglob
shopt -s nullglob dotglob

fail() { printf 'Lab 1: %s\n' "$*" >&2; exit 1; }
backup="$PWD/db_backup.sh"
[[ -f "$backup" ]] || fail 'Run from the Database Backup module directory.'

umask 077
scratch=$(mktemp -d "${TMPDIR:-/tmp}/db-backup-lab1.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ "$scratch" == /* ]] || scratch="$PWD/$scratch"
cd -- "$scratch"

mkdir bin
cat > bin/mysqldump <<'MYSQL'
#!/bin/sh
set -eu
printf 'mysql\n' >> dump-calls
[ "${LAB_DRY_RUN:-0}" = 0 ] || exit 99
printf '%s\n' '-- MySQL dump stub' 'CREATE TABLE t (id int);'
MYSQL
cat > bin/pg_dump <<'POSTGRES'
#!/bin/sh
set -eu
out=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -f) out=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ "${out%/*}" = postgres ] || exit 99
printf 'postgresql\n' >> dump-calls
printf '%s\n' '-- PostgreSQL dump stub' > "$out"
POSTGRES
chmod 700 bin/mysqldump bin/pg_dump
export PATH="$PWD/bin:$PATH"
for client in mysqldump pg_dump; do
    [[ $(command -v "$client") == "$PWD/bin/$client" ]] || fail "Fake $client did not resolve."
done
export DB_BACKUP_PASSWORD=lab-placeholder-not-a-credential
unset LAB_DRY_RUN

run_backup() {
    local status=0
    bash "$backup" -n labdb -u backup_user "$@" >stdout 2>stderr || status=$?
    if [[ "$status" != 0 || -s stderr ]]; then
        cat stdout stderr >&2
        fail "Expected exit 0 and empty stderr; got exit $status."
    fi
}

# 1. MySQL: the utility reads the fake client's stdout and compresses it.
run_backup -t mysql -d mysql -r 7
files=(mysql/*)
[[ ${#files[@]} == 1 && ${files[0]} == mysql/mysql_labdb_*.sql.gz ]] ||
    fail 'Expected one MySQL archive.'
gzip -cd -- "${files[0]}" > mysql-dump
printf '%s\n' '-- MySQL dump stub' 'CREATE TABLE t (id int);' | cmp -s - mysql-dump ||
    fail 'Unexpected MySQL dump contents.'
grep -Fq 'Backup complete. Pruned 0 old backup(s).' stdout || fail 'Missing MySQL summary.'
printf '%s\n' 'MySQL: exit=0 (compressed fake dump)'

# 2. Dry run: age both fixtures so a real run would prune them.
printf '%s\n' '-- Old disposable backup' > mysql/old.sql
touch -t 200001010000 mysql/*
mkdir before
cp -p mysql/* before/
LAB_DRY_RUN=1 run_backup -t mysql -d mysql --dry-run
for action in 'create backup directory' 'invoke: mysqldump' 'compress:' 'prune backups'; do
    grep -Fq "[DRY RUN] Would $action" stdout || fail "Missing dry-run preview: $action"
done
[[ $(<dump-calls) == mysql ]] || fail 'Dry run invoked a client.'
files=(mysql/*)
[[ ${#files[@]} == 2 ]] || fail 'Dry run changed the file list.'
for original in before/*; do
    current="mysql/${original##*/}"
    cmp -s "$original" "$current" || fail "Dry run changed $current."
    [[ ! "$original" -nt "$current" && ! "$current" -nt "$original" ]] ||
        fail "Dry run changed the timestamp of $current."
done
printf '%s\n' 'Dry run: exit=0 (no dump; backup fixtures unchanged)'

# 3. PostgreSQL: the fake client writes to the path supplied by -f.
run_backup -t postgresql -d postgres --no-compress
files=(postgres/*)
[[ ${#files[@]} == 1 && ${files[0]} == postgres/postgresql_labdb_*.sql ]] ||
    fail 'Expected one uncompressed PostgreSQL dump.'
printf '%s\n' '-- PostgreSQL dump stub' | cmp -s - "${files[0]}" ||
    fail 'Unexpected PostgreSQL dump contents.'
[[ $(<dump-calls) == $'mysql\npostgresql' ]] || fail 'Unexpected client calls.'
grep -Fq 'Backup complete. Pruned 0 old backup(s).' stdout || fail 'Missing PostgreSQL summary.'
printf '%s\n' 'PostgreSQL: exit=0 (uncompressed fake dump)' 'Lab 1 checks passed.'
LAB
```

## What the checks show

| Check | Expected result |
| :--- | :--- |
| MySQL | Exit `0`; one `mysql_labdb_<timestamp>.sql.gz` containing the fake dump. |
| Dry run | Exit `0`; `[DRY RUN]` previews the work without calling the fake client. |
| PostgreSQL | Exit `0`; one `postgresql_labdb_<timestamp>.sql` left uncompressed. |

The dry-run example does not pass `-l`. If you provide an audit log, dry run can write a preview
record to it. Use [Lab 2](LAB2_EXIT_CODES_AND_RETENTION.md) to check failure exit codes and pruning.

## Related documents

- [Lab 3 — Scheduling in Production](LAB3_PRODUCTION_SCHEDULING.md)
- [Scenarios](../SCENARIOS.md)
