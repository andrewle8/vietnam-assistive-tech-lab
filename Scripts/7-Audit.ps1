# Vietnam Lab Deployment - Machine Audit Script
# Version: 1.1
# Compares a machine's state against the manifest.json and reports drift.
# Run on any lab PC to check if it matches the expected configuration.
# Last Updated: April 2026

param(
    [string]$ManifestPath,
    [string]$LogPath = "$PSScriptRoot\audit.log",
    [switch]$OutputJson
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Machine Audit" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PC: $env:COMPUTERNAME  |  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
Write-Host ""

# Find manifest.json
if (-not $ManifestPath) {
    $usbRoot = Split-Path -Parent $PSScriptRoot
    $ManifestPath = Join-Path $usbRoot "manifest.json"
}

if (-not (Test-Path $ManifestPath)) {
    Write-Host "[ERROR] manifest.json not found at: $ManifestPath" -ForegroundColor Red
    Write-Host "        Place manifest.json in the repo root or specify -ManifestPath" -ForegroundColor Red
    pause
    exit 1
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
Write-Host "Manifest version: $($manifest.manifest_version)" -ForegroundColor DarkGray
Write-Host ""
Write-Log "=== Audit Started on $env:COMPUTERNAME (manifest $($manifest.manifest_version)) ==="

$results = @()
$pass = 0
$fail = 0
$warn = 0

function Add-Result {
    param([string]$Category, [string]$Check, [string]$Expected, [string]$Actual, [string]$Status)
    $script:results += [PSCustomObject]@{
        Category = $Category
        Check    = $Check
        Expected = $Expected
        Actual   = $Actual
        Status   = $Status
    }
    $icon = switch ($Status) {
        "PASS" { "OK"; $script:pass++ }
        "FAIL" { "FAIL"; $script:fail++ }
        "WARN" { "WARN"; $script:warn++ }
    }
    $color = switch ($Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "[" -NoNewline
    Write-Host $icon -ForegroundColor $color -NoNewline
    Write-Host "] $Category :: $Check" -NoNewline
    if ($Status -ne "PASS") {
        Write-Host " (expected: $Expected, found: $Actual)" -ForegroundColor $color
    } else {
        Write-Host ""
    }
    Write-Log "$Category :: $Check - $Status (expected: $Expected, actual: $Actual)" $Status
}

# -----------------------------------------------
# Section 1: Windows Version
# -----------------------------------------------
Write-Host "`n--- Windows ---" -ForegroundColor White
Write-Host ""

$winBuild = [System.Environment]::OSVersion.Version.Build
$minBuild = [int]$manifest.os.min_build
if ($winBuild -ge $minBuild) {
    Add-Result "Windows" "Build >= $minBuild" $minBuild $winBuild "PASS"
} else {
    Add-Result "Windows" "Build >= $minBuild" $minBuild $winBuild "FAIL"
}

# Check timezone
$tz = (Get-TimeZone).Id
$expectedTz = $manifest.configuration.windows_timezone
if ($tz -eq $expectedTz) {
    Add-Result "Windows" "Timezone" $expectedTz $tz "PASS"
} else {
    Add-Result "Windows" "Timezone" $expectedTz $tz "FAIL"
}

# Check language — compare primary subtag so expected "vi-VN" accepts actual "vi"
# (Windows canonicalises Set-WinUserLanguageList "vi-VN" down to LanguageTag "vi" on
# some builds). Match is bidirectional: either value can be the more specific one.
$langList = Get-WinUserLanguageList
$primaryLang = $langList[0].LanguageTag
$expectedLang = $manifest.configuration.windows_language
$primarySubtag  = ($primaryLang  -split '-')[0]
$expectedSubtag = ($expectedLang -split '-')[0]
if ($primarySubtag -ieq $expectedSubtag) {
    Add-Result "Windows" "Primary Language" $expectedLang $primaryLang "PASS"
} else {
    Add-Result "Windows" "Primary Language" $expectedLang $primaryLang "FAIL"
}

# Check Windows Update service
$wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
$wuStatus = if ($wuService) { $wuService.StartType.ToString() } else { "NotFound" }
$expectedWU = $manifest.configuration.windows_update
if ($expectedWU -eq "disabled" -and $wuStatus -eq "Disabled") {
    Add-Result "Windows" "Windows Update" "Disabled" $wuStatus "PASS"
} elseif ($expectedWU -eq "disabled") {
    Add-Result "Windows" "Windows Update" "Disabled" $wuStatus "FAIL"
} else {
    Add-Result "Windows" "Windows Update" $expectedWU $wuStatus "PASS"
}

# -----------------------------------------------
# Section 2: Software Installed
# -----------------------------------------------
Write-Host "`n--- Software ---" -ForegroundColor White
Write-Host ""

foreach ($sw in $manifest.software.PSObject.Properties) {
    $name = $sw.Name
    $info = $sw.Value

    # Skip LibreOffice (replaced by Microsoft Office)
    if ($name -eq "libreoffice") { continue }

    $found = $false

    foreach ($path in $info.paths) {
        # Expand environment variables
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
        if (Test-Path $expandedPath) {
            $found = $true
            break
        }
    }

    $status = if ($found) { "PASS" } elseif ($info.critical) { "FAIL" } else { "WARN" }
    $actual = if ($found) { "Installed" } else { "Missing" }
    Add-Result "Software" $name $info.version $actual $status
}

# -----------------------------------------------
# Section 3: NVDA Configuration
# -----------------------------------------------
Write-Host "`n--- NVDA Config ---" -ForegroundColor White
Write-Host ""

$nvdaConfigPath = "C:\Users\Student\AppData\Roaming\nvda\nvda.ini"
if (Test-Path $nvdaConfigPath) {
    $nvdaConfig = Get-Content $nvdaConfigPath -Raw

    # Check language
    if ($nvdaConfig -match "language\s*=\s*(.+)") {
        $nvdaLang = $Matches[1].Trim()
        $expected = $manifest.configuration.nvda_language
        if ($nvdaLang -eq $expected) {
            Add-Result "NVDA" "Language" $expected $nvdaLang "PASS"
        } else {
            Add-Result "NVDA" "Language" $expected $nvdaLang "FAIL"
        }
    }

    # Check voice
    if ($nvdaConfig -match "voice\s*=\s*(.+)") {
        $nvdaVoice = $Matches[1].Trim()
        $expected = $manifest.configuration.nvda_voice
        if ($nvdaVoice -eq $expected) {
            Add-Result "NVDA" "Voice" $expected $nvdaVoice "PASS"
        } else {
            Add-Result "NVDA" "Voice" $expected $nvdaVoice "FAIL"
        }
    }

    # Check speech rate
    if ($nvdaConfig -match "rate\s*=\s*(\d+)") {
        $nvdaRate = [int]$Matches[1]
        $expected = $manifest.configuration.nvda_speech_rate
        if ($nvdaRate -eq $expected) {
            Add-Result "NVDA" "Speech Rate" $expected $nvdaRate "PASS"
        } else {
            Add-Result "NVDA" "Speech Rate" $expected $nvdaRate "WARN"
        }
    }
} else {
    Add-Result "NVDA" "Config File" "Present" "Missing" "FAIL"
}

# Check NVDA is running
$nvdaProc = Get-Process nvda -ErrorAction SilentlyContinue
if ($nvdaProc) {
    Add-Result "NVDA" "Running" "Yes" "PID $($nvdaProc.Id)" "PASS"
} else {
    Add-Result "NVDA" "Running" "Yes" "Not running" "WARN"
}

# Check NVDA addons against manifest. Installed addon directories may have version
# suffixes ("-2.0.19") OR be bare ("clipspeak"). Match by name prefix; ignore version.
$addonsDir = "C:\Users\Student\AppData\Roaming\nvda\addons"
if (Test-Path $addonsDir) {
    $installedAddons = Get-ChildItem $addonsDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    foreach ($expected in $manifest.nvda_addons.PSObject.Properties) {
        $aname = $expected.Name
        $aver  = $expected.Value
        # Match either "<name>" or "<name>-<anything>" (case-insensitive)
        $found = $installedAddons | Where-Object { $_ -ieq $aname -or $_ -ilike "$aname-*" }
        if ($found) {
            Add-Result "NVDA" "Addon: $aname" $aver "Installed" "PASS"
        } else {
            Add-Result "NVDA" "Addon: $aname" $aver "Missing" "WARN"
        }
    }
} else {
    Add-Result "NVDA" "Addons Directory" "Present" "Missing" "FAIL"
}

# NVDA auto-start is now the LabNVDAStart scheduled task (audited in Section 6 below);
# legacy NVDA.lnk + StartupApproved checks removed because Win11 deferred those by ~2 min
# on battery cold boot.

# -----------------------------------------------
# Section 4: System Configuration
# -----------------------------------------------
Write-Host "`n--- System Config ---" -ForegroundColor White
Write-Host ""

# Check power settings - hibernate
$hibFile = "C:\hiberfil.sys"
$hibExists = Test-Path $hibFile
$expectedHib = $manifest.configuration.hibernate
if ($expectedHib -eq "disabled" -and -not $hibExists) {
    Add-Result "System" "Hibernate" "Disabled" "Disabled" "PASS"
} elseif ($expectedHib -eq "disabled" -and $hibExists) {
    Add-Result "System" "Hibernate" "Disabled" "Enabled" "FAIL"
} else {
    Add-Result "System" "Hibernate" $expectedHib $(if($hibExists){"Enabled"}else{"Disabled"}) "PASS"
}

# Check disk space
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($freeGB -ge 10) {
    Add-Result "System" "Free Disk Space" ">= 10 GB" "${freeGB} GB" "PASS"
} elseif ($freeGB -ge 5) {
    Add-Result "System" "Free Disk Space" ">= 10 GB" "${freeGB} GB" "WARN"
} else {
    Add-Result "System" "Free Disk Space" ">= 10 GB" "${freeGB} GB" "FAIL"
}

# Check LabTools directory
if (Test-Path "C:\LabTools") {
    Add-Result "System" "LabTools Directory" "Present" "Present" "PASS"
} else {
    Add-Result "System" "LabTools Directory" "Present" "Missing" "FAIL"
}

# Generate and check battery report
$batteryReport = "C:\LabTools\battery-report.htm"
powercfg /batteryreport /output $batteryReport 2>&1 | Out-Null
if (Test-Path $batteryReport) {
    Add-Result "System" "Battery Report" "Generated" "C:\LabTools\battery-report.htm" "PASS"
} else {
    Add-Result "System" "Battery Report" "Generated" "Failed" "WARN"
}

# Check battery health from WMI. On some Windows builds Get-CimInstance against
# root\wmi\BatteryStaticData throws "Generic failure" while the legacy Get-WmiObject
# call succeeds returning the same data. Try CIM first, fall back to WMI before
# giving up. FullChargedCapacity reads reliably via CIM on the same systems.
$designCap = $null
$fullChargeCap = $null
try {
    $designCap = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
} catch {
    try {
        $designCap = (Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
    } catch { $designCap = $null }
}
try {
    $fullChargeCap = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
} catch {
    try {
        $fullChargeCap = (Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
    } catch { $fullChargeCap = $null }
}
if ($designCap -and $designCap -gt 0 -and $fullChargeCap) {
    $healthPct = [math]::Round(($fullChargeCap / $designCap) * 100, 0)
    $status = if ($healthPct -ge 60) { "PASS" } elseif ($healthPct -ge 40) { "WARN" } else { "FAIL" }
    Add-Result "System" "Battery Health" ">= 60%" "${healthPct}%" $status
} else {
    Add-Result "System" "Battery Health" "Readable" "Could not read (WMI unavailable)" "WARN"
}

# Default browser is intentionally left as Edge on Win11 24H2 (see Configure-Laptop
# Step 4c rationale). The default PDF handler is also Edge by default in Windows 11.
# Firefox stays installed as a desktop shortcut. No verification needed for browser
# default — accept Windows' default. Audit just informs which handler is current.
try {
    $studentSidAudit = (New-Object System.Security.Principal.NTAccount("Student")).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
    $studentHive = "Registry::HKEY_USERS\$studentSidAudit"
    $httpHandler = (Get-ItemProperty "$studentHive\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $pdfHandler  = (Get-ItemProperty "$studentHive\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $httpShown = if ($httpHandler) { $httpHandler } else { "(empty - Windows default applies)" }
    $pdfShown  = if ($pdfHandler)  { $pdfHandler }  else { "(empty - Windows default applies)" }
    Add-Result "System" "Default Browser (Student)" "Edge or Windows default" $httpShown "PASS"
    Add-Result "System" "Default PDF Reader (Student)" "Edge or Windows default" $pdfShown  "PASS"
} catch {
    Add-Result "System" "Default App Associations" "Readable" "Could not resolve Student SID" "WARN"
}

# Check NVDA backup exists
if (Test-Path "C:\LabTools\nvda-backup\nvda.ini") {
    Add-Result "System" "NVDA Config Backup" "Present" "Present" "PASS"
} else {
    Add-Result "System" "NVDA Config Backup" "Present" "Missing" "WARN"
}

# Office default-save location to D:\ (the student USB). Word uses the legacy "DOC-PATH"
# value name; Excel and PowerPoint use "DefaultPath". All three are set in Configure-Laptop
# Step 4 across the Student SID hive. If D: is unmounted, Office falls back gracefully
# but the registry value should still be D:\.
try {
    $studentSid = (New-Object System.Security.Principal.NTAccount("Student")).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
    $studentHive = "Registry::HKEY_USERS\$studentSid"

    $officeChecks = @(
        @{ App = "Word";       Path = "$studentHive\Software\Microsoft\Office\16.0\Word\Options";       Name = "DOC-PATH" },
        @{ App = "Excel";      Path = "$studentHive\Software\Microsoft\Office\16.0\Excel\Options";      Name = "DefaultPath" },
        @{ App = "PowerPoint"; Path = "$studentHive\Software\Microsoft\Office\16.0\PowerPoint\Options"; Name = "DefaultPath" }
    )
    foreach ($oc in $officeChecks) {
        $val = (Get-ItemProperty -Path $oc.Path -Name $oc.Name -ErrorAction SilentlyContinue).$($oc.Name)
        if ($val -eq "D:\") {
            Add-Result "System" "Office Default Save ($($oc.App))" "D:\" $val "PASS"
        } else {
            $shown = if ($val) { $val } else { "(not set)" }
            Add-Result "System" "Office Default Save ($($oc.App))" "D:\" $shown "FAIL"
        }
    }
} catch {
    Add-Result "System" "Office Default Save" "Readable" "Could not resolve Student SID" "WARN"
}

# Audacity Vietnamese GUI language pin. Audacity rewrites audacity.cfg on every clean
# exit so the deployment script kills audacity.exe first; if Language ever drifts off
# vi the menus revert to English and screen-reader hotkeys (taught in Vietnamese) miss.
$audacityCfg = "C:\Users\Student\AppData\Roaming\audacity\audacity.cfg"
if (Test-Path $audacityCfg) {
    $cfgRaw = Get-Content $audacityCfg -Raw
    # Find Language= within the [Locale] section. Allow whitespace, accept just "vi"
    # (also "vi_VN" if a future Audacity build uses regional variants).
    if ($cfgRaw -match '(?ms)^\[Locale\][^\[]*?^Language\s*=\s*(\S+)') {
        $lang = $Matches[1].Trim()
        if ($lang -ieq "vi" -or $lang -like "vi_*") {
            Add-Result "System" "Audacity Language" "vi" $lang "PASS"
        } else {
            Add-Result "System" "Audacity Language" "vi" $lang "FAIL"
        }
    } else {
        Add-Result "System" "Audacity Language" "vi" "(no [Locale] section)" "WARN"
    }
} else {
    Add-Result "System" "Audacity Language" "vi" "audacity.cfg not yet created" "WARN"
}

# Firefox policies.json — locks the default-browser-popup off, sets Vietnamese locale,
# and pins download dir to D:\. Without it students get the "Make Firefox default?"
# nag on every startup, which a blind student can't dismiss without tab navigation.
$ffPolicies = "C:\Program Files\Mozilla Firefox\distribution\policies.json"
if (Test-Path $ffPolicies) {
    try {
        $pol = Get-Content $ffPolicies -Raw | ConvertFrom-Json
        if ($pol.policies.DontCheckDefaultBrowser -eq $true) {
            Add-Result "System" "Firefox Default-Browser Nag" "Suppressed" "Suppressed" "PASS"
        } else {
            Add-Result "System" "Firefox Default-Browser Nag" "Suppressed" "Not suppressed" "FAIL"
        }
    } catch {
        Add-Result "System" "Firefox policies.json" "Valid JSON" "Parse error" "WARN"
    }
} else {
    Add-Result "System" "Firefox policies.json" "Present" "Missing" "FAIL"
}

# SM Readmate ebook population. Configure-Laptop Step 17b copies EPUBs from the USB
# into Readmate's data folder and inserts tb_books rows so the library shows up on
# first launch. Empty library = students see "No books" and can't access the textbooks.
$readmateDb  = "C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\databases\app_database.db"
$readmateDir = "C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\file"
if (Test-Path $readmateDb) {
    Add-Result "System" "Readmate Database" "Present" "Present" "PASS"
} else {
    Add-Result "System" "Readmate Database" "Present" "Missing" "WARN"
}
if (Test-Path $readmateDir) {
    $epubCount = @(Get-ChildItem $readmateDir -Filter *.epub -Recurse -ErrorAction SilentlyContinue).Count
    if ($epubCount -gt 0) {
        Add-Result "System" "Readmate Ebooks" ">= 1 EPUB" "$epubCount EPUBs" "PASS"
    } else {
        Add-Result "System" "Readmate Ebooks" ">= 1 EPUB" "0 EPUBs" "WARN"
    }
} else {
    Add-Result "System" "Readmate Ebooks" "Populated" "file folder missing" "WARN"
}

# -----------------------------------------------
# Section 5: Remote Management
# -----------------------------------------------
Write-Host "`n--- Remote Management ---" -ForegroundColor White
Write-Host ""

# Check update agent
$updateAgentScript = "C:\LabTools\update-agent\Update-Agent.ps1"
if (Test-Path $updateAgentScript) {
    Add-Result "Remote" "Update Agent" "Deployed" "Deployed" "PASS"
} else {
    Add-Result "Remote" "Update Agent" "Deployed" "Missing" "WARN"
}

# Last update check
$lastUpdateCheck = $null
$updateStatus = "none"
$updateResultsDir = "C:\LabTools\update-agent\results"
if (Test-Path $updateResultsDir) {
    $latestResult = Get-ChildItem $updateResultsDir -Filter "update-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestResult) {
        try {
            $updateData = Get-Content $latestResult.FullName -Raw | ConvertFrom-Json
            $updateStatus = $updateData.status
            $lastUpdateCheck = $latestResult.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        } catch {}
        Add-Result "Remote" "Last Update Check" "Recent" $latestResult.LastWriteTime.ToString("yyyy-MM-dd") "PASS"
    }
}

# System uptime
$uptimeDays = 0
try {
    $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeDays = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)
    Add-Result "Remote" "Uptime" "N/A" "$uptimeDays days" "PASS"
} catch {}

# -----------------------------------------------
# Section 6: Deployment Tasks & Startup
# -----------------------------------------------
Write-Host "`n--- Deployment Tasks ---" -ForegroundColor White
Write-Host ""

# Scheduled tasks created by Configure-Laptop:
#   LabReassignStudentUSB pins any STU-### labeled USB to drive D: (boot/logon/1-min poll).
#   LabUpdateAgent is the GitHub-pull update agent (daily at 18:00).
#   LabNVDAStart auto-launches NVDA at logon (replaces legacy Startup-folder .lnk that
#     Windows deferred ~2 min on battery cold boot).
#   LabVolumeReset / LabBrightnessReset clamp speakers to 50% (hearing safety) and
#     brightness to 50% (battery + comfort) at every logon.
$expectedTasks = @("LabReassignStudentUSB", "LabUpdateAgent", "LabNVDAStart", "LabVolumeReset", "LabBrightnessReset")
foreach ($taskName in $expectedTasks) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Add-Result "Tasks" "Scheduled: $taskName" "Ready" $task.State.ToString() $(if($task.State -eq "Ready" -or $task.State -eq "Running") {"PASS"} else {"WARN"})
    } else {
        Add-Result "Tasks" "Scheduled: $taskName" "Present" "Missing" "FAIL"
    }
}

# LabTools support files. Each is referenced by either a scheduled task or a startup
# shortcut, so a missing file means the corresponding automation is broken.
$labToolsFiles = @(
    "C:\LabTools\reset-volume.ps1",
    "C:\LabTools\reset-brightness.ps1",
    "C:\LabTools\Reassign-StudentUSB.ps1",
    "C:\LabTools\update-agent\Update-Agent.ps1"
)
foreach ($lf in $labToolsFiles) {
    $name = Split-Path $lf -Leaf
    if (Test-Path $lf) {
        Add-Result "Tasks" "LabTools: $name" "Present" "Present" "PASS"
    } else {
        Add-Result "Tasks" "LabTools: $name" "Present" "Missing" "FAIL"
    }
}

# Public desktop shortcuts. Configure-Laptop Step 6 maintains a fixed alphabetized set
# for first-letter screen-reader navigation. Vietnamese filenames (Từ Điển, Thùng Rác)
# require IShellLink Unicode save — WScript.Shell silently corrupts them via CP-1252.
# NVDA.lnk is intentionally NOT on the public desktop: Step 14 removes it there and
# places it on the Student user desktop (so the Win+Ctrl+N hotkey registers per-user).
$publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$expectedShortcuts = @(
    "Audacity.lnk", "Calculator.lnk", "Excel.lnk", "Firefox.lnk",
    "PowerPoint.lnk", "Readmate.lnk", "Sao Mai Typing Tutor.lnk",
    "Thùng Rác.lnk", "Từ Điển.lnk", "USB.lnk", "VLC media player.lnk",
    "Wikipedia.lnk", "Word.lnk"
)
$presentShortcuts = Get-ChildItem $publicDesktop -Filter *.lnk -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$missingShortcuts = $expectedShortcuts | Where-Object { $_ -notin $presentShortcuts }
if ($missingShortcuts.Count -eq 0) {
    Add-Result "Tasks" "Public Desktop Shortcuts" "$($expectedShortcuts.Count) present" "$($expectedShortcuts.Count) present" "PASS"
} else {
    Add-Result "Tasks" "Public Desktop Shortcuts" "$($expectedShortcuts.Count) present" "Missing: $($missingShortcuts -join ', ')" "FAIL"
}

# Student user desktop must have NVDA.lnk (Win+Ctrl+N hotkey registration).
$studentDesktopNvda = "C:\Users\Student\Desktop\NVDA.lnk"
if (Test-Path $studentDesktopNvda) {
    Add-Result "Tasks" "Student Desktop NVDA Shortcut" "Present" "Present" "PASS"
} else {
    Add-Result "Tasks" "Student Desktop NVDA Shortcut" "Present" "Missing" "FAIL"
}

# -----------------------------------------------
# Section 7: Accounts & Localization
# -----------------------------------------------
Write-Host "`n--- Accounts ---" -ForegroundColor White
Write-Host ""

# Student is the target account; LabAdmin is the maintenance/recovery account created
# by Configure-Laptop Step 20. If either is missing, the deployment did not complete.
foreach ($acct in @("Student", "LabAdmin")) {
    $u = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
    if ($u -and $u.Enabled) {
        Add-Result "Accounts" "Local user: $acct" "Enabled" "Enabled" "PASS"
    } elseif ($u) {
        Add-Result "Accounts" "Local user: $acct" "Enabled" "Disabled" "FAIL"
    } else {
        Add-Result "Accounts" "Local user: $acct" "Present" "Missing" "FAIL"
    }
}

# Vietnamese Language Experience Pack (LXP). Win11 modern UI surfaces (Settings, File
# Explorer ribbon, lock screen) only render Vietnamese when the Store-delivered LXP
# is installed; the LIP cab + FoDs alone leave parts of the shell in English. Known
# deployment gap: bootstrap installs the LIP/FoDs but LXP requires Store access.
# Repair tool: Fix-Vietnamese.ps1 on the DEPLOY_ USB.
$lxp = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Microsoft.LanguageExperiencePack*vi*" } | Select-Object -First 1
if ($lxp) {
    Add-Result "Accounts" "Vietnamese LXP" "Installed" $lxp.Version "PASS"
} else {
    Add-Result "Accounts" "Vietnamese LXP" "Installed" "Missing (run Fix-Vietnamese.ps1)" "WARN"
}

# -----------------------------------------------
# Summary
# -----------------------------------------------

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Audit Summary - $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Manifest:  $($manifest.manifest_version)" -ForegroundColor White
Write-Host "Passed:    $pass" -ForegroundColor Green
Write-Host "Warnings:  $warn" -ForegroundColor $(if($warn -gt 0){"Yellow"}else{"Green"})
Write-Host "Failed:    $fail" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})

if ($fail -gt 0) {
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  $($_.Category) :: $($_.Check) - expected $($_.Expected), found $($_.Actual)" -ForegroundColor Red
    }
}

Write-Log "Summary - Pass: $pass, Warn: $warn, Fail: $fail"

# Output JSON report if requested or write to USB
if ($OutputJson) {
    $report = @{
        computer          = $env:COMPUTERNAME
        timestamp         = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        manifest          = $manifest.manifest_version
        pass              = $pass
        warn              = $warn
        fail              = $fail
        uptime_days       = $uptimeDays
        battery_health    = if ($healthPct) { $healthPct } else { "N/A" }
        update_status     = $updateStatus
        last_update_check = $lastUpdateCheck
        results           = $results
    }

    $jsonPath = Join-Path $PSScriptRoot "audit-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd').json"
    $report | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
    Write-Host "`nJSON report: $jsonPath" -ForegroundColor Cyan
}

Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "=== Audit Complete ==="

if (-not $env:LAB_BOOTSTRAP) { pause }
