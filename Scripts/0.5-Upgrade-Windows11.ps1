# Vietnam Lab Deployment - Windows 10 to Windows 11 In-Place Upgrade
# Version: 1.0
# Run BEFORE scripts 1-3. Requires Administrator.
# Uses a pre-downloaded Windows 11 ISO to perform a silent in-place upgrade.
# The Dell Latitude 5420 meets all Win11 requirements (i5-1145G7, TPM 2.0, UEFI).
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\win11-upgrade.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}elseif($Level -eq "WARNING"){"Yellow"}else{"Cyan"})
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Windows 11 Upgrade" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator!" "ERROR"
    Write-Host "`nPlease right-click and select 'Run as Administrator'" -ForegroundColor Red
    pause
    exit 1
}

Write-Log "=== Windows 11 Upgrade Started on $env:COMPUTERNAME ==="

# Check current Windows version
$currentBuild = [System.Environment]::OSVersion.Version.Build
$currentVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
Write-Log "Current Windows version: $currentVersion (Build $currentBuild)"

# Check if already on Windows 11 (build 22000+)
if ($currentBuild -ge 22000) {
    Write-Log "This machine is already running Windows 11 (Build $currentBuild)" "SUCCESS"
    Write-Host "`nNo upgrade needed. Proceeding to next step." -ForegroundColor Green
    Write-Host "Run .\1-Install-All.ps1 next." -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 0
}

# Check hardware requirements
Write-Log "Checking hardware requirements..."

# Check TPM 2.0
$tpm = Get-Tpm -ErrorAction SilentlyContinue
if ($tpm -and $tpm.TpmPresent) {
    Write-Log "TPM present: $($tpm.ManufacturerVersion)" "SUCCESS"
} else {
    Write-Log "WARNING: TPM not detected. Upgrade may fail." "WARNING"
}

# Check Secure Boot
$secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
if ($secureBoot) {
    Write-Log "Secure Boot: Enabled" "SUCCESS"
} else {
    Write-Log "WARNING: Secure Boot not enabled. Enable in BIOS if upgrade fails." "WARNING"
}

# Check RAM
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Log "RAM: ${ramGB}GB $(if($ramGB -ge 4){'(OK)'}else{'(WARNING: minimum 4GB)'})"

# Check disk space (need ~20GB free)
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Log "Free disk space: ${freeGB}GB $(if($freeGB -ge 20){'(OK)'}else{'(WARNING: recommend 20GB+)'})"

if ($freeGB -lt 15) {
    Write-Log "ERROR: Not enough disk space. Need at least 15GB free, have ${freeGB}GB." "ERROR"
    pause
    exit 1
}

# Find the Windows 11 ISO
$usbRoot = Split-Path -Parent $PSScriptRoot
$isoPath = Join-Path $usbRoot "Installers\Windows\Win11_25H2_English_x64.iso"

# Also check for alternative names/locations
# Note: Vietnamese ISO not available from Microsoft as of Feb 2026
$altPaths = @(
    (Join-Path $usbRoot "Installers\Windows\Win11_24H2_English_x64.iso"),
    (Join-Path $usbRoot "Installers\Windows\Win11.iso"),
    (Join-Path $usbRoot "Win11.iso")
)

if (-not (Test-Path $isoPath)) {
    foreach ($alt in $altPaths) {
        if (Test-Path $alt) {
            $isoPath = $alt
            break
        }
    }
}

if (-not (Test-Path $isoPath)) {
    Write-Log "ERROR: Windows 11 ISO not found!" "ERROR"
    Write-Host "`nExpected location: $isoPath" -ForegroundColor Red
    Write-Host "`nTo download:" -ForegroundColor Yellow
    Write-Host "  1. Go to https://www.microsoft.com/en-us/software-download/windows11" -ForegroundColor White
    Write-Host "  2. Download the Windows 11 ISO (64-bit)" -ForegroundColor White
    Write-Host "  3. Place it in: Installers\Windows\" -ForegroundColor White
    Write-Host "  4. Re-run this script" -ForegroundColor White
    pause
    exit 1
}

Write-Log "Found Windows 11 ISO: $isoPath"
$isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
Write-Log "ISO size: ${isoSize}GB"

# Mount the ISO
Write-Log "Mounting ISO..."
try {
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Log "ISO mounted as ${driveLetter}:" "SUCCESS"
} catch {
    Write-Log "ERROR: Could not mount ISO: $($_.Exception.Message)" "ERROR"
    pause
    exit 1
}

$setupPath = "${driveLetter}:\setup.exe"
if (-not (Test-Path $setupPath)) {
    Write-Log "ERROR: setup.exe not found in ISO" "ERROR"
    Dismount-DiskImage -ImagePath $isoPath
    pause
    exit 1
}

# Run the upgrade
Write-Log "Starting Windows 11 in-place upgrade..."
Write-Log "This will take 20-45 minutes. The PC will reboot automatically."
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  IMPORTANT: DO NOT turn off the PC!" -ForegroundColor Yellow
Write-Host "  The upgrade will reboot 1-2 times." -ForegroundColor Yellow
Write-Host "  Wait for Windows to fully start again." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

# Silent upgrade flags:
# /auto upgrade    - In-place upgrade preserving apps and files
# /quiet           - Minimal UI
# /eula accept     - Auto-accept the EULA (required for unattended upgrade)
# /showoobe none   - Skip the out-of-box experience
# /DynamicUpdate disable - Don't download updates during install (offline)
# /Compat IgnoreWarning  - Proceed even with minor compatibility warnings
# /Telemetry Disable     - No telemetry during install
# /copylogs $LogPath     - Copy setup logs

$setupArgs = "/auto upgrade /quiet /eula accept /showoobe none /DynamicUpdate disable /Compat IgnoreWarning /Telemetry Disable /copylogs `"$(Split-Path $LogPath)`""

Write-Log "Running: setup.exe $setupArgs"

try {
    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Log "Windows 11 upgrade initiated successfully (Exit: $($process.ExitCode))" "SUCCESS"
        Write-Log "The PC will reboot to complete the upgrade."
    } elseif ($process.ExitCode -eq 0xC1900210) {
        Write-Log "Upgrade compatibility check passed. Upgrade in progress." "SUCCESS"
    } else {
        Write-Log "Setup exited with code: $($process.ExitCode)" "WARNING"
        Write-Log "Check logs at: $(Split-Path $LogPath)" "WARNING"
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
}

# Note: setup.exe may return before the actual upgrade completes
# The system will reboot on its own

Write-Log "=== Upgrade script complete. System will reboot to finish. ==="

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "After the upgrade completes:" -ForegroundColor Green
Write-Host "  1. Wait for Windows 11 to fully boot" -ForegroundColor White
Write-Host "  2. Log in as Administrator" -ForegroundColor White
Write-Host "  3. Run: .\1-Install-All.ps1" -ForegroundColor White
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

pause
