#Requires -Version 5.1

param(
    [string]$LogDirectory = "C:\Logs",
    [int]$Days = 30,
    [switch]$DryRun
)

$Colors = @{
    Red = "`e[31m"
    Green = "`e[32m"
    Yellow = "`e[33m"
    Blue = "`e[34m"
    Cyan = "`e[36m"
    Reset = "`e[0m"
}

Write-Host "$($Colors.Blue)=== Log Cleanup Utility ===$($Colors.Reset)"
Write-Host "Target directory: $($Colors.Cyan)$LogDirectory$($Colors.Reset)"
Write-Host "Delete files older than: $($Colors.Yellow)$Days days$($Colors.Reset)"
Write-Host "Dry run mode: $($Colors.Cyan)$DryRun$($Colors.Reset)"

if (-not (Test-Path $LogDirectory)) {
    Write-Host "$($Colors.Red)Error: Directory $LogDirectory does not exist$($Colors.Reset)"
    exit 1
}

$CutoffDate = (Get-Date).AddDays(-$Days)
$Files = Get-ChildItem -Path $LogDirectory -Filter "*.log" -File | Where-Object { $_.LastWriteTime -lt $CutoffDate }

foreach ($File in $Files) {
    $SizeMB = [math]::Round($File.Length / 1MB, 2)
    
    if ($DryRun) {
        Write-Host "$($Colors.Yellow)[DRY RUN]$($Colors.Reset) Would delete: $($File.Name) (${SizeMB}MB)"
    } else {
        Write-Host "$($Colors.Red)Deleting:$($Colors.Reset) $($File.Name) (${SizeMB}MB)"
        try {
            Remove-Item $File.FullName -Force
            Write-Host "$($Colors.Green)✓ Deleted successfully$($Colors.Reset)"
        } catch {
            Write-Host "$($Colors.Red)✗ Failed to delete: $($_.Exception.Message)$($Colors.Reset)"
        }
    }
}

Write-Host "`n$($Colors.Green)Cleanup operation completed.$($Colors.Reset)"