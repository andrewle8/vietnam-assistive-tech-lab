# Vietnam Lab Deployment - Download Vietnamese Language Pack
# Version: 1.0
# Downloads the vi-VN language pack cab for offline installation.
# Run this BEFORE deployment so Configure-Laptop.ps1 doesn't need internet.
# Last Updated: February 2026

param(
    [string]$DestinationDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "Installers\LanguagePacks")
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Vietnamese Language Pack" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

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

Write-Host "The Vietnamese language pack is needed for offline deployment." -ForegroundColor Yellow
Write-Host ""
Write-Host "Microsoft doesn't provide a direct download link for individual" -ForegroundColor White
Write-Host "language pack .cab files. You have two options:" -ForegroundColor White
Write-Host ""
Write-Host "Option 1: Download from Microsoft (RECOMMENDED)" -ForegroundColor Cyan
Write-Host "  1. On a Windows 11 PC with internet, open PowerShell as Admin" -ForegroundColor White
Write-Host "  2. Run these commands:" -ForegroundColor White
Write-Host ""
Write-Host '     Install-Language -Language "vi-VN"' -ForegroundColor Green
Write-Host ""
Write-Host "  3. After it finishes, the cab is cached at:" -ForegroundColor White
Write-Host "     C:\Windows\SoftwareDistribution\Download\" -ForegroundColor DarkGray
Write-Host "  4. Or export it with DISM:" -ForegroundColor White
Write-Host ""
Write-Host "     mkdir C:\temp\langpack" -ForegroundColor Green
Write-Host '     DISM /Online /Get-Packages | findstr "LanguagePack.*vi-VN"' -ForegroundColor Green
Write-Host ""
Write-Host "  5. Copy the .cab file to:" -ForegroundColor White
Write-Host "     $cabFile" -ForegroundColor Yellow
Write-Host ""
Write-Host "Option 2: Let Configure-Laptop.ps1 download it during setup" -ForegroundColor Cyan
Write-Host "  This works but requires internet on each laptop during config." -ForegroundColor White
Write-Host "  Not recommended for deployment in Vietnam." -ForegroundColor DarkYellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "After placing the .cab file, re-run this script to verify." -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

pause
