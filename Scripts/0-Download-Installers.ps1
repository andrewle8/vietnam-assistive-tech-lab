# Vietnam Lab Deployment - Automated Installer Downloader
# Version: 1.0
# Downloads all required software installers
# Last Updated: February 2026

param(
    [string]$DestinationRoot = "..\Installers"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Installer Downloader" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create destination directories
$paths = @{
    NVDA = Join-Path $DestinationRoot "NVDA"
    NVDAAddons = Join-Path $DestinationRoot "NVDA\addons"
    SaoMai = Join-Path $DestinationRoot "SaoMai"
    LibreOffice = Join-Path $DestinationRoot "LibreOffice"
    Firefox = Join-Path $DestinationRoot "Firefox"
    Utilities = Join-Path $DestinationRoot "Utilities"
    Educational = Join-Path $DestinationRoot "Educational"
}

foreach ($path in $paths.Values) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

# Download list with URLs and destinations
$downloads = @(
    @{
        Name = "NVDA 2025.3.2"
        Url = "https://www.nvaccess.org/files/nvda/releases/2025.3.2/nvda_2025.3.2.exe"
        Destination = Join-Path $paths.NVDA "nvda_2025.3.2.exe"
        Size = "50 MB"
        Note = "If this exact version doesn't exist, get the latest stable from nvaccess.org/download"
    },
    @{
        Name = "LibreOffice 24.8 (64-bit MSI)"
        Url = "https://download.documentfoundation.org/libreoffice/stable/24.8.4/win/x86_64/LibreOffice_24.8.4_Win_x86-64.msi"
        Destination = Join-Path $paths.LibreOffice "LibreOffice_24.8_Win_x86-64.msi"
        Size = "300 MB"
        Note = "Check libreoffice.org for latest 24.8.x version"
    },
    @{
        Name = "Firefox ESR 128"
        Url = "https://download.mozilla.org/?product=firefox-esr-latest-ssl&os=win64&lang=en-US"
        Destination = Join-Path $paths.Firefox "Firefox_ESR_128_Setup.exe"
        Size = "60 MB"
        Note = "Gets latest ESR version"
    },
    @{
        Name = "VLC Media Player 3.0"
        Url = "https://get.videolan.org/vlc/last/win64/vlc-3.0.21-win64.exe"
        Destination = Join-Path $paths.Utilities "VLC-3.0.x.exe"
        Size = "40 MB"
        Note = "Check videolan.org for latest 3.0.x version"
    }
    # Note: 7-Zip removed - Windows 11 has built-in support for ZIP, 7z, RAR, TAR, etc.
)

$successCount = 0
$failCount = 0
$skippedCount = 0

foreach ($item in $downloads) {
    Write-Host "`n[$($downloads.IndexOf($item) + 1)/$($downloads.Count)] $($item.Name)" -ForegroundColor Yellow
    Write-Host "Size: $($item.Size)" -ForegroundColor DarkGray

    # Check if file already exists
    if (Test-Path $item.Destination) {
        Write-Host "[SKIP] File already exists: $($item.Destination)" -ForegroundColor DarkYellow
        $skippedCount++
        continue
    }

    try {
        Write-Host "Downloading from: $($item.Url)" -ForegroundColor Cyan
        Write-Host "Saving to: $($item.Destination)" -ForegroundColor Cyan

        # Download with progress bar
        $ProgressPreference = 'SilentlyContinue'  # Faster download
        Invoke-WebRequest -Uri $item.Url -OutFile $item.Destination -UseBasicParsing
        $ProgressPreference = 'Continue'

        if (Test-Path $item.Destination) {
            $fileSize = (Get-Item $item.Destination).Length / 1MB
            Write-Host "[OK] Downloaded successfully ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Green
            $successCount++
        } else {
            throw "Download completed but file not found"
        }

    } catch {
        Write-Host "[FAIL] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Note: $($item.Note)" -ForegroundColor Yellow
        $failCount++
    }
}

# Manual downloads required (no direct download links)
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "MANUAL DOWNLOADS REQUIRED" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

Write-Host "`nThe following software must be downloaded manually:`n" -ForegroundColor Yellow

Write-Host "1. Sao Mai VNVoice (Vietnamese TTS)" -ForegroundColor Cyan
Write-Host "   URL: https://saomaicenter.org/en/downloads" -ForegroundColor White
Write-Host "   Save to: $($paths.SaoMai)\SaoMai_VNVoice_1.0.exe`n" -ForegroundColor DarkGray

Write-Host "2. Sao Mai Typing Tutor" -ForegroundColor Cyan
Write-Host "   URL: https://saomaicenter.org/en/downloads/vietnamese-talking-software/sao-mai-typing-tutor-smtt" -ForegroundColor White
Write-Host "   Save to: $($paths.SaoMai)\SaoMai_TypingTutor.exe`n" -ForegroundColor DarkGray

Write-Host "3. VLC NVDA Add-on (for VLC accessibility)" -ForegroundColor Cyan
Write-Host "   URL: https://addons.nvda-project.org/ (search for 'VLC')" -ForegroundColor White
Write-Host "   Save to: $($paths.NVDAAddons)\VLC.nvda-addon`n" -ForegroundColor DarkGray

Write-Host "4. LEAP Games (Educational audio games for blind children)" -ForegroundColor Cyan
Write-Host "   URL: https://www.gamesfortheblind.org/" -ForegroundColor White
Write-Host "   Download: Windows 64-bit versions of Tic-Tac-Toe, Tennis, and Curve" -ForegroundColor White
Write-Host "   Save to: $($paths.Educational)\`n" -ForegroundColor DarkGray

Write-Host "These require navigating their websites to find the download links." -ForegroundColor Yellow

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Download Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow
Write-Host "Manual: 4 (Sao Mai software + VLC NVDA add-on + LEAP Games)" -ForegroundColor Yellow

if ($failCount -gt 0) {
    Write-Host "`n⚠️  Some downloads failed. This may be due to:" -ForegroundColor Yellow
    Write-Host "  - Changed URLs (software versions updated)" -ForegroundColor White
    Write-Host "  - Network connectivity issues" -ForegroundColor White
    Write-Host "  - Firewall/antivirus blocking downloads" -ForegroundColor White
    Write-Host "`nPlease download failed items manually from the URLs above." -ForegroundColor Yellow
}

Write-Host "`n✅ Automated downloads complete!" -ForegroundColor Green
Write-Host "Don't forget to manually download the 3 items listed above." -ForegroundColor Yellow
Write-Host "`nNext: Run .\1-Install-All.ps1 on a test PC" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

pause
