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

# Step 4: Configure Windows for Vietnamese language, locale, and timezone
Write-Log "Step 4: Setting Windows to Vietnamese language and locale..." "INFO"

try {
    # Install Vietnamese language pack (requires internet on first run, or pre-cached)
    # Check if Vietnamese language pack is already installed
    $viLang = Get-WinUserLanguageList | Where-Object { $_.LanguageTag -eq "vi" -or $_.LanguageTag -eq "vi-VN" }

    if (-not $viLang) {
        Write-Log "Installing Vietnamese language pack (may take several minutes)..." "INFO"
        $langList = Get-WinUserLanguageList
        $langList.Add("vi-VN")
        Set-WinUserLanguageList $langList -Force
        # Trigger language pack download if online
        Install-Language -Language "vi-VN" -ErrorAction SilentlyContinue
    }

    # Set Vietnamese as the preferred display language (first in list)
    $langList = New-WinUserLanguageList "vi-VN"
    $langList.Add("en-US")
    Set-WinUserLanguageList $langList -Force
    Write-Log "Windows display language set to Vietnamese (vi-VN), English (en-US) as secondary" "SUCCESS"

    # Set region and locale to Vietnam
    Set-WinHomeLocation -GeoId 0xF1  # Vietnam
    Set-Culture "vi-VN"
    Write-Log "Region set to Vietnam, culture set to vi-VN" "SUCCESS"

    # Set timezone to Southeast Asia (UTC+7 Ho Chi Minh)
    Set-TimeZone -Id "SE Asia Standard Time"
    Write-Log "Timezone set to SE Asia Standard Time (UTC+7)" "SUCCESS"

    # Set system locale to Vietnamese (affects non-Unicode programs)
    # This requires a registry change and reboot to take effect
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language"
    Set-ItemProperty -Path $regPath -Name "Default" -Value "042A" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPath -Name "InstallLanguage" -Value "042A" -Force -ErrorAction SilentlyContinue

    $successCount++
} catch {
    Write-Log "Could not fully configure Vietnamese locale: $($_.Exception.Message)" "ERROR"
    Write-Log "You may need to set language manually: Settings > Time & Language > Language" "ERROR"
    $failCount++
}

# Create a language toggle script and desktop shortcut
Write-Log "Creating language toggle shortcut..." "INFO"

try {
    $labToolsDir2 = "C:\LabTools"
    if (-not (Test-Path $labToolsDir2)) {
        New-Item -Path $labToolsDir2 -ItemType Directory -Force | Out-Null
    }

    $toggleScript = @'
# Toggle Windows display language between Vietnamese and English
# Requires sign-out to take effect
$current = (Get-WinUserLanguageList)[0].LanguageTag

if ($current -like "vi*") {
    $langList = New-WinUserLanguageList "en-US"
    $langList.Add("vi-VN")
    Set-WinUserLanguageList $langList -Force
    $msg = "Ngôn ngữ đã chuyển sang Tiếng Anh. Đăng xuất để áp dụng.`nLanguage switched to English. Sign out to apply."
} else {
    $langList = New-WinUserLanguageList "vi-VN"
    $langList.Add("en-US")
    Set-WinUserLanguageList $langList -Force
    $msg = "Language switched to Vietnamese. Sign out to apply.`nNgôn ngữ đã chuyển sang Tiếng Việt. Đăng xuất để áp dụng."
}

Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show($msg, "Language / Ngôn ngữ", "OK", "Information")
'@

    $toggleScriptPath = Join-Path $labToolsDir2 "toggle-language.ps1"
    Set-Content -Path $toggleScriptPath -Value $toggleScript -Force

    # Create desktop shortcut
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $WshShell = New-Object -ComObject WScript.Shell
    $toggleShortcutPath = Join-Path $publicDesktop "Doi Ngon Ngu - Switch Language.lnk"
    $toggleShortcut = $WshShell.CreateShortcut($toggleShortcutPath)
    $toggleShortcut.TargetPath = "powershell.exe"
    $toggleShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$toggleScriptPath`""
    $toggleShortcut.Description = "Toggle between Vietnamese and English / Chuyển đổi giữa Tiếng Việt và Tiếng Anh"
    $toggleShortcut.Save()

    Write-Log "Language toggle shortcut created on desktop" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create language toggle: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 5: Configure Windows Magnifier for low-vision users
Write-Log "Step 5: Configuring Windows Magnifier for low-vision users..." "INFO"

try {
    # Enable Magnifier keyboard shortcut (Win+Plus) and set sensible defaults
    $magPath = "HKCU:\Software\Microsoft\ScreenMagnifier"
    if (-not (Test-Path $magPath)) {
        New-Item -Path $magPath -Force | Out-Null
    }
    # Set Magnifier to lens mode (less disorienting than full-screen for new users)
    Set-ItemProperty -Path $magPath -Name "MagnificationMode" -Value 3 -Force
    # Start at 200% zoom
    Set-ItemProperty -Path $magPath -Name "Magnification" -Value 200 -Force

    # Enable High Contrast as an available option (Win+Left Alt+Print Screen to toggle)
    $hcPath = "HKCU:\Control Panel\Accessibility\HighContrast"
    if (-not (Test-Path $hcPath)) {
        New-Item -Path $hcPath -Force | Out-Null
    }
    # Enable the keyboard shortcut for high contrast toggle
    Set-ItemProperty -Path $hcPath -Name "Flags" -Value "126" -Force

    Write-Log "Windows Magnifier defaults set (Win+Plus to launch, lens mode, 200%)" "SUCCESS"
    Write-Log "High contrast toggle enabled (Win+Left Alt+Print Screen)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure Magnifier settings: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 6: Create Calculator desktop shortcut
Write-Log "Step 6: Creating Calculator desktop shortcut..." "INFO"

try {
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $WshShell = New-Object -ComObject WScript.Shell
    $calcShortcutPath = Join-Path $publicDesktop "Calculator.lnk"
    $calcShortcut = $WshShell.CreateShortcut($calcShortcutPath)
    $calcShortcut.TargetPath = "calc.exe"
    $calcShortcut.Description = "Windows Calculator (accessible with NVDA)"
    $calcShortcut.Save()

    Write-Log "Created Calculator shortcut on public desktop" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create Calculator shortcut: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 7: Create welcome audio startup script for Student login
Write-Log "Step 7: Setting up welcome audio orientation message..." "INFO"

try {
    # Create a small PowerShell script that uses SAPI to speak a welcome message
    $welcomeScriptDir = "C:\LabTools"
    if (-not (Test-Path $welcomeScriptDir)) {
        New-Item -Path $welcomeScriptDir -ItemType Directory -Force | Out-Null
    }

    $welcomeScript = @'
# Lab Welcome Audio - plays on Student login
# Speaks through NVDA using the configured Vietnamese voice (Sao Mai VNVoice)
Start-Sleep -Seconds 8

# Use NVDA's controller client DLL to speak through NVDA's configured voice
$nvdaDll = "C:\Program Files\NVDA\lib\nvdaControllerClient64.dll"
if (-not (Test-Path $nvdaDll)) {
    $nvdaDll = "C:\Program Files (x86)\NVDA\lib\nvdaControllerClient64.dll"
}

if (Test-Path $nvdaDll) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NvdaController {
    [DllImport("$($nvdaDll.Replace('\','\\'))", CharSet = CharSet.Unicode)]
    public static extern int nvdaController_speakText(string text);
    [DllImport("$($nvdaDll.Replace('\','\\'))", CharSet = CharSet.Unicode)]
    public static extern int nvdaController_testIfRunning();
}
"@
    # Wait up to 30 seconds for NVDA to be ready
    $waited = 0
    while ($waited -lt 30) {
        if ([NvdaController]::nvdaController_testIfRunning() -eq 0) { break }
        Start-Sleep -Seconds 2
        $waited += 2
    }
    if ([NvdaController]::nvdaController_testIfRunning() -eq 0) {
        # Vietnamese welcome message:
        # "NVDA dang chay. Nhan Insert cong T de nghe tieu de cua so. Nhan Insert cong F7 de xem danh sach lien ket."
        [NvdaController]::nvdaController_speakText("NVDA đang chạy. Nhấn Insert cộng T để nghe tiêu đề cửa sổ. Nhấn Insert cộng F7 để xem danh sách liên kết.")
    }
}
'@

    $welcomeScriptPath = Join-Path $welcomeScriptDir "welcome-audio.ps1"
    Set-Content -Path $welcomeScriptPath -Value $welcomeScript -Force

    # Create a startup shortcut for the Student user profile
    # This goes in All Users startup so it runs for any user
    $allUsersStartup = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    $WshShell = New-Object -ComObject WScript.Shell
    $welcomeShortcutPath = Join-Path $allUsersStartup "LabWelcome.lnk"
    $welcomeShortcut = $WshShell.CreateShortcut($welcomeShortcutPath)
    $welcomeShortcut.TargetPath = "powershell.exe"
    $welcomeShortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$welcomeScriptPath`""
    $welcomeShortcut.Description = "Lab welcome audio orientation"
    $welcomeShortcut.WindowStyle = 7  # Minimized
    $welcomeShortcut.Save()

    Write-Log "Welcome audio script created at $welcomeScriptPath" "SUCCESS"
    Write-Log "Startup shortcut created for all users" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set up welcome audio: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 8: Create "My USB" desktop shortcut
Write-Log "Step 8: Creating 'My USB' desktop shortcut..." "INFO"

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
Write-Host "  welcome-audio $(if(Test-Path "$labToolsDir\welcome-audio.ps1"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "$labToolsDir\welcome-audio.ps1"){"Green"}else{"Red"})
Write-Host ""
Write-Host "Accessibility:" -ForegroundColor White
Write-Host "  Magnifier    Win+Plus (lens mode, 200%)" -ForegroundColor White
Write-Host "  High Contrast Win+Left Alt+Print Screen" -ForegroundColor White
Write-Host "  Calculator   Desktop shortcut" -ForegroundColor White
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
