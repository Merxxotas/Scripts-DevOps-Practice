# Lab 3: Audit Logs, Exit Codes & Scheduling

Verify an audit trail and two exit codes without installing a scheduler or deleting real logs.
Start in the module directory. Run the blocks for your shell in the same session, in order, and
stop if a step fails. The scheduling section is reference only.

## Step 1: Create a sandbox and preview cleanup (exit 0)

Create one log dated about 45 days ago. Keep the audit log outside the scanned directory so it
cannot become a cleanup candidate. Dry-run must leave the test log in place.

### Bash

```bash
lab_dir=$(mktemp -d "${TMPDIR:-/tmp}/log-cleanup-lab3.XXXXXXXX") && (
    set -e
    mkdir "$lab_dir/input"
    printf 'Sample stale log\n' > "$lab_dir/input/old.log"
    if [[ $(uname -s) == Darwin ]]; then
        stamp=$(date -v-45d +%Y%m%d%H%M)
    else
        stamp=$(date -d '45 days ago' +%Y%m%d%H%M)
    fi
    touch -t "$stamp" "$lab_dir/input/old.log"
    rc=0
    ./cleanup_logs.sh -d "$lab_dir/input" -t 30 -n -l "$lab_dir/audit.log" || rc=$?
    printf 'Preview exit: %s\n' "$rc"
    [[ "$rc" -eq 0 && -f "$lab_dir/input/old.log" ]]
)
```

### PowerShell

```powershell
$LabDir = $null
$SandboxPath = Join-Path ([System.IO.Path]::GetTempPath()) ('log-cleanup-lab3.' + [guid]::NewGuid())
$LabDir = (New-Item -ItemType Directory -Path $SandboxPath -ErrorAction Stop).FullName
$InputDir = Join-Path $LabDir 'input'
New-Item -ItemType Directory -Path $InputDir -ErrorAction Stop | Out-Null
$Old = Join-Path $InputDir 'old.log'
Set-Content -LiteralPath $Old -Value 'Sample stale log' -ErrorAction Stop
[System.IO.File]::SetLastWriteTime($Old, (Get-Date).AddDays(-45))
$Audit = Join-Path $LabDir 'audit.log'
.\cleanup_logs.ps1 -LogDirectory $InputDir -Days 30 -DryRun -LogFile $Audit
$Code = $LASTEXITCODE
"Preview exit: $Code"
if ($Code -ne 0 -or -not (Test-Path -LiteralPath $Old -PathType Leaf)) {
    throw 'Preview must succeed and preserve old.log.'
}
```

## Step 2: Verify the audit trail and a rejected input (exit 1)

The audit log should show an ISO 8601 UTC timestamp, a `Would delete` entry for `old.log`, and a
summary for one scanned file, one candidate, and zero failures. `Processed=1` counts the previewed
candidate; it does not mean a deletion occurred. The actual timestamp and file size vary.

Pass a nonexistent directory within the sandbox to demonstrate exit `1` without scanning system
paths. Exit `2` indicates a partial failure; this exercise does not induce one.

### Bash

```bash
(
    set -e
    audit="${lab_dir:?Run lab setup first}/audit.log"
    timestamp='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
    grep -E "$timestamp \\[INFO\\] \\[DRY RUN\\] Would delete: .*/old\\.log " "$audit"
    grep -F 'Cleanup completed: Scanned=1, Eligible=1, Processed=1, Failed=0' "$audit"
    rc=0
    ./cleanup_logs.sh -d "$lab_dir/missing" -t 30 -n || rc=$?
    printf 'Rejected input exit: %s\n' "$rc"
    [[ "$rc" -eq 1 && -f "$lab_dir/input/old.log" && ! -e "$lab_dir/missing" ]]
)
```

### PowerShell

```powershell
$Entries = Get-Content -LiteralPath $Audit -ErrorAction Stop
$Timestamp = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z'
$Preview = $Entries -match "$Timestamp \[INFO\] \[DRY RUN\] Would delete: .*old\.log "
$Summary = $Entries -like '*Cleanup completed: Scanned=1, Eligible=1, Processed=1, Failed=0*'
if (-not $Preview -or -not $Summary) { throw 'The expected audit entries are missing.' }
$Preview
$Summary
$Missing = Join-Path $LabDir 'missing'
.\cleanup_logs.ps1 -LogDirectory $Missing -Days 30 -DryRun
$Code = $LASTEXITCODE
"Rejected input exit: $Code"
if ($Code -ne 1 -or (Test-Path -LiteralPath $Missing) -or
    -not (Test-Path -LiteralPath $Old -PathType Leaf)) {
    throw 'An invalid directory must return exit 1 and leave the sandbox unchanged.'
}
```

## Step 3: Remove the sandbox

### Bash

```bash
rm -- "${lab_dir:?Run lab setup first}/input/old.log" "$lab_dir/audit.log" &&
    rmdir -- "$lab_dir/input" "$lab_dir"
```

### PowerShell

```powershell
Remove-Item -LiteralPath $Old, $Audit -ErrorAction Stop
[System.IO.Directory]::Delete($InputDir)
[System.IO.Directory]::Delete($LabDir)
```

## Production scheduling reference (not part of the walkthrough)

The scheduler should run under a dedicated account with access only to the intended logs and
an audit destination outside that tree. Start with dry-run, inspect the audit output and scheduler
history, and configure an alert on nonzero exits before enabling deletion. A successful exit does
not by itself prove that the audit file was written; verify that separately.

- **Cron:** Use explicit paths. In the dedicated account's crontab, a daily preview at 02:30
  looks like this:

  ```cron
  30 2 * * * /opt/log-cleanup/cleanup_logs.sh -d /srv/myapp/logs -t 14 -r -n -l /srv/myapp/audit/cleanup.log
  ```

- **Windows Task Scheduler:** Use a daily trigger under a dedicated account, not `SYSTEM`. Set
  `powershell.exe` as the program and use an action such as the following (replace all paths and
  follow your execution policy). Verify **Last Run Result** and the audit file after a preview.

  ```text
  -NoProfile -NonInteractive -File "C:\Scripts\cleanup_logs.ps1" -LogDirectory "C:\Logs\App" -Days 14 -Recursive -DryRun -LogFile "C:\Audit\cleanup.log"
  ```
