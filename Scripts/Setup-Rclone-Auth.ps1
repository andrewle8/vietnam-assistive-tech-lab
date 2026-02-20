# Vietnam Lab - Rclone Google Drive Authorization
# Version: 1.0
# One-time interactive script to authorize rclone with the lab Google account.
# Run once on any PC with internet before deploying to laptops.
# Last Updated: February 2026

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Google Drive Authorization" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

$usbRoot = Split-Path -Parent $PSScriptRoot
$rcloneExe = Join-Path $usbRoot "Installers\Utilities\rclone\rclone.exe"
$configDir = Join-Path $usbRoot "Config\rclone"
$configFile = Join-Path $configDir "rclone.conf"

# Check rclone exists
if (-not (Test-Path $rcloneExe)) {
    Write-Host "[ERROR] rclone.exe not found at:" -ForegroundColor Red
    Write-Host "  $rcloneExe" -ForegroundColor White
    Write-Host ""
    Write-Host "Run 0-Download-Installers.ps1 first to download rclone." -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "This will open a browser window to authorize Google Drive access." -ForegroundColor Yellow
Write-Host "Sign in with the lab's Google account." -ForegroundColor Yellow
Write-Host ""

# Create config directory if needed
if (-not (Test-Path $configDir)) {
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
}

# Create a minimal rclone config with the remote name
$tempConfig = Join-Path $env:TEMP "rclone-setup.conf"

Write-Host "Starting rclone configuration..." -ForegroundColor Cyan
Write-Host "When prompted:" -ForegroundColor Yellow
Write-Host "  1. Choose 'n' for new remote" -ForegroundColor White
Write-Host "  2. Name it: gdrive" -ForegroundColor White
Write-Host "  3. Choose 'drive' (Google Drive)" -ForegroundColor White
Write-Host "  4. Leave client_id and client_secret blank (press Enter)" -ForegroundColor White
Write-Host "  5. Choose scope '1' (full access)" -ForegroundColor White
Write-Host "  6. Leave root_folder_id blank" -ForegroundColor White
Write-Host "  7. Leave service_account_file blank" -ForegroundColor White
Write-Host "  8. Choose 'y' for auto config" -ForegroundColor White
Write-Host "  9. A browser will open - sign in with the lab Google account" -ForegroundColor White
Write-Host " 10. Choose 'n' for team drive" -ForegroundColor White
Write-Host " 11. Confirm with 'y', then 'q' to quit" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to begin"

# Run rclone config interactively
& $rcloneExe config --config $configFile

Write-Host ""

if (Test-Path $configFile) {
    $configContent = Get-Content $configFile -Raw
    if ($configContent -match '\[gdrive\]') {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Authorization Successful!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Config saved to: $configFile" -ForegroundColor White
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Run Configure-Laptop.ps1 on each lab laptop" -ForegroundColor White
        Write-Host "     (this deploys rclone and the config to each PC)" -ForegroundColor White
        Write-Host ""
        Write-Host "IMPORTANT: Do NOT commit rclone.conf to git." -ForegroundColor Red
        Write-Host "It contains OAuth tokens for the lab Google account." -ForegroundColor Red
    } else {
        Write-Host "[WARNING] Config file exists but 'gdrive' remote not found." -ForegroundColor Yellow
        Write-Host "Make sure you named the remote 'gdrive' during setup." -ForegroundColor Yellow
        Write-Host "You can re-run this script to try again." -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARNING] No config file was created." -ForegroundColor Yellow
    Write-Host "The authorization may not have completed. Try again." -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

pause
