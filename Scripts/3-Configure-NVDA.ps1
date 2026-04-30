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
# Hard-coded Student profile, not $env:APPDATA — UAC-elevated PS sessions resolve
# $env:APPDATA to whichever account answered the elevation prompt (Admin if you
# typed the Admin password, Student if Student is itself an admin). Writing to
# the wrong profile silently strands NVDA config + addons where Student can't
# see them. Standalone re-runs of this script (post-deploy patches) need to be
# correct regardless of which user ran the elevated shell.
$nvdaConfigDir = "C:\Users\Student\AppData\Roaming\nvda"
$nvdaConfigPath = Join-Path $nvdaConfigDir "nvda.ini"

Write-Log "USB Root: $usbRoot" "INFO"
Write-Log "Source config: $sourceConfig" "INFO"
Write-Log "Target config: $nvdaConfigPath" "INFO"

# Step 0: If NVDA is running, stop it before we touch nvda.ini or the addons
# directory. On already-deployed laptops where Student is auto-logged in, NVDA
# holds open file handles into addons\<name>\synthDrivers\*.pyd and
# globalPlugins\*; replacing those directories while NVDA is loaded races with
# its still-open handles, and on next reload NVDA can't load the addon
# (ModuleNotFoundError on the synthDriver) — student gets English fallback
# instead of Vietnamese. Stop-Process returns immediately but file-handle
# release lags, so poll until the processes are actually gone before
# proceeding. Save the running-state so Step 8 knows to restart.
$wasNvdaRunning = $false
$nvdaInitial = Get-Process -Name "nvda", "nvda_slave" -ErrorAction SilentlyContinue
if ($nvdaInitial) {
    Write-Log "NVDA is running (PIDs: $($nvdaInitial.Id -join ', ')) — stopping before config + addon work (will restart at end)..." "INFO"
    $wasNvdaRunning = $true
    Stop-Process -InputObject $nvdaInitial -Force -ErrorAction SilentlyContinue

    # Poll until processes are gone. 15s is generous; in practice handles release within 2-3s.
    # The previous fixed 2s sleep raced on slower laptops and was the proximate cause of the
    # 2026-04-30 "RHVoice ModuleNotFoundError after patch" incident.
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process -Name "nvda", "nvda_slave" -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
        Start-Sleep -Milliseconds 500
    }
    $stillRunning = Get-Process -Name "nvda", "nvda_slave" -ErrorAction SilentlyContinue
    if ($stillRunning) {
        Write-Log "WARNING: NVDA still running after 15s; addon files may be in use during Step 4 (PIDs: $($stillRunning.Id -join ', '))" "WARNING"
    } else {
        Write-Log "NVDA stopped cleanly; file handles released" "INFO"
    }
}

# Step 1: Create NVDA config directory if it doesn't exist
if (-not (Test-Path $nvdaConfigDir)) {
    Write-Log "Creating NVDA config directory..." "INFO"
    New-Item -Path $nvdaConfigDir -ItemType Directory -Force | Out-Null
}

# Step 2: Copy pre-configured NVDA profile.
# Hash-compare to skip if already canonical: on already-deployed laptops where the
# nvda.ini hasn't drifted, this avoids overwriting any student-saved tweaks (e.g.
# voice rate, punctuation level via NVDA+Ctrl+C). When config has actually changed
# (e.g. new chime-suppression block, schema bump), we deploy the canonical version.
if (Test-Path $sourceConfig) {
    try {
        $skipDeploy = $false
        if (Test-Path $nvdaConfigPath) {
            $srcHash = (Get-FileHash $sourceConfig).Hash
            $dstHash = (Get-FileHash $nvdaConfigPath).Hash
            if ($srcHash -eq $dstHash) {
                Write-Log "NVDA config already at canonical (hash $srcHash) — preserving in place" "INFO"
                $skipDeploy = $true
            }
        }
        if (-not $skipDeploy) {
            Copy-Item $sourceConfig $nvdaConfigPath -Force
            Write-Log "NVDA configuration profile applied successfully" "SUCCESS"
        }
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
        # Track every manifest name we successfully extract so the post-loop cleanup
        # can recognise stale duplicates (folders left over from prior script versions
        # that named extraction folders by .nvda-addon filename instead of manifest name).
        $extractedManifestNames = @{}

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
                # Copy-Item + Remove-Item rather than Move-Item: Move-Item from $env:TEMP
                # (Admin's profile) into the Student profile preserved the source's
                # directory entries, and on previously-deployed laptops where NVDA had
                # the old folder cached (or held a handle past Step 0), NVDA's import
                # system would fail to load the synth on next start (ModuleNotFoundError
                # on synthDrivers.<name>) even though the files looked correct on disk.
                # Copying creates fresh dirEntries that NVDA picks up cleanly. Confirmed
                # in field 2026-04-30: a laptop where Move-Item left RHVoice unloadable
                # was fixed by exactly this Copy + Remove sequence (sideline+restore).
                Copy-Item -Path $tempExtract -Destination $targetPath -Recurse -Force
                Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Add-on '$($addon.Name)' installed as '$manifestName'" "SUCCESS"
                $extractedManifestNames[$manifestName] = $true
            } catch {
                Write-Log "ERROR installing add-on $($addon.Name): $($_.Exception.Message)" "ERROR"
            }
        }

        # Cleanup duplicate addon folders left over from prior deploys.
        # An older version of this script extracted .nvda-addon files into folders
        # named after the file (e.g. addons/RHVoice-2.0.19/) instead of the manifest
        # name (e.g. addons/RHVoice/). The current run extracts to the manifest-name
        # folder but does NOT touch the legacy <filename> folder, so both end up on
        # disk side-by-side. NVDA loads BOTH (same `name = RHVoice` manifest field),
        # picks the higher version, and on this lab that means RHVoice 2.0.19 — which
        # fails inside the native lib (RHVoice_new_tts_engine returns NULL because
        # 2.0.19's voice resource layout doesn't match Vi-Vu's 1.x voice addon).
        # NVDA falls back to oneCore + Microsoft An. The student hears the wrong
        # Vietnamese voice and we get blamed for "vi-VN not defaulting".
        # The duplicate is identified by: same manifest name as one we just (re-)
        # extracted, but a different folder name. User-installed addons via the
        # NVDA UI are protected because they always extract to <manifestName>/.
        $cleanedCount = 0
        Get-ChildItem -Path $addonsDestDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $folderName = $_.Name
            $manifest = Join-Path $_.FullName 'manifest.ini'
            if (-not (Test-Path $manifest)) { return }
            $line = Get-Content $manifest | Where-Object { $_ -match '^\s*name\s*=' } | Select-Object -First 1
            if ($line -match '^\s*name\s*=\s*"?([^"\r\n]+?)"?\s*$') {
                $folderManifestName = $Matches[1].Trim()
                if ($extractedManifestNames.ContainsKey($folderManifestName) -and ($folderName -ne $folderManifestName)) {
                    try {
                        Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                        Write-Log "Removed stale duplicate addon folder '$folderName' (canonical='$folderManifestName')" "SUCCESS"
                        $cleanedCount++
                    } catch {
                        Write-Log "Could not remove stale duplicate '$folderName': $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        }
        if ($cleanedCount -gt 0) {
            Write-Log "Cleaned up $cleanedCount stale duplicate addon folder(s) from previous deploy(s)" "INFO"
        } else {
            Write-Log "No stale duplicate addon folders found" "INFO"
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
            # PowerShell 5.1's "-Encoding UTF8" prepends a BOM. NVDA's manifest parser
            # tolerates BOMs in some places but breaks subtly in others (the addon shows
            # in the addons folder but its synthDrivers/ never gets added to sys.path,
            # so setSynth fails with ModuleNotFoundError on the next start). Use
            # WriteAllText(...UTF8Encoding($false)) to write WITHOUT the BOM.
            [System.IO.File]::WriteAllText($manifest, $patched, (New-Object System.Text.UTF8Encoding $false))
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
        # Same BOM concern as the manifest patch above -- write without BOM.
        [System.IO.File]::WriteAllText($rhvoiceInit, $rhvoiceSrc, (New-Object System.Text.UTF8Encoding $false))
        $pyc = Join-Path (Split-Path $rhvoiceInit -Parent) '__pycache__'
        if (Test-Path $pyc) { Remove-Item $pyc -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Log "Patched RHVoice driver for NVDA 2025+ outputDevice config" "SUCCESS"
    } elseif ($rhvoiceSrc -match '_wp_kwargs') {
        Write-Log "RHVoice driver already patched for outputDevice" "INFO"
    } else {
        Write-Log "RHVoice driver WavePlayer line unrecognized; outputDevice patch skipped" "WARNING"
    }
}

# Step 4d: Silence NVDA Remote peer-join/leave chimes for the shared lab session.
# All laptops auto-connect to nvdaremote.com under shared key 'monarch-vn-lab'
# (remote.ini deployed by Configure-Laptop.ps1), forming one persistent multi-peer
# session. When any laptop's NVDA restarts, the relay broadcasts a leave then a
# join to every other peer in that channel; each peer fires cues.client_disconnected
# then cues.client_connected, which play disconnected.wav + controlling.wav from
# addons\remote\sounds\. Co-located laptops play those nearly simultaneously --
# the "synced chime" the user reported. Blind students don't need it: NVDA's own
# startup speech announces NVDA is running, and arrow-key navigation already speaks
# focus events. Note: setting [ui] play_sounds=False in remote.ini does NOT help --
# cues.py falls through to a beep-tone sequence in that branch (still audible).
# Overwriting the two WAVs with a 50 ms silent PCM stub kills the noise at source
# while leaving controlled.wav (local "joined relay" cue, once-per-restart on the
# joining laptop) and the clipboard cues intact for actual support sessions.
# Step 4 above wipes addons\remote\sounds\ on every run by re-extracting from the
# .nvda-addon archive, so this patch must run AFTER that to take effect -- same
# pattern as the RHVoice __init__.py patch above.
$remoteSoundsDir = Join-Path $addonsDestDir 'remote\sounds'
if (Test-Path $remoteSoundsDir) {
    # Build a minimal valid PCM WAV: 22050 Hz, mono, 16-bit, 50 ms of silence.
    # Header (44 bytes) + 2205 samples * 2 bytes = 2249 bytes total. Standard
    # nvwave.playWaveFile in NVDA accepts this without complaint.
    $sampleRate = 22050
    $bitsPerSample = 16
    $channels = 1
    $numSamples = [int]($sampleRate * 0.05)
    $byteRate = $sampleRate * $channels * ($bitsPerSample / 8)
    $blockAlign = $channels * ($bitsPerSample / 8)
    $dataSize = $numSamples * $blockAlign
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $bw.Write([uint32](36 + $dataSize))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
    $bw.Write([uint32]16)         # fmt chunk size
    $bw.Write([uint16]1)          # PCM
    $bw.Write([uint16]$channels)
    $bw.Write([uint32]$sampleRate)
    $bw.Write([uint32]$byteRate)
    $bw.Write([uint16]$blockAlign)
    $bw.Write([uint16]$bitsPerSample)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $bw.Write([uint32]$dataSize)
    $bw.Write((New-Object byte[] $dataSize))
    $silentBytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()

    $silenceCount = 0
    foreach ($wavName in @('disconnected.wav', 'controlling.wav')) {
        $target = Join-Path $remoteSoundsDir $wavName
        if (Test-Path $target) {
            try {
                [System.IO.File]::WriteAllBytes($target, $silentBytes)
                Write-Log "Silenced NVDA Remote chime: $wavName ($($silentBytes.Length) bytes)" "SUCCESS"
                $silenceCount++
            } catch {
                Write-Log "Could not silence ${wavName}: $($_.Exception.Message)" "WARNING"
            }
        }
    }
    if ($silenceCount -gt 0) {
        Write-Log "NVDA Remote chime silencing: $silenceCount WAV(s) replaced (peer-join/leave audible on all co-located lab laptops otherwise)" "INFO"
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
        # Stop UniKey if it's running. On previously-deployed laptops the
        # UniKey-Startup-Vietnamese scheduled task has already auto-launched
        # UniKeyNT.exe, which holds an exclusive write lock on Program Files\UniKey\
        # binaries. Without this stop, Copy-Item below fails with
        # "process cannot access the file ... because it is being used by another
        # process" and the binaries are left at the prior version (silent failure
        # — confirmed in 2026-04-30 field-patch log).
        $unikeyProcs = Get-Process -Name "UniKeyNT" -ErrorAction SilentlyContinue
        if ($unikeyProcs) {
            Write-Log "Stopping UniKey (PIDs: $($unikeyProcs.Id -join ', ')) so binaries can be replaced" "INFO"
            Stop-Process -InputObject $unikeyProcs -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
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

# Step 8: Start NVDA. Prefer the LabNVDAStart scheduled task because it brokers
# UIAccess elevation through `cmd /c start` (ShellExecute) — direct CreateProcess
# of nvda.exe from a non-admin principal returns 0x800702E4 because nvda.exe ships
# with manifest level=asInvoker uiAccess=true. The task was registered by
# Configure-Laptop.ps1 Step 16 and runs in the BUILTIN\Users group context, so it
# starts NVDA in Student's interactive session even when this wrapper was elevated
# to Admin via UAC.
$nvdaProcess = Get-Process -Name "nvda" -ErrorAction SilentlyContinue
if (-not $nvdaProcess) {
    Write-Log "Starting NVDA..." "INFO"
    try {
        $labTask = Get-ScheduledTask -TaskName 'LabNVDAStart' -ErrorAction SilentlyContinue
        if ($labTask) {
            Start-ScheduledTask -TaskName 'LabNVDAStart' -ErrorAction Stop
            Start-Sleep -Seconds 3
            $nvdaProcess = Get-Process -Name "nvda" -ErrorAction SilentlyContinue
            if ($nvdaProcess) {
                Write-Log "NVDA started via LabNVDAStart task (PID $($nvdaProcess.Id))" "SUCCESS"
            } else {
                Write-Log "LabNVDAStart task fired but nvda.exe not visible yet; should appear shortly" "WARNING"
            }
        } else {
            $nvdaExePath = if (Test-Path "C:\Program Files\NVDA\nvda.exe") {
                "C:\Program Files\NVDA\nvda.exe"
            } elseif (Test-Path "C:\Program Files (x86)\NVDA\nvda.exe") {
                "C:\Program Files (x86)\NVDA\nvda.exe"
            } else { $null }
            if ($nvdaExePath) {
                # Fallback: cmd /c start brokers ShellExecute for UIAccess.
                Start-Process -FilePath cmd.exe -ArgumentList "/c", "start", '""', "`"$nvdaExePath`"" -WindowStyle Hidden
                Start-Sleep -Seconds 3
                Write-Log "NVDA started ($nvdaExePath via cmd /c start)" "SUCCESS"
            } else {
                Write-Log "NVDA executable not found in either Program Files location; LabNVDAStart will start it on next logon" "WARNING"
            }
        }
    } catch {
        Write-Log "ERROR starting NVDA: $($_.Exception.Message)" "ERROR"
        if ($wasNvdaRunning) {
            Write-Log "CRITICAL: NVDA was running before this script started but is not running now. Student has no speech until logon/reboot triggers LabNVDAStart." "ERROR"
        }
    }
} else {
    Write-Log "NVDA is already running" "INFO"
}

# Step 9: Validate that NVDA actually came up healthy with the configured synth.
# Three classes of failure can ship silently if we don't check the log:
#   1. Config-schema rejection — NVDA renames nvda.ini to nvda.ini.corrupted.bak
#      and reverts to defaults (we shipped a config NVDA's parser no longer accepts).
#   2. Synth load failure — NVDA tried to load synthDrivers.rhvoice but couldn't,
#      so it falls back to oneCore (English Microsoft An). Student loses Vietnamese
#      speech and the script's old success/fail check missed this entirely.
#   3. NVDA process didn't even start.
# All three were observed in the field; the script must fail LOUD on each so the
# field tech doesn't walk away with the laptop in a half-broken state.
Write-Log "Validating NVDA started with the configured synth..." "INFO"
Start-Sleep -Seconds 6  # let NVDA finish init + write log

$nvdaRunningNow = Get-Process -Name "nvda" -ErrorAction SilentlyContinue
$logCandidates = @(
    "C:\Users\Student\AppData\Local\Temp\nvda.log",
    "C:\Users\Admin\AppData\Local\Temp\nvda.log"
)
$configRejected = $false
$synthFailed = $false
$synthLoaded = $null
$logChecked = $null

foreach ($logPath in $logCandidates) {
    if (Test-Path $logPath) {
        $logChecked = $logPath
        $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        # Only look at current session — previous corruption events are irrelevant.
        $lastStart = ($logContent -split "`n" | Select-String -Pattern 'Starting NVDA version' | Select-Object -Last 1).LineNumber
        if ($lastStart) {
            $sessionLines = ($logContent -split "`n") | Select-Object -Skip ($lastStart - 1)
            $sessionText = $sessionLines -join "`n"

            # 1. Schema rejection
            if ($sessionText -match 'ValidateError|Error loading base configuration') {
                Write-Log "ERROR: NVDA rejected the deployed config on this start." "ERROR"
                Write-Log "Log: $logPath" "ERROR"
                $configRejected = $true
            }

            # 2. Synth load failure — NVDA fell back from configured RHVoice.
            if ($sessionText -match "ModuleNotFoundError: No module named 'synthDrivers\.rhvoice'") {
                Write-Log "ERROR: NVDA could not import synthDrivers.rhvoice — RHVoice addon failed to register." "ERROR"
                $synthFailed = $true
            }
            if ($sessionText -match 'Falling back to next synthDriver (\S+)') {
                Write-Log "ERROR: NVDA fell back to '$($Matches[1])' instead of configured RHVoice. Student gets English fallback." "ERROR"
                $synthFailed = $true
            }
            $synthMatch = [regex]::Match($sessionText, 'Loaded synthDriver (\S+)')
            if ($synthMatch.Success) { $synthLoaded = $synthMatch.Groups[1].Value.Trim() }
            if ($synthLoaded -and $synthLoaded -ne 'RHVoice') {
                Write-Log "ERROR: NVDA loaded synthDriver '$synthLoaded' but config wanted RHVoice." "ERROR"
                $synthFailed = $true
            }
        }
        break
    }
}

# 3. NVDA didn't start at all
$nvdaMissing = -not $nvdaRunningNow

# Loud summary banner — field tech sees pass/fail at a glance, no log-parsing required.
Write-Host ""
$validationFailed = $configRejected -or $synthFailed -or $nvdaMissing
if ($validationFailed) {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  NVDA CONFIGURATION FAILED — DO NOT WALK AWAY" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    if ($nvdaMissing) {
        Write-Host "  - nvda.exe is not running 6s after Step 8 attempted to start it." -ForegroundColor Red
        Write-Host "    Try: Start-ScheduledTask -TaskName 'LabNVDAStart' manually." -ForegroundColor Red
    }
    if ($configRejected) {
        Write-Host "  - Config schema rejected. Fix Config/nvda-config/nvda.ini" -ForegroundColor Red
        Write-Host "    in the repo before deploying to more laptops." -ForegroundColor Red
    }
    if ($synthFailed) {
        Write-Host "  - Configured synth (RHVoice) did not load. Loaded: '$synthLoaded'." -ForegroundColor Red
        Write-Host "    Student will hear English fallback instead of Vietnamese." -ForegroundColor Red
        Write-Host "    Recovery: kill nvda; rename addons -> addons.broken; restart NVDA;" -ForegroundColor Red
        Write-Host "    Copy-Item addons.broken contents back into addons; restart NVDA." -ForegroundColor Red
    }
    if ($logChecked) { Write-Host "  Log: $logChecked" -ForegroundColor Red }
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Log "=== NVDA Configuration FAILED — see banner ===" "ERROR"
    exit 1
} elseif ($logChecked -and $synthLoaded) {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  NVDA OK: synthDriver '$synthLoaded' loaded; no schema errors" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Log "NVDA validated: synth=$synthLoaded, no schema errors" "SUCCESS"
} else {
    Write-Log "WARNING: NVDA running but log not yet parseable — synth load not confirmed (this is rare; if you can't hear Vi-Vu, treat as FAIL)" "WARNING"
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
Write-Host "  2. Run .\2-Verify-Installation.ps1 to confirm install + addons" -ForegroundColor White
Write-Host "  3. Then .\Configure-Laptop.ps1 -PCNumber <N> for hardening + scheduled tasks" -ForegroundColor White
Write-Host ""

Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Green
Write-Host ""

Write-Log "=== NVDA Configuration Complete ===" "INFO"

# Explicit exit 0 — without this, $LASTEXITCODE leaks from the last native command
# (icacls, robocopy, reg.exe, etc.) and the Apply-All-Field-Patches.ps1 wrapper
# misreports this step as FAIL even when everything succeeded.
exit 0
