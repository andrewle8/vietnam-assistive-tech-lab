# App Accessibility Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pre-configure Firefox, VLC, Audacity, SumatraPDF, Kiwix, and GoldenDict with optimal settings for blind NVDA users across 19 laptops.

**Architecture:** Config files stored in `Config/` subdirectories, copied to Windows user profile paths during `Configure-Laptop.ps1`. Follows existing NVDA/Firefox deployment pattern.

**Tech Stack:** PowerShell, JSON (Firefox policies), INI (VLC/Audacity/Kiwix), custom format (SumatraPDF), XML (GoldenDict), CSS

---

### Task 1: Update Firefox policies.json

**Files:**
- Modify: `Config/firefox-profile/policies.json`

**Step 1: Replace policies.json with expanded accessibility version**

Replace the entire file with the updated version that adds ~30 accessibility preferences while keeping all existing settings. Remove `toolkit.telemetry.enabled` (outside allowed prefix list — telemetry already blocked by `datareporting.policy.dataSubmissionEnabled`).

```json
{
  "policies": {
    "Homepage": {
      "URL": "about:blank",
      "Locked": true,
      "StartPage": "homepage"
    },
    "DisableAppUpdate": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "PictureInPicture": {
      "Enabled": false,
      "Locked": true
    },
    "RequestedLocales": ["vi", "en-US"],
    "Extensions": {
      "Uninstall": [
        "pictureinpicture@mozilla.org"
      ]
    },
    "Preferences": {
      "intl.locale.requested": {
        "Value": "vi,en-US",
        "Status": "locked"
      },
      "media.videocontrols.picture-in-picture.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "media.videocontrols.picture-in-picture.video-toggle.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "browser.aboutwelcome.enabled": {
        "Value": false,
        "Status": "locked"
      },
      "browser.shell.checkDefaultBrowser": {
        "Value": false,
        "Status": "locked"
      },
      "datareporting.policy.dataSubmissionEnabled": {
        "Value": false,
        "Status": "locked"
      },

      "accessibility.force_disabled": {
        "Value": 0,
        "Status": "locked",
        "Type": "number"
      },
      "accessibility.browsewithcaret": {
        "Value": true,
        "Status": "default"
      },
      "accessibility.browsewithcaret_shortcut.enabled": {
        "Value": true,
        "Status": "locked"
      },
      "accessibility.tabfocus": {
        "Value": 7,
        "Status": "locked",
        "Type": "number"
      },

      "ui.prefersReducedMotion": {
        "Value": 1,
        "Status": "locked",
        "Type": "number"
      },
      "ui.key.menuAccessKeyFocuses": {
        "Value": false,
        "Status": "locked"
      },

      "media.autoplay.default": {
        "Value": 5,
        "Status": "locked",
        "Type": "number"
      },

      "browser.download.useDownloadDir": {
        "Value": true,
        "Status": "locked"
      },
      "browser.download.folderList": {
        "Value": 1,
        "Status": "locked",
        "Type": "number"
      },
      "browser.download.always_ask_before_handling_new_types": {
        "Value": false,
        "Status": "locked"
      },
      "browser.download.open_pdf_attachments_inline": {
        "Value": true,
        "Status": "locked"
      },
      "browser.download.manager.addToRecentDocs": {
        "Value": false,
        "Status": "locked"
      },

      "signon.autofillForms": {
        "Value": false,
        "Status": "locked"
      },
      "signon.rememberSignons": {
        "Value": false,
        "Status": "locked"
      },
      "browser.formfill.enable": {
        "Value": false,
        "Status": "locked"
      },

      "browser.tabs.warnOnClose": {
        "Value": false,
        "Status": "locked"
      },
      "browser.link.open_newwindow": {
        "Value": 3,
        "Status": "locked",
        "Type": "number"
      },
      "browser.link.open_newwindow.restriction": {
        "Value": 0,
        "Status": "locked",
        "Type": "number"
      },

      "browser.startup.page": {
        "Value": 1,
        "Status": "locked",
        "Type": "number"
      },
      "browser.sessionstore.resume_from_crash": {
        "Value": false,
        "Status": "locked"
      },

      "privacy.trackingprotection.enabled": {
        "Value": true,
        "Status": "locked"
      },
      "privacy.trackingprotection.socialtracking.enabled": {
        "Value": true,
        "Status": "locked"
      },
      "dom.popup_maximum": {
        "Value": 2,
        "Status": "locked",
        "Type": "number"
      },
      "network.prefetch-next": {
        "Value": false,
        "Status": "locked"
      },
      "network.dns.disablePrefetch": {
        "Value": true,
        "Status": "locked"
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add Config/firefox-profile/policies.json
git commit -m "Add accessibility prefs to Firefox policies.json"
```

---

### Task 2: Create VLC config

**Files:**
- Create: `Config/vlc-config/vlcrc`

**Step 1: Create vlcrc**

```ini
# VLC Configuration for Vietnam Lab
# Optimized for blind users with NVDA screen reader
# Deployed by Configure-Laptop.ps1

[core]
# Audio-only mode (no video window)
video=0

# No audio visualizations
audio-visual=none

# Single instance (enqueue files, don't spawn new windows)
one-instance=1
one-instance-when-started-from-file=1

# No network metadata fetching
metadata-network-access=0

# Save volume between sessions
volume-save=1

[qt]
# Skip first-run privacy dialog
qt-privacy-ask=0

# Show filename in title bar (NVDA reads it)
qt-name-in-title=1

# No system tray icon (avoids hidden window confusion)
qt-system-tray=0

# Don't start minimized
qt-start-minimized=0

# Don't pause when minimized
qt-pause-minimized=0

# No background cone graphic
qt-bgcone=0

# No fullscreen controller
qt-fs-controller=0

# Volume keys control VLC directly
qt-disable-volume-keys=0

# No recent files (privacy on shared machines)
qt-recentplay=0

# Track change notifications (NVDA reads them)
qt-notification=1

# Volume cap at 100%
qt-max-volume=100

# Don't resize to video dimensions
qt-video-autoresize=0

# Don't continue from last position
qt-continue=0
```

**Step 2: Commit**

```bash
git add Config/vlc-config/vlcrc
git commit -m "Add VLC accessibility config for blind users"
```

---

### Task 3: Create Audacity config

**Files:**
- Create: `Config/audacity-config/audacity.cfg`

**Step 1: Create audacity.cfg**

```ini
PrefsVersion=1.1.1r1

[GUI]
ShowSplashScreen=0
AutoScroll=0
ShowExtraMenus=1
BeepOnCompletion=1
SelectAllOnNone=1
CircularTrackNavigation=1
TypeToCreateLabel=0
Theme=dark
ShowTrackNameInWaveform=0

[AudioIO]
Host=MME
RecordChannels=1
LatencyDuration=100
LatencyCorrection=-130
SWPlaythrough=0
SoundActivatedRecord=0
EffectsPreviewLen=6
CutPreviewBeforeLen=2
CutPreviewAfterLen=1
SeekShortPeriod=1
SeekLongPeriod=15

[SamplingRate]
DefaultProjectSampleRate=44100

[Spectrum]
EnableSpectralSelection=0

[Warnings]
FirstProjectSave=0

[Window]
Maximized=1
```

**Step 2: Commit**

```bash
git add Config/audacity-config/audacity.cfg
git commit -m "Add Audacity accessibility config for blind users"
```

---

### Task 4: Create SumatraPDF config

**Files:**
- Create: `Config/sumatrapdf-config/SumatraPDF-settings.txt`

**Step 1: Create SumatraPDF-settings.txt**

```
# SumatraPDF settings for Vietnam Lab
# Optimized for blind/low-vision users

DefaultDisplayMode = continuous
DefaultZoom = fit width
UseSysColors = true
ShowToc = true
ShowLinks = true
UIFontSize = 14

FixedPageUI [
	TextColor = #000000
	BackgroundColor = #ffffff
	InvertColors = false
	HideScrollbars = false
]

EbookUI [
	FontName = Arial
	FontSize = 16
	TextColor = #000000
	BackgroundColor = #ffffff
]
```

**Step 2: Commit**

```bash
git add Config/sumatrapdf-config/SumatraPDF-settings.txt
git commit -m "Add SumatraPDF accessibility config"
```

---

### Task 5: Create Kiwix config

**Files:**
- Create: `Config/kiwix-config/Kiwix-desktop.conf`

**Step 1: Create Kiwix-desktop.conf**

```ini
[view]
zoomFactor=1.3

[General]
reopenTab=true
moveToTrash=false
```

**Step 2: Commit**

```bash
git add Config/kiwix-config/Kiwix-desktop.conf
git commit -m "Add Kiwix accessibility config"
```

---

### Task 6: Create GoldenDict config and CSS

**Files:**
- Create: `Config/goldendict-config/config`
- Create: `Config/goldendict-config/styles/article-style.css`

**Step 1: Create GoldenDict config XML**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <preferences>
    <zoomFactor>1.5</zoomFactor>
    <helpZoomFactor>1.5</helpZoomFactor>
    <wordsZoomLevel>2</wordsZoomLevel>
    <scanPopupUseUIAutomation>1</scanPopupUseUIAutomation>
    <scanPopupUseIAccessibleEx>1</scanPopupUseIAccessibleEx>
    <pronounceOnLoadMain>0</pronounceOnLoadMain>
    <pronounceOnLoadPopup>0</pronounceOnLoadPopup>
    <interfaceLanguage></interfaceLanguage>
  </preferences>
</config>
```

**Step 2: Create article-style.css**

```css
body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 18px;
    line-height: 1.6;
}
```

**Step 3: Commit**

```bash
git add Config/goldendict-config/
git commit -m "Add GoldenDict accessibility config and article CSS"
```

---

### Task 7: Add app config deployment steps to Configure-Laptop.ps1

**Files:**
- Modify: `Scripts/Configure-Laptop.ps1` (insert before line 1333 "# Summary")

**Step 1: Add Steps 31-35**

Insert the following block between the end of Step 30 (line 1331) and the Summary section (line 1333). Each step follows the same pattern: resolve the Student user profile, create the target directory, copy the config file.

```powershell
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
```

**Step 2: Update the Summary output section**

In the summary section (around line 1353), after the existing Firefox line, add lines for the new app configs:

```powershell
Write-Host "  VLC           Audio-only, NVDA-friendly, volume cap 100%" -ForegroundColor White
Write-Host "  Audacity      MME audio host, no splash, beep on completion" -ForegroundColor White
Write-Host "  SumatraPDF    Continuous scroll, fit-width, system colors" -ForegroundColor White
Write-Host "  Kiwix         130% zoom, reopen last tab" -ForegroundColor White
Write-Host "  GoldenDict    150% zoom, 18px article font, UI Automation" -ForegroundColor White
```

**Step 3: Commit**

```bash
git add Scripts/Configure-Laptop.ps1
git commit -m "Add app config deployment steps 31-35 to Configure-Laptop"
```

---

### Task 8: Update summary and push

**Step 1: Verify all config files exist**

```bash
ls -la Config/vlc-config/vlcrc Config/audacity-config/audacity.cfg Config/sumatrapdf-config/SumatraPDF-settings.txt Config/kiwix-config/Kiwix-desktop.conf Config/goldendict-config/config Config/goldendict-config/styles/article-style.css Config/firefox-profile/policies.json
```

Expected: all 7 files present.

**Step 2: Push to remote**

```bash
git push
```
