# Apply-All-Field-Patches.ps1
#
# Post-deployment field patch for already-deployed Vietnam lab laptops.
# Plug a DEPLOY_ USB into the laptop and run:
#
#   <USB>:\Scripts\patches\Apply-All-Field-Patches.ps1
#
# Self-elevates if not already Administrator. Runs the five field patches in
# sequence, captures full output to C:\LabTools\field-patch-<timestamp>\,
# prints a per-step PASS/FAIL summary at the end, and exits non-zero if any
# step failed. Every child script is idempotent — safe to re-run.
#
# Steps (in order):
#   1. Fix-Kiwix-Library.ps1       — library.xml, kiwix-serve, scheduled task,
#                                    Wikipedia.lnk → Firefox+localhost
#   2. Patch-GoldenDict-Paths.ps1  — dictionary path, hide side panes,
#                                    disable scan popup
#   3. Patch-Readmate-Prefs.ps1    — Microsoft An TTS, no double-read,
#                                    disable auto-play
#   4. stu-resolver/Apply-Patch.ps1 — STU- USB → drive D: pinning + Office,
#                                    Firefox, Audacity defaults
#   5. 3-Configure-NVDA.ps1        — Student nvda.ini + addons + SAPI5 mirror
#                                    + UniKey + RHVoice/manifest patches

[CmdletBinding()]
param(
    # Internal flag: set automatically by the self-elevation relaunch so the
    # newly-spawned admin window pauses at the end (otherwise it would close
    # immediately and the field tech wouldn't see the summary).
    [switch]$Relaunched
)

$ErrorActionPreference = 'Continue'

# --- Self-elevation --------------------------------------------------------

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Apply-All-Field-Patches: not elevated. Relaunching as Administrator..." -ForegroundColor Yellow
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Relaunched'
    )
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "Elevation cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# --- Path resolution -------------------------------------------------------

# Wrapper lives at <USB>\Scripts\patches\Apply-All-Field-Patches.ps1
$patchesDir = $PSScriptRoot                     # ...\Scripts\patches
$scriptsDir = Split-Path -Parent $PSScriptRoot  # ...\Scripts

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = "C:\LabTools\field-patch-$timestamp"
if (-not (Test-Path 'C:\LabTools')) {
    New-Item -Path 'C:\LabTools' -ItemType Directory -Force | Out-Null
}
New-Item -Path $logDir -ItemType Directory -Force | Out-Null

$transcriptPath = Join-Path $logDir 'full-run.log'
Start-Transcript -Path $transcriptPath -IncludeInvocationHeader | Out-Null

# --- Step definitions ------------------------------------------------------

$steps = @(
    @{ Name = 'Fix-Kiwix-Library';      Path = Join-Path $patchesDir 'Fix-Kiwix-Library.ps1' }
    @{ Name = 'Patch-GoldenDict-Paths'; Path = Join-Path $patchesDir 'Patch-GoldenDict-Paths.ps1' }
    @{ Name = 'Patch-Readmate-Prefs';   Path = Join-Path $patchesDir 'Patch-Readmate-Prefs.ps1' }
    @{ Name = 'stu-resolver';           Path = Join-Path $patchesDir 'stu-resolver\Apply-Patch.ps1' }
    @{ Name = '3-Configure-NVDA';       Path = Join-Path $scriptsDir '3-Configure-NVDA.ps1' }
)

# --- Banner ----------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Vietnam Lab - Post-Deployment Field Patch" -ForegroundColor Cyan
Write-Host "  Host:  $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Time:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Logs:  $logDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- Pre-flight: every script must exist before we start --------------------

$missing = @()
foreach ($s in $steps) {
    if (-not (Test-Path $s.Path)) { $missing += $s.Path }
}
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Required script(s) missing - aborting before any change is made:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Verify you are running from a plugged DEPLOY_ USB and that the" -ForegroundColor Red
    Write-Host "USB has a complete Scripts/ tree." -ForegroundColor Red
    Stop-Transcript | Out-Null
    if ($Relaunched) { Read-Host "`nPress Enter to close" | Out-Null }
    exit 1
}

# Pre-flight: detect repo-clone misruns. The deployment USB carries a full
# Installers/ tree (binary blobs excluded from git per CLAUDE.md). If we're
# running from a local repo clone instead, Fix-Kiwix-Library will fail half-way
# with confusing errors. Fail loud BEFORE any patch touches the laptop.
$kiwixServeProbe = Join-Path (Split-Path -Parent $patchesDir) "..\Installers\Kiwix\kiwix-serve.exe"
if (-not (Test-Path $kiwixServeProbe)) {
    Write-Host ""
    Write-Host "ERROR: Installers\Kiwix\kiwix-serve.exe not found." -ForegroundColor Red
    Write-Host "Probed: $kiwixServeProbe" -ForegroundColor Red
    Write-Host ""
    Write-Host "This wrapper must run from a DEPLOY_ USB drive that has the full" -ForegroundColor Red
    Write-Host "Installers/ tree. The git repo intentionally excludes binary blobs" -ForegroundColor Red
    Write-Host "(installers, ZIM files, ebooks) so it cannot be run from a clone." -ForegroundColor Red
    Write-Host ""
    Write-Host "Re-run from a DEPLOY_ USB:  <USB>:\Scripts\patches\Apply-All-Field-Patches.ps1" -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    if ($Relaunched) { Read-Host "`nPress Enter to close" | Out-Null }
    exit 1
}

# Pre-flight: warn the tech to close apps that the patches will Stop-Process.
# Patch-GoldenDict-Paths kills GoldenDict.exe; Patch-Readmate-Prefs kills
# sm_readmate.exe; 3-Configure-NVDA stops nvda.exe at start and restarts it at
# end (so addon directories can be replaced without sharing violations on the
# loaded .pyd files). Student can lose unsaved state in any of these apps.
Write-Host ""
Write-Host "Before continuing:" -ForegroundColor Yellow
Write-Host "  - Close GoldenDict if open (this patch will force-stop it)" -ForegroundColor Yellow
Write-Host "  - Close SM Readmate if open (this patch will force-stop it)" -ForegroundColor Yellow
Write-Host "  - NVDA will be stopped briefly during the addon refresh and restarted" -ForegroundColor Yellow
Write-Host "    automatically at the end (student loses speech for ~10 seconds)" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to start patching, or Ctrl+C to abort" | Out-Null

# --- Run each step ---------------------------------------------------------

$results = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor White
    Write-Host ("  [{0}/{1}] {2}" -f ($i + 1), $steps.Count, $s.Name) -ForegroundColor White
    Write-Host "  $($s.Path)" -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------" -ForegroundColor White

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = 0
    try {
        # Reset $LASTEXITCODE so a failure in a previous step doesn't leak
        # into this one's status if the child script never sets it.
        $global:LASTEXITCODE = 0
        & $s.Path
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    } catch {
        Write-Host "  EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }
    $sw.Stop()

    $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    $results.Add([PSCustomObject]@{
        Name     = $s.Name
        Status   = $status
        ExitCode = $exitCode
        Duration = '{0:N1}s' -f $sw.Elapsed.TotalSeconds
    })
}

# --- Summary ---------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1,-26} ({2,7}, exit={3})" -f $r.Status, $r.Name, $r.Duration, $r.ExitCode) -ForegroundColor $color
}

$failed = @($results | Where-Object Status -eq 'FAIL').Count

Write-Host ""
Write-Host "  Full log: $transcriptPath" -ForegroundColor DarkGray
Write-Host ""

if ($failed -eq 0) {
    Write-Host "  All field patches applied successfully." -ForegroundColor Green
} else {
    Write-Host "  $failed step(s) failed. Inspect the log for details." -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Stop-Transcript | Out-Null

if ($Relaunched) {
    Read-Host "Press Enter to close" | Out-Null
}

exit $(if ($failed -eq 0) { 0 } else { 1 })
