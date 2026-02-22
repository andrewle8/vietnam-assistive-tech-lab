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
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

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

$startupPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
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

                # Extract add-on (it's a ZIP file with .nvda-addon extension)
                # Expand-Archive only recognizes .zip — copy to temp .zip first
                $tempZip = Join-Path $env:TEMP "$addonName.zip"
                Copy-Item -Path $addon.FullName -Destination $tempZip -Force
                Expand-Archive -Path $tempZip -DestinationPath $targetPath -Force
                Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
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

# Step 5: Install UniKey (Vietnamese keyboard input)
Write-Log "Installing UniKey Vietnamese keyboard..." "INFO"

$unikeySourceDir = Join-Path $usbRoot "Installers\Utilities\UniKey"
$unikeyDestDir = "C:\Program Files\UniKey"
$publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")

if (Test-Path $unikeySourceDir) {
    try {
        if (-not (Test-Path $unikeyDestDir)) {
            New-Item -Path $unikeyDestDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$unikeySourceDir\*" -Destination $unikeyDestDir -Recurse -Force
        Write-Log "Copied UniKey to $unikeyDestDir" "SUCCESS"

        # Create startup shortcut so UniKey runs on login (All Users)
        $startupPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        $unikeyExe = Join-Path $unikeyDestDir "UniKeyNT.exe"
        if (Test-Path $unikeyExe) {
            $WshShell = New-Object -ComObject WScript.Shell
            $shortcut = $WshShell.CreateShortcut((Join-Path $startupPath "UniKey.lnk"))
            $shortcut.TargetPath = $unikeyExe
            $shortcut.WorkingDirectory = $unikeyDestDir
            $shortcut.Description = "UniKey Vietnamese Keyboard"
            $shortcut.Save()
            Write-Log "UniKey auto-start on login enabled" "SUCCESS"

            # Start UniKey now
            Start-Process -FilePath $unikeyExe -WorkingDirectory $unikeyDestDir
            Write-Log "UniKey started" "SUCCESS"
        }
    } catch {
        Write-Log "ERROR installing UniKey: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "UniKey not found at $unikeySourceDir (optional)" "INFO"
    Write-Log "Vietnamese input: use Windows Settings > Language > Add Vietnamese" "INFO"
}

# Step 6: Enable NVDA on Windows login screen (secure desktop)
Write-Log "Enabling NVDA speech on Windows login screen..." "INFO"

try {
    # Copy NVDA config to system profile so NVDA speaks at the login screen
    # This is the equivalent of NVDA > General Settings > "Use NVDA during sign-in"
    $systemNvdaConfig = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\nvda"
    if (-not (Test-Path $systemNvdaConfig)) {
        New-Item -Path $systemNvdaConfig -ItemType Directory -Force | Out-Null
    }
    if (Test-Path $nvdaConfigPath) {
        Copy-Item -Path $nvdaConfigPath -Destination (Join-Path $systemNvdaConfig "nvda.ini") -Force
        Write-Log "NVDA login screen speech enabled (config copied to system profile)" "SUCCESS"
    }

    # Set NVDA to run on secure desktops (login screen, UAC prompts)
    $nvdaRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
    # Enable the NVDA Ease of Access integration
    $easeOfAccessPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Accessibility\ATs\nvda"
    if (-not (Test-Path $easeOfAccessPath)) {
        New-Item -Path $easeOfAccessPath -Force | Out-Null
    }
    $nvdaExeResolved = if (Test-Path "C:\Program Files\NVDA\nvda.exe") { "C:\Program Files\NVDA\nvda.exe" } else { "C:\Program Files (x86)\NVDA\nvda.exe" }
    Set-ItemProperty -Path $easeOfAccessPath -Name "ATExe" -Value $nvdaExeResolved -Force
    Set-ItemProperty -Path $easeOfAccessPath -Name "StartExe" -Value $nvdaExeResolved -Force
    Set-ItemProperty -Path $easeOfAccessPath -Name "Description" -Value "NVDA Screen Reader" -Force

    Write-Log "NVDA registered as Ease of Access screen reader" "SUCCESS"
} catch {
    Write-Log "Could not configure NVDA login screen: $($_.Exception.Message)" "ERROR"
    Write-Log "Manually enable via NVDA > General Settings > Use NVDA during sign-in" "ERROR"
}

# Step 7: Start NVDA now (if not already running)
$nvdaProcess = Get-Process -Name "nvda" -ErrorAction SilentlyContinue

if (-not $nvdaProcess) {
    Write-Log "Starting NVDA..." "INFO"
    try {
        Start-Process -FilePath $nvdaExePath
        Start-Sleep -Seconds 3
        Write-Log "NVDA started successfully" "SUCCESS"
    } catch {
        Write-Log "ERROR starting NVDA: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "NVDA is already running" "INFO"
    Write-Host "`nNVDA is already running. Restart NVDA to apply new settings:" -ForegroundColor Yellow
    Write-Host "   Press NVDA+Q (Insert+Q), then start NVDA again" -ForegroundColor White
    Write-Host ""
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "NVDA Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
Write-Host "  - NVDA profile configured for Vietnamese" -ForegroundColor White
Write-Host "  - NVDA add-ons installed (if present in Installers\NVDA\addons\)" -ForegroundColor White
Write-Host "  - Auto-start on Windows login enabled" -ForegroundColor White
Write-Host "  - UniKey Vietnamese keyboard installed and auto-starting" -ForegroundColor White
Write-Host "  - Speech synthesizer set to VNVoice (Minh Du voice)" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test speech output (NVDA should speak in Vietnamese)" -ForegroundColor White
Write-Host "  2. Copy training materials to Desktop" -ForegroundColor White
Write-Host "  3. Repeat for remaining PCs" -ForegroundColor White
Write-Host ""

Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

Write-Log "=== NVDA Configuration Complete ===" "INFO"

if (-not $env:LAB_BOOTSTRAP) { pause }
