# Install-Dell-DCC.ps1 - Standalone Dell Command | Configure installer.
#
# Use case: rolling out today's BIOS settings to laptops that already had the
# rest of the stack installed by an earlier 1-Install-All.ps1 run. cctk.exe is
# the only new dependency Configure-Laptop.ps1's BIOS step (Step 38) needs;
# re-running the full Install-All would reinstall NVDA/Firefox/etc. for nothing.
#
# Workflow on each existing deployed laptop:
#   1. Plug in DEPLOY_ USB
#   2. Run this script (admin)         <-- installs cctk.exe (~2 min)
#   3. Run Configure-Laptop.ps1 (admin) <-- applies all today's config + BIOS
#   4. Reboot
#
# Idempotent: if cctk.exe is already present, exits cleanly without re-running
# the installer.

[CmdletBinding()]
param(
    [string]$LogPath = "$PSScriptRoot\install-dell-dcc.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default   { "Cyan" }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

# Admin check (DCC installer needs HKLM + Program Files write).
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "Must be run as Administrator." "ERROR"
    pause
    exit 1
}

Write-Log "=== Dell Command | Configure standalone installer ===" "INFO"

# Dell hardware check. cctk only works on Dell systems; on non-Dell hardware
# the install succeeds but cctk -o returns "system is not supported".
try {
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    Write-Log "System manufacturer: $manufacturer" "INFO"
    if ($manufacturer -notmatch 'Dell') {
        Write-Log "Non-Dell hardware detected - DCC will install but cctk won't apply BIOS settings here." "WARNING"
    }
} catch {
    Write-Log "Could not read manufacturer: $($_.Exception.Message)" "WARNING"
}

# Already installed? cctk lives at one of three known paths.
$cctkCandidates = @(
    "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files (x86)\Dell\Command Configure\X86\cctk.exe"
)
$existing = $cctkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($existing) {
    Write-Log "cctk already installed at: $existing - nothing to do." "SUCCESS"
    Write-Host ""
    Write-Host "Next step: run Configure-Laptop.ps1 (admin), then reboot." -ForegroundColor Cyan
    exit 0
}

# Locate the installer. Script lives at <USB>:\Scripts\, installer at
# <USB>:\Installers\Dell\Dell-Command-Configure-Application_F2V9N_WIN64_5.2.2.292_A00.EXE.
$usbRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $usbRoot "Installers\Dell\Dell-Command-Configure-Application_F2V9N_WIN64_5.2.2.292_A00.EXE"
if (-not (Test-Path $installer)) {
    Write-Log "DCC installer not found at: $installer" "ERROR"
    Write-Log "Expected USB layout: <USB>:\Installers\Dell\Dell-Command-Configure-Application_F2V9N_WIN64_5.2.2.292_A00.EXE" "ERROR"
    pause
    exit 1
}
Write-Log "Installer: $installer" "INFO"

# Self-extracting Dell SDP wrapper; /s runs silent. Some Dell SDP packages exit
# 0 on success, others exit 2 with a "reboot recommended" flag - both are fine
# for our purposes (we'll prompt for reboot at the end of Configure-Laptop).
Write-Log "Running installer (silent, ~60-120s)..." "INFO"
try {
    $proc = Start-Process -FilePath $installer -ArgumentList "/s" -Wait -PassThru -NoNewWindow
    Write-Log "Installer exit code: $($proc.ExitCode)" "INFO"
} catch {
    Write-Log "Installer failed to start: $($_.Exception.Message)" "ERROR"
    pause
    exit 1
}

# Verify by re-checking cctk paths. Even on a successful exit code, if cctk
# isn't where we expect it, the BIOS step won't find it.
$installed = $cctkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Log "Install reported done but cctk.exe was not found in any expected location." "ERROR"
    Write-Log "Searched: $($cctkCandidates -join '; ')" "ERROR"
    pause
    exit 1
}
Write-Log "cctk verified at: $installed" "SUCCESS"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Dell Command | Configure installed." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Run Configure-Laptop.ps1 (admin) - applies today's NVDA + BIOS changes" -ForegroundColor White
Write-Host "  2. Reboot when prompted" -ForegroundColor White
Write-Host ""
exit 0
