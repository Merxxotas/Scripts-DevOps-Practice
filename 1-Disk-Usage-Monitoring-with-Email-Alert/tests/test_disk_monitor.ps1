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
$HttpCaptureFile = Join-Path $TestSandbox "http_capture.txt"
$OutFile = Join-Path $TestSandbox "stdout.txt"
$ErrFile = Join-Path $TestSandbox "stderr.txt"
$UsageStub = Join-Path $StubDir "usage_stub.ps1"
$MailStub = Join-Path $StubDir "mail_stub.ps1"
$HttpStub = Join-Path $StubDir "http_stub.ps1"
$script:OriginalPath = $env:PATH

$script:PassedCount = 0
$script:FailedCount = 0
$script:LastStdout = ""
$script:LastStderr = ""
$script:LastRunExitCode = 0

# Creates the sandbox, the stubs and a clean environment
function Enter-TestEnvironment {
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

    # HTTP client stub. It records its arguments, one per line, and its
    # stdin, so the test can assert on the composed request without touching
    # the network. The script declares no parameter block on purpose: the
    # client is invoked with curl-style options such as --silent, which a
    # parameter binder would reject.
    @'
$lines = @()
$lines += "ARGC:$($args.Count)"
foreach ($item in $args) {
    $lines += "ARG:$item"
}
$lines += "STDIN-BEGIN"
$lines += ($input | Out-String)
$lines += "STDIN-END"
Add-Content -LiteralPath $env:DISK_MONITOR_STUB_HTTP_CAPTURE -Value $lines

if ($env:DISK_MONITOR_STUB_HTTP_FAIL -eq "1") {
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath $HttpStub -Encoding utf8

    # A client shim on PATH, so the default resolution can be observed. The
    # shim is never invoked by the suite: only the resolution is observed.
    if ($IsWindows) {
        Set-Content -LiteralPath (Join-Path $StubDir "curl.cmd") -Value @(
            "@echo off"
            "exit /b 0"
        )
    } else {
        $pathShim = Join-Path $StubDir "curl"
        Set-Content -LiteralPath $pathShim -Value @(
            "#!/bin/sh"
            "exit 0"
        )
        & chmod +x $pathShim
    }

    Set-Content -LiteralPath $CaptureFile -Value "" -NoNewline
    Set-Content -LiteralPath $HttpCaptureFile -Value "" -NoNewline

    $env:DISK_MONITOR_STUB_CAPTURE = $CaptureFile
    $env:DISK_MONITOR_STUB_HTTP_CAPTURE = $HttpCaptureFile
    $env:DISK_MONITOR_STUB_DF_USAGE = "49"
    $env:DISK_MONITOR_STUB_DF_FAIL = "0"
    $env:DISK_MONITOR_STUB_MAIL_FAIL = "0"
    $env:DISK_MONITOR_STUB_HTTP_FAIL = "0"
    $env:DISK_MONITOR_USAGE_COMMAND = $UsageStub
    Remove-Item Env:DISK_MONITOR_USAGE_OVERRIDE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TO -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_MAIL_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_THRESHOLD -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_PARTITION -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_NOTIFY -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_LOG_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_URL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_BODY_TEMPLATE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_HEADER -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TIMEOUT -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_HTTP_COMMAND -ErrorAction SilentlyContinue
    $env:PATH = $script:OriginalPath
}

function Exit-TestEnvironment {
    Remove-Item -LiteralPath $TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_CAPTURE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_HTTP_CAPTURE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_DF_USAGE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_DF_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_MAIL_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_STUB_HTTP_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_USAGE_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_USAGE_OVERRIDE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TO -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_MAIL_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_THRESHOLD -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_PARTITION -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_NOTIFY -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_LOG_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_URL -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_BODY_TEMPLATE -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_HEADER -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_TIMEOUT -ErrorAction SilentlyContinue
    Remove-Item Env:DISK_MONITOR_HTTP_COMMAND -ErrorAction SilentlyContinue
    $env:PATH = $script:OriginalPath
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

    $script:LastRunExitCode = $code
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
function Assert-Absent {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()][string]$Haystack = "",
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Haystack) {
        $Haystack = ""
    }

    if (-not $Haystack.Contains($Needle)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected NOT to contain: '$Needle')"
        $script:FailedCount++
    }
}

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

# Asserts that the HTTP client was never invoked
function Assert-HttpCaptureEmpty {
    param([Parameter(Mandatory = $true)][string]$TestName)

    $capture = ""
    if (Test-Path -LiteralPath $HttpCaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $HttpCaptureFile
        if ($null -ne $raw) {
            $capture = $raw
        }
    }

    if ([string]::IsNullOrWhiteSpace($capture)) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected no HTTP activity, got: '$capture')"
        $script:FailedCount++
    }
}

# Reads the captured HTTP request
function Get-HttpCapture {
    $capture = ""
    if (Test-Path -LiteralPath $HttpCaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $HttpCaptureFile
        if ($null -ne $raw) {
            $capture = $raw
        }
    }
    return $capture
}

# Asserts that the text matches a regular expression
function Assert-Regex {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyString()][string]$Haystack = "",
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$TestName
    )

    if ($null -eq $Haystack) {
        $Haystack = ""
    }

    if ($Haystack -match $Pattern) {
        Write-Host "$([char]27)[0;32m[PASS]$([char]27)[0m $TestName"
        $script:PassedCount++
    } else {
        Write-Host "$([char]27)[0;31m[FAIL]$([char]27)[0m $TestName (Expected to match: '$Pattern')"
        $script:FailedCount++
    }
}

# Test 1: Help exits with code 0 and documents the flags
function Test-HelpMenu {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Help")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 1a: Help menu exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "Disk Usage Monitor" -TestName "Test 1b: Help menu names the tool"
    Assert-Match -Haystack $script:LastStdout -Needle "-Threshold" -TestName "Test 1c: Help menu documents -Threshold"
    Assert-Match -Haystack $script:LastStdout -Needle "-DryRun" -TestName "Test 1d: Help menu documents -DryRun"
    Assert-Match -Haystack $script:LastStdout -Needle "-Notify" -TestName "Test 1e: Help menu documents -Notify"
    Exit-TestEnvironment
}

# Test 2: An unknown parameter is a configuration error
function Test-UnknownParameter {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-ThisFlagDoesNotExist")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 2: Unknown parameter exits with code 1"
    Exit-TestEnvironment
}

# Test 3: The threshold is validated as an integer between 1 and 100
function Test-ThresholdValidation {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Threshold", "0")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 3a: Threshold 0 exits with code 1"
    Invoke-Monitor -Arguments @("-Threshold", "101")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 3b: Threshold 101 exits with code 1"
    Invoke-Monitor -Arguments @("-Threshold", "abc")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 3c: Non-numeric threshold exits with code 1"
    Exit-TestEnvironment
}

# Test 4: The notify backend is validated against the supported set
function Test-NotifyValidation {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "carrier-pigeon", "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 4: Unsupported notify backend exits with code 1"
    Exit-TestEnvironment
}

# Test 5: A partition that does not exist is a configuration error
function Test-MissingPartition {
    Enter-TestEnvironment
    $missing = Join-Path $TestSandbox "does-not-exist"
    Invoke-Monitor -Arguments @("-Partition", $missing, "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 5: Missing partition exits with code 1"
    Exit-TestEnvironment
}

# Test 6: A missing recipient is a configuration error when mail is enabled
function Test-MissingRecipient {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "mail")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 6a: Missing recipient exits with code 1"
    Assert-Match -Haystack $script:LastStderr -Needle "DISK_MONITOR_TO" -TestName "Test 6b: Missing recipient names the environment variable"
    Exit-TestEnvironment
}

# Test 7: An unresolvable mail agent is a configuration error
function Test-MissingMailAgent {
    Enter-TestEnvironment
    $missing = Join-Path $TestSandbox "not-a-real-agent"
    Invoke-Monitor -Arguments @("-MailCommand", $missing, "-To", "ops@example.com")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 7: Unresolvable mail agent exits with code 1"
    Assert-Match -Haystack $script:LastStderr -Needle "mail" -TestName "Test 7b: Unresolvable mail agent explains itself"
    Exit-TestEnvironment
}

# Test 8: Usage below the threshold exits 0 and sends nothing
function Test-BelowThreshold {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 8a: Usage below the threshold exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "42%" -TestName "Test 8b: The report shows the measured usage"
    Assert-CaptureEmpty -TestName "Test 8c: No alert is sent below the threshold"
    Exit-TestEnvironment
}

# Test 9: Usage above the threshold sends the alert and still exits 0
function Test-AboveThreshold {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "91"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 9a: Usage above the threshold exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 9b: The report warns about the breach"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops@example.com" -TestName "Test 9c: The alert carries the recipient"
    Assert-Match -Haystack $capture -Needle "91%" -TestName "Test 9d: The alert body carries the measured usage"
    Assert-Match -Haystack $capture -Needle "Disk Alert" -TestName "Test 9e: The alert carries the expected subject"
    Exit-TestEnvironment
}

# Test 10: Usage exactly at the threshold does not alert
function Test-ThresholdBoundary {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "80"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 10a: Usage equal to the threshold exits with code 0"
    Assert-CaptureEmpty -TestName "Test 10b: Usage equal to the threshold does not alert"
    Exit-TestEnvironment
}

# Test 11: DryRun reports the alert without handing it to the mail agent
function Test-DryRun {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-DryRun", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 11a: DryRun exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "DRY RUN" -TestName "Test 11b: DryRun announces itself"
    Assert-CaptureEmpty -TestName "Test 11c: DryRun hands nothing to the mail agent"
    Exit-TestEnvironment
}

# Test 12: -Notify none never touches the mail agent
function Test-NotifyNone {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 12a: -Notify none exits with code 0"
    Assert-CaptureEmpty -TestName "Test 12b: -Notify none hands nothing to the mail agent"
    Exit-TestEnvironment
}

# Test 13: -Notify none needs no recipient
function Test-NotifyNoneNeedsNoRecipient {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 13: -Notify none requires no recipient"
    Exit-TestEnvironment
}

# Test 14: The audit log is written
function Test-AuditLog {
    Enter-TestEnvironment
    $auditFile = Join-Path $TestSandbox "logs/audit.log"
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub, "-LogFile", $auditFile)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 14a: Run with an audit log exits with code 0"
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $auditFile) -TestName "Test 14b: The audit log file is created"

    $audit = ""
    if (Test-Path -LiteralPath $auditFile) {
        $raw = Get-Content -Raw -LiteralPath $auditFile
        if ($null -ne $raw) { $audit = $raw }
    }
    Assert-Match -Haystack $audit -Needle "95" -TestName "Test 14c: The audit log records the measured usage"
    Exit-TestEnvironment
}

# Test 15: A disk usage read failure is a partial failure
function Test-UsageReadFailure {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_FAIL = "1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 2 -Actual $script:LastRunExitCode -TestName "Test 15: An unreadable disk usage exits with code 2"
    Exit-TestEnvironment
}

# Test 16: A failed alert hand-off is a partial failure
function Test-AlertHandoffFailure {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_STUB_MAIL_FAIL = "1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 2 -Actual $script:LastRunExitCode -TestName "Test 16: A failed alert hand-off exits with code 2"
    Exit-TestEnvironment
}

# Test 17: The recipient falls back to the environment variable
function Test-RecipientFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_TO = "oncall@example.com"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 17a: The environment recipient is accepted"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "oncall@example.com" -TestName "Test 17b: The environment recipient is used"
    Exit-TestEnvironment
}

# Test 18: The mail command can be overridden by the environment
function Test-MailCommandFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_MAIL_COMMAND = $MailStub
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 18: The mail command can come from the environment"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops@example.com" -TestName "Test 18b: The overridden mail command is used"
    Exit-TestEnvironment
}

# Test 19: The verbose flag is accepted
function Test-Verbose {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Verbose", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 19a: The verbose flag is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "Partition" -TestName "Test 19b: The report names the watched partition"
    Exit-TestEnvironment
}

# Test 20: A forced usage value is honoured and labelled as such
function Test-UsageOverride {
    Enter-TestEnvironment
    $env:DISK_MONITOR_USAGE_OVERRIDE = "91"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 20a: A forced usage value is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "91%" -TestName "Test 20b: The forced value is reported"
    Assert-Match -Haystack $script:LastStdout -Needle "overridden" -TestName "Test 20c: The report labels the value as overridden"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "91%" -TestName "Test 20d: The alert carries the forced value"
    Exit-TestEnvironment
}

# Test 21: An invalid forced usage value is a configuration error
function Test-InvalidUsageOverride {
    Enter-TestEnvironment
    $env:DISK_MONITOR_USAGE_OVERRIDE = "abc"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 21: An invalid usage override exits with code 1"
    Exit-TestEnvironment
}

# Test 22: The measurement command can be replaced
function Test-UsageCommandOverride {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "77"
    Invoke-Monitor -Arguments @("-Threshold", "70", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 22a: A replaced measurement command is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle "77%" -TestName "Test 22b: The replaced command supplies the usage"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "77%" -TestName "Test 22c: The alert carries the replaced value"
    Exit-TestEnvironment
}

# Test 23: An unresolvable measurement command is a configuration error
function Test-MissingUsageCommand {
    Enter-TestEnvironment
    $env:DISK_MONITOR_USAGE_COMMAND = Join-Path $TestSandbox "not-a-real-command"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 23: An unresolvable measurement command exits with code 1"
    Exit-TestEnvironment
}

# Test 24: The default measurement source works against the real host
function Test-DefaultMeasurementSource {
    Enter-TestEnvironment
    Remove-Item Env:DISK_MONITOR_USAGE_COMMAND -ErrorAction SilentlyContinue
    Invoke-Monitor -Arguments @("-Threshold", "100", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 24a: The default measurement source exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "measured" -TestName "Test 24b: The default source is labelled as measured"
    Exit-TestEnvironment
}

# Test 25: A mount point containing spaces does not shift the capacity column
function Test-MountPointWithSpace {
    Enter-TestEnvironment
    $env:DISK_MONITOR_USAGE_COMMAND = Join-Path $StubDir "usage_spaced_stub.ps1"
    Invoke-Monitor -Arguments @("-Threshold", "60", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 25a: A spaced mount point exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "63%" -TestName "Test 25b: The capacity is read from its fixed position"
    Exit-TestEnvironment
}

# Test 26: A configuration file supplies the partition and the threshold.
function Test-ConfigFileValue {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "# a comment line"
        "partition = $TestSandbox"
        "threshold = 60"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 26a: A configuration file is accepted"
    Assert-Match -Haystack $script:LastStdout -Needle $TestSandbox -TestName "Test 26b: The configured partition is used"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 26c: The configured threshold is used"
    Exit-TestEnvironment
}

# Test 27: A command line flag overrides the configuration file.
function Test-ConfigPrecedenceFlag {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value "threshold = 60"
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "90", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 27a: The run succeeds"
    Assert-Absent -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 27b: The flag overrides the configured threshold"
    Exit-TestEnvironment
}

# Test 28: An environment variable overrides the configuration file.
function Test-ConfigPrecedenceEnvironment {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value "threshold = 60"
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    $env:DISK_MONITOR_THRESHOLD = "90"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 28a: The run succeeds"
    Assert-Absent -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 28b: The environment overrides the configured threshold"
    Exit-TestEnvironment
}

# Test 29: A command line flag overrides the environment variable.
function Test-ConfigPrecedenceFlagOverEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    $env:DISK_MONITOR_THRESHOLD = "90"
    Invoke-Monitor -Arguments @("-Threshold", "20", "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 29a: The run succeeds"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 29b: The flag overrides the environment"
    Exit-TestEnvironment
}

# Test 30: The configuration file supplies the recipient.
function Test-ConfigFileRecipient {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "to = oncall@example.com"
        "threshold = 60"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 30a: The run succeeds"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "oncall@example.com" -TestName "Test 30b: The configured recipient is used"
    Exit-TestEnvironment
}

# Test 31: A configuration file that does not exist is a configuration error.
function Test-ConfigFileMissing {
    Enter-TestEnvironment
    Invoke-Monitor -Arguments @("-Config", (Join-Path $TestSandbox "no-such-file.conf"), "-Notify", "none")
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 31: A missing configuration file exits with code 1"
    Exit-TestEnvironment
}

# Test 32: A malformed line is reported and ignored; the rest still applies.
function Test-ConfigFileMalformedLine {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "this line has no separator"
        "threshold = 60"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 32a: The run succeeds despite a malformed line"
    Assert-Match -Haystack $script:LastStderr -Needle "malformed" -TestName "Test 32b: The malformed line is reported"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 32c: The valid lines are still applied"
    Exit-TestEnvironment
}

# Test 33: An unknown key is reported and ignored.
function Test-ConfigFileUnknownKey {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "threshold = 60"
        "not_a_real_key = value"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 33a: The run succeeds despite an unknown key"
    Assert-Match -Haystack $script:LastStderr -Needle "not_a_real_key" -TestName "Test 33b: The unknown key is reported"
    Exit-TestEnvironment
}

# Test 34: A quoted value keeps its spaces.
function Test-ConfigFileQuotedValue {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        'to = "ops team@example.com"'
        "threshold = 60"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 34a: The run succeeds"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops team@example.com" -TestName "Test 34b: The quoted value keeps its spaces"
    Exit-TestEnvironment
}

# Test 35: The configuration file path can come from the environment.
function Test-ConfigFileFromEnvironment {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value "threshold = 60"
    $env:DISK_MONITOR_STUB_DF_USAGE = "70"
    $env:DISK_MONITOR_CONFIG = $configFile
    Invoke-Monitor -Arguments @("-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 35a: The run succeeds"
    Assert-Match -Haystack $script:LastStdout -Needle "WARNING" -TestName "Test 35b: The configured threshold is used"
    Exit-TestEnvironment
}

# Test 36: A well formed configuration file is accepted.
function Test-ConfigFileWellFormed {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "partition = $TestSandbox"
        "threshold = 60"
    )
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Notify", "none")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 36a: A well formed configuration file is accepted"
    Exit-TestEnvironment
}

# Test 37: The HTTP transport posts the alert to the endpoint.
function Test-HttpTransportSendsTheRequest {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 37a: The HTTP transport exits with code 0"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "https://ntfy.sh/disk-alerts" -TestName "Test 37b: The request carries the endpoint"
    Assert-Match -Haystack $capture -Needle "ARG:--request" -TestName "Test 37c: The request carries the method option"
    Assert-Match -Haystack $capture -Needle "ARG:POST" -TestName "Test 37d: The default method is POST"
    Assert-Match -Haystack $capture -Needle "ARG:--max-time" -TestName "Test 37e: The request carries the timeout option"
    Assert-Match -Haystack $capture -Needle "ARG:10" -TestName "Test 37f: The default timeout is ten seconds"
    Assert-Match -Haystack $capture -Needle "95%" -TestName "Test 37g: The request body carries the measured usage"
    Exit-TestEnvironment
}

# Test 38: The body template placeholders are substituted.
function Test-HttpBodyTemplatePlaceholder {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @(
        "-Partition", $TestSandbox,
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-BodyTemplate", '{host}|{partition}|{usage}|{threshold}|{recipient}|{timestamp}|{subject}',
        "-HttpCommand", $HttpStub
    )
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 38a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "|" -TestName "Test 38b: The template is rendered"
    Assert-Match -Haystack $capture -Needle "|$TestSandbox|" -TestName "Test 38c: The partition placeholder is substituted"
    Assert-Match -Haystack $capture -Needle "|95%|80%|" -TestName "Test 38d: The usage and threshold placeholders are substituted"
    Assert-Match -Haystack $capture -Needle "https://ntfy.sh/disk-alerts|" -TestName "Test 38e: The recipient placeholder is the endpoint"
    Assert-Match -Haystack $capture -Needle "Disk Alert" -TestName "Test 38f: The subject placeholder is substituted"
    Assert-Regex -Haystack $capture -Pattern '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z' -TestName "Test 38g: The timestamp placeholder is substituted"
    Exit-TestEnvironment
}

# Test 39: The default body template is the plain-text message.
function Test-HttpDefaultBodyTemplate {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Partition", $TestSandbox, "-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 39a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "Disk usage on" -TestName "Test 39b: The default body is the plain-text message"
    Assert-Match -Haystack $capture -Needle "Partition : $TestSandbox" -TestName "Test 39c: The default body carries the partition"
    Assert-Match -Haystack $capture -Needle "Threshold: 80%" -TestName "Test 39d: The default body carries the threshold"
    Exit-TestEnvironment
}

# Test 40: A missing endpoint is a configuration error.
function Test-HttpMissingEndpoint {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 40a: A missing endpoint exits with code 1"
    Assert-Match -Haystack $script:LastStderr -Needle "DISK_MONITOR_URL" -TestName "Test 40b: The missing endpoint names the environment variable"
    Exit-TestEnvironment
}

# Test 41: An unresolvable HTTP client is a configuration error.
function Test-HttpMissingClient {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @(
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-HttpCommand", (Join-Path $TestSandbox "not-a-real-client")
    )
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 41: An unresolvable HTTP client exits with code 1"
    Exit-TestEnvironment
}

# Test 42: A failed request is a partial failure.
function Test-HttpRequestFailure {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_STUB_HTTP_FAIL = "1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 2 -Actual $script:LastRunExitCode -TestName "Test 42: A failed HTTP request exits with code 2"
    Exit-TestEnvironment
}

# Test 43: A header value is never reported and never logged.
function Test-HttpHeaderValueIsNeverReported {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $auditFile = Join-Path $TestSandbox "logs/audit.log"
    Invoke-Monitor -Arguments @(
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-Header", "Authorization: Bearer super-secret-token",
        "-HttpCommand", $HttpStub,
        "-LogFile", $auditFile
    )
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 43a: The run succeeds"

    $audit = ""
    if (Test-Path -LiteralPath $auditFile) {
        $raw = Get-Content -Raw -LiteralPath $auditFile
        if ($null -ne $raw) { $audit = $raw }
    }
    Assert-Absent -Haystack $script:LastStdout -Needle "super-secret-token" -TestName "Test 43b: The header value is not printed"
    Assert-Absent -Haystack $script:LastStderr -Needle "super-secret-token" -TestName "Test 43c: The header value is not reported as an error"
    Assert-Absent -Haystack $audit -Needle "super-secret-token" -TestName "Test 43d: The header value is not written to the audit log"
    Exit-TestEnvironment
}

# Test 44: The endpoint falls back to the environment variable.
function Test-HttpEndpointFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_URL = "https://ntfy.sh/from-env"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 44a: The run succeeds"
    Assert-Match -Haystack (Get-HttpCapture) -Needle "https://ntfy.sh/from-env" -TestName "Test 44b: The environment endpoint is used"
    Exit-TestEnvironment
}

# Test 45: The body template falls back to the environment variable.
function Test-HttpBodyTemplateFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_BODY_TEMPLATE = '{"text":"{body}"}'
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 45a: The run succeeds"
    Assert-Match -Haystack (Get-HttpCapture) -Needle '{"text":"Disk usage on' -TestName "Test 45b: The environment body template is used"
    Exit-TestEnvironment
}

# Test 46: The timeout falls back to the environment variable.
function Test-HttpTimeoutFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_TIMEOUT = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 46a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:--max-time" -TestName "Test 46b: The request carries the timeout option"
    Assert-Match -Haystack $capture -Needle "ARG:42" -TestName "Test 46c: The environment timeout is used"
    Exit-TestEnvironment
}

# Test 47: The method and the endpoint come from the configuration file.
function Test-HttpValuesFromConfigFile {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "method = PUT"
        "url = https://ntfy.sh/from-config"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "80", "-Notify", "http", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 47a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:PUT" -TestName "Test 47b: The configured method is used"
    Assert-Match -Haystack $capture -Needle "https://ntfy.sh/from-config" -TestName "Test 47c: The configured endpoint is used"
    Exit-TestEnvironment
}

# Test 48: The flag wins over the environment and the configuration file.
function Test-HttpPrecedenceFlag {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value "url = https://ntfy.sh/from-config"
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_URL = "https://ntfy.sh/from-env"
    Invoke-Monitor -Arguments @(
        "-Config", $configFile,
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/from-flag",
        "-HttpCommand", $HttpStub
    )
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 48a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "https://ntfy.sh/from-flag" -TestName "Test 48b: The flag wins"
    Assert-Absent -Haystack $capture -Needle "https://ntfy.sh/from-env" -TestName "Test 48c: The environment is not used"
    Assert-Absent -Haystack $capture -Needle "https://ntfy.sh/from-config" -TestName "Test 48d: The configuration file is not used"
    Exit-TestEnvironment
}

# Test 49: The HTTP client can be replaced by the flag and by the environment.
function Test-HttpClientCanBeReplaced {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 49a: The run succeeds with a replaced client"
    Assert-Match -Haystack (Get-HttpCapture) -Needle "https://ntfy.sh/disk-alerts" -TestName "Test 49b: The replaced client carries the request"

    Set-Content -LiteralPath $HttpCaptureFile -Value "" -NoNewline
    $env:DISK_MONITOR_HTTP_COMMAND = $HttpStub
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 49c: The run succeeds with an environment client"
    Assert-Match -Haystack (Get-HttpCapture) -Needle "https://ntfy.sh/disk-alerts" -TestName "Test 49d: The environment client carries the request"
    Exit-TestEnvironment
}

# Test 50: The default client resolves to a real application on the host.
function Test-HttpDefaultClientIsAnApplication {
    Enter-TestEnvironment
    # The usage is below the threshold, so no request is made and the client
    # is never invoked: only the resolution is observed.
    $env:DISK_MONITOR_STUB_DF_USAGE = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 50a: The default client resolves"
    Assert-Match -Haystack $script:LastStdout -Needle "HTTP Client" -TestName "Test 50b: The report names the resolved client"

    $clientLine = @($script:LastStdout -split "`r?`n" | Where-Object { $_ -like "*HTTP Client*" })[0]
    $clientPath = ($clientLine -split ":", 2)[1].Trim()
    Assert-Equal -Expected $true -Actual (Test-Path -LiteralPath $clientPath -PathType Leaf) -TestName "Test 50c: The resolved client is a file on disk, not an alias"
    Exit-TestEnvironment
}

# Test 51: The client on PATH wins over the system client.
function Test-HttpPathClientIsPreferred {
    Enter-TestEnvironment
    $env:PATH = $StubDir + [System.IO.Path]::PathSeparator + $script:OriginalPath
    $env:DISK_MONITOR_STUB_DF_USAGE = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts")
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 51a: The run succeeds with the client on PATH"
    Assert-Match -Haystack $script:LastStdout -Needle $StubDir -TestName "Test 51b: The client on PATH is preferred over the system client"
    Exit-TestEnvironment
}

# Test 52: A malformed timeout is a configuration error.
function Test-HttpInvalidTimeout {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_TIMEOUT = "abc"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 52a: A malformed timeout exits with code 1"

    $env:DISK_MONITOR_TIMEOUT = "0"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 52b: A zero timeout exits with code 1"
    Exit-TestEnvironment
}

# Test 53: A malformed method is a configuration error.
function Test-HttpInvalidMethod {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value 'method = "BAD METHOD"'
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 53: A malformed method exits with code 1"
    Exit-TestEnvironment
}

# Test 54: A malformed header is a configuration error and its value is not reported.
function Test-HttpInvalidHeader {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-Header", "not-a-header-value", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 54a: A malformed header exits with code 1"
    Assert-Absent -Haystack $script:LastStderr -Needle "not-a-header-value" -TestName "Test 54b: The malformed header value is not reported"
    Exit-TestEnvironment
}

# Test 55: A malformed endpoint is a configuration error.
function Test-HttpInvalidEndpoint {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "not-a-url", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 1 -Actual $script:LastRunExitCode -TestName "Test 55: A malformed endpoint exits with code 1"
    Exit-TestEnvironment
}

# Test 56: A header reaches the request.
function Test-HttpHeaderReachesTheRequest {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @(
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-Header", "X-Title: Disk",
        "-HttpCommand", $HttpStub
    )
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 56a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:--header" -TestName "Test 56b: The request carries the header option"
    Assert-Match -Haystack $capture -Needle "ARG:X-Title: Disk" -TestName "Test 56c: The request carries the header value"
    Exit-TestEnvironment
}

# Test 57: A JSON body template keeps its braces.
function Test-HttpJsonBodyTemplate {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @(
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-BodyTemplate", '{"text":"{body}"}',
        "-HttpCommand", $HttpStub
    )
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 57a: The run succeeds"
    Assert-Match -Haystack (Get-HttpCapture) -Needle '{"text":"Disk usage on' -TestName "Test 57b: The JSON template keeps its braces"
    Exit-TestEnvironment
}

# Test 58: Several headers come from the configuration file.
function Test-HttpHeadersFromConfigFile {
    Enter-TestEnvironment
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "header = X-One: 1"
        "header = X-Two: 2"
        "url = https://ntfy.sh/disk-alerts"
    )
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "80", "-Notify", "http", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 58a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:X-One: 1" -TestName "Test 58b: The first configured header is used"
    Assert-Match -Haystack $capture -Needle "ARG:X-Two: 2" -TestName "Test 58c: The second configured header is used"
    Exit-TestEnvironment
}

# Test 59: The report names the endpoint and never a header value.
function Test-HttpReportShowsTheEndpointOnly {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @(
        "-Threshold", "80",
        "-Notify", "http",
        "-Url", "https://ntfy.sh/disk-alerts",
        "-Header", "Authorization: Bearer secret-value",
        "-HttpCommand", $HttpStub
    )
    Assert-Match -Haystack $script:LastStdout -Needle "https://ntfy.sh/disk-alerts" -TestName "Test 59a: The report names the endpoint"
    Assert-Absent -Haystack $script:LastStdout -Needle "secret-value" -TestName "Test 59b: The report never names a header value"
    Exit-TestEnvironment
}

# Test 60: Usage below the threshold sends no request.
function Test-HttpBelowThresholdSendsNothing {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "42"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 60a: Usage below the threshold exits with code 0"
    Assert-HttpCaptureEmpty -TestName "Test 60b: No request is sent below the threshold"
    Exit-TestEnvironment
}

# Test 61: Dry-run reports the alert and sends no request.
function Test-HttpDryRunSendsNothing {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-DryRun", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 61a: Dry-run exits with code 0"
    Assert-Match -Haystack $script:LastStdout -Needle "DRY RUN" -TestName "Test 61b: Dry-run announces itself"
    Assert-HttpCaptureEmpty -TestName "Test 61c: Dry-run sends no request"
    Exit-TestEnvironment
}

# Test 62: The mail transport keeps working next to the HTTP transport.
function Test-MailTransport {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "mail", "-To", "ops@example.com", "-MailCommand", $MailStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 62a: The mail transport exits with code 0"

    $capture = ""
    if (Test-Path -LiteralPath $CaptureFile) {
        $raw = Get-Content -Raw -LiteralPath $CaptureFile
        if ($null -ne $raw) { $capture = $raw }
    }
    Assert-Match -Haystack $capture -Needle "ops@example.com" -TestName "Test 62b: The mail transport still delivers"
    Assert-HttpCaptureEmpty -TestName "Test 62c: The mail transport does not touch the HTTP client"
    Exit-TestEnvironment
}

# Test 63: One header value may carry several headers, one per line.
function Test-HttpMultiHeaderValue {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_HEADER = "X-One: 1`nX-Two: 2"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 63a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:X-One: 1" -TestName "Test 63b: The first header of the value is used"
    Assert-Match -Haystack $capture -Needle "ARG:X-Two: 2" -TestName "Test 63c: The second header of the value is used"
    Exit-TestEnvironment
}

# Test 64: The header comes from the environment variable.
function Test-HttpHeaderFromEnvironment {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_HEADER = "X-From-Env: 1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 64a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "ARG:X-From-Env: 1" -TestName "Test 64b: The environment header is used"
    Exit-TestEnvironment
}

# Test 65: A header flag that was supplied wins over the environment, even
# when its value is empty.
function Test-HttpEmptyHeaderFlag {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $env:DISK_MONITOR_HEADER = "X-From-Env: 1"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-Header", "", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 65a: The run succeeds"

    $capture = Get-HttpCapture
    Assert-Absent -Haystack $capture -Needle "ARG:X-From-Env: 1" -TestName "Test 65b: The environment header is not used"
    Exit-TestEnvironment
}

# Test 66: A client that exists but cannot be run is a partial failure.
function Test-HttpNonRunnableClient {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $unusable = Join-Path $TestSandbox "not-executable.txt"
    Set-Content -LiteralPath $unusable -Value "not a client"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $unusable)
    Assert-Equal -Expected 2 -Actual $script:LastRunExitCode -TestName "Test 66: A client that cannot be run exits with code 2"
    Exit-TestEnvironment
}

# Test 67: A header value from the environment never reaches an output.
function Test-HttpEnvironmentHeaderIsNeverReported {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $auditFile = Join-Path $TestSandbox "logs/audit.log"
    $env:DISK_MONITOR_HEADER = "Authorization: Bearer env-secret-token"
    Invoke-Monitor -Arguments @("-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub, "-LogFile", $auditFile)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 67a: The run succeeds"

    $audit = ""
    if (Test-Path -LiteralPath $auditFile) {
        $raw = Get-Content -Raw -LiteralPath $auditFile
        if ($null -ne $raw) { $audit = $raw }
    }
    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "Authorization: Bearer env-secret-token" -TestName "Test 67b: The header does reach the request"
    Assert-Absent -Haystack $script:LastStdout -Needle "env-secret-token" -TestName "Test 67c: The header value is not printed"
    Assert-Absent -Haystack $script:LastStderr -Needle "env-secret-token" -TestName "Test 67d: The header value is not reported as an error"
    Assert-Absent -Haystack $audit -Needle "env-secret-token" -TestName "Test 67e: The header value is not written to the audit log"
    Exit-TestEnvironment
}

# Test 68: A header value from the configuration file never reaches an output.
function Test-HttpConfigHeaderIsNeverReported {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $auditFile = Join-Path $TestSandbox "logs/audit.log"
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "header = Authorization: Bearer config-secret-token"
        "url = https://ntfy.sh/disk-alerts"
    )
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "80", "-Notify", "http", "-HttpCommand", $HttpStub, "-LogFile", $auditFile)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 68a: The run succeeds"

    $audit = ""
    if (Test-Path -LiteralPath $auditFile) {
        $raw = Get-Content -Raw -LiteralPath $auditFile
        if ($null -ne $raw) { $audit = $raw }
    }
    $capture = Get-HttpCapture
    Assert-Match -Haystack $capture -Needle "Authorization: Bearer config-secret-token" -TestName "Test 68b: The header does reach the request"
    Assert-Absent -Haystack $script:LastStdout -Needle "config-secret-token" -TestName "Test 68c: The header value is not printed"
    Assert-Absent -Haystack $script:LastStderr -Needle "config-secret-token" -TestName "Test 68d: The header value is not reported as an error"
    Assert-Absent -Haystack $audit -Needle "config-secret-token" -TestName "Test 68e: The header value is not written to the audit log"
    Exit-TestEnvironment
}

# Test 69: A malformed configuration line is named, never shown, because a
# line pasted into the file by mistake may hold a token.
function Test-HttpMalformedConfigLineIsNotEchoed {
    Enter-TestEnvironment
    $env:DISK_MONITOR_STUB_DF_USAGE = "95"
    $configFile = Join-Path $TestSandbox "diskmonitor.conf"
    Set-Content -LiteralPath $configFile -Value @(
        "Authorization: Bearer pasted-secret-token"
        "threshold = 60"
    )
    Invoke-Monitor -Arguments @("-Config", $configFile, "-Threshold", "80", "-Notify", "http", "-Url", "https://ntfy.sh/disk-alerts", "-HttpCommand", $HttpStub)
    Assert-Equal -Expected 0 -Actual $script:LastRunExitCode -TestName "Test 69a: The run succeeds"

    Assert-Match -Haystack $script:LastStderr -Needle "malformed" -TestName "Test 69b: The malformed line is reported"
    Assert-Absent -Haystack $script:LastStderr -Needle "pasted-secret-token" -TestName "Test 69c: The malformed line is not echoed"
    Exit-TestEnvironment
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
Test-ConfigFileValue
Test-ConfigPrecedenceFlag
Test-ConfigPrecedenceEnvironment
Test-ConfigPrecedenceFlagOverEnvironment
Test-ConfigFileRecipient
Test-ConfigFileMissing
Test-ConfigFileMalformedLine
Test-ConfigFileUnknownKey
Test-ConfigFileQuotedValue
Test-ConfigFileFromEnvironment
Test-ConfigFileWellFormed
Test-HttpTransportSendsTheRequest
Test-HttpBodyTemplatePlaceholder
Test-HttpDefaultBodyTemplate
Test-HttpMissingEndpoint
Test-HttpMissingClient
Test-HttpRequestFailure
Test-HttpHeaderValueIsNeverReported
Test-HttpEndpointFromEnvironment
Test-HttpBodyTemplateFromEnvironment
Test-HttpTimeoutFromEnvironment
Test-HttpValuesFromConfigFile
Test-HttpPrecedenceFlag
Test-HttpClientCanBeReplaced
Test-HttpDefaultClientIsAnApplication
Test-HttpPathClientIsPreferred
Test-HttpInvalidTimeout
Test-HttpInvalidMethod
Test-HttpInvalidHeader
Test-HttpInvalidEndpoint
Test-HttpHeaderReachesTheRequest
Test-HttpJsonBodyTemplate
Test-HttpHeadersFromConfigFile
Test-HttpReportShowsTheEndpointOnly
Test-HttpBelowThresholdSendsNothing
Test-HttpDryRunSendsNothing
Test-MailTransport
Test-HttpMultiHeaderValue
Test-HttpHeaderFromEnvironment
Test-HttpEmptyHeaderFlag
Test-HttpNonRunnableClient
Test-HttpEnvironmentHeaderIsNeverReported
Test-HttpConfigHeaderIsNeverReported
Test-HttpMalformedConfigLineIsNotEchoed

Write-Host "============================================================"
Write-Host "Tests Summary: $([char]27)[0;32m$script:PassedCount Passed$([char]27)[0m, $([char]27)[0;31m$script:FailedCount Failed$([char]27)[0m"
Write-Host "============================================================"

if ($script:FailedCount -gt 0) {
    exit 1
}
exit 0
