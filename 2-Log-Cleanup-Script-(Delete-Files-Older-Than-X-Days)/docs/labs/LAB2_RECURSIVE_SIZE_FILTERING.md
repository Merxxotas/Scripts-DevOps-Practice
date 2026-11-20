# Lab 2: Recursive Traversal & Size Threshold Filtering 📁

Compare three dry runs before applying a policy that deletes only old, large logs.
Start in the module directory after [Lab 1](LAB1_BASIC_RETENTION_AND_DRYRUN.md). Run only the
blocks for your shell, in the same session, and stop if a step fails.

## Step 1: Create an isolated directory tree

| File | Age | Size |
| --- | ---: | ---: |
| `root_old.log` | 45 days | 5 MiB |
| `auth/small_old.log` | 45 days | 100 KiB |
| `billing/large_old.log` | 45 days | 15 MiB |
| `worker/large_old.log` | 45 days | 25 MiB |
| `auth/active.log` | Recent | 5 bytes |
| `billing/active.log` | Recent | 12 MiB |

The recent 12 MiB log meets the size rule but not the age rule. The CLI calls its size unit MB;
its minimum of 10 MB is 10 × 1,048,576 bytes.

### Bash

```bash
lab_dir=$(mktemp -d "${TMPDIR:-/tmp}/log-cleanup-lab2.XXXXXXXX") && (
    set -e
    mkdir "$lab_dir"/{auth,billing,worker}
    dd if=/dev/zero of="$lab_dir/root_old.log" bs=1048576 count=5
    dd if=/dev/zero of="$lab_dir/auth/small_old.log" bs=1024 count=100
    dd if=/dev/zero of="$lab_dir/billing/large_old.log" bs=1048576 count=15
    dd if=/dev/zero of="$lab_dir/worker/large_old.log" bs=1048576 count=25
    dd if=/dev/zero of="$lab_dir/billing/active.log" bs=1048576 count=12
    printf 'live\n' > "$lab_dir/auth/active.log"

    if [[ $(uname -s) == Darwin ]]; then
        stamp=$(date -v-45d +%Y%m%d%H%M)
    else
        stamp=$(date -d '45 days ago' +%Y%m%d%H%M)
    fi
    touch -t "$stamp" "$lab_dir/root_old.log" "$lab_dir/auth/small_old.log" \
        "$lab_dir/billing/large_old.log" "$lab_dir/worker/large_old.log"
)
```

### PowerShell

```powershell
$LabDir = $null
$SandboxPath = Join-Path ([System.IO.Path]::GetTempPath()) ('log-cleanup-lab2.' + [guid]::NewGuid())
$LabDir = (New-Item -ItemType Directory -Path $SandboxPath -ErrorAction Stop).FullName
foreach ($Service in 'auth', 'billing', 'worker') {
    New-Item -ItemType Directory -Path (Join-Path $LabDir $Service) -ErrorAction Stop | Out-Null
}
$Stale = (Get-Date).AddDays(-45)
$Sizes = @{
    'root_old.log' = 5MB
    'auth/small_old.log' = 100KB
    'billing/large_old.log' = 15MB
    'worker/large_old.log' = 25MB
    'auth/active.log' = 5
    'billing/active.log' = 12MB
}
foreach ($Log in $Sizes.Keys) {
    $Path = Join-Path $LabDir $Log
    $File = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try { $File.SetLength($Sizes[$Log]) } finally { $File.Dispose() }
    if ($Log -like '*_old.log') { [System.IO.File]::SetLastWriteTime($Path, $Stale) }
}
```

## Step 2: Compare flat and recursive scans

Without recursion, the only candidate is `root_old.log`.

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 -n
```

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30 -DryRun
if ($LASTEXITCODE -ne 0) { throw "Flat dry run failed (exit $LASTEXITCODE)." }
```

With recursion, all four `_old.log` files are candidates. Neither active log is a candidate.

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 -r -n
```

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30 -Recursive -DryRun
if ($LASTEXITCODE -ne 0) { throw "Recursive dry run failed (exit $LASTEXITCODE)." }
```

## Step 3: Preview the combined policy

The only two candidates should be `billing/large_old.log` and `worker/large_old.log`, a total of
40 MiB. All six files should still be present after the dry runs.

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 -r -m 10 -n && (
    for log in root_old.log auth/small_old.log billing/large_old.log worker/large_old.log \
        auth/active.log billing/active.log; do
        [[ -f "$lab_dir/$log" ]] || { printf 'Missing after dry run: %s\n' "$log" >&2; exit 1; }
    done
)
```

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30 -Recursive -MinSizeMB 10 -DryRun
if ($LASTEXITCODE -ne 0) { throw "Filtered dry run failed (exit $LASTEXITCODE)." }
foreach ($Log in $Sizes.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $LabDir $Log) -PathType Leaf)) {
        throw "Missing after dry run: $Log"
    }
}
```

## Step 4: Apply the combined policy

Only the two large stale logs should disappear. The stale logs below the minimum and both recent
logs should remain.

```bash
./cleanup_logs.sh -d "$lab_dir" -t 30 -r -m 10 && (
    for log in billing/large_old.log worker/large_old.log; do
        [[ ! -e "$lab_dir/$log" ]] || { printf 'Still present: %s\n' "$log" >&2; exit 1; }
    done
    for log in root_old.log auth/small_old.log auth/active.log billing/active.log; do
        [[ -f "$lab_dir/$log" ]] || { printf 'Unexpected deletion: %s\n' "$log" >&2; exit 1; }
    done
)
```

```powershell
.\cleanup_logs.ps1 -LogDirectory $LabDir -Days 30 -Recursive -MinSizeMB 10
if ($LASTEXITCODE -ne 0) { throw "Live cleanup failed (exit $LASTEXITCODE)." }
$Expired = 'billing/large_old.log', 'worker/large_old.log'
foreach ($Log in $Sizes.Keys) {
    $Present = Test-Path -LiteralPath (Join-Path $LabDir $Log) -PathType Leaf
    if ($Present -ne ($Log -notin $Expired)) { throw "Unexpected file state: $Log" }
}
```

## Step 5: Remove the sandbox

Remove only the four remaining sample files and their now-empty directories.

```bash
rm -- "${lab_dir:?Run lab setup first}/root_old.log" "$lab_dir/auth/small_old.log" \
    "$lab_dir/auth/active.log" "$lab_dir/billing/active.log" &&
    rmdir -- "$lab_dir"/{auth,billing,worker} "$lab_dir"
```

```powershell
foreach ($Log in $Sizes.Keys) {
    if ($Log -notin $Expired) {
        Remove-Item -LiteralPath (Join-Path $LabDir $Log) -ErrorAction Stop
    }
}
foreach ($Service in 'auth', 'billing', 'worker') {
    [System.IO.Directory]::Delete((Join-Path $LabDir $Service))
}
[System.IO.Directory]::Delete($LabDir)
```
