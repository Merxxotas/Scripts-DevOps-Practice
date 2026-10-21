#Requires -Version 7.0

# Color setup using $PSStyle (PowerShell 7+)
$Red = $PSStyle.Foreground.Red
$Green = $PSStyle.Foreground.Green
$Yellow = $PSStyle.Foreground.Yellow
$Blue = $PSStyle.Foreground.Blue
$Reset = $PSStyle.Reset

$Threshold = 80
$Email = "admin@company.com"
$Partition = "C:"

Write-Host "$Blue=== Disk Usage Monitor ===$Reset"

# Get disk info
$Disk = Get-Volume -DriveLetter $Partition.TrimEnd(':') -ErrorAction SilentlyContinue
if (-not $Disk) {
    $Disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Partition'" 
    $Usage = [math]::Round((($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100)
} else {
    $Usage = [math]::Round((($Disk.Size - $Disk.SizeRemaining) / $Disk.Size) * 100)
}

Write-Host "Current usage: $Yellow${Usage}%$Reset"
Write-Host "Threshold: $Green${Threshold}%$Reset"

if ($Usage -gt $Threshold) {
    Write-Host "$Red`WARNING: Disk usage exceeds threshold!$Reset" -ForegroundColor Red
    $Subject = "Disk Alert $(hostname)"
    $Body = "Alert: Disk usage on $(hostname) is at ${Usage}% (threshold: ${Threshold}%)"
    
    try {
        # Configure Send-MailMessage parameters based on your SMTP server
        # Send-MailMessage -To $Email -From "alerts@company.com" -Subject $Subject -Body $Body -SmtpServer "smtp.company.com"
        Write-Host "$Green`Alert email prepared for $Email (configure SMTP server)$Reset"
    } catch {
        Write-Host "$Red`Failed to send email: $($_.Exception.Message)$Reset"
    }
} else {
    Write-Host "$Green`Disk usage is within normal limits.$Reset"
}