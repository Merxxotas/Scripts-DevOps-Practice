<#
.SYNOPSIS
    Automated Database Backup with Timestamp.

.DESCRIPTION
    Runs a database dump, compresses the result, stores it in a backup directory
    and prunes backups older than a retention window. Supports MySQL (mysqldump)
    and PostgreSQL (pg_dump). Credentials come from a parameter or an environment
    variable and are never hardcoded, echoed or written to the audit log in full.

    Exit codes:
      0  success (backup created, compressed, retention applied)
      1  configuration or safety violation
      2  partial failure (dump, compression or retention step failed)
#>

param(
    [ValidateSet("mysql", "postgresql", "postgres")]
    [string]$DbType = "mysql",
    [string]$DbName = "mydatabase",
    [string]$DbUser = "backup_user",
    [string]$DbPassword = "",
    [string]$BackupDir = "C:\Backups\Database",
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = 7,
    [switch]$Compress,
    [switch]$NoCompress,
    [switch]$DryRun,
    [string]$LogFile = "",
    [switch]$Verbose,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$Colors = @{
    Red = "`e[31m"
    Green = "`e[32m"
    Yellow = "`e[33m"
    Blue = "`e[34m"
    Cyan = "`e[36m"
    Reset = "`e[0m"
}

# ---------- helpers ----------

function Write-Color {
    param([string]$Color, [string]$Message)
    Write-Host "$($Colors[$Color])$Message$($Colors.Reset)"
}

function Write-ErrorLine {
    param([string]$Message)
    Write-Host "$($Colors.Red)Error: $Message$($Colors.Reset)" -ForegroundColor Red
}

function Write-InfoLine {
    param([string]$Message)
    Write-Host "$($Colors.Blue)$Message$($Colors.Reset)"
}

function Write-SuccessLine {
    param([string]$Message)
    Write-Host "$($Colors.Green)$Message$($Colors.Reset)"
}

function Write-WarningLine {
    param([string]$Message)
    Write-Host "$($Colors.Yellow)$Message$($Colors.Reset)" -ForegroundColor Yellow
}

function Show-Help {
    @"
Database Backup Utility (PowerShell)
Usage: .\db_backup.ps1 [OPTIONS]

Optional Arguments:
  -DbType <mysql|postgresql>   Database engine (default: mysql).
  -DbName <name>               Database name (default: mydatabase).
  -DbUser <user>               Database user (default: backup_user).
  -DbPassword <pass>           Database password (default: `$env:DB_BACKUP_PASSWORD).
  -BackupDir <path>            Directory to store backups (default: C:\Backups\Database).
  -RetentionDays <n>           Delete backups older than n days (default: 7).
  -Compress                    Compress the backup (default: on).
  -NoCompress                  Do not compress the backup.
  -DryRun                      Preview without dumping, compressing or deleting.
  -LogFile <file>              Append ISO-8601 audit records.
  -Verbose                     Enable diagnostic output.
  -Help                        Show this help and exit 0.

Configuration:
  A flag wins over an environment variable, which wins over the built-in
  default. The password is read from -DbPassword, then DB_BACKUP_PASSWORD.
  No other setting has an environment variable in v1.

Exit Codes:
  0  success (backup created, compressed, retention applied)
  1  configuration or safety violation
  2  partial failure (dump, compression or retention step failed)
"@
}

if ($Help) {
    Show-Help
    exit 0
}

# ---------- guardrails ----------

function Test-BlockedPath {
    param([string]$Path)
    $lower = $Path.ToLowerInvariant()
    $blocked = @("/", "\\", "c:\\", "c:\\windows", "c:\\program files", "c:\\users",
                  "/etc", "/var", "/usr", "/bin", "/sbin", "/lib", "/lib64",
                  "/boot", "/dev", "/proc", "/sys", "/root")
    foreach ($b in $blocked) {
        if ($lower -eq $b -or $lower.StartsWith("$b\\" ) -or $lower.StartsWith("$b/")) {
            return $true
        }
    }
    return $false
}

# ---------- validation ----------

function Normalize-DbType {
    param([string]$Type)
    $t = $Type.ToLowerInvariant()
    if ($t -eq "postgres") { return "postgresql" }
    return $t
}

function Test-ValidDbType {
    param([string]$Type)
    return ($Type -in @("mysql", "postgresql"))
}

function Test-ValidRetention {
    param([int]$Days)
    return ($Days -ge 0 -and $Days -le 3650)
}

# ---------- log ----------

function Write-AuditLine {
    param([string]$Level, [string]$Message)
    if (-not [string]::IsNullOrEmpty($LogFile)) {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        try {
            Add-Content -Path $LogFile -Value "$timestamp [$Level] $Message" -ErrorAction SilentlyContinue
        } catch { }
    }
    if ($Verbose -or $Level -eq "ERROR" -or $Level -eq "WARNING") {
        [Console]::Error.WriteLine($Message)
    }
}

# ---------- dump command ----------

function Get-DumpTool {
    param([string]$DbType)
    switch ($DbType) {
        "mysql" { return "mysqldump" }
        "postgresql" { return "pg_dump" }
    }
}

# ---------- main ----------

$DbType = Normalize-DbType $DbType
$CompressEnabled = $true
if ($NoCompress) { $CompressEnabled = $false }
if ($Compress) { $CompressEnabled = $true }

# Validate db type
if (-not (Test-ValidDbType $DbType)) {
    Write-ErrorLine "Unsupported database type: '$DbType'. Use mysql or postgresql."
    exit 1
}

# Validate db name
if ([string]::IsNullOrWhiteSpace($DbName)) {
    Write-ErrorLine "Database name must not be empty."
    exit 1
}

# Validate db user
if ([string]::IsNullOrWhiteSpace($DbUser)) {
    Write-ErrorLine "Database user must not be empty."
    exit 1
}

# Resolve password
if ([string]::IsNullOrEmpty($DbPassword)) {
    $DbPassword = $env:DB_BACKUP_PASSWORD
}
if ([string]::IsNullOrEmpty($DbPassword)) {
    Write-ErrorLine "Database password is required. Pass -DbPassword or set DB_BACKUP_PASSWORD."
    exit 1
}

# Validate retention
if (-not (Test-ValidRetention $RetentionDays)) {
    Write-ErrorLine "Retention days must be an integer between 0 and 3650."
    exit 1
}

# Guardrail: backup dir
if (Test-BlockedPath $BackupDir) {
    Write-ErrorLine "Refusing to use a system path as the backup directory: '$BackupDir'."
    exit 1
}

$dumpTool = Get-DumpTool $DbType
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$backupFile = Join-Path $BackupDir "${DbType}_${DbName}_${timestamp}.sql"
$compressedFile = "$backupFile.zip"

Write-InfoLine "=== Database Backup Utility ==="
Write-InfoLine "Database type : $DbType"
Write-InfoLine "Database name : $DbName"
Write-InfoLine "Backup dir    : $BackupDir"
Write-InfoLine "Backup file   : $backupFile"
Write-InfoLine "Retention     : $RetentionDays days"
Write-InfoLine "Compress      : $CompressEnabled"

# Dry run
if ($DryRun) {
    Write-InfoLine "[DRY RUN] Would create backup directory: $BackupDir"
    Write-InfoLine "[DRY RUN] Would invoke: $dumpTool ... > $backupFile"
    if ($CompressEnabled) {
        Write-InfoLine "[DRY RUN] Would compress: $backupFile -> $compressedFile"
    }
    Write-InfoLine "[DRY RUN] Would prune backups older than $RetentionDays days in $BackupDir"
    Write-AuditLine "INFO" "Dry run: planned backup $backupFile (no changes made)."
    exit 0
}

# Create backup dir
try {
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
} catch {
    Write-ErrorLine "Cannot create backup directory: '$BackupDir'."
    exit 1
}
if (-not (Test-Path -LiteralPath $BackupDir -PathType Container)) {
    Write-ErrorLine "Backup directory does not exist: '$BackupDir'."
    exit 1
}

# Resolve dump tool
if (-not (Get-Command $dumpTool -ErrorAction SilentlyContinue)) {
    Write-ErrorLine "Database dump tool not found: '$dumpTool'. Install it and retry."
    exit 1
}

# Run dump
$dumpStatus = 0
try {
    switch ($DbType) {
        "mysql" {
            $env:MYSQL_PWD = $DbPassword
            & $dumpTool "-u$DbUser" $DbName > $backupFile
            $dumpStatus = $LASTEXITCODE
            $env:MYSQL_PWD = $null
        }
        "postgresql" {
            $env:PGPASSWORD = $DbPassword
            & $dumpTool -U $DbUser -d $DbName -f $backupFile
            $dumpStatus = $LASTEXITCODE
            $env:PGPASSWORD = $null
        }
    }
} catch {
    $dumpStatus = 1
    Write-ErrorLine "EXCEPTION: $($_.Exception.Message)"
}

if ($dumpStatus -ne 0) {
    Write-ErrorLine "Database dump failed (exit $dumpStatus)."
    Write-AuditLine "ERROR" "Dump failed for $DbType/$DbName (exit $dumpStatus)."
    Remove-Item -Path $backupFile -Force -ErrorAction SilentlyContinue
    exit 2
}

Write-SuccessLine "Backup created: $backupFile"
Write-AuditLine "INFO" "Backup created: $backupFile"

# Compress
if ($CompressEnabled) {
    try {
        Compress-Archive -Path $backupFile -DestinationPath $compressedFile -Force
        Remove-Item -Path $backupFile -Force
    } catch {
        Write-ErrorLine "Compression failed for $backupFile. $($_.Exception.Message)"
        Write-AuditLine "ERROR" "Compression failed for $backupFile."
        exit 2
    }
    Write-SuccessLine "Compressed: $compressedFile"
    Write-AuditLine "INFO" "Compressed: $compressedFile"
}

# Retention pruning
$pruned = 0
$pruneFailed = 0
$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -Path $BackupDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".sql", ".zip", ".gz") } |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Force
            $pruned++
            Write-AuditLine "INFO" "Pruned old backup: $($_.FullName)"
        } catch {
            $pruneFailed++
            Write-AuditLine "WARNING" "Failed to prune: $($_.FullName)"
        }
    }

if ($pruneFailed -gt 0) {
    Write-WarningLine "Retention pruning partially failed ($pruneFailed file(s))."
    Write-AuditLine "WARNING" "Retention pruning partial failure: $pruneFailed file(s)."
}

Write-SuccessLine "Backup complete. Pruned $pruned old backup(s)."
Write-AuditLine "INFO" "Backup complete for $DbType/$DbName. Pruned $pruned old backup(s)."

if ($pruneFailed -gt 0) {
    exit 2
}
exit 0