<#
.SYNOPSIS
    Website Availability (HTTP Health Check)

.DESCRIPTION
    Performs a single HTTP GET against a target URL and reports whether the
    response status matches the expected code, along with response time, size
    and (optionally) SSL certificate expiry.
#>

param(
    [string]$Url = "https://example.com",
    [int]$TimeoutSec = 10,
    [int]$ExpectedCode = 200,
    [switch]$SslCheck,
    [switch]$DryRun,
    [string]$AuditLog = "",
    [switch]$Verbose,
    [switch]$Help
)

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Colors (curlie-inspired)
# ---------------------------------------------------------------------------
$CReset   = "`e[0m"
$CBold    = "`e[1m"
$CDim     = "`e[2m"
$CRed     = "`e[31m"
$CGreen   = "`e[32m"
$CYellow  = "`e[33m"
$CBlue    = "`e[34m"
$CCyan    = "`e[36m"
$CMagenta = "`e[35m"

function Write-Err {
    param([string]$Message)
    Write-Host "$CRed$Message$CReset"
}

function Write-VerboseLog {
    param([string]$Message)
    if ($Verbose) { Write-Host "$CDim$Message$CReset" }
}

function Show-Usage {
    @"
Usage: health_check.ps1 [options]

Website Availability (HTTP Health Check) - single HTTP GET probe.

Options:
  -Url <URL>            Target URL (default: https://example.com)
  -TimeoutSec <SEC>     Request timeout in seconds (default: 10)
  -ExpectedCode <N>     HTTP status code considered healthy (default: 200)
  -SslCheck             Report SSL certificate expiry (HTTPS only)
  -DryRun               Print target/expected/timeout, no request
  -AuditLog <PATH>      Append an ISO-8601 audit line per run
  -Verbose              Diagnostic output
  -Help                 Show this help and exit

Exit codes:
  0  Healthy (status matches expected) or dry-run
  1  Configuration or safety violation
  2  Unhealthy (status mismatch or connection failure)
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if ($Url -notmatch '^https?://') {
    Write-Err "Invalid URL: must start with http:// or https://"
    exit 1
}
if ($TimeoutSec -le 0) {
    Write-Err "Invalid timeout: must be a positive integer"
    exit 1
}
if ($ExpectedCode -lt 100 -or $ExpectedCode -gt 599) {
    Write-Err "Invalid expected code: must be between 100 and 599"
    exit 1
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
Write-Host "$CBold$CBlue=== HTTP Health Check ===$CReset"
Write-Host ("  {0}Target:{1}   {2}{3}{4}" -f $CDim, $CReset, $CCyan, $Url, $CReset)
Write-Host ("  {0}Expected:{1} {2}{3}{4}" -f $CDim, $CReset, $CGreen, $ExpectedCode, $CReset)
Write-Host ("  {0}Timeout:{1}  {2}{3}s{4}" -f $CDim, $CReset, $CYellow, $TimeoutSec, $CReset)
if ($SslCheck) {
    Write-Host ("  {0}SSL:{1}     {2}enabled{3}" -f $CDim, $CReset, $CMagenta, $CReset)
}

# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------
if ($DryRun) {
    Write-Host ""
    Write-Host "$($CGreen)Dry run - no request made.$($CReset)"
    if ($AuditLog) {
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "$ts url=$Url status=- time=- size=- outcome=dry-run" | Out-File -FilePath $AuditLog -Append -Encoding utf8 -ErrorAction SilentlyContinue
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Request
# ---------------------------------------------------------------------------
Write-VerboseLog "Performing GET request (no redirects)..."

$httpCode = 0
$respTime = 0
$size = 0
$connFailed = $false

# Test seam: HEALTH_CHECK_MOCK_RESPONSE = "code|time|size" or "FAIL"
$mock = $env:HEALTH_CHECK_MOCK_RESPONSE
if ($mock) {
    if ($mock -eq "FAIL") {
        $connFailed = $true
        $httpCode = 0
        $respTime = 0
        $size = 0
    } else {
        $parts = $mock -split '\|'
        $httpCode = [int]$parts[0]
        $respTime = $parts[1]
        $size = [int]$parts[2]
    }
    Start-Sleep -Milliseconds 1
} else {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -UseBasicParsing -SkipHttpErrorCheck -ErrorAction Stop
        $sw.Stop()
        $httpCode = [int]$response.StatusCode
        $respTime = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        $size = [int]$response.RawContentLength
    } catch {
        $sw.Stop()
        $respTime = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        $connFailed = $true
        if ($_.Exception.Response) {
            try { $httpCode = [int]$_.Exception.Response.StatusCode } catch { $httpCode = 0 }
        } else {
            $httpCode = 0
        }
    }
}

Write-VerboseLog "http_code=$httpCode time=${respTime}s size=$size"

# ---------------------------------------------------------------------------
# Health determination
# ---------------------------------------------------------------------------
$outcome = "healthy"
$exitCode = 0
if ($connFailed -or $httpCode -eq 0) {
    $outcome = "unhealthy"
    $exitCode = 2
} elseif ($httpCode -eq $ExpectedCode) {
    $outcome = "healthy"
    $exitCode = 0
} else {
    $outcome = "unhealthy"
    $exitCode = 2
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "$($CBold)Result$($CReset)"
Write-Host ("  {0,-12}" -f "Status:") -NoNewline
if ($outcome -eq "healthy") {
    Write-Host "$CGreen$httpCode OK$CReset"
} elseif ($httpCode -eq 0) {
    Write-Host "$($CRed)CONNECTION FAILED$($CReset)"
} else {
    Write-Host "$CYellow$httpCode (unexpected, expected $ExpectedCode)$CReset"
}
Write-Host ("  {0}Time:{1}     {2}{3}s{4}" -f $CDim, $CReset, $CCyan, $respTime, $CReset)
Write-Host ("  {0}Size:{1}     {2}{3} bytes{4}" -f $CDim, $CReset, $CCyan, $size, $CReset)

if ($SslCheck -and $Url -match '^https') {
    $expiry = "unavailable"
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        try {
            $hostName = ([uri]$Url).Host
            $endLine = ("" | openssl s_client -servername $hostName -connect "${hostName}:443" 2>$null) 2>$null | openssl x509 -noout -enddate 2>$null
            if ($endLine -match 'notAfter=(.+)') {
                $expiry = $Matches[1].Trim()
            }
        } catch {
            $expiry = "unavailable"
        }
    }
    Write-Host ("  {0}SSL expiry:{1} {2}{3}{4}" -f $CDim, $CReset, $CMagenta, $expiry, $CReset)
}

Write-Host ""
if ($outcome -eq "healthy") {
    Write-Host "$($CGreen)Healthy.$($CReset)"
} else {
    Write-Host "$($CRed)Unhealthy.$($CReset)"
}

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------
if ($AuditLog) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    "$ts url=$Url status=$httpCode time=${respTime}s size=$size outcome=$outcome" | Out-File -FilePath $AuditLog -Append -Encoding utf8 -ErrorAction SilentlyContinue
}

exit $exitCode
