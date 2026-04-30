# Fix-Help.ps1
# USB-walkup patch for already-deployed laptops. Installs the help portal
# (accessible HTML user guide for blind students) on a laptop that was
# deployed before this step existed in Configure-Laptop.ps1.
#
# After this runs, C:\LabTools\help\ contains the portal HTML files
# (index.html + huong-dan.html + user-guide.html + any future docs from the
# manifest) and the Student Public Desktop has a "Hướng Dẫn" shortcut that
# opens Firefox at file:///C:/LabTools/help/index.html. NVDA browse mode
# works natively on local HTML in Firefox - we don't need a server like
# kiwix/SilverDict because the help is static.
#
# Mirrors Configure-Laptop.ps1 Step 35c. Idempotent - safe to re-run.
# All real work happens in Scripts\Deploy-Help.ps1; this is just the wrapper
# that invokes it with -FromUSB and a USB-rooted source path.
#
# Run from elevated PowerShell:
#   & "<USB>:\Scripts\patches\Fix-Help.ps1"
#
# Exits 0 on success, 1 if Deploy-Help reports any stage failure.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# Resolve USB root from this script's location: <usb>\Scripts\patches\Fix-Help.ps1
# So: <usb> = $PSScriptRoot\..\..
$usbRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$deployScript = Join-Path $usbRoot 'Scripts\Deploy-Help.ps1'

Write-Host "Fix-Help: usb root = $usbRoot"
Write-Host "Fix-Help: deploy script = $deployScript"

if (-not (Test-Path $deployScript)) {
    Write-Host "Fix-Help: Deploy-Help.ps1 not found at $deployScript - cannot continue." -ForegroundColor Red
    Write-Host "Make sure you are running from a fully-synced DEPLOY_ USB." -ForegroundColor Red
    exit 1
}

# Hand off to the shared deploy logic. Deploy-Help.ps1 prints its own per-stage
# summary and exit code; we just propagate.
& $deployScript -FromUSB $usbRoot
exit $LASTEXITCODE
