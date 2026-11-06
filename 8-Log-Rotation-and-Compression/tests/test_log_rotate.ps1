#Requires -Version 5.1
<#
.SYNOPSIS
    Automated integration and unit test suite for log_rotate.ps1

.DESCRIPTION
    Every test drives the public interface of the tool: the flags, the exit
    codes and the emitted files. All filesystem activity happens under a temp dir.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$RotateScript = Join-Path (Split-Path -Parent $ScriptDir) "log_rotate.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_ps1_log_rotate_" + [System.Guid]::NewGuid().ToString("N"))
$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Enter-Sandbox {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null
}

function Invoke-Rotate {
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    # fall back to powershell if pwsh missing
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $psi.FileName = "powershell"
    }
    $psi.Arguments = "-NoProfile -File `"$RotateScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $script:LastStdout = $proc.StandardOutput.ReadToEnd()
    $script:LastStderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $script:LastExitCode = $proc.ExitCode
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Match {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Path {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (missing $Path)" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Absent {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (exists $Path)" -ForegroundColor Red
        $script:FailedCount++
    }
}

# ---------- tests ----------

Enter-Sandbox

# Test 1: help
Invoke-Rotate -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Match $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: missing file
$f = Join-Path $TestSandbox "nope.log"
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"")
Assert-Equal 1 $script:LastExitCode "Test 2: missing file exits 1"

# Test 3: no-op
$f = Join-Path $TestSandbox "small.log"
"small" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "10")
Assert-Equal 0 $script:LastExitCode "Test 3a: no-op exits 0"
Assert-Match $script:LastStdout "No rotation needed" "Test 3b: no-op message"

# Test 4: rotation basic
$f = Join-Path $TestSandbox "f.log"
("line`n" * 100) | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "0")
Assert-Equal 0 $script:LastExitCode "Test 4a: rotation exits 0"
Assert-Path "$f.1.zip" "Test 4b: backup created"

# Test 5: dry-run
$f = Join-Path $TestSandbox "g.log"
("line`n" * 100) | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "0", "-DryRun")
Assert-Equal 0 $script:LastExitCode "Test 5a: dry-run exits 0"
Assert-Match $script:LastStdout "DRY RUN" "Test 5b: dry-run label"
Assert-Absent "$f.1.zip" "Test 5c: no backup created"

# Test 6: force
$f = Join-Path $TestSandbox "h.log"
"tiny" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-Force")
Assert-Equal 0 $script:LastExitCode "Test 6a: force exits 0"
Assert-Path "$f.1.zip" "Test 6b: backup created"

# Test 7: no-compress
$f = Join-Path $TestSandbox "i.log"
("line`n" * 100) | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "0", "-NoCompress")
Assert-Equal 0 $script:LastExitCode "Test 7a: no-compress exits 0"
Assert-Path "$f.1" "Test 7b: raw backup created"

# Test 8: bad max-size (negative via invalid? ValidateRange 0.. prevents negative)
$f = Join-Path $TestSandbox "j.log"
"line" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "-5")
Assert-Equal 1 $script:LastExitCode "Test 8: negative max-size exits 1"

# Test 9: bad backup-count 0
$f = Join-Path $TestSandbox "k.log"
"line" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-BackupCount", "0")
Assert-Equal 1 $script:LastExitCode "Test 9: zero backup-count exits 1"

# Test 10: audit log
$f = Join-Path $TestSandbox "l.log"
"line" | Set-Content -LiteralPath $f -NoNewline
$audit = Join-Path $TestSandbox "audit.log"
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-Force", "-AuditLog", "`"$audit`"")
Assert-Equal 0 $script:LastExitCode "Test 10a: audit run exits 0"
Assert-Path $audit "Test 10b: audit file created"

# Test 11: -Json dry-run outputs JSON
$f = Join-Path $TestSandbox "j.log"
"line" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-Force", "-DryRun", "-Json")
Assert-Equal 0 $script:LastExitCode "Test 11a: -Json dry-run exits 0"
Assert-Match $script:LastStdout '"outcome": "dry-run"' "Test 11b: json dry-run outcome"

# Test 12: -Csv dry-run outputs header + row
$f = Join-Path $TestSandbox "c.log"
"line" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-Force", "-DryRun", "-Csv")
Assert-Equal 0 $script:LastExitCode "Test 12a: -Csv dry-run exits 0"
Assert-Match $script:LastStdout "log_file,current_size_bytes" "Test 12b: csv header"

# Test 13: -Json and -Csv mutually exclusive
$f = Join-Path $TestSandbox "m.log"
"line" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-Force", "-Json", "-Csv")
Assert-Equal 1 $script:LastExitCode "Test 13: mutual exclusion exits 1"

# Test 14: a file under a protected full-tree root must be refused
# (host-dependent candidates; SKIP when none exists)
$IsWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
$ProtectedProbe = $null
$ProtectedCandidates = if ($IsWin) {
    @("C:\Windows\System32\drivers\etc\hosts")
} else {
    @("/usr/share/zoneinfo/UTC", "/etc/hostname", "/etc/ssh/sshd_config", "/etc/nginx/nginx.conf")
}
foreach ($c in $ProtectedCandidates) {
    if (Test-Path -LiteralPath $c -PathType Leaf) { $ProtectedProbe = $c; break }
}
if ($null -eq $ProtectedProbe) {
    Write-Host "[SKIP] Test 14: no protected full-tree file found on this host" -ForegroundColor Yellow
} else {
    Invoke-Rotate -ScriptArgs @("-LogFile", "`"$ProtectedProbe`"", "-Force", "-DryRun")
    Assert-Equal 1 $script:LastExitCode "Test 14: file under protected full-tree root exits 1"
}

# Test 15: a file in a subtree of an exact-only root stays allowed
$subdir = Join-Path $TestSandbox "var-log-like"
New-Item -ItemType Directory -Path (Join-Path $subdir "app") -Force | Out-Null
$f = Join-Path (Join-Path $subdir "app") "f.log"
"small" | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"")
Assert-Equal 0 $script:LastExitCode "Test 15: subtree of exact-only root is allowed"

# Test 16: guard blocks via the resolved path when the input path is a symlink (POSIX only)
if ($IsWin) {
    Write-Host "[SKIP] Test 16: symlink guard test is POSIX-only" -ForegroundColor Yellow
} elseif (-not (Test-Path /etc/passwd -PathType Leaf)) {
    Write-Host "[SKIP] Test 16: /etc/passwd does not exist on this host" -ForegroundColor Yellow
} else {
    $link = Join-Path $TestSandbox "link"
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target "/etc" -ErrorAction Stop | Out-Null
        Invoke-Rotate -ScriptArgs @("-LogFile", "`"$link/passwd`"", "-Force", "-DryRun")
        Assert-Equal 1 $script:LastExitCode "Test 16: symlink into protected tree exits 1"
    } catch {
        Write-Host "[SKIP] Test 16: symlink creation refused on this host" -ForegroundColor Yellow
    }
}

# Test 17: the zip backup decompresses to the original bytes
$f = Join-Path $TestSandbox "zipcheck.log"
$original = Join-Path $TestSandbox "zipcheck.original"
("roundtrip-content`n" * 80) | Set-Content -LiteralPath $f -NoNewline
Copy-Item -LiteralPath $f -Destination $original -Force
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "0")
Assert-Equal 0 $script:LastExitCode "Test 17a: rotation exits 0"
$verifyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("log_rotate_ps_test_" + [System.Guid]::NewGuid().ToString("N"))
try {
    Expand-Archive -LiteralPath "$f.1.zip" -DestinationPath $verifyDir -Force -ErrorAction Stop
    $extracted = (Get-ChildItem -LiteralPath $verifyDir -File | Select-Object -First 1).FullName
    $hashOriginal = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    $hashZip = (Get-FileHash -LiteralPath $extracted -Algorithm SHA256).Hash
    Assert-Equal $hashOriginal $hashZip "Test 17b: zip backup matches the original"
} finally {
    Remove-Item -LiteralPath $verifyDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 18: the original is truncated to zero bytes after rotation
$f = Join-Path $TestSandbox "trunccheck.log"
("line`n" * 100) | Set-Content -LiteralPath $f -NoNewline
Invoke-Rotate -ScriptArgs @("-LogFile", "`"$f`"", "-MaxSizeMB", "0")
Assert-Equal 0 $script:LastExitCode "Test 18a: rotation exits 0"
$sz = (Get-Item -LiteralPath $f).Length
Assert-Equal 0 $sz "Test 18b: original truncated to 0"

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

if ($script:FailedCount -gt 0) { exit 1 }
exit 0