# Vietnam Lab Deployment - Loaner Laptop Configuration
# Version: 1.0
# Run on each lab laptop after scripts 1-3. Requires Administrator.
# Deploys rclone, backup script, scheduled task, and desktop shortcut.
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\laptop-config.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Loaner Laptop Configuration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator!" "ERROR"
    Write-Host "`nPlease right-click and select 'Run as Administrator'" -ForegroundColor Red
    pause
    exit 1
}

Write-Log "=== Loaner Laptop Configuration Started on $env:COMPUTERNAME ===" "INFO"

$usbRoot = Split-Path -Parent $PSScriptRoot
$labToolsDir = "C:\LabTools\rclone"
$successCount = 0
$failCount = 0

# Step 1: Deploy rclone
Write-Log "Step 1: Deploying rclone..." "INFO"

$rcloneSource = Join-Path $usbRoot "Installers\Utilities\rclone\rclone.exe"
$rcloneConfSource = Join-Path $usbRoot "Config\rclone\rclone.conf"
$backupScriptSource = Join-Path $usbRoot "Scripts\backup-usb.ps1"

if (-not (Test-Path $labToolsDir)) {
    New-Item -Path $labToolsDir -ItemType Directory -Force | Out-Null
    Write-Log "Created directory: $labToolsDir" "INFO"
}

# Copy rclone.exe
if (Test-Path $rcloneSource) {
    Copy-Item -Path $rcloneSource -Destination $labToolsDir -Force
    Write-Log "Copied rclone.exe to $labToolsDir" "SUCCESS"
    $successCount++
} else {
    Write-Log "rclone.exe not found at $rcloneSource" "ERROR"
    Write-Log "Run 0-Download-Installers.ps1 first to download rclone." "ERROR"
    $failCount++
}

# Copy rclone.conf
if (Test-Path $rcloneConfSource) {
    Copy-Item -Path $rcloneConfSource -Destination $labToolsDir -Force
    Write-Log "Copied rclone.conf to $labToolsDir" "SUCCESS"
    $successCount++
} else {
    Write-Log "rclone.conf not found at $rcloneConfSource" "ERROR"
    Write-Log "Run Setup-Rclone-Auth.ps1 first to authorize Google Drive." "ERROR"
    $failCount++
}

# Copy backup script
if (Test-Path $backupScriptSource) {
    Copy-Item -Path $backupScriptSource -Destination $labToolsDir -Force
    Write-Log "Copied backup-usb.ps1 to $labToolsDir" "SUCCESS"
    $successCount++
} else {
    Write-Log "backup-usb.ps1 not found at $backupScriptSource" "ERROR"
    $failCount++
}

# Create logs directory
$logSubDir = Join-Path $labToolsDir "logs"
if (-not (Test-Path $logSubDir)) {
    New-Item -Path $logSubDir -ItemType Directory -Force | Out-Null
    Write-Log "Created logs directory: $logSubDir" "INFO"
}

# Step 2: Set AutoPlay for removable drives to open folder
Write-Log "Step 2: Configuring AutoPlay for removable drives..." "INFO"

try {
    $autoPlayPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers\EventHandlersDefaultSelection\StorageOnArrival"
    $autoPlayPath2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers\UserChosenExecuteHandlers\StorageOnArrival"

    # Ensure registry paths exist
    foreach ($regPath in @($autoPlayPath, $autoPlayPath2)) {
        $parentPath = Split-Path $regPath
        if (-not (Test-Path $parentPath)) {
            New-Item -Path $parentPath -Force | Out-Null
        }
    }

    # Set to open folder
    Set-ItemProperty -Path (Split-Path $autoPlayPath) -Name "StorageOnArrival" -Value "MSOpenFolder" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path (Split-Path $autoPlayPath2) -Name "StorageOnArrival" -Value "MSOpenFolder" -Force -ErrorAction SilentlyContinue

    # Also disable the AutoPlay prompt so it just opens
    $autoPlaySettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"
    Set-ItemProperty -Path $autoPlaySettings -Name "DisableAutoplay" -Value 0 -Force -ErrorAction SilentlyContinue

    Write-Log "AutoPlay set to open folder for removable drives" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure AutoPlay: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 3: Create Scheduled Task for USB backup
Write-Log "Step 3: Creating scheduled task 'LabUSBBackup'..." "INFO"

try {
    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName "LabUSBBackup" -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName "LabUSBBackup" -Confirm:$false
        Write-Log "Removed existing LabUSBBackup task" "INFO"
    }

    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$labToolsDir\backup-usb.ps1`""

    $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 15) `
        -RepetitionDuration (New-TimeSpan -Days 9999)

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited

    Register-ScheduledTask `
        -TaskName "LabUSBBackup" `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $taskPrincipal `
        -Description "Backs up student USB drives to Google Drive every 15 minutes" | Out-Null

    Write-Log "Scheduled task 'LabUSBBackup' created (runs every 15 minutes)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create scheduled task: $($_.Exception.Message)" "ERROR"
    Write-Log "You can manually create the task or run backup-usb.ps1 from $labToolsDir" "ERROR"
    $failCount++
}

# Step 4: Create "My USB" desktop shortcut
Write-Log "Step 4: Creating 'My USB' desktop shortcut..." "INFO"

try {
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcutPath = Join-Path $publicDesktop "My USB.lnk"
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "explorer.exe"
    $shortcut.Arguments = "shell:MyComputerFolder"
    $shortcut.Description = "Open This PC to access your USB drive"
    $shortcut.IconLocation = "%SystemRoot%\System32\imageres.dll,109"
    $shortcut.Save()

    Write-Log "Created 'My USB' shortcut on public desktop" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create desktop shortcut: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Loaner Laptop Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Computer:      $env:COMPUTERNAME" -ForegroundColor White
Write-Host "Successful:    $successCount" -ForegroundColor Green
Write-Host "Failed:        $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
Write-Host ""
Write-Host "Deployed to:   $labToolsDir" -ForegroundColor White
Write-Host "  rclone.exe   $(if(Test-Path "$labToolsDir\rclone.exe"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "$labToolsDir\rclone.exe"){"Green"}else{"Red"})
Write-Host "  rclone.conf  $(if(Test-Path "$labToolsDir\rclone.conf"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "$labToolsDir\rclone.conf"){"Green"}else{"Red"})
Write-Host "  backup-usb   $(if(Test-Path "$labToolsDir\backup-usb.ps1"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "$labToolsDir\backup-usb.ps1"){"Green"}else{"Red"})
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Some steps failed. Check the log and ensure:" -ForegroundColor Yellow
    Write-Host "  1. Run 0-Download-Installers.ps1 to download rclone" -ForegroundColor White
    Write-Host "  2. Run Setup-Rclone-Auth.ps1 to authorize Google Drive" -ForegroundColor White
    Write-Host "  3. Re-run this script" -ForegroundColor White
} else {
    Write-Host "This laptop is ready for student USB backups." -ForegroundColor Green
    Write-Host "USB drives labeled STU-### will auto-backup to Google Drive." -ForegroundColor White
}

Write-Host ""
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Green

pause
