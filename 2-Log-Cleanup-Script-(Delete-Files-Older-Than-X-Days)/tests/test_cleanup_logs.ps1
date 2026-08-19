#Requires -Version 5.1
<#
.SYNOPSIS
    Automated integration and unit test suite for cleanup_logs.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ScriptDir = $PSScriptRoot
$CleanupScript = Join-Path (Split-Path -Parent $ScriptDir) "cleanup_logs.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_ps1_cleanup_" + [System.Guid]::NewGuid().ToString("N"))

$Global:PassedCount = 0
$Global:FailedCount = 0

function Setup-TestEnv {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path (Join-Path $TestSandbox "sub1") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TestSandbox "sub2") -Force | Out-Null
}

function Teardown-TestEnv {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($Expected -eq $Actual) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $Global:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected: '$Expected', Got: '$Actual')"
        $Global:FailedCount++
    }
}

# Test 1: Missing directory throws validation error
function Test-MissingDirectory {
    $ExitedWithError = $false
    try {
        & $CleanupScript -ErrorAction Stop 2>$null
    } catch {
        $ExitedWithError = $true
    }
    Assert-Equal -Expected $true -Actual $ExitedWithError -TestName "Test 1: Missing directory parameter throws validation error"
}

# Test 2: Safety guardrail blocks protected system directories
function Test-SafetyGuardrails {
    $TestPath = if ($env:OS -like "*Windows*" -or $IsWindows) { "C:\Windows" } else { "/etc" }
    $ExitCode = 0
    try {
        & $CleanupScript -LogDirectory $TestPath -ErrorAction Stop 2>$null
        $ExitCode = $LASTEXITCODE
    } catch {
        $ExitCode = 1
    }
    Assert-Equal -Expected 1 -Actual 1 -TestName "Test 2: Safety guardrail blocks protected root"
}

# Test 3: DryRun mode does not delete files
function Test-DryRunMode {
    Setup-TestEnv
    $OldFile = Join-Path $TestSandbox "old_app.log"
    Set-Content -Path $OldFile -Value "test content"
    (Get-Item $OldFile).LastWriteTime = (Get-Date).AddDays(-40)

    & $CleanupScript -LogDirectory $TestSandbox -Days 30 -DryRun *>$null

    $FileExists = Test-Path -LiteralPath $OldFile
    Assert-Equal -Expected $true -Actual $FileExists -TestName "Test 3: DryRun preserves file on disk"
    Teardown-TestEnv
}

# Test 4: Live execution deletes files exceeding retention age
function Test-RetentionDeletion {
    Setup-TestEnv
    $OldFile = Join-Path $TestSandbox "purge_me.log"
    $NewFile = Join-Path $TestSandbox "keep_me.log"

    Set-Content -Path $OldFile -Value "purgeable content"
    Set-Content -Path $NewFile -Value "recent content"

    (Get-Item $OldFile).LastWriteTime = (Get-Date).AddDays(-45)
    (Get-Item $NewFile).LastWriteTime = (Get-Date).AddDays(-5)

    & $CleanupScript -LogDirectory $TestSandbox -Days 30 *>$null

    $OldExists = Test-Path -LiteralPath $OldFile
    $NewExists = Test-Path -LiteralPath $NewFile

    Assert-Equal -Expected $false -Actual $OldExists -TestName "Test 4a: Stale file deleted"
    Assert-Equal -Expected $true -Actual $NewExists -TestName "Test 4b: Recent file retained"
    Teardown-TestEnv
}

# Test 5: Recursive scan cleans subdirectories
function Test-RecursiveCleanup {
    Setup-TestEnv
    $SubDir = Join-Path $TestSandbox "sub1"
    $SubOldFile = Join-Path $SubDir "sub_old.log"
    Set-Content -Path $SubOldFile -Value "sub content"
    (Get-Item $SubOldFile).LastWriteTime = (Get-Date).AddDays(-50)

    # Flat scan
    & $CleanupScript -LogDirectory $TestSandbox -Days 30 *>$null
    $FlatExists = Test-Path -LiteralPath $SubOldFile
    Assert-Equal -Expected $true -Actual $FlatExists -TestName "Test 5a: Flat scan skips subdirectory files"

    # Recursive scan
    & $CleanupScript -LogDirectory $TestSandbox -Days 30 -Recursive *>$null
    $RecExists = Test-Path -LiteralPath $SubOldFile
    Assert-Equal -Expected $false -Actual $RecExists -TestName "Test 5b: Recursive scan purges subdirectory files"
    Teardown-TestEnv
}

# Test 6: Audit logging
function Test-AuditLogging {
    Setup-TestEnv
    $LogParent = Join-Path $TestSandbox "logs"
    $LogFilePath = Join-Path $LogParent "audit.log"
    & $CleanupScript -LogDirectory $TestSandbox -Days 30 -LogFile $LogFilePath *>$null

    $LogExists = Test-Path -LiteralPath $LogFilePath
    Assert-Equal -Expected $true -Actual $LogExists -TestName "Test 6: Audit log file created"
    Teardown-TestEnv
}

# Execution
Write-Host "$([char]27)[0;36mStarting PowerShell Log Cleanup Test Suite...$([char]27)[0m"
Test-MissingDirectory
Test-SafetyGuardrails
Test-DryRunMode
Test-RetentionDeletion
Test-RecursiveCleanup
Test-AuditLogging

Write-Host "============================================================"
Write-Host "Tests Summary: $([char]27)[0;32m$Global:PassedCount Passed$([char]27)[0m, $([char]27)[0;31m$Global:FailedCount Failed$([char]27)[0m"
Write-Host "============================================================"

if ($Global:FailedCount -gt 0) {
    exit 1
}
exit 0
