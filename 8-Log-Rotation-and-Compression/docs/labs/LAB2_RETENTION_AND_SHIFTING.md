# Lab 2 — Retention and Shifting

**Goal:** Confirm backups shift and prune beyond the count.

## Steps (Bash)

```bash
d=$(mktemp -d); f="$d/app.log"
for i in 1 2 3 4; do
  printf "version %s\n" "$i" > "$f"
  /path/to/log_rotate.sh -f "$f" -c 2 --force >/dev/null
done
ls "$d"
```

## Expected
- Only `app.log`, `app.log.1.gz`, `app.log.2.gz` remain.
- `app.log.3.gz` is pruned because `-c 2`.