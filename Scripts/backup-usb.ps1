# Vietnam Lab - USB Backup Script
# Version: 1.0
# Runs on schedule to sync student USB drives to Google Drive via rclone
# Deployed to C:\LabTools\rclone\ by Configure-Laptop.ps1
# Last Updated: February 2026

$ErrorActionPreference = "Continue"

$labToolsDir = "C:\LabTools\rclone"
$rcloneExe = Join-Path $labToolsDir "rclone.exe"
$rcloneConf = Join-Path $labToolsDir "rclone.conf"
$logDir = Join-Path $labToolsDir "logs"
$logFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-BackupLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $logFile -Value $line
}

# Check rclone exists
if (-not (Test-Path $rcloneExe)) {
    Write-BackupLog "ERROR: rclone.exe not found at $rcloneExe"
    exit 0
}

if (-not (Test-Path $rcloneConf)) {
    Write-BackupLog "ERROR: rclone.conf not found at $rcloneConf"
    exit 0
}

# Find student USB drives
$removableDrives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }

if (-not $removableDrives) {
    Write-BackupLog "No removable drives found. Nothing to back up."
    exit 0
}

$studentDrives = @()

foreach ($drive in $removableDrives) {
    $studentId = $null

    # Check volume label first
    if ($drive.VolumeName -match '^STU-\d{3}$') {
        $studentId = $drive.VolumeName
    }

    # Fallback: check .student-id file
    if (-not $studentId) {
        $idFile = Join-Path "$($drive.DeviceID)\" ".student-id"
        if (Test-Path $idFile) {
            $fileContent = (Get-Content -Path $idFile -First 1).Trim()
            if ($fileContent -match '^STU-\d{3}$') {
                $studentId = $fileContent
            }
        }
    }

    if ($studentId) {
        $studentDrives += @{ DeviceID = $drive.DeviceID; StudentId = $studentId }
    }
}

if ($studentDrives.Count -eq 0) {
    Write-BackupLog "No student USB drives found. Nothing to back up."
    exit 0
}

Write-BackupLog "Found $($studentDrives.Count) student USB drive(s): $(($studentDrives | ForEach-Object { $_.StudentId }) -join ', ')"

# Test internet connectivity
try {
    $dns = Resolve-DnsName -Name "google.com" -Type A -DnsOnly -ErrorAction Stop
    if (-not $dns) { throw "DNS resolution returned no results" }
} catch {
    Write-BackupLog "No internet connectivity. Skipping backup."
    exit 0
}

Write-BackupLog "Internet connectivity confirmed. Starting backup..."

# Sync each student drive
$foldersToSync = @("Documents", "Audio", "Schoolwork")

foreach ($sd in $studentDrives) {
    $driveRoot = "$($sd.DeviceID)\"
    $studentId = $sd.StudentId

    Write-BackupLog "Backing up $studentId from $driveRoot"

    foreach ($folder in $foldersToSync) {
        $localPath = Join-Path $driveRoot $folder
        if (-not (Test-Path $localPath)) {
            continue
        }

        $remotePath = "gdrive:VietnamLabBackups/$studentId/$folder"

        try {
            $result = & $rcloneExe copy $localPath $remotePath --config $rcloneConf --log-level ERROR 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-BackupLog "  OK: $studentId/$folder"
            } else {
                Write-BackupLog "  WARN: $studentId/$folder - rclone exit code $LASTEXITCODE - $result"
            }
        } catch {
            Write-BackupLog "  ERROR: $studentId/$folder - $($_.Exception.Message)"
        }
    }
}

Write-BackupLog "Backup cycle complete."
exit 0
