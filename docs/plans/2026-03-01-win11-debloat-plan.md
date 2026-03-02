# Windows 11 Debloat Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all Windows 11 bloatware, widgets, Cortana, Edge shortcuts, telemetry, and taskbar clutter from lab laptops so NVDA users encounter a clean, distraction-free environment.

**Architecture:** Add Steps 23-28 to `Scripts/Configure-Laptop.ps1` (before the Summary block at line 1002). Each step follows the existing try/catch + Write-Log + successCount/failCount pattern. Update the summary block to report debloat results.

**Tech Stack:** PowerShell (Get-AppxPackage, Remove-AppxPackage, Get-AppxProvisionedPackage, Remove-AppxProvisionedPackage, registry edits)

---

### Task 1: Add Step 23 — Remove Bloatware Apps

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1:1000` (insert before line 1002 `# Summary`)

**Step 1: Add the bloatware removal block**

Insert after line 1000 (after the OpenSSH step closing brace). Use a list of package name patterns and loop through them with `Get-AppxPackage -AllUsers` and `Get-AppxProvisionedPackage -Online`:

```powershell
# Step 23: Remove bloatware apps (reduces clutter for NVDA screen reader users)
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
```

**Step 2: Verify the code follows existing patterns**

Check: uses try/catch, Write-Log, increments $successCount/$failCount, has a step comment header.

**Step 3: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add bloatware removal (Step 23) to Configure-Laptop"
```

---

### Task 2: Add Step 24 — Remove OneDrive

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert after Step 23)

**Step 1: Add OneDrive removal block**

```powershell
# Step 24: Remove OneDrive (offline machines, nag popups confuse NVDA)
Write-Log "Step 24: Removing OneDrive..." "INFO"

try {
    # Stop OneDrive process
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Uninstall OneDrive (try both 64-bit and 32-bit paths)
    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
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
    $clsid = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
    Set-ItemProperty -Path $clsid -Name "DisableFileSyncNGSC" -Value 1 -Force

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
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add OneDrive removal (Step 24) to Configure-Laptop"
```

---

### Task 3: Add Step 25 — Disable Widgets, Cortana, Search Highlights

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert after Step 24)

**Step 1: Add the registry tweaks block**

```powershell
# Step 25: Disable Widgets, Cortana, and Search Highlights
Write-Log "Step 25: Disabling Widgets, Cortana, and Search Highlights..." "INFO"

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
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add Widgets/Cortana/Search disable (Step 25) to Configure-Laptop"
```

---

### Task 4: Add Step 26 — Neuter Microsoft Edge

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert after Step 25)

**Step 1: Add Edge neutering block**

Full removal is fragile on Win11 (MS re-installs it via updates, but updates are disabled on these machines). Remove shortcuts and disable auto-start instead.

```powershell
# Step 26: Neuter Microsoft Edge (remove shortcuts, disable auto-start)
Write-Log "Step 26: Neutering Microsoft Edge..." "INFO"

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

    # Disable Edge first-run experience
    $edgePolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicies)) { New-Item -Path $edgePolicies -Force | Out-Null }
    Set-ItemProperty -Path $edgePolicies -Name "HideFirstRunExperience" -Value 1 -Force
    Set-ItemProperty -Path $edgePolicies -Name "StartupBoostEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "BackgroundModeEnabled" -Value 0 -Force

    # Prevent Edge from running in background
    Set-ItemProperty -Path $edgePolicies -Name "ComponentUpdatesEnabled" -Value 0 -Force

    # Prevent Edge from stealing default browser
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingEnabled" -Value 0 -Force
    Set-ItemProperty -Path $edgePolicies -Name "DefaultBrowserSettingsCampaignEnabled" -Value 0 -Force

    # Remove Edge from startup
    $edgeAutostart = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $edgeAutostart -Name "MicrosoftEdgeAutoLaunch*" -Force -ErrorAction SilentlyContinue

    Write-Log "Microsoft Edge neutered (shortcuts removed, auto-start disabled)" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not neuter Microsoft Edge: $($_.Exception.Message)" "ERROR"
    $failCount++
}
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add Edge neutering (Step 26) to Configure-Laptop"
```

---

### Task 5: Add Step 27 — Clean Taskbar

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert after Step 26)

**Step 1: Add taskbar cleanup block**

```powershell
# Step 27: Clean taskbar (remove clutter, keep only essentials)
Write-Log "Step 27: Cleaning taskbar..." "INFO"

try {
    $taskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    # Hide Chat icon (Teams consumer)
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarMn" -Value 0 -Force
    # Hide Task View button
    Set-ItemProperty -Path $taskbarPath -Name "ShowTaskViewButton" -Value 0 -Force
    # Hide Search box (keep Start menu search, just hide taskbar box)
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Force
    # Hide Widgets button
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarDa" -Value 0 -Force
    # Hide Copilot button (Win11 23H2+)
    Set-ItemProperty -Path $taskbarPath -Name "ShowCopilotButton" -Value 0 -Force -ErrorAction SilentlyContinue

    # Unpin all default apps from taskbar by clearing the layout
    # Delete existing pinned items (TaskBand registry)
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
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add taskbar cleanup (Step 27) to Configure-Laptop"
```

---

### Task 6: Add Step 28 — Reduce Telemetry

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert after Step 27)

**Step 1: Add telemetry reduction block**

```powershell
# Step 28: Reduce telemetry (offline machines, no need to phone home)
Write-Log "Step 28: Reducing telemetry..." "INFO"

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

    # Disable dmwappushservice (WAP Push Message Routing)
    Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue

    Write-Log "Telemetry reduced to minimum" "SUCCESS"
    $successCount++
} catch {
    Write-Log "Could not reduce telemetry: $($_.Exception.Message)" "ERROR"
    $failCount++
}
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add telemetry reduction (Step 28) to Configure-Laptop"
```

---

### Task 7: Update Summary Block

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` — the summary block starting at line 1022

**Step 1: Add debloat section to summary output**

After the existing "Safety & Hardening:" block (around line 1033), add:

```powershell
Write-Host "Debloat & Cleanup:" -ForegroundColor White
Write-Host "  Bloatware     Removed (Xbox, News, Weather, Solitaire, etc.)" -ForegroundColor White
Write-Host "  OneDrive      Removed" -ForegroundColor White
Write-Host "  Widgets       Disabled" -ForegroundColor White
Write-Host "  Cortana       Disabled" -ForegroundColor White
Write-Host "  Edge          Neutered (shortcuts removed, no auto-start)" -ForegroundColor White
Write-Host "  Taskbar       Cleaned (Chat, Task View, Search, Widgets hidden)" -ForegroundColor White
Write-Host "  Telemetry     Reduced to minimum" -ForegroundColor White
Write-Host ""
```

**Step 2: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add debloat results to Configure-Laptop summary output"
```
