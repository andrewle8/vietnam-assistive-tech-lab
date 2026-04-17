# Vietnam Lab Deployment - Loaner Laptop Configuration
# Version: 1.0
# Run on each lab laptop after scripts 1-3. Requires Administrator.
# Applies Windows hardening, desktop shortcuts, NVDA config, file associations,
# LabAdmin/Student accounts, language pack, power settings, and more.
# Last Updated: April 2026

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
$labToolsDir = "C:\LabTools"
$successCount = 0
$failCount = 0

# ── Pre-flight: Ensure Student account exists and resolve SID ──────────────
# Many steps below write per-user registry settings for the Student profile.
# The account must exist first so we can resolve its SID and target HKU.
Write-Log "Pre-flight: Ensuring Student account exists..." "INFO"

$studentExists = Get-LocalUser -Name "Student" -ErrorAction SilentlyContinue
if (-not $studentExists) {
    New-LocalUser -Name "Student" -NoPassword -FullName "Student" -Description "Lab student account" -ErrorAction Stop
    Add-LocalGroupMember -Group "Users" -Member "Student" -ErrorAction SilentlyContinue
    Set-LocalUser -Name "Student" -PasswordNeverExpires $true -ErrorAction SilentlyContinue
    Write-Log "Created Student account (standard user, no password)" "SUCCESS"
}

# Resolve Student SID for HKU registry targeting
$studentSID = $null
try {
    $studentSID = (New-Object System.Security.Principal.NTAccount("Student")).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
    Write-Log "Student SID resolved: $studentSID" "INFO"
} catch {
    Write-Log "WARNING: Could not resolve Student SID. Per-user settings will only apply to Admin." "ERROR"
}

# Build array of registry hive paths to target (Admin HKCU + Student HKU + Default profile)
$hkuPaths = @("HKCU:")
$studentHiveLoaded = $false
if ($studentSID) {
    $studentHivePath = "REGISTRY::HKEY_USERS\$studentSID"
    if (Test-Path $studentHivePath) {
        # Student is logged in — SID already in HKU
        $hkuPaths += $studentHivePath
    } else {
        # Student is NOT logged in — manually load their NTUSER.DAT
        $studentNtuser = "C:\Users\Student\NTUSER.DAT"
        if (Test-Path $studentNtuser) {
            reg load "HKU\$studentSID" $studentNtuser 2>$null
            if ($LASTEXITCODE -eq 0) {
                $studentHiveLoaded = $true
                $hkuPaths += $studentHivePath
                Write-Log "Loaded Student registry hive from NTUSER.DAT" "INFO"
            } else {
                Write-Log "WARNING: Could not load Student NTUSER.DAT — per-user settings will not apply to Student." "ERROR"
            }
        } else {
            Write-Log "WARNING: Student NTUSER.DAT not found — Student has never logged in. Per-user settings will apply via Default profile only." "ERROR"
        }
    }
}
$defaultLoaded = $false
$defaultNtuser = "C:\Users\Default\NTUSER.DAT"
if ((Test-Path $defaultNtuser) -and -not (Test-Path "REGISTRY::HKEY_USERS\DefaultProfile")) {
    reg load "HKU\DefaultProfile" $defaultNtuser 2>$null
    if ($LASTEXITCODE -eq 0) { $defaultLoaded = $true; $hkuPaths += "REGISTRY::HKEY_USERS\DefaultProfile" }
}

Write-Log "Registry targets: $($hkuPaths -join ', ')" "INFO"

# Step 1: Ensure LabTools directory exists
Write-Log "Step 1: Creating LabTools directory..." "INFO"

if (-not (Test-Path $labToolsDir)) {
    New-Item -Path $labToolsDir -ItemType Directory -Force | Out-Null
    Write-Log "Created directory: $labToolsDir" "SUCCESS"
    $successCount++
}

# Cleanup legacy artifacts from prior deployments (Tailscale, rclone, Thorium, Quorum, LEAP, nvdaRemote)
foreach ($legacy in @("$labToolsDir\rclone", "$labToolsDir\fleet-reports", "$labToolsDir\start-tailscale.ps1", "$labToolsDir\start-tailscale.vbs", "$labToolsDir\Report-FleetHealth.ps1", "$labToolsDir\backup-usb.ps1", "C:\Games\LEAP")) {
    if (Test-Path $legacy) { Remove-Item -Path $legacy -Recurse -Force -ErrorAction SilentlyContinue }
}
foreach ($taskName in @("LabUSBBackup", "LabFleetReport")) {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Removed legacy scheduled task: $taskName" "INFO"
    }
}
Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -Force -ErrorAction SilentlyContinue

# Uninstall Tailscale service + app if present
$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($tsService) {
    Stop-Service -Name "Tailscale" -Force -ErrorAction SilentlyContinue
    Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $tsUninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "Tailscale" } | Select-Object -First 1
    if ($tsUninstall -and $tsUninstall.UninstallString -match 'MsiExec') {
        $guid = [regex]::Match($tsUninstall.UninstallString, '\{[0-9A-Fa-f\-]+\}').Value
        if ($guid) { Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue }
    }
    Remove-Item "C:\Program Files\Tailscale" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Removed legacy Tailscale install" "INFO"
}

# Uninstall Quorum Studio if present
$quorumPath = "C:\Program Files\QuorumStudio"
if (Test-Path $quorumPath) {
    $quorumUninstall = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Quorum" } | Select-Object -First 1
    if ($quorumUninstall -and $quorumUninstall.UninstallString) {
        Start-Process cmd.exe -ArgumentList "/c", "`"$($quorumUninstall.UninstallString)`" /S" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    Remove-Item $quorumPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Public\Desktop\Quorum Studio.lnk" -Force -ErrorAction SilentlyContinue
    Write-Log "Removed legacy Quorum Studio install" "INFO"
}

# Remove Thorium per-user install (all profiles)
foreach ($profile in @("Admin", "Student")) {
    $thPath = "C:\Users\$profile\AppData\Local\Programs\Thorium"
    if (Test-Path $thPath) {
        Remove-Item $thPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed Thorium from $profile profile" "INFO"
    }
}
Remove-Item "C:\Users\Public\Desktop\Thorium Reader.lnk" -Force -ErrorAction SilentlyContinue

# Remove nvdaRemote addon from all profiles
Get-ChildItem "C:\Users\*\AppData\Roaming\nvda\addons\remote*" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Step 2: Set AutoPlay for removable drives to open folder
Write-Log "Step 2: Configuring AutoPlay for removable drives..." "INFO"

try {
    # Apply AutoPlay settings to all user profiles
    foreach ($hive in $hkuPaths) {
        $apBase = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"
        $apDefault = "$apBase\EventHandlersDefaultSelection\StorageOnArrival"
        $apChosen = "$apBase\UserChosenExecuteHandlers\StorageOnArrival"

        foreach ($regPath in @($apDefault, $apChosen)) {
            $parentPath = Split-Path $regPath
            if (-not (Test-Path $parentPath)) { New-Item -Path $parentPath -Force -ErrorAction SilentlyContinue | Out-Null }
        }

        Set-ItemProperty -Path (Split-Path $apDefault) -Name "StorageOnArrival" -Value "MSOpenFolder" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path (Split-Path $apChosen) -Name "StorageOnArrival" -Value "MSOpenFolder" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $apBase -Name "DisableAutoplay" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    Write-Log "AutoPlay set to open folder for removable drives" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure AutoPlay: $($_.Exception.Message)" "ERROR"
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

    # Apply Vietnamese locale directly to Student profile via HKU (Set-Culture only hits Admin HKCU)
    if ($studentSID) {
        $studentIntl = "REGISTRY::HKEY_USERS\$studentSID\Control Panel\International"
        if (Test-Path $studentIntl) {
            Set-ItemProperty -Path $studentIntl -Name "Locale" -Value "0000042A" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "LocaleName" -Value "vi-VN" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "sShortDate" -Value "dd/MM/yyyy" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "sLongDate" -Value "dd MMMM yyyy" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "sCurrency" -Value "₫" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "sLanguage" -Value "VIT" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "iMeasure" -Value "0" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $studentIntl -Name "iPaperSize" -Value "9" -Force -ErrorAction SilentlyContinue
            Write-Log "Vietnamese locale applied to Student profile (vi-VN, dd/MM/yyyy, dong)" "SUCCESS"
        }

        # Set Vietnamese as preferred Office editing language for Student
        $studentOffice = "REGISTRY::HKEY_USERS\$studentSID\Software\Microsoft\Office\16.0\Common\LanguageResources"
        if (-not (Test-Path $studentOffice)) { New-Item -Path $studentOffice -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $studentOffice -Name "PreferredEditingLanguage" -Value "vi-vn" -Force -ErrorAction SilentlyContinue
        Write-Log "Office preferred editing language set to Vietnamese for Student" "SUCCESS"
    }

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

    # Desktop shortcut is created in Step 6 (standardized desktop shortcuts)
    Write-Log "Language toggle script created (shortcut added in Step 6)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create language toggle: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 5: Configure Windows Magnifier for low-vision users
Write-Log "Step 5: Configuring Windows Magnifier for low-vision users..." "INFO"

try {
    # Enable Magnifier keyboard shortcut (Win+Plus) and set sensible defaults for all users
    foreach ($hive in $hkuPaths) {
        $magPath = "$hive\Software\Microsoft\ScreenMagnifier"
        if (-not (Test-Path $magPath)) { New-Item -Path $magPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $magPath -Name "MagnificationMode" -Value 1 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $magPath -Name "Magnification" -Value 200 -Force -ErrorAction SilentlyContinue

        # Enable High Contrast keyboard shortcut (Win+Left Alt+Print Screen)
        $hcPath = "$hive\Control Panel\Accessibility\HighContrast"
        if (-not (Test-Path $hcPath)) { New-Item -Path $hcPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $hcPath -Name "Flags" -Value "126" -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Windows Magnifier defaults set (Win+Plus to launch, lens mode, 200%)" "SUCCESS"
    Write-Log "High contrast toggle enabled (Win+Left Alt+Print Screen)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure Magnifier settings: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 5b: Copy per-user apps (SumatraPDF) from Admin to Student profile
# These installers install to Admin's %LOCALAPPDATA% since Bootstrap runs as Admin
Write-Log "Step 5b: Copying per-user apps to Student profile..." "INFO"

try {
    $adminProfile = $env:USERPROFILE
    $studentProfile = "C:\Users\Student"

    # SumatraPDF
    $adminSumatra = "$adminProfile\AppData\Local\SumatraPDF"
    $studentSumatra = "$studentProfile\AppData\Local\SumatraPDF"
    if ((Test-Path "$adminSumatra\SumatraPDF.exe") -and -not (Test-Path "$studentSumatra\SumatraPDF.exe")) {
        Copy-Item $adminSumatra $studentSumatra -Recurse -Force
        icacls $studentSumatra /grant "Student:(OI)(CI)F" /T /Q 2>$null
        Write-Log "Copied SumatraPDF to Student profile" "SUCCESS"
    }

    $successCount++
} catch {
    Write-Log "Could not copy per-user apps: $($_.Exception.Message)" "WARNING"
}

# Step 6: Clean desktop and create shortcuts for screen reader navigation
Write-Log "Step 6: Wiping desktop shortcuts and creating clean set for screen reader navigation..." "INFO"

try {
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $userDesktop = [Environment]::GetFolderPath("Desktop")

    # Wipe ALL existing shortcuts from both desktops (clean slate)
    foreach ($desktop in @($publicDesktop, $userDesktop)) {
        Get-ChildItem -Path $desktop -Filter "*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Cleared all existing desktop shortcuts" "INFO"

    # Disable Windows Spotlight "Learn about this picture" overlay (distracting for screen readers)
    # Registry-only approaches do NOT reliably kill Spotlight on Win11. What works: set an actual
    # solid-color BMP as wallpaper with BackgroundType=0 (Picture), so Windows never enters Spotlight mode.

    # Create a 1x1 solid black BMP (58 bytes)
    $bmpPath = "C:\Windows\Web\Wallpaper\solid-black.bmp"
    if (-not (Test-Path $bmpPath)) {
        $bmpBytes = [byte[]]@(
            0x42,0x4D,0x3A,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00,
            0x28,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x00,
            0x18,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00)
        [System.IO.File]::WriteAllBytes($bmpPath, $bmpBytes)
    }

    # HKLM Group Policy — prevents Spotlight from re-enabling on any user
    $polPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }
    New-ItemProperty -Path $polPath -Name "DisableWindowsSpotlightFeatures" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $polPath -Name "DisableWindowsSpotlightOnDesktop" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $polPath -Name "DisableWindowsSpotlightWindowsWelcomeExperience" -Value 1 -PropertyType DWord -Force | Out-Null

    # Set wallpaper to solid black BMP for Admin, Student, and Default profile
    # (uses $hkuPaths from pre-flight section)
    foreach ($hive in $hkuPaths) {
        # Set wallpaper to solid black BMP (BackgroundType 0 = Picture, NOT Spotlight)
        $wpPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
        if (-not (Test-Path $wpPath)) { New-Item -Path $wpPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $wpPath -Name "BackgroundType" -Value 0 -Force -ErrorAction SilentlyContinue
        $deskPath = "$hive\Control Panel\Desktop"
        if (Test-Path $deskPath) {
            Set-ItemProperty -Path $deskPath -Name "Wallpaper" -Value $bmpPath -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $deskPath -Name "WallpaperStyle" -Value "2" -Force -ErrorAction SilentlyContinue
        }
        # Disable Spotlight overlay
        $spotlightPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\DesktopSpotlight"
        if (-not (Test-Path $spotlightPath)) { New-Item -Path $spotlightPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $spotlightPath -Name "Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Hide system desktop icons that create dead spots for screen reader arrow-key navigation
    # (Recycle Bin, Spotlight shell object, This PC — students use "My USB" shortcut instead)
    # Must set both NewStartPanel AND ClassicStartMenu — Win11 checks both paths
    $hideGuids = @(
        "{645FF040-5081-101B-9F08-00AA002F954E}",  # Recycle Bin
        "{2CC5CA98-6485-489A-920E-B3E88A6CCCE3}",  # "Learn about this picture" Spotlight
        "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"   # This PC
    )
    foreach ($hive in $hkuPaths) {
        foreach ($subKey in @("NewStartPanel", "ClassicStartMenu")) {
            $hidePath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\$subKey"
            if (-not (Test-Path $hidePath)) { New-Item -Path $hidePath -Force -ErrorAction SilentlyContinue | Out-Null }
            foreach ($guid in $hideGuids) {
                New-ItemProperty -Path $hidePath -Name $guid -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
    # Also set machine-wide (HKLM) so it applies even if per-user keys are missing
    $hklmHide = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    if (-not (Test-Path $hklmHide)) { New-Item -Path $hklmHide -Force | Out-Null }
    foreach ($guid in $hideGuids) {
        New-ItemProperty -Path $hklmHide -Name $guid -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Force Explorer to re-read hide flags by toggling all desktop icons off then on
    foreach ($hive in $hkuPaths) {
        $advPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "HideIcons" -Value 1 -Force -ErrorAction SilentlyContinue
        }
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    foreach ($hive in $hkuPaths) {
        $advPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "HideIcons" -Value 0 -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Process explorer.exe
    Start-Sleep -Seconds 2
    Write-Log "Hidden system icons (Recycle Bin, Spotlight, This PC) and forced desktop refresh" "INFO"

    # Plain names — no number prefixes. NVDA users navigate the desktop alphabetically
    # and use first-letter keys to jump (press "W" for Word, "F" for Firefox, etc.).
    # Numbers broke first-letter nav and added noisy "zero one" speech on every item.
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcuts = @(
        # --- Core accessibility ---
        @{ Name = "NVDA"; Target = "C:\Program Files\NVDA\nvda.exe"; AltTarget = "C:\Program Files (x86)\NVDA\nvda.exe"; Desc = "NVDA Screen Reader" },
        # --- Productivity ---
        @{ Name = "Word"; Target = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE"; Desc = "Microsoft Word" },
        @{ Name = "Excel"; Target = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\EXCEL.EXE"; Desc = "Microsoft Excel" },
        @{ Name = "PowerPoint"; Target = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\POWERPNT.EXE"; Desc = "Microsoft PowerPoint" },
        # --- Web & Reading ---
        @{ Name = "Firefox"; Target = "C:\Program Files\Mozilla Firefox\firefox.exe"; AltTarget = "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"; Desc = "Firefox Web Browser" },
        @{ Name = "Wikipedia (Offline)"; Target = "C:\Program Files\Kiwix\kiwix-desktop.exe"; Desc = "Kiwix - Offline Vietnamese Wikipedia" },
        @{ Name = "Tu Dien - Dictionary"; Target = "C:\Program Files\GoldenDict\GoldenDict.exe"; AltTarget = "C:\Program Files (x86)\GoldenDict\GoldenDict.exe"; Desc = "GoldenDict - Offline Dictionary" },
        @{ Name = "SumatraPDF"; Target = "C:\Program Files\SumatraPDF\SumatraPDF.exe"; AltTarget = "C:\Users\Student\AppData\Local\SumatraPDF\SumatraPDF.exe"; Desc = "SumatraPDF Reader" },
        # --- Media ---
        @{ Name = "VLC media player"; Target = "C:\Program Files\VideoLAN\VLC\vlc.exe"; AltTarget = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"; Desc = "VLC Media Player" },
        @{ Name = "Audacity"; Target = "C:\Program Files\Audacity\Audacity.exe"; AltTarget = "C:\Program Files (x86)\Audacity\Audacity.exe"; Desc = "Audacity Audio Editor" },
        # --- Education ---
        @{ Name = "Sao Mai Typing Tutor"; Target = "C:\Program Files (x86)\SaoMai\SMTT\SMTT.exe"; AltTarget = "C:\Program Files\SaoMai\SMTT\SMTT.exe"; Desc = "Sao Mai Vietnamese Typing Tutor" },
        @{ Name = "Readmate"; Target = "C:\Program Files\SaoMai\sm_readmate\sm_readmate.exe"; AltTarget = "C:\Program Files (x86)\SaoMai\sm_readmate\sm_readmate.exe"; Desc = "Sao Mai Readmate Accessible Reader" },
        # --- Utilities ---
        @{ Name = "Calculator"; Target = "calc.exe"; Desc = "Windows Calculator" },
        @{ Name = "My USB"; Target = "explorer.exe"; Args = "shell:MyComputerFolder"; IconLocation = "%SystemRoot%\System32\imageres.dll,109"; Desc = "Open This PC to access your USB drive" },
        # --- Lab tools ---
        @{ Name = "Doi Ngon Ngu - Switch Language"; Target = "powershell.exe"; Args = "-NoProfile -ExecutionPolicy Bypass -File `"C:\LabTools\toggle-language.ps1`""; Desc = "Toggle Vietnamese/English" },
        @{ Name = "Khoi Phuc NVDA - Restore NVDA"; Target = "powershell.exe"; Args = "-NoProfile -ExecutionPolicy Bypass -File `"C:\LabTools\restore-nvda.ps1`""; Desc = "Restore NVDA to default configuration" }
    )

    $createdCount = 0
    foreach ($s in $shortcuts) {
        # Resolve the target path (try primary, then alt)
        $targetPath = $null
        if ($s.Target -in @("calc.exe", "explorer.exe", "powershell.exe")) {
            $targetPath = $s.Target
        } elseif (Test-Path $s.Target) {
            $targetPath = $s.Target
        } elseif ($s.AltTarget -and (Test-Path $s.AltTarget)) {
            $targetPath = $s.AltTarget
        }

        if (-not $targetPath) {
            # Try wildcard search for apps with unknown exact exe names
            $searchDirs = @($s.Target, $s.AltTarget) | Where-Object { $_ } | ForEach-Object { Split-Path $_ -Parent }
            foreach ($dir in $searchDirs) {
                if (Test-Path $dir) {
                    $foundExe = Get-ChildItem -Path $dir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($foundExe) { $targetPath = $foundExe.FullName; break }
                }
            }
        }

        if (-not $targetPath) {
            Write-Log "Skipping shortcut '$($s.Name)' - executable not found" "ERROR"
            continue
        }

        $lnkPath = Join-Path $publicDesktop "$($s.Name).lnk"
        $shortcut = $WshShell.CreateShortcut($lnkPath)
        $shortcut.TargetPath = $targetPath
        if ($s.Args) { $shortcut.Arguments = $s.Args }
        if ($s.IconLocation) { $shortcut.IconLocation = $s.IconLocation }
        $shortcut.Description = $s.Desc
        if ($targetPath -notin @("calc.exe", "explorer.exe", "powershell.exe")) {
            $shortcut.WorkingDirectory = Split-Path $targetPath -Parent
        }
        $shortcut.Save()
        $createdCount++
    }

    Write-Log "Created $createdCount desktop shortcuts (alphabetical for screen reader first-letter navigation)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set up desktop shortcuts: $($_.Exception.Message)" "ERROR"
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

    # Deploy the NVDA controller client DLL (no longer bundled with NVDA since 2023.1)
    $dllSource = Join-Path (Split-Path -Parent $PSScriptRoot) "Installers\NVDA\nvdaControllerClient64.dll"
    $dllDest = Join-Path $welcomeScriptDir "nvdaControllerClient64.dll"
    if ((Test-Path $dllSource) -and -not (Test-Path $dllDest)) {
        Copy-Item -Path $dllSource -Destination $dllDest -Force
        Write-Log "Deployed nvdaControllerClient64.dll from USB" "SUCCESS"
    }

    $welcomeScript = @'
# Lab Welcome Audio - plays on Student login
# Speaks through NVDA using the configured Vietnamese voice (Sao Mai VNVoice)
Start-Sleep -Seconds 8

# Use NVDA's controller client DLL to speak through NVDA's configured voice
# The DLL is no longer bundled with NVDA since 2023.1 — we ship it in LabTools
$nvdaDll = "C:\LabTools\nvdaControllerClient64.dll"

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

# Step 8: (Moved to Step 6 — desktop shortcuts are now created in one pass)

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

# Step 9b: Set Windows SAPI default voice to Vietnamese (matches NVDA and user audience)
# This affects any app using Windows TTS. NVDA uses its own voice config and is unaffected.
Write-Log "Step 9b: Setting Windows SAPI default voice to Vietnamese (Minh Du)..." "INFO"

try {
    # Machine-wide SAPI default (Vietnamese Minh Du from Sao Mai VNVoice)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Speech\Voices" `
        -Name "DefaultTokenId" `
        -Value "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\Minh Du" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Speech_OneCore\Voices" `
        -Name "DefaultTokenId" `
        -Value "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_viVN_An" -Force

    # Per-user SAPI default (Student + any other loaded hives)
    foreach ($hive in $hkuPaths) {
        $speechPath = "$hive\Software\Microsoft\Speech\Voices"
        if (-not (Test-Path $speechPath)) { New-Item -Path $speechPath -Force | Out-Null }
        Set-ItemProperty -Path $speechPath -Name "DefaultTokenId" `
            -Value "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\Minh Du" -Force

        $oneCorePath = "$hive\Software\Microsoft\Speech_OneCore\Voices"
        if (-not (Test-Path $oneCorePath)) { New-Item -Path $oneCorePath -Force | Out-Null }
        Set-ItemProperty -Path $oneCorePath -Name "DefaultTokenId" `
            -Value "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_viVN_An" -Force
    }

    Write-Log "SAPI default voice set to Vietnamese (Minh Du)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set SAPI default voice: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 10: Configure Windows Update (manual-only — no auto-downloads or auto-installs)
Write-Log "Step 10: Configuring Windows Update for manual-only..." "INFO"

try {
    # Keep services at Manual so updates CAN run when the admin chooses
    Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
    Set-Service -Name "WaaSMedicSvc" -StartupType Manual -ErrorAction SilentlyContinue
    Set-Service -Name "UsoSvc" -StartupType Manual -ErrorAction SilentlyContinue

    # Set Group Policy: "Notify for download and notify for install" (AUOptions=2)
    # This prevents automatic downloads/installs but allows manual "Check for updates"
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
    Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 0 -Force
    Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Force
    # Disable auto-reboot when users are logged in
    Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Force
    # Suppress Windows Update restart notification popups (interrupts NVDA)
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name "SetAutoRestartNotificationDisable" -Value 1 -Force

    Write-Log "Windows Update set to manual-only (notify, no auto-install, no restart popups)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure Windows Update: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 11: Disable non-essential notifications
Write-Log "Step 11: Disabling non-essential notifications..." "INFO"

try {
    # Disable tips, suggestions, and Get Started notifications for all users
    foreach ($hive in $hkuPaths) {
        $contentDelivery = "$hive\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $contentDelivery) {
            Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338389Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-310093Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338393Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-353698Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $contentDelivery -Name "SoftLandingEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $contentDelivery -Name "SystemPaneSuggestionsEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        }

        # Disable toast notifications (prevents popups that interrupt NVDA speech)
        $pushNotify = "$hive\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
        if (-not (Test-Path $pushNotify)) { New-Item -Path $pushNotify -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $pushNotify -Name "ToastEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

        # Disable Notification Center entirely
        $explorerPolicy = "$hive\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $explorerPolicy)) { New-Item -Path $explorerPolicy -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $explorerPolicy -Name "DisableNotificationCenter" -Value 1 -Force -ErrorAction SilentlyContinue
    }

    # Disable Windows Defender notifications (machine-wide)
    $defenderNotify = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    if (-not (Test-Path $defenderNotify)) { New-Item -Path $defenderNotify -Force | Out-Null }
    Set-ItemProperty -Path $defenderNotify -Name "DisableNotifications" -Value 1 -Force

    Write-Log "Non-essential notifications disabled (toast, Notification Center, suggestions)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable notifications: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 11b: Disable Windows system sounds (reduces audio clutter that interferes with NVDA speech)
Write-Log "Step 11b: Disabling Windows system sounds..." "INFO"

try {
    # Disable for Admin (HKCU) and Student (HKU)
    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes" -Name "(Default)" -Value ".None" -Force
    if ($studentSID) {
        $studentSchemes = "REGISTRY::HKEY_USERS\$studentSID\AppEvents\Schemes"
        if (Test-Path $studentSchemes) {
            Set-ItemProperty -Path $studentSchemes -Name "(Default)" -Value ".None" -Force
        }
    }
    Write-Log "Windows system sounds disabled for all users (reduces interference with NVDA)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable system sounds: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 12: Disable Narrator shortcut (prevents dual screen reader conflict)
Write-Log "Step 12: Disabling Narrator auto-start shortcut..." "INFO"

try {
    # Disable the Win+Ctrl+Enter shortcut for Narrator for all users
    foreach ($hive in $hkuPaths) {
        $narratorPath = "$hive\Software\Microsoft\Narrator\NoRoam"
        if (-not (Test-Path $narratorPath)) { New-Item -Path $narratorPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $narratorPath -Name "WinEnterLaunchEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

        $easeAccess = "$hive\Software\Microsoft\Ease of Access"
        if (-not (Test-Path $easeAccess)) { New-Item -Path $easeAccess -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $easeAccess -Name "selfvoice.ManualStart" -Value 1 -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Narrator shortcut disabled for all users (prevents NVDA conflict)" "SUCCESS"
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
    # Apply to all user profiles (Admin, Student, Default)
    foreach ($hive in $hkuPaths) {
        # Disable Sticky Keys popup (triggered by pressing Shift 5 times)
        $stickyKeysPath = "$hive\Control Panel\Accessibility\StickyKeys"
        if (-not (Test-Path $stickyKeysPath)) { New-Item -Path $stickyKeysPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $stickyKeysPath -Name "Flags" -Value "506" -Force -ErrorAction SilentlyContinue

        # Disable Filter Keys popup (triggered by holding a key)
        $filterKeysPath = "$hive\Control Panel\Accessibility\Keyboard Response"
        if (-not (Test-Path $filterKeysPath)) { New-Item -Path $filterKeysPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $filterKeysPath -Name "Flags" -Value "122" -Force -ErrorAction SilentlyContinue

        # Enable Toggle Keys beep (useful audio feedback for blind users - Caps/Num/Scroll Lock)
        $toggleKeysPath = "$hive\Control Panel\Accessibility\ToggleKeys"
        if (-not (Test-Path $toggleKeysPath)) { New-Item -Path $toggleKeysPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $toggleKeysPath -Name "Flags" -Value "63" -Force -ErrorAction SilentlyContinue
    }

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
    # Target Student's NVDA config (not Admin's $env:APPDATA which resolves to Admin profile)
    $nvdaConfigDir = "C:\Users\Student\AppData\Roaming\nvda"

    # Deploy the repo template as the known-good config
    $nvdaTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\nvda-config\nvda.ini"
    if (-not (Test-Path $nvdaConfigDir)) {
        New-Item -Path $nvdaConfigDir -ItemType Directory -Force | Out-Null
    }
    if (Test-Path $nvdaTemplate) {
        Copy-Item -Path $nvdaTemplate -Destination "$nvdaConfigDir\nvda.ini" -Force
        Write-Log "Deployed NVDA config template (laptop layout, Vietnamese, rate 35) to Student profile" "SUCCESS"
    }

    # Copy NVDA addons from Admin profile to Student (3-Configure-NVDA.ps1 installs
    # addons to $env:APPDATA which resolves to Admin when run from Bootstrap)
    $adminAddons = Join-Path $env:APPDATA "nvda\addons"
    $studentAddons = Join-Path $nvdaConfigDir "addons"
    if ((Test-Path $adminAddons) -and (Get-ChildItem $adminAddons -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path $studentAddons)) {
            New-Item -Path $studentAddons -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$adminAddons\*" -Destination $studentAddons -Recurse -Force -ErrorAction SilentlyContinue
        $addonCount = (Get-ChildItem $studentAddons -Directory -ErrorAction SilentlyContinue).Count
        Write-Log "Copied $addonCount NVDA addon(s) from Admin to Student profile" "SUCCESS"
    }

    # Backup the config
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
# Always target Student profile, even when run as Admin
$nvdaConfigDir = "C:\Users\Student\AppData\Roaming\nvda"

if (Test-Path $backupDir) {
    # Stop NVDA
    $nvda = Get-Process nvda -ErrorAction SilentlyContinue
    if ($nvda) { Stop-Process -Name nvda -Force; Start-Sleep -Seconds 2 }

    # Restore config
    Copy-Item -Path "$backupDir\*" -Destination $nvdaConfigDir -Recurse -Force

    # Restart NVDA
    $nvdaExe = "C:\Program Files (x86)\NVDA\nvda.exe"
    if (-not (Test-Path $nvdaExe)) { $nvdaExe = "C:\Program Files\NVDA\nvda.exe" }
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

    # Desktop shortcut is created in Step 6 (standardized desktop shortcuts)
    Write-Log "NVDA backup/restore script created (shortcut added in Step 6)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create NVDA backup/restore: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 17: Create Vietnamese-labeled content folders (no desktop shortcuts — desktop is managed in Step 6)
Write-Log "Step 17: Creating Vietnamese content folders..." "INFO"

try {
    $studentDocs = "C:\Users\Public\Documents"

    $viFolders = @("Tai Lieu", "Am Nhac", "Truyen", "Hoc Tap", "Tro Choi")

    foreach ($folderName in $viFolders) {
        $folderPath = Join-Path $studentDocs $folderName
        if (-not (Test-Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        }
    }
    # NOTE: No desktop shortcuts created here. Step 6 owns the full desktop layout.
    # Students access these folders through File Explorer / My USB shortcut.

    Write-Log "Vietnamese content folders created (Tai Lieu, Am Nhac, Truyen, Hoc Tap, Tro Choi)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create Vietnamese folders: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 17b: Populate SM Readmate library — copies ebooks from USB into Student's
# SM Readmate data folder and registers them in its SQLite library (uses relative
# paths, required by SM Readmate 1.1.0+).
Write-Log "Step 17b: Populating SM Readmate ebook library..." "INFO"

try {
    $ebookSource   = Join-Path $usbRoot "Installers\Ebooks"
    $studentDbPath = "C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\databases\app_database.db"
    $populateScript = Join-Path $PSScriptRoot "Populate-ReadmateDB.ps1"

    if ((Test-Path $ebookSource) -and (Test-Path $populateScript)) {
        & $populateScript -EbookSource $ebookSource -DbPath $studentDbPath
        Write-Log "SM Readmate library populated with ebooks from $ebookSource" "SUCCESS"
        $successCount++
    } else {
        $missing = @()
        if (-not (Test-Path $ebookSource))     { $missing += "$ebookSource (expected on USB)" }
        if (-not (Test-Path $populateScript))  { $missing += "Populate-ReadmateDB.ps1" }
        Write-Log "Skipped SM Readmate population - missing: $($missing -join ', ')" "WARNING"
    }
} catch {
    Write-Log "Could not populate SM Readmate library: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 17c: Block SM Readmate auto-update endpoint via hosts file
# SM Readmate 1.1.0 polls saomaicenter.org for updates and prompts students on new
# versions. We saw firsthand that 1.0.5 -> 1.1.0 broke the entire library. Block so
# students never see the prompt. Updates to SM Readmate are pushed via our update
# agent (update-manifest.json) after testing each version.
Write-Log "Step 17c: Blocking SM Readmate auto-update endpoint..." "INFO"

try {
    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $marker = "# VN-LAB: block SM Readmate auto-update"
    $blockEntry = "0.0.0.0 saomaicenter.org"

    $content = if (Test-Path $hostsFile) { Get-Content $hostsFile -Raw } else { "" }
    if ($content -notmatch [regex]::Escape($marker)) {
        $append = "`r`n$marker`r`n$blockEntry`r`n"
        Add-Content -Path $hostsFile -Value $append -Encoding ASCII
        ipconfig /flushdns | Out-Null
        Write-Log "SM Readmate update check blocked (hosts file entry added)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "SM Readmate update block already present in hosts file" "INFO"
        $successCount++
    }
} catch {
    Write-Log "Could not block SM Readmate updates: $($_.Exception.Message)" "WARNING"
}

# Step 17d: Deploy SM Readmate preferences (default to Microsoft An, offline reliable)
# User can switch to Edge TTS (HoaiMy Neural) in F4 settings if internet is available.
Write-Log "Step 17d: Deploying SM Readmate preferences..." "INFO"

try {
    $prefTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\sm-readmate-config\shared_preferences.json"
    $prefDest = "C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\shared_preferences.json"
    $prefDestDir = Split-Path $prefDest -Parent

    if (Test-Path $prefTemplate) {
        if (-not (Test-Path $prefDestDir)) { New-Item -Path $prefDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $prefTemplate -Destination $prefDest -Force
        icacls $prefDestDir /grant "Student:(OI)(CI)F" /T /Q 2>$null
        Write-Log "SM Readmate preferences deployed (default voice: Microsoft An)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "SM Readmate preference template not found at $prefTemplate" "WARNING"
    }
} catch {
    Write-Log "Could not deploy SM Readmate preferences: $($_.Exception.Message)" "WARNING"
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

    # Random offset per PC (0-90 min) based on PC number to spread GitHub load
    # Target window: 6 PM - 7:30 PM (dinner, laptops likely still on, students away eating)
    $pcNum = 0
    if ($env:COMPUTERNAME -match "PC-(\d+)") { $pcNum = [int]$Matches[1] }
    $randomDelay = New-TimeSpan -Minutes ($pcNum * 5)  # PC-01=5min, PC-19=95min

    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$updateAgentDir\Update-Agent.ps1`""

    # Trigger at 6 PM local (Vietnam is ICT GMT+7) — dinner window, students away
    # StartWhenAvailable = true handles the case where laptop was off at 6 PM
    $taskTrigger = New-ScheduledTaskTrigger -Daily -At "18:00" -RandomDelay $randomDelay

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
        -Description "Checks for and applies software updates from GitHub (daily 6-7:30 PM dinner window)" | Out-Null

    Write-Log "Scheduled task 'LabUpdateAgent' created (daily at 6 PM + ${pcNum}x5 min offset)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not deploy update agent: $($_.Exception.Message)" "ERROR"
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

# Step 22: Ensure OpenSSH Server is disabled (no remote access by design)
Write-Log "Step 22: Ensuring OpenSSH Server is disabled..." "INFO"

try {
    $sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($sshService) {
        if ($sshService.Status -eq 'Running') { Stop-Service sshd -Force -ErrorAction SilentlyContinue }
        Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "OpenSSH Server service stopped and disabled" "INFO"
    }

    # Close firewall rules if they exist
    Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    Get-NetFirewallRule -DisplayName "OpenSSH SSH Server (sshd)" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue

    Write-Log "SSH disabled (no remote access by design)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable SSH: $($_.Exception.Message)" "WARNING"
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
Write-Log "Step 24: Removing bloatware apps..." "INFO"

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

    # Remove leftover folders (Admin profile via env vars)
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

    # Also clean Student profile (env vars point to Admin when running as Admin)
    $studentProfileDir = "C:\Users\Student"
    if (Test-Path $studentProfileDir) {
        Remove-Item "$studentProfileDir\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$studentProfileDir\AppData\Local\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove OneDrive from Explorer sidebar
    $oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $oneDrivePolicy)) { New-Item -Path $oneDrivePolicy -Force | Out-Null }
    Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -Force

    # Remove scheduled tasks
    Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match 'OneDrive' } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    # Clean OneDrive Run entries from all user profiles
    foreach ($hive in $hkuPaths) {
        $runPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runPath) {
            Get-Item -Path $runPath -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Property |
                Where-Object { $_ -like "*OneDrive*" } |
                ForEach-Object { Remove-ItemProperty -Path $runPath -Name $_ -Force -ErrorAction SilentlyContinue }
        }
    }
    # Also HKLM Run
    Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Property |
        Where-Object { $_ -like "*OneDrive*" } |
        ForEach-Object { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $_ -Force -ErrorAction SilentlyContinue }

    Write-Log "OneDrive removed and disabled (including Run key residuals)" "SUCCESS"
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

    # Disable Search Highlights and web search for all user profiles
    foreach ($hive in $hkuPaths) {
        $searchSettings = "$hive\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        if (-not (Test-Path $searchSettings)) { New-Item -Path $searchSettings -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $searchSettings -Name "IsDynamicSearchBoxEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

        $explorerPolicies = "$hive\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $explorerPolicies)) { New-Item -Path $explorerPolicies -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $explorerPolicies -Name "DisableSearchBoxSuggestions" -Value 1 -Force -ErrorAction SilentlyContinue
    }

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

    # Disable Edge update scheduled tasks
    Get-ScheduledTask -TaskName "MicrosoftEdge*" -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null

    Write-Log "Microsoft Edge neutered (shortcuts removed, auto-start disabled, update tasks disabled)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not neuter Microsoft Edge: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 27b: Clean startup apps (suppress annoying popups on login)
Write-Log "Step 27b: Cleaning startup apps..." "INFO"

try {
    # UniKey: ensure startup shortcut uses the wrapper VBS that sets ShowDlg=0
    # (UniKey overwrites ShowDlg=1 on exit, so registry-only fix doesn't persist)
    $unikeyLnk = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\UniKey.lnk"
    $launcherVbs = "C:\LabTools\start-unikey.vbs"
    if ((Test-Path $unikeyLnk) -and (Test-Path $launcherVbs)) {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($unikeyLnk)
        if ($shortcut.TargetPath -ne (Get-Command wscript.exe).Path) {
            $shortcut.TargetPath = "wscript.exe"
            $shortcut.Arguments = "`"$launcherVbs`""
            $shortcut.WorkingDirectory = "C:\Program Files\UniKey"
            $shortcut.WindowStyle = 7
            $shortcut.Description = "UniKey Vietnamese Input (silent start)"
            $shortcut.Save()
            Write-Log "UniKey startup shortcut updated to use wrapper" "INFO"
        }
    }

    # Also set registry values for good measure (covers fresh profiles)
    foreach ($hive in $hkuPaths) {
        $uniKeyPath = "$hive\Software\PkLong\UniKey"
        if (-not (Test-Path $uniKeyPath)) { New-Item -Path $uniKeyPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $uniKeyPath -Name "ShowDlg" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $uniKeyPath -Name "AutoUpdate" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Startup apps cleaned (UniKey dialog suppressed via wrapper)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not clean startup apps: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 28: Clean taskbar (remove clutter, keep only essentials)
Write-Log "Step 28: Cleaning taskbar..." "INFO"

try {
    # Apply taskbar cleanup to all user profiles
    foreach ($hive in $hkuPaths) {
        $taskbarPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $taskbarPath)) { New-Item -Path $taskbarPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $taskbarPath -Name "TaskbarMn" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $taskbarPath -Name "ShowTaskViewButton" -Value 0 -Force -ErrorAction SilentlyContinue
        # TaskbarDa (Widgets) is ACL-protected per-user; disabled machine-wide via HKLM Dsh policy in Step 26
        Set-ItemProperty -Path $taskbarPath -Name "ShowCopilotButton" -Value 0 -Force -ErrorAction SilentlyContinue

        $searchRegPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchRegPath)) { New-Item -Path $searchRegPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $searchRegPath -Name "SearchboxTaskbarMode" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Clear pinned taskbar items for ALL user profiles (Win11 stores pins per-user)
    $userProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }
    foreach ($profile in $userProfiles) {
        $pinnedPath = Join-Path $profile.FullName "AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (Test-Path $pinnedPath) {
            Get-ChildItem -Path $pinnedPath -Filter "*.lnk" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike "*File Explorer*" } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Log "Cleared taskbar pins for $($profile.Name)" "INFO"
        }
    }
    # Also clear for Default profile (new users)
    $defaultPinned = "C:\Users\Default\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $defaultPinned) {
        Get-ChildItem -Path $defaultPinned -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*File Explorer*" } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Clear Taskband registry for current user and Student user
    $taskband = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    if (Test-Path $taskband) {
        Remove-ItemProperty -Path $taskband -Name "Favorites" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $taskband -Name "FavoritesResolve" -Force -ErrorAction SilentlyContinue
    }
    # Clear for Student via SID
    try {
        $studentSID = (New-Object System.Security.Principal.NTAccount("Student")).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $studentTB = "REGISTRY::HKEY_USERS\$studentSID\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        if (Test-Path $studentTB) {
            Remove-ItemProperty -Path $studentTB -Name "Favorites" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $studentTB -Name "FavoritesResolve" -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Could not clear Student taskband (user may not exist yet): $($_.Exception.Message)" "INFO"
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

    # Disable advertising ID for all user profiles
    foreach ($hive in $hkuPaths) {
        $adInfo = "$hive\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        if (-not (Test-Path $adInfo)) { New-Item -Path $adInfo -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $adInfo -Name "Enabled" -Value 0 -Force -ErrorAction SilentlyContinue
    }

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
    # Apply UX cleanup to all user profiles
    foreach ($hive in $hkuPaths) {
        # Disable Xbox Game Bar (Win+G accidental activation confuses NVDA)
        $gameBar = "$hive\Software\Microsoft\GameBar"
        if (-not (Test-Path $gameBar)) { New-Item -Path $gameBar -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $gameBar -Name "UseNexusForGameBarEnabled" -Value 0 -Force -ErrorAction SilentlyContinue
        $gameDVR = "$hive\System\GameConfigStore"
        if (-not (Test-Path $gameDVR)) { New-Item -Path $gameDVR -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $gameDVR -Name "GameDVR_Enabled" -Value 0 -Force -ErrorAction SilentlyContinue

        # Disable Snap Layouts hover tooltip
        $advPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "EnableSnapAssistFlyout" -Value 0 -Force -ErrorAction SilentlyContinue
        }

        # Disable OOBE nag
        $upe = "$hive\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
        if (-not (Test-Path $upe)) { New-Item -Path $upe -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $upe -Name "ScoobeSystemSettingEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

        # Disable Start menu suggestions / promoted apps / lock screen tips
        $cd = "$hive\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $cd) {
            foreach ($name in @("SubscribedContent-338388Enabled","SubscribedContent-353694Enabled","SubscribedContent-353696Enabled","OemPreInstalledAppsEnabled","PreInstalledAppsEnabled","SilentInstalledAppsEnabled","RotatingLockScreenOverlayEnabled","RotatingLockScreenEnabled")) {
                Set-ItemProperty -Path $cd -Name $name -Value 0 -Force -ErrorAction SilentlyContinue
            }
        }

        # Disable touch keyboard auto-show
        $touchKB = "$hive\Software\Microsoft\TabletTip\1.7"
        if (-not (Test-Path $touchKB)) { New-Item -Path $touchKB -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $touchKB -Name "TipbandDesiredVisibility" -Value 0 -Force -ErrorAction SilentlyContinue
    }

    # Machine-wide Game DVR policy
    $gameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDVRPolicy)) { New-Item -Path $gameDVRPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRPolicy -Name "AllowGameDVR" -Value 0 -Force

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

# Step 33b: Set file associations (.pdf -> SumatraPDF). Students read EPUBs via SM Readmate library.
Write-Log "Step 33b: Setting file associations (.pdf -> SumatraPDF)..." "INFO"

try {
    $sumatraExe = "C:\Users\Student\AppData\Local\SumatraPDF\SumatraPDF.exe"
    if (-not (Test-Path $sumatraExe)) {
        $sumatraExe = "C:\Program Files\SumatraPDF\SumatraPDF.exe"
    }

    # ── Unregister any leftover Thorium .epub associations from prior deployments ──
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\ThoriumReader.epub" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\Applications\Thorium.exe" -Recurse -Force -ErrorAction SilentlyContinue
    cmd /c ftype ThoriumReader.epub= 2>$null
    cmd /c assoc .epub= 2>$null

    # ── Register SumatraPDF ProgID in HKLM (machine-wide) ──
    $sumatraProgID = "HKLM:\SOFTWARE\Classes\SumatraPDF.pdf"
    if (-not (Test-Path $sumatraProgID)) { New-Item -Path $sumatraProgID -Force | Out-Null }
    Set-ItemProperty -Path $sumatraProgID -Name "(default)" -Value "PDF Document" -Force
    $sumatraShell = "$sumatraProgID\shell\open\command"
    if (-not (Test-Path $sumatraShell)) { New-Item -Path $sumatraShell -Force | Out-Null }
    Set-ItemProperty -Path $sumatraShell -Name "(default)" -Value "`"$sumatraExe`" `"%1`"" -Force
    $sumatraIcon = "$sumatraProgID\DefaultIcon"
    if (-not (Test-Path $sumatraIcon)) { New-Item -Path $sumatraIcon -Force | Out-Null }
    Set-ItemProperty -Path $sumatraIcon -Name "(default)" -Value "`"$sumatraExe`",0" -Force

    # ── Set machine-wide default for .pdf ──
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\.pdf" -Name "(default)" -Value "SumatraPDF.pdf" -Force

    # ── OpenWithProgids (add ours, remove Edge's claim on .pdf) ──
    $pdfOWP = "HKLM:\SOFTWARE\Classes\.pdf\OpenWithProgids"
    if (-not (Test-Path $pdfOWP)) { New-Item -Path $pdfOWP -Force | Out-Null }
    New-ItemProperty -Path $pdfOWP -Name "SumatraPDF.pdf" -Value ([byte[]]@()) -PropertyType Binary -Force | Out-Null
    Remove-ItemProperty -Path $pdfOWP -Name "MSEdgePDF" -Force -ErrorAction SilentlyContinue

    # ── Register in Applications key ──
    $sumatraApp = "HKLM:\SOFTWARE\Classes\Applications\SumatraPDF.exe\shell\open\command"
    if (-not (Test-Path $sumatraApp)) { New-Item -Path $sumatraApp -Force | Out-Null }
    Set-ItemProperty -Path $sumatraApp -Name "(default)" -Value "`"$sumatraExe`" `"%1`"" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\Applications\SumatraPDF.exe" -Name "FriendlyAppName" -Value "SumatraPDF" -Force
    $sumatraST = "HKLM:\SOFTWARE\Classes\Applications\SumatraPDF.exe\SupportedTypes"
    if (-not (Test-Path $sumatraST)) { New-Item -Path $sumatraST -Force | Out-Null }
    Set-ItemProperty -Path $sumatraST -Name ".pdf" -Value "" -Force

    # ── Neuter MSEdgePDF so even if UserChoice still points there, SumatraPDF opens ──
    $edgePdfCmd = "HKLM:\SOFTWARE\Classes\MSEdgePDF\shell\open\command"
    if (Test-Path $edgePdfCmd) {
        Set-ItemProperty -Path $edgePdfCmd -Name "(default)" -Value "`"$sumatraExe`" `"%1`"" -Force
        Write-Log "MSEdgePDF ProgID neutered (now opens SumatraPDF)" "INFO"
    }

    # ── Per-user: register ProgIDs, OpenWithProgids, OpenWithList for all profiles ──
    foreach ($hive in $hkuPaths) {
        # Clean up any leftover Thorium associations for this user
        Remove-Item -Path "$hive\SOFTWARE\Classes\ThoriumReader.epub" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.epub\UserChoice" -Force -ErrorAction SilentlyContinue

        # SumatraPDF.pdf ProgID
        $uSumatraCmd = "$hive\SOFTWARE\Classes\SumatraPDF.pdf\shell\open\command"
        if (-not (Test-Path $uSumatraCmd)) { New-Item -Path $uSumatraCmd -Force | Out-Null }
        Set-ItemProperty -Path $uSumatraCmd -Name "(default)" -Value "`"$sumatraExe`" `"%1`"" -Force
        Set-ItemProperty -Path "$hive\SOFTWARE\Classes\SumatraPDF.pdf" -Name "(default)" -Value "PDF Document" -Force

        # .pdf OpenWithProgids (add SumatraPDF, remove Edge)
        $uPdfOWP = "$hive\SOFTWARE\Classes\.pdf\OpenWithProgids"
        if (-not (Test-Path $uPdfOWP)) { New-Item -Path $uPdfOWP -Force | Out-Null }
        New-ItemProperty -Path $uPdfOWP -Name "SumatraPDF.pdf" -Value ([byte[]]@()) -PropertyType Binary -Force | Out-Null
        Remove-ItemProperty -Path $uPdfOWP -Name "MSEdgePDF" -Force -ErrorAction SilentlyContinue

        # OpenWithList — put SumatraPDF first
        $uPdfOWL = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\OpenWithList"
        if (-not (Test-Path $uPdfOWL)) { New-Item -Path $uPdfOWL -Force | Out-Null }
        Set-ItemProperty -Path $uPdfOWL -Name "a" -Value "SumatraPDF.exe" -Force
        Set-ItemProperty -Path $uPdfOWL -Name "MRUList" -Value "a" -Force

        # Remove UserChoice for .pdf if it points elsewhere (ACL-protected, best-effort)
        $ucPath = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice"
        if (Test-Path $ucPath) { Remove-Item -Path $ucPath -Force -ErrorAction SilentlyContinue }
    }

    # ── Use assoc/ftype as belt-and-suspenders ──
    cmd /c ftype SumatraPDF.pdf="`"$sumatraExe`" `"%1`"" 2>$null
    cmd /c assoc .pdf=SumatraPDF.pdf 2>$null

    # Notify Explorer shell of association changes
    $shChangeCode = 'using System; using System.Runtime.InteropServices; public class Shell32Assoc { [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2); }'
    Add-Type -TypeDefinition $shChangeCode -ErrorAction SilentlyContinue
    [Shell32Assoc]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

    Write-Log "File associations set: .pdf -> SumatraPDF (.epub unregistered, use SM Readmate library)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set file associations: $($_.Exception.Message)" "ERROR"
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

# Step 36: Create System Restore point as post-configuration baseline
Write-Log "Step 36: Creating System Restore point..." "INFO"

try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Vietnam Lab post-deployment baseline" -RestorePointType "APPLICATION_INSTALL" -ErrorAction Stop
    Write-Log "System Restore point created" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not create restore point: $($_.Exception.Message)" "INFO"
    $successCount++  # Non-critical
}

# Step 37: Grant write permissions to Sao Mai apps (SMTT stores data in its install folder)
Write-Log "Step 37: Fixing Sao Mai app permissions..." "INFO"

try {
    $smttPath = "C:\Program Files (x86)\SaoMai\SMTT"
    if (Test-Path $smttPath) {
        icacls $smttPath /grant "BUILTIN\Users:(OI)(CI)(M)" /T /Q 2>$null
        Write-Log "Granted Users modify access to $smttPath" "SUCCESS"
    } else {
        Write-Log "SMTT not found at $smttPath — skipping" "INFO"
    }
    $successCount++
} catch {
    Write-Log "Could not set SMTT permissions: $($_.Exception.Message)" "INFO"
    $successCount++  # Non-critical
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
Write-Host "  welcome-audio $(if(Test-Path "C:\LabTools\welcome-audio.ps1"){"OK"}else{"MISSING"})" -ForegroundColor $(if(Test-Path "C:\LabTools\welcome-audio.ps1"){"Green"}else{"Red"})
Write-Host ""
Write-Host "Desktop:" -ForegroundColor White
Write-Host "  Shortcuts     Standardized (wiped + recreated for all apps)" -ForegroundColor White
Write-Host "  Apps          NVDA, Word, Excel, PowerPoint, Firefox, VLC, Audacity," -ForegroundColor White
Write-Host "                SumatraPDF, Kiwix, GoldenDict," -ForegroundColor White
Write-Host "                Sao Mai Typing Tutor, Readmate," -ForegroundColor White
Write-Host "                Calculator, My USB, Language Toggle, NVDA Restore" -ForegroundColor White
Write-Host "  Vi folders    Tai Lieu, Am Nhac, Truyen, Hoc Tap, Tro Choi" -ForegroundColor White
Write-Host ""
Write-Host "Accessibility:" -ForegroundColor White
Write-Host "  Magnifier    Win+Plus (full-screen, 200%)" -ForegroundColor White
Write-Host "  High Contrast Win+Left Alt+Print Screen" -ForegroundColor White
Write-Host ""
Write-Host "Safety & Hardening:" -ForegroundColor White
Write-Host "  Firefox       Policies deployed (no updates, Vietnamese, no PiP, accessibility)" -ForegroundColor White
Write-Host "  VLC           Audio-only, NVDA-friendly, volume cap 100%" -ForegroundColor White
Write-Host "  Audacity      MME audio host, no splash, beep on completion" -ForegroundColor White
Write-Host "  SumatraPDF    Continuous scroll, fit-width, system colors" -ForegroundColor White
Write-Host "  File assoc    .pdf -> SumatraPDF (EPUBs via SM Readmate library)" -ForegroundColor White
Write-Host "  Kiwix         130% zoom, reopen last tab" -ForegroundColor White
Write-Host "  GoldenDict    150% zoom, 18px article font, UI Automation" -ForegroundColor White
Write-Host "  Sticky Keys   Popup disabled (Shift x5)" -ForegroundColor White
Write-Host "  Filter Keys   Popup disabled (hold key)" -ForegroundColor White
Write-Host "  Toggle Keys   Beep enabled (Caps/Num/Scroll Lock)" -ForegroundColor White
Write-Host "  Volume limit  70% on each login" -ForegroundColor White
Write-Host "  Win Update    Disabled (offline)" -ForegroundColor White
Write-Host "  Notifications Toast, Notification Center, tips/suggestions all disabled" -ForegroundColor White
Write-Host "  Narrator      Shortcut disabled (NVDA only)" -ForegroundColor White
Write-Host "  Power         No sleep on AC, no hibernate" -ForegroundColor White
Write-Host "  Battery       Report saved to C:\LabTools\battery-report.htm" -ForegroundColor White
Write-Host "  NVDA backup   Restore script at C:\LabTools\restore-nvda.ps1" -ForegroundColor White
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
Write-Host "  SSH server    Disabled (no remote access)" -ForegroundColor White
Write-Host "  Update agent  Daily 6-7:30 PM (LabUpdateAgent task, pulls from GitHub)" -ForegroundColor White
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Some steps failed. Check the log and re-run this script." -ForegroundColor Yellow
} else {
    Write-Host "This laptop is ready for deployment." -ForegroundColor Green
}

Write-Host ""
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

# Unload registry hives if we loaded them
if ($studentHiveLoaded) {
    [gc]::Collect()
    Start-Sleep -Seconds 1
    reg unload "HKU\$studentSID" 2>$null | Out-Null
    Write-Log "Unloaded Student registry hive" "INFO"
}
if ($defaultLoaded) {
    reg unload "HKU\DefaultProfile" 2>$null | Out-Null
    Write-Log "Unloaded Default profile registry hive" "INFO"
}

if (-not $env:LAB_BOOTSTRAP) { pause }
