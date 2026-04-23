# Fix Student Account - PC-01 Post-Bootstrap
# Copies NVDA config, addons, app configs, and HKCU settings to Student profile
# Must run as Administrator

$studentProfile = "C:\Users\Student"
$adminProfile = $env:USERPROFILE

if (-not (Test-Path $studentProfile)) {
    Write-Host "[ERROR] Student profile not found at $studentProfile" -ForegroundColor Red
    exit 1
}

Write-Host "=== Fixing Student Account ===" -ForegroundColor Cyan

# ---- 1. NVDA Config ----
Write-Host "`n[1/7] Copying NVDA config to Student..." -ForegroundColor Yellow
$studentNvda = "$studentProfile\AppData\Roaming\nvda"
$adminNvda = "$adminProfile\AppData\Roaming\nvda"

if (-not (Test-Path $studentNvda)) {
    New-Item -Path $studentNvda -ItemType Directory -Force | Out-Null
}
Copy-Item "$adminNvda\nvda.ini" "$studentNvda\nvda.ini" -Force
Write-Host "  [OK] nvda.ini copied (Vietnamese voice)" -ForegroundColor Green

# ---- 2. NVDA Addons ----
Write-Host "`n[2/7] Copying NVDA addons to Student..." -ForegroundColor Yellow
$adminAddons = "$adminNvda\addons"
$studentAddons = "$studentNvda\addons"

if (Test-Path $adminAddons) {
    if (-not (Test-Path $studentAddons)) {
        New-Item -Path $studentAddons -ItemType Directory -Force | Out-Null
    }
    Copy-Item "$adminAddons\*" $studentAddons -Recurse -Force
    $count = (Get-ChildItem $studentAddons -Directory).Count
    Write-Host "  [OK] $count addons copied" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] No addons found in Admin profile" -ForegroundColor DarkGray
}

# ---- 3. App configs (VLC, Audacity, Kiwix, GoldenDict) ----
Write-Host "`n[3/7] Copying app configs to Student..." -ForegroundColor Yellow
$appConfigs = @(
    @{ Name = "VLC"; Src = "$adminProfile\AppData\Roaming\vlc"; Dst = "$studentProfile\AppData\Roaming\vlc" },
    @{ Name = "Audacity"; Src = "$adminProfile\AppData\Roaming\audacity"; Dst = "$studentProfile\AppData\Roaming\audacity" },
    @{ Name = "GoldenDict"; Src = "$adminProfile\AppData\Roaming\GoldenDict"; Dst = "$studentProfile\AppData\Roaming\GoldenDict" },
    @{ Name = "Kiwix"; Src = "$adminProfile\AppData\Local\kiwix-desktop"; Dst = "$studentProfile\AppData\Local\kiwix-desktop" }
)

foreach ($cfg in $appConfigs) {
    if (Test-Path $cfg.Src) {
        $parent = Split-Path $cfg.Dst -Parent
        if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
        Copy-Item $cfg.Src $cfg.Dst -Recurse -Force
        Write-Host "  [OK] $($cfg.Name) config copied" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $($cfg.Name) config not found in Admin" -ForegroundColor DarkGray
    }
}

# ---- 4. (Removed — previously copied SumatraPDF per-user install. Now using Edge for PDFs.) ----

# ---- 5. (Removed — SumatraPDF desktop shortcut no longer deployed.) ----

# ---- 6. HKCU settings for Student (load hive) ----
Write-Host "`n[6/7] Applying registry settings to Student account..." -ForegroundColor Yellow

# Load Student's registry hive
$studentHive = "$studentProfile\NTUSER.DAT"
$hiveMounted = $false

# Check if Student is logged off (hive not loaded)
$loaded = Get-ChildItem "Registry::HKEY_USERS" | Where-Object { $_.Name -match "S-1-5-21.*-1003$" }
if ($loaded) {
    $studentSID = $loaded.PSChildName
    $hiveRoot = "Registry::HKEY_USERS\$studentSID"
    Write-Host "  Student hive already loaded at $studentSID" -ForegroundColor DarkGray
} else {
    reg load "HKU\StudentTemp" "$studentHive" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hiveRoot = "Registry::HKEY_USERS\StudentTemp"
        $hiveMounted = $true
        Write-Host "  Loaded Student hive temporarily" -ForegroundColor DarkGray
    } else {
        Write-Host "  [ERROR] Could not load Student registry hive" -ForegroundColor Red
        $hiveRoot = $null
    }
}

if ($hiveRoot) {
    # Taskbar cleanup
    $explorerAdv = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $explorerAdv)) { New-Item -Path $explorerAdv -Force | Out-Null }
    Set-ItemProperty -Path $explorerAdv -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue  # Widgets
    Set-ItemProperty -Path $explorerAdv -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force  # Task View
    Set-ItemProperty -Path $explorerAdv -Name "TaskbarMn" -Value 0 -Type DWord -Force  # Chat
    Set-ItemProperty -Path $explorerAdv -Name "ShowCopilotButton" -Value 0 -Type DWord -Force  # Copilot
    Set-ItemProperty -Path $explorerAdv -Name "EnableSnapAssistFlyout" -Value 0 -Type DWord -Force  # Snap
    Write-Host "  [OK] Taskbar cleaned" -ForegroundColor Green

    # Search box hidden
    $searchPath = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    Set-ItemProperty -Path $searchPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force
    Write-Host "  [OK] Search box hidden" -ForegroundColor Green

    # Sticky Keys, Filter Keys, Toggle Keys
    $accessPath = "$hiveRoot\Control Panel\Accessibility\StickyKeys"
    if (-not (Test-Path $accessPath)) { New-Item -Path $accessPath -Force | Out-Null }
    Set-ItemProperty -Path $accessPath -Name "Flags" -Value "506" -Force

    $filterPath = "$hiveRoot\Control Panel\Accessibility\Keyboard Response"
    if (-not (Test-Path $filterPath)) { New-Item -Path $filterPath -Force | Out-Null }
    Set-ItemProperty -Path $filterPath -Name "Flags" -Value "122" -Force

    $togglePath = "$hiveRoot\Control Panel\Accessibility\ToggleKeys"
    if (-not (Test-Path $togglePath)) { New-Item -Path $togglePath -Force | Out-Null }
    Set-ItemProperty -Path $togglePath -Name "Flags" -Value "62" -Force
    Write-Host "  [OK] Sticky/Filter Keys popups disabled, Toggle Keys beep enabled" -ForegroundColor Green

    # Disable Narrator shortcut
    $narratorPath = "$hiveRoot\SOFTWARE\Microsoft\Narrator\NoRoam"
    if (-not (Test-Path $narratorPath)) { New-Item -Path $narratorPath -Force | Out-Null }
    Set-ItemProperty -Path $narratorPath -Name "WinEnterLaunchEnabled" -Value 0 -Type DWord -Force
    Write-Host "  [OK] Narrator shortcut disabled" -ForegroundColor Green

    # Notifications
    $pushPath = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $pushPath)) { New-Item -Path $pushPath -Force | Out-Null }
    Set-ItemProperty -Path $pushPath -Name "ToastEnabled" -Value 1 -Type DWord -Force

    $contentPath = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $contentPath)) { New-Item -Path $contentPath -Force | Out-Null }
    Set-ItemProperty -Path $contentPath -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $contentPath -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $contentPath -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $contentPath -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $contentPath -Name "SoftLandingEnabled" -Value 0 -Type DWord -Force
    Write-Host "  [OK] Notifications/suggestions disabled" -ForegroundColor Green

    # Game Bar disabled
    $gameBarPath = "$hiveRoot\SOFTWARE\Microsoft\GameBar"
    if (-not (Test-Path $gameBarPath)) { New-Item -Path $gameBarPath -Force | Out-Null }
    Set-ItemProperty -Path $gameBarPath -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord -Force
    Write-Host "  [OK] Game Bar disabled" -ForegroundColor Green

    # OOBE nag disabled
    $userOobe = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
    if (-not (Test-Path $userOobe)) { New-Item -Path $userOobe -Force | Out-Null }
    Set-ItemProperty -Path $userOobe -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord -Force
    Write-Host "  [OK] OOBE nag disabled" -ForegroundColor Green

    # Start menu suggestions disabled
    $startPath = "$hiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\Start"
    if (-not (Test-Path $startPath)) { New-Item -Path $startPath -Force | Out-Null }
    Set-ItemProperty -Path $startPath -Name "ShowRecentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Start menu suggestions disabled" -ForegroundColor Green

    # Unload hive if we loaded it
    if ($hiveMounted) {
        [gc]::Collect()
        Start-Sleep -Seconds 2
        reg unload "HKU\StudentTemp" 2>$null
        Write-Host "  Student hive unloaded" -ForegroundColor DarkGray
    }
}

# ---- 7. Fix Admin taskbar too (Widgets) ----
Write-Host "`n[7/7] Fixing Admin taskbar..." -ForegroundColor Yellow
$adminExplorer = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Try via policy instead since direct write failed during bootstrap
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
Set-ItemProperty -Path $policyPath -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
Write-Host "  [OK] Widgets disabled via policy (machine-wide)" -ForegroundColor Green

# Auxiliary pins
$auxPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins"
if (Test-Path $auxPath) {
    Set-ItemProperty -Path $auxPath -Name "MailPin" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auxPath -Name "RecallPin" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auxPath -Name "TFLPin" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auxPath -Name "CopilotPWAPin" -Value 0 -Type DWord -Force
    Write-Host "  [OK] Auxiliary taskbar pins disabled" -ForegroundColor Green
}

# Set file ownership so Student can access their own files
Write-Host "`nSetting ownership on Student profile copies..." -ForegroundColor Yellow
icacls "$studentProfile\AppData\Roaming\nvda" /grant "Student:(OI)(CI)F" /T /Q 2>$null
icacls "$studentProfile\AppData\Roaming\vlc" /grant "Student:(OI)(CI)F" /T /Q 2>$null
icacls "$studentProfile\AppData\Roaming\audacity" /grant "Student:(OI)(CI)F" /T /Q 2>$null
icacls "$studentProfile\AppData\Roaming\GoldenDict" /grant "Student:(OI)(CI)F" /T /Q 2>$null
icacls "$studentProfile\AppData\Local\kiwix-desktop" /grant "Student:(OI)(CI)F" /T /Q 2>$null
Write-Host "  [OK] Permissions set" -ForegroundColor Green

Write-Host "`n=== Student Account Fix Complete ===" -ForegroundColor Green
