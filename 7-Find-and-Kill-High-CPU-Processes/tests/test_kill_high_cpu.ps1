# Test Suite: test_kill_high_cpu.ps1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KillerScript = Join-Path (Split-Path -Parent $ScriptDir) "kill_high_cpu.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_kill_high_cpu_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-Killer {
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $psi.FileName = "powershell"
    }
    $psi.Arguments = "-NoProfile -File `"$KillerScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $script:LastStdout = $proc.StandardOutput.ReadToEnd()
    $script:LastStderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $script:LastExitCode = $proc.ExitCode
    if ($script:LastStderr) {
        Write-Host "STDERR: $($script:LastStderr)" -ForegroundColor DarkYellow
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red; $script:FailedCount++
    }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red; $script:FailedCount++
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (file missing: $Path)" -ForegroundColor Red; $script:FailedCount++
    }
}

# Test 1: help
Invoke-Killer -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Contains $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: invalid threshold (negative)
Invoke-Killer -ScriptArgs @("-CpuThreshold", "-5")
Assert-Equal 1 $script:LastExitCode "Test 2: negative threshold exits 1"

# Test 3: non-numeric threshold
Invoke-Killer -ScriptArgs @("-CpuThreshold", "abc")
Assert-Equal 1 $script:LastExitCode "Test 3: non-numeric threshold exits 1"

# Test 4: dry-run (no kills) exits 0
Invoke-Killer -ScriptArgs @("-DryRun")
Assert-Equal 0 $script:LastExitCode "Test 4a: dry-run exits 0"
Assert-Contains $script:LastStdout "DRY RUN" "Test 4b: dry-run label"

# Test 5: audit log with dry-run
$audit = Join-Path $TestSandbox "audit.log"
Invoke-Killer -ScriptArgs @("-DryRun", "-AuditLog", $audit)
Assert-Equal 0 $script:LastExitCode "Test 5a: audit dry-run exits 0"
Assert-FileExists $audit "Test 5b: audit file created"

# Test 6: verbose dry-run
Invoke-Killer -ScriptArgs @("-DryRun", "-Verbose")
Assert-Equal 0 $script:LastExitCode "Test 6: verbose dry-run exits 0"

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0