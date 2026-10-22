#Requires -Version 7.0
<#
.SYNOPSIS
    Disk usage monitor with threshold alerting.

.DESCRIPTION
    Measures the usage of a mounted filesystem and hands an alert to the
    configured transport when the usage crosses a threshold. The transport is
    the host mail agent or an HTTP endpoint. The HTTP request is sent by an
    external client, so the module opens no socket of its own and holds no
    credential: a credential travels in a header the caller supplies.

    The measurement source is the POSIX df output on Linux and macOS, and the
    native volume API on Windows. Both report the capacity as a percentage.

    The threshold is a string and not a number, because the configuration file
    and the environment may hold a value that is not a number, and the tool
    has to report it instead of dropping it. The value of every source is
    judged by the validation, which is what the doctor reports, and the
    binder holds no range and no set, because a value that the binder
    refuses is a value the doctor never sees.

.PARAMETER Partition
    Mount point to watch. Defaults to the root of the current drive on Windows
    and to "/" elsewhere.

.PARAMETER Threshold
    Alert when the usage is strictly greater than this percentage (Default: 80).

.PARAMETER DryRun
    Report the alert without handing it to the mail agent.

.PARAMETER Notify
    Notification backend, either "none", "mail" or "http" (Default: mail).

.PARAMETER To
    Alert recipient. Defaults to the DISK_MONITOR_TO environment variable.

.PARAMETER MailCommand
    Mail agent to hand the alert to. Defaults to the
    DISK_MONITOR_MAIL_COMMAND environment variable.

.PARAMETER LogFile
    Path to append ISO-8601 audit records.

.PARAMETER Url
    HTTP endpoint to post the alert to. Defaults to the DISK_MONITOR_URL
    environment variable.

.PARAMETER BodyTemplate
    HTTP request body. The placeholders are {subject}, {body}, {partition},
    {usage}, {threshold}, {recipient}, {host} and {timestamp}. Defaults to the
    plain-text message.

.PARAMETER Header
    Extra HTTP header, in the form 'Name: value'. One value may carry
    several headers, one per line.

.PARAMETER Timeout
    HTTP request timeout in seconds (Default: 10).

.PARAMETER HttpCommand
    HTTP client to send the request with. Defaults to the
    DISK_MONITOR_HTTP_COMMAND environment variable, and to curl.

.PARAMETER Doctor
    Report what is configured and what is missing. The disk is not measured
    and nothing is sent.

.PARAMETER Help
    Show the help and usage documentation.

.EXAMPLE
    .\disk_monitor.ps1 -Partition C:\ -Threshold 80 -To ops@example.com

.EXAMPLE
    .\disk_monitor.ps1 -Partition /home -Threshold 90 -DryRun -Verbose

.EXAMPLE
    .\disk_monitor.ps1 -Notify http -Url https://ntfy.sh/disk-alerts
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Partition = "",

    [Parameter(Mandatory = $false)]
    [string]$Threshold = "80",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$Notify = "mail",

    [Parameter(Mandatory = $false)]
    [string]$To = "",

    [Parameter(Mandatory = $false)]
    [string]$MailCommand = "",

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "",

    [Parameter(Mandatory = $false)]
    [string]$Config = "",

    [Parameter(Mandatory = $false)]
    [string]$Url = "",

    [Parameter(Mandatory = $false)]
    [string]$BodyTemplate = "",

    [Parameter(Mandatory = $false)]
    [string[]]$Header = @(),

    [Parameter(Mandatory = $false)]
    [string]$Timeout = "",

    [Parameter(Mandatory = $false)]
    [string]$HttpCommand = "",

    [Parameter(Mandatory = $false)]
    [switch]$Doctor,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# The verbose flag is a common parameter, so it is captured here in the script
# scope. Inside a function $PSBoundParameters would describe the function's
# own parameters, not the script's, and the flag would never be seen.
$script:VerboseEnabled = $PSBoundParameters.ContainsKey('Verbose') -and $Verbose

# The measurement command and the mail agent are external programs, so
# $LASTEXITCODE carries their status. It is initialised here so the strict
# mode never trips over it before the first external call.
$global:LASTEXITCODE = 0

# The configuration file and the values it supplied
$script:ConfigFilePath = ""
$script:ConfigPartition = ""
$script:ConfigThreshold = ""
$script:ConfigNotify = ""
$script:ConfigTo = ""
$script:ConfigMailCommand = ""
$script:ConfigLogFile = ""
$script:ConfigUsageCommand = ""
$script:ConfigUsageOverride = ""
$script:ConfigHeaders = @()
$script:ConfigUrl = ""
$script:ConfigBodyTemplate = ""
$script:ConfigMethod = ""
$script:ConfigTimeout = ""

# Whether the command line supplied each setting. The binder knows, and it
# is captured here in the script scope: inside a function $PSBoundParameters
# would describe the function's own parameters, not the script's.
$script:FlagPartitionSet = $PSBoundParameters.ContainsKey('Partition')
$script:FlagThresholdSet = $PSBoundParameters.ContainsKey('Threshold')
$script:FlagNotifySet = $PSBoundParameters.ContainsKey('Notify')
$script:FlagToSet = $PSBoundParameters.ContainsKey('To')
$script:FlagMailCommandSet = $PSBoundParameters.ContainsKey('MailCommand')
$script:FlagLogFileSet = $PSBoundParameters.ContainsKey('LogFile')
$script:FlagConfigSet = $PSBoundParameters.ContainsKey('Config')
$script:FlagUrlSet = $PSBoundParameters.ContainsKey('Url')
$script:FlagBodyTemplateSet = $PSBoundParameters.ContainsKey('BodyTemplate')
$script:FlagHeaderSet = $PSBoundParameters.ContainsKey('Header')
$script:FlagTimeoutSet = $PSBoundParameters.ContainsKey('Timeout')
$script:FlagHttpCommandSet = $PSBoundParameters.ContainsKey('HttpCommand')

# Where each resolved value came from
$script:SourcePartition = "default"
$script:SourceThreshold = "default"
$script:SourceNotify = "default"
$script:SourceTo = "default"
$script:SourceMailCommand = "default"
$script:SourceLogFile = "default"
$script:SourceUsageCommand = "default"
$script:SourceUsageOverride = "default"
$script:SourceUrl = "default"
$script:SourceBodyTemplate = "default"
$script:SourceMethod = "default"
$script:SourceTimeout = "default"
$script:SourceHttpCommand = "default"
$script:SourceHeader = "default"

# The HTTP transport settings and the headers it carries
$script:ResolvedUrl = ""
$script:ResolvedBodyTemplate = ""
$script:ResolvedMethod = "POST"
$script:ResolvedTimeout = "10"
$script:ResolvedHttpCommand = ""
$script:ResolvedHttpClient = ""
$script:ResolvedHeaders = @()

# The configuration file was named explicitly but does not exist
$script:ConfigFileMissing = $false

# The problems the doctor found
$script:DoctorProblem = @()
$script:DoctorWarning = @()

# The problem found in the resolved headers, and the audit line it writes
$script:HeaderProblem = ""
$script:HeaderAuditMessage = ""

# ANSI Color mapping
$Colors = @{
    Red    = "$([char]27)[0;31m"
    Green  = "$([char]27)[0;32m"
    Yellow = "$([char]27)[1;33m"
    Blue   = "$([char]27)[0;34m"
    Cyan   = "$([char]27)[0;36m"
    Bold   = "$([char]27)[1m"
    Reset  = "$([char]27)[0m"
}

# Prints usage and help message
function Show-Help {
    Write-Host @"
Disk Usage Monitor (PowerShell)
Usage: $PSCommandPath [OPTIONS]

Optional Arguments:
  -Partition <path>        Mount point to watch (default: / on Unix, the system drive on Windows).
  -Threshold <percent>     Alert when usage is strictly greater (default: 80).
  -DryRun                  Report the alert without handing it to the mail agent.
  -Notify <none|mail|http> Notification backend (default: mail).
  -To <address>            Alert recipient (default: `$DISK_MONITOR_TO).
  -MailCommand <cmd>       Mail agent to hand the alert to.
  -Url <url>               HTTP endpoint to post the alert to.
  -BodyTemplate <text>     HTTP request body (default: the plain-text message).
  -Header 'Name: value'    Extra HTTP header. One value may carry several
                            headers, one per line.
  -Timeout <seconds>       HTTP request timeout in seconds (default: 10).
  -HttpCommand <cmd>       HTTP client to send the request with (default: curl).
  -LogFile <file>          Path to append ISO-8601 audit records.
  -Config <file>           Configuration file to read (default: ./.diskmonitor.conf).
  -Doctor                  Report what is configured and what is missing.
  -Verbose                 Enable diagnostic output.
  -Help                    Show this help and usage documentation.

Configuration:
  A flag wins over an environment variable, which wins over the
  configuration file, which wins over the built-in default. The environment
  variables are DISK_MONITOR_PARTITION, DISK_MONITOR_THRESHOLD,
  DISK_MONITOR_NOTIFY, DISK_MONITOR_TO, DISK_MONITOR_MAIL_COMMAND,
  DISK_MONITOR_LOG_FILE, DISK_MONITOR_USAGE_COMMAND,
  DISK_MONITOR_USAGE_OVERRIDE, DISK_MONITOR_CONFIG, DISK_MONITOR_URL,
  DISK_MONITOR_BODY_TEMPLATE, DISK_MONITOR_HEADER, DISK_MONITOR_TIMEOUT and
  DISK_MONITOR_HTTP_COMMAND.

HTTP transport:
  One transport covers every HTTP notification service, because a request
  with a body to a URL is the same primitive everywhere. The body template
  supports {subject}, {body}, {partition}, {usage}, {threshold},
  {recipient}, {host} and {timestamp}; a JSON template therefore speaks to
  Telegram, Discord and Slack without provider-specific code. {recipient} is
  the endpoint the alert is addressed to, and {usage} and {threshold} carry
  the percent sign. The rendered body is written to the client's standard
  input, followed by a newline. A header value is never printed and never
  written to the audit log, because it may carry a token.

Doctor:
  -Doctor reports the resolved configuration and where each value came
  from, whether the measurement command and the transport client can be
  resolved, and whether the recipient or the endpoint is set. It measures
  nothing and sends nothing. It exits 0 when the tool is ready to run and 1
  when something is missing, with one line per problem and the remedy for
  it. A missing dependency is named with the install command of the platform
  the tool was found on.

Exit Codes:
  0  The check completed; the alert was delivered, not needed, or suppressed.
  1  Configuration or safety error (bad flag, threshold, partition, recipient,
     mail agent, endpoint, timeout, method, header or HTTP client).
  2  Partial failure (the usage could not be read, or the alert could not be
     handed to the mail agent or the HTTP client).

Examples:
  $PSCommandPath -Partition / -Threshold 80 -To ops@example.com
  $PSCommandPath -Partition /home -Threshold 90 -DryRun -Verbose
  $PSCommandPath -Notify http -Url https://ntfy.sh/disk-alerts
  $PSCommandPath -Doctor
"@
}

# Writes a message to the error stream without touching the error pipeline
function Write-ErrorLine {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
}

# Writes a message to the audit log with an ISO-8601 timestamp
function Write-AuditLog {
    param(
        [string]$Level = "INFO",
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        return
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $entry = "$timestamp [$Level] $Message"

    try {
        $parent = [System.IO.Path]::GetDirectoryName($LogFile)
        if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $entry -ErrorAction SilentlyContinue
    } catch {
        # A failing audit log must never break the measurement, but the
        # failure is still worth reporting to whoever asked for the detail.
        Write-Verbose "Audit log write failed: $($_.Exception.Message)"
    }
}

# Removes leading and trailing whitespace
function Get-TrimmedValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Trim()
}

# Reads the configuration file. A key is separated from its value by the
# first equals sign. A line may be a comment, and a value may be quoted to
# protect spaces or a hash.
function Read-ConfigFile {
    param([string]$Path)

    $script:ConfigFilePath = $Path
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    $lineNumber = 0

    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = Get-TrimmedValue -Value $line

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        if (-not $trimmed.Contains("=")) {
            # The line is named, never shown: a line pasted into the file by
            # mistake may hold a bearer token.
            Write-ConfigProblem -Kind "malformed" -LineNumber $lineNumber
            continue
        }

        $separator = $trimmed.IndexOf("=")
        $key = Get-TrimmedValue -Value $trimmed.Substring(0, $separator)
        $value = Get-TrimmedValue -Value $trimmed.Substring($separator + 1)

        if ($value.StartsWith('"')) {
            $closing = $value.IndexOf('"', 1)
            if ($closing -gt 0) {
                $value = $value.Substring(1, $closing - 1)
            }
        } elseif ($value.StartsWith("'")) {
            $closing = $value.IndexOf("'", 1)
            if ($closing -gt 0) {
                $value = $value.Substring(1, $closing - 1)
            }
        }

        switch ($key) {
            "partition" { $script:ConfigPartition = $value }
            "threshold" { $script:ConfigThreshold = $value }
            "notify" { $script:ConfigNotify = $value }
            "to" { $script:ConfigTo = $value }
            "mail_command" { $script:ConfigMailCommand = $value }
            "log_file" { $script:ConfigLogFile = $value }
            "usage_command" { $script:ConfigUsageCommand = $value }
            "usage_override" { $script:ConfigUsageOverride = $value }
            "url" { $script:ConfigUrl = $value }
            "body_template" { $script:ConfigBodyTemplate = $value }
            "method" { $script:ConfigMethod = $value }
            "timeout" { $script:ConfigTimeout = $value }
            "header" { $script:ConfigHeaders += $value }
            default {
                Write-ConfigProblem -Kind "unknown" -LineNumber $lineNumber -Key $key
            }
        }
    }
}

# Reports one problem found in the configuration file. A malformed line is
# named by its number and never shown, because a line pasted into the file by
# mistake may hold a bearer token. The doctor carries the problem in its own
# report; a run reports it as a warning.
function Write-ConfigProblem {
    param(
        [string]$Kind,
        [int]$LineNumber,
        [string]$Key = ""
    )

    if ($Kind -eq "malformed") {
        if ($Doctor) {
            Add-DoctorProblem "The configuration file has a malformed line at line $LineNumber, which was ignored. Fix the line, or remove it."
        } else {
            Write-ErrorLine "$($Colors.Yellow)Warning: ignoring malformed line $LineNumber in '$script:ConfigFilePath'.$($Colors.Reset)"
        }
        return
    }

    if ($Doctor) {
        Add-DoctorProblem "The configuration file has an unknown key '$Key' at line $LineNumber, which was ignored. Remove the key, or check its spelling."
    } else {
        Write-ErrorLine "$($Colors.Yellow)Warning: ignoring unknown configuration key '$Key' in '$script:ConfigFilePath'.$($Colors.Reset)"
    }
}

# Resolves one setting: the command line wins, then the environment, then the
# configuration file, then the built-in default.
function Resolve-Setting {
    param(
        [string]$FlagValue,
        [bool]$FlagSet,
        [string]$EnvironmentValue,
        [string]$ConfigValue,
        [string]$DefaultValue
    )

    if ($FlagSet) {
        return [pscustomobject]@{ Value = $FlagValue; Source = "flag" }
    }
    # An environment variable or a configuration value that holds only
    # whitespace is a value, not an absence. The Bash implementation reads it
    # the same way, so the two sides resolve the same setting the same way.
    if (-not [string]::IsNullOrEmpty($EnvironmentValue)) {
        return [pscustomobject]@{ Value = $EnvironmentValue; Source = "environment" }
    }
    if (-not [string]::IsNullOrEmpty($ConfigValue)) {
        return [pscustomobject]@{ Value = $ConfigValue; Source = "config" }
    }
    return [pscustomobject]@{ Value = $DefaultValue; Source = "default" }
}

# Loads the configuration file and applies the precedence to every setting.
# A file named explicitly must exist; a default one that is absent is not an
# error.
function Resolve-Configuration {
    $candidate = ""
    $explicit = $false

    if ($script:FlagConfigSet) {
        $candidate = $Config
        $explicit = $true
    } elseif (-not [string]::IsNullOrWhiteSpace($env:DISK_MONITOR_CONFIG)) {
        $candidate = $env:DISK_MONITOR_CONFIG
        $explicit = $true
    } elseif (Test-Path -LiteralPath "./.diskmonitor.conf" -PathType Leaf) {
        $candidate = "./.diskmonitor.conf"
    } elseif (Test-Path -LiteralPath "$env:HOME/.config/disk-monitor/config" -PathType Leaf) {
        $candidate = "$env:HOME/.config/disk-monitor/config"
    }

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            if ($explicit) {
                $script:ConfigFilePath = $candidate
                $script:ConfigFileMissing = $true
            }
        } else {
            Read-ConfigFile -Path $candidate
        }
    }

    $partitionDefault = "/"
    if ($IsWindows) {
        $partitionDefault = "$env:SystemDrive\"
    }
    $setting = Resolve-Setting -FlagValue $Partition -FlagSet $script:FlagPartitionSet -EnvironmentValue ([string]$env:DISK_MONITOR_PARTITION) -ConfigValue $script:ConfigPartition -DefaultValue $partitionDefault
    $script:Partition = $setting.Value
    $script:SourcePartition = $setting.Source

    $setting = Resolve-Setting -FlagValue $Threshold -FlagSet $script:FlagThresholdSet -EnvironmentValue ([string]$env:DISK_MONITOR_THRESHOLD) -ConfigValue $script:ConfigThreshold -DefaultValue "80"
    $script:Threshold = $setting.Value
    $script:SourceThreshold = $setting.Source

    $setting = Resolve-Setting -FlagValue $Notify -FlagSet $script:FlagNotifySet -EnvironmentValue ([string]$env:DISK_MONITOR_NOTIFY) -ConfigValue $script:ConfigNotify -DefaultValue "mail"
    $script:Notify = $setting.Value
    $script:SourceNotify = $setting.Source

    $setting = Resolve-Setting -FlagValue $To -FlagSet $script:FlagToSet -EnvironmentValue ([string]$env:DISK_MONITOR_TO) -ConfigValue $script:ConfigTo -DefaultValue ""
    $script:To = $setting.Value
    $script:SourceTo = $setting.Source

    $setting = Resolve-Setting -FlagValue $MailCommand -FlagSet $script:FlagMailCommandSet -EnvironmentValue ([string]$env:DISK_MONITOR_MAIL_COMMAND) -ConfigValue $script:ConfigMailCommand -DefaultValue ""
    $script:MailCommand = $setting.Value
    $script:SourceMailCommand = $setting.Source

    $setting = Resolve-Setting -FlagValue $LogFile -FlagSet $script:FlagLogFileSet -EnvironmentValue ([string]$env:DISK_MONITOR_LOG_FILE) -ConfigValue $script:ConfigLogFile -DefaultValue ""
    $script:LogFile = $setting.Value
    $script:SourceLogFile = $setting.Source

    $usageDefault = "df"
    if ($IsWindows) {
        $usageDefault = ""
    }
    $setting = Resolve-Setting -FlagValue "" -FlagSet $false -EnvironmentValue ([string]$env:DISK_MONITOR_USAGE_COMMAND) -ConfigValue $script:ConfigUsageCommand -DefaultValue $usageDefault
    $script:UsageCommand = $setting.Value
    $script:SourceUsageCommand = $setting.Source

    $setting = Resolve-Setting -FlagValue "" -FlagSet $false -EnvironmentValue ([string]$env:DISK_MONITOR_USAGE_OVERRIDE) -ConfigValue $script:ConfigUsageOverride -DefaultValue ""
    $script:UsageOverride = $setting.Value
    $script:SourceUsageOverride = $setting.Source

    $setting = Resolve-Setting -FlagValue $Url -FlagSet $script:FlagUrlSet -EnvironmentValue ([string]$env:DISK_MONITOR_URL) -ConfigValue $script:ConfigUrl -DefaultValue ""
    $script:ResolvedUrl = $setting.Value
    $script:SourceUrl = $setting.Source

    $setting = Resolve-Setting -FlagValue $BodyTemplate -FlagSet $script:FlagBodyTemplateSet -EnvironmentValue ([string]$env:DISK_MONITOR_BODY_TEMPLATE) -ConfigValue $script:ConfigBodyTemplate -DefaultValue ""
    $script:ResolvedBodyTemplate = $setting.Value
    $script:SourceBodyTemplate = $setting.Source

    $setting = Resolve-Setting -FlagValue "" -FlagSet $false -EnvironmentValue "" -ConfigValue $script:ConfigMethod -DefaultValue "POST"
    $script:ResolvedMethod = $setting.Value
    $script:SourceMethod = $setting.Source

    $setting = Resolve-Setting -FlagValue $Timeout -FlagSet $script:FlagTimeoutSet -EnvironmentValue ([string]$env:DISK_MONITOR_TIMEOUT) -ConfigValue $script:ConfigTimeout -DefaultValue "10"
    $script:ResolvedTimeout = $setting.Value
    $script:SourceTimeout = $setting.Source

    $setting = Resolve-Setting -FlagValue $HttpCommand -FlagSet $script:FlagHttpCommandSet -EnvironmentValue ([string]$env:DISK_MONITOR_HTTP_COMMAND) -ConfigValue "" -DefaultValue ""
    $script:ResolvedHttpCommand = $setting.Value
    $script:SourceHttpCommand = $setting.Source

    Resolve-HeaderList
}

# Splits header values into individual headers. A value may carry several
# headers, one per line, which is the same shape the environment variable and
# the configuration file use.
function Split-HeaderLine {
    param([string[]]$HeaderValues)

    $result = @()

    foreach ($value in $HeaderValues) {
        foreach ($line in ($value -split "`n")) {
            $trimmed = $line.TrimEnd([char]13)
            if ($trimmed -ne "") {
                $result += $trimmed
            }
        }
    }

    return $result
}

# Resolves the headers the request carries. A command line header wins over
# an environment header, which wins over the headers in the configuration
# file, which wins over no header at all. Both the environment variable and
# the configuration file accept one header per line.
function Resolve-HeaderList {
    $envHeader = [string]$env:DISK_MONITOR_HEADER

    if ($script:FlagHeaderSet) {
        $script:ResolvedHeaders = @()
        if ($Header.Count -gt 0) {
            $script:ResolvedHeaders = @(Split-HeaderLine -HeaderValues $Header)
        }
        $script:SourceHeader = "flag"
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($envHeader)) {
        $script:ResolvedHeaders = @(Split-HeaderLine -HeaderValues @($envHeader))
        $script:SourceHeader = "environment"
        return
    }

    if ($script:ConfigHeaders.Count -gt 0) {
        $script:ResolvedHeaders = @(Split-HeaderLine -HeaderValues $script:ConfigHeaders)
        $script:SourceHeader = "config"
        return
    }

    $script:ResolvedHeaders = @()
    $script:SourceHeader = "default"
}

# Reads the usage percentage from the POSIX df output.
# The capacity is taken from the fifth field, because that is its fixed
# position in the POSIX layout: the mount point is last and may contain
# spaces, so counting from the right would read the mount point instead.
function Read-PosixUsage {
    param(
        [string]$Path,
        [string]$Command
    )

    $output = $null
    try {
        $output = & $Command -P $Path 2>$null
    } catch {
        return $null
    }

    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return $null
    }

    $lines = @($output)
    if ($lines.Count -lt 2) {
        return $null
    }

    $fields = $lines[1].Trim() -split '\s+'
    if ($fields.Count -lt 5) {
        return $null
    }

    $capacity = $fields[4].TrimEnd('%')
    if ($capacity -notmatch '^\d+$') {
        return $null
    }

    return [int]$capacity
}

# Reads the usage percentage of a Windows volume
function Get-WindowsVolumeUsage {
    param([string]$Path)

    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = "$env:SystemDrive\"
    }
    $deviceId = $root.TrimEnd('\')

    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -eq $deviceId }

    if ($null -eq $disk -or $null -eq $disk.Size -or $disk.Size -le 0) {
        return $null
    }

    $used = $disk.Size - $disk.FreeSpace
    return [int][math]::Round(($used / $disk.Size) * 100)
}

# Reads the usage percentage of the watched partition, or $null when the
# measurement failed. A forced value short-circuits the measurement.
function Get-DiskUsagePercent {
    param(
        [string]$Path,
        [string]$Command
    )

    if (-not [string]::IsNullOrWhiteSpace($script:UsageOverride)) {
        return [int]$script:UsageOverride
    }

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        return (Read-PosixUsage -Path $Path -Command $Command)
    }

    return (Get-WindowsVolumeUsage -Path $Path)
}

# Resolves the mail agent that receives the alert. The contract is:
#   <mail-command> -s <subject> <recipient>   with the body on stdin.
# The candidate list covers the agents that honour that contract.
function Resolve-MailCommand {
    param([string]$Override)

    $candidate = $Override

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        $resolved = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Source
        }
        return $null
    }

    foreach ($name in @("mail", "msmtp")) {
        $resolved = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Source
        }
    }

    return $null
}

# Hands the alert to the resolved mail agent
function Send-Alert {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$Command,
        [string]$Recipient
    )

    try {
        $Body | & $Command -s $Subject $Recipient 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Resolves the HTTP client that carries the request. The contract is:
#   -HttpCommand  ->  DISK_MONITOR_HTTP_COMMAND  ->  curl
# Only an application is a client: the legacy PowerShell "curl" alias must
# never be captured, and on Windows this reaches the real curl.exe.
function Resolve-HttpCommand {
    param([string]$Override)

    $candidate = $Override

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        $resolved = @(Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            return $resolved[0].Source
        }
        return $null
    }

    foreach ($name in @("curl", "curl.exe")) {
        $resolved = @(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            return $resolved[0].Source
        }
    }

    return $null
}

# Resolves the measurement command to the program that runs it. The command
# is an external program, so it is resolved the way the mail agent and the
# HTTP client are resolved.
function Resolve-UsageCommand {
    param([string]$Command)

    if ([string]::IsNullOrEmpty($Command)) {
        return $null
    }

    $resolved = @(Get-Command $Command -ErrorAction SilentlyContinue)
    if ($resolved.Count -gt 0) {
        return $resolved[0].Source
    }

    return $null
}

# Returns the partition the tool watches. The default is the root of the
# current drive on Windows and "/" elsewhere.
function Get-ResolvedPartition {
    $value = $Partition

    if ([string]::IsNullOrEmpty($value)) {
        if ($IsWindows) {
            return "$env:SystemDrive\"
        }
        return "/"
    }

    return $value
}

# Names the platform the tool is running on. The distribution is read from
# the file every Linux distribution ships, so the report names the system the
# tool was found on and not only the kernel.
function Get-PlatformName {
    if ($IsWindows) {
        return "Windows"
    }

    if ($IsMacOS) {
        return "macOS"
    }

    $identifier = ""
    if (Test-Path -LiteralPath "/etc/os-release" -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath "/etc/os-release")) {
            if ($line.StartsWith("ID=")) {
                $identifier = $line.Substring(3).Trim().Trim('"').Trim("'")
                break
            }
        }
    }

    if ($identifier -ne "") {
        return "Linux ($identifier)"
    }

    return "Linux"
}

# Prints the command that installs a package on this platform. The package
# manager is the one that is installed, so the remedy names a command the
# reader can run. The package name is the same on every distribution, only
# the syntax of the command differs.
function Resolve-InstallCommand {
    param([string]$Package)

    if ($IsWindows) {
        return $null
    }

    if ($IsMacOS) {
        return "brew install $Package"
    }

    $manager = @(
        @{ Name = "apt-get"; Command = "sudo apt-get install" },
        @{ Name = "dnf"; Command = "sudo dnf install" },
        @{ Name = "yum"; Command = "sudo yum install" },
        @{ Name = "pacman"; Command = "sudo pacman -S" },
        @{ Name = "apk"; Command = "sudo apk add" },
        @{ Name = "zypper"; Command = "sudo zypper install" }
    )

    foreach ($entry in $manager) {
        $resolved = @(Get-Command $entry.Name -CommandType Application -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            return "$($entry.Command) $Package"
        }
    }

    return $null
}

# The remedy for a dependency that is not installed. The install command is
# the one of the platform the tool was found on, because a generic suggestion
# is not an instruction the reader can run.
function Get-DependencyRemedy {
    param([string]$Dependency)

    $package = "coreutils"
    $alternative = "or set DISK_MONITOR_USAGE_COMMAND to another measurement command"

    switch ($Dependency) {
        "curl" {
            $package = "curl"
            $alternative = "or set -HttpCommand to another HTTP client"
        }
        "msmtp" {
            $package = "msmtp"
            $alternative = "or set -MailCommand to another mail agent"
        }
    }

    if ($IsWindows) {
        switch ($Dependency) {
            "curl" {
                return "curl.exe ships with Windows 10 (1803) and later. Run 'curl.exe --version' to confirm it, or set -HttpCommand to another client."
            }
            "msmtp" {
                return "Windows has no mail agent. Use -Notify http with -Url, which needs no local agent."
            }
            default {
                return "Install coreutils, or set DISK_MONITOR_USAGE_COMMAND to another measurement command."
            }
        }
    }

    $installCommand = Resolve-InstallCommand -Package $package
    if ($null -ne $installCommand) {
        return "Install it with: $installCommand"
    }

    return "Install $package with your package manager, $alternative."
}

# Removes the control characters from a value before it is printed. A value
# that carries an escape sequence could otherwise rewrite the report, so the
# doctor prints a value that cannot move the cursor or change a colour.
function Get-SafeDisplayValue {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }

    return ($Value -replace "[`e`r`n`b]", "")
}

# Removes the leading zeros of a numeric string, so a value is judged by its
# value and not by the way it is spelled.
function Get-CanonicalNumber {
    param([string]$Value)

    $digits = $Value.TrimStart('0')
    if ($digits -eq "") {
        return "0"
    }

    return $digits
}

# Reports whether a value is a valid threshold: an integer between 1 and
# 100. The digits are judged before they are compared, so a value that does
# not fit in an integer is reported as invalid instead of overflowing.
function Test-ThresholdValue {
    param([string]$Value)

    if ($Value -notmatch '^\d+$') {
        return $false
    }

    $digits = Get-CanonicalNumber -Value $Value
    if ($digits.Length -gt 3) {
        return $false
    }

    return (([int]$digits -ge 1) -and ([int]$digits -le 100))
}

# Reports whether a value is a valid timeout: a whole number of seconds
# above zero. The digits are judged before they are compared, so a value
# that does not fit in an integer is not mistaken for a small one.
function Test-TimeoutValue {
    param([string]$Value)

    if ($Value -notmatch '^\d+$') {
        return $false
    }

    $digits = Get-CanonicalNumber -Value $Value
    if ($digits.Length -gt 10) {
        return $false
    }

    return (([int64]$digits -ge 1) -and ([int64]$digits -le 2147483647))
}

# Reports whether a file can be read by a user other than its owner. The
# configuration file may hold a token, so a file that other users can read
# is a finding the doctor has to report. On Windows the permission bits are
# an access control list, so the named principals that every user belongs to
# are the ones that decide it.
function Test-FileReadableByOther {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($null -eq $acl) {
            return $false
        }

        # Only the Everyone principal is reported on Windows, by name and by
        # well-known identifier. The built-in Users group holds read access
        # on every file of a user profile, so reporting it would report
        # every file of the platform.
        foreach ($rule in $acl.Access) {
            if ($rule.AccessControlType -ne "Allow") {
                continue
            }
            if ($rule.IdentityReference -notmatch "Everyone|S-1-1-0") {
                continue
            }
            if (($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Read) -ne 0) {
                return $true
            }
        }

        return $false
    }

    # The permission of a Unix host is a mode, and the mode is read from the
    # flags of the file system, so the group and the others are judged by
    # their own flag and not by the spelling of the mode.
    $reader = [System.IO.File].GetMethod("GetUnixFileMode", [Type[]]@([string]))
    if ($null -ne $reader) {
        $mode = [System.IO.File]::GetUnixFileMode($Path)
        $groupRead = $mode.HasFlag([System.IO.UnixFileMode]::GroupRead)
        $otherRead = $mode.HasFlag([System.IO.UnixFileMode]::OtherRead)

        return ($groupRead -or $otherRead)
    }

    # The API that reads the mode arrived in .NET 7, so the mode of the file
    # system provider is used when the API is not there. The provider
    # renders the mode as the three triples of the owner, the group and the
    # others.
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $false
    }

    $text = $item.Mode
    if ($text.Length -lt 9) {
        return $false
    }

    $text = $text.Substring($text.Length - 9)
    $groupChar = $text.Substring(3, 1)
    $otherChar = $text.Substring(6, 1)

    return (($groupChar -eq "r") -or ($otherChar -eq "r"))
}

# Prints the command that restricts a file to its owner. The remedy names
# the platform it was found on, because the permission model of Windows is
# an access control list and the permission model of a Unix host is a mode.
function Get-ConfigFileRestrictCommand {
    param([string]$Path)

    if ($IsWindows) {
        return "icacls '$Path' /inheritance:r /grant:r '$($env:USERNAME):(R,W)'"
    }

    return "chmod 600 '$Path'"
}

# Writes one field of the doctor report. The source of the value is shown
# with it, so the reader can see where a setting came from. The value is
# stripped of the control characters, so it cannot rewrite the report.
function Write-DoctorField {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Source = ""
    )

    $safe = Get-SafeDisplayValue -Value $Value

    if ($Source -ne "") {
        Write-Host ("{0,-20}: {1} ({2})" -f $Label, $safe, $Source)
        return
    }

    Write-Host ("{0,-20}: {1}" -f $Label, $safe)
}

# Records one problem the doctor found. Every problem carries its own
# remedy, on one line.
function Add-DoctorProblem {
    param([string]$Message)

    $script:DoctorProblem += $Message
}

# Records one warning the doctor found. A warning is reported with its own
# remedy, but the tool still runs, so it does not change the exit code.
function Add-DoctorWarning {
    param([string]$Message)

    $script:DoctorWarning += $Message
}

# Validates the resolved headers. A header is a name and a value, and it must
# not carry a line break, which would let it inject a second header. The
# value is never reported: it may carry a bearer token. The problem is handed
# to the caller, which decides whether to fail the run or to report it.
function Test-HttpHeader {
    param([string[]]$HeaderList)

    $headerNumber = 0
    $script:HeaderProblem = ""
    $script:HeaderAuditMessage = ""

    foreach ($headerText in $HeaderList) {
        $headerNumber++

        if ($headerText.Contains("`n") -or $headerText.Contains("`r")) {
            $script:HeaderProblem = "Header $headerNumber carries a line break."
            $script:HeaderAuditMessage = "Malformed HTTP header: it carries a line break."
            return $false
        }

        if ($headerText -notmatch '^[^:\s]+:.*$') {
            $script:HeaderProblem = "Header $headerNumber is malformed. Expected 'Name: value'."
            $script:HeaderAuditMessage = "Malformed HTTP header."
            return $false
        }
    }

    return $true
}

# Fails the run when a header is malformed
function Assert-HttpHeader {
    param([string[]]$HeaderList)

    if (Test-HttpHeader -HeaderList $HeaderList) {
        return
    }

    Write-ErrorLine "$($Colors.Red)Error: $($script:HeaderProblem)$($Colors.Reset)"
    Write-AuditLog -Level "ERROR" -Message $script:HeaderAuditMessage
    exit 1
}

# Renders the body template.
# The template is scanned from left to right and the earliest known
# placeholder is replaced wherever it appears. A value is never re-scanned, so
# a partition named "{usage}" cannot be substituted a second time. An unknown
# placeholder is copied verbatim, which is what keeps a JSON template intact:
# only the known names are substituted, the JSON braces are not.
function Format-BodyTemplate {
    param(
        [string]$Template,
        [string]$SubjectValue,
        [string]$BodyValue,
        [string]$PartitionValue,
        [string]$UsageValue,
        [string]$ThresholdValue,
        [string]$RecipientValue,
        [string]$HostValue,
        [string]$TimestampValue
    )

    $placeholders = [ordered]@{
        "subject"   = $SubjectValue
        "body"      = $BodyValue
        "partition" = $PartitionValue
        "usage"     = $UsageValue
        "threshold" = $ThresholdValue
        "recipient" = $RecipientValue
        "host"      = $HostValue
        "timestamp" = $TimestampValue
    }

    $result = ""
    $rest = $Template

    while ($rest.Length -gt 0) {
        $bestIndex = -1
        $bestKey = ""

        foreach ($key in $placeholders.Keys) {
            $index = $rest.IndexOf("{" + $key + "}", [System.StringComparison]::Ordinal)
            if ($index -ge 0 -and ($bestIndex -lt 0 -or $index -lt $bestIndex)) {
                $bestIndex = $index
                $bestKey = $key
            }
        }

        if ($bestIndex -lt 0) {
            $result += $rest
            break
        }

        $result += $rest.Substring(0, $bestIndex)
        $result += $placeholders[$bestKey]
        $rest = $rest.Substring($bestIndex + $bestKey.Length + 2)
    }

    return $result
}

# Hands the alert to the resolved HTTP client. The contract is:
#   <http-command> --silent --show-error --max-time <seconds>
#                   --request <method> --header <name: value>...
#                   --data-binary @- <url>
# with the rendered body on standard input.
function Send-HttpAlert {
    param(
        [string]$Endpoint,
        [string]$Body,
        [string]$Method,
        [int]$TimeoutSeconds,
        [string]$Client,
        [string[]]$HeaderList
    )

    $clientArgs = @(
        "--silent",
        "--show-error",
        "--max-time",
        $TimeoutSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture),
        "--request",
        $Method
    )

    foreach ($headerText in $HeaderList) {
        $clientArgs += @("--header", $headerText)
    }

    $clientArgs += @("--data-binary", "@-", $Endpoint)

    try {
        # The client's own diagnostics are left on the error stream, so a
        # failed request says why. The Bash implementation behaves the same.
        $Body | & $Client @clientArgs | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Reports what is configured and what is missing, and changes nothing. The
# disk is not measured and nothing is sent: the report is the whole point.
# The exit code tells the reader whether the tool is ready to run.
function Invoke-Doctor {
    $platform = Get-PlatformName
    $usageCommand = $null
    $httpClient = $null
    $mailCommand = $null
    $resolvedPartition = Get-ResolvedPartition

    # The configuration file
    if ($script:ConfigFileMissing) {
        Add-DoctorProblem "The configuration file '$($script:ConfigFilePath)' was not found. Create it, or point -Config at a file that exists."
    } elseif (-not [string]::IsNullOrEmpty($script:ConfigFilePath) -and (Test-Path -LiteralPath $script:ConfigFilePath -PathType Leaf)) {
        # The file may hold a token, so a file other users can read is
        # reported. It is a warning and not a problem: the tool still runs,
        # and a new file is readable by others until it is restricted.
        if (Test-FileReadableByOther -Path $script:ConfigFilePath) {
            $restrictCommand = Get-ConfigFileRestrictCommand -Path $script:ConfigFilePath
            Add-DoctorWarning "The configuration file '$($script:ConfigFilePath)' can be read by other users. Restrict it: $restrictCommand"
        }
    }

    # The threshold
    if (-not (Test-ThresholdValue -Value $script:Threshold)) {
        Add-DoctorProblem "The threshold '$($script:Threshold)' is not an integer between 1 and 100. Set -Threshold to a number between 1 and 100."
    }

    # The notify backend
    if ($script:Notify -ne "none" -and $script:Notify -ne "mail" -and $script:Notify -ne "http") {
        Add-DoctorProblem "The notify backend '$($script:Notify)' is not supported. Set -Notify to none, mail or http."
    }

    # The partition
    if (-not (Test-Path -LiteralPath $resolvedPartition -PathType Container)) {
        Add-DoctorProblem "The partition '$resolvedPartition' does not exist. Set -Partition to a mount point that exists."
    }

    # The measurement command. The remedy names the package only when the
    # command is the built-in one: a command the configuration file names
    # comes from no package, so the remedy has to point at the setting.
    if (-not [string]::IsNullOrEmpty($script:UsageCommand)) {
        $usageCommand = Resolve-UsageCommand -Command $script:UsageCommand
        if ($null -eq $usageCommand) {
            if ($script:SourceUsageCommand -eq "default") {
                Add-DoctorProblem "The measurement command '$($script:UsageCommand)' was not found. $(Get-DependencyRemedy -Dependency 'coreutils')"
            } else {
                Add-DoctorProblem "The measurement command '$($script:UsageCommand)' was not found. Install it, or set DISK_MONITOR_USAGE_COMMAND to another measurement command."
            }
        }
    }

    # The transport
    if ($script:Notify -eq "mail") {
        if ([string]::IsNullOrEmpty($script:To)) {
            Add-DoctorProblem "No recipient is configured. Set -To, or DISK_MONITOR_TO, or the 'to' key in the configuration file."
        }

        $mailCommand = Resolve-MailCommand -Override $script:MailCommand
        if ($null -eq $mailCommand) {
            Add-DoctorProblem "No mail agent was found. $(Get-DependencyRemedy -Dependency 'msmtp')"
        }
    } elseif ($script:Notify -eq "http") {
        if ([string]::IsNullOrEmpty($script:ResolvedUrl)) {
            Add-DoctorProblem "No endpoint is configured. Set -Url, or DISK_MONITOR_URL, or the 'url' key in the configuration file."
        } elseif ($script:ResolvedUrl -notmatch '^https?://\S+$') {
            Add-DoctorProblem "The endpoint '$($script:ResolvedUrl)' is not a valid http or https URL. Set -Url to a URL that starts with http:// or https://."
        }

        if (-not (Test-TimeoutValue -Value $script:ResolvedTimeout)) {
            Add-DoctorProblem "The HTTP timeout '$($script:ResolvedTimeout)' is not a whole number of seconds above zero. Set -Timeout to a whole number of seconds."
        }

        if ($script:ResolvedMethod -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            Add-DoctorProblem "The HTTP method '$($script:ResolvedMethod)' is not a valid token. Set the method to a name such as POST."
        }

        if (-not (Test-HttpHeader -HeaderList $script:ResolvedHeaders)) {
            Add-DoctorProblem $script:HeaderProblem
        }

        $httpClient = Resolve-HttpCommand -Override $script:ResolvedHttpCommand
        if ($null -eq $httpClient) {
            if (-not [string]::IsNullOrEmpty($script:ResolvedHttpCommand)) {
                Add-DoctorProblem "The HTTP client '$($script:ResolvedHttpCommand)' was not found. Install it, or set -HttpCommand to another HTTP client."
            } else {
                Add-DoctorProblem "curl was not found. $(Get-DependencyRemedy -Dependency 'curl')"
            }
        }
    }

    # The report
    Write-Host "$($Colors.Blue)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)                 Disk Usage Monitor - Doctor                 $($Colors.Reset)"
    Write-Host "$($Colors.Blue)============================================================$($Colors.Reset)"

    Write-DoctorField -Label "Platform" -Value $platform

    if ($script:ConfigFileMissing) {
        Write-DoctorField -Label "Config file" -Value "(not found: $($script:ConfigFilePath))"
    } elseif (-not [string]::IsNullOrEmpty($script:ConfigFilePath)) {
        Write-DoctorField -Label "Config file" -Value $script:ConfigFilePath
    } else {
        Write-DoctorField -Label "Config file" -Value "(none found)"
    }

    Write-DoctorField -Label "Partition" -Value $resolvedPartition -Source $script:SourcePartition
    Write-DoctorField -Label "Threshold" -Value "$($script:Threshold)%" -Source $script:SourceThreshold
    Write-DoctorField -Label "Notify backend" -Value $script:Notify -Source $script:SourceNotify

    if ($script:Notify -eq "http") {
        if (-not [string]::IsNullOrEmpty($script:ResolvedUrl)) {
            Write-DoctorField -Label "Endpoint" -Value $script:ResolvedUrl -Source $script:SourceUrl
        } else {
            Write-DoctorField -Label "Endpoint" -Value "(not set)"
        }
        Write-DoctorField -Label "Recipient" -Value "(not required)"
        if ($null -ne $httpClient) {
            Write-DoctorField -Label "HTTP client" -Value $httpClient -Source $script:SourceHttpCommand
        } else {
            Write-DoctorField -Label "HTTP client" -Value "(not found)"
        }
    } elseif ($script:Notify -eq "mail") {
        Write-DoctorField -Label "Endpoint" -Value "(not required)"
        if (-not [string]::IsNullOrEmpty($script:To)) {
            Write-DoctorField -Label "Recipient" -Value $script:To -Source $script:SourceTo
        } else {
            Write-DoctorField -Label "Recipient" -Value "(not set)"
        }
        Write-DoctorField -Label "HTTP client" -Value "(not required)"
    } else {
        Write-DoctorField -Label "Endpoint" -Value "(not required)"
        Write-DoctorField -Label "Recipient" -Value "(not required)"
        Write-DoctorField -Label "HTTP client" -Value "(not required)"
    }

    if ($script:Notify -eq "mail") {
        if ($null -ne $mailCommand) {
            Write-DoctorField -Label "Mail agent" -Value $mailCommand -Source $script:SourceMailCommand
        } else {
            Write-DoctorField -Label "Mail agent" -Value "(not found)"
        }
    } else {
        Write-DoctorField -Label "Mail agent" -Value "(not required)"
    }

    if ($IsWindows -and [string]::IsNullOrEmpty($script:UsageCommand)) {
        Write-DoctorField -Label "Measurement command" -Value "(not required: the native volume API is used)"
    } elseif ($null -ne $usageCommand) {
        Write-DoctorField -Label "Measurement command" -Value $usageCommand -Source $script:SourceUsageCommand
    } else {
        Write-DoctorField -Label "Measurement command" -Value "(not found)"
    }

    if (-not [string]::IsNullOrEmpty($script:LogFile)) {
        Write-DoctorField -Label "Audit log file" -Value $script:LogFile -Source $script:SourceLogFile
    } else {
        Write-DoctorField -Label "Audit log file" -Value "(not set)"
    }

    Write-DoctorField -Label "HTTP headers" -Value "$($script:ResolvedHeaders.Count)" -Source $script:SourceHeader

    Write-Host "$($Colors.Blue)------------------------------------------------------------$($Colors.Reset)"

    if ($script:DoctorWarning.Count -gt 0) {
        foreach ($warning in $script:DoctorWarning) {
            Write-DoctorField -Label "Warnings" -Value $warning
        }
    }

    if ($script:DoctorProblem.Count -eq 0) {
        Write-Host ("{0,-20}: {1}READY{2}" -f "Status", $Colors.Green, $Colors.Reset)
        return $true
    }

    Write-Host ("{0,-20}: {1}NOT READY{2}" -f "Status", $Colors.Yellow, $Colors.Reset)
    foreach ($problem in $script:DoctorProblem) {
        Write-Host "  - $(Get-SafeDisplayValue -Value $problem)"
    }

    return $false
}

# Main script orchestration
function Invoke-DiskMonitor {
    if ($Help) {
        Show-Help
        exit 0
    }

    Resolve-Configuration

    if ($script:ConfigFileMissing -and -not $Doctor) {
        Write-ErrorLine "$($Colors.Red)Error: Configuration file '$($script:ConfigFilePath)' does not exist.$($Colors.Reset)"
        exit 1
    }

    if ($Doctor) {
        if (Invoke-Doctor) {
            exit 0
        }
        exit 1
    }

    if (-not (Test-ThresholdValue -Value $script:Threshold)) {
        Write-ErrorLine "$($Colors.Red)Error: Threshold must be an integer between 1 and 100.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Invalid threshold: '$script:Threshold'."
        exit 1
    }

    if ($script:Notify -ne "none" -and $script:Notify -ne "mail" -and $script:Notify -ne "http") {
        Write-ErrorLine "$($Colors.Red)Error: Notify backend must be 'none', 'mail' or 'http'.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Invalid notify backend: '$script:Notify'."
        exit 1
    }

    $resolvedPartition = Get-ResolvedPartition

    if (-not (Test-Path -LiteralPath $resolvedPartition -PathType Container)) {
        Write-ErrorLine "$($Colors.Red)Error: Partition '$resolvedPartition' does not exist.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Partition does not exist: '$resolvedPartition'."
        exit 1
    }

    $usageOverride = $script:UsageOverride
    if (-not [string]::IsNullOrWhiteSpace($usageOverride)) {
        $parsedOverride = 0
        $isNumeric = [int]::TryParse($usageOverride, [ref]$parsedOverride)
        if (-not $isNumeric -or $parsedOverride -lt 0 -or $parsedOverride -gt 100) {
            Write-ErrorLine "$($Colors.Red)Error: DISK_MONITOR_USAGE_OVERRIDE must be an integer between 0 and 100.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Invalid usage override: '$usageOverride'."
            exit 1
        }
    }

    $resolvedUsageCommand = ""
    if (-not [string]::IsNullOrEmpty($script:UsageCommand)) {
        $resolvedUsageCommand = Resolve-UsageCommand -Command $script:UsageCommand
        if ($null -eq $resolvedUsageCommand) {
            Write-ErrorLine "$($Colors.Red)Error: Measurement command '$($script:UsageCommand)' was not found.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Measurement command not found: '$($script:UsageCommand)'."
            exit 1
        }
    }

    $recipient = $To

    $resolvedMailCommand = ""
    if ($script:Notify -eq "mail") {
        if ([string]::IsNullOrWhiteSpace($recipient)) {
            Write-ErrorLine "$($Colors.Red)Error: No recipient. Use -To, or set DISK_MONITOR_TO.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No alert recipient configured."
            exit 1
        }

        $resolvedMailCommand = Resolve-MailCommand -Override $MailCommand
        if ($null -eq $resolvedMailCommand) {
            Write-ErrorLine "$($Colors.Red)Error: No mail agent found. Install one, or set -MailCommand or DISK_MONITOR_MAIL_COMMAND.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No mail agent could be resolved."
            exit 1
        }
    }

    if ($script:Notify -eq "http") {
        if ([string]::IsNullOrWhiteSpace($script:ResolvedUrl)) {
            Write-ErrorLine "$($Colors.Red)Error: No endpoint. Use -Url, or set DISK_MONITOR_URL.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No HTTP endpoint configured."
            exit 1
        }

        if ($script:ResolvedUrl -notmatch '^https?://\S+$') {
            Write-ErrorLine "$($Colors.Red)Error: Endpoint '$($script:ResolvedUrl)' is not a valid http or https URL.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Invalid HTTP endpoint: '$($script:ResolvedUrl)'."
            exit 1
        }

        if (-not (Test-TimeoutValue -Value $script:ResolvedTimeout)) {
            Write-ErrorLine "$($Colors.Red)Error: Timeout must be an integer of seconds greater than zero.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Invalid HTTP timeout: '$($script:ResolvedTimeout)'."
            exit 1
        }

        if ($script:ResolvedMethod -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            Write-ErrorLine "$($Colors.Red)Error: HTTP method must be a token, for example POST.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "Invalid HTTP method: '$($script:ResolvedMethod)'."
            exit 1
        }

        $script:ResolvedHttpClient = Resolve-HttpCommand -Override $script:ResolvedHttpCommand
        if ($null -eq $script:ResolvedHttpClient) {
            Write-ErrorLine "$($Colors.Red)Error: No HTTP client found. Install one, or set -HttpCommand or DISK_MONITOR_HTTP_COMMAND.$($Colors.Reset)"
            Write-AuditLog -Level "ERROR" -Message "No HTTP client could be resolved."
            exit 1
        }

        Assert-HttpHeader -HeaderList $script:ResolvedHeaders
    }

    $usedPercent = Get-DiskUsagePercent -Path $resolvedPartition -Command $resolvedUsageCommand
    if ($null -eq $usedPercent) {
        Write-ErrorLine "$($Colors.Red)Error: Could not read the disk usage of '$resolvedPartition'.$($Colors.Reset)"
        Write-AuditLog -Level "ERROR" -Message "Could not read the disk usage of '$resolvedPartition'."
        exit 2
    }

    $usageSource = "measured"
    if (-not [string]::IsNullOrWhiteSpace($script:UsageOverride)) {
        $usageSource = "overridden"
    }

    $modeLabel = if ($DryRun) { "$($Colors.Yellow)DRY RUN (Simulation)$($Colors.Reset)" } else { "$($Colors.Green)LIVE (Alerts Active)$($Colors.Reset)" }

    $mailLabel = $resolvedMailCommand
    if ([string]::IsNullOrWhiteSpace($mailLabel)) {
        $mailLabel = "(not resolved: notification disabled)"
    }

    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)                DevOps Disk Usage Monitor                  $($Colors.Reset)"
    Write-Host "$($Colors.Blue)$($Colors.Bold)============================================================$($Colors.Reset)"
    Write-Host "Partition         : $($Colors.Cyan)$resolvedPartition$($Colors.Reset)"
    Write-Host "Usage             : $($Colors.Bold)$usedPercent%$($Colors.Reset) ($usageSource)"
    Write-Host "Threshold         : $($Colors.Yellow)$Threshold%$($Colors.Reset)"
    if ($script:Notify -eq "http") {
        Write-Host "Endpoint          : $($Colors.Cyan)$($script:ResolvedUrl)$($Colors.Reset)"
        Write-Host "HTTP Client       : $($Colors.Cyan)$($script:ResolvedHttpClient)$($Colors.Reset)"
    } else {
        Write-Host "Mail Agent        : $($Colors.Cyan)$mailLabel$($Colors.Reset)"
        if ($script:Notify -eq "mail") {
            Write-Host "Recipient         : $($Colors.Cyan)$recipient$($Colors.Reset)"
        }
    }
    Write-Host "Execution Mode    : $modeLabel"
    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        Write-Host "Audit Log File    : $($Colors.Cyan)$LogFile$($Colors.Reset)"
    }

    if ($script:VerboseEnabled) {
        Write-Host "$($Colors.Blue)Diagnostics        : $($Colors.Reset)mail agent '$mailLabel', recipient '$recipient', dry-run '$DryRun'$($Colors.Reset)"
        if ($script:Notify -eq "http") {
            Write-Host "$($Colors.Blue)Transport          : $($Colors.Reset)endpoint '$($script:SourceUrl)', body template '$($script:SourceBodyTemplate)', method '$($script:SourceMethod)', timeout '$($script:SourceTimeout)', http command '$($script:SourceHttpCommand)', headers $($script:ResolvedHeaders.Count) ('$($script:SourceHeader)')$($Colors.Reset)"
        }
    }
    if ($usedPercent -gt $Threshold) {
        Write-Host "$($Colors.Red)WARNING: Disk usage exceeds the threshold.$($Colors.Reset)"

        $hostName = if ($IsWindows) { $env:COMPUTERNAME } else { (hostname 2>$null) }
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = "unknown-host"
        }

        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $subject = "Disk Alert: $resolvedPartition at $usedPercent%"
        $body = @(
            "Disk usage on $hostName is at $usedPercent% (threshold: $Threshold%)."
            ""
            "Partition : $resolvedPartition"
            "Usage    : $usedPercent%"
            "Threshold: $Threshold%"
            "Time     : $timestamp"
        ) -join "`n"

        $notificationTarget = $recipient
        if ($script:Notify -eq "http") {
            $notificationTarget = $script:ResolvedUrl
        }

        if ($DryRun) {
            Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would send an alert to $notificationTarget"
            Write-AuditLog -Level "INFO" -Message "[DRY RUN] Would send an alert to $notificationTarget (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
        } elseif ($script:Notify -eq "mail") {
            if (Send-Alert -Subject $subject -Body $body -Command $resolvedMailCommand -Recipient $recipient) {
                Write-Host "$($Colors.Green)Alert sent to $recipient$($Colors.Reset)"
                Write-AuditLog -Level "INFO" -Message "ALERT SENT to $recipient (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
            } else {
                Write-ErrorLine "$($Colors.Red)Error: The alert could not be handed to the mail agent.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "FAILED to hand the alert to the mail agent (Usage: ${usedPercent}%, Source: $usageSource)"
                exit 2
            }
        } elseif ($script:Notify -eq "http") {
            $template = $script:ResolvedBodyTemplate
            if ([string]::IsNullOrWhiteSpace($template)) {
                $template = $body
            }

            $renderedBody = Format-BodyTemplate -Template $template -SubjectValue $subject -BodyValue $body -PartitionValue $resolvedPartition -UsageValue "$usedPercent%" -ThresholdValue "$Threshold%" -RecipientValue $script:ResolvedUrl -HostValue $hostName -TimestampValue $timestamp

            if (Send-HttpAlert -Endpoint $script:ResolvedUrl -Body $renderedBody -Method $script:ResolvedMethod -TimeoutSeconds ([int]$script:ResolvedTimeout) -Client $script:ResolvedHttpClient -HeaderList $script:ResolvedHeaders) {
                Write-Host "$($Colors.Green)Alert sent to $($script:ResolvedUrl)$($Colors.Reset)"
                Write-AuditLog -Level "INFO" -Message "ALERT SENT to $($script:ResolvedUrl) (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
            } else {
                Write-ErrorLine "$($Colors.Red)Error: The alert could not be handed to the HTTP client.$($Colors.Reset)"
                Write-AuditLog -Level "ERROR" -Message "FAILED to hand the alert to the HTTP client (Usage: ${usedPercent}%, Source: $usageSource)"
                exit 2
            }
        } else {
            Write-Host "$($Colors.Cyan)Alert suppressed by -Notify none.$($Colors.Reset)"
            Write-AuditLog -Level "INFO" -Message "Alert suppressed by -Notify none (Usage: ${usedPercent}%, Source: $usageSource)"
        }
    } else {
        Write-Host "$($Colors.Green)Disk usage is within the threshold.$($Colors.Reset)"
        Write-AuditLog -Level "INFO" -Message "Usage within threshold (Usage: ${usedPercent}%, Source: $usageSource, Threshold: ${Threshold}%)"
    }

    exit 0
}

Invoke-DiskMonitor
