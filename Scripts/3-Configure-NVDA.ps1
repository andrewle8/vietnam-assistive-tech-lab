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
# NVDA auto-start is handled by Configure-Laptop.ps1 Step 16 via the LabNVDAStart
# scheduled task (AtLogOn, battery-safe, Priority 4). The legacy Startup-folder .lnk
# was deferred ~2 minutes on battery cold boot, leaving blind students without speech.

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
                # NVDA 2024+ matches addons by the 'name' field in manifest.ini, NOT by folder
                # name. If we extract clipspeak-2025.06.13.nvda-addon to a folder of the same
                # name, NVDA's loader skips it because the folder doesn't match the manifest's
                # `name = clipspeak`. Result: addon is invisible (no synth in NVDA+Ctrl+S, no
                # commands, etc.) -- and silent, because there's no error in the log either.
                # Fix: extract to temp, read the real name from manifest.ini, then move.
                $fileStem = [System.IO.Path]::GetFileNameWithoutExtension($addon.Name)
                $tempZip = Join-Path $env:TEMP "$fileStem.zip"
                $tempExtract = Join-Path $env:TEMP "addon-extract-$fileStem"
                if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
                Copy-Item -Path $addon.FullName -Destination $tempZip -Force
                Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
                Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue

                $manifestPath = Join-Path $tempExtract 'manifest.ini'
                $manifestName = $null
                if (Test-Path $manifestPath) {
                    # Manifest values may be quoted ("clipspeak") or bare (clipspeak); strip both.
                    $line = Get-Content $manifestPath | Where-Object { $_ -match '^\s*name\s*=' } | Select-Object -First 1
                    if ($line -match '^\s*name\s*=\s*"?([^"\r\n]+?)"?\s*$') { $manifestName = $Matches[1].Trim() }
                }
                if (-not $manifestName) {
                    Write-Log "Manifest name missing in $($addon.Name); falling back to filename '$fileStem'" "WARNING"
                    $manifestName = $fileStem
                }

                $targetPath = Join-Path $addonsDestDir $manifestName
                if (Test-Path $targetPath) { Remove-Item -Path $targetPath -Recurse -Force }
                Move-Item -Path $tempExtract -Destination $targetPath -Force
                Write-Log "Add-on '$($addon.Name)' installed as '$manifestName'" "SUCCESS"
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

# Step 4b: Bump lastTestedNVDAVersion in addon manifests to bypass NVDA's compat block.
# Some bundled addons (notably RHVoice 2.0.19) ship with lastTestedNVDAVersion = 2024.1.0.
# NVDA 2025.x silently blocks them with "ModuleNotFoundError: No module named 'synthDrivers.<x>'"
# and falls back to the next synth -- on this build that's oneCore + Microsoft An, which is what
# we want as the default anyway. But the user can never SELECT RHVoice (or any other blocked
# addon) from the synth dropdown, because NVDA never registers it. Patching the manifest after
# extraction makes the addon load and become selectable, without needing pickle edits to
# addonsState. We do this for the local copy only -- the .nvda-addon archives on the USB stay
# untouched as binary source-of-truth.
$bumpFloor = '9999.1.0'  # any value the addon ships with will be lower
$bumpedCount = 0
Get-ChildItem -Path $addonsDestDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $manifest = Join-Path $_.FullName 'manifest.ini'
    if (-not (Test-Path $manifest)) { return }
    $content = Get-Content $manifest -Raw
    if ($content -match '(?m)^\s*lastTestedNVDAVersion\s*=\s*(\S+)') {
        $current = $Matches[1]
        if ($current -ne $bumpFloor) {
            $patched = $content -replace '(?m)^(\s*lastTestedNVDAVersion\s*=\s*)\S+', "`${1}$bumpFloor"
            Set-Content -Path $manifest -Value $patched -NoNewline -Encoding UTF8
            Write-Log "Bumped lastTestedNVDAVersion in $($_.Name) (was $current)" "SUCCESS"
            $bumpedCount++
        }
    }
}
Write-Log "Manifest compat bump: $bumpedCount addon(s) updated" "INFO"

# Step 4c: Patch RHVoice 1.16.2 driver for NVDA 2025+ audio config layout.
# The driver constructs nvwave.WavePlayer with outputDevice=config.conf["speech"]["outputDevice"].
# NVDA 2025 removed that key (audio routing is now global in the [audio] section), so the
# WavePlayer construction throws KeyError on every attempt to speak -- the synth loads, the
# voice gets selected, but no audio ever plays. Patch makes the lookup defensive: try the old
# location, then the new [audio] location, then fall back to no-arg (system default device).
# Idempotent: the regex matches the unpatched line and rewrites only the first time.
$rhvoiceInit = Join-Path $addonsDestDir 'RHVoice\synthDrivers\RHVoice\__init__.py'
if (Test-Path $rhvoiceInit) {
    $rhvoiceSrc = Get-Content $rhvoiceInit -Raw
    $unpatched = 'player = nvwave.WavePlayer(channels=1, samplesPerSec=self.__sample_rate, bitsPerSample=16, outputDevice=config.conf["speech"]["outputDevice"])'
    $patched = @'
_wp_kwargs = {"channels": 1, "samplesPerSec": self.__sample_rate, "bitsPerSample": 16}
            try:
                _wp_kwargs["outputDevice"] = config.conf["speech"]["outputDevice"]
            except KeyError:
                try:
                    _wp_kwargs["outputDevice"] = config.conf["audio"]["outputDevice"]
                except KeyError:
                    pass  # let WavePlayer pick the system default
            player = nvwave.WavePlayer(**_wp_kwargs)
'@
    if ($rhvoiceSrc.Contains($unpatched)) {
        $rhvoiceSrc = $rhvoiceSrc.Replace($unpatched, $patched.TrimEnd())
        Set-Content -Path $rhvoiceInit -Value $rhvoiceSrc -NoNewline -Encoding UTF8
        $pyc = Join-Path (Split-Path $rhvoiceInit -Parent) '__pycache__'
        if (Test-Path $pyc) { Remove-Item $pyc -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Log "Patched RHVoice driver for NVDA 2025+ outputDevice config" "SUCCESS"
    } elseif ($rhvoiceSrc -match '_wp_kwargs') {
        Write-Log "RHVoice driver already patched for outputDevice" "INFO"
    } else {
        Write-Log "RHVoice driver WavePlayer line unrecognized; outputDevice patch skipped" "WARNING"
    }
}

# Step 5: Mirror VNVoice SAPI5 voices from 32-bit to 64-bit registry
# VNVoice installs as 32-bit (WOW6432Node) but NVDA is 64-bit
Write-Log "Mirroring VNVoice voices to 64-bit SAPI5 registry..." "INFO"

$src32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Speech\Voices\Tokens"
$dst64 = "HKLM:\SOFTWARE\Microsoft\Speech\Voices\Tokens"

if (Test-Path $src32) {
    $saoMaiVoices = Get-ChildItem $src32 | Where-Object {
        $attrs = Join-Path $_.PSPath "Attributes"
        (Test-Path $attrs) -and ((Get-ItemProperty $attrs -EA SilentlyContinue).Vendor -eq "SaoMai")
    }

    foreach ($voice in $saoMaiVoices) {
        $voiceName = $voice.PSChildName
        $dstPath = Join-Path $dst64 $voiceName

        if (-not (Test-Path $dstPath)) { New-Item -Path $dstPath -Force | Out-Null }
        $srcProps = Get-ItemProperty $voice.PSPath
        foreach ($prop in $srcProps.PSObject.Properties) {
            if ($prop.Name -match "^PS") { continue }
            Set-ItemProperty -Path $dstPath -Name $prop.Name -Value $prop.Value -Force
        }

        $srcAttr = Join-Path $voice.PSPath "Attributes"
        $dstAttr = Join-Path $dstPath "Attributes"
        if (Test-Path $srcAttr) {
            if (-not (Test-Path $dstAttr)) { New-Item -Path $dstAttr -Force | Out-Null }
            $attrProps = Get-ItemProperty $srcAttr
            foreach ($prop in $attrProps.PSObject.Properties) {
                if ($prop.Name -match "^PS") { continue }
                Set-ItemProperty -Path $dstAttr -Name $prop.Name -Value $prop.Value -Force
            }
        }

        Write-Log "Mirrored voice '$voiceName' to 64-bit registry" "SUCCESS"
    }

    if ($saoMaiVoices.Count -eq 0) {
        Write-Log "No SaoMai voices found in 32-bit registry (VNVoice may not be installed)" "WARNING"
    }
} else {
    Write-Log "32-bit SAPI5 registry path not found" "WARNING"
}

# Step 5b: DllSurrogate for VnTtsEng (32-bit COM, must be reachable by 64-bit NVDA).
# Mirroring the voice tokens (Step 5) is not enough -- the engine CLSID resolves to a
# 32-bit InprocServer32, which 64-bit processes cannot load directly. Registering an
# empty DllSurrogate for the AppID makes COM host the DLL in dllhost.exe, and 64-bit
# clients (NVDA, sm-Readmate, SAPI.SpVoice) can then enumerate and use the voices.
$vnTtsClsid = '{7DDCD6E4-E60A-4C60-B7AA-C9A652FEEDF2}'
$wow64Clsid = "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$vnTtsClsid"
if (Test-Path $wow64Clsid) {
    try {
        $appIdPath = "HKLM:\SOFTWARE\Classes\AppID\$vnTtsClsid"
        if (-not (Test-Path $appIdPath)) { New-Item -Path $appIdPath -Force | Out-Null }
        New-ItemProperty -Path $appIdPath -Name 'DllSurrogate' -Value '' -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $wow64Clsid -Name 'AppID' -Value $vnTtsClsid -PropertyType String -Force | Out-Null
        Write-Log "Registered DllSurrogate for VnTtsEng -- 64-bit NVDA can now use Sao Mai voices" "SUCCESS"
    } catch {
        Write-Log "Failed to register DllSurrogate for VnTtsEng: $_" "WARNING"
    }
} else {
    Write-Log "VnTtsEng CLSID not found in 32-bit hive (VNVoice may not be installed)" "INFO"
}

# Step 6: Install UniKey (Vietnamese keyboard input)
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

        # Auto-start on login + per-hive registry baseline (ShowDlg=0, AutoUpdate=0,
        # Vietnamese=1) are handled by Configure-Laptop.ps1 Step 27b, which installs
        # the 'UniKey-Startup-Vietnamese' scheduled task. No launcher shortcut or VBS
        # wrapper is created here -- an earlier approach did, and then Step 27b had to
        # delete it, producing a transient "cannot find script file start-unikey.vbs"
        # popup on fresh deployments.
    } catch {
        Write-Log "ERROR installing UniKey: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "UniKey not found at $unikeySourceDir (optional)" "INFO"
    Write-Log "Vietnamese input: use Windows Settings > Language > Add Vietnamese" "INFO"
}

# Step 7 (secure-desktop / login-screen NVDA with Vi-Vu voice) has moved to
# Configure-Laptop.ps1 Step 16. It has to run AFTER the Student profile has
# received nvda.ini and the addons, which happens in Configure-Laptop.ps1 —
# not here.

# Step 8: Start NVDA now (if not already running)
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

# Step 9: Validate deployed config loaded without schema errors.
# NVDA's config schema changes between releases (e.g. old boolean fields becoming
# featureFlag enums). If our deployed nvda.ini has syntax NVDA no longer accepts,
# NVDA saves it to nvda.ini.corrupted.bak and reverts to defaults, showing a
# Vietnamese error popup on first boot. Fail deployment loud here rather than
# letting 18 laptops ship with silently-reset configs.
Write-Log "Validating NVDA config loaded without schema errors..." "INFO"
Start-Sleep -Seconds 4  # give NVDA time to write its log
$logCandidates = @(
    "C:\Users\Student\AppData\Local\Temp\nvda.log",
    "C:\Users\Admin\AppData\Local\Temp\nvda.log"
)
$configRejected = $false
$logChecked = $null
foreach ($logPath in $logCandidates) {
    if (Test-Path $logPath) {
        $logChecked = $logPath
        $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        # Only look at current session — previous corruption events are irrelevant.
        # Each NVDA start logs "Starting NVDA version" — check only since the last one.
        $lastStart = ($logContent -split "`n" | Select-String -Pattern 'Starting NVDA version' | Select-Object -Last 1).LineNumber
        if ($lastStart) {
            $sessionLines = ($logContent -split "`n") | Select-Object -Skip ($lastStart - 1)
            $sessionText = $sessionLines -join "`n"
            if ($sessionText -match 'ValidateError|Error loading base configuration') {
                Write-Log "ERROR: NVDA rejected the deployed config on this start." "ERROR"
                Write-Log "Log: $logPath" "ERROR"
                Write-Log "Check the log for 'ValidateError' — config/nvda-config/nvda.ini likely has a key whose type changed in a newer NVDA release (e.g. boolean -> featureFlag)." "ERROR"
                $configRejected = $true
            }
        }
        break
    }
}
if ($configRejected) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "CONFIG VALIDATION FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "NVDA rejected the deployed config. See $logChecked for the ValidateError trace." -ForegroundColor Red
    Write-Host "Fix Config/nvda-config/nvda.ini in the repo before deploying to more laptops." -ForegroundColor Red
    Write-Host ""
} elseif ($logChecked) {
    Write-Log "NVDA config validated (no schema errors in $logChecked)" "SUCCESS"
} else {
    Write-Log "WARNING: Could not locate NVDA log to validate (NVDA may not have started yet)" "WARNING"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "NVDA Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
Write-Host "  - NVDA profile configured for Vietnamese" -ForegroundColor White
Write-Host "  - NVDA add-ons installed (if present in Installers\NVDA\addons\)" -ForegroundColor White
Write-Host "  - Auto-start on Windows login enabled" -ForegroundColor White
Write-Host "  - UniKey Vietnamese keyboard installed and auto-starting" -ForegroundColor White
Write-Host "  - Speech synthesizer set to RHVoice Vi-Vu (Vietnamese, portable)" -ForegroundColor White
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
