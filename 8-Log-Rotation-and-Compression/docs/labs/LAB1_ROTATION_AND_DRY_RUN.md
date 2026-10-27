# Lab 1 — Rotation and Dry-Run

**Goal:** Observe a rotation and verify dry-run changes nothing.

## Steps (Bash)

1. Create a temp log file larger than the threshold:

   ```bash
   d=$(mktemp -d); f="$d/app.log"
   yes line | head -n 1000 > "$f"
   ```

2. Dry-run:

   ```bash
   ./log_rotate.sh -f "$f" -m 0 --dry-run
   ls "$d"   # only app.log present
   ```

3. Real run:

   ```bash
   ./log_rotate.sh -f "$f" -m 0
   ls "$d"   # app.log (now empty) + app.log.1.gz
   ```

## Expected
- Exit code 0 in both cases.
- Dry-run creates no backup; real run creates `app.log.1.gz` and truncates `app.log`.