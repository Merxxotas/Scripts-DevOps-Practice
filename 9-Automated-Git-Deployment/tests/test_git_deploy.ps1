# Test Suite: test_git_deploy.ps1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployScript = Join-Path (Split-Path -Parent $ScriptDir) "git_deploy.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_git_deploy_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestSandbox -Force | Out-Null
$AppDir = Join-Path $TestSandbox "appdir"
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

function Invoke-Deploy {
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $psi.FileName = "powershell" }
    $psi.Arguments = "-NoProfile -File `"$DeployScript`" " + ($ScriptArgs -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $script:LastStdout = $proc.StandardOutput.ReadToEnd()
    $script:LastStderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $script:LastExitCode = $proc.ExitCode
    if ($script:LastStderr) { Write-Host "STDERR: $($script:LastStderr)" -ForegroundColor DarkYellow }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -eq $Actual) { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (expected '$Expected', got '$Actual')" -ForegroundColor Red; $script:FailedCount++ }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Label)
    if ($Haystack -like "*$Needle*") { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (missing '$Needle')" -ForegroundColor Red; $script:FailedCount++ }
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:PassedCount++ }
    else { Write-Host "[FAIL] $Label (file missing: $Path)" -ForegroundColor Red; $script:FailedCount++ }
}

# Test 1: help
Invoke-Deploy -ScriptArgs @("-Help")
Assert-Equal 0 $script:LastExitCode "Test 1a: -Help exits 0"
Assert-Contains $script:LastStdout "Usage" "Test 1b: help shows usage"

# Test 2: missing app dir
Invoke-Deploy -ScriptArgs @("-AppDir", (Join-Path $TestSandbox "nope"))
Assert-Equal 1 $script:LastExitCode "Test 2: missing app dir exits 1"

# Test 3: protected app dir
Invoke-Deploy -ScriptArgs @("-AppDir", "C:\")
Assert-Equal 1 $script:LastExitCode "Test 3: protected app dir exits 1"

# Test 4: invalid branch
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-Branch", "bad@branch")
Assert-Equal 1 $script:LastExitCode "Test 4: invalid branch exits 1"

# Test 5: dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun")
Assert-Equal 0 $script:LastExitCode "Test 5a: dry-run exits 0"
Assert-Contains $script:LastStdout "DRY RUN" "Test 5b: dry-run label"

# Test 6: audit log with dry-run
$audit = Join-Path $TestSandbox "audit.log"
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-AuditLog", $audit)
Assert-Equal 0 $script:LastExitCode "Test 6a: audit dry-run exits 0"
Assert-FileExists $audit "Test 6b: audit file created"

# Test 7: verbose dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-Verbose")
Assert-Equal 0 $script:LastExitCode "Test 7: verbose dry-run exits 0"

# Test 8: skip-backup dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-SkipBackup")
Assert-Equal 0 $script:LastExitCode "Test 8: skip-backup dry-run exits 0"

# Test 9: skip-post-deploy dry-run
Invoke-Deploy -ScriptArgs @("-AppDir", $AppDir, "-DryRun", "-SkipPostDeploy")
Assert-Equal 0 $script:LastExitCode "Test 9: skip-post-deploy dry-run exits 0"

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "Tests Passed: $script:PassedCount" -ForegroundColor Green
Write-Host "Tests Failed: $script:FailedCount" -ForegroundColor Red
Write-Host "========================================"

Remove-Item -Recurse -Force $TestSandbox -ErrorAction SilentlyContinue

if ($script:FailedCount -gt 0) { exit 1 }
exit 0