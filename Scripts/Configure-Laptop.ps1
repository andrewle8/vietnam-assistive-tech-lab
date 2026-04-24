# Vietnam Lab Deployment - Loaner Laptop Configuration
# Version: 1.0
# Run on each lab laptop after scripts 1-3. Requires Administrator.
# Applies Windows hardening, desktop shortcuts, NVDA config, file associations,
# LabAdmin/Student accounts, language pack, power settings, and more.
# Last Updated: April 2026

param(
    [string]$LogPath = "$PSScriptRoot\laptop-config.log",
    [int]$PCNumber = 0
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

# Materialize Student profile (C:\Users\Student\NTUSER.DAT) if missing.
# New-LocalUser only creates the SAM account — the on-disk profile is normally provisioned
# by Windows on Student's first interactive logon. Without NTUSER.DAT we cannot reg.exe load
# Student's hive, so per-user writes below would fall through to the Default profile only,
# and Win11 24H2 OOBE does NOT reliably propagate every key from Default to a new user's
# hive on first login (observed: TaskbarMn, SearchboxTaskbarMode, wallpaper, UniKey ShowDlg).
# The Win32 CreateProfile API provisions the profile directory and hive non-interactively so
# every per-user write in this script lands in Student's real hive on the first run.
#
# Historical bug: a previous version gated this block on `-not (Test-Path NTUSER.DAT)`. On
# freshly-created Student accounts, New-LocalUser's background profile scaffolding can
# transiently create C:\Users\Student\NTUSER.DAT and then delete it within ~100ms, causing
# Test-Path to flip TRUE→FALSE between the gate and the later hive-load code. When it
# returned TRUE we skipped CreateProfile, then NTUSER.DAT was gone by the hive-load step
# and Student hive was not loaded. Consequence: ShowDlg=0, Languages, wallpaper, etc. only
# hit Admin + Default profile, leaving Student with a partially-configured hive after first
# login. Fix: always call CreateProfile when we have a SID (it's idempotent — returns
# 0x800700B7 ERROR_ALREADY_EXISTS if the profile exists, which we accept as success), then
# poll for NTUSER.DAT to be present AND non-empty before continuing.
if ($studentSID) {
    try {
        Add-Type -Namespace LabProfile -Name Userenv -MemberDefinition @'
[DllImport("userenv.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern int CreateProfile(
    [MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,
    [MarshalAs(UnmanagedType.LPWStr)] string pszUserName,
    [MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszProfilePath,
    uint cchProfilePath);
'@ -ErrorAction SilentlyContinue
        $profilePath = New-Object System.Text.StringBuilder 260
        $hr = [LabProfile.Userenv]::CreateProfile($studentSID, "Student", $profilePath, [uint32]$profilePath.Capacity)
        # Poll for NTUSER.DAT ready: exists AND readable AND size > 0. Win11 CreateProfile
        # can return before the hive file is fully flushed; 10×500ms gives up to 5s.
        $ntUser = "C:\Users\Student\NTUSER.DAT"
        $ready  = $false
        for ($i = 0; $i -lt 10; $i++) {
            $fi = Get-Item $ntUser -Force -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt 0) { $ready = $true; break }
            Start-Sleep -Milliseconds 500
        }
        if ($ready) {
            Write-Log "Student profile ready at $($profilePath.ToString()) (HR=0x$('{0:X8}' -f $hr))" "SUCCESS"
        } else {
            Write-Log "CreateProfile HR=0x$('{0:X8}' -f $hr) but NTUSER.DAT not ready after 5s — per-user writes may fall through to Default profile" "WARNING"
        }
    } catch {
        Write-Log "CreateProfile failed: $($_.Exception.Message)" "WARNING"
    }
}

# Build array of registry hive paths to target (Admin HKCU + Student HKU + Default profile)
# Verify each hive is actually writable by Test-Path — reg.exe exit codes are unreliable under PowerShell.
$hkuPaths = @("HKCU:")
$studentHiveLoaded = $false
if ($studentSID) {
    $studentHivePath = "REGISTRY::HKEY_USERS\$studentSID"
    $studentSoftwarePath = "$studentHivePath\Software"
    if (Test-Path $studentSoftwarePath) {
        # Student is logged in — SID already in HKU, hive is writable
        $hkuPaths += $studentHivePath
        Write-Log "Student hive already loaded (user logged in)" "INFO"
    } else {
        # Student is NOT logged in — manually load their NTUSER.DAT
        $studentNtuser = "C:\Users\Student\NTUSER.DAT"
        if (Test-Path $studentNtuser) {
            & reg.exe load "HKU\$studentSID" $studentNtuser 2>&1 | Out-Null
            # Verify the load worked by actually probing the hive (reg.exe exit codes unreliable under PS)
            Start-Sleep -Milliseconds 200
            if (Test-Path $studentSoftwarePath) {
                $studentHiveLoaded = $true
                $hkuPaths += $studentHivePath
                Write-Log "Loaded Student registry hive from NTUSER.DAT" "INFO"
            } else {
                Write-Log "WARNING: reg load reported ok but Student hive not reachable — per-user settings will not apply to Student." "ERROR"
            }
        } else {
            Write-Log "WARNING: Student NTUSER.DAT not found — Student has never logged in. Per-user settings will apply via Default profile only." "ERROR"
        }
    }
}
$defaultLoaded = $false
$defaultNtuser = "C:\Users\Default\NTUSER.DAT"
$defaultHivePath = "REGISTRY::HKEY_USERS\DefaultProfile"
if ((Test-Path $defaultNtuser) -and -not (Test-Path "$defaultHivePath\Software")) {
    & reg.exe load "HKU\DefaultProfile" $defaultNtuser 2>&1 | Out-Null
    Start-Sleep -Milliseconds 200
    if (Test-Path "$defaultHivePath\Software") {
        $defaultLoaded = $true
        $hkuPaths += $defaultHivePath
    } else {
        Write-Log "WARNING: Default profile hive load failed" "WARNING"
    }
}

Write-Log "Registry targets: $($hkuPaths -join ', ')" "INFO"

# Step 1: Ensure LabTools directory exists
Write-Log "Step 1: Creating LabTools directory..." "INFO"

if (-not (Test-Path $labToolsDir)) {
    New-Item -Path $labToolsDir -ItemType Directory -Force | Out-Null
    Write-Log "Created directory: $labToolsDir" "SUCCESS"
    $successCount++
}

# Legacy artifact cleanup (Tailscale, rclone, Thorium, Quorum, LEAP, nvdaRemote, etc.)
# moved to Scripts\Uninstall-Legacy.ps1 — run once on upgrade-in-place laptops.
# Fresh laptops never had these, so Configure-Laptop.ps1 skips this cleanup on every run.

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

    # Set-WinUserLanguageList only affects the running user (Admin here). Propagate the
    # same preference list to every OTHER user hive we know about so Student (existing and
    # future) gets a Vietnamese UI without a manual Settings trip.
    #
    # 1) Copy-UserInternationalSettingsToSystem seeds the Default profile + Welcome Screen,
    #    so any user profile created AFTER this point (e.g. a fresh Student on a machine
    #    where CreateProfile hasn't run yet) inherits vi-VN on first login. Win10 21H2+.
    # 2) Direct HKU writes of Languages (REG_MULTI_SZ) into each loaded hive cover Student
    #    when their profile is already materialized (normal path after the CreateProfile
    #    call in pre-flight).
    if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
        try {
            Copy-UserInternationalSettingsToSystem -NewUser $true -WelcomeScreen $true -ErrorAction Stop
            Write-Log "Propagated language settings to Default profile + Welcome Screen" "SUCCESS"
        } catch {
            Write-Log "Copy-UserInternationalSettingsToSystem failed: $($_.Exception.Message)" "WARNING"
        }
    }
    foreach ($hive in $hkuPaths) {
        $up = "$hive\Control Panel\International\User Profile"
        if (-not (Test-Path $up)) { New-Item -Path $up -Force -ErrorAction SilentlyContinue | Out-Null }
        New-ItemProperty -Path $up -Name "Languages" -Value @("vi-VN","en-US") -PropertyType MultiString -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log "Per-user language list (vi-VN primary, en-US secondary) written to $($hkuPaths.Count) hive(s)" "SUCCESS"

    # Set region and locale to Vietnam
    Set-WinHomeLocation -GeoId 0xFB  # Vietnam (251)
    Set-Culture "vi-VN"
    Write-Log "Region set to Vietnam, culture set to vi-VN" "SUCCESS"

    # Set timezone to Southeast Asia (UTC+7 Ho Chi Minh)
    Set-TimeZone -Id "SE Asia Standard Time"
    # Disable the "Set time zone automatically" service. Without this, Windows geolocates
    # the laptop and overrides Set-TimeZone the moment it sees a non-VN network (e.g. at
    # the deployment bench in the US), leaving students on a US clock until someone
    # flips the toggle in Settings. Stopping + disabling tzautoupdate pins the clock.
    Stop-Service -Name tzautoupdate -Force -ErrorAction SilentlyContinue
    Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Log "Timezone set to SE Asia Standard Time (UTC+7); tzautoupdate service disabled" "SUCCESS"

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

    # Set Word/Excel/PowerPoint default save location to D:\ (the student USB).
    # Blind students can't realistically navigate the Save As folder tree or type full paths —
    # this makes Ctrl+S → filename → Enter pre-fill D:\ in the Save As dialog.
    # If USB is unplugged, Office gracefully falls back to Documents without errors.
    # Office 16.0 is stable across 2016/2019/2021/2024/M365 — key names unchanged for 10+ years.
    # D: is force-assigned to the student's STU-### USB by the LabReassignStudentUSB task (Step 19).
    # Writes to HKCU + Student SID + DefaultProfile (if loaded) via $hkuPaths so re-running the
    # script reasserts the setting after any Office reset / profile rebuild.
    foreach ($hive in $hkuPaths) {
        $wordOpts = "$hive\Software\Microsoft\Office\16.0\Word\Options"
        if (-not (Test-Path $wordOpts)) { New-Item -Path $wordOpts -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $wordOpts -Name "DOC-PATH"     -Value "D:\" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wordOpts -Name "PICTURE-PATH" -Value "D:\" -Force -ErrorAction SilentlyContinue
        # Word AutoRecover: save every 5 minutes (default is 10). Blind students can lose work
        # silently if Word crashes — tight recovery window minimizes data loss.
        Set-ItemProperty -Path $wordOpts -Name "AutoSave"       -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wordOpts -Name "AutoRecoverTime" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue

        # Excel: DefaultPath under Options has been the supported key since Office 2003.
        $excelOpts = "$hive\Software\Microsoft\Office\16.0\Excel\Options"
        if (-not (Test-Path $excelOpts)) { New-Item -Path $excelOpts -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $excelOpts -Name "DefaultPath" -Value "D:\" -Force -ErrorAction SilentlyContinue

        # PowerPoint: DefaultPath under Options is the documented Save As default folder
        # (same pattern as Excel, honored by Office 2016 through M365).
        $pptOpts = "$hive\Software\Microsoft\Office\16.0\PowerPoint\Options"
        if (-not (Test-Path $pptOpts)) { New-Item -Path $pptOpts -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $pptOpts -Name "DefaultPath" -Value "D:\" -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Office default save location set to D:\ (Word/Excel/PowerPoint) + Word AutoRecover=5min on $($hkuPaths.Count) hive(s)" "SUCCESS"

    # Suppress the OneDrive / cloud-save nag in file dialogs (no cloud accounts deployed).
    # (Backstage itself cannot be cleanly disabled in current O365 Enterprise builds —
    # SkipOpenSaveDialog stopped working somewhere around the 2024 update. Students are
    # instructed to use F12 for Save As, which bypasses Backstage directly.)
    foreach ($hive in $hkuPaths) {
        $commonInt = "$hive\Software\Microsoft\Office\16.0\Common\Internet"
        if (-not (Test-Path $commonInt)) { New-Item -Path $commonInt -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $commonInt -Name "OnlineStorage" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Log "OneDrive nag suppressed in Office file dialogs" "SUCCESS"

    $successCount++
} catch {
    Write-Log "Could not fully configure Vietnamese locale: $($_.Exception.Message)" "ERROR"
    Write-Log "You may need to set language manually: Settings > Time & Language > Language" "ERROR"
    $failCount++
}

# Disable Windows language/layout hotkeys so UniKey's Ctrl+Shift is the only V/E toggle.
# Windows defaults: Alt+Shift switches language, Ctrl+Shift switches layout. Both can desync
# Windows IME state from UniKey state if hit accidentally during typing drills — invisible
# to a blind student and hard to recover from. Vietnamese Telex IME stays installed
# (reachable via Win+Space or Settings) as a deliberate fallback; only the accidental
# hotkeys are neutralized. Values: "1"=Alt+Shift, "2"=Ctrl+Shift, "3"=disabled.
# Reversal: delete the two values, or Settings → Time & language → Typing → Advanced
# keyboard settings → Language bar options → Change Key Sequence.
Write-Log "Disabling Windows language/layout hotkeys (UniKey remains the single V/E toggle)..." "INFO"

try {
    $hotkeyHives = 0
    foreach ($hive in $hkuPaths) {
        $togglePath = "$hive\Keyboard Layout\Toggle"
        if (-not (Test-Path $togglePath)) {
            New-Item -Path $togglePath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $togglePath -Name "Language Hotkey" -Value "3" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $togglePath -Name "Layout Hotkey"   -Value "3" -Force -ErrorAction SilentlyContinue
        $hotkeyHives++
    }
    Write-Log "Language/layout hotkeys disabled on $hotkeyHives hive(s) — UniKey Ctrl+Shift is the single V/E toggle" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable language hotkeys: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Pin the default keyboard input method to US English on every login.
# Without this, Windows picks the first language's default IME (= Vietnamese Telex, since
# vi-VN is the primary display language) and the taskbar pill shows "VIE" on boot/unlock.
# Students open the lid and see Vietnamese by default — confusing and not what we want.
# Pinning to en-US here means the pill always reads "ENG" on login; UniKey handles Vietnamese
# input when the student toggles it with Ctrl+Shift.
#
# TWO registry mechanisms are needed — InputMethodOverride alone is NOT sufficient:
#   1. HKCU\Control Panel\International\User Profile\InputMethodOverride — modern (Win10+).
#   2. HKCU\Keyboard Layout\Preload — legacy, read at logon. New-WinUserLanguageList populates
#      this based on language-list order, so after making vi-VN the primary display language
#      above, Preload\1 ends up as Vietnamese (0000042a). Windows loads Preload\1 FIRST at
#      session start, overriding InputMethodOverride. We must explicitly swap it.
#      00000409 = US English, 0000042a = Vietnamese.
# Writes to HKCU + Student SID + Default profile via $hkuPaths.
Write-Log "Pinning default keyboard to US English on login..." "INFO"

try {
    $imeHives = 0
    foreach ($hive in $hkuPaths) {
        $profPath = "$hive\Control Panel\International\User Profile"
        if (-not (Test-Path $profPath)) {
            New-Item -Path $profPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $profPath -Name "InputMethodOverride" -Value "0409:00000409" -Force -ErrorAction SilentlyContinue

        $preloadPath = "$hive\Keyboard Layout\Preload"
        if (-not (Test-Path $preloadPath)) {
            New-Item -Path $preloadPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $preloadPath -Name "1" -Value "00000409" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $preloadPath -Name "2" -Value "0000042a" -Force -ErrorAction SilentlyContinue

        $imeHives++
    }
    Write-Log "Default input pinned to en-US (InputMethodOverride + Preload\1) on $imeHives hive(s)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not pin default input method: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 4b: Windows 11 blind-student friction fixes.
# Each of these was identified as "likely to hit in daily use" by the deployment audit.
# All are reversible registry tweaks — no policy layers, matches Minimal Upkeep Philosophy.
Write-Log "Applying Windows 11 friction fixes for blind student use..." "INFO"
try {
    # 1. Disable Windows 11 startup sound — it masks NVDA's "NVDA đang chạy" announcement on boot/wake.
    $bootAnim = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation"
    if (-not (Test-Path $bootAnim)) { New-Item -Path $bootAnim -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $bootAnim -Name "DisableStartupSound" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    $sysPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $sysPol)) { New-Item -Path $sysPol -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $sysPol -Name "DisableStartupSound" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # 2. NumLock off at boot — Dell 5420 has no numpad, NumLock state can interfere with NVDA laptop layout commands.
    # 3. Explorer LaunchTo=1 — open File Explorer to "This PC" (disk list) not "Home" (recent files).
    # 4. Clipboard history disabled — Win+V triggers a modal dialog that interrupts NVDA flow.
    # 5. Notifications always unrestricted — prevents Focus Assist from accidentally muting NVDA + toast audio.
    foreach ($hive in $hkuPaths) {
        $kbIndicators = "$hive\Control Panel\Keyboard"
        if (-not (Test-Path $kbIndicators)) { New-Item -Path $kbIndicators -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $kbIndicators -Name "InitialKeyboardIndicators" -Value "0" -Force -ErrorAction SilentlyContinue

        $explAdv = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $explAdv)) { New-Item -Path $explAdv -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $explAdv -Name "LaunchTo" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        $clip = "$hive\Software\Microsoft\Clipboard"
        if (-not (Test-Path $clip)) { New-Item -Path $clip -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $clip -Name "EnableClipboardHistory" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        $notifSet = "$hive\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
        if (-not (Test-Path $notifSet)) { New-Item -Path $notifSet -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $notifSet -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    # 6. Defer Windows feature updates (not quality updates) — prevents disruptive Win11 feature upgrades
    # that re-enable Spotlight, Copilot, widgets, and the startup sound.
    $wuPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPol)) { New-Item -Path $wuPol -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $wuPol -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $wuPol -Name "DeferQualityUpdatesPeriodInDays" -Value 7 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Log "Windows 11 friction fixes applied (startup sound, NumLock, Explorer, clipboard, notifications, feature-update deferral)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not apply all Windows 11 friction fixes: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 4c: Apply Microsoft Edge policies for the PDF reader experience.
# Edge's built-in PDF reader supports tagged-PDF navigation (H/K/T) with NVDA, exposes
# SAPI5 voices (including Vi-Vu) via its Read Aloud feature (Ctrl+Shift+U), ships with
# Windows, and needs no separate installer. SumatraPDF was removed because it exposes
# no page-body text to screen readers (sumatrapdfreader#321). Adobe Reader DC has 2025
# NVDA regressions (#18800) and aggressive cloud-sign-in nags — skip it.
Write-Log "Applying Microsoft Edge policies for NVDA-accessible PDF reading..." "INFO"
try {
    # Edge policy keys (HKLM, no ADMX needed) — disable sign-in nag, enable Read Aloud,
    # keep PDFs inside Edge (not downloaded), disable cloud sync.
    $edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePol)) { New-Item -Path $edgePol -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $edgePol -Name "ReadAloudEnabled"            -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name "HideFirstRunExperience"      -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name "BrowserSignin"               -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name "SyncDisabled"                -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name "DefaultBrowserSettingEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name "AlwaysOpenPdfExternally"     -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Log "Edge policies applied; Read Aloud enabled; cloud sign-in disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not apply Edge policies: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Default browser: Edge (Windows default — left intentionally unchanged).
# Microsoft tightened default-browser-change paths on Win11 24H2 (UCPD.sys + restricted
# DISM/GPO seeding); Firefox-as-default would require bundling SetUserFTA.exe + a
# scheduled task and is fragile across Windows updates. Edge is NVDA-accessible for
# both browsing and PDFs, ships with Windows, and never needs babysitting. Firefox
# stays installed and on the Student desktop as a shortcut for students who want it.

# Language toggle shortcut removed. Student UI is Vietnamese-only by design so NVDA's
# Vietnamese synth reads everything correctly; admins who need to change language can
# do it via Settings > Time & language directly.

# Step 5: Configure Windows Magnifier for low-vision users
Write-Log "Step 5: Configuring Windows Magnifier for low-vision users..." "INFO"

try {
    # Enable Magnifier keyboard shortcut (Win+Plus) and set sensible defaults for all users
    # MagnificationMode: 1=docked, 2=full-screen, 3=lens. Manifest requests full-screen (=2).
    foreach ($hive in $hkuPaths) {
        $magPath = "$hive\Software\Microsoft\ScreenMagnifier"
        if (-not (Test-Path $magPath)) { New-Item -Path $magPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $magPath -Name "MagnificationMode" -Value 2 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $magPath -Name "Magnification" -Value 200 -Force -ErrorAction SilentlyContinue

        # Enable High Contrast keyboard shortcut (Win+Left Alt+Print Screen)
        $hcPath = "$hive\Control Panel\Accessibility\HighContrast"
        if (-not (Test-Path $hcPath)) { New-Item -Path $hcPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $hcPath -Name "Flags" -Value "126" -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Windows Magnifier defaults set (Win+Plus to launch, full-screen mode, 200%)" "SUCCESS"
    Write-Log "High contrast toggle enabled (Win+Left Alt+Print Screen)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure Magnifier settings: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 5b: (Removed — previously copied SumatraPDF per-user install from Admin to Student.
# SumatraPDF was removed from deployment; Edge handles PDFs accessibly without per-user copy.)
try {
    $successCount++
} catch {
    Write-Log "Step 5b placeholder: $($_.Exception.Message)" "WARNING"
}

# Step 6: Clean desktop and create shortcuts for screen reader navigation
Write-Log "Step 6: Creating managed desktop shortcuts and removing unmanaged ones..." "INFO"

try {
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $userDesktop = [Environment]::GetFolderPath("Desktop")

    # User desktop: wipe entirely. No lab shortcuts belong here — Step 14 later creates
    # NVDA.lnk in the user desktop for hotkey registration. Public desktop is cleaned
    # SELECTIVELY AFTER the create loop (remove only unmanaged .lnk names), so that if
    # an app is installed at an unexpected path and we can't resolve its target, the
    # working shortcut is preserved instead of destroyed by an upfront blanket wipe.
    # Prior behavior wiped upfront; when Kiwix/GoldenDict/Office were at non-standard
    # paths, shortcuts went missing permanently (see laptop-config.log history on
    # DEPLOY_02, 2026-04-22 16:38-18:11: Excel/PowerPoint/Word skipped repeatedly).
    Get-ChildItem -Path $userDesktop -Filter "*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Cleared user desktop shortcuts (public desktop cleaned selectively after create loop)" "INFO"

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
    # (Recycle Bin, Spotlight shell object, This PC — students use "USB" shortcut instead)
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

    # Ensure desktop icons are visible (HideIcons=0) and restart explorer so the
    # HideDesktopIcons flags (system icons: Recycle Bin, This PC, Spotlight) apply.
    foreach ($hive in $hkuPaths) {
        $advPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "HideIcons" -Value 0 -Force -ErrorAction SilentlyContinue
        }
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Start-Sleep -Seconds 2
    Write-Log "Hidden system icons (Recycle Bin, Spotlight, This PC) and refreshed desktop" "INFO"

    # Plain names — no number prefixes. NVDA users navigate the desktop alphabetically
    # and use first-letter keys to jump (press "W" for Word, "F" for Firefox, etc.).
    # Numbers broke first-letter nav and added noisy "zero one" speech on every item.
    # Direct IShellLink + IPersistFile::Save. WScript.Shell's Save() lossy-converts
    # the .lnk filename through the system ANSI codepage (CP-1252 on this box), which
    # corrupts Vietnamese chars outside Latin-1: "Từ Điển" becomes "T? Ði?n" and Save
    # throws "Unable to save shortcut". Thùng Rác happens to work because ù and á
    # are both in CP-1252. IPersistFile::Save takes LPCOLESTR (pure Unicode) so it
    # handles any Unicode filename regardless of the system codepage.
    if (-not ('ShellLinkCreator' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ShellLinkCreator {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] public class ShellLink { }
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder psz, int cch, IntPtr pfd, uint f);
        void GetIDList(out IntPtr p); void SetIDList(IntPtr p);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder psz, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string psz);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder psz, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string psz);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder psz, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string psz);
        void GetHotkey(out short h); void SetHotkey(short h);
        void GetShowCmd(out int s); void SetShowCmd(int s);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder psz, int cch, out int idx);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string psz, int idx);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string psz, uint r);
        void Resolve(IntPtr hwnd, uint f);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string psz);
    }
    [ComImport, Guid("0000010B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPersistFile {
        [PreserveSig] int GetClassID(out Guid g);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string f, uint m);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.Bool)] bool r);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
        void GetCurFile([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f);
    }
    public static void Create(string lnk, string target, string args, string desc, string workDir, string iconLoc) {
        IShellLinkW l = (IShellLinkW)(new ShellLink());
        l.SetPath(target);
        if (!string.IsNullOrEmpty(args))    l.SetArguments(args);
        if (!string.IsNullOrEmpty(desc))    l.SetDescription(desc);
        if (!string.IsNullOrEmpty(workDir)) l.SetWorkingDirectory(workDir);
        if (!string.IsNullOrEmpty(iconLoc)) {
            int idx = 0; string file = iconLoc; int c = iconLoc.LastIndexOf(',');
            if (c > 0) { file = iconLoc.Substring(0, c); int.TryParse(iconLoc.Substring(c + 1), out idx); }
            l.SetIconLocation(file, idx);
        }
        ((IPersistFile)l).Save(lnk, true);
        Marshal.ReleaseComObject(l);
    }
}
'@
    }

    # Deploy a standalone GoldenDict .ico to C:\LabTools\icons\goldendict.ico so
    # the Từ Điển shortcut can point IconLocation at a concrete external file.
    # Problem: setting IconLocation to "GoldenDict.exe,0" (same path as target,
    # index 0) triggers Windows' SetIconLocation optimization — the shell stores
    # no icon path and leaves HasLinkFlags.HasIconLocation = false. Explorer then
    # extracts the icon dynamically from the target exe each render. That indirect
    # path appears to fail on some Win11 builds specifically for Unicode-named
    # .lnk files (observed on PC-10, PC-14, PC-15: Từ Điển renders blank even
    # though the .lnk target resolves and the exe has valid icon resources).
    # Pointing IconLocation at an external .ico forces HasIconLocation=true and
    # decouples rendering from exe-resource extraction entirely.
    $goldenDictIcoPath = $null
    try {
        $icoDir = "C:\LabTools\icons"
        if (-not (Test-Path $icoDir)) { New-Item -Path $icoDir -ItemType Directory -Force | Out-Null }
        $icoTarget = Join-Path $icoDir "goldendict.ico"
        $deployed = $false

        # Copy the bundled .ico. We pre-extract it on the test bench by reading the
        # PE RT_GROUP_ICON + RT_ICON resources directly (preserves all sizes and the
        # alpha channel). Earlier attempts used PrivateExtractIcons → Icon.FromHandle
        # → Icon.Save, but that pipeline goes through GDI+ which drops the alpha on
        # 32bpp icons — the exported .ico showed a white background and looked
        # pixelated after Windows scaled the single size. The bundled .ico has 13
        # embedded sizes (16, 24, 32, 48, 64, 96, 128, 256 across 4/8/32-bpp) so
        # Windows can pick the exact match for whatever desktop IconSize setting.
        $bundled = Join-Path $usbRoot "Config\icons\goldendict.ico"
        if (Test-Path $bundled) {
            Copy-Item -Path $bundled -Destination $icoTarget -Force -ErrorAction Stop
            if ((Test-Path $icoTarget) -and (Get-Item $icoTarget).Length -gt 0) { $deployed = $true }
        }

        if ($deployed) {
            $goldenDictIcoPath = $icoTarget
            Write-Log "GoldenDict icon deployed to $icoTarget ($((Get-Item $icoTarget).Length) bytes)" "INFO"
        } else {
            Write-Log "GoldenDict icon not deployed (bundled .ico missing at $bundled) - Từ Điển will fall back to exe,0" "WARNING"
        }
    } catch {
        Write-Log "Could not deploy GoldenDict icon: $($_.Exception.Message)" "WARNING"
    }

    # Alphabetical by display name so creation order matches visual order on a fresh Windows desktop
    # (Windows places new icons in grid top-to-bottom, left-to-right based on creation sequence).
    # IconLocation is set only for shortcuts whose target .exe lacks a usable embedded icon.
    $shortcuts = @(
        @{ Name = "Audacity"; Target = "C:\Program Files\Audacity\Audacity.exe"; AltTarget = "C:\Program Files (x86)\Audacity\Audacity.exe"; IconLocation = "C:\Program Files\Audacity\Audacity.exe,0"; Desc = "Audacity Audio Editor" },
        @{ Name = "Calculator"; Target = "calc.exe"; IconLocation = "%SystemRoot%\System32\imageres.dll,76"; Desc = "Windows Calculator" },
        @{ Name = "Excel"; Target = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\EXCEL.EXE"; Desc = "Microsoft Excel" },
        @{ Name = "Firefox"; Target = "C:\Program Files\Mozilla Firefox\firefox.exe"; AltTarget = "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"; Desc = "Firefox Web Browser" },
        @{ Name = "NVDA"; Target = "C:\Program Files\NVDA\nvda.exe"; AltTarget = "C:\Program Files (x86)\NVDA\nvda.exe"; Desc = "NVDA Screen Reader" },
        @{ Name = "PowerPoint"; Target = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\POWERPNT.EXE"; IconLocation = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE,0"; Desc = "Microsoft PowerPoint" },
        @{ Name = "Readmate"; Target = "C:\Program Files\SaoMai\sm_readmate\sm_readmate.exe"; AltTarget = "C:\Program Files (x86)\SaoMai\sm_readmate\sm_readmate.exe"; Desc = "Sao Mai Readmate Accessible Reader" },
        @{ Name = "Sao Mai Typing Tutor"; Target = "C:\Program Files (x86)\SaoMai\SMTT\SMTT.exe"; AltTarget = "C:\Program Files\SaoMai\SMTT\SMTT.exe"; IconLocation = "%SystemRoot%\System32\imageres.dll,116"; Desc = "Sao Mai Vietnamese Typing Tutor" },
        @{ Name = "Thùng Rác"; Target = "explorer.exe"; Args = "shell:RecycleBinFolder"; IconLocation = "%SystemRoot%\System32\shell32.dll,31"; Desc = "Thùng rác - khôi phục tập tin đã xóa" },
        @{ Name = "Từ Điển"; Target = "C:\Program Files\GoldenDict\GoldenDict.exe"; AltTarget = "C:\Program Files (x86)\GoldenDict\GoldenDict.exe"; IconLocation = $goldenDictIcoPath; Desc = "GoldenDict - Offline Dictionary" },
        @{ Name = "USB"; Target = "explorer.exe"; Args = "shell:MyComputerFolder"; IconLocation = "%SystemRoot%\System32\imageres.dll,109"; Desc = "Open This PC to access your USB drive" },
        @{ Name = "VLC media player"; Target = "C:\Program Files\VideoLAN\VLC\vlc.exe"; AltTarget = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"; Desc = "VLC Media Player" },
        @{ Name = "Wikipedia"; Target = "C:\Program Files\Kiwix\kiwix-desktop.exe"; Desc = "Kiwix - Offline Vietnamese Wikipedia" },
        @{ Name = "Word"; Target = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE"; AltTarget = "C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE"; Desc = "Microsoft Word" }
    )

    $createdCount = 0
    $preservedCount = 0
    foreach ($s in $shortcuts) {
        $lnkPath = Join-Path $publicDesktop "$($s.Name).lnk"

        # Resolve the target path: primary → alt → recursive search by exact exe name.
        $targetPath = $null
        if ($s.Target -in @("calc.exe", "explorer.exe", "powershell.exe")) {
            $targetPath = $s.Target
        } elseif (Test-Path $s.Target) {
            $targetPath = $s.Target
        } elseif ($s.AltTarget -and (Test-Path $s.AltTarget)) {
            $targetPath = $s.AltTarget
        } else {
            # Not at expected path — search for the EXACT exe name recursively under the
            # primary and alt parent directories. Handles nested installs (e.g. Kiwix
            # extracted as C:\Program Files\Kiwix\kiwix-desktop-2.4.1\kiwix-desktop.exe
            # instead of the flat layout the current installer produces).
            # The old fallback grabbed "first .exe in parent" which for Kiwix picks
            # aria2c.exe alphabetically — a broken shortcut. Filter by exe name.
            $exeName = Split-Path $s.Target -Leaf
            foreach ($t in @($s.Target, $s.AltTarget) | Where-Object { $_ }) {
                $parentDir = Split-Path $t -Parent
                if ($parentDir -and (Test-Path $parentDir)) {
                    $found = Get-ChildItem -Path $parentDir -Filter $exeName -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { $targetPath = $found.FullName; break }
                }
            }
        }

        if (-not $targetPath) {
            # App genuinely not installed at any expected location. Do NOT destroy an
            # existing working shortcut — preserve it. (Pre-fix behavior wiped upfront
            # then skipped creation here, losing the shortcut permanently.) If no
            # existing .lnk, nothing to do.
            if (Test-Path $lnkPath) {
                Write-Log "Preserving existing '$($s.Name)' shortcut - target not at expected path" "WARNING"
                $preservedCount++
            } else {
                Write-Log "Skipping '$($s.Name)' - not installed and no existing shortcut" "WARNING"
            }
            continue
        }

        $workDir = if ($targetPath -notin @("calc.exe", "explorer.exe", "powershell.exe")) {
            Split-Path $targetPath -Parent
        } else { "" }

        # Make IconLocation explicit: if no system-DLL icon was specified in the array
        # entry, point it at the resolved target exe. Empty IconLocation makes Windows
        # implicitly fall back to the target for icon extraction, but for Unicode-named
        # .lnk files (Từ Điển) some laptops' icon cache fails to refresh when the shortcut
        # is overwritten with the same filename — icon appears blank. Setting IconLocation
        # explicitly gives Windows a concrete path to resolve, bypassing the stale cache key.
        $iconLoc = $s.IconLocation
        if (-not $iconLoc -and $targetPath -and $targetPath -like "*.exe") {
            $iconLoc = "$targetPath,0"
        }

        # Delete any existing .lnk before writing a fresh one. This forces Windows to
        # treat the result as a genuinely new file (new creation time) so the icon cache
        # doesn't reuse a stale entry for the same filename.
        if (Test-Path $lnkPath) { Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue }

        # Per-shortcut try/catch so one failed Save() can't skip the rest of the loop.
        try {
            [ShellLinkCreator]::Create($lnkPath, $targetPath, $s.Args, $s.Desc, $workDir, $iconLoc)
            $createdCount++
        } catch {
            Write-Log "Failed to create shortcut '$($s.Name)': $($_.Exception.Message)" "ERROR"
        }
    }

    # Cleanup pass: remove any .lnk on the public desktop whose name is NOT in our
    # managed set. This catches legacy shortcuts from old deployments and shortcuts
    # created by installers (Edge, GoldenDict installer's own, old "Wikipedia (Offline)"
    # names, etc.) without touching working shortcuts we intentionally preserved above.
    $managedNames = @($shortcuts | ForEach-Object { "$($_.Name).lnk" })
    Get-ChildItem -Path $publicDesktop -Filter "*.lnk" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $managedNames } |
        ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Removed unmanaged shortcut: $($_.Name)" "INFO"
        }

    Write-Log "Desktop shortcuts: created=$createdCount preserved=$preservedCount (alphabetical for screen reader first-letter navigation)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set up desktop shortcuts: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 6b: Force Student's icon cache to refresh. When a .lnk was previously rendered
# with "no icon" (target-not-found during an earlier partial deploy, or Install's
# WScript.Shell Save failed and left a 0-byte file), Explorer caches the null result
# keyed by the .lnk path. Re-writing the .lnk at the same path does NOT invalidate
# that cache — observed specifically on Unicode-named shortcuts (Từ Điển) across
# PC-10 and PC-15. Two-pronged:
#   1. SHChangeNotify(SHCNE_ASSOCCHANGED) — tells any live Explorer to flush now.
#   2. MoveFileEx(DELAY_UNTIL_REBOOT) on Student's iconcache_*.db / thumbcache_*.db —
#      Explorer holds them open, but this queues a guaranteed delete for next boot,
#      after which Windows rebuilds from scratch.
try {
    # Prior buggy version split this into two classes Win32.MoveFileEx and
    # Win32.SHChange. C# rejects a class named MoveFileEx that declares a method
    # named MoveFileEx (it treats the method as a would-be constructor, and extern
    # constructors aren't legal), so Add-Type failed and neither pathway ran.
    # Single class Win32.Native holds both P/Invokes — names don't collide.
    if (-not ('Win32.Native' -as [type])) {
        Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);

[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
'@
    }

    # MOVEFILE_DELAY_UNTIL_REBOOT = 0x4. Files remain usable this session; the OS
    # records the pending delete in HKLM\...\Session Manager\PendingFileRenameOperations
    # and honors it on the next boot. Also try a best-effort immediate delete — if
    # Explorer isn't holding the file (unlikely but possible on a fresh deploy before
    # Student login), it succeeds and no reboot is needed.
    $cacheDir = "C:\Users\Student\AppData\Local\Microsoft\Windows\Explorer"
    $cacheDirExists = Test-Path $cacheDir
    $found = 0; $queued = 0; $deleted = 0
    if ($cacheDirExists) {
        foreach ($pat in @('iconcache_*.db','thumbcache_*.db')) {
            Get-ChildItem $cacheDir -Filter $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $found++
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    $deleted++
                } catch {
                    if ([Win32.Native]::MoveFileEx($_.FullName, $null, 4)) { $queued++ }
                }
            }
        }
    }
    $legacyIconDb = "C:\Users\Student\AppData\Local\IconCache.db"
    if (Test-Path $legacyIconDb) {
        $found++
        try { Remove-Item -Path $legacyIconDb -Force -ErrorAction Stop; $deleted++ }
        catch { if ([Win32.Native]::MoveFileEx($legacyIconDb, $null, 4)) { $queued++ } }
    }

    # SHCNE_ASSOCCHANGED = 0x08000000; SHCNF_IDLIST = 0. Broadcasts to every Explorer
    # instance in the session to flush assoc/icon cache. Fast, non-disruptive.
    [Win32.Native]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

    Write-Log "Icon cache: dir-exists=$cacheDirExists found=$found deleted-now=$deleted queued-for-reboot=$queued; Explorer notified via SHChangeNotify" "INFO"
} catch {
    Write-Log "Icon cache refresh failed: $($_.Exception.Message)" "WARNING"
}

# Step 7: Welcome audio — REMOVED. NVDA's own "NVDA has started" announcement at login
# serves the same purpose without the race condition or the bundled controller DLL dependency.
# Clean up leftovers from any prior deploy that installed the welcome audio.
try {
    Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\LabWelcome.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\LabTools\welcome-audio.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\LabTools\nvdaControllerClient64.dll" -Force -ErrorAction SilentlyContinue
} catch {}

# Step 8: (Moved to Step 6 — desktop shortcuts are now created in one pass)

# Step 9: Login-reset defaults (volume + brightness)
# Both run on every login via All Users Startup shortcuts. They guarantee a known-good
# baseline so the previous session can't leave the laptop muted, deafening, blacked-out,
# or blindingly bright. Each script logs failures next to itself for diagnosis.
Write-Log "Step 9: Setting login-reset defaults (volume + brightness)..." "INFO"

try {
    # --- Volume reset script (50%) -------------------------------------------------
    # Caps system volume at 50% on each login to protect hearing (ATH-M40x are 98dB sensitivity).
    # Uses a C# static helper so the COM cast happens inside the CLR — PowerShell's
    # strict cast operator refuses to cast the [ComImport] coclass directly to its
    # interface, which is why earlier inline-COM versions silently did nothing.
    $volumeScript = @'
# Reset system volume to 50% and clear mute on each login.
# Protects children's hearing — ATH-M40x at full volume can exceed safe SPL.
# Level and mute are independent in Core Audio, so both must be set explicitly.
$logPath = 'C:\LabTools\reset-volume.log'
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace LabVol {
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr p);
    int UnregisterControlChangeNotify(IntPtr p);
    int GetChannelCount(out uint c);
    int SetMasterVolumeLevel(float l, ref Guid g);
    int SetMasterVolumeLevelScalar(float l, ref Guid g);
    int GetMasterVolumeLevel(out float l);
    int GetMasterVolumeLevelScalar(out float l);
    int SetChannelVolumeLevel(uint c, float l, ref Guid g);
    int SetChannelVolumeLevelScalar(uint c, float l, ref Guid g);
    int GetChannelVolumeLevel(uint c, out float l);
    int GetChannelVolumeLevelScalar(uint c, out float l);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid g);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid id, uint clsCtx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int role, out IntPtr e);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice d);
}
public static class Helper {
    public static void ResetToDefault(float level) {
        var t = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(t);
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        var iid = typeof(IAudioEndpointVolume).GUID;
        object o;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 1, IntPtr.Zero, out o));
        var vol = (IAudioEndpointVolume)o;
        var g = Guid.Empty;
        Marshal.ThrowExceptionForHR(vol.SetMasterVolumeLevelScalar(level, ref g));
        Marshal.ThrowExceptionForHR(vol.SetMute(false, ref g));
    }
}
}
"@
    [LabVol.Helper]::ResetToDefault(0.50)
    "$([DateTime]::Now.ToString('s')) OK level=50%" | Out-File -FilePath $logPath -Append -Encoding ASCII
} catch {
    "$([DateTime]::Now.ToString('s')) FAILED: $($_.Exception.Message)" | Out-File -FilePath $logPath -Append -Encoding ASCII
}
'@

    $volumeScriptPath = Join-Path "C:\LabTools" "reset-volume.ps1"
    Set-Content -Path $volumeScriptPath -Value $volumeScript -Force

    # --- Brightness reset script (50%) ---------------------------------------------
    # Saves ~3-5W per laptop continuously, eases eye strain, and recovers from any
    # session that left the panel fully bright or near-black. WMI may return no
    # instance on hardware without a software-controllable backlight (e.g. desktops
    # or some external monitors); failures land in the log file.
    $brightnessScript = @'
# Reset internal display brightness to 50% on each login.
# Saves power (~3-5W per laptop), reduces eye strain, and protects against
# the previous session leaving the panel uncomfortably bright or dim.
$logPath = 'C:\LabTools\reset-brightness.log'
try {
    $br = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop
    Invoke-CimMethod -InputObject $br -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]0; Brightness = [byte]50 } | Out-Null
    "$([DateTime]::Now.ToString('s')) OK level=50%" | Out-File -FilePath $logPath -Append -Encoding ASCII
} catch {
    "$([DateTime]::Now.ToString('s')) FAILED: $($_.Exception.Message)" | Out-File -FilePath $logPath -Append -Encoding ASCII
}
'@

    $brightnessScriptPath = Join-Path "C:\LabTools" "reset-brightness.ps1"
    Set-Content -Path $brightnessScriptPath -Value $brightnessScript -Force

    # --- Scheduled tasks (replaces legacy All Users Startup .lnks) -----------------
    # Win11 defers Startup-folder .lnk launches by ~2 minutes on DC power (Power Throttling
    # + Explorer startup deferment), so a battery cold boot left the laptop at full volume
    # / wrong brightness for the first few minutes of class. Scheduled tasks fire directly
    # on the AtLogOn trigger with explicit AllowStartIfOnBatteries and Priority 4, so they
    # run promptly on AC and DC alike. Pattern matches UniKey-Startup-Vietnamese below.
    # BUILTIN\Users + Limited principal: COM endpoints (CoreAudio, WMI brightness) are
    # session-scoped, so the task must run inside the logging-on user's interactive session.
    $allUsersStartup = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    $approvedFolder  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
    foreach ($staleLnk in @('LabVolumeReset.lnk','LabBrightnessReset.lnk')) {
        Remove-Item (Join-Path $allUsersStartup $staleLnk) -Force -ErrorAction SilentlyContinue
        if (Test-Path $approvedFolder) {
            Remove-ItemProperty -Path $approvedFolder -Name $staleLnk -Force -ErrorAction SilentlyContinue
        }
    }

    $resetTaskTrigger   = New-ScheduledTaskTrigger -AtLogOn
    $resetTaskSettings  = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -Priority 4 `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew
    $resetTaskPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited  # BUILTIN\Users

    $volTaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$volumeScriptPath`""
    Register-ScheduledTask -TaskName 'LabVolumeReset' `
        -Description 'Reset system volume to 50% on each login (hearing protection).' `
        -Action $volTaskAction -Trigger $resetTaskTrigger `
        -Settings $resetTaskSettings -Principal $resetTaskPrincipal -Force | Out-Null

    $brTaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$brightnessScriptPath`""
    Register-ScheduledTask -TaskName 'LabBrightnessReset' `
        -Description 'Reset display brightness to 50% on each login.' `
        -Action $brTaskAction -Trigger $resetTaskTrigger `
        -Settings $resetTaskSettings -Principal $resetTaskPrincipal -Force | Out-Null

    Write-Log "Login-reset tasks registered (LabVolumeReset, LabBrightnessReset; AtLogOn, battery-safe, Priority 4)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set login-reset defaults: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 9b: SAPI5 bridge + default Vietnamese voice
# - Bridge Microsoft An (OneCore neural vi-VN) into SAPI5 for BOTH 64-bit (Readmate)
#   and 32-bit (NVDA) apps. Without 32-bit mirror, NVDA falls back to Sao Mai Thanh Vi
#   which has an internal English voice (Daniel) that spells Vietnamese letter-by-letter
#   when it mis-detects short Vietnamese fragments.
# - Set machine + per-user SAPI defaults to Microsoft An for consistency across apps.
# Note: Microsoft An is Northern dialect. No offline Southern neural voice exists that
# handles bilingual text correctly. This is the best available option.
Write-Log "Step 9b: Bridging Microsoft An to SAPI5 (64-bit + 32-bit) and setting default voice..." "INFO"

try {
    $oneCoreAn = "HKLM:\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_viVN_An"
    $sapiAn64  = "HKLM:\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An"
    $sapiAn32  = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An"

    if (Test-Path $oneCoreAn) {
        if (-not (Test-Path $sapiAn64)) {
            & reg.exe copy "HKLM\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_viVN_An" `
                           "HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An" /s /f 2>&1 | Out-Null
            Write-Log "Microsoft An bridged to 64-bit SAPI5 (enables Readmate)" "SUCCESS"
        }
        if (-not (Test-Path $sapiAn32)) {
            & reg.exe copy "HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An" `
                           "HKLM\SOFTWARE\WOW6432Node\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An" /s /f 2>&1 | Out-Null
            Write-Log "Microsoft An mirrored to 32-bit SAPI5 (enables NVDA bilingual reading)" "SUCCESS"
        }
    } else {
        Write-Log "Microsoft An (OneCore) not found — Vietnamese language pack TTS may not be installed" "WARNING"
    }

    # Machine-wide SAPI default (Microsoft An everywhere — bilingual neural, consistent with NVDA + Readmate)
    $anPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\MSTTS_V110_viVN_An"
    $anOneCore = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_viVN_An"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Speech\Voices" -Name "DefaultTokenId" -Value $anPath -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Speech_OneCore\Voices" -Name "DefaultTokenId" -Value $anOneCore -Force

    # Per-user SAPI default (Student + any other loaded hives)
    foreach ($hive in $hkuPaths) {
        $speechPath = "$hive\Software\Microsoft\Speech\Voices"
        if (-not (Test-Path $speechPath)) { New-Item -Path $speechPath -Force | Out-Null }
        Set-ItemProperty -Path $speechPath -Name "DefaultTokenId" -Value $anPath -Force

        $oneCorePath = "$hive\Software\Microsoft\Speech_OneCore\Voices"
        if (-not (Test-Path $oneCorePath)) { New-Item -Path $oneCorePath -Force | Out-Null }
        Set-ItemProperty -Path $oneCorePath -Name "DefaultTokenId" -Value $anOneCore -Force
    }

    Write-Log "SAPI default voice set to Microsoft An (bilingual neural)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not set SAPI voices: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 10: Configure Windows Update — auto-install quality (security) updates daily at 18:00,
# matching the LabUpdateAgent dinner window (students away). Feature-update deferral of 365 days
# is set in Step 6 (HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate). Combined effect:
# security patches install unattended overnight-equivalent; feature jumps stay locked.
Write-Log "Step 10: Configuring Windows Update for auto-install of security updates at 18:00..." "INFO"

try {
    # Services must run automatically so the scheduled install actually fires
    Set-Service -Name "wuauserv" -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name "UsoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name "WaaSMedicSvc" -StartupType Manual -ErrorAction SilentlyContinue

    # Group Policy: "Auto download and schedule install" (AUOptions=4)
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
    Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path $auPath -Name "ScheduledInstallDay" -Value 0 -Type DWord -Force   # 0 = every day
    Set-ItemProperty -Path $auPath -Name "ScheduledInstallTime" -Value 18 -Type DWord -Force # 18 = 6 PM, matches LabUpdateAgent
    # Never reboot while a user is signed in (would interrupt NVDA / a class)
    Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
    # Suppress Windows Update restart notification popups (interrupts NVDA)
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name "SetAutoRestartNotificationDisable" -Value 1 -Type DWord -Force

    Write-Log "Windows Update set to auto-install quality updates daily at 18:00 (no reboot while signed in)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not configure Windows Update: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 10b: Disable Microsoft 365 Office auto-updates. Office still works offline;
# activation check runs separately (~30 days). Updates can be pushed via update agent if needed.
Write-Log "Step 10b: Disabling Office 365 auto-updates..." "INFO"

try {
    $officeUpdatePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate"
    if (-not (Test-Path $officeUpdatePolicy)) { New-Item -Path $officeUpdatePolicy -Force | Out-Null }
    Set-ItemProperty -Path $officeUpdatePolicy -Name "enableautomaticupdates" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $officeUpdatePolicy -Name "hideenabledisableupdates" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $officeUpdatePolicy -Name "hideupdatenotifications" -Value 1 -Type DWord -Force

    # Disable Office auto-update scheduled tasks (wildcards via -like — Get-ScheduledTask -TaskName
    # doesn't reliably expand * on all Win11 builds).
    $officeTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like "Office Automatic Updates*" -or
        $_.TaskName -like "Office Feature Updates*" -or
        $_.TaskName -like "Office Background Push Maintenance*" -or
        $_.TaskName -like "Office Startup Maintenance*"
    }
    foreach ($t in $officeTasks) {
        Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Log "Office 365 auto-updates disabled (policy + $($officeTasks.Count) scheduled tasks)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Office updates: $($_.Exception.Message)" "WARNING"
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
    # Machine-wide policy (defense-in-depth; applies to any user, including logon screen)
    $narratorPolicy = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Narrator.exe"
    if (-not (Test-Path $narratorPolicy)) { New-Item -Path $narratorPolicy -Force -ErrorAction SilentlyContinue | Out-Null }
    # Redirect Narrator.exe invocations to a harmless no-op so it can't run even if triggered
    Set-ItemProperty -Path $narratorPolicy -Name "Debugger" -Value "%SystemRoot%\System32\systray.exe" -Force -ErrorAction SilentlyContinue

    # Per-user: also disable the Win+Ctrl+Enter shortcut so the key combo does nothing
    foreach ($hive in $hkuPaths) {
        $narratorPath = "$hive\Software\Microsoft\Narrator\NoRoam"
        if (-not (Test-Path $narratorPath)) { New-Item -Path $narratorPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $narratorPath -Name "WinEnterLaunchEnabled" -Value 0 -Force -ErrorAction SilentlyContinue

        $easeAccess = "$hive\Software\Microsoft\Ease of Access"
        if (-not (Test-Path $easeAccess)) { New-Item -Path $easeAccess -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $easeAccess -Name "selfvoice.ManualStart" -Value 1 -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Narrator disabled (HKLM IFEO debugger + per-user hotkey off) — prevents NVDA conflict" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Narrator: $($_.Exception.Message)" "ERROR"
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
    # Target the Balanced scheme by GUID instead of SCHEME_CURRENT. Script runs as Admin, so
    # SCHEME_CURRENT resolves to Admin's active scheme — if Student's active scheme ever
    # differs (OEM preload, manual change), edits would miss Student entirely. Writing to
    # Balanced's GUID guarantees values land in the scheme both accounts use on fresh Windows.
    $balanced = "381b4222-f694-41f0-9685-ff5bb260df2e"

    # Display timeout: 30 min AC (1800s) / 15 min battery (900s)
    powercfg /setacvalueindex $balanced SUB_VIDEO VIDEOIDLE 1800
    powercfg /setdcvalueindex $balanced SUB_VIDEO VIDEOIDLE 900
    # Sleep: never on AC (0) / 30 min on battery (1800s)
    powercfg /setacvalueindex $balanced SUB_SLEEP STANDBYIDLE 0
    powercfg /setdcvalueindex $balanced SUB_SLEEP STANDBYIDLE 1800
    # Disable hibernate entirely (frees ~8GB pagefile, avoids wake bugs)
    powercfg /hibernate off
    # Lid close → sleep on AC and battery. Students check laptops out to take home/school;
    # a closed lid with the system awake in a backpack cooks the battery and throttles the
    # CPU from restricted airflow. Sleep protects hardware during transport.
    powercfg /setacvalueindex $balanced SUB_BUTTONS LIDACTION 1
    powercfg /setdcvalueindex $balanced SUB_BUTTONS LIDACTION 1
    # Disable wake timers — scheduled tasks and Windows Update can wake a sleeping laptop
    # inside a closed backpack, then potentially fail to re-sleep. That's the exact thermal
    # scenario the lid-close rule is meant to prevent.
    powercfg /setacvalueindex $balanced SUB_SLEEP RTCWAKE 0
    powercfg /setdcvalueindex $balanced SUB_SLEEP RTCWAKE 0
    # Critical battery action = shutdown (2). Hibernate is off so Windows would fall back
    # anyway, but explicit avoids relying on implicit fallback behavior.
    powercfg /setdcvalueindex $balanced SUB_BATTERY BATACTIONCRIT 2
    # Skip the lock screen on wake — go straight back to Student's session. Student has no
    # password anyway (Step 21), so the lock screen is a redundant Enter-press that a blind
    # student can't see. With CONSOLELOCK 0, opening the lid resumes NVDA mid-sentence and
    # the desktop is immediately available again.
    powercfg /setacvalueindex $balanced SUB_NONE CONSOLELOCK 0
    powercfg /setdcvalueindex $balanced SUB_NONE CONSOLELOCK 0
    # Make Balanced active so the values we just wrote take effect immediately.
    powercfg /setactive $balanced

    Write-Log "Power settings configured (Balanced scheme: sleep on lid close, no wake timers, no lock screen on wake, no hibernate)" "SUCCESS"
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
        # Clean up any stale .corrupted.bak from a prior broken deploy
        Remove-Item "$nvdaConfigDir\nvda.ini.corrupted.bak" -Force -ErrorAction SilentlyContinue
        Write-Log "Deployed NVDA config template (laptop layout, Vietnamese Thanh Vi, rate 35) to Student profile" "SUCCESS"
    }

    # NVDA shortcuts: machine-wide Startup for auto-launch + per-user for Ctrl+Alt+N hotkey.
    # Windows 11 22H2+ only registers .lnk HotKey from the current user's own profile.
    # Also delete installer-created duplicates (Public Desktop + ProgramData NVDA folder)
    # so Student doesn't see two icons.
    try {
        $nvdaExe = "C:\Program Files (x86)\NVDA\nvda.exe"
        if (-not (Test-Path $nvdaExe)) { $nvdaExe = "C:\Program Files\NVDA\nvda.exe" }
        $nvdaDir = Split-Path -Parent $nvdaExe
        $nvdaIco = Join-Path $nvdaDir "images\nvda.ico"

        $studentStart = "C:\Users\Student\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\NVDA"
        $studentDesk  = "C:\Users\Student\Desktop"
        $sysStartup   = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        New-Item -ItemType Directory -Force -Path $studentStart | Out-Null

        $WshShell = New-Object -ComObject WScript.Shell

        # Per-user Desktop + Start Menu (hotkey sources)
        foreach ($dir in @($studentStart, $studentDesk)) {
            $lnk = Join-Path $dir "NVDA.lnk"
            $sc  = $WshShell.CreateShortcut($lnk)
            $sc.TargetPath       = $nvdaExe
            $sc.WorkingDirectory = $nvdaDir
            if (Test-Path $nvdaIco) { $sc.IconLocation = $nvdaIco }
            $sc.Hotkey           = "Ctrl+Alt+N"
            $sc.Description      = "NVDA Screen Reader"
            $sc.Save()
            & icacls.exe $lnk /setowner Student /C 2>&1 | Out-Null
            & icacls.exe $lnk /grant "Student:F" /C 2>&1 | Out-Null
        }

        # Auto-launch via scheduled task (replaces the legacy system-Startup NVDA.lnk).
        # The task fires AtLogOn with battery-safe settings so NVDA starts promptly once the
        # user session is up.
        #
        # CRITICAL — must invoke nvda.exe via `cmd /c start` (ShellExecute), NOT directly:
        # nvda.exe ships with manifest `level="asInvoker" uiAccess="True"` so it can speak
        # on the secure desktop (sign-in / UAC). Task Scheduler launches actions via
        # CreateProcess, which refuses any UIAccess binary launched from a non-admin
        # principal and returns 0x800702E4 (ERROR_ELEVATION_REQUIRED). Wrapping with
        # `cmd /c start` routes the launch through ShellExecute, which is the only API
        # that brokers UIAccess elevation for non-admin callers (this is also why the
        # legacy Startup-folder .lnk worked — Explorer launches startup shortcuts via
        # ShellExecute).
        #
        # ExecutionTimeLimit MUST be zero — NVDA is a long-running session app; any
        # non-zero limit causes Task Scheduler to reap it when the limit expires.
        Remove-Item (Join-Path $sysStartup "NVDA.lnk") -Force -ErrorAction SilentlyContinue
        $saFolder = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
        if (Test-Path $saFolder) {
            Remove-ItemProperty -Path $saFolder -Name "NVDA.lnk" -Force -ErrorAction SilentlyContinue
        }
        foreach ($hive in $hkuPaths) {
            $hkuSA = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
            if (Test-Path $hkuSA) {
                Remove-ItemProperty -Path $hkuSA -Name "NVDA.lnk" -Force -ErrorAction SilentlyContinue
            }
        }

        $nvdaTaskAction    = New-ScheduledTaskAction -Execute 'cmd.exe' `
            -Argument "/c start `"`" `"$nvdaExe`""
        $nvdaTaskTrigger   = New-ScheduledTaskTrigger -AtLogOn
        $nvdaTaskSettings  = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -Priority 4 `
            -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -MultipleInstances IgnoreNew
        $nvdaTaskPrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited  # BUILTIN\Users

        Register-ScheduledTask -TaskName 'LabNVDAStart' `
            -Description 'Auto-start NVDA in the logging-on user session (cmd /c start brokers UIAccess elevation that CreateProcess refuses).' `
            -Action $nvdaTaskAction -Trigger $nvdaTaskTrigger `
            -Settings $nvdaTaskSettings -Principal $nvdaTaskPrincipal -Force | Out-Null

        # Delete installer-created duplicates (these don't register hotkeys on Win11 22H2+
        # and just show up as duplicate icons).
        Remove-Item "C:\Users\Public\Desktop\NVDA.lnk" -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\NVDA\NVDA.lnk" -Force -ErrorAction SilentlyContinue

        Write-Log "NVDA hotkey shortcuts deployed (Student Desktop + StartMenu, Ctrl+Alt+N); LabNVDAStart task registered; duplicates removed" "SUCCESS"
    } catch {
        Write-Log "Could not configure NVDA shortcuts: $($_.Exception.Message)" "WARNING"
    }

    # Copy NVDA addons from Admin profile to Student (3-Configure-NVDA.ps1 installs
    # addons to $env:APPDATA which resolves to Admin when run from Bootstrap).
    # Prune Student's addon dir first so removed-from-manifest addons don't linger on redeploy.
    $adminAddons = Join-Path $env:APPDATA "nvda\addons"
    $studentAddons = Join-Path $nvdaConfigDir "addons"
    if ((Test-Path $adminAddons) -and (Get-ChildItem $adminAddons -ErrorAction SilentlyContinue)) {
        if (Test-Path $studentAddons) {
            Remove-Item "$studentAddons\*" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -Path $studentAddons -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$adminAddons\*" -Destination $studentAddons -Recurse -Force -ErrorAction SilentlyContinue
        $addonCount = (Get-ChildItem $studentAddons -Directory -ErrorAction SilentlyContinue).Count
        Write-Log "Copied $addonCount NVDA addon(s) from Admin to Student profile (pruned first)" "SUCCESS"
    }

    # Enable NVDA on Windows login screen / UAC / lock screen with Vi-Vu voice.
    #
    # Previously this block lived in 3-Configure-NVDA.ps1, but it ran before the
    # Student profile had nvda.ini or addons, so the mirror source was empty and
    # the login screen fell back to defaults (silent or English).
    #
    # NVDA's _setSystemConfig() reads from <NVDA install>\systemConfig\ when
    # running on secure desktops (sign-in / UAC), per nvaccess/nvda
    # source/config/__init__.py. We mirror Student's config there once it's
    # populated, with exclusions matching NVDA's own code path.
    #
    # /XD exclusions MUST be full paths so they only match top-level scratch dirs.
    # Using bare names like "synthDrivers" would also match
    # addons\RHVoice\synthDrivers\ and strip out the synth driver that the
    # sign-in NVDA (SYSTEM account) needs to speak Vi-Vu.
    try {
        $nvdaInstallDir = if (Test-Path "C:\Program Files\NVDA\nvda.exe") { "C:\Program Files\NVDA" } else { "C:\Program Files (x86)\NVDA" }
        $nvdaExeResolved = Join-Path $nvdaInstallDir "nvda.exe"
        $systemConfigDir = Join-Path $nvdaInstallDir "systemConfig"

        if (-not (Test-Path $systemConfigDir)) { New-Item -ItemType Directory -Path $systemConfigDir -Force | Out-Null }
        if (Test-Path $nvdaConfigDir) {
            $excludeFiles = @('*.exe','addonsState.pickle','addonsState.json','updateCheckState.pickle','nvda.log','nvda-old.log')
            $excludeDirs  = @(
                (Join-Path $nvdaConfigDir 'appModules'),
                (Join-Path $nvdaConfigDir 'brailleDisplayDrivers'),
                (Join-Path $nvdaConfigDir 'brailleTables'),
                (Join-Path $nvdaConfigDir 'globalPlugins'),
                (Join-Path $nvdaConfigDir 'synthDrivers'),
                (Join-Path $nvdaConfigDir 'visionEnhancementProviders'),
                (Join-Path $nvdaConfigDir 'addonStore'),
                (Join-Path $nvdaConfigDir 'updates')
            )
            & robocopy $nvdaConfigDir $systemConfigDir /MIR /XF @excludeFiles /XD @excludeDirs /R:2 /W:2 /NFL /NDL /NJH /NJS | Out-Null
            # robocopy exit codes 0-7 are "success variants"
            if ($LASTEXITCODE -lt 8) {
                Write-Log "NVDA Student config mirrored to systemConfig (login screen will speak Vi-Vu)" "SUCCESS"
            } else {
                Write-Log "robocopy returned $LASTEXITCODE mirroring systemConfig — may be partial" "WARNING"
            }
        } else {
            Write-Log "Student NVDA config not found at $nvdaConfigDir — secure desktop will use defaults" "WARNING"
        }

        # Remove the stale incorrect copy if a previous buggy script created it.
        $stale = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\nvda"
        if (Test-Path $stale) {
            Remove-Item -Path $stale -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed stale incorrect NVDA config at $stale" "INFO"
        }

        # Ease of Access registration — tells Windows which AT to launch when
        # Win+Ctrl+Enter is pressed at the login screen and lets NVDA run on
        # secure desktops.
        $easeOfAccessPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Accessibility\ATs\nvda"
        if (-not (Test-Path $easeOfAccessPath)) { New-Item -Path $easeOfAccessPath -Force | Out-Null }
        Set-ItemProperty -Path $easeOfAccessPath -Name "ATExe" -Value $nvdaExeResolved -Force
        Set-ItemProperty -Path $easeOfAccessPath -Name "StartExe" -Value $nvdaExeResolved -Force
        Set-ItemProperty -Path $easeOfAccessPath -Name "Description" -Value "NVDA Screen Reader" -Force

        Write-Log "NVDA registered as Ease of Access screen reader; systemConfig has Vi-Vu" "SUCCESS"
    } catch {
        Write-Log "Could not configure NVDA login screen: $($_.Exception.Message)" "WARNING"
    }

    # Backup the config — prune first so stale addons don't persist across redeploys
    if (Test-Path $nvdaConfigDir) {
        if (Test-Path $backupDir) {
            Remove-Item "$backupDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$nvdaConfigDir\*" -Destination $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "NVDA config backed up to $backupDir (pruned first)" "SUCCESS"
    }

    # Clean up legacy student-facing restore artifacts. Earlier deployments shipped a
    # "Khoi Phuc NVDA" desktop shortcut plus C:\LabTools\restore-nvda.ps1. The shortcut
    # hard-coded C:\Users\Student\AppData\Roaming\nvda, which broke on any laptop whose
    # Student profile landed at a different path (the orphan-profile bug). The feature
    # wasn't usable for a blind student who'd need it (if NVDA is broken, they can't
    # navigate the desktop to find it). Ctrl+Alt+N to restart NVDA and Admin-side
    # robocopy from C:\LabTools\nvda-backup remain as recovery paths.
    Remove-Item "C:\LabTools\restore-nvda.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Public\Desktop\Khoi Phuc NVDA - Restore NVDA.lnk" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Student\Desktop\Khoi Phuc NVDA - Restore NVDA.lnk" -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item (Join-Path $_.FullName "Desktop\Khoi Phuc NVDA - Restore NVDA.lnk") -Force -ErrorAction SilentlyContinue
    }

    Write-Log "NVDA config backed up to C:\LabTools\nvda-backup (legacy restore shortcut removed)" "SUCCESS"
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
    # Students access these folders through File Explorer / USB shortcut.

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

# Step 17c: Remove any legacy saomaicenter.org hosts block
# Earlier deployments blocked saomaicenter.org to stop SM Readmate self-update prompts.
# Students need it unblocked so they can reach SMTT lesson downloads and pull extra
# books from Sao Mai. Readmate's update is dialog-based, so blind users won't
# accidentally accept a silent upgrade.
Write-Log "Step 17c: Ensuring saomaicenter.org is not blocked in hosts file..." "INFO"

try {
    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $marker = "# VN-LAB: block SM Readmate auto-update"

    if (Test-Path $hostsFile) {
        $lines = Get-Content $hostsFile
        $filtered = $lines | Where-Object { $_ -notmatch [regex]::Escape($marker) -and $_ -notmatch 'saomaicenter\.org' }
        if ($filtered.Count -ne $lines.Count) {
            Set-Content -Path $hostsFile -Value $filtered -Encoding ASCII
            ipconfig /flushdns | Out-Null
            Write-Log "Removed legacy saomaicenter.org block from hosts" "SUCCESS"
        } else {
            Write-Log "No saomaicenter.org block present (nothing to remove)" "INFO"
        }
        $successCount++
    }
} catch {
    Write-Log "Could not scrub hosts file: $($_.Exception.Message)" "WARNING"
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

# Step 17e: Deploy SMTT per-user data (DB, lessons, UI lang, help)
# SMTT looks for .\SMTT.ini / .\SMTT.smdb in %APPDATA%\SaoMai\SMTT. Without it,
# first launch prompts "File not found. Press OK to select your data". Ship a
# pre-populated template so Student gets a working app on first run.
Write-Log "Step 17e: Deploying SMTT per-user data..." "INFO"

try {
    $smttTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\smtt-data"
    $smttDest = "C:\Users\Student\AppData\Roaming\SaoMai\SMTT"

    if (Test-Path $smttTemplate) {
        if (-not (Test-Path $smttDest)) { New-Item -Path $smttDest -ItemType Directory -Force | Out-Null }
        Copy-Item -Path "$smttTemplate\*" -Destination $smttDest -Recurse -Force
        icacls $smttDest /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null
        Write-Log "SMTT data deployed to Student AppData" "SUCCESS"
        $successCount++
    } else {
        Write-Log "SMTT template not found at $smttTemplate" "WARNING"
    }
} catch {
    Write-Log "Could not deploy SMTT data: $($_.Exception.Message)" "WARNING"
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
    # Prefer -PCNumber param (Bootstrap passes it before the rename has taken effect).
    # Fall back to hostname regex for standalone re-runs after reboot.
    $pcNum = $PCNumber
    if ($pcNum -eq 0 -and $env:COMPUTERNAME -match "PC-(\d+)") { $pcNum = [int]$Matches[1] }
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

# Step 19: Pin student USB (STU-###) to drive letter D:
# Word/Excel/PowerPoint/Firefox/Audacity all default-save to D:\ — must reliably be the
# student's USB. Windows Mount Manager can drift D: to a different volume GUID if the
# registry has accumulated stale mappings. This scheduled task assigns any STU-###
# labeled volume to D: whenever D: is vacant. Never touches another drive's letter.
# See Scripts/Reassign-StudentUSB.ps1 for the reassignment logic.
Write-Log "Step 19: Deploying STU → D: reassignment task..." "INFO"

try {
    $reassignScript = Join-Path $PSScriptRoot "Reassign-StudentUSB.ps1"
    $reassignDest   = "C:\LabTools\Reassign-StudentUSB.ps1"
    if (Test-Path $reassignScript) {
        Copy-Item -Path $reassignScript -Destination $reassignDest -Force
        Write-Log "Copied Reassign-StudentUSB.ps1 to C:\LabTools\" "SUCCESS"
    } else {
        throw "Reassign-StudentUSB.ps1 not found at $reassignScript"
    }

    $existing = Get-ScheduledTask -TaskName "LabReassignStudentUSB" -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName "LabReassignStudentUSB" -Confirm:$false }

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$reassignDest`""

    # Three triggers: boot, logon, and every 1 minute. Belt-and-suspenders for
    # volume-arrival detection without depending on event log channels that may be disabled.
    # Task Scheduler enforces a 1-minute minimum repetition interval (API hard limit).
    $trigBoot  = New-ScheduledTaskTrigger -AtStartup
    $trigLogon = New-ScheduledTaskTrigger -AtLogOn
    $trigPoll  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                    -RepetitionInterval (New-TimeSpan -Minutes 1) `
                    -RepetitionDuration (New-TimeSpan -Days 3650)

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask `
        -TaskName "LabReassignStudentUSB" `
        -Action $action `
        -Trigger @($trigBoot, $trigLogon, $trigPoll) `
        -Settings $settings `
        -Principal $principal `
        -Description "Pins any STU-### labeled USB to drive letter D: (boot/logon/1min)" | Out-Null

    Write-Log "Scheduled task 'LabReassignStudentUSB' registered (3 triggers: boot, logon, 1-min poll)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not deploy STU → D: reassignment task: $($_.Exception.Message)" "ERROR"
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

    # Allow blank-password logon via the AutoAdminLogon code path.
    # Default LimitBlankPasswordUse=1 blocks blank-password logons that LSA classifies
    # as non-console (Network/Service/Batch). On a slow boot — especially battery cold
    # boot on a Modern Standby laptop — Winlogon fires AutoAdminLogon before the console
    # session is fully ready, LSA classifies the call as non-console, returns 1326
    # (ERROR_LOGON_FAILURE), and Winlogon backs off ~100 sec before retrying. Setting
    # this to 0 makes the first attempt succeed and eliminates the back-off.
    # Safety: SSH is disabled (Step 22), no SMB shares are exposed, no RDP. Risk of
    # remote blank-password abuse is zero on this offline lab laptop.
    $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Set-ItemProperty -Path $lsaPath -Name "LimitBlankPasswordUse" -Value 0 -Type DWord -Force

    Write-Log "Auto-login configured for Student account (LimitBlankPasswordUse=0 to skip ~100s blank-password back-off on cold boot)" "SUCCESS"
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

# Step 26b: Disable Windows 11 "Soft Landing" content-recommendation tasks. Windows
# auto-creates per-user tasks at \SoftLanding\<SID>\ that push suggestions; they
# clutter scheduled tasks and can surface popups. Belt-and-suspenders with Step 11
# (SoftLandingEnabled=0 in ContentDeliveryManager).
Write-Log "Step 26b: Disabling SoftLanding content tasks..." "INFO"

try {
    # schtasks.exe /Delete works where Disable-ScheduledTask cmdlet fails (Access is
    # denied on per-user protected task paths).
    $softLandingTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like "\SoftLanding\*" }
    foreach ($t in $softLandingTasks) {
        $full = $t.TaskPath + $t.TaskName
        & schtasks.exe /Delete /TN $full /F 2>&1 | Out-Null
    }
    if ($softLandingTasks) {
        Write-Log "Deleted $($softLandingTasks.Count) SoftLanding task(s)" "SUCCESS"
    } else {
        Write-Log "No SoftLanding tasks found (nothing to delete)" "INFO"
    }
    $successCount++
} catch {
    Write-Log "Could not remove SoftLanding tasks: $($_.Exception.Message)" "WARNING"
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

    # Block Edge auto-update via policy (UpdateDefault=0). Also disables the update
    # services so Edge can't refresh itself in the background.
    $edgeUpdatePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
    if (-not (Test-Path $edgeUpdatePolicy)) { New-Item -Path $edgeUpdatePolicy -Force | Out-Null }
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "UpdateDefault" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "AutoUpdateCheckPeriodMinutes" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "InstallDefault" -Value 0 -Type DWord -Force
    foreach ($svc in @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")) {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Microsoft Edge neutered (shortcuts removed, auto-start + auto-update disabled)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not neuter Microsoft Edge: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 27b: Clean startup apps (suppress annoying popups on login)
Write-Log "Step 27b: Cleaning startup apps..." "INFO"

try {
    # UniKey uses a "last-used state" model: on shutdown it writes the current input mode
    # (V or E) and the current dialog-visible state to HKCU\Software\PkLong\UniKey, and on
    # startup it reads those values to decide what to do. One-time registry writes during
    # deployment therefore get OVERWRITTEN the first time a user ever closes UniKey in a
    # different state (e.g. ShowDlg=1 if the config dialog was visible at exit, Vietnamese=0
    # if English mode was last used). To reliably force the silent-Vietnamese startup UX we
    # re-assert all three knobs (Vietnamese=1, ShowDlg=0, AutoUpdate=0) immediately BEFORE
    # UniKey launches, on every login.
    #
    # Implementation: a scheduled task triggered at user logon, with four sequential actions:
    # (1-3) reg.exe writes each baseline value to the logged-in user's HKCU, (4) UniKeyNT
    # launches. No script files, no WSH/VBS parsing risk, no console window flash. Task
    # Scheduler runs actions sequentially when each preceding action terminates (reg.exe is
    # short-lived so it completes before UniKey opens and reads the values). An earlier
    # VBS-wrapper approach hit inconsistent "Wrong number of arguments" parse errors on some
    # sessions -- the scheduled task sidesteps that entire surface area.
    #
    # Why all three (not just Vietnamese): on fresh Win11 profiles that didn't inherit the
    # Software\PkLong subtree from Default (observed on laptops where Configure-Laptop's
    # pre-flight couldn't load Student's hive), UniKey launches with partial config, shows
    # its config dialog, and persists ShowDlg=1 on close even when the user clicks Accept.
    # Pre-asserting all three on every login breaks the loop: Student's HKCU always has
    # ShowDlg=0 visible to UniKey before it reads the registry.
    #
    # Principal = BUILTIN\Users, so the task fires for both Admin and Student on their
    # own logons, each writing to their own HKCU.
    $unikeyExe = "C:\Program Files\UniKey\UniKeyNT.exe"
    $taskName  = 'UniKey-Startup-Vietnamese'

    # Clean up prior approaches (idempotent -- safe on re-runs)
    Remove-Item "C:\LabTools\start-unikey.vbs" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\UniKey.lnk" -Force -ErrorAction SilentlyContinue
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    if (Test-Path $unikeyExe) {
        $a1 = New-ScheduledTaskAction -Execute 'reg.exe' -Argument 'add "HKCU\Software\PkLong\UniKey" /v Vietnamese /t REG_DWORD /d 1 /f'
        $a2 = New-ScheduledTaskAction -Execute 'reg.exe' -Argument 'add "HKCU\Software\PkLong\UniKey" /v ShowDlg /t REG_DWORD /d 0 /f'
        $a3 = New-ScheduledTaskAction -Execute 'reg.exe' -Argument 'add "HKCU\Software\PkLong\UniKey" /v AutoUpdate /t REG_DWORD /d 0 /f'
        $a4 = New-ScheduledTaskAction -Execute $unikeyExe
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        # ExecutionTimeLimit MUST be zero (unlimited). Default is 3 days and even a short
        # limit causes Task Scheduler to reap UniKey when the limit expires (UniKey is a
        # persistent tray app, so the task appears "running" indefinitely -- that is correct).
        # User-session logout terminates the task naturally when the user signs out.
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited  # BUILTIN\Users

        Register-ScheduledTask `
            -TaskName $taskName `
            -Description 'Force UniKey to start silent in Vietnamese mode on user login (reg baseline writes + launch).' `
            -Action @($a1, $a2, $a3, $a4) `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null
    }

    # Baseline registry config -- these are read by UniKey on startup and are safe to pin.
    # Vietnamese=1 is written here too so the scheduled task's first run has something
    # correct to reassert, and in case the task fails to fire for any reason.
    # Windows keyboard is pinned to en-US (see language section above) so Windows IME stays
    # dormant. UniKey's low-level hook does all Vietnamese composition. Net UX on login:
    # taskbar shows ENG (Windows dormant) + UniKey tray shows V (active) → student types and
    # Vietnamese characters come out directly, no toggle needed. Ctrl+Shift flips UniKey to E
    # for English words, URLs, passwords.
    foreach ($hive in $hkuPaths) {
        $uniKeyPath = "$hive\Software\PkLong\UniKey"
        if (-not (Test-Path $uniKeyPath)) { New-Item -Path $uniKeyPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $uniKeyPath -Name "ShowDlg" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $uniKeyPath -Name "AutoUpdate" -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $uniKeyPath -Name "Vietnamese" -Value 1 -Force -ErrorAction SilentlyContinue
    }

    Write-Log "UniKey configured: scheduled task '$taskName' (AtLogOn), registry baseline set on $($hkuPaths.Count) hive(s)" "SUCCESS"
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

# Step 30b: Schedule one-shot post-Student-login debloat sweep.
# Debloat Step 24 runs before Student first login, so Remove-AppxPackage -AllUsers has no
# Student-installed packages to remove. Win11 24H2 re-pushes some apps (Content Delivery
# Manager, Store first-run) into Student at first logon. This task fires on every logon
# as SYSTEM, invokes Debloat-Windows.ps1, and drops a marker + self-unregisters after
# the first successful run — so it's a true one-shot with no ongoing overhead.
Write-Log "Step 30b: Registering post-Student-login debloat task..." "INFO"

try {
    $debloatSrc  = Join-Path $PSScriptRoot "Debloat-Windows.ps1"
    $debloatDest = "C:\LabTools\Debloat-Windows.ps1"
    $markerFile  = "C:\LabTools\debloat-done.marker"
    $taskName    = 'Lab-PostStudent-Debloat'

    if (Test-Path $markerFile) {
        Write-Log "Post-Student debloat already completed on this machine (marker present) — skipping task registration" "INFO"
    } elseif (-not (Test-Path $debloatSrc)) {
        Write-Log "Debloat-Windows.ps1 not found at $debloatSrc — cannot schedule post-login sweep" "WARNING"
    } else {
        Copy-Item -Path $debloatSrc -Destination $debloatDest -Force
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$debloatDest`" -MarkerFile `"$markerFile`" -SelfUnregister"
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask `
            -TaskName $taskName `
            -Description 'One-shot debloat sweep after Student first login; self-unregisters on success.' `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force | Out-Null
        Write-Log "Scheduled task '$taskName' registered (fires at next logon, self-unregisters after success)" "SUCCESS"
    }
    $successCount++
} catch {
    Write-Log "Could not register post-Student-login debloat task: $($_.Exception.Message)" "ERROR"
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
    # Close Audacity if running — otherwise it rewrites the config on exit and undoes our pins.
    Stop-Process -Name audacity -Force -ErrorAction SilentlyContinue

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

# Step 33: (Removed — previously deployed SumatraPDF accessibility config.
# SumatraPDF was removed from deployment; Edge handles PDFs. The .pdf default is
# set during Bootstrap-Laptop.ps1's Phase 4 via the Settings UI — see Step 4c comment.)

# Step 33b: Clean up legacy PDF-reader registry entries and notify Explorer shell.
Write-Log "Step 33b: Removing legacy reader associations and notifying Explorer..." "INFO"
try {
    # Clean up any leftover Thorium / SumatraPDF associations from prior deployments
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\ThoriumReader.epub" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\Applications\Thorium.exe" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\SumatraPDF.pdf" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Classes\Applications\SumatraPDF.exe" -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($hive in $hkuPaths) {
        Remove-Item -Path "$hive\SOFTWARE\Classes\ThoriumReader.epub" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$hive\SOFTWARE\Classes\SumatraPDF.pdf" -Recurse -Force -ErrorAction SilentlyContinue
    }

    $shChangeCode = 'using System; using System.Runtime.InteropServices; public class Shell32Assoc { [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2); }'
    Add-Type -TypeDefinition $shChangeCode -ErrorAction SilentlyContinue
    [Shell32Assoc]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

    Write-Log "Cleaned up legacy PDF-reader registrations; Explorer notified of assoc changes" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not notify Explorer of association changes: $($_.Exception.Message)" "ERROR"
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
        Write-Log "Kiwix config deployed to $kiwixConfigDir (130% zoom, monitorDir)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "Kiwix config not found at $kiwixSource" "ERROR"
        $failCount++
    }

    # Deploy library.xml so Wikipedia + Wiktionary ZIMs show up in "Local files"
    # on first launch. Without it, the library is empty and students see nothing.
    $libraryDir = Join-Path $profileBase "AppData\Roaming\kiwix-desktop"
    if (-not (Test-Path $libraryDir)) { New-Item -Path $libraryDir -ItemType Directory -Force | Out-Null }
    $librarySource = Join-Path (Split-Path -Parent $PSScriptRoot) "Config\kiwix-config\library.xml"
    if (Test-Path $librarySource) {
        Copy-Item -Path $librarySource -Destination "$libraryDir\library.xml" -Force
        icacls $libraryDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null
        Write-Log "Kiwix library.xml deployed (Wikipedia + Wiktionary pre-registered)" "SUCCESS"
        $successCount++
    } else {
        Write-Log "Kiwix library.xml template not found at $librarySource" "WARNING"
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
Write-Host ""
Write-Host "Desktop:" -ForegroundColor White
Write-Host "  Shortcuts     Standardized (wiped + recreated for all apps)" -ForegroundColor White
Write-Host "  Apps          NVDA, Word, Excel, PowerPoint, Firefox, VLC, Audacity," -ForegroundColor White
Write-Host "                Kiwix, GoldenDict, Sao Mai Typing Tutor, Readmate," -ForegroundColor White
Write-Host "                Calculator, USB, Language Toggle" -ForegroundColor White
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
Write-Host "  Edge (PDF)    Policies: Read Aloud on, sign-in off, sync off, in-browser PDFs" -ForegroundColor White
Write-Host "                (.pdf default association is set via Settings UI in Bootstrap)" -ForegroundColor DarkGray
Write-Host "  Kiwix         130% zoom, reopen last tab" -ForegroundColor White
Write-Host "  GoldenDict    150% zoom, 18px article font, UI Automation" -ForegroundColor White
Write-Host "  Sticky Keys   Popup disabled (Shift x5)" -ForegroundColor White
Write-Host "  Filter Keys   Popup disabled (hold key)" -ForegroundColor White
Write-Host "  Toggle Keys   Beep enabled (Caps/Num/Scroll Lock)" -ForegroundColor White
Write-Host "  Volume reset  50% on each login (hearing safety)" -ForegroundColor White
Write-Host "  Brightness    50% on each login (power saving, eye comfort)" -ForegroundColor White
Write-Host "  Win Update    Disabled (offline)" -ForegroundColor White
Write-Host "  Notifications Toast, Notification Center, tips/suggestions all disabled" -ForegroundColor White
Write-Host "  Narrator      Shortcut disabled (NVDA only)" -ForegroundColor White
Write-Host "  Power         No sleep on AC, no hibernate" -ForegroundColor White
Write-Host "  Battery       Report saved to C:\LabTools\battery-report.htm" -ForegroundColor White
Write-Host "  NVDA backup   C:\LabTools\nvda-backup (robocopy from Admin to restore)" -ForegroundColor White
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
