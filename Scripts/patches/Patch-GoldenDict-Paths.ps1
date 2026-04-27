# Patch-GoldenDict-Paths.ps1
# Surgical patch for the Student profile's GoldenDict config. Two fixes,
# both needed by already-deployed laptops where Configure-Laptop.ps1's
# Step 35 ran an older repo stub:
#
# 1. <paths>: ensures the dictionary content directory is registered, so
#    bundled Vietnamese dictionaries (star_anhviet, star_vietanh) load
#    instead of every lookup returning
#      "Khong co dich nghia cho '<word>' duoc tim thay trong nhom 'Tat ca'"
#    (No translation found in group All).
#
# 2. <mainWindowState>: ensures the History, Favorites, and Dictionaries
#    side panes are hidden on launch. NVDA cannot announce GoldenDict's
#    QtWebEngine article view (NVDA issue #10838: it doesn't recognize
#    QtWebEngine as web content), so the documented student workflow is
#    Tab-from-search-box into article view, then Ctrl+A / Ctrl+C / NVDA+C.
#    Hiding the three side panes makes that Tab cycle deterministic
#    (one Tab from search box reaches the article view).
#
# Both targets are read from the repo stub (Config/goldendict-config/config)
# so the patch and stub stay in sync — there is one source of truth.
#
# Background: 1-Install-All.ps1 copies the .ifo/.idx/.dict.dz files into
# C:\Program Files (x86)\GoldenDict\content\ but earlier versions of the
# stub config only contained <preferences>; on first launch GoldenDict
# expanded missing elements to defaults (paths empty, panes visible), so
# it never scanned the content folder and side panes cluttered Tab order.
# The repo stub is now correct and fresh deploys are correct; this script
# is the surgical equivalent for already-deployed laptops.
#
# Run from any plugged DEPLOY_ USB or from a local clone of the repo:
#   <USB>:\Scripts\patches\Patch-GoldenDict-Paths.ps1
#
# Idempotent: re-running on a laptop where both elements already match the
# golden values is a no-op and exits 0.
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

# Read the golden <mainWindowState> from the repo stub. Single source of
# truth: whatever is in the stub is what we patch deployed laptops to match.
# Stub path differs depending on whether we're running from a USB
# (Scripts/patches/...) or a local repo clone — both have the same layout.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stubPath = Join-Path $repoRoot "Config\goldendict-config\config"
if (-not (Test-Path $stubPath)) {
    Write-Host "Patch-GoldenDict-Paths: repo stub missing at $stubPath - aborting." -ForegroundColor Red
    exit 1
}
[xml]$stubXml = Get-Content -Path $stubPath -Raw -Encoding UTF8
$goldenStateNode = $stubXml.SelectSingleNode("/config/mainWindowState")
$goldenMainWindowState = if ($goldenStateNode) { $goldenStateNode.InnerText } else { $null }
if (-not $goldenMainWindowState) {
    Write-Host "Patch-GoldenDict-Paths: repo stub has no <mainWindowState>; pane-state patch will be skipped." -ForegroundColor Yellow
}

# Idempotency: parse the live config and decide whether either fix is needed.
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

$alreadyHasGoldenState = $false
if ($goldenMainWindowState) {
    $liveStateNode = $xml.SelectSingleNode("/config/mainWindowState")
    if ($liveStateNode -and $liveStateNode.InnerText -eq $goldenMainWindowState) {
        $alreadyHasGoldenState = $true
    }
} else {
    # No golden value to enforce; treat as already satisfied so we don't loop.
    $alreadyHasGoldenState = $true
}

if ($alreadyHasPath -and $alreadyHasGoldenState) {
    Write-Host "Patch-GoldenDict-Paths: <paths> and <mainWindowState> already match. Nothing to do." -ForegroundColor Green
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

$rootNode = $xml.SelectSingleNode("/config")
if (-not $rootNode) {
    Write-Host "Patch-GoldenDict-Paths: <config> root missing in $gdConfig - file appears corrupt; aborting." -ForegroundColor Red
    exit 1
}

# Patch 1: ensure <paths> contains $ContentDir.
$pathPatched = $false
if (-not $alreadyHasPath) {
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
    $pathElem = $xml.CreateElement("path")
    $pathElem.SetAttribute("recursive", "1")
    $pathElem.InnerText = $ContentDir
    $paths.AppendChild($pathElem) | Out-Null
    $pathPatched = $true
}

# Patch 2: ensure <mainWindowState> matches golden (panes hidden).
$statePatched = $false
if ($goldenMainWindowState -and -not $alreadyHasGoldenState) {
    $liveStateNode = $rootNode.SelectSingleNode("mainWindowState")
    if ($liveStateNode) {
        $liveStateNode.InnerText = $goldenMainWindowState
    } else {
        $newStateNode = $xml.CreateElement("mainWindowState")
        $newStateNode.InnerText = $goldenMainWindowState
        $rootNode.AppendChild($newStateNode) | Out-Null
    }
    $statePatched = $true
}

# Write back. Encoding UTF-8 with declaration matches GoldenDict's own writes.
$xml.Save($gdConfig)

# Wipe the stale index dir so GoldenDict rebuilds dictionary indexes on next
# launch. Without this, an empty index from the prior run can mask the newly
# scanned dictionaries until the user clicks Edit > Dictionaries > Rescan.
# Only relevant when paths changed — pane-state alone doesn't need reindex.
$indexCleared = $false
if ($pathPatched) {
    $indexDir = Join-Path $gdConfigDir "index"
    if (Test-Path $indexDir) {
        Get-ChildItem -Path $indexDir -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        $indexCleared = $true
    }
}

# Restore Student modify access (script runs as Admin and any new dir/file
# would otherwise inherit Admin-only ACLs).
icacls $gdConfigDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

if ($pathPatched) {
    Write-Host "Patch-GoldenDict-Paths: added <path recursive=`"1`">$ContentDir</path>" -ForegroundColor Green
    Write-Host "Patch-GoldenDict-Paths: $($ifoFiles.Count) dictionary file(s) detected:" -ForegroundColor Green
    $ifoFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Green }
}
if ($statePatched) {
    Write-Host "Patch-GoldenDict-Paths: updated <mainWindowState> (History/Favorites/Dictionaries panes hidden)." -ForegroundColor Green
}
if ($indexCleared) {
    Write-Host "Patch-GoldenDict-Paths: cleared $indexDir; dictionaries reindex on next launch." -ForegroundColor Green
}
Write-Host "Patch-GoldenDict-Paths: done." -ForegroundColor Green
exit 0
