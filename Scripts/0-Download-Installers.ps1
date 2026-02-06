# Vietnam Lab Deployment - Automated Installer Downloader
# Version: 2.0
# Downloads all required software from GitHub Releases
# Last Updated: February 2026

param(
    [string]$DestinationRoot = "..\Installers"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Installer Downloader" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# GitHub Releases base URL
$releaseBase = "https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/download/installers-v1"

# Create destination directories
$paths = @{
    NVDA       = Join-Path $DestinationRoot "NVDA"
    NVDAAddons = Join-Path $DestinationRoot "NVDA\addons"
    SaoMai     = Join-Path $DestinationRoot "SaoMai"
    LibreOffice = Join-Path $DestinationRoot "LibreOffice"
    Firefox    = Join-Path $DestinationRoot "Firefox"
    Utilities  = Join-Path $DestinationRoot "Utilities"
    Rclone     = Join-Path $DestinationRoot "Utilities\rclone"
    Educational = Join-Path $DestinationRoot "Educational"
}

foreach ($path in $paths.Values) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

# Download list - all from GitHub Releases
$downloads = @(
    @{
        Name        = "NVDA 2025.3.2"
        Filename    = "nvda_2025.3.2.exe"
        Destination = Join-Path $paths.NVDA "nvda_2025.3.2.exe"
    },
    @{
        Name        = "VLC NVDA Add-on"
        Filename    = "VLC-2025.1.0.nvda-addon"
        Destination = Join-Path $paths.NVDAAddons "VLC-2025.1.0.nvda-addon"
    },
    @{
        Name        = "Access8Math NVDA Add-on"
        Filename    = "access8math-4.3.nvda-addon"
        Destination = Join-Path $paths.NVDAAddons "access8math-4.3.nvda-addon"
    },
    @{
        Name        = "Sao Mai VNVoice"
        Filename    = "SaoMai_voice1.0.exe"
        Destination = Join-Path $paths.SaoMai "SaoMai_voice1.0.exe"
    },
    @{
        Name        = "Sao Mai Typing Tutor"
        Filename    = "SMTTSetup.exe"
        Destination = Join-Path $paths.SaoMai "SMTTSetup.exe"
    },
    @{
        Name        = "LibreOffice 26.2.0"
        Filename    = "LibreOffice_26.2.0_Win_x86-64.msi"
        Destination = Join-Path $paths.LibreOffice "LibreOffice_26.2.0_Win_x86-64.msi"
    },
    @{
        Name        = "Firefox 147.0.3"
        Filename    = "Firefox.Setup.147.0.3.msi"
        Destination = Join-Path $paths.Firefox "Firefox Setup 147.0.3.msi"
    },
    @{
        Name        = "VLC Media Player 3.0.23"
        Filename    = "vlc-3.0.23-win64.exe"
        Destination = Join-Path $paths.Utilities "vlc-3.0.23-win64.exe"
    }
)

# LEAP game zips - download, extract, delete
$leapDownloads = @(
    @{
        Name        = "LEAP Tic-Tac-Toe"
        Filename    = "tictactoe-win64_build-1.1b.zip"
        ExtractTo   = Join-Path $paths.Educational "TicTacToe"
    },
    @{
        Name        = "LEAP Tennis"
        Filename    = "tennis_win64_built-0.9b.zip"
        ExtractTo   = Join-Path $paths.Educational "Tennis"
    },
    @{
        Name        = "LEAP Curve"
        Filename    = "curve_eng_win64.zip"
        ExtractTo   = Join-Path $paths.Educational "Curve"
    }
)

$successCount = 0
$failCount = 0
$skippedCount = 0
$totalItems = $downloads.Count + $leapDownloads.Count + 1  # +1 for rclone

# Download direct installer files
foreach ($item in $downloads) {
    $index = $downloads.IndexOf($item) + 1
    Write-Host "`n[$index/$totalItems] $($item.Name)" -ForegroundColor Yellow

    if (Test-Path $item.Destination) {
        Write-Host "[SKIP] File already exists: $($item.Destination)" -ForegroundColor DarkYellow
        $skippedCount++
        continue
    }

    $url = "$releaseBase/$($item.Filename)"
    try {
        Write-Host "Downloading: $($item.Filename)" -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $item.Destination -UseBasicParsing
        $ProgressPreference = 'Continue'

        $fileSize = (Get-Item $item.Destination).Length / 1MB
        Write-Host "[OK] Downloaded ($([math]::Round($fileSize, 1)) MB)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Download and extract LEAP game zips
foreach ($item in $leapDownloads) {
    $index = $downloads.Count + $leapDownloads.IndexOf($item) + 1
    Write-Host "`n[$index/$totalItems] $($item.Name)" -ForegroundColor Yellow

    if (Test-Path $item.ExtractTo) {
        $hasExe = Get-ChildItem -Path $item.ExtractTo -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($hasExe) {
            Write-Host "[SKIP] Already extracted: $($item.ExtractTo)" -ForegroundColor DarkYellow
            $skippedCount++
            continue
        }
    }

    $url = "$releaseBase/$($item.Filename)"
    $zipPath = Join-Path $paths.Educational $item.Filename
    try {
        Write-Host "Downloading: $($item.Filename)" -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        $ProgressPreference = 'Continue'

        Write-Host "Extracting to $($item.ExtractTo)..." -ForegroundColor Cyan
        if (-not (Test-Path $item.ExtractTo)) {
            New-Item -Path $item.ExtractTo -ItemType Directory -Force | Out-Null
        }
        Expand-Archive -Path $zipPath -DestinationPath $item.ExtractTo -Force
        Remove-Item -Path $zipPath -Force
        Write-Host "[OK] Downloaded and extracted" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue }
        $failCount++
    }
}

# Download rclone (portable zip from GitHub)
$rcloneIndex = $downloads.Count + $leapDownloads.Count + 1
Write-Host "`n[$rcloneIndex/$totalItems] Rclone (Google Drive sync tool)" -ForegroundColor Yellow

$rcloneExeDest = Join-Path $paths.Rclone "rclone.exe"
if (Test-Path $rcloneExeDest) {
    Write-Host "[SKIP] Already exists: $rcloneExeDest" -ForegroundColor DarkYellow
    $skippedCount++
} else {
    $rcloneVersion = "v1.68.2"
    $rcloneZipName = "rclone-$rcloneVersion-windows-amd64.zip"
    $rcloneUrl = "https://github.com/rclone/rclone/releases/download/$rcloneVersion/$rcloneZipName"
    $rcloneZipPath = Join-Path $paths.Rclone $rcloneZipName
    $rcloneTempDir = Join-Path $paths.Rclone "temp-extract"

    try {
        Write-Host "Downloading: $rcloneZipName" -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $rcloneUrl -OutFile $rcloneZipPath -UseBasicParsing
        $ProgressPreference = 'Continue'

        Write-Host "Extracting rclone.exe..." -ForegroundColor Cyan
        Expand-Archive -Path $rcloneZipPath -DestinationPath $rcloneTempDir -Force

        # rclone zip contains a subfolder like rclone-v1.68.2-windows-amd64/rclone.exe
        $extractedExe = Get-ChildItem -Path $rcloneTempDir -Filter "rclone.exe" -Recurse | Select-Object -First 1
        if ($extractedExe) {
            Copy-Item -Path $extractedExe.FullName -Destination $rcloneExeDest -Force
            Write-Host "[OK] Extracted rclone.exe" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "[FAIL] rclone.exe not found in archive" -ForegroundColor Red
            $failCount++
        }

        # Clean up
        Remove-Item -Path $rcloneZipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $rcloneTempDir -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $rcloneZipPath) { Remove-Item -Path $rcloneZipPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $rcloneTempDir) { Remove-Item -Path $rcloneTempDir -Recurse -Force -ErrorAction SilentlyContinue }
        $failCount++
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Download Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow

if ($failCount -gt 0) {
    Write-Host "`nSome downloads failed. Check your internet connection and try again." -ForegroundColor Yellow
    Write-Host "All files are hosted at:" -ForegroundColor White
    Write-Host "  $releaseBase" -ForegroundColor Cyan
}

Write-Host "`nAll downloads complete!" -ForegroundColor Green
Write-Host "Next: Run .\1-Install-All.ps1 on a test PC" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

pause
