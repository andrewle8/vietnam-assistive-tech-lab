# Vietnam Lab Deployment - Master Installation Script
# Version: 1.0
# Run as Administrator
# Last Updated: February 2026

param(
    [switch]$Silent = $true,
    [string]$LogPath = "$PSScriptRoot\installation.log"
)

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "SUCCESS"){"Green"}else{"Cyan"})
    Add-Content -Path $LogPath -Value $logMessage
}

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator!" "ERROR"
    Write-Host "`nPlease right-click and select 'Run as Administrator'" -ForegroundColor Red
    exit 1
}

Write-Log "=== Vietnam Lab Deployment Started ===" "INFO"
Write-Log "Computer Name: $env:COMPUTERNAME" "INFO"

# Navigate to USB root directory (assuming script is in Scripts folder)
$usbRoot = Split-Path -Parent $PSScriptRoot
Set-Location $usbRoot

Write-Log "USB Root: $usbRoot" "INFO"

# Installation sequence
$installations = @(
    @{
        Name = "NVDA 2025.3.3"
        Path = ".\Installers\NVDA\nvda_2025.3.3.exe"
        Args = @("--install-silent", "--minimal", "--log-level=20")
        WaitTime = 60
    },
    @{
        Name = "Sao Mai VNVoice"
        Path = ".\Installers\SaoMai\SaoMai_voice1.0.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        Name = "Sao Mai Typing Tutor"
        Path = ".\Installers\SaoMai\SMTTSetup.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        Name = "SM Readmate"
        Path = ".\Installers\SaoMai\SMReadmate1.1.0-setup.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        # SAPI5 build of RHVoice + Vi-Vu (LouderPages bundle: x86/x64 engine, English &
        # Vietnamese language packs, Vi-Vu voice). Registers Vi-Vu via a SAPI5 TokenEnum
        # under HKLM\SOFTWARE\Microsoft\Speech\Voices\TokenEnums\RHVoice -- so it shows up
        # to any SAPI5-aware app (Readmate, SMTT, NVDA's SAPI5 driver). Inno bundle, takes
        # /VERYSILENT cleanly. /SILENT shows a progress bar; /VERYSILENT is fully invisible.
        Name = "RHVoice Vi-Vu (SAPI5)"
        Path = ".\Installers\SaoMai\RHVoice-voice-Vietnamese-Vi-Vu-v4.8.1009.21-setup.exe"
        Args = @("/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES")
        WaitTime = 45
    }
)

$installations += @(
    @{
        Name = "Firefox 149"
        Path = ".\Installers\Firefox\Firefox Setup 149.0.msi"
        Args = @("/i", "`"$($usbRoot)\Installers\Firefox\Firefox Setup 149.0.msi`"", "/quiet", "/norestart")
        UseMsiExec = $true
        WaitTime = 60
    },
    @{
        Name = "VLC Media Player"
        Path = ".\Installers\Utilities\vlc-3.0.23-win64.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        Name = "Audacity 3.7.7"
        Path = ".\Installers\Audacity\audacity-win-3.7.7-64bit.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        Name = "GoldenDict 1.5.1"
        Path = ".\Installers\Utilities\GoldenDict\GoldenDict-1.5.1-Install.exe"
        Args = @("/S")
        WaitTime = 30
    },
    @{
        # Dell Command | Configure - provides cctk.exe for fleet BIOS management.
        # Self-extracting Dell SDP wrapper; /s runs silent. Only required on Dell hardware
        # (Latitude 5420 in our fleet); harmless to skip on non-Dell test bench.
        Name = "Dell Command | Configure 5.2.2"
        Path = ".\Installers\Dell\Dell-Command-Configure-Application_F2V9N_WIN64_5.2.2.292_A00.EXE"
        Args = @("/s")
        WaitTime = 120
    }
)

$successCount = 0
$failCount = 0

foreach ($app in $installations) {
    Write-Log "Installing $($app.Name)..." "INFO"

    # Check if installer exists
    if (-not (Test-Path $app.Path)) {
        Write-Log "ERROR: Installer not found at $($app.Path)" "ERROR"
        $failCount++
        continue
    }

    try {
        if ($app.UseMsiExec) {
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $app.Args -Wait -PassThru -NoNewWindow
        } else {
            $process = Start-Process -FilePath $app.Path -ArgumentList $app.Args -Wait -PassThru -NoNewWindow
        }

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "$($app.Name) installed successfully (Exit Code: $($process.ExitCode))" "SUCCESS"
            $successCount++
        } else {
            Write-Log "$($app.Name) installation completed with exit code: $($process.ExitCode)" "WARNING"
            $successCount++  # Many installers return non-zero for success
        }

        # Wait a bit before next installation
        Start-Sleep -Seconds 2

    } catch {
        Write-Log "ERROR installing $($app.Name): $($_.Exception.Message)" "ERROR"
        $failCount++
    }
}

# Install Microsoft Office
Write-Log "Installing Microsoft Office..." "INFO"
$msOfficeInstaller = Join-Path $usbRoot "Installers\MSOffice\setup.exe"
$msOfficeInstalled = (Test-Path "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE") -or
                     (Test-Path "C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE")

if ($msOfficeInstalled) {
    Write-Log "Microsoft Office is already installed - skipping" "SUCCESS"
    $successCount++
} elseif (Test-Path $msOfficeInstaller) {
    try {
        $process = Start-Process -FilePath $msOfficeInstaller -ArgumentList "/configure", "configuration.xml" -Wait -PassThru -NoNewWindow -WorkingDirectory (Split-Path $msOfficeInstaller)
        if ($process.ExitCode -eq 0) {
            Write-Log "Microsoft Office installed successfully" "SUCCESS"
            $successCount++
        } else {
            Write-Log "Microsoft Office installation completed with exit code: $($process.ExitCode)" "WARNING"
            $successCount++
        }
    } catch {
        Write-Log "ERROR installing Microsoft Office: $($_.Exception.Message)" "ERROR"
        $failCount++
    }
} else {
    Write-Log "WARNING: MS Office installer not found at $msOfficeInstaller - skipping office suite install" "WARNING"
    Write-Log "  Place Office Deployment Tool files in Installers\MSOffice\ or pre-install MS Office" "INFO"
}

$publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")

# Install Kiwix + Vietnamese Wikipedia (portable - copy to local folder and create shortcut)
Write-Log "Installing Kiwix offline encyclopedia..." "INFO"

$kiwixSourceDir = Join-Path $usbRoot "Installers\Kiwix"
$kiwixDestDir = "C:\Program Files\Kiwix"

if (Test-Path $kiwixSourceDir) {
    $kiwixExe = Get-ChildItem -Path $kiwixSourceDir -Filter "kiwix-desktop.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($kiwixExe) {
        try {
            if (-not (Test-Path $kiwixDestDir)) {
                New-Item -Path $kiwixDestDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$kiwixSourceDir\*" -Destination $kiwixDestDir -Recurse -Force
            Write-Log "Copied Kiwix to $kiwixDestDir" "SUCCESS"

            # Create desktop shortcut
            $destExe = Join-Path $kiwixDestDir "kiwix-desktop.exe"
            if (Test-Path $destExe) {
                $WshShell = New-Object -ComObject WScript.Shell
                $shortcutPath = Join-Path $publicDesktop "Wikipedia.lnk"
                $shortcut = $WshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $destExe
                $shortcut.WorkingDirectory = $kiwixDestDir
                $shortcut.Description = "Kiwix - Offline Vietnamese Wikipedia"
                $shortcut.Save()
                Write-Log "Created desktop shortcut: Wikipedia" "SUCCESS"
            }

            $successCount++
        } catch {
            Write-Log "ERROR installing Kiwix: $($_.Exception.Message)" "ERROR"
            $failCount++
        }
    } else {
        Write-Log "Kiwix executable not found in $kiwixSourceDir (optional)" "INFO"
    }
} else {
    Write-Log "Kiwix directory not found at $kiwixSourceDir (optional)" "INFO"
}

# Locate GoldenDict.exe for dictionary content installation below.
# Desktop shortcut creation is owned by Configure-Laptop.ps1 Step 6 — it uses
# direct IShellLink/IPersistFile which handles the Unicode "Từ Điển" filename
# cleanly. WScript.Shell here would always throw on CP-1252 systems and produce
# a misleading WARNING in the log.
$goldenDictExe = if (Test-Path "C:\Program Files\GoldenDict\GoldenDict.exe") {
    "C:\Program Files\GoldenDict\GoldenDict.exe"
} elseif (Test-Path "C:\Program Files (x86)\GoldenDict\GoldenDict.exe") {
    "C:\Program Files (x86)\GoldenDict\GoldenDict.exe"
} else { $null }

if ($goldenDictExe) {
    # Install Vietnamese StarDict dictionaries into GoldenDict's content folder
    Write-Log "Installing Vietnamese dictionaries for GoldenDict..." "INFO"
    $dictSourceDir = Join-Path $usbRoot "Installers\Dictionaries"
    $goldenDictDir = Split-Path $goldenDictExe
    $dictDestDir = Join-Path $goldenDictDir "content"

    if (Test-Path $dictSourceDir) {
        try {
            if (-not (Test-Path $dictDestDir)) {
                New-Item -Path $dictDestDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$dictSourceDir\*" -Destination $dictDestDir -Recurse -Force
            $dictCount = (Get-ChildItem $dictDestDir -Filter "*.ifo" -Recurse -ErrorAction SilentlyContinue).Count
            Write-Log "Installed $dictCount Vietnamese dictionaries to $dictDestDir" "SUCCESS"
            $successCount++
        } catch {
            Write-Log "Could not install dictionaries: $($_.Exception.Message)" "WARNING"
        }
    } else {
        Write-Log "No dictionaries found at $dictSourceDir (run 0-Download-Installers.ps1)" "INFO"
    }
}

# Note: Ebook deployment is now handled by Configure-Laptop.ps1 Step 17b
# (calls Populate-ReadmateDB.ps1 which copies books directly into SM Readmate's
# data folder and registers them in its library database).

Write-Log "`n=== Installation Summary ===" "INFO"
Write-Log "Successful installations: $successCount" "SUCCESS"
Write-Log "Failed installations: $failCount" $(if($failCount -gt 0){"ERROR"}else{"SUCCESS"})

if ($failCount -eq 0) {
    Write-Log "`nAll software installed successfully!" "SUCCESS"
    Write-Log "Next step: Run 2-Verify-Installation.ps1" "INFO"
} else {
    Write-Log "`nSome installations failed. Check log at: $LogPath" "WARNING"
    Write-Log "You can re-run this script or install failed components manually" "INFO"
}

Write-Log "=== Installation Complete ===" "INFO"

Write-Host "`n"
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Successful: $successCount | Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){"Yellow"}else{"Green"})
Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
Write-Host "`nNext step: Run .\2-Verify-Installation.ps1" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
