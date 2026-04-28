# Fix-Kiwix-Library.ps1
# USB-walkup patch for already-deployed laptops. Five idempotent stages:
#
#   1. Deploy canonical library.xml to Student profile + restore Modify ACL.
#      Without `size`, kiwix-desktop 2.5.1 lists books with 0 bytes or hides them.
#   2. Copy kiwix-serve.exe from <USB>\Installers\Kiwix\ to C:\Program Files\Kiwix\.
#   3. Write C:\Program Files\Kiwix\start-kiwix-serve.vbs (hidden launcher).
#   4. Register Scheduled Task "KiwixServe" at logon-of-Student → wscript runs the .vbs.
#   5. Replace Student desktop "Wikipedia.lnk" to launch Firefox at http://localhost:21808.
#
# After this runs, kiwix-serve serves the same ZIM files over localhost:21808 and the
# desktop "Wikipedia" shortcut opens Firefox to that URL. NVDA browse mode works
# natively in Firefox - NVDA cannot browse-mode kiwix-desktop's QtWebEngine view
# (NVDA issue #10838). kiwix-desktop stays installed for sighted users via Start Menu.
#
# Run from elevated PowerShell:
#   & "<USB>:\Scripts\patches\Fix-Kiwix-Library.ps1"
#
# Each stage runs in its own try/catch so a partial failure (e.g., kiwix-serve.exe
# missing from USB) doesn't mask success of the others. Exit 0 if all stages OK,
# 1 if any stage failed.

param(
    [string]$StudentProfile   = "C:\Users\Student",
    [string]$LibrarySource    = (Join-Path $PSScriptRoot "..\..\Config\kiwix-config\library.xml"),
    [string]$KiwixInstallDir  = "C:\Program Files\Kiwix",
    [string]$KiwixServeSource = (Join-Path $PSScriptRoot "..\..\Installers\Kiwix\kiwix-serve.exe"),
    [int]$KiwixServePort      = 21808
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Fix-Kiwix-Library: Student profile not found at $StudentProfile - skipping all stages."
    exit 0
}

$results = [ordered]@{}

# --------------------------------------------------------------------------
# Stage 1: Deploy library.xml so kiwix-desktop GUI shows books with sizes.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 1/5] Deploying library.xml to Student profile..."
try {
    if (-not (Test-Path $LibrarySource)) {
        throw "Source library.xml not found at $LibrarySource"
    }
    $libraryDir  = Join-Path $StudentProfile "AppData\Roaming\kiwix-desktop"
    $libraryFile = Join-Path $libraryDir "library.xml"
    if (-not (Test-Path $libraryDir)) {
        New-Item -Path $libraryDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $LibrarySource -Destination $libraryFile -Force
    icacls $libraryDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null
    Write-Host "  [OK] library.xml deployed ($((Get-Item $libraryFile).Length) bytes)"
    $results['library.xml'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['library.xml'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 2: Copy kiwix-serve.exe alongside kiwix-desktop.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 2/5] Installing kiwix-serve.exe to $KiwixInstallDir..."
try {
    if (-not (Test-Path $KiwixInstallDir)) {
        throw "$KiwixInstallDir not found - is kiwix-desktop installed?"
    }
    if (-not (Test-Path $KiwixServeSource)) {
        throw "kiwix-serve.exe source not found at $KiwixServeSource (run 0-Download-Installers.ps1 first)"
    }
    $kiwixServeDest = Join-Path $KiwixInstallDir "kiwix-serve.exe"
    Copy-Item -Path $KiwixServeSource -Destination $kiwixServeDest -Force
    $sizeMB = [math]::Round((Get-Item $kiwixServeDest).Length / 1MB, 1)
    Write-Host "  [OK] kiwix-serve.exe installed ($sizeMB MB)"
    $results['kiwix-serve.exe'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['kiwix-serve.exe'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 3: Write hidden VBS launcher. wscript.exe is non-console subsystem,
# and the .vbs's Run with bWindowStyle=0 + bWaitOnReturn=False keeps the
# spawned kiwix-serve process invisible and detached. Direct task-action
# launches of console apps would otherwise leave a visible console window
# open for the lifetime of the server.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 3/5] Writing hidden launcher script..."
try {
    $libraryPath    = Join-Path $StudentProfile "AppData\Roaming\kiwix-desktop\library.xml"
    $kiwixServePath = Join-Path $KiwixInstallDir "kiwix-serve.exe"
    $vbsPath        = Join-Path $KiwixInstallDir "start-kiwix-serve.vbs"
    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$kiwixServePath"" --address=127.0.0.1 --port=$KiwixServePort --library ""$libraryPath""", 0, False
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
# Restart 3x with a 1-minute interval if kiwix-serve crashes. ExecutionTimeLimit=0
# means "no time limit" (long-running service).
# --------------------------------------------------------------------------
Write-Host "`n[Stage 4/5] Registering 'KiwixServe' scheduled task..."
try {
    $vbsPath = Join-Path $KiwixInstallDir "start-kiwix-serve.vbs"
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
    Register-ScheduledTask -TaskName "KiwixServe" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "  [OK] Task 'KiwixServe' registered (trigger: at logon of Student)"
    $results['scheduled task'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['scheduled task'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 5: Rewrite Student desktop "Wikipedia.lnk" to launch Firefox + URL.
# Targeting firefox.exe directly bypasses the system default-browser setting
# (a .url file would honor it; a .lnk pointing at firefox.exe doesn't).
# Icon stays as kiwix-desktop's so students recognize the shortcut.
# --------------------------------------------------------------------------
Write-Host "`n[Stage 5/5] Updating 'Wikipedia' desktop shortcut to use Firefox..."
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
        throw "Firefox not found - cannot update Wikipedia shortcut"
    }

    $publicDesktop = "C:\Users\Public\Desktop"
    $lnkPath = Join-Path $publicDesktop "Wikipedia.lnk"
    if (Test-Path $lnkPath) { Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue }

    $kiwixIcon = Join-Path $KiwixInstallDir "kiwix-desktop.exe"
    $iconLoc = if (Test-Path $kiwixIcon) { "$kiwixIcon,0" } else { "$firefoxPath,0" }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath        = $firefoxPath
    $shortcut.Arguments         = "http://localhost:$KiwixServePort/"
    $shortcut.WorkingDirectory  = Split-Path $firefoxPath -Parent
    $shortcut.IconLocation      = $iconLoc
    $shortcut.Description       = "Wikipedia (offline) - opens in Firefox so NVDA browse mode works"
    $shortcut.Save()
    Write-Host "  [OK] Wikipedia.lnk -> $firefoxPath http://localhost:$KiwixServePort/"
    $results['desktop shortcut'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_"
    $results['desktop shortcut'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host "`n=== Fix-Kiwix-Library Summary ==="
foreach ($key in $results.Keys) {
    $status = $results[$key]
    $color = if ($status -eq 'OK') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-20} {1}" -f $key, $status) -ForegroundColor $color
}

# Best-effort: kick the task immediately if Student is the active interactive user
# so the patch is live without waiting for a logout. Quietly skip if not.
if ($results['scheduled task'] -eq 'OK') {
    try {
        $loggedOn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if ($loggedOn -like "*\Student") {
            Start-ScheduledTask -TaskName "KiwixServe" -ErrorAction SilentlyContinue
            Write-Host "`nKiwixServe started (Student is logged on - server is live now on http://localhost:$KiwixServePort/)"
        } else {
            Write-Host "`nKiwixServe will start at next Student logon."
        }
    } catch {}
}

$failed = ($results.Values | Where-Object { $_ -ne 'OK' }).Count
exit $(if ($failed -eq 0) { 0 } else { 1 })
