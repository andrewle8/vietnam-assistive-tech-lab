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
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

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
    # Install Vietnamese language pack and Features on Demand
    # Prefers offline .cab files from 0.6-Download-LanguagePack.ps1 (extracted from Microsoft LOF ISO)
    # Falls back to online Install-Language if no cabs available
    $viLang = Get-WinUserLanguageList | Where-Object { $_.LanguageTag -eq "vi" -or $_.LanguageTag -eq "vi-VN" }

    if (-not $viLang) {
        Write-Log "Installing Vietnamese language pack (may take several minutes)..." "INFO"

        $usbRoot = Split-Path -Parent $PSScriptRoot
        $langPackDir = Join-Path $usbRoot "Installers\LanguagePacks"
        # Accept either full Client language pack or LIP (Language Interface Pack)
        $cabPath = Join-Path $langPackDir "Microsoft-Windows-Client-Language-Pack_x64_vi-vn.cab"
        if (-not (Test-Path $cabPath)) {
            $cabPath = Join-Path $langPackDir "Microsoft-Windows-Lip-Language-Pack_x64_vi-vn.cab"
        }

        if (Test-Path $cabPath) {
            Write-Log "Found offline language pack: $langPackDir" "INFO"

            # Install the main language pack cab
            Write-Log "Installing base language pack via DISM..." "INFO"
            $dismResult = & DISM /Online /Add-Package /PackagePath:"$cabPath" /NoRestart /Quiet 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Base language pack installed" "SUCCESS"
            } else {
                Write-Log "DISM Add-Package returned exit code $LASTEXITCODE (may already be installed)" "INFO"
            }

            # Install language Features on Demand (Basic, TextToSpeech, OCR, etc.)
            # Language Features on Demand (Handwriting not available for vi-VN)
            $fodCapabilities = @(
                "Language.Basic~~~vi-VN~0.0.1.0",
                "Language.OCR~~~vi-VN~0.0.1.0",
                "Language.TextToSpeech~~~vi-VN~0.0.1.0"
            )

            foreach ($capability in $fodCapabilities) {
                $capName = ($capability -split '~~~')[0]
                Write-Log "Installing $capName..." "INFO"
                $dismResult = & DISM /Online /Add-Capability /CapabilityName:$capability /Source:"$langPackDir" /LimitAccess /NoRestart /Quiet 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "$capName installed" "SUCCESS"
                } else {
                    Write-Log "$capName returned exit code $LASTEXITCODE (may already be installed or not available)" "INFO"
                }
            }

            Write-Log "Vietnamese language pack installed from offline cabs" "SUCCESS"
        } else {
            Write-Log "No offline cabs found at $langPackDir. Trying Install-Language (requires internet)..." "ERROR"
            try {
                Install-Language -Language "vi-VN" -ErrorAction Stop
            } catch {
                Write-Log "Install-Language failed (no internet?): $($_.Exception.Message)" "ERROR"
                Write-Log "Vietnamese language pack NOT installed. Run 0.6-Download-LanguagePack.ps1 on setup PC first." "ERROR"
            }
        }

        $langList = Get-WinUserLanguageList
        $langList.Add("vi-VN")
        Set-WinUserLanguageList $langList -Force
    }

    # Prevent Windows from auto-removing the language pack
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\MUI\" -TaskName "LPRemove" -ErrorAction SilentlyContinue
    Disable-ScheduledTask -TaskPath "\Microsoft\Windows\LanguageComponentsInstaller" -TaskName "Uninstallation" -ErrorAction SilentlyContinue
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "BlockCleanupOfUnusedPreinstalledLangPacks" /t REG_DWORD /d 1 /f 2>$null | Out-Null

    # Set Vietnamese as the preferred display language (first in list)
    $langList = New-WinUserLanguageList "vi-VN"
    $langList.Add("en-US")
    Set-WinUserLanguageList $langList -Force
    Write-Log "Windows display language set to Vietnamese (vi-VN), English (en-US) as secondary" "SUCCESS"

    # Set region and locale to Vietnam
    Set-WinHomeLocation -GeoId 0xFB  # Vietnam (251)
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
    # Set Magnifier to full-screen mode (better for keyboard-primary users like blind/low-vision)
    Set-ItemProperty -Path $magPath -Name "MagnificationMode" -Value 1 -Force
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

# Step 9: Volume safety limit for children's hearing
Write-Log "Step 9: Setting volume safety limit..." "INFO"

try {
    # Cap system volume at 70% to protect children's hearing (ATH-M40x are 98dB sensitivity)
    # Create a startup script that resets volume to 70% on each login
    $volumeScript = @'
# Reset system volume to safe level for children on each login
# ATH-M40x headphones at full volume can exceed safe levels for children
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int _0(); int _1(); int _2(); int _3(); int _4(); int _5(); int _6(); int _7(); int _8(); int _9(); int _10(); int _11();
    int SetMasterVolumeLevelScalar(float fLevel, System.Guid pguidEventContext);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, int clsCtx, int activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
"@
try {
    $enumerator = New-Object MMDeviceEnumerator
    $device = $null
    $enumerator.GetDefaultAudioEndpoint(0, 1, [ref]$device)
    $iid = [Guid]"5CDF2C82-841E-4546-9722-0CF74078229A"
    $volume = $null
    $device.Activate([ref]$iid, 1, 0, [ref]$volume)
    # Set to 70% max (0.7 = 70%)
    $volume.SetMasterVolumeLevelScalar(0.70, [Guid]::Empty)
} catch {}
'@

    $volumeScriptPath = Join-Path "C:\LabTools" "reset-volume.ps1"
    Set-Content -Path $volumeScriptPath -Value $volumeScript -Force

    # Add to All Users startup
    $allUsersStartup = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    $WshShell = New-Object -ComObject WScript.Shell
    $volShortcutPath = Join-Path $allUsersStartup "LabVolumeReset.lnk"
    $volShortcut = $WshShell.CreateShortcut($volShortcutPath)
    $volShortcut.TargetPath = "powershell.exe"
    $volShortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$volumeScriptPath`""
    $volShortcut.Description = "Reset volume to safe level"
    $volShortcut.WindowStyle = 7
    $volShortcut.Save()

    Write-Log "Volume safety limit set (70% on each login)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set volume limit: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 10: Disable Windows Update (offline machines, prevents unexpected reboots)
Write-Log "Step 10: Disabling Windows Update..." "INFO"

try {
    # Disable Windows Update service
    Set-Service -Name "wuauserv" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue

    # Disable Windows Update Medic Service (re-enables Windows Update)
    Set-Service -Name "WaaSMedicSvc" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "WaaSMedicSvc" -Force -ErrorAction SilentlyContinue

    # Disable Update Orchestrator Service
    Set-Service -Name "UsoSvc" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "UsoSvc" -Force -ErrorAction SilentlyContinue

    Write-Log "Windows Update services disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Windows Update: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 11: Disable non-essential notifications
Write-Log "Step 11: Disabling non-essential notifications..." "INFO"

try {
    # Disable tips, suggestions, and Get Started notifications
    $contentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (Test-Path $contentDelivery) {
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338389Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-310093Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338393Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SoftLandingEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SystemPaneSuggestionsEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Disable Windows Defender notifications (offline machines don't need antivirus alerts)
    $defenderNotify = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    if (-not (Test-Path $defenderNotify)) {
        New-Item -Path $defenderNotify -Force | Out-Null
    }
    Set-ItemProperty -Path $defenderNotify -Name "DisableNotifications" -Value 1 -Force

    # Disable notification center suggestions
    $pushNotify = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $pushNotify)) {
        New-Item -Path $pushNotify -Force | Out-Null
    }
    Set-ItemProperty -Path $pushNotify -Name "ToastEnabled" -Value 1 -Force  # Keep toast but disable suggestions

    Write-Log "Non-essential notifications disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable notifications: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 11b: Disable Windows system sounds (reduces audio clutter that interferes with NVDA speech)
Write-Log "Step 11b: Disabling Windows system sounds..." "INFO"

try {
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes" -Name "(Default)" -Value ".None" -Force
    Write-Log "Windows system sounds disabled (reduces interference with NVDA)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable system sounds: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 12: Disable Narrator shortcut (prevents dual screen reader conflict)
Write-Log "Step 12: Disabling Narrator auto-start shortcut..." "INFO"

try {
    # Disable the Win+Ctrl+Enter shortcut for Narrator to prevent accidental activation
    $narratorPath = "HKCU:\Software\Microsoft\Narrator\NoRoam"
    if (-not (Test-Path $narratorPath)) {
        New-Item -Path $narratorPath -Force | Out-Null
    }
    # Disable Narrator from starting with the shortcut
    Set-ItemProperty -Path $narratorPath -Name "WinEnterLaunchEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

    # Also disable via Ease of Access settings
    $easeAccess = "HKCU:\Software\Microsoft\Ease of Access"
    if (-not (Test-Path $easeAccess)) {
        New-Item -Path $easeAccess -Force | Out-Null
    }
    Set-ItemProperty -Path $easeAccess -Name "selfvoice.ManualStart" -Value 1 -Force -ErrorAction SilentlyContinue

    Write-Log "Narrator shortcut disabled (prevents NVDA conflict)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Narrator shortcut: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 13: Deploy Firefox policies (homepage, disable updates, Vietnamese locale)
Write-Log "Step 13: Deploying Firefox enterprise policies..." "INFO"

try {
    $firefoxDistDir = "C:\Program Files\Mozilla Firefox\distribution"
    if (-not (Test-Path $firefoxDistDir)) {
        New-Item -Path $firefoxDistDir -ItemType Directory -Force | Out-Null
        Write-Log "Created directory: $firefoxDistDir" "INFO"
    }

    $policiesSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\firefox-profile\policies.json"
    if (Test-Path $policiesSource) {
        Copy-Item -Path $policiesSource -Destination "$firefoxDistDir\policies.json" -Force
        Write-Log "Firefox policies.json deployed to $firefoxDistDir" "SUCCESS"
        $successCount++
    } else {
        Write-Log "policies.json not found at $policiesSource" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy Firefox policies: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 14: Disable Sticky Keys / Filter Keys popups (confusing for blind users)
Write-Log "Step 14: Disabling Sticky Keys and Filter Keys popups..." "INFO"

try {
    # Disable Sticky Keys popup (triggered by pressing Shift 5 times)
    $stickyKeysPath = "HKCU:\Control Panel\Accessibility\StickyKeys"
    if (-not (Test-Path $stickyKeysPath)) {
        New-Item -Path $stickyKeysPath -Force | Out-Null
    }
    Set-ItemProperty -Path $stickyKeysPath -Name "Flags" -Value "506" -Force

    # Disable Filter Keys popup (triggered by holding a key)
    $filterKeysPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"
    if (-not (Test-Path $filterKeysPath)) {
        New-Item -Path $filterKeysPath -Force | Out-Null
    }
    Set-ItemProperty -Path $filterKeysPath -Name "Flags" -Value "122" -Force

    # Enable Toggle Keys beep (useful audio feedback for blind users - Caps/Num/Scroll Lock)
    $toggleKeysPath = "HKCU:\Control Panel\Accessibility\ToggleKeys"
    if (-not (Test-Path $toggleKeysPath)) {
        New-Item -Path $toggleKeysPath -Force | Out-Null
    }
    Set-ItemProperty -Path $toggleKeysPath -Name "Flags" -Value "63" -Force

    Write-Log "Sticky Keys popup disabled, Filter Keys popup disabled, Toggle Keys beep enabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure accessibility key settings: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 15: Power settings (no sleep when plugged in, no hibernate)
Write-Log "Step 15: Configuring power settings..." "INFO"

try {
    # Set display timeout to 30 minutes on AC, 15 on battery
    powercfg /change monitor-timeout-ac 30
    powercfg /change monitor-timeout-dc 15
    # Disable sleep when plugged in, 30 min on battery
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 30
    # Disable hibernate entirely
    powercfg /hibernate off
    # Set lid close to do nothing (AC and battery)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
    powercfg /setactive SCHEME_CURRENT

    Write-Log "Power settings configured (no sleep on AC, no hibernate)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure power settings: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 16: Create NVDA config backup and restore script
Write-Log "Step 16: Creating NVDA config backup/restore..." "INFO"

try {
    $backupDir = "C:\LabTools\nvda-backup"
    $nvdaConfigDir = Join-Path $env:APPDATA "nvda"

    # Backup current (known good) NVDA config
    if (Test-Path $nvdaConfigDir) {
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$nvdaConfigDir\*" -Destination $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "NVDA config backed up to $backupDir" "SUCCESS"
    }

    # Create restore script
    $restoreScript = @'
# NVDA Config Restore - Restores NVDA to known good configuration
# Run this if NVDA stops speaking Vietnamese or has wrong settings
$backupDir = "C:\LabTools\nvda-backup"
$nvdaConfigDir = Join-Path $env:APPDATA "nvda"

if (Test-Path $backupDir) {
    # Stop NVDA
    $nvda = Get-Process nvda -ErrorAction SilentlyContinue
    if ($nvda) { Stop-Process -Name nvda -Force; Start-Sleep -Seconds 2 }

    # Restore config
    Copy-Item -Path "$backupDir\*" -Destination $nvdaConfigDir -Recurse -Force

    # Restart NVDA
    $nvdaExe = "C:\Program Files\NVDA\nvda.exe"
    if (-not (Test-Path $nvdaExe)) { $nvdaExe = "C:\Program Files (x86)\NVDA\nvda.exe" }
    if (Test-Path $nvdaExe) { Start-Process -FilePath $nvdaExe }

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("NVDA da duoc khoi phuc cai dat goc.`nNVDA has been restored to default settings.", "NVDA Restore", "OK", "Information")
} else {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Khong tim thay ban sao luu NVDA.`nNVDA backup not found.", "Error", "OK", "Error")
}
'@

    $restoreScriptPath = "C:\LabTools\restore-nvda.ps1"
    Set-Content -Path $restoreScriptPath -Value $restoreScript -Force

    # Create desktop shortcut
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $WshShell = New-Object -ComObject WScript.Shell
    $restoreShortcutPath = Join-Path $publicDesktop "Khoi Phuc NVDA - Restore NVDA.lnk"
    $restoreShortcut = $WshShell.CreateShortcut($restoreShortcutPath)
    $restoreShortcut.TargetPath = "powershell.exe"
    $restoreShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$restoreScriptPath`""
    $restoreShortcut.Description = "Restore NVDA to default configuration / Khôi phục cài đặt NVDA"
    $restoreShortcut.Save()

    Write-Log "NVDA restore shortcut created on desktop" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create NVDA backup/restore: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 17: Create Vietnamese-labeled desktop folders
Write-Log "Step 17: Creating Vietnamese desktop folders..." "INFO"

try {
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $studentDocs = "C:\Users\Public\Documents"

    $viFolders = @(
        @{ Name = "Tai Lieu"; Desc = "Tài Liệu - Documents" },
        @{ Name = "Am Nhac"; Desc = "Âm Nhạc - Music" },
        @{ Name = "Truyen"; Desc = "Truyện - Stories" },
        @{ Name = "Hoc Tap"; Desc = "Học Tập - Study" },
        @{ Name = "Tro Choi"; Desc = "Trò Chơi - Games" }
    )

    foreach ($folder in $viFolders) {
        $folderPath = Join-Path $studentDocs $folder.Name
        if (-not (Test-Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        }

        # Create desktop shortcut to each folder
        $WshShell = New-Object -ComObject WScript.Shell
        $folderShortcutPath = Join-Path $publicDesktop "$($folder.Name).lnk"
        $folderShortcut = $WshShell.CreateShortcut($folderShortcutPath)
        $folderShortcut.TargetPath = $folderPath
        $folderShortcut.Description = $folder.Desc
        $folderShortcut.Save()
    }

    Write-Log "Vietnamese desktop folders created (Tai Lieu, Am Nhac, Truyen, Hoc Tap, Tro Choi)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create Vietnamese folders: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 18: Deploy Update Agent
Write-Log "Step 18: Deploying auto-update agent..." "INFO"

try {
    $updateAgentDir = "C:\LabTools\update-agent"
    foreach ($subDir in @($updateAgentDir, "$updateAgentDir\staging", "$updateAgentDir\rollback", "$updateAgentDir\results", "$updateAgentDir\logs")) {
        if (-not (Test-Path $subDir)) {
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null
        }
    }

    # Copy update agent script
    $agentSource = Join-Path $PSScriptRoot "Update-Agent.ps1"
    if (Test-Path $agentSource) {
        Copy-Item -Path $agentSource -Destination "$updateAgentDir\Update-Agent.ps1" -Force
        Write-Log "Copied Update-Agent.ps1 to $updateAgentDir" "SUCCESS"
    }

    # Copy audit script for post-install verification
    $auditSource = Join-Path $PSScriptRoot "7-Audit.ps1"
    if (Test-Path $auditSource) {
        Copy-Item -Path $auditSource -Destination "$updateAgentDir\7-Audit.ps1" -Force
    }

    # Copy local manifest for version tracking
    $manifestSource = Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"
    if (Test-Path $manifestSource) {
        Copy-Item -Path $manifestSource -Destination "C:\LabTools\manifest.json" -Force
        Write-Log "Deployed manifest.json to C:\LabTools\" "SUCCESS"
    }

    # Register LabUpdateAgent scheduled task
    $existingTask = Get-ScheduledTask -TaskName "LabUpdateAgent" -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName "LabUpdateAgent" -Confirm:$false
    }

    # Random offset per PC (0-120 min) based on PC number to spread load
    $pcNum = 0
    if ($env:COMPUTERNAME -match "PC-(\d+)") { $pcNum = [int]$Matches[1] }
    $randomDelay = New-TimeSpan -Minutes ($pcNum * 6)  # PC-01=6min, PC-19=114min

    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$updateAgentDir\Update-Agent.ps1`""

    $taskTrigger = New-ScheduledTaskTrigger -Daily -At "02:00" -RandomDelay $randomDelay

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask `
        -TaskName "LabUpdateAgent" `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $taskPrincipal `
        -Description "Checks for and applies software updates from GitHub (daily 2-4 AM)" | Out-Null

    Write-Log "Scheduled task 'LabUpdateAgent' created (daily at 2 AM + ${pcNum}x6 min offset)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not deploy update agent: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 19: Deploy Fleet Health Reporter
Write-Log "Step 19: Deploying fleet health reporter..." "INFO"

try {
    # Copy fleet health script
    $healthSource = Join-Path $PSScriptRoot "Report-FleetHealth.ps1"
    if (Test-Path $healthSource) {
        Copy-Item -Path $healthSource -Destination "C:\LabTools\Report-FleetHealth.ps1" -Force
        Write-Log "Copied Report-FleetHealth.ps1 to C:\LabTools\" "SUCCESS"
    }

    # Register LabFleetReport scheduled task
    $existingTask = Get-ScheduledTask -TaskName "LabFleetReport" -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName "LabFleetReport" -Confirm:$false
    }

    # Stagger by PC number: PC-01 at 03:00, PC-02 at 03:05, etc.
    $reportTime = "03:00"
    if ($env:COMPUTERNAME -match "PC-(\d+)") {
        $offset = ([int]$Matches[1] - 1) * 5
        $reportTime = (Get-Date "03:00").AddMinutes($offset).ToString("HH:mm")
    }

    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"C:\LabTools\Report-FleetHealth.ps1`""

    $taskTrigger = New-ScheduledTaskTrigger -Daily -At $reportTime

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask `
        -TaskName "LabFleetReport" `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $taskPrincipal `
        -Description "Uploads health report to Google Drive (daily at $reportTime)" | Out-Null

    Write-Log "Scheduled task 'LabFleetReport' created (daily at $reportTime)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not deploy fleet reporter: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 20: Create LabAdmin account for remote troubleshooting and local maintenance
Write-Log "Step 20: Creating LabAdmin account..." "INFO"

try {
    $adminExists = Get-LocalUser -Name "LabAdmin" -ErrorAction SilentlyContinue
    if (-not $adminExists) {
        $adminPassword = ConvertTo-SecureString "monarch" -AsPlainText -Force
        New-LocalUser -Name "LabAdmin" -Password $adminPassword -FullName "Lab Administrator" -Description "Admin - remote mgmt and maintenance" -ErrorAction Stop
        Add-LocalGroupMember -Group "Administrators" -Member "LabAdmin" -ErrorAction SilentlyContinue
        Write-Log "Created LabAdmin account (local administrator)" "SUCCESS"
    } else {
        Write-Log "LabAdmin account already exists" "INFO"
    }

    # Set password to never expire
    Set-LocalUser -Name "LabAdmin" -PasswordNeverExpires $true -ErrorAction SilentlyContinue

    $successCount++
} catch {
    Write-Log "Could not create LabAdmin account: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 21: Create Student account with auto-login
Write-Log "Step 21: Creating Student account with auto-login..." "INFO"

try {
    # Create local Student account (no password, standard user)
    $studentExists = Get-LocalUser -Name "Student" -ErrorAction SilentlyContinue
    if (-not $studentExists) {
        New-LocalUser -Name "Student" -NoPassword -FullName "Student" -Description "Lab student account" -ErrorAction Stop
        Add-LocalGroupMember -Group "Users" -Member "Student" -ErrorAction SilentlyContinue
        Write-Log "Created local Student account (no password, standard user)" "SUCCESS"
    } else {
        Write-Log "Student account already exists" "INFO"
    }

    # Set password to never expire
    Set-LocalUser -Name "Student" -PasswordNeverExpires $true -ErrorAction SilentlyContinue

    # Configure auto-login for Student account
    $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon" -Value "1" -Force
    Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName" -Value "Student" -Force
    Set-ItemProperty -Path $winlogonPath -Name "DefaultPassword" -Value "" -Force

    Write-Log "Auto-login configured for Student account" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create Student account: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 22: Enable OpenSSH Server for remote management
Write-Log "Step 22: Enabling OpenSSH Server..." "INFO"

try {
    # Install OpenSSH Server if not already present
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        Write-Log "OpenSSH Server installed" "INFO"
    } else {
        Write-Log "OpenSSH Server already installed" "INFO"
    }

    # Start and enable the service
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic

    # Ensure firewall rule exists
    $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $fwRule) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
            -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }

    # Set default shell to PowerShell
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

    Write-Log "OpenSSH Server enabled (auto-start, PowerShell default shell)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not enable OpenSSH Server: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 23: Generate battery health report
Write-Log "Step 23: Generating battery health report..." "INFO"

try {
    $batteryReport = "C:\LabTools\battery-report.htm"
    powercfg /batteryreport /output $batteryReport 2>&1 | Out-Null
    if (Test-Path $batteryReport) {
        Write-Log "Battery report saved to $batteryReport" "SUCCESS"
    } else {
        Write-Log "Battery report generated (check C:\LabTools\)" "SUCCESS"
    }
    $successCount++
} catch {
    Write-Log "Could not generate battery report: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 24: Remove bloatware apps (reduces clutter for NVDA screen reader users)
Write-Log "Step 23: Removing bloatware apps..." "INFO"

try {
    $bloatPackages = @(
        "Microsoft.BingNews"
        "Microsoft.BingWeather"
        "Microsoft.GamingApp"
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.People"
        "Microsoft.Todos"
        "Microsoft.PowerAutomateDesktop"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.YourPhone"
        "MicrosoftCorporationII.MicrosoftFamily"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "Microsoft.549981C3F5F10"
        "Clipchamp.Clipchamp"
        "MicrosoftTeams"
        "Microsoft.MicrosoftStickyNotes"
        "Microsoft.WindowsAlarms"
        "microsoft.windowscommunicationsapps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.3DBuilder"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.Paint3D"
    )

    $removedCount = 0
    foreach ($pkg in $bloatPackages) {
        # Remove for all users
        Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        # Remove provisioned (prevents reinstall for new users)
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object DisplayName -eq $pkg |
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        $removedCount++
    }

    Write-Log "Bloatware removal complete ($removedCount packages processed)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not remove bloatware: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 25: Remove OneDrive (offline machines, nag popups confuse NVDA)
Write-Log "Step 25: Removing OneDrive..." "INFO"

try {
    # Stop OneDrive process
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Uninstall OneDrive (try 64-bit path first, then 32-bit)
    $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    }
    if (Test-Path $oneDriveSetup) {
        Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
        Write-Log "OneDrive uninstalled" "INFO"
    }

    # Remove leftover folders
    $oneDriveFolders = @(
        "$env:USERPROFILE\OneDrive"
        "$env:LOCALAPPDATA\Microsoft\OneDrive"
        "$env:PROGRAMDATA\Microsoft OneDrive"
        "C:\OneDriveTemp"
    )
    foreach ($folder in $oneDriveFolders) {
        if (Test-Path $folder) {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove OneDrive from Explorer sidebar
    $oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $oneDrivePolicy)) { New-Item -Path $oneDrivePolicy -Force | Out-Null }
    Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -Force

    # Remove scheduled tasks
    Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match 'OneDrive' } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    Write-Log "OneDrive removed and disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not remove OneDrive: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 26: Disable Widgets, Cortana, and Search Highlights
Write-Log "Step 26: Disabling Widgets, Cortana, and Search Highlights..." "INFO"

try {
    # Disable Widgets
    $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $dshPath)) { New-Item -Path $dshPath -Force | Out-Null }
    Set-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -Value 0 -Force

    # Disable Cortana
    $searchPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    Set-ItemProperty -Path $searchPath -Name "AllowCortana" -Value 0 -Force

    # Disable Search Highlights (visual clutter in Start menu)
    $searchSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
    if (-not (Test-Path $searchSettings)) { New-Item -Path $searchSettings -Force | Out-Null }
    Set-ItemProperty -Path $searchSettings -Name "IsDynamicSearchBoxEnabled" -Value 0 -Force

    # Disable web search in Start menu
    $explorerPolicies = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $explorerPolicies)) { New-Item -Path $explorerPolicies -Force | Out-Null }
    Set-ItemProperty -Path $explorerPolicies -Name "DisableSearchBoxSuggestions" -Value 1 -Force

    Write-Log "Widgets, Cortana, and Search Highlights disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Widgets/Cortana/Search: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 27: Neuter Microsoft Edge (remove shortcuts, disable auto-start)
Write-Log "Step 27: Neutering Microsoft Edge..." "INFO"

try {
    # Remove Edge desktop shortcuts
    $desktopPaths = @(
        [Environment]::GetFolderPath("CommonDesktopDirectory")
        [Environment]::GetFolderPath("Desktop")
    )
    foreach ($desktop in $desktopPaths) {
        $edgeShortcut = Join-Path $desktop "Microsoft Edge.lnk"
        if (Test-Path $edgeShortcut) {
            Remove-Item -Path $edgeShortcut -Force -ErrorAction SilentlyContinue
        }
    }

    # Disable Edge first-run experience and background behavior
    $edgePolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicies)) { New-Item -Path $edgePolicies -Force | Out-Null }
    Set-ItemProperty -Path $edgePolicies -Name "HideFirstRunExperience" -Value 1 -Force
    Set-ItemProperty -Path $edgePolicies -Name "StartupBoostEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "BackgroundModeEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "ComponentUpdatesEnabled" -Value 0 -Force

    # Prevent Edge from stealing default browser
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingsCampaignEnabled" -Value 0 -Force

    # Remove Edge from startup (wildcards don't work in Remove-ItemProperty, so enumerate first)
    Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Property |
        Where-Object { $_ -like "MicrosoftEdgeAutoLaunch*" } |
        ForEach-Object {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $_ -Force -ErrorAction SilentlyContinue
        }

    Write-Log "Microsoft Edge neutered (shortcuts removed, auto-start disabled)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not neuter Microsoft Edge: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 28: Clean taskbar (remove clutter, keep only essentials)
Write-Log "Step 28: Cleaning taskbar..." "INFO"

try {
    $taskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    # Hide Chat icon (Teams consumer)
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarMn" -Value 0 -Force
    # Hide Task View button
    Set-ItemProperty -Path $taskbarPath -Name "ShowTaskViewButton" -Value 0 -Force
    # Hide Widgets button
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarDa" -Value 0 -Force
    # Hide Copilot button (Win11 23H2+)
    Set-ItemProperty -Path $taskbarPath -Name "ShowCopilotButton" -Value 0 -Force -ErrorAction SilentlyContinue

    # Hide Search box from taskbar
    $searchRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $searchRegPath)) { New-Item -Path $searchRegPath -Force | Out-Null }
    Set-ItemProperty -Path $searchRegPath -Name "SearchboxTaskbarMode" -Value 0 -Force

    # Clear pinned taskbar items (Win11 stores these as shortcut files, not registry)
    $pinnedPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $pinnedPath) {
        Get-ChildItem -Path $pinnedPath -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*File Explorer*" } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Also clear the Win10-era Taskband registry (in case it's used)
    $taskband = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    if (Test-Path $taskband) {
        Remove-ItemProperty -Path $taskband -Name "Favorites" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $taskband -Name "FavoritesResolve" -Force -ErrorAction SilentlyContinue
    }

    # Restart Explorer to apply changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer

    Write-Log "Taskbar cleaned (pins removed, Chat/Task View/Search/Widgets/Copilot hidden)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not clean taskbar: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 29: Reduce telemetry (offline machines, no need to phone home)
Write-Log "Step 29: Reducing telemetry..." "INFO"

try {
    # Set telemetry to Security level (minimum)
    $dataCollection = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $dataCollection)) { New-Item -Path $dataCollection -Force | Out-Null }
    Set-ItemProperty -Path $dataCollection -Name "AllowTelemetry" -Value 0 -Force

    # Disable advertising ID
    $adInfo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (-not (Test-Path $adInfo)) { New-Item -Path $adInfo -Force | Out-Null }
    Set-ItemProperty -Path $adInfo -Name "Enabled" -Value 0 -Force

    # Disable activity history
    $systemPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $systemPolicies)) { New-Item -Path $systemPolicies -Force | Out-Null }
    Set-ItemProperty -Path $systemPolicies -Name "EnableActivityFeed" -Value 0 -Force
    Set-ItemProperty -Path $systemPolicies -Name "PublishUserActivities" -Value 0 -Force
    Set-ItemProperty -Path $systemPolicies -Name "UploadUserActivities" -Value 0 -Force

    # Disable Connected User Experiences and Telemetry service
    Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue

    # Disable WAP Push Message Routing
    Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue

    Write-Log "Telemetry reduced to minimum" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not reduce telemetry: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 30: Additional UX cleanup (Game Bar, Snap Layouts, OOBE nag, etc.)
Write-Log "Step 30: Additional UX cleanup..." "INFO"

try {
    # Disable Xbox Game Bar (Win+G accidental activation confuses NVDA)
    $gameBar = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gameBar)) { New-Item -Path $gameBar -Force | Out-Null }
    Set-ItemProperty -Path $gameBar -Name "UseNexusForGameBarEnabled" -Value 0 -Force
    $gameDVR = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $gameDVR)) { New-Item -Path $gameDVR -Force | Out-Null }
    Set-ItemProperty -Path $gameDVR -Name "GameDVR_Enabled" -Value 0 -Force
    $gameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDVRPolicy)) { New-Item -Path $gameDVRPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRPolicy -Name "AllowGameDVR" -Value 0 -Force

    # Disable Snap Layouts hover tooltip (unexpected NVDA reads on maximize button)
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0 -Force

    # Disable "Let's finish setting up your device" OOBE nag
    $contentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $userProfileEngagement = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
    if (-not (Test-Path $userProfileEngagement)) { New-Item -Path $userProfileEngagement -Force | Out-Null }
    Set-ItemProperty -Path $userProfileEngagement -Name "ScoobeSystemSettingEnabled" -Value 0 -Force

    # Disable Start menu suggestions / promoted apps
    if (Test-Path $contentDelivery) {
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338388Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-353694Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-353696Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "OemPreInstalledAppsEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "PreInstalledAppsEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "SilentInstalledAppsEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Disable lock screen tips and trivia
    if (Test-Path $contentDelivery) {
        Set-ItemProperty -Path $contentDelivery -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $contentDelivery -Name "RotatingLockScreenEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Disable touch keyboard auto-show (physical keyboards only)
    $touchKB = "HKCU:\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path $touchKB)) { New-Item -Path $touchKB -Force | Out-Null }
    Set-ItemProperty -Path $touchKB -Name "TipbandDesiredVisibility" -Value 0 -Force

    Write-Log "Additional UX cleanup complete (Game Bar, Snap Layouts, OOBE nag, Start suggestions, lock screen tips, touch keyboard)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not complete UX cleanup: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 31: Deploy VLC accessibility config (audio-only mode, NVDA-friendly)
Write-Log "Step 31: Deploying VLC accessibility config..." "INFO"

try {
    $studentProfile = "C:\Users\Student"
    $currentProfile = $env:USERPROFILE
    $profileBase = if (Test-Path $studentProfile) { $studentProfile } else { $currentProfile }

    $vlcConfigDir = Join-Path $profileBase "AppData\Roaming\vlc"
    if (-not (Test-Path $vlcConfigDir)) {
        New-Item -Path $vlcConfigDir -ItemType Directory -Force | Out-Null
    }

    $vlcSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\vlc-config\vlcrc"
    if (Test-Path $vlcSource) {
        Copy-Item -Path $vlcSource -Destination "$vlcConfigDir\vlcrc" -Force
        Write-Log "VLC config deployed to $vlcConfigDir (audio-only, NVDA-friendly)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "VLC config not found at $vlcSource" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy VLC config: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 32: Deploy Audacity accessibility config (MME audio, no splash, beep on completion)
Write-Log "Step 32: Deploying Audacity accessibility config..." "INFO"

try {
    $profileBase = if (Test-Path "C:\Users\Student") { "C:\Users\Student" } else { $env:USERPROFILE }

    $audacityConfigDir = Join-Path $profileBase "AppData\Roaming\audacity"
    if (-not (Test-Path $audacityConfigDir)) {
        New-Item -Path $audacityConfigDir -ItemType Directory -Force | Out-Null
    }

    $audacitySource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\audacity-config\audacity.cfg"
    if (Test-Path $audacitySource) {
        Copy-Item -Path $audacitySource -Destination "$audacityConfigDir\audacity.cfg" -Force
        Write-Log "Audacity config deployed to $audacityConfigDir (MME host, blind-friendly)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "Audacity config not found at $audacitySource" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy Audacity config: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 33: Deploy SumatraPDF accessibility config (continuous scroll, system colors)
Write-Log "Step 33: Deploying SumatraPDF accessibility config..." "INFO"

try {
    $profileBase = if (Test-Path "C:\Users\Student") { "C:\Users\Student" } else { $env:USERPROFILE }

    $sumatraConfigDir = Join-Path $profileBase "AppData\Local\SumatraPDF"
    if (-not (Test-Path $sumatraConfigDir)) {
        New-Item -Path $sumatraConfigDir -ItemType Directory -Force | Out-Null
    }

    $sumatraSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\sumatrapdf-config\SumatraPDF-settings.txt"
    if (Test-Path $sumatraSource) {
        Copy-Item -Path $sumatraSource -Destination "$sumatraConfigDir\SumatraPDF-settings.txt" -Force
        Write-Log "SumatraPDF config deployed to $sumatraConfigDir (continuous, fit-width)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "SumatraPDF config not found at $sumatraSource" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy SumatraPDF config: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 34: Deploy Kiwix accessibility config (130% zoom, reopen tabs)
Write-Log "Step 34: Deploying Kiwix accessibility config..." "INFO"

try {
    $profileBase = if (Test-Path "C:\Users\Student") { "C:\Users\Student" } else { $env:USERPROFILE }

    $kiwixConfigDir = Join-Path $profileBase "AppData\Local\kiwix-desktop"
    if (-not (Test-Path $kiwixConfigDir)) {
        New-Item -Path $kiwixConfigDir -ItemType Directory -Force | Out-Null
    }

    $kiwixSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\kiwix-config\Kiwix-desktop.conf"
    if (Test-Path $kiwixSource) {
        Copy-Item -Path $kiwixSource -Destination "$kiwixConfigDir\Kiwix-desktop.conf" -Force
        Write-Log "Kiwix config deployed to $kiwixConfigDir (130% zoom)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "Kiwix config not found at $kiwixSource" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy Kiwix config: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 35: Deploy GoldenDict accessibility config (150% zoom, large article font)
Write-Log "Step 35: Deploying GoldenDict accessibility config..." "INFO"

try {
    $profileBase = if (Test-Path "C:\Users\Student") { "C:\Users\Student" } else { $env:USERPROFILE }

    $gdConfigDir = Join-Path $profileBase "AppData\Roaming\GoldenDict"
    $gdStylesDir = Join-Path $gdConfigDir "styles"
    if (-not (Test-Path $gdStylesDir)) {
        New-Item -Path $gdStylesDir -ItemType Directory -Force | Out-Null
    }

    $gdConfigSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\goldendict-config\config"
    $gdCssSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\goldendict-config\styles\article-style.css"

    $deployed = 0
    if (Test-Path $gdConfigSource) {
        Copy-Item -Path $gdConfigSource -Destination "$gdConfigDir\config" -Force
        $deployed++
    }
    if (Test-Path $gdCssSource) {
        Copy-Item -Path $gdCssSource -Destination "$gdStylesDir\article-style.css" -Force
        $deployed++
    }

    if ($deployed -eq 2) {
        Write-Log "GoldenDict config + CSS deployed to $gdConfigDir (150% zoom, 18px font)" "SUCCESS"
        $successCount++
    } elseif ($deployed -gt 0) {
        Write-Log "GoldenDict partially deployed ($deployed/2 files)" "WARNING"
        $successCount++
    } else {
        Write-Log "GoldenDict config files not found" "ERROR"
        $failCount++
    }
} catch {
    Write-Log "Could not deploy GoldenDict config: $($_.Exception.Message)" "ERROR"
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
Write-Host "  welcome-audio $(if(Test-Path "C:\LabTools\welcome-audio.ps1"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "C:\LabTools\welcome-audio.ps1"){"Green"}else{"Red"})
Write-Host ""
Write-Host "Accessibility:" -ForegroundColor White
Write-Host "  Magnifier    Win+Plus (full-screen, 200%)" -ForegroundColor White
Write-Host "  High Contrast Win+Left Alt+Print Screen" -ForegroundColor White
Write-Host "  Calculator   Desktop shortcut" -ForegroundColor White
Write-Host ""
Write-Host "Safety & Hardening:" -ForegroundColor White
Write-Host "  Firefox       Policies deployed (no updates, Vietnamese, no PiP, accessibility)" -ForegroundColor White
Write-Host "  VLC           Audio-only, NVDA-friendly, volume cap 100%" -ForegroundColor White
Write-Host "  Audacity      MME audio host, no splash, beep on completion" -ForegroundColor White
Write-Host "  SumatraPDF    Continuous scroll, fit-width, system colors" -ForegroundColor White
Write-Host "  Kiwix         130% zoom, reopen last tab" -ForegroundColor White
Write-Host "  GoldenDict    150% zoom, 18px article font, UI Automation" -ForegroundColor White
Write-Host "  Sticky Keys   Popup disabled (Shift x5)" -ForegroundColor White
Write-Host "  Filter Keys   Popup disabled (hold key)" -ForegroundColor White
Write-Host "  Toggle Keys   Beep enabled (Caps/Num/Scroll Lock)" -ForegroundColor White
Write-Host "  Volume limit  70% on each login" -ForegroundColor White
Write-Host "  Win Update    Disabled (offline)" -ForegroundColor White
Write-Host "  Notifications Tips/suggestions disabled" -ForegroundColor White
Write-Host "  Narrator      Shortcut disabled (NVDA only)" -ForegroundColor White
Write-Host "  Power         No sleep on AC, no hibernate" -ForegroundColor White
Write-Host "  Battery       Report saved to C:\LabTools\battery-report.htm" -ForegroundColor White
Write-Host "  NVDA backup   Restore shortcut on desktop" -ForegroundColor White
Write-Host "  Vi folders    Tai Lieu, Am Nhac, Truyen, Hoc Tap, Tro Choi" -ForegroundColor White
Write-Host ""
Write-Host "Debloat & Cleanup:" -ForegroundColor White
Write-Host "  Bloatware     Removed (Xbox, News, Weather, Solitaire, Teams, etc.)" -ForegroundColor White
Write-Host "  OneDrive      Removed" -ForegroundColor White
Write-Host "  Widgets       Disabled" -ForegroundColor White
Write-Host "  Cortana       Disabled" -ForegroundColor White
Write-Host "  Edge          Neutered (shortcuts removed, no auto-start)" -ForegroundColor White
Write-Host "  Taskbar       Cleaned (Chat, Task View, Search, Widgets, Copilot hidden)" -ForegroundColor White
Write-Host "  Telemetry     Reduced to minimum" -ForegroundColor White
Write-Host "  Game Bar      Disabled (Win+G)" -ForegroundColor White
Write-Host "  Snap Layouts  Hover tooltip disabled" -ForegroundColor White
Write-Host "  OOBE nag      'Finish setup' prompt disabled" -ForegroundColor White
Write-Host "  Start menu    Suggestions/promoted apps disabled" -ForegroundColor White
Write-Host ""
Write-Host "Remote Management:" -ForegroundColor White
Write-Host "  SSH server    Enabled (port 22, PowerShell default shell)" -ForegroundColor White
Write-Host "  Update agent  Daily 2-4 AM (LabUpdateAgent task)" -ForegroundColor White
Write-Host "  Fleet report  Daily health upload to Google Drive (LabFleetReport task)" -ForegroundColor White
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
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

if (-not $env:LAB_BOOTSTRAP) { pause }
