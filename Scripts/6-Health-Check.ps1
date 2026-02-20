# Vietnam Lab Deployment - Post-Deployment Health Check
# Version: 1.0
# Run anytime to verify the lab PC is healthy
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\health-check.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Health Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PC: $env:COMPUTERNAME  |  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor DarkGray

Write-Log "=== Health Check Started on $env:COMPUTERNAME ===" "INFO"

# -----------------------------------------------
# Section 1: Software Presence (same as 2-Verify)
# -----------------------------------------------

Write-Host "--- Software Installed ---`n" -ForegroundColor White

$softwareChecks = @(
    @{
        Name = "NVDA"
        Paths = @(
            "C:\Program Files\NVDA\nvda.exe",
            "C:\Program Files (x86)\NVDA\nvda.exe"
        )
        Critical = $true
    },
    @{
        Name = "VNVoice (SAPI5)"
        Paths = @(
            "C:\Windows\Speech\Engines\TTS\*vnvoice*",
            "C:\Program Files\SaoMai\VNVoice\*"
        )
        Critical = $true
    },
    @{
        Name = "Sao Mai Typing Tutor"
        Paths = @(
            "C:\Program Files\SaoMai\TypingTutor\*",
            "C:\Program Files (x86)\SaoMai\TypingTutor\*"
        )
        Critical = $false
    },
    @{
        Name = "LibreOffice"
        Paths = @(
            "C:\Program Files\LibreOffice\program\soffice.exe",
            "C:\Program Files (x86)\LibreOffice\program\soffice.exe"
        )
        Critical = $true
    },
    @{
        Name = "Firefox"
        Paths = @(
            "C:\Program Files\Mozilla Firefox\firefox.exe",
            "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
        )
        Critical = $true
    },
    @{
        Name = "VLC Media Player"
        Paths = @(
            "C:\Program Files\VideoLAN\VLC\vlc.exe",
            "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        )
        Critical = $false
    },
    @{
        Name = "Thorium Reader"
        Paths = @(
            "$env:LOCALAPPDATA\Programs\Thorium\Thorium.exe",
            "C:\Program Files\Thorium\Thorium.exe",
            "C:\Program Files (x86)\Thorium\Thorium.exe"
        )
        Critical = $false
    },
    @{
        Name = "LEAP Games"
        Paths = @(
            "C:\Games\LEAP\TicTacToe\*.exe",
            "C:\Games\LEAP\Tennis\*.exe",
            "C:\Games\LEAP\Curve\*.exe"
        )
        Critical = $false
    },
    @{
        Name = "SumatraPDF"
        Paths = @(
            "C:\Program Files\SumatraPDF\SumatraPDF.exe",
            "${env:LOCALAPPDATA}\SumatraPDF\SumatraPDF.exe"
        )
        Critical = $false
    },
    @{
        Name = "GoldenDict"
        Paths = @(
            "C:\Program Files\GoldenDict\GoldenDict.exe"
        )
        Critical = $false
    }
)

$results = @{
    Pass = 0
    Fail = 0
    Critical = 0
}

foreach ($check in $softwareChecks) {
    $found = $false
    $foundPath = ""

    foreach ($path in $check.Paths) {
        if (Test-Path $path) {
            $found = $true
            $foundPath = $path
            break
        }
    }

    if ($found) {
        Write-Host "[" -NoNewline
        Write-Host "OK" -ForegroundColor Green -NoNewline
        Write-Host "] $($check.Name)" -NoNewline
        Write-Host " - $foundPath" -ForegroundColor DarkGray
        Write-Log "$($check.Name): FOUND at $foundPath" "SUCCESS"
        $results.Pass++
    } else {
        Write-Host "[" -NoNewline
        Write-Host "FAIL" -ForegroundColor Red -NoNewline
        Write-Host "] $($check.Name)" -NoNewline
        if ($check.Critical) {
            Write-Host " [CRITICAL]" -ForegroundColor Red
            $results.Critical++
        } else {
            Write-Host " [Optional]" -ForegroundColor Yellow
        }
        $severity = if ($check.Critical) { "CRITICAL" } else { "WARNING" }
        Write-Log "$($check.Name): NOT FOUND" $severity
        $results.Fail++
    }
}

# -----------------------------------------------
# Section 2: Runtime Checks
# -----------------------------------------------

Write-Host "`n--- Runtime Status ---`n" -ForegroundColor White

# Check if NVDA is currently running
$nvdaProcess = Get-Process nvda -ErrorAction SilentlyContinue
if ($nvdaProcess) {
    Write-Host "[" -NoNewline
    Write-Host "OK" -ForegroundColor Green -NoNewline
    Write-Host "] NVDA is running (PID: $($nvdaProcess.Id))"
    Write-Log "NVDA process: RUNNING (PID $($nvdaProcess.Id))" "SUCCESS"
    $results.Pass++
} else {
    Write-Host "[" -NoNewline
    Write-Host "WARN" -ForegroundColor Yellow -NoNewline
    Write-Host "] NVDA is not running"
    Write-Host "      Restart with: Ctrl+Alt+N" -ForegroundColor DarkGray
    Write-Log "NVDA process: NOT RUNNING" "WARNING"
    $results.Fail++
}

# Check NVDA auto-start registry entry
$nvdaAutoStart = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NVDA" -ErrorAction SilentlyContinue
if ($nvdaAutoStart) {
    Write-Host "[" -NoNewline
    Write-Host "OK" -ForegroundColor Green -NoNewline
    Write-Host "] NVDA auto-start enabled"
    Write-Log "NVDA auto-start: ENABLED" "SUCCESS"
    $results.Pass++
} else {
    Write-Host "[" -NoNewline
    Write-Host "FAIL" -ForegroundColor Red -NoNewline
    Write-Host "] NVDA auto-start is disabled"
    Write-Host "      Re-run 3-Configure-NVDA.ps1 to fix" -ForegroundColor DarkGray
    Write-Log "NVDA auto-start: DISABLED" "CRITICAL"
    $results.Fail++
    $results.Critical++
}

# Check disk space on system drive
$systemDrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
if ($systemDrive) {
    $freeGB = [math]::Round($systemDrive.Free / 1GB, 1)
    if ($freeGB -ge 5) {
        Write-Host "[" -NoNewline
        Write-Host "OK" -ForegroundColor Green -NoNewline
        Write-Host "] Disk space: ${freeGB}GB free"
        Write-Log "Disk space: ${freeGB}GB free" "SUCCESS"
        $results.Pass++
    } else {
        Write-Host "[" -NoNewline
        Write-Host "WARN" -ForegroundColor Yellow -NoNewline
        Write-Host "] Disk space low: ${freeGB}GB free"
        Write-Log "Disk space LOW: ${freeGB}GB free" "WARNING"
        $results.Fail++
    }
}

# Detect removable USB drives
Write-Host "`n--- USB Drives ---`n" -ForegroundColor White
$usbDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
if ($usbDrives) {
    foreach ($usb in $usbDrives) {
        $label = if ($usb.VolumeName) { $usb.VolumeName } else { "(no label)" }
        $sizeGB = if ($usb.Size) { [math]::Round($usb.Size / 1GB, 1) } else { "?" }
        Write-Host "  [$($usb.DeviceID)] $label - ${sizeGB}GB"
        Write-Log "USB detected: $($usb.DeviceID) $label ${sizeGB}GB" "INFO"
    }
} else {
    Write-Host "  No USB drives detected" -ForegroundColor DarkGray
    Write-Log "No USB drives detected" "INFO"
}

# -----------------------------------------------
# Summary
# -----------------------------------------------

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Health Check Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $($results.Pass)" -ForegroundColor Green
Write-Host "Failed: $($results.Fail)" -ForegroundColor $(if($results.Fail -gt 0){"Red"}else{"Green"})
Write-Host "Critical Issues: $($results.Critical)" -ForegroundColor $(if($results.Critical -gt 0){"Red"}else{"Green"})

Write-Log "Summary - Pass: $($results.Pass), Fail: $($results.Fail), Critical: $($results.Critical)" "INFO"

if ($results.Critical -gt 0) {
    Write-Host "`n" -NoNewline
    Write-Host "CRITICAL ISSUES FOUND" -ForegroundColor Red
    Write-Host "This PC needs attention before students can use it." -ForegroundColor Red
} elseif ($results.Fail -gt 0) {
    Write-Host "`n" -NoNewline
    Write-Host "Minor issues found — lab is functional" -ForegroundColor Yellow
} else {
    Write-Host "`n" -NoNewline
    Write-Host "All checks passed — PC is healthy!" -ForegroundColor Green
}

Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Log "=== Health Check Complete ===" "INFO"

pause
