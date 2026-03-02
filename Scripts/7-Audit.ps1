# Vietnam Lab Deployment - Machine Audit Script
# Version: 1.0
# Compares a machine's state against the manifest.json and reports drift.
# Run on any lab PC to check if it matches the expected configuration.
# Last Updated: February 2026

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

# Check language
$langList = Get-WinUserLanguageList
$primaryLang = $langList[0].LanguageTag
$expectedLang = $manifest.configuration.windows_language
if ($primaryLang -like "$expectedLang*") {
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

$nvdaConfigPath = Join-Path $env:APPDATA "nvda\nvda.ini"
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

# Check battery health from WMI
try {
    $designCap = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop).DesignedCapacity
    $fullChargeCap = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop).FullChargedCapacity
    if ($designCap -gt 0) {
        $healthPct = [math]::Round(($fullChargeCap / $designCap) * 100, 0)
        $status = if ($healthPct -ge 60) { "PASS" } elseif ($healthPct -ge 40) { "WARN" } else { "FAIL" }
        Add-Result "System" "Battery Health" ">= 60%" "${healthPct}%" $status
    }
} catch {
    Add-Result "System" "Battery Health" "Readable" "Could not read" "WARN"
}

# Check NVDA backup exists
if (Test-Path "C:\LabTools\nvda-backup\nvda.ini") {
    Add-Result "System" "NVDA Config Backup" "Present" "Present" "PASS"
} else {
    Add-Result "System" "NVDA Config Backup" "Present" "Missing" "WARN"
}

# -----------------------------------------------
# Section 5: Remote Management
# -----------------------------------------------
Write-Host "`n--- Remote Management ---" -ForegroundColor White
Write-Host ""

# Check Tailscale
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$tailscaleIP = $null
$tailscaleOnline = $false
if (Test-Path $tailscaleExe) {
    Add-Result "Remote" "Tailscale Installed" "Yes" "Installed" "PASS"
    try {
        $tsIP = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
        if ($tsIP -match "^100\.") {
            $tailscaleIP = $tsIP.Trim()
            $tailscaleOnline = $true
            Add-Result "Remote" "Tailscale Connected" "Connected" $tailscaleIP "PASS"
        } else {
            Add-Result "Remote" "Tailscale Connected" "Connected" "Disconnected" "WARN"
        }
    } catch {
        Add-Result "Remote" "Tailscale Connected" "Connected" "Error" "WARN"
    }
} else {
    Add-Result "Remote" "Tailscale Installed" "Yes" "Not installed" "WARN"
}

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

# Last rclone backup
$lastBackup = $null
$rcloneLogDir = "C:\LabTools\rclone\logs"
if (Test-Path $rcloneLogDir) {
    $latestLog = Get-ChildItem $rcloneLogDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        $lastBackup = $latestLog.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        $backupAge = (Get-Date) - $latestLog.LastWriteTime
        if ($backupAge.TotalDays -lt 1) {
            Add-Result "Remote" "Last Backup" "Recent" $latestLog.LastWriteTime.ToString("yyyy-MM-dd HH:mm") "PASS"
        } else {
            Add-Result "Remote" "Last Backup" "Recent" "$([math]::Round($backupAge.TotalDays, 0)) days ago" "WARN"
        }
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
        tailscale_ip      = if ($tailscaleIP) { $tailscaleIP } else { "N/A" }
        tailscale_online  = $tailscaleOnline
        uptime_days       = $uptimeDays
        battery_health    = if ($healthPct) { $healthPct } else { "N/A" }
        update_status     = $updateStatus
        last_update_check = $lastUpdateCheck
        last_backup       = $lastBackup
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
