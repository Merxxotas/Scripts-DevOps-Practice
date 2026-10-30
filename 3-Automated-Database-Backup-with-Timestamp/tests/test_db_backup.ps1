#Requires -Version 7.0
<#
.SYNOPSIS
    Automated integration and unit test suite for db_backup.ps1

.DESCRIPTION
    Every test drives the public interface of the tool: the flags, the exit
    codes and the emitted output. The database dump tool is replaced by a
    stub on PATH, so the suite never needs a real database. The suite is
    written to run under pwsh on Linux, macOS and Windows (CI matrix).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$BackupScript = Join-Path (Split-Path -Parent $ScriptDir) "db_backup.ps1"
$BashScript = Join-Path (Split-Path -Parent $ScriptDir) "db_backup.sh"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_ps1_db_backup_" + [System.Guid]::NewGuid().ToString("N"))
$StubDir = Join-Path $TestSandbox "stubs"
$CaptureFile = Join-Path $TestSandbox "dump_capture.txt"
$OutFile = Join-Path $TestSandbox "stdout.txt"
$ErrFile = Join-Path $TestSandbox "stderr.txt"
$script:OriginalPath = $env:PATH

$script:PwshPath = "pwsh"
$pwshCommand = @(Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)
if ($pwshCommand.Count -gt 0) {
    $script:PwshPath = $pwshCommand[0].Source
}

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastRunExitCode = 0

function Enter-TestEnvironment {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $StubDir -Force | Out-Null

    if ($IsWindows) {
        $mysqldumpContent = @"
@echo off
if "%STUB_DUMP_CAPTURE%"=="" set "STUB_DUMP_CAPTURE=NUL"
echo DUMP-CALLED>>"%STUB_DUMP_CAPTURE%"
if "%STUB_DUMP_FAIL%"=="1" (
    echo mysqldump: simulated failure 1>&2
    exit /b 1
)
set "out="
:msloop
if "%~1"=="" goto msdone
if /I "%~1"=="-r" (
    set "out=%~2"
    shift
)
shift
goto msloop
:msdone
if "%STUB_DB_NAME%"=="" set "STUB_DB_NAME=mydatabase"
if not "%out%"=="" (
    echo FAKE SQL DUMP for %STUB_DB_NAME% > "%out%"
) else (
    echo FAKE SQL DUMP for %STUB_DB_NAME%
)
exit /b 0
"@
        Set-Content -LiteralPath (Join-Path $StubDir "mysqldump.cmd") -Value $mysqldumpContent -Encoding ascii

        $pgdumpContent = @"
@echo off
if "%STUB_DUMP_CAPTURE%"=="" set "STUB_DUMP_CAPTURE=NUL"
echo DUMP-CALLED>>"%STUB_DUMP_CAPTURE%"
if "%STUB_DUMP_FAIL%"=="1" (
    echo pg_dump: simulated failure 1>&2
    exit /b 1
)
set "out="
:pgloop
if "%~1"=="" goto pgdone
if /I "%~1"=="-f" (
    set "out=%~2"
    shift
)
shift
goto pgloop
:pgdone
if "%STUB_DB_NAME%"=="" set "STUB_DB_NAME=mydatabase"
if not "%out%"=="" (
    echo FAKE SQL DUMP for %STUB_DB_NAME% > "%out%"
) else (
    echo FAKE SQL DUMP for %STUB_DB_NAME%
)
exit /b 0
"@
        Set-Content -LiteralPath (Join-Path $StubDir "pg_dump.cmd") -Value $pgdumpContent -Encoding ascii
    } else {
        $mysqldumpContent = @'
#!/bin/bash
printf 'DUMP-CALLED\n' >> "${STUB_DUMP_CAPTURE:-/dev/null}"
if [[ "${STUB_DUMP_FAIL:-0}" == "1" ]]; then
    echo "mysqldump: simulated failure" >&2
    exit 1
fi
out=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    if [[ "${args[$i]}" == "-r" ]]; then
        out="${args[$((i+1))]}"
        break
    fi
    i=$((i+1))
done
if [[ -z "${STUB_DB_NAME:-}" ]]; then STUB_DB_NAME="mydatabase"; fi
if [[ -n "$out" ]]; then
    printf 'FAKE SQL DUMP for %s\n' "$STUB_DB_NAME" > "$out"
else
    printf 'FAKE SQL DUMP for %s\n' "$STUB_DB_NAME"
fi
exit 0
'@
        $mysqldumpContent = $mysqldumpContent -replace "`r`n", "`n"
        $msPath = Join-Path $StubDir "mysqldump"
        Set-Content -LiteralPath $msPath -Value $mysqldumpContent -Encoding ascii -NoNewline
        & chmod +x $msPath

        $pgdumpContent = @'
#!/bin/bash
printf 'DUMP-CALLED\n' >> "${STUB_DUMP_CAPTURE:-/dev/null}"
if [[ "${STUB_DUMP_FAIL:-0}" == "1" ]]; then
    echo "pg_dump: simulated failure" >&2
    exit 1
fi
out=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    if [[ "${args[$i]}" == "-f" ]]; then
        out="${args[$((i+1))]}"
        break
    fi
    i=$((i+1))
done
if [[ -z "${STUB_DB_NAME:-}" ]]; then STUB_DB_NAME="mydatabase"; fi
if [[ -n "$out" ]]; then
    printf 'FAKE SQL DUMP for %s\n' "$STUB_DB_NAME" > "$out"
else
    printf 'FAKE SQL DUMP for %s\n' "$STUB_DB_NAME"
fi
exit 0
'@
        $pgdumpContent = $pgdumpContent -replace "`r`n", "`n"
        $pgPath = Join-Path $StubDir "pg_dump"
        Set-Content -LiteralPath $pgPath -Value $pgdumpContent -Encoding ascii -NoNewline
        & chmod +x $pgPath
    }

    Set-Content -LiteralPath $CaptureFile -Value "" -NoNewline
    $env:STUB_DUMP_CAPTURE = $CaptureFile
    $env:STUB_DUMP_FAIL = "0"
    $env:STUB_DB_NAME = "mydatabase"
    Remove-Item Env:DB_BACKUP_PASSWORD -ErrorAction SilentlyContinue
    $env:PATH = "$StubDir$([System.IO.Path]::PathSeparator)$script:OriginalPath"
}

function Exit-TestEnvironment {
    Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:STUB_DUMP_CAPTURE -ErrorAction SilentlyContinue
    Remove-Item Env:STUB_DUMP_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:STUB_DB_NAME -ErrorAction SilentlyContinue
    Remove-Item Env:DB_BACKUP_PASSWORD -ErrorAction SilentlyContinue
    $env:PATH = $script:OriginalPath
}

function Invoke-Backup {
    param([string[]]$Arguments = @())

    $code = 0
    try {
        & $script:PwshPath -NoProfile -File $BackupScript @Arguments 1> $OutFile 2> $ErrFile
        $code = $LASTEXITCODE
    } catch {
        $code = 1
    }

    $script:LastRunExitCode = $code
    $script:LastStdout = Read-Stripped -Path $OutFile
    $script:LastStderr = Read-Stripped -Path $ErrFile
}

function Read-Stripped {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $raw = Get-Content -Raw -LiteralPath $Path
    if ($null -eq $raw) {
        return ""
    }

    return ($raw -replace "`e\[[0-9;]*[a-zA-Z]", "")
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()]$Expected = "",
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()]$Actual = "",
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Actual) { $Actual = "" }
    if ("$Expected" -eq "$Actual") {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (expected '$Expected', got '$Actual')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()]$Haystack = "",
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Haystack) { $Haystack = "" }
    if ($Haystack.Contains($Needle)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (missing '$Needle')" -ForegroundColor Red
        $script:FailedCount++
    }
}

function Assert-Absent {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()]$Haystack = "",
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Haystack) { $Haystack = "" }
    if (-not $Haystack.Contains($Needle)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (unexpected '$Needle')" -ForegroundColor Red
        $script:FailedCount++
    }
}

# ---------- tests ----------

function Test-HelpMenu {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-Help")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 1a: -Help exits 0"
    Assert-Match -Haystack $script:LastStdout -Needle "Database Backup Utility" -TestName "Test 1b: help names the tool"
    Exit-TestEnvironment
}

function Test-UnknownFlag {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-ThisFlagDoesNotExist")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 2: unknown flag exits 1"
    Exit-TestEnvironment
}

function Test-MissingPassword {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-DbName","foo","-BackupDir",(Join-Path $TestSandbox "bk"))
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 3: missing password exits 1"
    Exit-TestEnvironment
}

function Test-DbTypeValidation {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-DbType","oracle","-DbPassword","secret","-BackupDir",(Join-Path $TestSandbox "bk"))
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 4a: unsupported db type exits 1"
    Exit-TestEnvironment
}

function Test-RetentionValidation {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-DbPassword","secret","-RetentionDays","5000","-BackupDir",(Join-Path $TestSandbox "bk"))
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 5a: retention out of range exits 1"
    Invoke-Backup -Arguments @("-DbPassword","secret","-RetentionDays","abc","-BackupDir",(Join-Path $TestSandbox "bk"))
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 5b: non-numeric retention exits 1"
    Exit-TestEnvironment
}

function Test-GuardrailBlockedPath {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir","/etc")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 6a: blocked path /etc exits 1"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir","/")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 6b: blocked path / exits 1"
    Exit-TestEnvironment
}

function Test-DryRun {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk,"-DryRun")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 7a: dry-run exits 0"
    Assert-Match -Haystack $script:LastStdout -Needle "DRY RUN" -TestName "Test 7b: dry-run announces itself"
    $captureLen = if (Test-Path -LiteralPath $CaptureFile) { (Get-Item -LiteralPath $CaptureFile).Length } else { 0 }
    if ($captureLen -gt 0) {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 7c: dump tool was invoked during dry-run" -ForegroundColor Red
        $script:FailedCount++
    } else {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 7c: dump tool not invoked during dry-run"
        $script:PassedCount++
    }
    Exit-TestEnvironment
}

function Test-BackupCreated {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 8a: backup exits 0"
    $found = @(Get-ChildItem -Path $bk -Filter "*.zip" -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($found) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 8b: compressed backup created"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 8b: no compressed backup found" -ForegroundColor Red
        $script:FailedCount++
    }
    Exit-TestEnvironment
}

function Test-DumpFailure {
    Enter-TestEnvironment
    $env:STUB_DUMP_FAIL = "1"
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk)
    Assert-Equal -Expected 2 -Actual $script:LastRunExitCode -TestName "Test 9: dump failure exits 2"
    Exit-TestEnvironment
}

function Test-RetentionPrunesOld {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    New-Item -ItemType Directory -Path $bk -Force | Out-Null
    $oldFile = Join-Path $bk "mysql_mydatabase_20200101_000000.sql.gz"
    Set-Content -LiteralPath $oldFile -Value "old" -NoNewline
    (Get-Item -LiteralPath $oldFile).LastWriteTime = (Get-Date).AddDays(-10)
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk,"-RetentionDays","7")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 10a: backup exits 0"
    if (-not (Test-Path -LiteralPath $oldFile)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 10b: old backup pruned"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 10b: old backup not pruned" -ForegroundColor Red
        $script:FailedCount++
    }
    Exit-TestEnvironment
}

function Test-PostgresqlBackend {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbType","postgresql","-DbPassword","secret","-BackupDir",$bk)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 11a: postgresql backup exits 0"
    $found = @(Get-ChildItem -Path $bk -Filter "postgresql_*.zip" -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($found) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 11b: postgresql backup created"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 11b: no postgresql backup found" -ForegroundColor Red
        $script:FailedCount++
    }
    Exit-TestEnvironment
}

function Test-PasswordFromEnv {
    Enter-TestEnvironment
    $env:DB_BACKUP_PASSWORD = "secret"
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbName","foo","-BackupDir",$bk)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 12: password from env exits 0"
    Exit-TestEnvironment
}

function Test-NoCompress {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk,"-NoCompress")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 13a: no-compress exits 0"
    $found = @(Get-ChildItem -Path $bk -Filter "*.sql" -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($found) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 13b: raw .sql retained when -NoCompress"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 13b: no raw .sql found" -ForegroundColor Red
        $script:FailedCount++
    }
    Exit-TestEnvironment
}

function Test-AuditLog {
    Enter-TestEnvironment
    $bk = Join-Path $TestSandbox "bk"
    $audit = Join-Path $TestSandbox "audit.log"
    Invoke-Backup -Arguments @("-DbPassword","secret","-BackupDir",$bk,"-LogFile",$audit)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 14a: backup with audit exits 0"
    if (Test-Path -LiteralPath $audit) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m Test 14b: audit log created"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m Test 14b: audit log not created" -ForegroundColor Red
        $script:FailedCount++
    }
    Exit-TestEnvironment
}

function Test-HelpMentionsBackends {
    Enter-TestEnvironment
    Invoke-Backup -Arguments @("-Help")
    Assert-Match -Haystack $script:LastStdout -Needle "mysql" -TestName "Test 15a: help mentions mysql"
    Assert-Match -Haystack $script:LastStdout -Needle "postgresql" -TestName "Test 15b: help mentions postgresql"
    Exit-TestEnvironment
}

# ---------- parity proof ----------

function Get-BashLongFlag {
    param([string]$Path)
    $text = Get-Content -Raw -LiteralPath $Path
    $block = [regex]::Match($text, "(?ms)^parse_args\(\) \{.*?^\}").Value
    $flags = [regex]::Matches($block, "--([a-z][a-z-]*)") | ForEach-Object { $_.Groups[1].Value }
    return @($flags | Sort-Object -Unique)
}

function Get-PowerShellLongFlag {
    param([string]$Path)
    $text = Get-Content -Raw -LiteralPath $Path
    $block = [regex]::Match($text, "(?ms)^param\(.*?^\)").Value
    $params = [regex]::Matches($block, "\[.*?\]\s*\`$([A-Za-z]+)") | ForEach-Object { $_.Groups[1].Value }
    $flags = foreach ($name in $params) {
        ($name -creplace "([a-z0-9])([A-Z])", '$1-$2').ToLowerInvariant()
    }
    if ($text -match "(?m)^\[CmdletBinding\(\)\]") {
        $flags = @($flags) + "verbose"
    }
    return @($flags | Sort-Object -Unique)
}

function Test-PublicInterfaceMatchesBashSide {
    Enter-TestEnvironment
    $bashFlags = (Get-BashLongFlag -Path $BashScript) -join " "
    $psFlags = (Get-PowerShellLongFlag -Path $BackupScript) -join " "
    Assert-Match -Haystack $bashFlags -Needle "db-type" -TestName "Test P1a: Bash flag extraction holds the interface"
    Assert-Match -Haystack $psFlags -Needle "db-type" -TestName "Test P1b: PowerShell flag extraction holds the interface"
    Assert-Match -Haystack $bashFlags -Needle "help" -TestName "Test P1c: Bash flag extraction holds help"
    Assert-Match -Haystack $psFlags -Needle "help" -TestName "Test P1d: PowerShell flag extraction holds help"
    Assert-Equal -Expected $bashFlags -Actual $psFlags -TestName "Test P1e: Both implementations offer the same flags"
    Exit-TestEnvironment
}

# ---------- run ----------
Write-Host "$([char]27)[0;36mStarting PowerShell DB Backup Test Suite...$([char]27)[0m"
Test-HelpMenu
Test-UnknownFlag
Test-MissingPassword
Test-DbTypeValidation
Test-RetentionValidation
Test-GuardrailBlockedPath
Test-DryRun
Test-BackupCreated
Test-DumpFailure
Test-RetentionPrunesOld
Test-PostgresqlBackend
Test-PasswordFromEnv
Test-NoCompress
Test-AuditLog
Test-HelpMentionsBackends
Test-PublicInterfaceMatchesBashSide

# Json/Csv mutual exclusion
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "pwsh"
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { $psi.FileName = "powershell" }
$psi.Arguments = "-NoProfile -File `"$BackupScript`" -DbPassword secret -Json -Csv"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
$null = $proc.StandardOutput.ReadToEnd()
$null = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
if ($proc.ExitCode -eq 1) {
    Write-Host "[PASS] Json/Csv mutual exclusion exits 1" -ForegroundColor Green
    $script:PassedCount++
} else {
    Write-Host "[FAIL] Json/Csv mutual exclusion (got $($proc.ExitCode))" -ForegroundColor Red
    $script:FailedCount++
}

Write-Host "============================================================"
Write-Host "Tests Summary: $([char]27)[0;32m$script:PassedCount Passed$([char]27)[0m, $([char]27)[0;31m$script:FailedCount Failed$([char]27)[0m"
Write-Host "============================================================"

if ($script:FailedCount -gt 0) {
    exit 1
}
exit 0