# Patch-GoldenDict-Paths.ps1
# One-shot patch: makes GoldenDict actually load the bundled Vietnamese
# dictionaries (star_anhviet en-vi + star_vietanh vi-en) by adding a
# <path recursive="1">...</path> entry under <paths> in the Student profile's
# GoldenDict config. Without that entry GoldenDict starts with no dictionaries
# loaded and every lookup returns:
#   "Khong co dich nghia cho '<word>' duoc tim thay trong nhom 'Tat ca'"
# (No translation found in group All).
#
# Background: 1-Install-All.ps1 copies the .ifo/.idx/.dict.dz files into
# C:\Program Files (x86)\GoldenDict\content\ but the stub config that
# Configure-Laptop.ps1 Step 35 deployed only contained <preferences>; on
# first launch GoldenDict expanded missing elements to defaults (paths
# empty), so it never scanned the content folder. The repo stub is now
# fixed (Config/goldendict-config/config) and fresh deploys are correct;
# this script is the surgical equivalent for already-deployed laptops.
#
# Run from any plugged DEPLOY_ USB or from a local clone of the repo:
#   <USB>:\Scripts\patches\Patch-GoldenDict-Paths.ps1
#
# Idempotent: re-running on a laptop already pointing at the content dir
# is a no-op and exits 0.
#
# Run as Administrator. Stops GoldenDict.exe if running so the in-memory
# config snapshot cannot flush back over our edit.

param(
    [string]$StudentProfile = "C:\Users\Student",
    [string]$ContentDir = $null
)

$ErrorActionPreference = "Stop"

# Resolve where the dictionaries actually live. GoldenDict 1.5.1 is 32-bit so
# on x64 Windows the install lands under (x86); but check both for safety.
if (-not $ContentDir) {
    $candidates = @(
        "C:\Program Files (x86)\GoldenDict\content",
        "C:\Program Files\GoldenDict\content"
    )
    $ContentDir = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $ContentDir) {
        Write-Host "Patch-GoldenDict-Paths: dictionary content not found at any of:" -ForegroundColor Red
        $candidates | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "Patch-GoldenDict-Paths: re-run 1-Install-All.ps1 to install dictionaries first." -ForegroundColor Yellow
        exit 1
    }
}

# Sanity-check there are real .ifo files; pointing GoldenDict at an empty dir
# accomplishes nothing.
$ifoFiles = @(Get-ChildItem -Path $ContentDir -Filter "*.ifo" -Recurse -ErrorAction SilentlyContinue)
if ($ifoFiles.Count -eq 0) {
    Write-Host "Patch-GoldenDict-Paths: no .ifo files under $ContentDir - aborting." -ForegroundColor Red
    Write-Host "Patch-GoldenDict-Paths: dictionaries not deployed; re-run 1-Install-All.ps1." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Patch-GoldenDict-Paths: Student profile not found at $StudentProfile - skipping." -ForegroundColor Yellow
    exit 0
}

$gdConfigDir = Join-Path $StudentProfile "AppData\Roaming\GoldenDict"
$gdConfig = Join-Path $gdConfigDir "config"

# If GoldenDict has never been launched on this profile, the config file may
# not yet exist. Deploy the canonical stub from the repo so we have something
# valid to patch. Configure-Laptop.ps1 Step 35 normally does this on initial
# deploy, but the patch must be self-sufficient.
if (-not (Test-Path $gdConfig)) {
    if (-not (Test-Path $gdConfigDir)) {
        New-Item -Path $gdConfigDir -ItemType Directory -Force | Out-Null
    }
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $stubPath = Join-Path $repoRoot "Config\goldendict-config\config"
    if (Test-Path $stubPath) {
        Copy-Item -Path $stubPath -Destination $gdConfig -Force
        Write-Host "Patch-GoldenDict-Paths: deployed canonical stub (no prior config)." -ForegroundColor Green
    } else {
        Write-Host "Patch-GoldenDict-Paths: no existing config and no repo stub at $stubPath - aborting." -ForegroundColor Red
        exit 1
    }
}

# Idempotency: parse the XML and check whether the path is already there.
[xml]$xml = Get-Content -Path $gdConfig -Raw -Encoding UTF8
$alreadyHasPath = $false
$paths = $xml.SelectSingleNode("/config/paths")
if ($paths) {
    foreach ($p in $paths.SelectNodes("path")) {
        if ($p.InnerText -ieq $ContentDir) {
            $alreadyHasPath = $true
            break
        }
    }
}

if ($alreadyHasPath) {
    Write-Host "Patch-GoldenDict-Paths: $ContentDir already in <paths>. Nothing to do." -ForegroundColor Green
    exit 0
}

# Stop GoldenDict so it doesn't flush its in-memory config over our edit when
# the user later closes the window. Students lose at most their current word
# lookup; the search history file is separate and untouched.
$proc = Get-Process -Name GoldenDict -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Patch-GoldenDict-Paths: stopping GoldenDict (PID $($proc.Id))..." -ForegroundColor Yellow
    Stop-Process -Name GoldenDict -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1500
    # Re-read after kill in case GoldenDict flushed on shutdown.
    [xml]$xml = Get-Content -Path $gdConfig -Raw -Encoding UTF8
}

# Ensure /config/paths exists.
$rootNode = $xml.SelectSingleNode("/config")
if (-not $rootNode) {
    Write-Host "Patch-GoldenDict-Paths: <config> root missing in $gdConfig - file appears corrupt; aborting." -ForegroundColor Red
    exit 1
}
$paths = $rootNode.SelectSingleNode("paths")
if (-not $paths) {
    $paths = $xml.CreateElement("paths")
    # Match GoldenDict's own write order: <paths> is the first child of <config>.
    if ($rootNode.HasChildNodes) {
        $rootNode.InsertBefore($paths, $rootNode.FirstChild) | Out-Null
    } else {
        $rootNode.AppendChild($paths) | Out-Null
    }
}

# Append the new <path recursive="1">$ContentDir</path>.
$pathElem = $xml.CreateElement("path")
$pathElem.SetAttribute("recursive", "1")
$pathElem.InnerText = $ContentDir
$paths.AppendChild($pathElem) | Out-Null

# Write back. Encoding UTF-8 with declaration matches GoldenDict's own writes.
$xml.Save($gdConfig)

# Wipe the stale index dir so GoldenDict rebuilds dictionary indexes on next
# launch. Without this, an empty index from the prior run can mask the newly
# scanned dictionaries until the user clicks Edit > Dictionaries > Rescan.
$indexDir = Join-Path $gdConfigDir "index"
if (Test-Path $indexDir) {
    Get-ChildItem -Path $indexDir -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

# Restore Student modify access (script runs as Admin and any new dir/file
# would otherwise inherit Admin-only ACLs).
icacls $gdConfigDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

Write-Host "Patch-GoldenDict-Paths: added <path recursive=`"1`">$ContentDir</path>" -ForegroundColor Green
Write-Host "Patch-GoldenDict-Paths: $($ifoFiles.Count) dictionary file(s) detected:" -ForegroundColor Green
$ifoFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Green }
Write-Host "Patch-GoldenDict-Paths: cleared $indexDir; dictionaries reindex on next launch." -ForegroundColor Green
Write-Host "Patch-GoldenDict-Paths: done." -ForegroundColor Green
exit 0
