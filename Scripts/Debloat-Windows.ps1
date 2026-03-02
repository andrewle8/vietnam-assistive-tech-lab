# Vietnam Lab Deployment - Windows 11 Debloat
# Standalone script containing Steps 23-29 from Configure-Laptop.ps1
# Run this on machines that already have Configure-Laptop applied but need debloating.
# Requires Administrator.

param(
    [string]$LogPath = "$PSScriptRoot\debloat.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Windows 11 Debloat" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator!" "ERROR"
    Write-Host "`nPlease right-click and select 'Run as Administrator'" -ForegroundColor Red
    pause
    exit 1
}

Write-Log "=== Windows 11 Debloat Started on $env:COMPUTERNAME ===" "INFO"

$successCount = 0
$failCount = 0

# Step 1: Remove bloatware apps
Write-Log "Step 1: Removing bloatware apps..." "INFO"

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
        Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
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

# Step 2: Remove OneDrive
Write-Log "Step 2: Removing OneDrive..." "INFO"

try {
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    }
    if (Test-Path $oneDriveSetup) {
        Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
        Write-Log "OneDrive uninstalled" "INFO"
    }

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

    $oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $oneDrivePolicy)) { New-Item -Path $oneDrivePolicy -Force | Out-Null }
    Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -Force

    Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match 'OneDrive' } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    Write-Log "OneDrive removed and disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not remove OneDrive: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 3: Disable Widgets, Cortana, and Search Highlights
Write-Log "Step 3: Disabling Widgets, Cortana, and Search Highlights..." "INFO"

try {
    $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $dshPath)) { New-Item -Path $dshPath -Force | Out-Null }
    Set-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -Value 0 -Force

    $searchPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    Set-ItemProperty -Path $searchPath -Name "AllowCortana" -Value 0 -Force

    $searchSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
    if (-not (Test-Path $searchSettings)) { New-Item -Path $searchSettings -Force | Out-Null }
    Set-ItemProperty -Path $searchSettings -Name "IsDynamicSearchBoxEnabled" -Value 0 -Force

    $explorerPolicies = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $explorerPolicies)) { New-Item -Path $explorerPolicies -Force | Out-Null }
    Set-ItemProperty -Path $explorerPolicies -Name "DisableSearchBoxSuggestions" -Value 1 -Force

    Write-Log "Widgets, Cortana, and Search Highlights disabled" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not disable Widgets/Cortana/Search: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 4: Neuter Microsoft Edge
Write-Log "Step 4: Neutering Microsoft Edge..." "INFO"

try {
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

    $edgePolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicies)) { New-Item -Path $edgePolicies -Force | Out-Null }
    Set-ItemProperty -Path $edgePolicies -Name "HideFirstRunExperience" -Value 1 -Force
    Set-ItemProperty -Path $edgePolicies -Name "StartupBoostEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "BackgroundModeEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "ComponentUpdatesEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingsCampaignEnabled" -Value 0 -Force

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

# Step 5: Clean taskbar
Write-Log "Step 5: Cleaning taskbar..." "INFO"

try {
    $taskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Set-ItemProperty -Path $taskbarPath -Name "TaskbarMn" -Value 0 -Force
    Set-ItemProperty -Path $taskbarPath -Name "ShowTaskViewButton" -Value 0 -Force
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarDa" -Value 0 -Force
    Set-ItemProperty -Path $taskbarPath -Name "ShowCopilotButton" -Value 0 -Force -ErrorAction SilentlyContinue

    $searchRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $searchRegPath)) { New-Item -Path $searchRegPath -Force | Out-Null }
    Set-ItemProperty -Path $searchRegPath -Name "SearchboxTaskbarMode" -Value 0 -Force

    $taskband = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    if (Test-Path $taskband) {
        Remove-ItemProperty -Path $taskband -Name "Favorites" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $taskband -Name "FavoritesResolve" -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Taskbar cleaned (Chat, Task View, Search, Widgets, Copilot hidden)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not clean taskbar: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 6: Reduce telemetry
Write-Log "Step 6: Reducing telemetry..." "INFO"

try {
    $dataCollection = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $dataCollection)) { New-Item -Path $dataCollection -Force | Out-Null }
    Set-ItemProperty -Path $dataCollection -Name "AllowTelemetry" -Value 0 -Force

    $adInfo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (-not (Test-Path $adInfo)) { New-Item -Path $adInfo -Force | Out-Null }
    Set-ItemProperty -Path $adInfo -Name "Enabled" -Value 0 -Force

    $systemPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $systemPolicies)) { New-Item -Path $systemPolicies -Force | Out-Null }
    Set-ItemProperty -Path $systemPolicies -Name "EnableActivityFeed" -Value 0 -Force
    Set-ItemProperty -Path $systemPolicies -Name "PublishUserActivities" -Value 0 -Force
    Set-ItemProperty -Path $systemPolicies -Name "UploadUserActivities" -Value 0 -Force

    Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue

    Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue

    Write-Log "Telemetry reduced to minimum" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not reduce telemetry: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Step 7: Additional UX cleanup
Write-Log "Step 7: Additional UX cleanup..." "INFO"

try {
    # Disable Xbox Game Bar
    $gameBar = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gameBar)) { New-Item -Path $gameBar -Force | Out-Null }
    Set-ItemProperty -Path $gameBar -Name "UseNexusForGameBarEnabled" -Value 0 -Force
    $gameDVR = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $gameDVR)) { New-Item -Path $gameDVR -Force | Out-Null }
    Set-ItemProperty -Path $gameDVR -Name "GameDVR_Enabled" -Value 0 -Force
    $gameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDVRPolicy)) { New-Item -Path $gameDVRPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRPolicy -Name "AllowGameDVR" -Value 0 -Force

    # Disable Snap Layouts hover tooltip
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

    # Disable touch keyboard auto-show
    $touchKB = "HKCU:\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path $touchKB)) { New-Item -Path $touchKB -Force | Out-Null }
    Set-ItemProperty -Path $touchKB -Name "TipbandDesiredVisibility" -Value 0 -Force

    Write-Log "Additional UX cleanup complete (Game Bar, Snap Layouts, OOBE nag, Start suggestions, lock screen tips, touch keyboard)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not complete UX cleanup: $($_.Exception.Message)" "ERROR"
    $failCount++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Windows 11 Debloat Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Computer:      $env:COMPUTERNAME" -ForegroundColor White
Write-Host "Successful:    $successCount" -ForegroundColor Green
Write-Host "Failed:        $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
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
Write-Host "NOTE: A reboot is recommended for all changes to take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

pause
