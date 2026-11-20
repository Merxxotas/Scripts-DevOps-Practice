# Lab 1: Basic Retention Policy & Dry-Run Preview 🧪

Preview a 30-day retention policy on four disposable logs, then apply it and verify what remains.

Use Bash 4+ on Linux/macOS or PowerShell 5.1+ on Windows. Start in the module directory, where
`cleanup_logs.sh` and `cleanup_logs.ps1` live. Run only the blocks for your shell, in the same
session, and stop if a step fails.

## Step 1: Create the test logs

Each run creates a new temporary directory. The four files have ages of 0, 5, 45 and 60 days, so
two are well outside the 30-day retention window regardless of when you run the lab.

### Linux / macOS (Bash)

```bash
lab_dir=$(mktemp -d "${TMPDIR:-/tmp}/log-cleanup-lab1.XXXXXXXX") && (
    set -e
    for log in app access debug error; do
        printf 'Sample %s log\n' "$log" > "$lab_dir/$log.log"
    done

    for fixture in access:5 debug:45 error:60; do
        log=${fixture%:*}
        days=${fixture#*:}
        if [[ $(uname -s) == Darwin ]]; then
            stamp=$(date -v-"${days}"d +%Y%m%d%H%M)
        else
            stamp=$(date -d "$days days ago" +%Y%m%d%H%M)
        fi
        touch -t "$stamp" "$lab_dir/$log.log"
    done
)
```

### Windows (PowerShell)

```powershell
$LabDir = $null
$SandboxPath = Join-Path ([System.IO.Path]::GetTempPath()) ('log-cleanup-lab1.' + [guid]::NewGuid())
$LabDir = (New-Item -ItemType Directory -Path $SandboxPath -ErrorAction Stop).FullName
$Now = Get-Date
$Ages = @{ 'app' = 0; 'access' = 5; 'debug' = 45; 'error' = 60 }
foreach ($Log in $Ages.Keys) {
    $File = Join-Path $LabDir "$Log.log"
    Set-Content -LiteralPath $File -Value "Sample $Log log" -ErrorAction Stop
    (Get-Item -LiteralPath $File -ErrorAction Stop).LastWriteTime = $Now.AddDays(-$Ages[$Log])
}
```

## Step 2: Preview and check that nothing was deleted

The dry run should scan four files and report two deletion candidates: `debug.log` and
`error.log`. Paths, file order, reported ages and sizes can vary. Both recent and expired logs
must still exist after the command.

### Bash

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 -n && (
    for log in app access debug error; do
        if [[ ! -f "$lab_dir/$log.log" ]]; then
            printf 'Dry run did not preserve %s.log\n' "$log" >&2
            exit 1
        fi
    done
)
```

### PowerShell

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30 -DryRun
if ($LASTEXITCODE -ne 0) { throw "Dry run failed (exit $LASTEXITCODE)." }
foreach ($Log in $Ages.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $LabDir "$Log.log") -PathType Leaf)) {
        throw "Dry run did not preserve $Log.log."
    }
}
```

## Step 3: Apply the policy and verify what remains

Only `app.log` and `access.log` should remain. `debug.log` and `error.log` should be gone.

### Bash

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 && (
    if [[ ! -f "$lab_dir/app.log" || ! -f "$lab_dir/access.log" ||
          -e "$lab_dir/debug.log" || -e "$lab_dir/error.log" ]]; then
        printf 'Live cleanup did not leave exactly the two recent logs.\n' >&2
        exit 1
    fi
)
```

### PowerShell

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30
if ($LASTEXITCODE -ne 0) { throw "Live cleanup failed (exit $LASTEXITCODE)." }
foreach ($Log in 'app', 'access') {
    if (-not (Test-Path -LiteralPath (Join-Path $LabDir "$Log.log") -PathType Leaf)) {
        throw "Live cleanup did not preserve $Log.log."
    }
}
foreach ($Log in 'debug', 'error') {
    if (Test-Path -LiteralPath (Join-Path $LabDir "$Log.log")) {
        throw "Live cleanup did not delete $Log.log."
    }
}
```

## Step 4: Remove the sandbox

Remove the remaining sample logs, then the empty directory. This does not recursively delete files.

### Bash

```bash
rm -- "${lab_dir:?Run lab setup first}/app.log" "$lab_dir/access.log" && rmdir -- "$lab_dir"
```

### PowerShell

```powershell
foreach ($Log in 'app', 'access') {
    Remove-Item -LiteralPath (Join-Path $LabDir "$Log.log") -ErrorAction Stop
}
[System.IO.Directory]::Delete($LabDir)
```
