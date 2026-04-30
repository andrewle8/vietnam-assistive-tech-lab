# Remove-SMTT-Myanmar.ps1
# One-shot patch: removes the Myanmar (.mya) UI language files from the
# Sao Mai Typing Tutor's deployed data directory.
#
# Background: Configure-Laptop.ps1 Step 17e copies Config\smtt-data\* into
# %APPDATA%\SaoMai\SMTT for the Student profile. SMTT (and its siblings
# SMLB/SMUM) scan the Lang\ subfolder and offer every <basename>.<ISO 639-3>
# file as a UI language option in the F5 config dialog. The .mya files
# came in from the upstream Sao Mai distribution and surfaced "Myanmar" in
# the language picker — NVDA reads it aloud and it confused Vietnamese
# students. We don't ship Myanmar lessons, keyboard layouts, or help, so
# the language option has no purpose in this deployment.
#
# This is the field-patch equivalent of removing .mya from the repo's
# Config\smtt-data\Lang\ template. Configure-Laptop.ps1 Step 17e now also
# scrubs leftover .mya files at deploy time, so re-running the full
# configure on an already-deployed laptop achieves the same result.
#
# Run from any plugged DEPLOY_ USB:
#   <USB>:\Scripts\patches\Remove-SMTT-Myanmar.ps1
#
# Idempotent: re-running with no .mya files present is a silent no-op
# that exits 0.
#
# Run as Administrator. Stops SMTT.exe / SMLB.exe / SMUM.exe if running so
# the deletion isn't blocked by an open language-file handle (SMTT keeps
# the active .lang file open while the config dialog is on screen).

param(
    [string]$StudentProfile = "C:\Users\Student"
)

$ErrorActionPreference = "Stop"

$smttDir = Join-Path $StudentProfile "AppData\Roaming\SaoMai\SMTT"
$langDir = Join-Path $smttDir "Lang"
$iniPath = Join-Path $smttDir "SMTT.ini"

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Remove-SMTT-Myanmar: Student profile not found at $StudentProfile - skipping." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $langDir)) {
    Write-Host "Remove-SMTT-Myanmar: SMTT Lang folder not found at $langDir - nothing to do." -ForegroundColor Green
    exit 0
}

$myaFiles = @(Get-ChildItem -Path $langDir -Filter "*.mya" -File -ErrorAction SilentlyContinue)

# Defensive: if SMTT.ini has UILanguage=mya, switch to vie before deleting
# the .mya file so SMTT doesn't fail to load its UI strings on next launch.
# Only act when the value is exactly "mya" — leave eng / vie / anything
# else alone (some labs may have intentionally set English).
$iniNeedsFix = $false
$iniContent = $null
if (Test-Path $iniPath) {
    $iniContent = Get-Content -Path $iniPath -Raw -ErrorAction SilentlyContinue
    if ($iniContent -match '(?im)^\s*UILanguage\s*=\s*mya\s*$') {
        $iniNeedsFix = $true
    }
}

if ($myaFiles.Count -eq 0 -and -not $iniNeedsFix) {
    Write-Host "Remove-SMTT-Myanmar: no Myanmar files present and ini already clean. Nothing to do." -ForegroundColor Green
    exit 0
}

# Stop SMTT and siblings (SMLB Learn Braille, SMUM User Manager) — they all
# share the same Lang folder, so any of them holding a .mya file open would
# block the delete. Force-stop is fine: students don't have unsaved typing
# state in SMTT's session (results are committed to SMTT.smdb each lesson).
$procNames = @('SMTT', 'SMLB', 'SMUM')
$stopped = $false
foreach ($n in $procNames) {
    $proc = Get-Process -Name $n -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Remove-SMTT-Myanmar: stopping $n (PID $($proc.Id))..." -ForegroundColor Yellow
        Stop-Process -Name $n -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }
}
if ($stopped) {
    Start-Sleep -Milliseconds 1000
}

if ($iniNeedsFix) {
    Write-Host "Remove-SMTT-Myanmar: SMTT.ini has UILanguage=mya; switching to vie." -ForegroundColor Yellow
    $patched = $iniContent -replace '(?im)^(\s*UILanguage\s*=\s*)mya(\s*)$', '$1vie$2'
    # SMTT.ini content is pure ASCII (UILanguage=eng|vie). Use UTF-8 no-BOM
    # via .NET — Set-Content's PS5.1 default ASCII fallback is brittle and
    # WriteAllText with no encoding gives us UTF-8 no-BOM, byte-identical
    # to ASCII for ASCII content.
    [System.IO.File]::WriteAllText($iniPath, $patched)
}

if ($myaFiles.Count -gt 0) {
    foreach ($f in $myaFiles) {
        Write-Host "Remove-SMTT-Myanmar: deleting $($f.Name)" -ForegroundColor Yellow
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

# Verify the delete actually went through. If a process we didn't think to
# stop still holds the handle, Remove-Item silently no-ops (we're using
# SilentlyContinue) and we'd exit thinking we succeeded.
$leftover = @(Get-ChildItem -Path $langDir -Filter "*.mya" -File -ErrorAction SilentlyContinue)
if ($leftover.Count -gt 0) {
    Write-Host "Remove-SMTT-Myanmar: $($leftover.Count) .mya file(s) still present after delete:" -ForegroundColor Red
    $leftover | ForEach-Object { Write-Host "  - $($_.FullName)" -ForegroundColor Red }
    Write-Host "Remove-SMTT-Myanmar: another process may be holding the file. Re-run after closing Sao Mai apps." -ForegroundColor Red
    exit 1
}

if ($myaFiles.Count -gt 0) {
    Write-Host "Remove-SMTT-Myanmar: removed $($myaFiles.Count) Myanmar lang file(s) from $langDir" -ForegroundColor Green
}
Write-Host "Remove-SMTT-Myanmar: done." -ForegroundColor Green
exit 0
