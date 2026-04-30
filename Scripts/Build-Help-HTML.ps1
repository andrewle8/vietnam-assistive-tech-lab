# Build-Help-HTML.ps1
# Dev-machine tool: convert the user-guide markdown sources under docs/ into
# accessible HTML for the help portal that ships on every student laptop.
#
# Reads Config/help-html/docs-manifest.json (the doc list) and runs pandoc once
# per language per doc, then generates docs/index.html (the portal landing page
# students land on when they open the "Huong Dan" desktop shortcut).
#
# Pandoc lives on the dev machine ONLY (default: C:\Tools\pandoc\pandoc.exe, or
# wherever pandoc is in PATH). The student laptops never see pandoc - they
# only receive the generated .html files via the existing USB-sync + LabUpdate
# Agent channels (see docs/Remote-Updates.md).
#
# Usage (from repo root):
#     .\Scripts\Build-Help-HTML.ps1
#
# Re-run after editing any .md source. The output .html files are committed
# to the repo alongside the .md, so the rest of the deploy chain (Deploy-Help.ps1
# and Configure-Laptop.ps1 Step 35c) just copies them; no pandoc needed in field.
#
# Adding a new doc:
#   1. Drop two .md files under docs/ (vi + en).
#   2. Append an entry to Config/help-html/docs-manifest.json.
#   3. Run this script.
#   4. Commit + push + bump update-manifest.json version.
#
# Note: this file is saved with a UTF-8 BOM so the Vietnamese strings (in the
# generated index footer below) round-trip correctly under PowerShell 5.1,
# which would otherwise read .ps1 as ANSI/CP1252 and corrupt the diacritics.

[CmdletBinding()]
param(
    [string]$RepoRoot       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ManifestPath   = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Config\help-html\docs-manifest.json'),
    [string]$StylesheetPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Config\help-html\style.css'),
    [string]$OutputDir      = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'docs'),
    [string]$PandocPath     = $null
)

$ErrorActionPreference = 'Stop'

# ----- Resolve pandoc ----------------------------------------------------------
# PATH first, then the standard C:\Tools\pandoc\pandoc.exe location used by the
# test-bench dev tools tree (consistent with C:\Tools\mingw64 etc.).
if (-not $PandocPath) {
    $cmd = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($cmd) {
        $PandocPath = $cmd.Source
    } elseif (Test-Path 'C:\Tools\pandoc\pandoc.exe') {
        $PandocPath = 'C:\Tools\pandoc\pandoc.exe'
    } else {
        throw "pandoc not found in PATH or at C:\Tools\pandoc\pandoc.exe. Install pandoc on this dev machine and re-run. Extract the windows-x86_64 zip from https://github.com/jgm/pandoc/releases/latest to C:\Tools\pandoc\."
    }
}

$pandocVersion = (& $PandocPath --version | Select-Object -First 1)
Write-Host "pandoc:    $PandocPath ($pandocVersion)" -ForegroundColor DarkGray
Write-Host "repo:      $RepoRoot" -ForegroundColor DarkGray
Write-Host "manifest:  $ManifestPath" -ForegroundColor DarkGray
Write-Host "output:    $OutputDir" -ForegroundColor DarkGray

# ----- Load manifest -----------------------------------------------------------
if (-not (Test-Path $ManifestPath))   { throw "Manifest not found: $ManifestPath" }
if (-not (Test-Path $StylesheetPath)) { throw "Stylesheet not found: $StylesheetPath" }

$manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.docs) { throw "Manifest has no 'docs' array" }

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

# ----- Build each doc ----------------------------------------------------------
$built = New-Object System.Collections.Generic.List[object]
foreach ($doc in $manifest.docs) {
    foreach ($lang in @('vi','en')) {
        $sourceRel = $doc."source_$lang"
        $outputRel = $doc."output_$lang"
        $title     = $doc."title_$lang"

        $sourcePath = Join-Path $RepoRoot $sourceRel
        $outputPath = Join-Path $OutputDir $outputRel

        if (-not (Test-Path $sourcePath)) {
            Write-Warning "[$($doc.id):$lang] source missing - skipping: $sourcePath"
            continue
        }

        Write-Host ""
        Write-Host "[$($doc.id):$lang] $sourceRel -> docs/$outputRel" -ForegroundColor Cyan

        # GFM (--from gfm) so our pipe-tables in the .md sources render as
        # proper <table>/<th>/<td> markup that NVDA reads as a real table.
        # --embed-resources inlines the stylesheet into the .html so the
        # output is one self-contained file (no broken <link> if the file
        # moves between USB / C:\LabTools\help / GitHub raw).
        $pandocArgs = @(
            $sourcePath
            '--from=gfm'
            '--to=html5'
            '--standalone'
            '--toc'
            '--toc-depth=3'
            '--embed-resources'
            "--css=$StylesheetPath"
            "--metadata=title:$title"
            "--metadata=lang:$lang"
            "--output=$outputPath"
        )
        & $PandocPath @pandocArgs
        if ($LASTEXITCODE -ne 0) { throw "pandoc failed (exit $LASTEXITCODE) on $sourcePath" }

        $sizeKB = [math]::Round((Get-Item $outputPath).Length / 1KB, 1)
        Write-Host ("   ok ({0} KB)" -f $sizeKB) -ForegroundColor Green
        $built.Add([PSCustomObject]@{ Id = $doc.id; Lang = $lang; Output = $outputRel; SizeKB = $sizeKB })
    }
}

# ----- Generate portal index.html ----------------------------------------------
# This is the page Firefox opens when the student clicks the "Huong Dan"
# desktop shortcut. Lists every doc with both language links. Pure semantic
# HTML - no JavaScript - so NVDA browse mode is fully unobstructed.
Write-Host ""
Write-Host "[index] generating portal docs/index.html" -ForegroundColor Cyan

$cssContent = Get-Content $StylesheetPath -Raw -Encoding UTF8

$sectionsHtml = New-Object System.Text.StringBuilder
foreach ($doc in $manifest.docs) {
    [void]$sectionsHtml.AppendLine('<section>')
    [void]$sectionsHtml.AppendLine("  <h2 lang=""vi"">$($doc.title_vi)</h2>")
    [void]$sectionsHtml.AppendLine("  <p lang=""vi"">$($doc.desc_vi)</p>")
    [void]$sectionsHtml.AppendLine("  <p lang=""en"">$($doc.desc_en)</p>")
    [void]$sectionsHtml.AppendLine('  <ul class="lang-links">')
    [void]$sectionsHtml.AppendLine("    <li><a href=""$($doc.output_vi)"" hreflang=""vi"" lang=""vi"">Tiếng Việt</a></li>")
    [void]$sectionsHtml.AppendLine("    <li><a href=""$($doc.output_en)"" hreflang=""en"" lang=""en"">English</a></li>")
    [void]$sectionsHtml.AppendLine('  </ul>')
    [void]$sectionsHtml.AppendLine('</section>')
}

$portalTitle = "$($manifest.portal_title_vi) / $($manifest.portal_title_en)"

$indexHtml = @"
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$portalTitle</title>
<style>
$cssContent
</style>
</head>
<body class="help-portal">
<header>
  <h1>$portalTitle</h1>
</header>
<main>
  <p lang="vi">$($manifest.portal_intro_vi)</p>
  <p lang="en">$($manifest.portal_intro_en)</p>
$($sectionsHtml.ToString().TrimEnd())
</main>
<footer lang="vi">
  Mở lại trang này bằng cách nhấn "H" trên màn hình chính, sau đó Enter trên "Hướng Dẫn".
</footer>
</body>
</html>
"@

$indexPath = Join-Path $OutputDir 'index.html'
[System.IO.File]::WriteAllText($indexPath, $indexHtml, [System.Text.UTF8Encoding]::new($false))
$indexKB = [math]::Round((Get-Item $indexPath).Length / 1KB, 1)
Write-Host ("   ok ({0} KB)" -f $indexKB) -ForegroundColor Green
$built.Add([PSCustomObject]@{ Id = 'index'; Lang = 'portal'; Output = 'index.html'; SizeKB = $indexKB })

# ----- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "=== Build summary ===" -ForegroundColor Yellow
$built | Format-Table Id, Lang, Output, SizeKB -AutoSize | Out-String | Write-Host

Write-Host ("Generated {0} file(s) under {1}" -f $built.Count, $OutputDir) -ForegroundColor Green
Write-Host "Next: git add docs\*.html ; git commit -m update ; git push" -ForegroundColor DarkGray
Write-Host "Then: bump update-manifest.json version + sync DEPLOY_ USBs." -ForegroundColor DarkGray
