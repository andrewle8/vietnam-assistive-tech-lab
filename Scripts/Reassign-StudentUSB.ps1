# Reassign-StudentUSB.ps1
# Version: stu-resolver
#
# Resolves any volume labeled with the STU- prefix to a stable, drive-letter-
# independent path: C:\StudentUSB\ (a mount-point reparse point). All apps
# (Office Word/Excel/PowerPoint, Firefox download dir, Audacity directories,
# USB desktop shortcut) target this path so saves land on the student's USB
# regardless of which letter Windows assigns it.
#
# Behavior on each fire:
#   1. Find any volume whose label matches ^STU- (Removable, retry up to 3s).
#   2. If none: remove C:\StudentUSB\ entirely (mountvol /D + rmdir) so any
#      attempted access errors loudly. Office surfaces "path not found" and
#      NVDA reads it -- no silent C: fall-through.
#   3. If found:
#      a. Pin to D: if D: is vacant (existing belt-and-suspenders behavior).
#         Skip if another volume holds D: -- never evict.
#      b. Bind to C:\StudentUSB\ via mountvol (creates folder, attaches reparse
#         point referencing the volume GUID). MountManager pins by GUID, so
#         once bound, subsequent plugs of the same USB auto-rebind.
#      c. Update Office regs in the Student SID hive.
#      d. Rewrite Firefox policies.json browser.download.dir.Value.
#      e. Rewrite Audacity audacity.cfg [Directories/*] Default entries.
#      f. Repoint C:\Users\Public\Desktop\USB.lnk to explorer.exe with C:\StudentUSB as arg
#         (explorer.exe target avoids Windows broken-shortcut detection during unplug).
#   4. Append timestamped line to C:\LabTools\stu-resolver.log. Truncate to
#      last 500 lines once the log exceeds 1000.
#
# All steps are idempotent and try/catch-wrapped. A failure in one step does
# not abort subsequent steps. Script always exits 0 except on completely
# unexpected failures (so Task Scheduler LastTaskResult stays 0x0).
#
# Registered as a SYSTEM scheduled task with four triggers:
#   - AtStartup        (catches USBs plugged before boot)
#   - AtLogOn (any)    (catches USBs at the login screen)
#   - 1-minute repeat  (safety-net poll)
#   - EventLog: Microsoft-Windows-Ntfs/Operational EventID 4
#                      (sub-second response on USB plug; race-window closer)

$ErrorActionPreference = 'Continue'
$mountPoint = 'C:\StudentUSB'
$logDir     = 'C:\LabTools'
$logPath    = Join-Path $logDir 'stu-resolver.log'

#------------------------------------------------------------ helpers --------

function Write-LogLine {
    param([string]$Msg)
    try {
        if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $logPath -Value "[$stamp] $Msg" -ErrorAction SilentlyContinue
    } catch {}
}

function Trim-Log {
    try {
        if (-not (Test-Path $logPath)) { return }
        $lines = Get-Content -Path $logPath -ErrorAction SilentlyContinue
        if ($lines.Count -gt 1000) {
            $lines | Select-Object -Last 500 | Set-Content -Path $logPath -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Set-RegIfDifferent {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'String')
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($current -ne $Value) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            return $true
        }
        return $false
    } catch {
        Write-LogLine "  reg write failed: $Path\$Name -- $($_.Exception.Message)"
        return $false
    }
}

#------------------------------------------------------------ find volume ----

$stuVol = $null
for ($i = 1; $i -le 3; $i++) {
    $stuVol = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystemLabel -match '^STU-' -and $_.DriveType -eq 'Removable' } |
        Select-Object -First 1
    if ($stuVol) { break }
    Start-Sleep -Seconds 1
}

#------------------------------------------------------------ cleanup branch -

if (-not $stuVol) {
    if (Test-Path -LiteralPath $mountPoint) {
        try { & mountvol $mountPoint /D 2>&1 | Out-Null } catch {}
        try { & cmd.exe /c "rmdir `"$mountPoint`"" 2>&1 | Out-Null } catch {}
        if (-not (Test-Path -LiteralPath $mountPoint)) {
            Write-LogLine "no STU- volume; cleanup applied (mount point removed)"
        } else {
            Write-LogLine "no STU- volume; cleanup attempted but $mountPoint still present"
        }
    } else {
        Write-LogLine "no STU- volume; nothing to clean up"
    }
    Trim-Log
    exit 0
}

$stuLabel  = $stuVol.FileSystemLabel
$stuLetter = $stuVol.DriveLetter
$stuGuid   = (Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='${stuLetter}:'" -ErrorAction SilentlyContinue).DeviceID
if (-not $stuGuid) { Write-LogLine "could not resolve GUID for $stuLabel on ${stuLetter}:; aborting"; Trim-Log; exit 0 }

#------------------------------------------------------------ setup: D: pin -

if ($stuLetter -ne 'D' -and -not (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue)) {
    try {
        $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='${stuLetter}:'" -ErrorAction Stop
        Set-CimInstance -InputObject $vol -Property @{ DriveLetter = 'D:' } -ErrorAction Stop
        $stuLetter = 'D'
    } catch {
        Write-LogLine "  D: pin failed: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------ setup: mount --

# Pre-create the folder (mountvol does not auto-create on Windows 11 builds we tested).
if (-not (Test-Path -LiteralPath $mountPoint)) {
    try { New-Item -Path $mountPoint -ItemType Directory -Force -ErrorAction Stop | Out-Null } catch {
        Write-LogLine "  could not create $mountPoint -- $($_.Exception.Message)"
    }
}

# Check current binding. If already bound to our STU- GUID, no-op. If bound to
# a different GUID (USB swap), detach and rebind. If unbound, just bind.
$currentlyBound = $null
try {
    $rp = & fsutil reparsepoint query $mountPoint 2>&1
    if ($LASTEXITCODE -eq 0 -and (($rp | Out-String) -match '\\\\\?\\Volume\{[^}]+\}')) { $currentlyBound = $matches[0] }
} catch {}

if (-not $currentlyBound -or ($currentlyBound -and $currentlyBound.TrimEnd('\') -ne $stuGuid.TrimEnd('\'))) {
    if ($currentlyBound) { try { & mountvol $mountPoint /D 2>&1 | Out-Null } catch {} }
    try { & mountvol $mountPoint $stuGuid 2>&1 | Out-Null } catch { Write-LogLine "  mountvol bind failed: $($_.Exception.Message)" }
}

#------------------------------------------------------------ setup: regs ---

# Resolver runs as SYSTEM; HKCU is SYSTEM's profile (irrelevant). Write to the
# Student SID hive only -- that is what affects the student's Office sessions.
$studentSID = $null
try {
    $studentSID = (Get-CimInstance Win32_UserAccount -Filter "Name='Student'" -ErrorAction Stop).SID
} catch {}

if ($studentSID -and (Test-Path "Registry::HKEY_USERS\$studentSID")) {
    $hive = "Registry::HKEY_USERS\$studentSID"
    $newPath = 'C:\StudentUSB\'

    # Word: legacy DOC-PATH plus DefaultPath (some builds read one, some the other).
    $wOpts = "$hive\Software\Microsoft\Office\16.0\Word\Options"
    Set-RegIfDifferent $wOpts 'DOC-PATH'     $newPath | Out-Null
    Set-RegIfDifferent $wOpts 'DefaultPath'  $newPath | Out-Null
    Set-RegIfDifferent $wOpts 'PICTURE-PATH' $newPath | Out-Null

    # Excel and PowerPoint: DefaultPath (documented since Office 2003).
    Set-RegIfDifferent "$hive\Software\Microsoft\Office\16.0\Excel\Options"      'DefaultPath' $newPath | Out-Null
    Set-RegIfDifferent "$hive\Software\Microsoft\Office\16.0\PowerPoint\Options" 'DefaultPath' $newPath | Out-Null

    # Backstage: prefer local paths over OneDrive in Save As surfaces.
    Set-RegIfDifferent "$hive\Software\Microsoft\Office\16.0\Common\General" 'PreferCloudSaveLocations' 0 'DWord' | Out-Null
} else {
    Write-LogLine "  Student SID hive not loaded; skipping reg writes (will retry on next fire)"
}

#------------------------------------------------------------ setup: Firefox --

$ffPolicies = 'C:\Program Files\Mozilla Firefox\distribution\policies.json'
if (Test-Path -LiteralPath $ffPolicies) {
    try {
        $raw  = [System.IO.File]::ReadAllText($ffPolicies, [System.Text.Encoding]::UTF8)
        $json = $raw | ConvertFrom-Json
        $cur  = $json.policies.Preferences.'browser.download.dir'.Value
        if ($cur -ne 'C:\StudentUSB\') {
            $json.policies.Preferences.'browser.download.dir'.Value = 'C:\StudentUSB\'
            $out = $json | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($ffPolicies, $out, [System.Text.Encoding]::UTF8)
        }
    } catch {
        Write-LogLine "  Firefox policies.json update failed: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------ setup: Audacity -

$audCfg = 'C:\Users\Student\AppData\Roaming\audacity\audacity.cfg'
if (Test-Path -LiteralPath $audCfg) {
    try {
        $lines = [System.IO.File]::ReadAllLines($audCfg, [System.Text.Encoding]::UTF8)
        $inDirSection    = $false
        $inCloudAudiocom = $false
        $sawCloudSection = $false
        $sawSaveLocMode  = $false
        $changed         = $false
        $newLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in $lines) {
            if ($line -match '^\[Directories(/.*)?\]\s*$') {
                # Only touch the per-action sub-sections (Open/Save/Import/Export/MacrosOut),
                # not the parent [Directories] which holds TempDir.
                $inDirSection    = ($line -match '^\[Directories/')
                $inCloudAudiocom = $false
                $newLines.Add($line); continue
            }
            if ($line -match '^\[cloud/audiocom\]\s*$') {
                $inCloudAudiocom = $true
                $sawCloudSection = $true
                $inDirSection    = $false
                $newLines.Add($line); continue
            }
            if ($line -match '^\[') {
                # Leaving [cloud/audiocom] without seeing SaveLocationMode -- insert it.
                if ($inCloudAudiocom -and -not $sawSaveLocMode) {
                    $newLines.Add('SaveLocationMode=local'); $changed = $true; $sawSaveLocMode = $true
                }
                $inDirSection    = $false
                $inCloudAudiocom = $false
                $newLines.Add($line); continue
            }
            if ($inDirSection -and $line -match '^Default\s*=') {
                # Audacity escapes backslashes in values: Default=C:\\StudentUSB\\
                $desired = 'Default=C:\\StudentUSB\\'
                if ($line -ne $desired) { $changed = $true; $newLines.Add($desired); continue }
            }
            if ($inCloudAudiocom -and $line -match '^SaveLocationMode\s*=') {
                $sawSaveLocMode = $true
                if ($line -ne 'SaveLocationMode=local') { $changed = $true; $newLines.Add('SaveLocationMode=local'); continue }
            }
            $newLines.Add($line)
        }
        # EOF case: file ended while inside [cloud/audiocom] without seeing the key.
        if ($inCloudAudiocom -and -not $sawSaveLocMode) {
            $newLines.Add('SaveLocationMode=local'); $changed = $true
        }
        # Section never appeared: append it. Suppresses the "save to cloud or computer?"
        # prompt that Audacity 3.x shows on every save by default.
        if (-not $sawCloudSection) {
            $newLines.Add('[cloud/audiocom]')
            $newLines.Add('SaveLocationMode=local')
            $changed = $true
        }
        if ($changed) {
            [System.IO.File]::WriteAllLines($audCfg, $newLines, [System.Text.Encoding]::UTF8)
        }
    } catch {
        Write-LogLine "  Audacity audacity.cfg update failed: $($_.Exception.Message)"
    }
}

#------------------------------------------------------------ setup: shortcut -

# Self-healing: recreate the USB shortcut if missing, force-update target/icon/description.
# Target is explorer.exe (NOT C:\StudentUSB directly): explorer.exe always exists, so Windows
# broken-shortcut maintenance never flags this shortcut for deletion even when the resolver
# removes C:\StudentUSB during USB unplug. Click behavior is unchanged -- explorer opens the
# folder if present, surfaces "Windows cannot find C:\StudentUSB" if missing (loud failure
# preserved). Description rewrite forces stale pre-patch shortcuts (which read "Open This PC
# to access your USB drive") to converge on every resolver fire.
$lnkPath        = 'C:\Users\Public\Desktop\USB.lnk'
$shortcutExists = Test-Path -LiteralPath $lnkPath
$desiredTarget  = "$env:SystemRoot\explorer.exe"
$desiredArgs    = $mountPoint
$desiredIcon    = '%SystemRoot%\System32\imageres.dll,109'
$desiredDesc    = 'Open student USB folder'
try {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)  # opens existing OR returns a fresh in-memory object
    $needsSave = $false
    if ($sc.TargetPath       -ne $desiredTarget) { $sc.TargetPath       = $desiredTarget; $needsSave = $true }
    if ($sc.Arguments        -ne $desiredArgs)   { $sc.Arguments        = $desiredArgs;   $needsSave = $true }
    if ($sc.WorkingDirectory -ne '')             { $sc.WorkingDirectory = '';             $needsSave = $true }
    if ($sc.IconLocation     -ne $desiredIcon)   { $sc.IconLocation     = $desiredIcon;   $needsSave = $true }
    if ($sc.Description      -ne $desiredDesc)   { $sc.Description      = $desiredDesc;   $needsSave = $true }
    if (-not $shortcutExists) {
        Write-LogLine "  USB.lnk recreated (was missing)"
        $needsSave = $true
    }
    if ($needsSave) { $sc.Save() }
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($sc) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
} catch {
    Write-LogLine "  USB.lnk repoint failed: $($_.Exception.Message)"
}

#------------------------------------------------------------ done ----------

Write-LogLine "OK label=$stuLabel letter=${stuLetter}: guid=$stuGuid"
Trim-Log
exit 0
