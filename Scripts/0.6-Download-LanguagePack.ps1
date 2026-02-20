# Vietnam Lab Deployment - Download Vietnamese Language Pack
# Version: 2.0
# Downloads the vi-VN language pack cab for offline installation.
# Must be run on a Windows 11 PC with internet.
# Run this BEFORE deployment so Configure-Laptop.ps1 doesn't need internet.
# Last Updated: February 2026

param(
    [string]$DestinationDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "Installers\LanguagePacks")
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Vietnamese Language Pack" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

$cabFile = Join-Path $DestinationDir "Microsoft-Windows-Client-Language-Pack_x64_vi-vn.cab"

# Check if already downloaded
if (Test-Path $cabFile) {
    $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
    Write-Host "[OK] Language pack already downloaded ($sizeMB MB)" -ForegroundColor Green
    Write-Host "     $cabFile" -ForegroundColor DarkGray
    pause
    exit 0
}

# Create destination directory
if (-not (Test-Path $DestinationDir)) {
    New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
}

# Check we're on Windows
if ($env:OS -ne "Windows_NT") {
    Write-Host "[ERROR] This script must be run on a Windows 11 PC." -ForegroundColor Red
    Write-Host "        It downloads the Vietnamese language pack for offline use." -ForegroundColor Yellow
    pause
    exit 1
}

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "        Right-click PowerShell > Run as Administrator, then try again." -ForegroundColor Yellow
    pause
    exit 1
}

# Check if Vietnamese is already installed
$viLang = Get-WinUserLanguageList | Where-Object { $_.LanguageTag -eq "vi" -or $_.LanguageTag -eq "vi-VN" }

if (-not $viLang) {
    Write-Host "Installing Vietnamese language pack (this may take several minutes)..." -ForegroundColor Yellow
    Write-Host "Downloading from Microsoft Windows Update servers..." -ForegroundColor DarkGray
    try {
        Install-Language -Language "vi-VN" -ErrorAction Stop
        Write-Host "[OK] Vietnamese language pack installed on this PC." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to install language pack: $_" -ForegroundColor Red
        Write-Host "`nMake sure this PC has internet access and Windows Update is not disabled." -ForegroundColor Yellow
        pause
        exit 1
    }
} else {
    Write-Host "[OK] Vietnamese language already installed on this PC." -ForegroundColor Green
}

# Extract the cab using DISM
Write-Host "`nExtracting language pack .cab file..." -ForegroundColor Yellow

# Find the installed vi-VN language pack
$packageName = $null
$dismOutput = & DISM /Online /Get-Packages 2>&1
foreach ($line in $dismOutput) {
    if ($line -match "(Microsoft-Windows-Client-LanguagePack-Package.*vi-VN.*)") {
        $packageName = $matches[1].Trim()
        break
    }
}

if (-not $packageName) {
    # Alternative: search for the cab in SoftwareDistribution cache
    Write-Host "Searching Windows Update cache for language pack cab..." -ForegroundColor DarkGray
    $cachedCabs = Get-ChildItem -Path "C:\Windows\SoftwareDistribution\Download" -Recurse -Filter "*vi-vn*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".cab" -and $_.Length -gt 10MB }

    if ($cachedCabs) {
        $sourceCab = ($cachedCabs | Sort-Object Length -Descending | Select-Object -First 1).FullName
        Write-Host "Found cached cab: $sourceCab" -ForegroundColor DarkGray
        Copy-Item -Path $sourceCab -Destination $cabFile -Force
        $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
        Write-Host "`n[OK] Language pack saved ($sizeMB MB):" -ForegroundColor Green
        Write-Host "     $cabFile" -ForegroundColor Cyan
        pause
        exit 0
    }

    Write-Host "[WARNING] Could not find the .cab file automatically." -ForegroundColor Yellow
    Write-Host "`nThe language pack IS installed on this PC, but the .cab could not be extracted." -ForegroundColor White
    Write-Host "This is OK -- Configure-Laptop.ps1 will use Install-Language on each laptop" -ForegroundColor White
    Write-Host "if internet is available, or you can copy the cab manually." -ForegroundColor White
    Write-Host "`nTo find it manually, run:" -ForegroundColor DarkGray
    Write-Host '  DISM /Online /Get-Packages | findstr "vi-VN"' -ForegroundColor Green
    pause
    exit 1
}

# Export using DISM
$tempDir = Join-Path $env:TEMP "langpack-export"
if (-not (Test-Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
}

Write-Host "Exporting package: $packageName" -ForegroundColor DarkGray
try {
    & DISM /Online /Get-PackageInfo /PackageName:$packageName | Out-Null

    # Try to find the cab in the component store
    $cachedCabs = Get-ChildItem -Path "C:\Windows\servicing\Packages" -Filter "*LanguagePack*vi-VN*" -ErrorAction SilentlyContinue
    if (-not $cachedCabs) {
        $cachedCabs = Get-ChildItem -Path "C:\Windows\SoftwareDistribution\Download" -Recurse -Filter "*.cab" -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 10MB }
    }

    if ($cachedCabs) {
        # Find the most likely vi-VN cab
        $sourceCab = $cachedCabs | Sort-Object Length -Descending | Select-Object -First 1
        Copy-Item -Path $sourceCab.FullName -Destination $cabFile -Force
        $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
        Write-Host "`n[OK] Language pack saved ($sizeMB MB):" -ForegroundColor Green
        Write-Host "     $cabFile" -ForegroundColor Cyan
    } else {
        Write-Host "[WARNING] Could not locate the .cab file in the system cache." -ForegroundColor Yellow
        Write-Host "The language is installed but the cab wasn't found for export." -ForegroundColor White
        Write-Host "Configure-Laptop.ps1 will download it on each laptop if internet is available." -ForegroundColor White
    }
}
catch {
    Write-Host "[WARNING] DISM export failed: $_" -ForegroundColor Yellow
    Write-Host "Configure-Laptop.ps1 will download it on each laptop if internet is available." -ForegroundColor White
}

# Cleanup
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

pause
