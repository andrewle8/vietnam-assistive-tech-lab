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

# Extract the cab from the system
Write-Host "`nSearching for language pack .cab file..." -ForegroundColor Yellow

$found = $false

# Method 1: Search DISM packages (match both "LanguagePack" and "Language-Pack")
Write-Host "  Checking DISM packages..." -ForegroundColor DarkGray
$packageName = $null
$dismOutput = & DISM /Online /Get-Packages 2>&1
foreach ($line in $dismOutput) {
    if ($line -match "(Microsoft-Windows-Client-Language.*Pack.*Package.*vi-VN.*)") {
        $packageName = $matches[1].Trim()
        break
    }
}

if ($packageName) {
    Write-Host "  Found DISM package: $packageName" -ForegroundColor DarkGray
}

# Method 2: Search common cache locations for vi-VN cab files
$searchPaths = @(
    @{ Path = "C:\Windows\SoftwareDistribution\Download"; Filter = "*vi*vn*"; Recurse = $true },
    @{ Path = "C:\Windows\servicing\Packages"; Filter = "*Language*vi-VN*"; Recurse = $false },
    @{ Path = "C:\Windows\Temp"; Filter = "*vi*vn*"; Recurse = $true }
)

foreach ($search in $searchPaths) {
    if ($found) { break }
    if (-not (Test-Path $search.Path)) { continue }

    Write-Host "  Searching $($search.Path)..." -ForegroundColor DarkGray
    $cabs = Get-ChildItem -Path $search.Path -Filter $search.Filter -Recurse:$search.Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".cab" -and $_.Length -gt 10MB }

    if ($cabs) {
        $sourceCab = ($cabs | Sort-Object Length -Descending | Select-Object -First 1).FullName
        Write-Host "  Found: $sourceCab" -ForegroundColor DarkGray
        Copy-Item -Path $sourceCab -Destination $cabFile -Force
        $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
        Write-Host "`n[OK] Language pack saved ($sizeMB MB):" -ForegroundColor Green
        Write-Host "     $cabFile" -ForegroundColor Cyan
        $found = $true
    }
}

# Method 3: Broad search — any large cab in SoftwareDistribution (some builds don't include vi-vn in filename)
if (-not $found -and (Test-Path "C:\Windows\SoftwareDistribution\Download")) {
    Write-Host "  Broad search in SoftwareDistribution..." -ForegroundColor DarkGray
    $allCabs = Get-ChildItem -Path "C:\Windows\SoftwareDistribution\Download" -Recurse -Filter "*.cab" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 30MB -and $_.Length -lt 500MB } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5

    foreach ($cab in $allCabs) {
        # Check if the cab contains vi-VN content using DISM
        $checkOutput = & DISM /Online /Get-PackageInfo /PackagePath:"$($cab.FullName)" 2>&1 | Out-String
        if ($checkOutput -match "vi-VN") {
            Write-Host "  Found vi-VN cab: $($cab.FullName)" -ForegroundColor DarkGray
            Copy-Item -Path $cab.FullName -Destination $cabFile -Force
            $sizeMB = [math]::Round((Get-Item $cabFile).Length / 1MB, 1)
            Write-Host "`n[OK] Language pack saved ($sizeMB MB):" -ForegroundColor Green
            Write-Host "     $cabFile" -ForegroundColor Cyan
            $found = $true
            break
        }
    }
}

if (-not $found) {
    # Clean up empty directory
    if ((Test-Path $DestinationDir) -and (Get-ChildItem $DestinationDir | Measure-Object).Count -eq 0) {
        Remove-Item -Path $DestinationDir -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`n[INFO] Could not extract the .cab file from this system." -ForegroundColor Yellow
    Write-Host "" -ForegroundColor White
    Write-Host "This is normal on Windows 11 24H2 — language packs are installed as" -ForegroundColor White
    Write-Host "Features on Demand and don't leave extractable .cab files." -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "This is OK! Configure-Laptop.ps1 will install the language pack" -ForegroundColor Green
    Write-Host "on each laptop using Install-Language (requires internet)." -ForegroundColor Green
    Write-Host "" -ForegroundColor White
    Write-Host "Since Bootstrap-Laptop.ps1 sets up Wi-Fi before running" -ForegroundColor White
    Write-Host "Configure-Laptop.ps1, each laptop will have internet access." -ForegroundColor White
}

pause
