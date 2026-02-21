# Vietnam Lab Deployment - Student USB Preparation
# Version: 1.0
# Prepares a USB drive for one student (run once per USB)
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\usb-preparation.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Student USB Preparation" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# List removable drives
$removableDrives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }

if (-not $removableDrives) {
    Write-Log "No removable drives found. Please insert a USB drive and try again." "ERROR"
    pause
    exit 1
}

Write-Host "Removable drives detected:" -ForegroundColor Yellow
foreach ($drive in $removableDrives) {
    $label = if ($drive.VolumeName) { $drive.VolumeName } else { "(no label)" }
    $sizeGB = [math]::Round($drive.Size / 1GB, 1)
    Write-Host "  $($drive.DeviceID)\ - $label ($sizeGB GB)" -ForegroundColor White
}

# Prompt for drive letter
Write-Host ""
$driveLetter = Read-Host "Enter the drive letter of the USB to prepare (e.g., E)"
$driveLetter = $driveLetter.Trim().TrimEnd(':').ToUpper()
$driveRoot = "${driveLetter}:"

# Validate the drive
$targetDrive = $removableDrives | Where-Object { $_.DeviceID -eq $driveRoot }
if (-not $targetDrive) {
    Write-Log "$driveRoot is not a removable drive. Aborting." "ERROR"
    pause
    exit 1
}

# Prompt for student number
Write-Host ""
$studentNum = Read-Host "Enter the student number (e.g., 1, 2, 15)"
$studentNum = $studentNum.Trim()

if (-not ($studentNum -match '^\d+$') -or [int]$studentNum -lt 1 -or [int]$studentNum -gt 999) {
    Write-Log "Invalid student number: '$studentNum'. Must be 1-999." "ERROR"
    pause
    exit 1
}

$studentId = "STU-{0:D3}" -f [int]$studentNum
Write-Log "Preparing USB at $driveRoot for student: $studentId" "INFO"

# Confirm
Write-Host ""
Write-Host "About to prepare USB drive $driveRoot as $studentId" -ForegroundColor Yellow

# Check current filesystem
$volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
$currentFS = if ($volume) { $volume.FileSystemType } else { "Unknown" }
$needsFormat = $currentFS -ne "NTFS"

if ($needsFormat) {
    Write-Host "  - FORMAT to NTFS (currently $currentFS) - ALL DATA WILL BE ERASED" -ForegroundColor Red
} else {
    Write-Host "  - Already NTFS - no format needed" -ForegroundColor Green
}
Write-Host "  - Set volume label to $studentId" -ForegroundColor White
Write-Host "  - Create folders: Documents, Audio, Schoolwork" -ForegroundColor White
Write-Host "  - Write hidden .student-id file" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Log "Cancelled by user." "INFO"
    pause
    exit 0
}

# Format to NTFS if needed (protects against data loss from improper ejection)
if ($needsFormat) {
    Write-Log "Formatting $driveRoot to NTFS..." "INFO"
    try {
        Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -NewFileSystemLabel $studentId -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Log "Formatted $driveRoot as NTFS with label '$studentId'" "SUCCESS"
    } catch {
        Write-Log "Format failed: $($_.Exception.Message)" "ERROR"
        Write-Log "Try formatting manually in File Explorer (right-click > Format > NTFS)" "ERROR"
        pause
        exit 1
    }
} else {
    # Already NTFS, just set volume label
    try {
        Get-Volume -DriveLetter $driveLetter | Set-Volume -NewFileSystemLabel $studentId
        Write-Log "Volume label set to '$studentId'" "SUCCESS"
    } catch {
        Write-Log "Could not set volume label: $($_.Exception.Message)" "ERROR"
        Write-Log "The .student-id file will be used as fallback identifier." "INFO"
    }
}

# Create folders
$folders = @("Documents", "Audio", "Schoolwork")
foreach ($folder in $folders) {
    $folderPath = Join-Path "$driveRoot\" $folder
    if (-not (Test-Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        Write-Log "Created folder: $folder" "SUCCESS"
    } else {
        Write-Log "Folder already exists: $folder" "INFO"
    }
}

# Write hidden .student-id file
$idFilePath = Join-Path "$driveRoot\" ".student-id"
Set-Content -Path $idFilePath -Value $studentId -Force
(Get-Item $idFilePath).Attributes = 'Hidden'
Write-Log "Created hidden .student-id file containing '$studentId'" "SUCCESS"

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "USB Preparation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Student ID:    $studentId" -ForegroundColor White
Write-Host "Drive:         $driveRoot\" -ForegroundColor White
Write-Host "Volume Label:  $studentId" -ForegroundColor White
Write-Host "Folders:       Documents, Audio, Schoolwork" -ForegroundColor White
Write-Host "ID File:       .student-id (hidden)" -ForegroundColor White
Write-Host ""
Write-Host "This USB is ready for student $studentId." -ForegroundColor Green
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

pause
