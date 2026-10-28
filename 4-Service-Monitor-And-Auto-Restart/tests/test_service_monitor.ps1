# Test Suite: test_service_monitor.ps1
# Description: Automated integration and unit test suite for service_monitor.ps1.
#              Drives the public interface: flags, exit codes and output.
#              Uses a runtime-discovered service for existence-dependent paths
#              so the suite stays portable across Windows and Linux (pwsh).

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MonitorScript = Join-Path (Split-Path -Parent $ScriptDir) "service_monitor.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_service_monitor_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-Monitor {
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $psi.FileName = "powershell"
    }
    $psi.Arguments = "-NoProfile -File `"$MonitorScript`" " + ($ScriptArgs -join " ")
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
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "[PASS] $Label" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] $Label (file missing: $Path)" -ForegroundColor Red
        $script:FailedCount++
    }
}

# Discover a service that exists on this host for existence-dependent tests.
$existingService = $null
$stoppedService = $null
try {
    $existingService = (Get-Service | Where-Object { $_.Name -match '^[a-zA-Z0-9_.-]+$' } | Select-Object -First 1).Name
    $stoppedService = (Get-Service | Where-Object { $_.Name -match '^[a-zA-Z0-9_.-]+$' -and $_.Status -eq 'Stopped' } | Select-Object -First 1).Name
} catch {
    $existingService = $null
    $stoppedService = $null
}

# Test 1: help
Invoke-Monitor -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Contains $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: invalid service name
Invoke-Monitor -ScriptArgs @("-ServiceName", "bad/name")
Assert-Equal 1 $script:LastExitCode "Test 2: invalid service name exits 1"

# Test 3: service not found
Invoke-Monitor -ScriptArgs @("-ServiceName", "NonExistentServiceXYZ123")
Assert-Equal 1 $script:LastExitCode "Test 3: missing service exits 1"

# Test 4: running/existing service path (if available)
if ($existingService) {
    Invoke-Monitor -ScriptArgs @("-ServiceName", $existingService)
    # Either 0 (running) or 2 (down and restart failed) is acceptable here.
    if ($script:LastExitCode -eq 0 -or $script:LastExitCode -eq 2) {
        Write-Host "[PASS] Test 4: existing service exits 0 or 2" -ForegroundColor Green
        $script:PassedCount++
    } else {
        Write-Host "[FAIL] Test 4: existing service unexpected exit $($script:LastExitCode)" -ForegroundColor Red
        $script:FailedCount++
    }
}

# Test 5: dry-run (prefer a stopped service so a restart is planned)
$drSvc = if ($stoppedService) { $stoppedService } else { $existingService }
if ($drSvc) {
    Invoke-Monitor -ScriptArgs @("-ServiceName", $drSvc, "-DryRun")
    Assert-Equal 0 $script:LastExitCode "Test 5a: dry-run exits 0"
    Assert-Contains $script:LastStdout "DRY RUN" "Test 5b: dry-run label"
}

# Test 6: bad max-retries (0) - ValidateRange blocks 0? range starts 1, so 0 invalid -> error exit 1
Invoke-Monitor -ScriptArgs @("-ServiceName", "NonExistentServiceXYZ123", "-MaxRetries", "0")
Assert-Equal 1 $script:LastExitCode "Test 6: zero max-retries exits 1"

# Test 7: bad retry-delay negative
Invoke-Monitor -ScriptArgs @("-ServiceName", "NonExistentServiceXYZ123", "-RetryDelaySeconds", "-1")
Assert-Equal 1 $script:LastExitCode "Test 7: negative retry-delay exits 1"

# Test 8: audit log with existing service (if available)
if ($existingService) {
    $audit = Join-Path $TestSandbox "audit.log"
    Invoke-Monitor -ScriptArgs @("-ServiceName", $existingService, "-AuditLog", $audit, "-DryRun")
    Assert-Equal 0 $script:LastExitCode "Test 8a: audit run exits 0"
    Assert-FileExists $audit "Test 8b: audit file created"
}

# Test 9: verbose
if ($existingService) {
    Invoke-Monitor -ScriptArgs @("-ServiceName", $existingService, "-Verbose", "-DryRun")
    Assert-Equal 0 $script:LastExitCode "Test 9: verbose exits 0"
}

# Test 10: skipped (unknown-option binding is platform-dependent)

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0