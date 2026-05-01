# Install-Readmate-Web.ps1
# Shared installer for the readmate-web NVDA-accessible EPUB reader. Mirrors
# the kiwix-serve / SilverDict pattern: a tiny Python server runs at
# 127.0.0.1:21810, the Student desktop "Đọc Sách" shortcut opens Firefox
# at the localhost URL, and NVDA browse mode reads foliate-js' rendered
# pages natively. SM Readmate stays installed and continues to manage the
# library tree at %APPDATA%\SaoMai\SM Readmate\file - we just read it.
#
# Used by both:
#   - Configure-Laptop.ps1 Step 35d (initial deploy from a DEPLOY_ USB)
#   - Scripts\patches\Fix-Readmate-Web.ps1 (post-deploy USB-walkup field patch)
#
# What it does (idempotent - safe to re-run):
#   1. Stop ReadmateServe scheduled task if it is running so we can replace
#      readmate_web.py + foliate-js without sharing-violation errors.
#   2. robocopy <usb>\Config\readmate-web\* to C:\LabTools\readmate-web\
#      using /E (additive) - never /MIR or /PURGE.
#   3. Write C:\LabTools\readmate-web\start-readmate-web.vbs (hidden launcher).
#   4. Verify C:\Program Files\SilverDict\env\python.exe is present (it is
#      shipped by SilverDict step 35b - if missing, deploy is incomplete).
#   5. Register/replace the ReadmateServe scheduled task at Student logon.
#   6. Refresh the "Đọc Sách.lnk" desktop shortcut (Unicode filename, so
#      we use the WshShell + ASCII temp path + Move-Item dance to dodge
#      WScript.Shell's CP1252-only COM marshaling).
#   7. Best-effort: kick the task immediately so the deploy is testable
#      without logoff/logon when Student is already logged in.
#
# Returns: exits 0 on success, non-zero if any required stage failed.
#
# IMPORTANT: this file is saved with a UTF-8 BOM so the literal Vietnamese
# chars below ("Đọc Sách", "Đọc sách EPUB ...") round-trip correctly under
# PowerShell 5.1 (which would otherwise read .ps1 as ANSI/CP1252 and mangle
# them on disk).

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FromUSB
)

$ErrorActionPreference = 'Continue'

$readmateInstallDir = "C:\LabTools\readmate-web"
$readmateSource     = Join-Path $FromUSB "Config\readmate-web"
$silverPython       = "C:\Program Files\SilverDict\env\python.exe"
$readmatePy         = Join-Path $readmateInstallDir "readmate_web.py"
$vbsPath            = Join-Path $readmateInstallDir "start-readmate-web.vbs"
$studentDesktop     = "C:\Users\Student\Desktop"
$taskName           = "ReadmateServe"
$readmatePort       = 21810

$results = [ordered]@{}

Write-Host ""
Write-Host "Install-Readmate-Web: source = $readmateSource"
Write-Host "Install-Readmate-Web: target = $readmateInstallDir"

if (-not (Test-Path $readmateSource)) {
    Write-Host "[FAIL] readmate-web source not found at $readmateSource" -ForegroundColor Red
    Write-Host "       Make sure you are running from a fully-synced DEPLOY_ USB or repo clone." -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------------
# Stage 1: Stop running ReadmateServe so files can be replaced cleanly.
# Get-ScheduledTask returns nothing if the task is absent; Stop-ScheduledTask
# is a no-op when the task is not running. Both are quietly idempotent.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 1/6] Stopping ReadmateServe (if running) so files can be replaced..."
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    # Belt-and-braces: the task may have a python.exe child still holding the
    # foliate-js JS files. Match by image path so we only kill our own server,
    # not other unrelated python processes (e.g. SilverDict's pythonw.exe).
    $readmateProcs = Get-Process -Name "python","pythonw" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainModule -and
            ($_.MainModule.FileName -ieq $silverPython) -and
            ($_.CommandLine -like "*readmate_web.py*" -or
             ($_.StartInfo -and $_.StartInfo.Arguments -like "*readmate_web.py*"))
        }
    # The CommandLine filter above is best-effort (Get-Process doesn't always
    # populate it). Fall back to CIM for the authoritative match.
    $cimProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*readmate_web.py*" }
    foreach ($p in $cimProcs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500

    Write-Host "  [OK] task stopped (or was not running)"
    $results['stop task'] = 'OK'
} catch {
    Write-Host "  [WARN] could not stop existing task: $($_.Exception.Message)" -ForegroundColor Yellow
    $results['stop task'] = 'OK'  # Non-fatal
}

# --------------------------------------------------------------------------
# Stage 2: Mirror Config\readmate-web\* into C:\LabTools\readmate-web\.
# /E (no /MIR, no /PURGE) - additive copy. Preserves any local diagnostic
# files placed in the install dir; only adds/updates from source.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 2/6] Robocopying readmate-web tree to $readmateInstallDir..."
try {
    if (-not (Test-Path $readmateInstallDir)) {
        New-Item -Path $readmateInstallDir -ItemType Directory -Force | Out-Null
    }

    $null = robocopy $readmateSource $readmateInstallDir /E /R:1 /W:1 /NJH /NJS /NFL /NDL
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed (exit $LASTEXITCODE) copying $readmateSource to $readmateInstallDir"
    }

    if (-not (Test-Path $readmatePy)) {
        throw "readmate_web.py missing after robocopy: $readmatePy"
    }

    # Reset robocopy's exit code so downstream LASTEXITCODE checks (e.g. in
    # Configure-Laptop) don't see a stale 1 = "files copied successfully".
    $global:LASTEXITCODE = 0

    Write-Host "  [OK] tree copied"
    $results['robocopy tree'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    $results['robocopy tree'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 3: Hidden VBS launcher. wscript is non-console subsystem, so the
# spawned python.exe inherits no visible console - the server is invisible
# for its lifetime. Same pattern as start-kiwix-serve.vbs / start-silverdict.vbs.
# Note we use python.exe (not pythonw.exe) because readmate_web.py prints
# startup messages and we want stderr/stdout going to the wscript bit-bucket
# rather than failing on a missing console handle.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 3/6] Writing hidden launcher script..."
try {
    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$silverPython"" ""$readmatePy""", 0, False
Set WshShell = Nothing
"@
    Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
    Write-Host "  [OK] $vbsPath written"
    $results['vbs launcher'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    $results['vbs launcher'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 4: Verify the SilverDict-bundled python is present. We deliberately
# reuse SilverDict's Python 3.12.1 instead of shipping a second copy - same
# version, same site-packages baseline, half the disk. If it is missing, the
# laptop has a broken/incomplete deploy and the task would just keep crash-
# looping; bail loudly and skip task registration so the failure is visible.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 4/6] Verifying SilverDict-bundled python at $silverPython..."
if (-not (Test-Path $silverPython)) {
    Write-Host "  [WARN] python.exe not found at $silverPython" -ForegroundColor Yellow
    Write-Host "         SilverDict step (35b) may not have run - skipping ReadmateServe task." -ForegroundColor Yellow
    $results['python check'] = 'SKIP'
    $results['scheduled task'] = 'SKIP'
} else {
    Write-Host "  [OK] python.exe present"
    $results['python check'] = 'OK'

    # ----------------------------------------------------------------------
    # Stage 5: Register the ReadmateServe scheduled task. AtLogOn for the
    # Student account, restart 3x with a 1-minute interval if the server
    # crashes, ExecutionTimeLimit=0 = no time limit (long-running service).
    # Limited RunLevel = no UAC elevation prompt at logon. -Force replaces
    # any prior registration cleanly.
    # ----------------------------------------------------------------------
    Write-Host ""
    Write-Host "[Stage 5/6] Registering 'ReadmateServe' scheduled task..."
    try {
        $studentUser = "$env:COMPUTERNAME\Student"
        $action      = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
        $trigger     = New-ScheduledTaskTrigger -AtLogOn -User $studentUser
        $principal   = New-ScheduledTaskPrincipal -UserId $studentUser -LogonType Interactive -RunLevel Limited
        $settings    = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Days 0) `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -MultipleInstances IgnoreNew

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

        Write-Host "  [OK] Task '$taskName' registered (trigger: at logon of Student, RunLevel Limited)"
        $results['scheduled task'] = 'OK'
    } catch {
        Write-Host "  [FAIL] $_" -ForegroundColor Red
        $results['scheduled task'] = 'FAIL'
    }
}

# --------------------------------------------------------------------------
# Stage 6: Refresh the Student desktop "Đọc Sách.lnk" shortcut to launch
# Firefox at http://localhost:21810/. The icon is the SM Readmate exe so
# students recognize the shortcut. Targeting firefox.exe directly bypasses
# the system default-browser setting (a .url file would honor it; a .lnk
# pointing at firefox.exe doesn't).
#
# WScript.Shell.CreateShortcut goes through ANSI COM marshaling: chars
# outside CP1252 (e.g. Đ U+0110, ọ U+1ECD, ú U+00FA, á U+00E1, ch in
# "Sách") get converted to "?", so we save to an ASCII temp path first,
# then Move-Item to the Unicode final path (Move-Item uses the Unicode
# Win32 MoveFileW API and handles non-CP1252 names correctly).
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 6/6] Updating 'Đọc Sách' desktop shortcut..."
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
        throw "Firefox not found - cannot create Đọc Sách shortcut"
    }

    if (-not (Test-Path $studentDesktop)) {
        New-Item -Path $studentDesktop -ItemType Directory -Force | Out-Null
    }

    $finalLnkPath = Join-Path $studentDesktop "Đọc Sách.lnk"
    $tempLnkPath  = Join-Path $studentDesktop "DocSach-NVDA-temp.lnk"

    # Clean prior name variants. Older runs that hit CP1252 marshaling may
    # have left a "?"-named or mojibake'd .lnk that Get-ChildItem can still
    # see and -Force-delete via its FullName.
    Get-ChildItem $studentDesktop -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @("Đọc Sách.lnk","Äá»c SÃ¡ch.lnk","? S?ch.lnk","DocSach-NVDA-temp.lnk","Doc Sach.lnk")
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Prefer SM Readmate's own exe icon so the shortcut visually matches
    # what students associate with reading. Fall back to firefox if the
    # SM Readmate install is missing on this machine.
    $smReadmateExe = "C:\Program Files\SaoMai\sm_readmate\sm_readmate.exe"
    $iconLoc = if (Test-Path $smReadmateExe) { "$smReadmateExe,0" } else { "$firefoxPath,0" }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($tempLnkPath)
    $shortcut.TargetPath       = $firefoxPath
    $shortcut.Arguments        = "http://localhost:$readmatePort/"
    $shortcut.WorkingDirectory = Split-Path $firefoxPath -Parent
    $shortcut.IconLocation     = $iconLoc
    $shortcut.Description      = "Đọc sách EPUB qua trình duyệt — NVDA-friendly"
    $shortcut.Save()

    Move-Item -Path $tempLnkPath -Destination $finalLnkPath -Force
    Write-Host "  [OK] $finalLnkPath -> $firefoxPath http://localhost:$readmatePort/"
    $results['desktop shortcut'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    $results['desktop shortcut'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Best-effort: kick the task immediately if Student is the active interactive
# user so the server is live without waiting for a logout. Quietly skip if
# Student is not currently logged in (e.g. running from Admin during deploy).
# --------------------------------------------------------------------------
if ($results['scheduled task'] -eq 'OK') {
    try {
        $loggedOn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if ($loggedOn -like "*\Student") {
            Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "ReadmateServe started (Student is logged on - server is live now on http://localhost:$readmatePort/)."
        } else {
            Write-Host ""
            Write-Host "ReadmateServe will start at next Student logon."
        }
    } catch {}
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Install-Readmate-Web Summary ==="
foreach ($key in $results.Keys) {
    $status = $results[$key]
    $color = if ($status -eq 'OK' -or $status -eq 'SKIP') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-22} {1}" -f $key, $status) -ForegroundColor $color
}

$failed = ($results.Values | Where-Object { $_ -eq 'FAIL' }).Count
exit $(if ($failed -eq 0) { 0 } else { 1 })
