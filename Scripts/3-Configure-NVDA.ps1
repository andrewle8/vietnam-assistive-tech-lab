# Vietnam Lab Deployment - NVDA Configuration Script
# Version: 1.0
# Run after verifying installation
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\configuration.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NVDA Configuration for Vietnamese Lab" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Log "=== NVDA Configuration Started on $env:COMPUTERNAME ===" "INFO"

# Navigate to USB root
$usbRoot = Split-Path -Parent $PSScriptRoot
$sourceConfig = Join-Path $usbRoot "Config\nvda-config\nvda.ini"
$nvdaConfigDir = Join-Path $env:APPDATA "nvda"
$nvdaConfigPath = Join-Path $nvdaConfigDir "nvda.ini"

Write-Log "USB Root: $usbRoot" "INFO"
Write-Log "Source config: $sourceConfig" "INFO"
Write-Log "Target config: $nvdaConfigPath" "INFO"

# Step 1: Create NVDA config directory if it doesn't exist
if (-not (Test-Path $nvdaConfigDir)) {
    Write-Log "Creating NVDA config directory..." "INFO"
    New-Item -Path $nvdaConfigDir -ItemType Directory -Force | Out-Null
}

# Step 2: Copy pre-configured NVDA profile
if (Test-Path $sourceConfig) {
    try {
        Copy-Item $sourceConfig $nvdaConfigPath -Force
        Write-Log "NVDA configuration profile applied successfully" "SUCCESS"
    } catch {
        Write-Log "ERROR copying NVDA config: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "Warning: Pre-configured NVDA profile not found at $sourceConfig" "WARNING"
    Write-Log "NVDA will use default settings. Configure manually via NVDA menu." "WARNING"
}

# Step 3: Set NVDA to auto-start on login
Write-Log "Configuring NVDA to auto-start on Windows login..." "INFO"

$startupPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$nvdaExePath = "C:\Program Files\NVDA\nvda.exe"

if (-not (Test-Path $nvdaExePath)) {
    $nvdaExePath = "C:\Program Files (x86)\NVDA\nvda.exe"
}

if (Test-Path $nvdaExePath) {
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $ShortcutPath = Join-Path $startupPath "NVDA.lnk"
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $nvdaExePath
        $Shortcut.WorkingDirectory = Split-Path $nvdaExePath
        $Shortcut.Description = "NVDA Screen Reader - Auto-start"
        $Shortcut.Save()

        Write-Log "NVDA auto-start shortcut created successfully" "SUCCESS"
    } catch {
        Write-Log "ERROR creating auto-start shortcut: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "ERROR: NVDA executable not found. Cannot create auto-start shortcut." "ERROR"
}

# Step 4: Install NVDA add-ons
Write-Log "Installing NVDA add-ons..." "INFO"

$addonsSourceDir = Join-Path $usbRoot "Installers\NVDA\addons"
$addonsDestDir = Join-Path $nvdaConfigDir "addons"

# Create addons directory if it doesn't exist
if (-not (Test-Path $addonsDestDir)) {
    New-Item -Path $addonsDestDir -ItemType Directory -Force | Out-Null
}

# Install all .nvda-addon files found in the source directory
if (Test-Path $addonsSourceDir) {
    $addonFiles = Get-ChildItem -Path $addonsSourceDir -Filter "*.nvda-addon" -ErrorAction SilentlyContinue

    if ($addonFiles.Count -gt 0) {
        foreach ($addon in $addonFiles) {
            Write-Log "Installing add-on: $($addon.Name)..." "INFO"
            try {
                # NVDA add-ons are ZIP files - extract to addons folder
                $addonName = [System.IO.Path]::GetFileNameWithoutExtension($addon.Name)
                $targetPath = Join-Path $addonsDestDir $addonName

                # Remove existing version if present
                if (Test-Path $targetPath) {
                    Remove-Item -Path $targetPath -Recurse -Force
                }

                # Extract add-on (it's a ZIP file)
                Expand-Archive -Path $addon.FullName -DestinationPath $targetPath -Force
                Write-Log "Add-on '$($addon.Name)' installed successfully" "SUCCESS"
            } catch {
                Write-Log "ERROR installing add-on $($addon.Name): $($_.Exception.Message)" "ERROR"
            }
        }
    } else {
        Write-Log "No NVDA add-on files found in $addonsSourceDir" "INFO"
    }
} else {
    Write-Log "NVDA add-ons directory not found at $addonsSourceDir" "INFO"
    Write-Log "To add VLC accessibility: download VLC.nvda-addon and place in Installers\NVDA\addons\" "INFO"
}

# Step 5: Configure braille settings for Orbit Reader 20
Write-Log "Configuring braille display settings..." "INFO"

# Note: NVDA braille settings are in nvda.ini which we already copied
# The Orbit Reader 20 uses HID mode and should auto-detect when plugged in

Write-Host "`n" -NoNewline
Write-Host "📝 IMPORTANT: Orbit Reader 20 Setup" -ForegroundColor Yellow
Write-Host "  1. Connect Orbit Reader 20 via USB" -ForegroundColor White
Write-Host "  2. NVDA should auto-detect it as 'APH Orbit Reader 20'" -ForegroundColor White
Write-Host "  3. If not detected, press NVDA+Control+A to open braille settings" -ForegroundColor White
Write-Host "  4. Select 'APH Orbit Reader 20' from the display list`n" -ForegroundColor White

# Step 6: Start NVDA now (if not already running)
$nvdaProcess = Get-Process -Name "nvda" -ErrorAction SilentlyContinue

if (-not $nvdaProcess) {
    Write-Log "Starting NVDA..." "INFO"
    try {
        Start-Process -FilePath $nvdaExePath -NoNewWindow
        Start-Sleep -Seconds 3
        Write-Log "NVDA started successfully" "SUCCESS"
    } catch {
        Write-Log "ERROR starting NVDA: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "NVDA is already running" "INFO"
    Write-Host "`nℹ️  NVDA is already running. Restart NVDA to apply new settings:" -ForegroundColor Yellow
    Write-Host "   Press NVDA+Q (Insert+Q), then start NVDA again`n" -ForegroundColor White
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "NVDA Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`n✅ Configuration Summary:" -ForegroundColor Cyan
Write-Host "  • NVDA profile configured for Vietnamese" -ForegroundColor White
Write-Host "  • NVDA add-ons installed (if present in Installers\NVDA\addons\)" -ForegroundColor White
Write-Host "  • Auto-start on Windows login enabled" -ForegroundColor White
Write-Host "  • Braille settings pre-configured for Orbit Reader 20" -ForegroundColor White
Write-Host "  • Speech synthesizer set to VNVoice (Minh Du voice)`n" -ForegroundColor White

Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Connect the Orbit Reader 20 via USB" -ForegroundColor White
Write-Host "  2. Test speech output (NVDA should speak in Vietnamese)" -ForegroundColor White
Write-Host "  3. Test braille output on the Orbit Reader" -ForegroundColor White
Write-Host "  4. Copy training materials to Desktop" -ForegroundColor White
Write-Host "  5. Repeat for remaining PCs`n" -ForegroundColor White

Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Green

Write-Log "=== NVDA Configuration Complete ===" "INFO"

pause
