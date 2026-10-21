#Requires -Version 7.0
<#
.SYNOPSIS
    Automated integration and unit test suite for disk_monitor.ps1

.DESCRIPTION
    Every test drives the public interface of the tool: the flags, the exit
    codes and the emitted output. The script is invoked as a separate process
    with pwsh -File, because the process exit code is the contract a caller
    actually observes, and because the behaviour is then identical on Windows
    and on Ubuntu.

    The measurement command and the mail agent are replaced by stubs, so the
    suite never depends on the host's real disk layout and never sends a real
    email.
#>

Set-StrictMode -Version Latest
# A test that raises an error must fail the run, not disappear from the
# summary. With Continue, a parameter binding error would print and be
# skipped, and the suite would report a pass it never earned.
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$MonitorScript = Join-Path (Split-Path -Parent $ScriptDir) "disk_monitor.ps1"
$TestSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("test_ps1_disk_" + [System.Guid]::NewGuid().ToString("N"))
$StubDir = Join-Path $TestSandbox "stubs"
$CaptureFile = Join-Path $TestSandbox "mail_capture.txt"
$OutFile = Join-Path $TestSandbox "stdout.txt"
$ErrFile = Join-Path $TestSandbox "stderr.txt"
$UsageStub = Join-Path $StubDir "usage_stub.ps1"
$MailStub = Join-Path $StubDir "mail_stub.ps1"

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastExitCode = 0

# Creates the sandbox, the stubs and a clean environment
function New-TestEnvironment {
    if (Test-Path -LiteralPath $TestSandbox) {
        Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $StubDir -Force | Out-Null

    # Measurement stub. It emits the POSIX six-field layout, so the module's
    # parser is exercised exactly as it would be on a real host.
    @'
param(
    [Parameter(Mandatory = $false, Position = 1)][string]$P = "",
    [Parameter(Mandatory = $false, Position = 2)][string]$Partition = ""
)

if ($env:DISK_MONITOR_STUB_DF_FAIL -eq "1") {
    [Console]::Error.WriteLine("measurement stub: simulated failure")
    exit 1
}

$usage = $env:DISK_MONITOR_STUB_DF_USAGE
if ([string]::IsNullOrWhiteSpace($usage)) {
    $usage = "49"
}

Write-Output "Filesystem     1024-blocks      Used Available Capacity Mounted on"
Write-Output "/dev/stub0        1000000  500000    500000      $usage% /"
exit 0
'@ | Set-Content -LiteralPath $UsageStub -Encoding utf8

    # Measurement stub whose mount point contains a space. The capacity is
    # still the fifth field, because the mount point is last and may be
    # several words long.
    @'
param(
    [Parameter(Mandatory = $false, Position = 1)][string]$P = "",
    [Parameter(Mandatory = $false, Position = 2)][string]$Partition = ""
)

Write-Output "Filesystem     1024-blocks      Used Available Capacity Mounted on"
Write-Output "/dev/stub0        1000000  500000    500000      63% /mnt/my disk"
exit 0
'@ | Set-Content -LiteralPath (Join-Path $StubDir "usage_spaced_stub.ps1") -Encoding utf8

    # Mail stub. It records the subject, the recipient and the body, so the
    # test can assert on the composed message without sending anything.
    @'
param(
    [Parameter(Mandatory = $false, Position = 1)][string]$s = "",
    [Parameter(Mandatory = $false, Position = 2)][string]$Recipient = ""
)

$lines = @()
$lines += "SUBJECT:$s"
$lines += "RECIPIENT:$Recipient"
$lines += "STDIN-BEGIN"
$lines += ($input | Out-String)
$lines += "STDIN-END"
Add-Content -LiteralPath $env:DISK_MONITOR_STUB_CAPTURE -Value $lines

if ($env:DISK_MONITOR_STUB_MAIL_FAIL -eq "1") {
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath $MailStub -Encoding utf8

    Set-Content -LiteralPath $CaptureFile -Value "" -NoNewline

    $env:DISK_MONITOR_STUB_CAPTURE = $CaptureFile
    $env:DISK_MONITOR_STUB_DF_USAGE = "49"
    $env:DISK_MONITOR_STUB_DF_FAIL = "0"
    $env:DISK_MONITOR_STUB_MAIL_FAIL = "0"
    $env:DISK_MONITOR_USAGE_COMMAND = $UsageStub
    Remove-Item Env:DISK_MONITOR_USAGE_OVERRIDE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TO -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_MAIL_COMMAND -ErrorAction SilentlyContinue
}

function Remove-TestEnvironment {
    Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_CAPTURE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_DF_USAGE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_DF_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_MAIL_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_USAGE_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_USAGE_OVERRIDE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TO -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_MAIL_COMMAND -ErrorAction SilentlyContinue
}

# Runs the monitor as a separate process and captures its exit code and output
function Invoke-Monitor {
    param([string[]]$Arguments = @())

    $code = 0
    try {
        & pwsh -NoProfile -File $MonitorScript @Arguments 1> $OutFile 2> $ErrFile
        $code = $LASTEXITCODE
    } catch {
        $code = 1
    }

    $script:LastExitCode = $code
    $script:LastStdout = Read-Stripped -Path $OutFile
    $script:LastStderr = Read-Stripped -Path $ErrFile
}

# Reads a captured file and removes the ANSI escape sequences
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

    if ($Expected -eq $Actual) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected: '$Expected', Got: '$Actual')"
        $script:FailedCount++
    }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()][string]$Haystack = "",
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Haystack) {
        $Haystack = ""
    }

    if ($Haystack.Contains($Needle)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected to contain: '$Needle')"
        $script:FailedCount++
    }
}

# Asserts that the mail agent was never invoked
function Assert-CaptureEmpty {
    param([Parameter(Mandatory = $true)][string]$TestName)

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) {
            $capture = $raw
        }
    }

    if ([string]::IsNullOrWhiteSpace($capture)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected no mail activity, got: '$capture')"
        $script:FailedCount++
    }
}

# Test 1: Help exits with code 0 and documents the flags
function Test-HelpMenu {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Help")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 1a: Help menu exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "Disk Usage Monitor" -TestName "Test 1b: Help menu names the tool"
    Assert-Match -Haystack $script:LastStdout -Needle "-Threshold" -TestName "Test 1c: Help menu documents -Threshold"
    Assert-Match -Haystack $script:LastStdout -Needle "-DryRun" -TestName "Test 1d: Help menu documents -DryRun"
    Assert-Match -Haystack $script:LastStdout -Needle "-Notify" -TestName "Test 1e: Help menu documents -Notify"
    Remove-TestEnvironment
}

# Test 2: An unknown parameter is a configuration error
function Test-UnknownParameter {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-ThisFlagDoesNotExist")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 2: Unknown parameter exits with code 1"
    Remove-TestEnvironment
}

# Test 3: The threshold is validated as an integer between 1 and 100
function Test-ThresholdValidation {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Threshold", "0")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 3a: Threshold 0 exits with code 1"
    Invoke-Monitor -Arguments @("-Threshold", "101")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 3b: Threshold 101 exits with code 1"
    Invoke-Monitor -Arguments @("-Threshold", "abc")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 3c: Non-numeric threshold exits with code 1"
    Remove-TestEnvironment
}

# Test 4: The notify backend is validated against the supported set
function Test-NotifyValidation {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "carrier-pigeon", "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 4: Unsupported notify backend exits with code 1"
    Remove-TestEnvironment
}

# Test 5: A partition that does not exist is a configuration error
function Test-MissingPartition {
    New-TestEnvironment
    $missing = Join-Path $TestSandbox "does-not-exist"
    Invoke-Monitor -Arguments @("-Partition", $missing, "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 5: Missing partition exits with code 1"
    Remove-TestEnvironment
}

# Test 6: A missing recipient is a configuration error when mail is enabled
function Test-MissingRecipient {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "mail")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 6a: Missing recipient exits with code 1"
    Assert-Match -Haystack $script:LastStderr -Needle "DISK_MONITOR_TO" -TestName "Test 6b: Missing recipient names the environment variable"
    Remove-TestEnvironment
}

# Test 7: An unresolvable mail agent is a configuration error
function Test-MissingMailAgent {
    New-TestEnvironment
    $missing = Join-Path $TestSandbox "not-a-real-agent"
    Invoke-Monitor -Arguments @("-MailCommand", $missing, "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 7: Unresolvable mail agent exits with code 1"
    Assert-Match -Haystack $script:LastStderr -Needle "mail" -TestName "Test 7b: Unresolvable mail agent explains itself"
    Remove-TestEnvironment
}

# Test 8: Usage below the threshold exits 0 and sends nothing
function Test-BelowThreshold {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 8a: Usage below the threshold exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "42%" -TestName "Test 8b: The report shows the measured usage"
    Assert-CaptureEmpty -TestName "Test 8c: No alert is sent below the threshold"
    Remove-TestEnvironment
}

# Test 9: Usage above the threshold sends the alert and still exits 0
function Test-AboveThreshold {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "91"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 9a: Usage above the threshold exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 9b: The report warns about the breach"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops@example.com" -TestName "Test 9c: The alert carries the recipient"
    Assert-Match -Haystack $capture -Needle "91%" -TestName "Test 9d: The alert body carries the measured usage"
    Assert-Match -Haystack $capture -Needle "Disk Alert" -TestName "Test 9e: The alert carries the expected subject"
    Remove-TestEnvironment
}

# Test 10: Usage exactly at the threshold does not alert
function Test-ThresholdBoundary {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "80"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 10a: Usage equal to the threshold exits with code 0"
    Assert-CaptureEmpty -TestName "Test 10b: Usage equal to the threshold does not alert"
    Remove-TestEnvironment
}

# Test 11: DryRun reports the alert without handing it to the mail agent
function Test-DryRun {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-DryRun", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 11a: DryRun exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "DRY RUN" -TestName "Test 11b: DryRun announces itself"
    Assert-CaptureEmpty -TestName "Test 11c: DryRun hands nothing to the mail agent"
    Remove-TestEnvironment
}

# Test 12: -Notify none never touches the mail agent
function Test-NotifyNone {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 12a: -Notify none exits with code 0"
    Assert-CaptureEmpty -TestName "Test 12b: -Notify none hands nothing to the mail agent"
    Remove-TestEnvironment
}

# Test 13: -Notify none needs no recipient
function Test-NotifyNoneNeedsNoRecipient {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 13: -Notify none requires no recipient"
    Remove-TestEnvironment
}

# Test 14: The audit log is written
function Test-AuditLog {
    New-TestEnvironment
    $auditFile = Join-Path $TestSandbox "logs/audit.log"
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub, "-LogFile", $auditFile)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 14a: Run with an audit log exits with code 0"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $auditFile) -TestName "Test 14b: The audit log file is created"

    $audit = ""
    if (Test-Path -LiteralPath $auditFile) {
        $raw = Get-Content -Raw -LiteralPath $auditFile
        if ($null -ne $raw) { $audit = $raw }
    }
    Assert-Match -Haystack $audit -Needle "95" -TestName "Test 14c: The audit log records the measured usage"
    Remove-TestEnvironment
}

# Test 15: A disk usage read failure is a partial failure
function Test-UsageReadFailure {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_FAIL = "1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 2 -Actual $script:LastExitCode -TestName "Test 15: An unreadable disk usage exits with code 2"
    Remove-TestEnvironment
}

# Test 16: A failed alert hand-off is a partial failure
function Test-AlertHandoffFailure {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_STUB_MAIL_FAIL = "1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 2 -Actual $script:LastExitCode -TestName "Test 16: A failed alert hand-off exits with code 2"
    Remove-TestEnvironment
}

# Test 17: The recipient falls back to the environment variable
function Test-RecipientFromEnvironment {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_TO = "oncall@example.com"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 17a: The environment recipient is accepted"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "oncall@example.com" -TestName "Test 17b: The environment recipient is used"
    Remove-TestEnvironment
}

# Test 18: The mail command can be overridden by the environment
function Test-MailCommandFromEnvironment {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_MAIL_COMMAND = $MailStub
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 18: The mail command can come from the environment"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops@example.com" -TestName "Test 18b: The overridden mail command is used"
    Remove-TestEnvironment
}

# Test 19: The verbose flag is accepted
function Test-Verbose {
    New-TestEnvironment
    Invoke-Monitor -Arguments @("-Verbose", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 19a: The verbose flag is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "Partition" -TestName "Test 19b: The report names the watched partition"
    Remove-TestEnvironment
}

# Test 20: A forced usage value is honoured and labelled as such
function Test-UsageOverride {
    New-TestEnvironment
    $env:DISK_MONITOR_USAGE_OVERRIDE = "91"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 20a: A forced usage value is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "91%" -TestName "Test 20b: The forced value is reported"
    Assert-Match -Haystack $script:LastStdout -Needle "overridden" -TestName "Test 20c: The report labels the value as overridden"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "91%" -TestName "Test 20d: The alert carries the forced value"
    Remove-TestEnvironment
}

# Test 21: An invalid forced usage value is a configuration error
function Test-InvalidUsageOverride {
    New-TestEnvironment
    $env:DISK_MONITOR_USAGE_OVERRIDE = "abc"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 21: An invalid usage override exits with code 1"
    Remove-TestEnvironment
}

# Test 22: The measurement command can be replaced
function Test-UsageCommandOverride {
    New-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "77"
    Invoke-Monitor -Arguments @("-Threshold", "70", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 22a: A replaced measurement command is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "77%" -TestName "Test 22b: The replaced command supplies the usage"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "77%" -TestName "Test 22c: The alert carries the replaced value"
    Remove-TestEnvironment
}

# Test 23: An unresolvable measurement command is a configuration error
function Test-MissingUsageCommand {
    New-TestEnvironment
    $env:DISK_MONITOR_USAGE_COMMAND = Join-Path $TestSandbox "not-a-real-command"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 1 -Actual $script:LastExitCode -TestName "Test 23: An unresolvable measurement command exits with code 1"
    Remove-TestEnvironment
}

# Test 24: The default measurement source works against the real host
function Test-DefaultMeasurementSource {
    New-TestEnvironment
    Remove-Item Env:DISK_MONITOR_USAGE_COMMAND -ErrorAction SilentlyContinue
    Invoke-Monitor -Arguments @("-Threshold", "100", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 24a: The default measurement source exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "measured" -TestName "Test 24b: The default source is labelled as measured"
    Remove-TestEnvironment
}

# Test 25: A mount point containing spaces does not shift the capacity column
function Test-MountPointWithSpace {
    New-TestEnvironment
    $env:DISK_MONITOR_USAGE_COMMAND = Join-Path $StubDir "usage_spaced_stub.ps1"
    Invoke-Monitor -Arguments @("-Threshold", "60", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastExitCode -TestName "Test 25a: A spaced mount point exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "63%" -TestName "Test 25b: The capacity is read from its fixed position"
    Remove-TestEnvironment
}

# Execution
Write-Host "$([char]27)[0;36mStarting PowerShell Disk Monitor Test Suite...$([char]27)[0m"
Test-HelpMenu
Test-UnknownParameter
Test-ThresholdValidation
Test-NotifyValidation
Test-MissingPartition
Test-MissingRecipient
Test-MissingMailAgent
Test-BelowThreshold
Test-AboveThreshold
Test-ThresholdBoundary
Test-DryRun
Test-NotifyNone
Test-NotifyNoneNeedsNoRecipient
Test-AuditLog
Test-UsageReadFailure
Test-AlertHandoffFailure
Test-RecipientFromEnvironment
Test-MailCommandFromEnvironment
Test-Verbose
Test-UsageOverride
Test-InvalidUsageOverride
Test-UsageCommandOverride
Test-MissingUsageCommand
Test-DefaultMeasurementSource
Test-MountPointWithSpace

Write-Host "============================================================"
Write-Host "Tests Summary: $([char]27)[0;32m$script:PassedCount Passed$([char]27)[0m, $([char]27)[0;31m$script:FailedCount Failed$([char]27)[0m"
Write-Host "============================================================"

if ($script:FailedCount -gt 0) {
    exit 1
}
exit 0
