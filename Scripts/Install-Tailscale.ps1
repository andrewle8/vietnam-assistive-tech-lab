# Vietnam Lab Deployment - Tailscale VPN Installation
# Installs Tailscale and joins the tailnet with a pre-auth key
# Run locally on each laptop during bootstrap (called by Bootstrap-Laptop.ps1)
# Requires Administrator
# Last Updated: February 2026

param(
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,19)]
    [int]$PCNumber,

    [string]$AuthKey = "tskey-auth-CHANGE_ME",

    [string]$InstallerPath
)

$hostname = "PC-{0:D2}" -f $PCNumber

if ($AuthKey -eq "tskey-auth-CHANGE_ME") {
    Write-Host "[ERROR] Auth key is still the placeholder. Pass a real key:" -ForegroundColor Red
    Write-Host "        .\Install-Tailscale.ps1 -PCNumber $PCNumber -AuthKey tskey-auth-YOUR_REAL_KEY" -ForegroundColor Red
    return
}

Write-Host "`n--- Tailscale VPN Setup ---" -ForegroundColor Cyan
Write-Host "Hostname: $hostname" -ForegroundColor White
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Must be run as Administrator" -ForegroundColor Red
    return
}

# Find installer
if (-not $InstallerPath) {
    $usbRoot = Split-Path -Parent $PSScriptRoot
    $searchPaths = @(
        (Get-ChildItem -Path (Join-Path $usbRoot "Installers\Utilities\Tailscale") -Filter "tailscale-setup-*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1),
        (Get-ChildItem -Path (Join-Path $usbRoot "Installers\Utilities\Tailscale") -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1)
    )
    foreach ($found in $searchPaths) {
        if ($found) {
            $InstallerPath = $found.FullName
            break
        }
    }
}

if (-not $InstallerPath -or -not (Test-Path $InstallerPath)) {
    Write-Host "[ERROR] Tailscale installer not found" -ForegroundColor Red
    Write-Host "        Expected in: Installers\Utilities\Tailscale\" -ForegroundColor Red
    Write-Host "        Run 0-Download-Installers.ps1 first" -ForegroundColor Red
    return
}

Write-Host "Installer: $InstallerPath" -ForegroundColor DarkGray

# Install Tailscale silently
Write-Host "Installing Tailscale..." -ForegroundColor Cyan
try {
    $msiArgs = "/i `"$InstallerPath`" /quiet /norestart"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "[ERROR] MSI install exited with code $($process.ExitCode)" -ForegroundColor Red
        return
    }
    Write-Host "[OK] Tailscale installed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Wait for Tailscale service to start
Write-Host "Waiting for Tailscale service..." -ForegroundColor Cyan
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
$maxWait = 30
$waited = 0
while ($waited -lt $maxWait) {
    if (Test-Path $tailscaleExe) { break }
    Start-Sleep -Seconds 2
    $waited += 2
}

if (-not (Test-Path $tailscaleExe)) {
    Write-Host "[ERROR] tailscale.exe not found after install" -ForegroundColor Red
    return
}

# Join the tailnet
# Auth key should be: reusable, tagged tag:vietnam-lab (tag disables node key expiry)
# Generate at: https://login.tailscale.com/admin/settings/keys
Write-Host "Joining tailnet as $hostname..." -ForegroundColor Cyan
try {
    & $tailscaleExe up --authkey="$AuthKey" --hostname="$hostname" --accept-routes=false --shields-up=false --reset 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    # Get Tailscale IP
    $tsStatus = & $tailscaleExe status --json 2>$null | ConvertFrom-Json
    $tailscaleIP = $tsStatus.Self.TailscaleIPs | Where-Object { $_ -match "^100\." } | Select-Object -First 1

    if ($tailscaleIP) {
        Write-Host "[OK] Joined tailnet. IP: $tailscaleIP" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Tailscale installed but no IP assigned yet" -ForegroundColor Yellow
        Write-Host "       May need internet connection to complete registration" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] Could not join tailnet: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "       Tailscale is installed. Run manually:" -ForegroundColor Yellow
    Write-Host "       tailscale up --authkey=YOUR_KEY --hostname=$hostname" -ForegroundColor Yellow
}

# Note: tailscale-ipn.exe (IPN client) is required for Tailscale to connect.
# Configure-Laptop.ps1 sets up a PowerShell startup script that launches it
# and hides the window via Win32 ShowWindow API, so students never see a popup.
Write-Host "[OK] Tailscale installed (Configure-Laptop.ps1 will set up hidden startup)" -ForegroundColor Green

Write-Host "--- Tailscale Setup Complete ---" -ForegroundColor Cyan
Write-Host ""
