# Patch-Readmate-Prefs.ps1
# One-shot patch: replaces the Student profile's SM Readmate
# shared_preferences.json with the canonical version from
# Config/sm-readmate-config/shared_preferences.json.
#
# Background: an earlier deploy used Vi-Vu via SAPI5, which caused NVDA to
# read the book content while Readmate's TTS also played it (double-read).
# The fixed config restores Microsoft An via OneCore/system TTS, lowers the
# speech/audio rates to comfortable values, and disables auto-play (students
# press Ctrl+P to start reading). Configure-Laptop.ps1 Step 17d deploys this
# same file on fresh installs; this script is the surgical equivalent for
# already-deployed laptops, runnable in seconds without a full re-deploy.
#
# Run from any plugged DEPLOY_ USB or from a local clone of the repo:
#   <USB>:\Scripts\patches\Patch-Readmate-Prefs.ps1
# The source is resolved relative to this script's location, so the same
# script works regardless of drive letter.
#
# Idempotent: re-running on a laptop already at the canonical config is a
# hash-checked no-op and exits 0.
#
# Run as Administrator. Stops sm_readmate.exe if running so the Flutter
# SharedPreferences in-memory state cannot flush back over the new file.
# Students lose at most their current reading position.

param(
    [string]$StudentProfile = "C:\Users\Student"
)

$ErrorActionPreference = "Stop"

# Resolve source: ../../Config/sm-readmate-config/shared_preferences.json
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src = Join-Path $repoRoot "Config\sm-readmate-config\shared_preferences.json"
$dstDir = Join-Path $StudentProfile "AppData\Roaming\SaoMai\SM Readmate"
$dst = Join-Path $dstDir "shared_preferences.json"

if (-not (Test-Path $src)) {
    Write-Host "Patch-Readmate-Prefs: source not found at $src - aborting." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Patch-Readmate-Prefs: Student profile not found at $StudentProfile - skipping." -ForegroundColor Yellow
    exit 0
}

$srcHash = (Get-FileHash $src).Hash

# Idempotent: skip if already at canonical config
if (Test-Path $dst) {
    $dstHash = (Get-FileHash $dst).Hash
    if ($srcHash -eq $dstHash) {
        Write-Host "Patch-Readmate-Prefs: already at canonical config (hash $srcHash). Nothing to do." -ForegroundColor Green
        exit 0
    }
}

# Stop Readmate so its in-memory prefs don't flush back over our copy.
$proc = Get-Process -Name sm_readmate -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Patch-Readmate-Prefs: stopping sm_readmate (PID $($proc.Id))..." -ForegroundColor Yellow
    Stop-Process -Name sm_readmate -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1500
}

if (-not (Test-Path $dstDir)) {
    New-Item -Path $dstDir -ItemType Directory -Force | Out-Null
}

Copy-Item -Path $src -Destination $dst -Force

$dstHash = (Get-FileHash $dst).Hash
if ($srcHash -ne $dstHash) {
    Write-Host "Patch-Readmate-Prefs: HASH MISMATCH after copy. src=$srcHash dst=$dstHash" -ForegroundColor Red
    exit 1
}

# Restore Student ownership of the dir tree. The script runs as Admin, so
# any dir it creates inherits Admin ACLs by default; explicit grant ensures
# Student can still read/write the prefs through Readmate.
icacls $dstDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

Write-Host "Patch-Readmate-Prefs: deployed canonical prefs to $dst" -ForegroundColor Green
Write-Host "Patch-Readmate-Prefs: hash $srcHash" -ForegroundColor Green
Write-Host "Patch-Readmate-Prefs: done." -ForegroundColor Green
exit 0
