# Fix-SilverDict.ps1
# USB-walkup patch for already-deployed laptops. Installs SilverDict (the
# NVDA-accessible dictionary path) on a laptop that was deployed before this
# step existed in Configure-Laptop.ps1.
#
# After this runs, SilverDict serves the StarDict dictionaries over
# localhost:2628 and the Student desktop "Từ Điển" shortcut opens Firefox to
# http://localhost:2628/dict.html. NVDA browse mode works natively in Firefox -
# NVDA cannot browse-mode GoldenDict's QtWebEngine article view (NVDA #10838,
# closed-Abandoned 2024-07-02). GoldenDict 1.5.1 stays installed for sighted
# users via Start Menu.
#
# Mirrors Configure-Laptop.ps1 Step 35b. Runs five idempotent stages:
#
#   1. Copy SilverDict bundle from <USB>\Installers\SilverDict\SilverDict to
#      C:\Program Files\SilverDict, replace 3 HTML files with NVDA-friendly
#      versions from Config\silverdict-config, stage StarDict files into
#      C:\Program Files\SilverDict\source.
#   2. Pre-seed C:\Users\Student\.silverdict\ with dictionaries.yaml,
#      groups.yaml, junction_table.yaml, misc.yaml, preferences.yaml so the
#      first server start has the dict list ready (no manual UI scan needed).
#   3. Write C:\Program Files\SilverDict\start-silverdict.vbs (hidden launcher).
#   4. Register Scheduled Task "SilverDictServe" at logon-of-Student.
#   5. Replace Student desktop "Từ Điển.lnk" to launch Firefox at
#      http://localhost:2628/dict.html (was: GoldenDict.exe).
#
# Run from elevated PowerShell:
#   & "<USB>:\Scripts\patches\Fix-SilverDict.ps1"
#
# Each stage runs in its own try/catch so a partial failure (e.g., bundle
# missing from USB) doesn't mask success of the others. Exit 0 if all stages
# OK, 1 if any stage failed.

param(
    [string]$StudentProfile     = "C:\Users\Student",
    [string]$SilverInstallDir   = "C:\Program Files\SilverDict",
    [string]$SilverBundleSource = (Join-Path $PSScriptRoot "..\..\Installers\SilverDict\SilverDict"),
    [string]$SilverConfigSource = (Join-Path $PSScriptRoot "..\..\Config\silverdict-config"),
    [string]$GoldenDictContent  = "C:\Program Files (x86)\GoldenDict\content",
    [int]$SilverPort            = 2628
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Fix-SilverDict: Student profile not found at $StudentProfile - skipping all stages."
    exit 0
}

$results = [ordered]@{}

# --------------------------------------------------------------------------
# Stage 1: Install SilverDict bundle to Program Files, replace NVDA-friendly
# HTML files, stage StarDict files into the source dir.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 1/5] Installing SilverDict bundle to $SilverInstallDir..."
try {
    if (-not (Test-Path $SilverBundleSource)) {
        throw "SilverDict bundle not found at $SilverBundleSource (run 0-Download-Installers.ps1 first)"
    }

    # Stop any running SilverDict so we can replace the bundled python.exe
    # without sharing-violation errors. The scheduled task respawns it later
    # via Start-ScheduledTask at end of script.
    $silverProcs = Get-Process -Name "pythonw","python" -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like "$SilverInstallDir\*" }
    if ($silverProcs) {
        Write-Host "  Stopping SilverDict (PIDs: $($silverProcs.Id -join ', ')) so bundle can be replaced..."
        Stop-Process -InputObject $silverProcs -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    if (-not (Test-Path $SilverInstallDir)) {
        New-Item -Path $SilverInstallDir -ItemType Directory -Force | Out-Null
    }

    # /E (no /MIR/PURGE) — additive copy, idempotent.
    $null = robocopy $SilverBundleSource $SilverInstallDir /E /R:1 /W:1 /NJH /NJS /NFL /NDL
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed (exit $LASTEXITCODE) copying $SilverBundleSource to $SilverInstallDir"
    }

    # NVDA-friendly HTML overrides.
    $htmlReplacements = @(
        @{ Source = (Join-Path $SilverConfigSource "build\dict.html");                    Dest = (Join-Path $SilverInstallDir "program\server\build\dict.html") },
        @{ Source = (Join-Path $SilverConfigSource "templates\articles_standalone.html"); Dest = (Join-Path $SilverInstallDir "program\server\app\templates\articles_standalone.html") },
        @{ Source = (Join-Path $SilverConfigSource "templates\suggestions.html");         Dest = (Join-Path $SilverInstallDir "program\server\app\templates\suggestions.html") }
    )
    $htmlReplaced = 0
    foreach ($r in $htmlReplacements) {
        if (Test-Path $r.Source) {
            Copy-Item -Path $r.Source -Destination $r.Dest -Force
            $htmlReplaced++
        } else {
            Write-Host "  [WARN] HTML override missing: $($r.Source)"
        }
    }

    # Stage StarDict files for SilverDict's source dir.
    $silverSourceDir = Join-Path $SilverInstallDir "source"
    if (-not (Test-Path $silverSourceDir)) {
        New-Item -Path $silverSourceDir -ItemType Directory -Force | Out-Null
    }
    $stardictFiles = @(
        "$GoldenDictContent\en-vi\star_anhviet.ifo",
        "$GoldenDictContent\en-vi\star_anhviet.idx",
        "$GoldenDictContent\en-vi\star_anhviet.dict.dz",
        "$GoldenDictContent\vi-en\star_vietanh.ifo",
        "$GoldenDictContent\vi-en\star_vietanh.idx",
        "$GoldenDictContent\vi-en\star_vietanh.dict.dz"
    )
    $copied = 0
    foreach ($f in $stardictFiles) {
        if (Test-Path $f) {
            Copy-Item -Path $f -Destination $silverSourceDir -Force
            $copied++
        }
    }

    Write-Host "  [OK] bundle installed, $htmlReplaced/3 HTML overrides applied, $copied/$($stardictFiles.Count) StarDict files staged"
    $results['silverdict bundle'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['silverdict bundle'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 2: Pre-seed Student's ~/.silverdict/ yamls so the dict list is ready
# at first server start (no manual UI scan needed).
# --------------------------------------------------------------------------
Write-Host "`n[Stage 2/5] Pre-seeding Student .silverdict yaml files..."
try {
    $studentSilverDir = Join-Path $StudentProfile ".silverdict"
    if (-not (Test-Path $studentSilverDir)) {
        New-Item -Path $studentSilverDir -ItemType Directory -Force | Out-Null
    }

    # IMPORTANT: this script must be saved with a UTF-8 BOM. PowerShell 5.1
    # reads .ps1 files as ANSI (CP1252) by default; without the BOM, the
    # literal Vietnamese chars below ("Từ điển Anh-Việt") get read as garbled
    # CP1252 codepoints, then Set-Content -Encoding UTF8 re-encodes those
    # garbage codepoints to UTF-8, double-encoding the bytes. The BOM tells
    # PS5.1 the file is UTF-8 and the literals round-trip correctly.
    $dictionariesYaml = @"
- dictionary_display_name: "Từ điển Anh-Việt"
  dictionary_filename: 'C:\Program Files\SilverDict\source\star_anhviet.ifo'
  dictionary_format: StarDict (.ifo)
  dictionary_name: __star_anhviet
- dictionary_display_name: "Từ điển Việt-Anh"
  dictionary_filename: 'C:\Program Files\SilverDict\source\star_vietanh.ifo'
  dictionary_format: StarDict (.ifo)
  dictionary_name: __star_vietanh
"@
    # The "Memory" group is special-cased in SilverDict (settings.py:130 +
    # dictionaries.py:129): if ANY dict is in this group, the startup loader
    # uses a serial for-loop instead of ThreadPoolExecutor.map. That matters
    # because executor.map silently swallows exceptions in worker threads —
    # and the bigger 387k-word star_anhviet dict (~9 MB .idx) loses the
    # parallel-load race, so it gets dropped from self._dictionaries with no
    # log entry, causing /api/lookup/__star_anhviet/X to KeyError. Putting
    # both dicts in "Memory" forces serial load AND keeps both indexes in RAM
    # for sub-ms lookups (~60 MB RAM total — comfortable on 8GB+ laptops).
    $groupsYaml = @"
- lang: !!set {}
  name: Default Group
- lang: !!set {}
  name: Memory
"@
    $junctionYaml = @"
__star_anhviet: !!set
  Default Group: null
  Memory: null
__star_vietanh: !!set
  Default Group: null
  Memory: null
"@
    $miscYaml = @"
history_size: 100
num_suggestions: 10
sources:
- 'C:\Program Files\SilverDict\source'
"@
    $preferencesYaml = @"
listening_address: 127.0.0.1
stardict_load_syns: false
suggestions_mode: right-side
ngram_stores_keys: false
running_mode: normal
chinese_preference: none
check_for_updates: false
full_text_search_diacritic_insensitive: false
autoplay_audio: false
"@
    Set-Content -Path (Join-Path $studentSilverDir "dictionaries.yaml")   -Value $dictionariesYaml -Encoding UTF8 -Force
    Set-Content -Path (Join-Path $studentSilverDir "groups.yaml")         -Value $groupsYaml       -Encoding UTF8 -Force
    Set-Content -Path (Join-Path $studentSilverDir "junction_table.yaml") -Value $junctionYaml     -Encoding UTF8 -Force
    Set-Content -Path (Join-Path $studentSilverDir "misc.yaml")           -Value $miscYaml         -Encoding UTF8 -Force
    Set-Content -Path (Join-Path $studentSilverDir "preferences.yaml")    -Value $preferencesYaml  -Encoding UTF8 -Force

    icacls $studentSilverDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

    Write-Host "  [OK] 5 yamls written, ACL granted Student modify"
    $results['student yamls'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['student yamls'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 3: Hidden VBS launcher. wscript is non-console subsystem and pythonw.exe
# is the console-less Python; together they keep SilverDict invisible for the
# lifetime of the server.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 3/5] Writing hidden launcher script..."
try {
    $silverPythonw  = Join-Path $SilverInstallDir "env\pythonw.exe"
    $silverServerPy = Join-Path $SilverInstallDir "program\server\server.py"
    $vbsPath        = Join-Path $SilverInstallDir "start-silverdict.vbs"

    if (-not (Test-Path $silverPythonw)) {
        throw "pythonw.exe not found at $silverPythonw - bundle install incomplete"
    }
    if (-not (Test-Path $silverServerPy)) {
        throw "server.py not found at $silverServerPy - bundle install incomplete"
    }

    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$silverPythonw"" -Xutf8 ""$silverServerPy"" 127.0.0.1:$SilverPort", 0, False
Set WshShell = Nothing
"@
    Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
    Write-Host "  [OK] $vbsPath written"
    $results['vbs launcher'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['vbs launcher'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 4: Register the Scheduled Task that fires at every Student logon.
# Restart 3x with a 1-minute interval if SilverDict crashes. ExecutionTimeLimit=0
# means "no time limit" (long-running service).
# --------------------------------------------------------------------------
Write-Host "`n[Stage 4/5] Registering 'SilverDictServe' scheduled task..."
try {
    $vbsPath = Join-Path $SilverInstallDir "start-silverdict.vbs"
    $studentUser = "$env:COMPUTERNAME\Student"
    $action    = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $studentUser
    $principal = New-ScheduledTaskPrincipal -UserId $studentUser -LogonType Interactive
    $settings  = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Days 0) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName "SilverDictServe" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "  [OK] Task 'SilverDictServe' registered (trigger: at logon of Student)"
    $results['scheduled task'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['scheduled task'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 5: Rewrite Student desktop "Từ Điển.lnk" to launch Firefox + URL.
# Targeting firefox.exe directly bypasses the system default-browser setting
# (a .url file would honor it; a .lnk pointing at firefox.exe doesn't).
# Icon stays as GoldenDict's so students recognize the shortcut.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 5/5] Updating 'Từ Điển' desktop shortcut to use Firefox..."
try {
    $firefoxPath = $null
    $appPathsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe"
    if (Test-Path $appPathsKey) {
        $firefoxPath = (Get-Item $appPathsKey).GetValue("")
    }
    if (-not $firefoxPath -or -not (Test-Path $firefoxPath)) {
        foreach ($p in @("C:\Program Files\Mozilla Firefox\firefox.exe","C:\Program Files (x86)\Mozilla Firefox\firefox.exe")) {
            if (Test-Path $p) { $firefoxPath = $p; break }
        }
    }
    if (-not $firefoxPath) {
        throw "Firefox not found - cannot update Từ Điển shortcut"
    }

    $publicDesktop = "C:\Users\Public\Desktop"
    $finalLnkPath  = Join-Path $publicDesktop "Từ Điển.lnk"
    $tempLnkPath   = Join-Path $publicDesktop "TuDien-NVDA-temp.lnk"

    # Clean any prior name variants. WScript.Shell.CreateShortcut goes through
    # ANSI COM marshaling: chars outside CP1252 (e.g. ừ U+1EEB, ể U+1EC3, ệ
    # U+1EC7, đ U+0111) get converted to "?", so older runs may have left a
    # mojibake'd "Tá»« Äiá»ƒn.lnk" or a "?"-named file that won't even save.
    Get-ChildItem $publicDesktop -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @("Từ Điển.lnk","Tá»« Äiá»ƒn.lnk","T? Ði?n.lnk","TuDien-NVDA-temp.lnk")
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Prefer a real .ico from the GoldenDict install; fall back to firefox itself.
    $goldenDictIco = $null
    foreach ($p in @("C:\Program Files (x86)\GoldenDict\icons\programicon.ico","C:\Program Files\GoldenDict\icons\programicon.ico","C:\Program Files (x86)\GoldenDict\GoldenDict.exe","C:\Program Files\GoldenDict\GoldenDict.exe")) {
        if (Test-Path $p) { $goldenDictIco = $p; break }
    }
    $iconLoc = if ($goldenDictIco) { "$goldenDictIco,0" } else { "$firefoxPath,0" }

    # Create the shortcut at an ASCII-safe temp path so CreateShortcut/Save
    # don't trip on the non-CP1252 chars in the final filename. Then Move-Item
    # to the Unicode final path — Move-Item uses MoveFileW (Unicode Win32 API)
    # and handles non-CP1252 names correctly. The .lnk's INTERNAL fields
    # (TargetPath, Description) are stored as Unicode by the COM object so
    # they round-trip fine even with non-CP1252 chars.
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($tempLnkPath)
    $shortcut.TargetPath        = $firefoxPath
    $shortcut.Arguments         = "http://localhost:$SilverPort/dict.html"
    $shortcut.WorkingDirectory  = Split-Path $firefoxPath -Parent
    $shortcut.IconLocation      = $iconLoc
    $shortcut.Description       = "Từ điển Anh-Việt (offline) - opens in Firefox so NVDA browse mode works"
    $shortcut.Save()

    Move-Item -Path $tempLnkPath -Destination $finalLnkPath -Force
    Write-Host "  [OK] Từ Điển.lnk -> $firefoxPath http://localhost:$SilverPort/dict.html"
    $results['desktop shortcut'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['desktop shortcut'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host "`n=== Fix-SilverDict Summary ==="
foreach ($key in $results.Keys) {
    $status = $results[$key]
    $color = if ($status -eq 'OK') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-22} {1}" -f $key, $status) -ForegroundColor $color
}

# Best-effort: kick the task immediately if Student is the active interactive
# user so the server is live without waiting for a logout. Quietly skip if not.
if ($results['scheduled task'] -eq 'OK') {
    try {
        $loggedOn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if ($loggedOn -like "*\Student") {
            Start-ScheduledTask -TaskName "SilverDictServe" -ErrorAction SilentlyContinue
            Write-Host "`nSilverDictServe started (Student is logged on - server is live now on http://localhost:$SilverPort/dict.html). First lookup may take ~30s while indexes build."
        } else {
            Write-Host "`nSilverDictServe will start at next Student logon. First lookup after that may take ~30s while indexes build."
        }
    } catch {}
}

$failed = ($results.Values | Where-Object { $_ -ne 'OK' }).Count
exit $(if ($failed -eq 0) { 0 } else { 1 })
