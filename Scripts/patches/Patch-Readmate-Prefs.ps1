# Patch-Readmate-Prefs.ps1
# Three-stage patch for SM Readmate:
#
#   Stage 1 - shared_preferences.json: replaces the Student profile's
#   prefs file with the canonical version from
#   Config/sm-readmate-config/shared_preferences.json.
#
#   Stage 2 - book.js: patches Readmate's bundled foliate-js engine to
#   force paginated reading flow. One-line injection in the setStyle()
#   function. Tagged with "VL-FORCED-PAGINATED" marker.
#
#   Stage 3 - view.js: patches the TTS highlight callback to skip the
#   unconditional scrollToAnchor() call when in paginated mode. Without
#   this, TTS playback smooth-scrolls the page to follow each phrase,
#   producing the "fast scroll" UX bug. With it, the page stays stable
#   during playback (audio continues normally; visual highlight is no
#   longer chased). Tagged with "VL-PAGINATED-NO-SCROLL" marker.
#
# Historical note: a Stage 4 was attempted that injected a keydown
# handler in book.js wiring Right/Left arrows to window.ttsNext/ttsPrev
# for phrase-by-phrase nav. It was reverted because (a) bare arrow keys
# in the article pane are how NVDA reads page content line-by-line for
# blind students, and (b) the keydown handler's preventDefault would
# block that natural behavior. Phrase nav is therefore not wired in
# this build; students rely on NVDA's caret-tracking line read in the
# article pane and Readmate's TTS playback from the top bar.
#
# Background (Stage 1): an earlier deploy used Vi-Vu via SAPI5, which
# caused NVDA to read the book content while Readmate's TTS also played
# it (double-read). The fixed config restores Microsoft An via OneCore/
# system TTS, lowers the speech/audio rates to comfortable values, and
# disables auto-play (students press Ctrl+P to start reading).
# Configure-Laptop.ps1 Step 17d deploys this same file on fresh installs.
#
# Background (Stage 2): SM Readmate's foliate-js engine defaults to
# "scroll" page-turn style. In that mode arrow keys scroll the article
# smoothly instead of jumping by phrase, which is unusable for blind
# students. The pageTurnStyle setting is not stored in shared prefs,
# the SQLite app DB, or WebView2 storage - it appears to be a Flutter-
# side hardcoded default. We hardcode the desired value by injecting
# `style.pageTurnStyle = 'noAnimation'` at the top of setStyle() in the
# bundled book.js. Students cannot undo this (Program Files = admin-
# only). Will need re-derivation if Readmate's installer ships a new
# book.js whose setStyle() shape differs - the patch fails loud in
# that case rather than silently mangling the file.
#
# Run from any plugged DEPLOY_ USB or from a local clone of the repo:
#   <USB>:\Scripts\patches\Patch-Readmate-Prefs.ps1
# The source is resolved relative to this script's location, so the same
# script works regardless of drive letter.
#
# Idempotent: re-running on a laptop already at the canonical config is a
# hash-checked no-op and exits 0. Same for book.js (marker check).
#
# Run as Administrator. Stops sm_readmate.exe if running so the Flutter
# SharedPreferences in-memory state cannot flush back over the new file
# AND so book.js (loaded by the embedded WebView) is not file-locked.
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

# --- Stage 1 pre-check: shared_preferences.json ----------------------------
$prefsAlreadyCanonical = $false
if (Test-Path $dst) {
    $dstHash = (Get-FileHash $dst).Hash
    if ($srcHash -eq $dstHash) {
        $prefsAlreadyCanonical = $true
    }
}

# --- Stage 2 pre-check: book.js (paginated-flow patch) ---------------------
$bookJsPath        = "C:\Program Files\SaoMai\sm_readmate\data\flutter_assets\assets\foliate-js\book.js"
$bookJsMarker      = "VL-FORCED-PAGINATED"
$bookJsInjectLine  = "  style.pageTurnStyle = 'noAnimation' // $bookJsMarker - paginated mode forced by Vietnam Lab deployment"
$bookJsExists      = Test-Path $bookJsPath
$bookJsAlreadyPatched = $false
if ($bookJsExists) {
    $probe = Get-Content -Path $bookJsPath -Raw
    if ($probe -match [regex]::Escape($bookJsMarker)) {
        $bookJsAlreadyPatched = $true
    }
}

# --- Stage 3 pre-check: view.js (TTS auto-scroll skip in paginated mode) ---
$viewJsPath        = "C:\Program Files\SaoMai\sm_readmate\data\flutter_assets\assets\foliate-js\view.js"
$viewJsMarker      = "VL-PAGINATED-NO-SCROLL"
$viewJsExists      = Test-Path $viewJsPath
$viewJsAlreadyPatched = $false
if ($viewJsExists) {
    $probe = Get-Content -Path $viewJsPath -Raw
    if ($probe -match [regex]::Escape($viewJsMarker)) {
        $viewJsAlreadyPatched = $true
    }
}

# --- Cleanup: strip historical Stage 4 (VL-PHRASE-NAV) if present ----------
# Earlier versions of this script appended a phrase-nav keydown handler at
# the end of book.js. It was reverted because it conflicted with NVDA's
# arrow-key line reading in the article pane. If we encounter a laptop that
# was patched with the old script, strip the appended block.
$phraseNavMarker = "VL-PHRASE-NAV"
$phraseNavCleanupNeeded = $false
if ($bookJsExists) {
    $probe = Get-Content -Path $bookJsPath -Raw
    if ($probe -match [regex]::Escape($phraseNavMarker)) {
        $phraseNavCleanupNeeded = $true
    }
}

# --- Early exit if all stages are already in place -------------------------
$bookJsDone = $bookJsAlreadyPatched -or -not $bookJsExists
$viewJsDone = $viewJsAlreadyPatched -or -not $viewJsExists
if ($prefsAlreadyCanonical -and $bookJsDone -and $viewJsDone -and -not $phraseNavCleanupNeeded) {
    Write-Host "Patch-Readmate-Prefs: prefs already at canonical config (hash $srcHash)." -ForegroundColor Green
    if ($bookJsAlreadyPatched) {
        Write-Host "Patch-Readmate-Prefs: book.js already patched (paginated mode forced)." -ForegroundColor Green
    } elseif (-not $bookJsExists) {
        Write-Host "Patch-Readmate-Prefs: book.js not found at $bookJsPath - SM Readmate may not be installed. Skipping JS patches." -ForegroundColor Yellow
    }
    if ($viewJsAlreadyPatched) {
        Write-Host "Patch-Readmate-Prefs: view.js already patched (TTS auto-scroll skipped in paginated mode)." -ForegroundColor Green
    } elseif (-not $viewJsExists) {
        Write-Host "Patch-Readmate-Prefs: view.js not found at $viewJsPath - SM Readmate may not be installed. Skipping JS patch." -ForegroundColor Yellow
    }
    Write-Host "Patch-Readmate-Prefs: nothing to do." -ForegroundColor Green
    exit 0
}

# --- Stop Readmate ---------------------------------------------------------
# Needed BEFORE either write: prefs would otherwise be flushed over by the
# in-memory Flutter SharedPreferences state, and book.js is held open by the
# embedded WebView2 process.
$proc = Get-Process -Name sm_readmate -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Patch-Readmate-Prefs: stopping sm_readmate (PID $($proc.Id))..." -ForegroundColor Yellow
    Stop-Process -Name sm_readmate -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1500
}

# --- Stage 1: write canonical prefs ----------------------------------------
if ($prefsAlreadyCanonical) {
    Write-Host "Patch-Readmate-Prefs: prefs already at canonical config (hash $srcHash). Skipping copy." -ForegroundColor Green
} else {
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

    Write-Host "Patch-Readmate-Prefs: prefs deployed to $dst (hash $srcHash)." -ForegroundColor Green
}

# --- Stage 2: patch book.js ------------------------------------------------
if (-not $bookJsExists) {
    Write-Host "Patch-Readmate-Prefs: book.js not found at $bookJsPath - SM Readmate may not be installed. Skipping JS patch." -ForegroundColor Yellow
} elseif ($bookJsAlreadyPatched) {
    Write-Host "Patch-Readmate-Prefs: book.js already patched (paginated mode forced). Skipping JS patch." -ForegroundColor Green
} else {
    # Re-read book.js with Readmate now stopped (file lock released).
    $bookJsRaw = Get-Content -Path $bookJsPath -Raw

    # Match setStyle() function opening + trailing line ending. The capture
    # groups preserve the file's existing line ending (LF or CRLF) so we
    # don't introduce mixed line endings on write.
    $pattern = '(const setStyle = \(\) => \{)(\r?\n)'

    if ($bookJsRaw -notmatch $pattern) {
        Write-Host ""
        Write-Host "Patch-Readmate-Prefs: ERROR - cannot locate 'const setStyle = () => {' in book.js." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Path: $bookJsPath" -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Readmate's installer likely shipped a new book.js whose setStyle() shape differs." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Investigate book.js manually before re-running this patch." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: (shared_preferences.json was patched OK; only the JS stage failed.)" -ForegroundColor Red
        exit 1
    }

    $replacement = "`$1`$2$bookJsInjectLine`$2"
    $patchedJs = $bookJsRaw -replace $pattern, $replacement

    if ($patchedJs -notmatch [regex]::Escape($bookJsMarker)) {
        Write-Host "Patch-Readmate-Prefs: ERROR - regex replace did not produce expected marker. Aborting before write." -ForegroundColor Red
        exit 1
    }

    # book.js ships without a UTF-8 BOM; preserve that. PowerShell 5.1's
    # Set-Content -Encoding UTF8 always writes a BOM, so use .NET WriteAllText
    # with an explicit no-BOM UTF-8 encoder.
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($bookJsPath, $patchedJs, $utf8NoBom)

    # Verify: re-read from disk and confirm the marker is present.
    $verifyJs = Get-Content -Path $bookJsPath -Raw
    if ($verifyJs -notmatch [regex]::Escape($bookJsMarker)) {
        Write-Host "Patch-Readmate-Prefs: ERROR - patch verification failed (marker not present after write)." -ForegroundColor Red
        exit 1
    }

    Write-Host "Patch-Readmate-Prefs: book.js patched - paginated mode now forced." -ForegroundColor Green
    Write-Host "Patch-Readmate-Prefs: marker '$bookJsMarker' present in $bookJsPath" -ForegroundColor Green
}

# --- Stage 3: patch view.js ------------------------------------------------
if (-not $viewJsExists) {
    Write-Host "Patch-Readmate-Prefs: view.js not found at $viewJsPath - skipping TTS-scroll patch." -ForegroundColor Yellow
} elseif ($viewJsAlreadyPatched) {
    Write-Host "Patch-Readmate-Prefs: view.js already patched (TTS auto-scroll skipped in paginated mode). Skipping." -ForegroundColor Green
} else {
    $viewJsRaw = Get-Content -Path $viewJsPath -Raw

    # Match the TTS highlight callback's unconditional scrollToAnchor call.
    # This is the source of the "fast scroll during TTS playback" bug: every
    # phrase advance triggers a scrollToAnchor that bypasses the flow=paginated
    # mode. We wrap it with a flow check so the scroll is skipped in paginated
    # mode but still works in scrolled mode (which we never use in deployment,
    # but defensive in case Stage 2 fails or is reverted).
    $viewJsPattern = '(\r?\n)(\s+)this\.renderer\.scrollToAnchor\(range\);(\r?\n)'

    if ($viewJsRaw -notmatch $viewJsPattern) {
        Write-Host ""
        Write-Host "Patch-Readmate-Prefs: ERROR - cannot locate 'this.renderer.scrollToAnchor(range);' in view.js." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Path: $viewJsPath" -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Readmate's installer likely shipped a new view.js." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: Investigate manually before re-running." -ForegroundColor Red
        Write-Host "Patch-Readmate-Prefs: (Stages 1 and 2 succeeded; only Stage 3 failed.)" -ForegroundColor Red
        exit 1
    }

    $viewJsReplacement = "`$1`$2if (this.renderer.getAttribute('flow') !== 'paginated') this.renderer.scrollToAnchor(range); // $viewJsMarker - skip TTS auto-scroll in paginated mode (Vietnam Lab deployment)`$3"
    $patchedViewJs = $viewJsRaw -replace $viewJsPattern, $viewJsReplacement

    if ($patchedViewJs -notmatch [regex]::Escape($viewJsMarker)) {
        Write-Host "Patch-Readmate-Prefs: ERROR - regex replace did not produce expected marker in view.js. Aborting before write." -ForegroundColor Red
        exit 1
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($viewJsPath, $patchedViewJs, $utf8NoBom)

    $verifyViewJs = Get-Content -Path $viewJsPath -Raw
    if ($verifyViewJs -notmatch [regex]::Escape($viewJsMarker)) {
        Write-Host "Patch-Readmate-Prefs: ERROR - view.js patch verification failed (marker not present after write)." -ForegroundColor Red
        exit 1
    }

    Write-Host "Patch-Readmate-Prefs: view.js patched - TTS auto-scroll now skipped in paginated mode." -ForegroundColor Green
    Write-Host "Patch-Readmate-Prefs: marker '$viewJsMarker' present in $viewJsPath" -ForegroundColor Green
}

# --- Cleanup historical Stage 4 if present ---------------------------------
if ($phraseNavCleanupNeeded) {
    $bookJsRevert = Get-Content -Path $bookJsPath -Raw
    # Strip from the VL-PHRASE-NAV comment block to end of file. The marker
    # always appears as a comment introducer "// VL-PHRASE-NAV", and the
    # appended block runs to EOF, so a single regex replace is sufficient.
    $cleaned = [regex]::Replace($bookJsRevert, '(?s)\r?\n// VL-PHRASE-NAV.*$', '')

    if ($cleaned -match [regex]::Escape($phraseNavMarker)) {
        Write-Host "Patch-Readmate-Prefs: ERROR - phrase-nav cleanup did not remove marker." -ForegroundColor Red
        exit 1
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($bookJsPath, $cleaned, $utf8NoBom)

    Write-Host "Patch-Readmate-Prefs: stripped historical phrase-nav inject from book.js." -ForegroundColor Green
}

Write-Host "Patch-Readmate-Prefs: done." -ForegroundColor Green
exit 0
