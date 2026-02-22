# Vietnam Lab Deployment - Download Vietnamese Language Pack
# Version: 3.0
# Downloads vi-VN language pack cabs from Microsoft's Languages & Optional Features ISO.
# Must be run on a Windows PC with internet.
# Run this BEFORE deployment so Configure-Laptop.ps1 can install offline.
# Last Updated: February 2026

param(
    [string]$DestinationDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "Installers\LanguagePacks")
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Vietnamese Language Pack" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Windows 11 24H2/25H2 Languages and Optional Features ISO (public Microsoft CDN, no login required)
# Source: https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs
$LOF_ISO_URL = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso"

# Check if already downloaded
$cabFile = Join-Path $DestinationDir "Microsoft-Windows-Client-Language-Pack_x64_vi-vn.cab"
if (Test-Path $cabFile) {
    $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
    $viFiles = (Get-ChildItem $DestinationDir -Filter "*vi-vn*" -ErrorAction SilentlyContinue).Count
    Write-Host "[OK] Language pack already downloaded ($viFiles files, main cab $sizeMB MB)" -ForegroundColor Green
    Write-Host "     $DestinationDir" -ForegroundColor DarkGray
    Write-Host ""
    Get-ChildItem $DestinationDir -Filter "*vi-vn*" | ForEach-Object {
        $sz = [math]::Round($_.Length / 1MB, 1)
        Write-Host "     $($_.Name) ($sz MB)" -ForegroundColor DarkGray
    }
    pause
    exit 0
}

# Check we're on Windows
if ($env:OS -ne "Windows_NT") {
    Write-Host "[ERROR] This script must be run on a Windows PC." -ForegroundColor Red
    pause
    exit 1
}

# Create destination directory
if (-not (Test-Path $DestinationDir)) {
    New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
}

# Download the LOF ISO
$isoPath = Join-Path $env:TEMP "Windows11-LOF.iso"

if (Test-Path $isoPath) {
    $isoSizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
    Write-Host "[OK] LOF ISO already downloaded ($isoSizeGB GB)" -ForegroundColor Green
    Write-Host "     $isoPath" -ForegroundColor DarkGray
} else {
    Write-Host "Downloading Microsoft Languages & Optional Features ISO..." -ForegroundColor Yellow
    Write-Host "This is ~5.8 GB - it may take a while." -ForegroundColor DarkGray
    Write-Host "Source: Microsoft public CDN (from Azure Virtual Desktop docs)" -ForegroundColor DarkGray
    Write-Host ""

    try {
        # Use BITS for resumable download with progress
        $bitsJob = Start-BitsTransfer -Source $LOF_ISO_URL -Destination $isoPath -DisplayName "Windows 11 Language Pack ISO" -ErrorAction Stop
        Write-Host "[OK] ISO downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "BITS transfer failed, trying curl.exe..." -ForegroundColor DarkGray
        # Fall back to curl.exe
        $curlArgs = @('-L', '--progress-bar', '-o', $isoPath, $LOF_ISO_URL)
        & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Download failed. Check internet connection and try again." -ForegroundColor Red
            if (Test-Path $isoPath) { Remove-Item $isoPath -Force }
            pause
            exit 1
        }
        Write-Host "[OK] ISO downloaded" -ForegroundColor Green
    }
}

# Mount the ISO
Write-Host "`nMounting ISO..." -ForegroundColor Yellow
try {
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Host "[OK] Mounted as ${driveLetter}:\" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Could not mount ISO: $_" -ForegroundColor Red
    Write-Host "Try double-clicking the ISO in Explorer, then re-run this script." -ForegroundColor Yellow
    pause
    exit 1
}

# Find and copy vi-VN cab files
Write-Host "`nSearching for Vietnamese (vi-VN) language files..." -ForegroundColor Yellow

$searchDir = "${driveLetter}:\LanguagesAndOptionalFeatures"
if (-not (Test-Path $searchDir)) {
    # Some ISO versions have a different folder name
    $searchDir = "${driveLetter}:\"
}

$viFiles = Get-ChildItem -Path $searchDir -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "vi-vn" -and $_.Extension -eq ".cab" }

if (-not $viFiles -or $viFiles.Count -eq 0) {
    Write-Host "[ERROR] No vi-VN .cab files found in ISO." -ForegroundColor Red
    Write-Host "ISO contents at ${searchDir}:" -ForegroundColor DarkGray
    Get-ChildItem $searchDir -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    pause
    exit 1
}

Write-Host "Found $($viFiles.Count) Vietnamese language files:" -ForegroundColor Green
$totalSize = 0
foreach ($file in $viFiles) {
    $sizeMB = [math]::Round($file.Length / 1MB, 1)
    $totalSize += $file.Length
    Write-Host "  $($file.Name) ($sizeMB MB)" -ForegroundColor DarkGray
    Copy-Item -Path $file.FullName -Destination $DestinationDir -Force
}

# Unmount the ISO
Write-Host "`nUnmounting ISO..." -ForegroundColor DarkGray
Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

$totalMB = [math]::Round($totalSize / 1MB, 1)
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "[OK] Vietnamese language pack ready ($($viFiles.Count) files, $totalMB MB)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Saved to: $DestinationDir" -ForegroundColor White
Get-ChildItem $DestinationDir -Filter "*vi-vn*" | ForEach-Object {
    $sz = [math]::Round($_.Length / 1MB, 1)
    Write-Host "  $($_.Name) ($sz MB)" -ForegroundColor White
}
Write-Host ""
Write-Host "Configure-Laptop.ps1 will install these offline via DISM." -ForegroundColor White
Write-Host ""

# Offer to delete the large ISO
Write-Host "The downloaded ISO ($([math]::Round((Get-Item $isoPath).Length / 1GB, 1)) GB) is in:" -ForegroundColor Yellow
Write-Host "  $isoPath" -ForegroundColor DarkGray
$deleteISO = Read-Host "Delete the ISO to free disk space? (Y/N)"
if ($deleteISO -eq "Y" -or $deleteISO -eq "y") {
    Remove-Item $isoPath -Force
    Write-Host "[OK] ISO deleted" -ForegroundColor Green
} else {
    Write-Host "ISO kept at $isoPath (you can delete it manually later)" -ForegroundColor DarkGray
}

Write-Host ""
pause
