# Vietnam Lab Deployment - Full Laptop Setup
# End-to-end: hostname, Wi-Fi, WinRM, install software, configure NVDA,
# Windows hardening, Tailscale VPN, scheduled tasks (update agent + fleet reporter)
# Must be run as Administrator from USB
# Usage: .\Bootstrap-Laptop.ps1 -PCNumber 5
# Last Updated: February 2026

param(
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,19)]
    [int]$PCNumber,

    [switch]$SkipInstall,
    [switch]$SkipReboot
)

# ---- CONFIGURE THESE BEFORE USE ----
$WifiSSID     = "YOUR_SSID_HERE"
$WifiPassword = "YOUR_PASSWORD_HERE"
$NASShare     = "\\AndrewServer\Data"
$DriveLetter  = "Z"
# -------------------------------------

$hostname = "PC-{0:D2}" -f $PCNumber
$totalSteps = 10
$currentStep = 0
$stepResults = @{}

function Step {
    param([string]$Name)
    $script:currentStep++
    Write-Host "[$currentStep/$totalSteps] $Name..." -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Full Laptop Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Target: $hostname  |  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor White
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click and select 'Run as Administrator'" -ForegroundColor Red
    pause
    exit 1
}

$scriptsDir = $PSScriptRoot
$usbRoot = Split-Path -Parent $scriptsDir

# =============================================
# Phase 1: Network & System Setup
# =============================================

Write-Host "`n--- Phase 1: Network & System Setup ---" -ForegroundColor White
Write-Host ""

Step "Setting hostname to $hostname"
if ($env:COMPUTERNAME -eq $hostname) {
    Write-Host "      Hostname already set to $hostname - skipping rename" -ForegroundColor Green
} else {
    Rename-Computer -NewName $hostname -Force -ErrorAction Stop
    Write-Host "      Hostname set to $hostname" -ForegroundColor Green
}

Step "Connecting to Wi-Fi ($WifiSSID)"
$profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$WifiSSID</name>
    <SSIDConfig>
        <SSID>
            <name>$WifiSSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$WifiPassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
    <MacRandomization xmlns="http://www.microsoft.com/networking/WLAN/profile/v3">
        <enableRandomization>false</enableRandomization>
    </MacRandomization>
</WLANProfile>
"@

$profilePath = "$env:TEMP\wifi-profile.xml"
$profileXml | Out-File -FilePath $profilePath -Encoding UTF8
netsh wlan add profile filename="$profilePath" | Out-Null
Remove-Item $profilePath -Force -ErrorAction SilentlyContinue
netsh wlan connect name="$WifiSSID" | Out-Null

# Wait for connection
$maxWait = 30
$waited = 0
while ($waited -lt $maxWait) {
    $iface = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -match "Wi-Fi|Wireless|WLAN" }
    if ($iface) {
        $ip = (Get-NetIPAddress -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($ip) { break }
    }
    Start-Sleep -Seconds 2
    $waited += 2
}

if ($ip) {
    Write-Host "      Connected. IP: $ip" -ForegroundColor Green
} else {
    Write-Host "      WARNING: Wi-Fi not connected after ${maxWait}s. Continuing..." -ForegroundColor Red
}

Step "Enabling WinRM"
Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop | Out-Null
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Write-Host "      WinRM enabled" -ForegroundColor Green

Step "Configuring firewall"
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes profile=any | Out-Null
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=yes | Out-Null
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -Scope LocalMachine
Write-Host "      Firewall + execution policy configured" -ForegroundColor Green

Step "Mapping NAS drive ($NASShare as ${DriveLetter}:)"
if (Test-Path "${DriveLetter}:\") {
    net use "${DriveLetter}:" /delete /yes 2>$null | Out-Null
}
net use "${DriveLetter}:" "$NASShare" /persistent:yes 2>$null
if (Test-Path "${DriveLetter}:\") {
    Write-Host "      ${DriveLetter}: mapped to $NASShare" -ForegroundColor Green
} else {
    Write-Host "      WARNING: Could not map ${DriveLetter}: drive. NAS may not be reachable." -ForegroundColor Red
}

# =============================================
# Phase 2: Software Installation
# =============================================

Write-Host "`n--- Phase 2: Software Installation ---" -ForegroundColor White
Write-Host ""

# Signal sub-scripts not to pause (they pause when run standalone)
$env:LAB_BOOTSTRAP = "1"

if ($SkipInstall) {
    Write-Host "      Skipping installation (-SkipInstall flag set)" -ForegroundColor DarkGray
    $currentStep += 3
} else {
    Step "Installing all software (1-Install-All.ps1)"
    $installScript = Join-Path $scriptsDir "1-Install-All.ps1"
    if (Test-Path $installScript) {
        try {
            & $installScript
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
            Write-Host "      Software installation complete" -ForegroundColor Green
            $stepResults["1-Install-All"] = $true
        } catch {
            Write-Host "      ERROR: 1-Install-All.ps1 failed: $($_.Exception.Message)" -ForegroundColor Red
            $stepResults["1-Install-All"] = $false
        }
    } else {
        Write-Host "      ERROR: 1-Install-All.ps1 not found at $installScript" -ForegroundColor Red
        $stepResults["1-Install-All"] = $false
    }

    Step "Configuring NVDA (3-Configure-NVDA.ps1)"
    $configScript = Join-Path $scriptsDir "3-Configure-NVDA.ps1"
    if (Test-Path $configScript) {
        try {
            & $configScript
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
            Write-Host "      NVDA configured" -ForegroundColor Green
            $stepResults["3-Configure-NVDA"] = $true
        } catch {
            Write-Host "      ERROR: 3-Configure-NVDA.ps1 failed: $($_.Exception.Message)" -ForegroundColor Red
            $stepResults["3-Configure-NVDA"] = $false
        }
    } else {
        Write-Host "      ERROR: 3-Configure-NVDA.ps1 not found at $configScript" -ForegroundColor Red
        $stepResults["3-Configure-NVDA"] = $false
    }

    Step "Verifying installation (2-Verify-Installation.ps1)"
    $verifyScript = Join-Path $scriptsDir "2-Verify-Installation.ps1"
    if (Test-Path $verifyScript) {
        try {
            & $verifyScript
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
            Write-Host "      Verification complete" -ForegroundColor Green
            $stepResults["2-Verify-Installation"] = $true
        } catch {
            Write-Host "      ERROR: 2-Verify-Installation.ps1 failed: $($_.Exception.Message)" -ForegroundColor Red
            $stepResults["2-Verify-Installation"] = $false
        }
    } else {
        Write-Host "      ERROR: 2-Verify-Installation.ps1 not found at $verifyScript" -ForegroundColor Red
        $stepResults["2-Verify-Installation"] = $false
    }
}

# =============================================
# Phase 3: Hardening & Remote Management
# =============================================

Write-Host "`n--- Phase 3: Hardening & Remote Management ---" -ForegroundColor White
Write-Host ""

Step "Applying Windows hardening and laptop config (Configure-Laptop.ps1)"
$configLaptopScript = Join-Path $scriptsDir "Configure-Laptop.ps1"
if (Test-Path $configLaptopScript) {
    try {
        & $configLaptopScript
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
        Write-Host "      Laptop configured (hardening, rclone, scheduled tasks)" -ForegroundColor Green
        $stepResults["Configure-Laptop"] = $true
    } catch {
        Write-Host "      ERROR: Configure-Laptop.ps1 failed: $($_.Exception.Message)" -ForegroundColor Red
        $stepResults["Configure-Laptop"] = $false
    }
} else {
    Write-Host "      ERROR: Configure-Laptop.ps1 not found at $configLaptopScript" -ForegroundColor Red
    $stepResults["Configure-Laptop"] = $false
}

Step "Installing Tailscale VPN"
$tailscaleScript = Join-Path $scriptsDir "Install-Tailscale.ps1"
if (Test-Path $tailscaleScript) {
    try {
        & $tailscaleScript -PCNumber $PCNumber
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
        $stepResults["Install-Tailscale"] = $true
    } catch {
        Write-Host "      ERROR: Install-Tailscale.ps1 failed: $($_.Exception.Message)" -ForegroundColor Red
        $stepResults["Install-Tailscale"] = $false
    }
} else {
    Write-Host "      WARNING: Install-Tailscale.ps1 not found. Skipping VPN setup." -ForegroundColor Red
    $stepResults["Install-Tailscale"] = $false
}

# =============================================
# Summary
# =============================================

# =============================================
# Step Results Summary
# =============================================

$failedSteps = $stepResults.GetEnumerator() | Where-Object { $_.Value -eq $false }
$passedSteps = $stepResults.GetEnumerator() | Where-Object { $_.Value -eq $true }

if ($failedSteps) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Setup Complete WITH ERRORS - $hostname" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed steps:" -ForegroundColor Red
    foreach ($step in $failedSteps) {
        Write-Host "  [FAIL] $($step.Key)" -ForegroundColor Red
    }
    Write-Host ""
    foreach ($step in $passedSteps) {
        Write-Host "  [OK  ] $($step.Key)" -ForegroundColor Green
    }
} else {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Setup Complete - All Steps Passed - $hostname" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Setup Details - $hostname" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$winrmStatus = try { (Get-Service WinRM).Status } catch { "Unknown" }
$currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match "Wi-Fi|Wireless|WLAN" -and $_.PrefixOrigin -ne "WellKnown" }).IPAddress
$tailscaleIP = if (Test-Path "C:\LabTools\tailscale-ip.txt") { Get-Content "C:\LabTools\tailscale-ip.txt" -ErrorAction SilentlyContinue } else { "Not configured" }

Write-Host ""
Write-Host "  Hostname:      $hostname (effective after reboot)" -ForegroundColor White
Write-Host "  IP Address:    $currentIP" -ForegroundColor White
Write-Host "  Tailscale IP:  $tailscaleIP" -ForegroundColor White
Write-Host "  WinRM:         $winrmStatus" -ForegroundColor White
Write-Host "  Drive Map:     ${DriveLetter}: -> $NASShare" -ForegroundColor White
Write-Host ""
Write-Host "  Office Suite:  Microsoft Office" -ForegroundColor White
Write-Host "  Software:      $(if(-not $SkipInstall){'Installed + Verified'}else{'Skipped'})" -ForegroundColor White
Write-Host "  NVDA:          $(if(-not $SkipInstall){'Configured (Vietnamese)'}else{'Skipped'})" -ForegroundColor White
Write-Host "  Hardening:     Applied (Configure-Laptop.ps1)" -ForegroundColor White
Write-Host "  Update Agent:  Scheduled (daily 2-4 AM)" -ForegroundColor White
Write-Host "  Fleet Report:  Scheduled (daily 3 AM)" -ForegroundColor White
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $SkipReboot) {
    Write-Host "Reboot required to apply hostname change." -ForegroundColor Yellow
    $reboot = Read-Host "Reboot now? (Y/N)"
    if ($reboot -eq "Y" -or $reboot -eq "y") {
        Restart-Computer -Force
    }
} else {
    Write-Host "Reboot skipped (-SkipReboot flag). Remember to reboot for hostname change." -ForegroundColor Yellow
}
