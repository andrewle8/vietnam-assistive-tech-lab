# Deploy-Help.ps1
# Deploys the help portal HTML to a laptop and refreshes the "Huong Dan"
# desktop shortcut. Shared by THREE deploy paths so the logic stays in one
# place and idempotent across all of them:
#
#   1. Configure-Laptop.ps1 Step 35c (initial deploy from a DEPLOY_ USB)
#       -> Deploy-Help.ps1 -FromUSB <usb-root>
#
#   2. Scripts\patches\Fix-Help.ps1 (post-deploy USB-walkup field patch)
#       -> Deploy-Help.ps1 -FromUSB <usb-root>
#
#   3. Scripts\Deploy-Help-Remote.ps1 invoked by LabUpdateAgent (remote
#      via internet, no USB present)
#       -> Deploy-Help.ps1 -FromGitHub
#
# Source-of-truth for which files to deploy: Config\help-html\docs-manifest.json.
# Reading the manifest (instead of a hardcoded list) means adding a new doc =
# add a manifest entry + .md files + run Build-Help-HTML.ps1; this script needs
# no changes.
#
# What this script does (idempotent):
#   - Ensure C:\LabTools\help\ exists
#   - Read the manifest (from USB or GitHub raw) to learn which .html files
#     belong to the portal
#   - Copy/download index.html plus every output_vi / output_en into LabTools
#   - Refresh "Huong Dan.lnk" on the Public Desktop pointing at Firefox +
#     file:///C:/LabTools/help/index.html
#
# Re-running just refreshes the files. Safe at any time.
#
# Note: this file is saved with a UTF-8 BOM so the Vietnamese chars in the
# shortcut description / cleanup-name list round-trip correctly under PS5.1.

[CmdletBinding(DefaultParameterSetName='USB')]
param(
    [Parameter(Mandatory, ParameterSetName='USB')]
    [string]$FromUSB,

    [Parameter(Mandatory, ParameterSetName='GitHub')]
    [switch]$FromGitHub,

    [string]$GitHubRawBase = 'https://raw.githubusercontent.com/andrewle8/vietnam-assistive-tech-lab/main',
    [string]$InstallDir    = 'C:\LabTools\help',
    [string]$ShortcutName  = 'Hướng Dẫn'
)

$ErrorActionPreference = 'Stop'

$results = [ordered]@{}

# --------------------------------------------------------------------------
# Stage 1: Ensure install dir, load manifest from chosen source, copy/fetch
#          each HTML file into C:\LabTools\help.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 1/2] Deploying HTML files to $InstallDir..."
try {
    if (-not (Test-Path $InstallDir)) {
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    }

    if ($PSCmdlet.ParameterSetName -eq 'USB') {
        $manifestPath = Join-Path $FromUSB 'Config\help-html\docs-manifest.json'
        if (-not (Test-Path $manifestPath)) {
            throw "Manifest not found on USB: $manifestPath. Make sure the USB has been synced from the repo."
        }
        Write-Host "  manifest source: $manifestPath"
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $manifestUrl = "$GitHubRawBase/Config/help-html/docs-manifest.json"
        Write-Host "  manifest source: $manifestUrl"
        $resp = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -ErrorAction Stop
        $manifest = $resp.Content | ConvertFrom-Json
    }

    if (-not $manifest.docs) {
        throw "Manifest has no 'docs' array"
    }

    # Always include the portal index. Then add every output_vi / output_en
    # from the manifest. De-duplicate (paranoia in case future manifest
    # entries share filenames).
    $fileList = New-Object System.Collections.Generic.List[string]
    $fileList.Add('index.html')
    foreach ($doc in $manifest.docs) {
        if ($doc.output_vi) { $fileList.Add($doc.output_vi) }
        if ($doc.output_en) { $fileList.Add($doc.output_en) }
    }
    $fileList = $fileList | Select-Object -Unique

    $copied = 0
    foreach ($f in $fileList) {
        $dst = Join-Path $InstallDir $f
        try {
            if ($PSCmdlet.ParameterSetName -eq 'USB') {
                $src = Join-Path $FromUSB "docs\$f"
                if (-not (Test-Path $src)) {
                    Write-Warning "  missing on USB: $src"
                    continue
                }
                Copy-Item -Path $src -Destination $dst -Force
            } else {
                $url = "$GitHubRawBase/docs/$f"
                Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing -ErrorAction Stop
            }
            $copied++
        } catch {
            Write-Warning "  failed on $f : $($_.Exception.Message)"
        }
    }

    Write-Host "  [OK] $copied/$($fileList.Count) files in $InstallDir"
    $results['html files'] = "OK ($copied/$($fileList.Count))"
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    $results['html files'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Stage 2: Refresh "Hướng Dẫn" desktop shortcut on Public Desktop.
# Targets firefox.exe directly (bypasses default-browser setting; a .url file
# would honor it but we want NVDA-friendly Firefox specifically). The shortcut
# name has chars outside CP1252 (ư U+01B0, ớ U+1EDB, ẫ U+1EAB) so we go
# through the same temp-ASCII-path + Move-Item dance as Fix-SilverDict.ps1.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "[Stage 2/2] Refreshing '$ShortcutName' desktop shortcut..."
try {
    # Find Firefox
    $firefoxPath = $null
    $appPathsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe"
    if (Test-Path $appPathsKey) {
        $firefoxPath = (Get-Item $appPathsKey).GetValue("")
    }
    if (-not $firefoxPath -or -not (Test-Path $firefoxPath)) {
        foreach ($p in @("C:\Program Files\Mozilla Firefox\firefox.exe", "C:\Program Files (x86)\Mozilla Firefox\firefox.exe")) {
            if (Test-Path $p) { $firefoxPath = $p; break }
        }
    }
    if (-not $firefoxPath) {
        throw "Firefox not found - cannot create $ShortcutName shortcut"
    }

    $publicDesktop = "C:\Users\Public\Desktop"
    $finalLnkPath  = Join-Path $publicDesktop "$ShortcutName.lnk"
    $tempLnkPath   = Join-Path $publicDesktop "HuongDan-Help-temp.lnk"

    # Clean any prior name variants. Same mojibake hazard as Từ Điển:
    # WScript.Shell.CreateShortcut goes through ANSI COM marshaling, so chars
    # outside CP1252 get converted to "?", potentially leaving a corrupted
    # name from an older deployment. Wipe known variants before recreate.
    $variantsToClean = @(
        "$ShortcutName.lnk",
        'HÆ°á»›ng Dáº«n.lnk',
        'H??ng D?n.lnk',
        'Huong Dan.lnk',
        'HuongDan-Help-temp.lnk'
    )
    Get-ChildItem $publicDesktop -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in $variantsToClean
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Use the system "info / book" imageres icon. shell32.dll question-mark
    # would also work but the imageres book is more recognizable as a guide.
    $iconLoc = "%SystemRoot%\System32\imageres.dll,94"

    # Create at ASCII-safe temp path so CreateShortcut/Save don't trip on the
    # non-CP1252 chars in the final filename. Then Move-Item to the Unicode
    # final path - Move-Item uses MoveFileW (Unicode Win32 API) and handles
    # non-CP1252 names correctly. The .lnk's INTERNAL fields (TargetPath,
    # Description) are stored as Unicode by the COM object so they round-trip
    # fine even with non-CP1252 chars.
    $wshell = New-Object -ComObject WScript.Shell
    $sc = $wshell.CreateShortcut($tempLnkPath)
    $sc.TargetPath       = $firefoxPath
    $sc.Arguments        = "file:///C:/LabTools/help/index.html"
    $sc.WorkingDirectory = Split-Path $firefoxPath -Parent
    $sc.IconLocation     = $iconLoc
    $sc.Description      = "Hướng dẫn sử dụng máy tính - opens in Firefox so NVDA browse mode works"
    $sc.Save()

    Move-Item -Path $tempLnkPath -Destination $finalLnkPath -Force
    Write-Host "  [OK] $finalLnkPath -> $firefoxPath file:///C:/LabTools/help/index.html"
    $results['desktop shortcut'] = 'OK'
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    $results['desktop shortcut'] = 'FAIL'
}

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Deploy-Help Summary ==="
foreach ($key in $results.Keys) {
    $status = $results[$key]
    $color = if ($status -like 'OK*') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-20} {1}" -f $key, $status) -ForegroundColor $color
}

$failed = ($results.Values | Where-Object { $_ -notlike 'OK*' }).Count
exit $(if ($failed -eq 0) { 0 } else { 1 })
