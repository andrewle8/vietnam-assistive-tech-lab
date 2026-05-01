# Fix-Readmate-Web.ps1
# USB-walkup field patch for already-deployed laptops. Installs readmate-web
# (the NVDA-accessible EPUB reader) on a laptop that was deployed before
# this step existed in Configure-Laptop.ps1.
#
# After this runs, a tiny Python server bundled with SM Readmate's library
# serves the books over http://localhost:21810/. The Student desktop "Đọc
# Sách" shortcut opens Firefox at that URL where NVDA browse mode reads
# foliate-js' rendered pages natively. The native SM Readmate app stays
# installed and untouched - this is a parallel, NVDA-friendly entry point.
#
# Mirrors the kiwix-serve / SilverDict architecture: hidden VBS launcher,
# Scheduled Task at Student logon, RestartCount=3. The Python interpreter
# is reused from the SilverDict bundle (C:\Program Files\SilverDict\env\
# python.exe) so we don't ship a second 80 MB CPython.
#
# Run from elevated PowerShell:
#   & "<USB>:\Scripts\patches\Fix-Readmate-Web.ps1"
#
# Self-elevates if not already Administrator. All real work happens in
# Scripts\Install-Readmate-Web.ps1, which is shared with the Configure-
# Laptop Step 35d path - this is just the wrapper that resolves the USB
# root and invokes it. Idempotent. Exits 0 on success, 1 on any failure.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# --- Self-elevation --------------------------------------------------------

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Fix-Readmate-Web: not elevated. Relaunching as Administrator..." -ForegroundColor Yellow
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    )
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "Elevation cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# --- Resolve USB root ------------------------------------------------------

# This script lives at <usb>\Scripts\patches\Fix-Readmate-Web.ps1, so the
# USB root is two levels up. Resolve-Path normalizes the .. away cleanly.
$usbRoot       = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installScript = Join-Path $usbRoot 'Scripts\Install-Readmate-Web.ps1'

Write-Host "Fix-Readmate-Web: usb root        = $usbRoot"
Write-Host "Fix-Readmate-Web: install script  = $installScript"

if (-not (Test-Path $installScript)) {
    Write-Host "Fix-Readmate-Web: Install-Readmate-Web.ps1 not found at $installScript - cannot continue." -ForegroundColor Red
    Write-Host "Make sure you are running from a fully-synced DEPLOY_ USB." -ForegroundColor Red
    exit 1
}

# Hand off to the shared installer. It prints its own per-stage summary
# and exit code; we just propagate.
& $installScript -FromUSB $usbRoot
exit $LASTEXITCODE
