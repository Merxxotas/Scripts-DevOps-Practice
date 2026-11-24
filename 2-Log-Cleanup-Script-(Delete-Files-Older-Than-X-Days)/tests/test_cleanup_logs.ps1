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

$Script:PassedCount = 0
$Script:FailedCount = 0

function Enter-TestEnvironment {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path (Join-Path $TestSandbox "sub1") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TestSandbox "sub2") -Force | Out-Null
}

function Exit-TestEnvironment {
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
        $Script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected: '$Expected', Got: '$Actual')"
        $Script:FailedCount++
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
function Test-SafetyGuardrail {
    $TestPath = if ($env:OS -like "*Windows*" -or $IsWindows) { "C:\Windows" } else { "/etc" }
    $ExitCode = 0
    try {
        & $CleanupScript -LogDirectory $TestPath -ErrorAction Stop 2>$null
        $ExitCode = $LASTEXITCODE
    } catch {
        $ExitCode = 1
    }
    Assert-Equal -Expected 1 -Actual $ExitCode -TestName "Test 2: Safety guardrail blocks protected root"
}

# Test 2b: a directory under a critical root is refused too (subtree guard)
function Test-SafetyGuardrailSubtree {
    $TestPath = if ($env:OS -like "*Windows*" -or $IsWindows) { "C:\Windows\System32\drivers" } else { "/etc/ssh" }
    if (-not (Test-Path -LiteralPath $TestPath)) {
        Write-Host "$([char]27)[0;36m[SKIP]$([char]27)[0m Test 2b: $TestPath does not exist on this host"
        return
    }
    $ExitCode = 0
    try {
        & $CleanupScript -LogDirectory $TestPath -DryRun -ErrorAction Stop *>$null
        $ExitCode = $LASTEXITCODE
    } catch {
        $ExitCode = 1
    }
    Assert-Equal -Expected 1 -Actual $ExitCode -TestName "Test 2b: Safety guardrail blocks subtree of protected root"
}

# Test 2c: the user profile root itself is refused
function Test-SafetyGuardrailHome {
    $ExitCode = 0
    $HomeDir = [Environment]::GetFolderPath("UserProfile")
    if ([string]::IsNullOrEmpty($HomeDir)) { $HomeDir = $HOME }
    try {
        & $CleanupScript -LogDirectory $HomeDir -DryRun -ErrorAction Stop *>$null
        $ExitCode = $LASTEXITCODE
    } catch {
        $ExitCode = 1
    }
    Assert-Equal -Expected 1 -Actual $ExitCode -TestName "Test 2c: Safety guardrail blocks the user profile root"
}

# Test 2d: Days = 0 must not delete anything (parameter validation rejects it)
function Test-DaysZeroRejected {
    Enter-TestEnvironment
    $OldFile = Join-Path $TestSandbox "purge_me.log"
    Set-Content -Path $OldFile -Value "purgeable content"
    (Get-Item $OldFile).LastWriteTime = (Get-Date).AddDays(-45)

    & $CleanupScript -LogDirectory $TestSandbox -Days 0 *>$null

    $FileExists = Test-Path -LiteralPath $OldFile
    Assert-Equal -Expected $true -Actual $FileExists -TestName "Test 2d: Days = 0 leaves files untouched"
    Exit-TestEnvironment
}

# Test 2e: Windows drive root itself is refused (normalization regression guard)
function Test-DriveRootGuard {
    if (-not ($env:OS -like "*Windows*" -or $IsWindows)) {
        Write-Host "$([char]27)[0;36m[SKIP]$([char]27)[0m Test 2e: Windows-only drive root check"
        return
    }
    $ExitCode = 0
    try {
        & $CleanupScript -LogDirectory "C:\" -DryRun -ErrorAction Stop *>$null
        $ExitCode = $LASTEXITCODE
    } catch {
        $ExitCode = 1
    }
    Assert-Equal -Expected 1 -Actual $ExitCode -TestName "Test 2e: Safety guardrail blocks the drive root 'C:\'"
}

# Test 3: DryRun mode does not delete files
function Test-DryRunMode {
    Enter-TestEnvironment
    $OldFile = Join-Path $TestSandbox "old_app.log"
    Set-Content -Path $OldFile -Value "test content"
    (Get-Item $OldFile).LastWriteTime = (Get-Date).AddDays(-40)

    & $CleanupScript -LogDirectory $TestSandbox -Days 30 -DryRun *>$null

    $FileExists = Test-Path -LiteralPath $OldFile
    Assert-Equal -Expected $true -Actual $FileExists -TestName "Test 3: DryRun preserves file on disk"
    Exit-TestEnvironment
}

# Test 4: Live execution deletes files exceeding retention age
function Test-RetentionDeletion {
    Enter-TestEnvironment
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
    Exit-TestEnvironment
}

# Test 5: Recursive scan cleans subdirectories
function Test-RecursiveCleanup {
    Enter-TestEnvironment
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
    Exit-TestEnvironment
}

# Test 6: Audit logging
function Test-AuditLogging {
    Enter-TestEnvironment
    $LogParent = Join-Path $TestSandbox "logs"
    $LogFilePath = Join-Path $LogParent "audit.log"
    & $CleanupScript -LogDirectory $TestSandbox -Days 30 -LogFile $LogFilePath *>$null

    $LogExists = Test-Path -LiteralPath $LogFilePath
    Assert-Equal -Expected $true -Actual $LogExists -TestName "Test 6: Audit log file created"
    Exit-TestEnvironment
}

# Run the published lab steps, including their filesystem assertions.
function Test-Lab1Walkthrough {
    $ErrorActionPreference = "Stop"
    $LabPath = Join-Path (Split-Path -Parent $ScriptDir) `
        "docs/labs/LAB1_BASIC_RETENTION_AND_DRYRUN.md"
    $Lab = Get-Content -LiteralPath $LabPath -Raw
    $Blocks = [regex]::Matches($Lab, '(?ms)^```powershell[^\S\r\n]*\r?\n(.*?)^```')
    if ($Blocks.Count -ne 4) {
        Assert-Equal -Expected 4 -Actual $Blocks.Count -TestName "Lab 1 publishes all PowerShell steps"
        return
    }

    Push-Location -LiteralPath (Split-Path -Parent $CleanupScript)
    $LabDir = $null
    try {
        $Commands = ($Blocks | ForEach-Object { $_.Groups[1].Value }) -join "`n"
        # Keep the setup variable in this scope so the sandbox can be cleaned up on failure.
        . ([scriptblock]::Create($Commands))
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $LabDir) `
            -TestName "Lab 1 completes dry-run, live purge, and sandbox cleanup"
    } catch {
        Assert-Equal -Expected "Lab succeeds" -Actual $_.ToString() -TestName "Lab 1 examples"
    } finally {
        Pop-Location
        if ($LabDir -and (Test-Path -LiteralPath $LabDir)) {
            Remove-Item -LiteralPath $LabDir -Recurse -Force
        }
    }
}

# Exercise the published scan examples and their filesystem assertions on Windows as well.
function Test-Lab2Walkthrough {
    $ErrorActionPreference = "Stop"
    $Lab = Join-Path (Split-Path -Parent $ScriptDir) `
        "docs/labs/LAB2_RECURSIVE_SIZE_FILTERING.md"
    $Blocks = [regex]::Matches((Get-Content -LiteralPath $Lab -Raw),
        '(?ms)^```powershell[^\S\r\n]*\r?\n(.*?)^```')
    if ($Blocks.Count -ne 6) {
        Assert-Equal -Expected 6 -Actual $Blocks.Count -TestName "Lab 2 publishes all PowerShell steps"
        return
    }

    Push-Location -LiteralPath (Split-Path -Parent $CleanupScript)
    $LabDir = $null
    try {
        . ([scriptblock]::Create($Blocks[0].Groups[1].Value))
        $Expected = @{
            1 = @('root_old.log')
            2 = @('root_old.log', 'auth/small_old.log', 'billing/large_old.log',
                  'worker/large_old.log')
            3 = @('billing/large_old.log', 'worker/large_old.log')
        }
        foreach ($Step in 1..3) {
            $Output = . ([scriptblock]::Create($Blocks[$Step].Groups[1].Value)) 6>&1
            $Candidates = @($Output | Where-Object { $_.ToString() -match 'Would delete: ' })
            $Missing = @(foreach ($Log in $Expected[$Step]) {
                $Path = [regex]::Escape((Join-Path $LabDir $Log))
                if (-not ($Candidates -match "Would delete: $Path \(")) { $Log }
            })
            if ($Candidates.Count -ne $Expected[$Step].Count -or $Missing.Count -ne 0) {
                throw "Unexpected candidates in Lab 2 scan ${Step}: $($Candidates -join '; ')"
            }
        }
        foreach ($Step in 4..5) {
            . ([scriptblock]::Create($Blocks[$Step].Groups[1].Value))
        }
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $LabDir) `
            -TestName "Lab 2 selects the expected logs and removes its sandbox"
    } catch {
        Assert-Equal -Expected "Lab succeeds" -Actual $_.ToString() -TestName "Lab 2 examples"
    } finally {
        Pop-Location
        if ($LabDir -and (Test-Path -LiteralPath $LabDir)) {
            Remove-Item -LiteralPath $LabDir -Recurse -Force
        }
    }
}

# Run only the executable walkthrough. Scheduler configuration is reference text.
function Test-Lab3Walkthrough {
    $ErrorActionPreference = "Stop"
    $Lab = Join-Path (Split-Path -Parent $ScriptDir) `
        "docs/labs/LAB3_PRODUCTION_SCHEDULING_AND_AUDIT.md"
    $Blocks = [regex]::Matches((Get-Content -LiteralPath $Lab -Raw),
        '(?ms)^```powershell[^\S\r\n]*\r?\n(.*?)^```')
    if ($Blocks.Count -ne 3) {
        Assert-Equal -Expected 3 -Actual $Blocks.Count -TestName "Lab 3 publishes its isolated steps"
        return
    }

    Push-Location -LiteralPath (Split-Path -Parent $CleanupScript)
    $LabDir = $null
    try {
        . ([scriptblock]::Create(($Blocks | ForEach-Object { $_.Groups[1].Value }) -join "`n"))
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $LabDir) `
            -TestName "Lab 3 verifies audit entries and exit codes without a scheduler"
    } catch {
        Assert-Equal -Expected "Lab succeeds" -Actual $_.ToString() -TestName "Lab 3 examples"
    } finally {
        Pop-Location
        if ($LabDir -and (Test-Path -LiteralPath $LabDir)) {
            Remove-Item -LiteralPath $LabDir -Recurse -Force
        }
    }
}

function Test-IncompleteScan {
    param([switch]$DryRun)

    Enter-TestEnvironment
    try {
        $Candidate = Join-Path $TestSandbox 'purge_me.log'
        $Audit = Join-Path $TestSandbox 'audit.txt'
        $ErrorFile = Join-Path $TestSandbox 'stderr.txt'
        [System.IO.File]::WriteAllText($Candidate, 'original log')
        [System.IO.File]::SetLastWriteTime($Candidate, [datetime]::new(2000, 1, 1))
        $Runner = Join-Path $TestSandbox 'scan-fixture.ps1'
        Set-Content -LiteralPath $Runner -Value @'
param($CleanupScript, $Target, $Candidate, $Audit, $Mode)
function Get-ChildItem {
    [CmdletBinding()]
    param($LiteralPath, $Filter, [switch]$File, [switch]$Force, [switch]$Recurse)
    Get-Item -LiteralPath $Candidate
    Write-Error 'Simulated failure after enumerating one file'
}
$Options = if ($Mode -eq 'DryRun') { @{ DryRun = $true; Csv = $true } }
           else { @{ Recursive = $true; Json = $true } }
& $CleanupScript -LogDirectory $Target -Days 30 -LogFile $Audit @Options
exit $LASTEXITCODE
'@
        $Mode = if ($DryRun) { 'DryRun' } else { 'Live' }
        $Executable = (Get-Process -Id $PID).Path
        # Process-level redirection keeps Windows PowerShell from formatting native stderr.
        $OutputFile = Join-Path $TestSandbox 'stdout.txt'
        $Arguments = @('-NoProfile', '-File', "`"$Runner`"", "`"$CleanupScript`"",
            "`"$TestSandbox`"", "`"$Candidate`"", "`"$Audit`"", $Mode)
        $Process = Start-Process -FilePath $Executable -ArgumentList $Arguments `
            -RedirectStandardOutput $OutputFile -RedirectStandardError $ErrorFile -Wait -PassThru
        $ExitCode = $Process.ExitCode
        $Diagnostic = 'Error: File enumeration failed; no log files were processed.'
        $Contents = if (Test-Path -LiteralPath $Candidate) {
            [System.IO.File]::ReadAllText($Candidate)
        } else { '[missing]' }

        Assert-Equal 2 $ExitCode "${Mode}: incomplete scan exits 2"
        Assert-Equal 'original log' $Contents "${Mode}: candidate remains untouched"
        Assert-Equal 0 ([System.IO.FileInfo]::new($OutputFile).Length) `
            "${Mode}: no partial report on stdout"
        $ExpectedError = $Diagnostic + [Environment]::NewLine
        Assert-Equal $true ([System.IO.File]::ReadAllText($ErrorFile) -ceq $ExpectedError) `
            "${Mode}: stderr diagnostic"
        Assert-Equal $true (([System.IO.File]::ReadAllText($Audit)).Contains("[ERROR] $Diagnostic")) `
            "${Mode}: audit records the enumeration failure"
    } finally {
        Exit-TestEnvironment
    }
}

# Execution
Write-Host "$([char]27)[0;36mStarting PowerShell Log Cleanup Test Suite...$([char]27)[0m"
Test-MissingDirectory
Test-SafetyGuardrail
Test-SafetyGuardrailSubtree
Test-SafetyGuardrailHome
Test-DaysZeroRejected
Test-DriveRootGuard
Test-DryRunMode
Test-RetentionDeletion
Test-RecursiveCleanup
Test-AuditLogging
Test-Lab1Walkthrough
Test-Lab2Walkthrough
Test-Lab3Walkthrough
Test-IncompleteScan
Test-IncompleteScan -DryRun

Write-Host "============================================================"
Write-Host "Tests Summary: $([char]27)[0;32m$Script:PassedCount Passed$([char]27)[0m, $([char]27)[0;31m$Script:FailedCount Failed$([char]27)[0m"
Write-Host "============================================================"

if ($Script:FailedCount -gt 0) {
    exit 1
}
exit 0
