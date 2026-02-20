# Vietnam Lab Deployment - Laptop Bootstrap Script
# Run locally on each laptop right after Windows OOBE
# Must be run as Administrator from USB
# Usage: .\Bootstrap-Laptop.ps1 -PCNumber 5

param(
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,19)]
    [int]$PCNumber
)

# ---- CONFIGURE THESE BEFORE USE ----
$WifiSSID     = "YOUR_SSID_HERE"
$WifiPassword = "YOUR_PASSWORD_HERE"
$NASShare     = "\\AndrewServer\Data"
$DriveLetter  = "Z"
# -------------------------------------

$hostname = "PC-{0:D2}" -f $PCNumber

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Laptop Bootstrap" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Target hostname: $hostname" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click and select 'Run as Administrator'" -ForegroundColor Red
    pause
    exit 1
}

# 1. Set hostname
Write-Host "[1/8] Setting hostname to $hostname..." -ForegroundColor Yellow
Rename-Computer -NewName $hostname -Force -ErrorAction Stop
Write-Host "      Hostname set to $hostname" -ForegroundColor Green

# 2. Connect to Wi-Fi
Write-Host "[2/8] Connecting to Wi-Fi ($WifiSSID)..." -ForegroundColor Yellow
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
    Write-Host "      WARNING: Wi-Fi not connected after ${maxWait}s. Continue manually." -ForegroundColor Red
}

# 3. Enable WinRM
Write-Host "[3/8] Enabling WinRM..." -ForegroundColor Yellow
Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop | Out-Null
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Write-Host "      WinRM enabled" -ForegroundColor Green

# 4. Configure firewall for WinRM
Write-Host "[4/8] Configuring firewall..." -ForegroundColor Yellow
# WinRM rules
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes profile=any | Out-Null
# File and printer sharing
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=yes | Out-Null
Write-Host "      Firewall rules configured" -ForegroundColor Green

# 5. Set execution policy
Write-Host "[5/8] Setting execution policy to RemoteSigned..." -ForegroundColor Yellow
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -Scope LocalMachine
Write-Host "      Execution policy set" -ForegroundColor Green

# 6. Map NAS drive
Write-Host "[6/8] Mapping $NASShare as ${DriveLetter}:..." -ForegroundColor Yellow
# Remove existing mapping if present
if (Test-Path "${DriveLetter}:\") {
    net use "${DriveLetter}:" /delete /yes 2>$null | Out-Null
}
net use "${DriveLetter}:" "$NASShare" /persistent:yes 2>$null
if (Test-Path "${DriveLetter}:\") {
    Write-Host "      ${DriveLetter}: mapped to $NASShare" -ForegroundColor Green
} else {
    Write-Host "      WARNING: Could not map ${DriveLetter}: drive. NAS may not be reachable yet." -ForegroundColor Red
}

# 7. Install Tailscale VPN
Write-Host "[7/8] Installing Tailscale VPN..." -ForegroundColor Yellow
$tailscaleScript = Join-Path $PSScriptRoot "Install-Tailscale.ps1"
if (Test-Path $tailscaleScript) {
    & $tailscaleScript -PCNumber $PCNumber
} else {
    Write-Host "      WARNING: Install-Tailscale.ps1 not found. Skipping VPN setup." -ForegroundColor Red
    Write-Host "      You can install Tailscale manually later." -ForegroundColor Red
}

# 8. Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$winrmStatus = try { (Get-Service WinRM).Status } catch { "Unknown" }
$currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match "Wi-Fi|Wireless|WLAN" -and $_.PrefixOrigin -ne "WellKnown" }).IPAddress
$tailscaleIP = if (Test-Path "C:\LabTools\tailscale-ip.txt") { Get-Content "C:\LabTools\tailscale-ip.txt" -ErrorAction SilentlyContinue } else { "Not configured" }

Write-Host "  Hostname:      $hostname (effective after reboot)" -ForegroundColor White
Write-Host "  IP Address:    $currentIP" -ForegroundColor White
Write-Host "  Tailscale IP:  $tailscaleIP" -ForegroundColor White
Write-Host "  WinRM:         $winrmStatus" -ForegroundColor White
Write-Host "  Drive Map:     ${DriveLetter}: -> $NASShare" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Reboot required to apply hostname change." -ForegroundColor Yellow
$reboot = Read-Host "Reboot now? (Y/N)"
if ($reboot -eq "Y" -or $reboot -eq "y") {
    Restart-Computer -Force
}
