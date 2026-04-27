# Fix-Kiwix-Library.ps1
# Remote-update payload: rewrites the Student-profile Kiwix library.xml with full
# metadata (size, description, creator, date) so the local Wikipedia + Wiktionary
# books appear correctly in the Kiwix-desktop "Local files" tab.
#
# Background: the version of library.xml shipped with the initial deploy had only
# id/path/title/language/name/tags/articleCount/mediaCount. Kiwix-desktop 2.5.1
# requires `size` (KB) at minimum to display book entries; without it the GUI
# either lists books with 0 bytes or hides them entirely.
#
# Runs as SYSTEM via Update-Agent. Writes to Student's profile via absolute path
# (NEVER $env:APPDATA — that resolves to SYSTEM profile under the agent).
#
# Idempotent: safe to re-run. Does not restart Kiwix; new metadata is picked up
# on the next launch.

param(
    [string]$StudentProfile = "C:\Users\Student",
    [string]$KiwixDir       = "C:\Program Files\Kiwix"
)

$ErrorActionPreference = "Stop"

$wikipediaZim  = Join-Path $KiwixDir "wikipedia_vi_all_mini_2025-11.zim"
$wiktionaryZim = Join-Path $KiwixDir "wiktionary_vi_all_nopic_2025-12.zim"

$libraryDir  = Join-Path $StudentProfile "AppData\Roaming\kiwix-desktop"
$libraryFile = Join-Path $libraryDir "library.xml"

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Fix-Kiwix-Library: Student profile not found at $StudentProfile - skipping."
    exit 0
}

if (-not (Test-Path $wikipediaZim) -or -not (Test-Path $wiktionaryZim)) {
    Write-Warning "Fix-Kiwix-Library: one or both ZIM files missing under $KiwixDir - skipping."
    Write-Warning "  Wikipedia ZIM exists: $(Test-Path $wikipediaZim)"
    Write-Warning "  Wiktionary ZIM exists: $(Test-Path $wiktionaryZim)"
    exit 0
}

# Compute size in KB (Kiwix library.xml uses KB, not bytes)
$wikipediaKb  = [int]([math]::Floor((Get-Item $wikipediaZim).Length  / 1024))
$wiktionaryKb = [int]([math]::Floor((Get-Item $wiktionaryZim).Length / 1024))

Write-Host "Fix-Kiwix-Library: computed sizes:"
Write-Host "  wikipedia  = $wikipediaKb KB"
Write-Host "  wiktionary = $wiktionaryKb KB"

if (-not (Test-Path $libraryDir)) {
    New-Item -Path $libraryDir -ItemType Directory -Force | Out-Null
}

$libraryXml = @"
<library version="20110515">
  <book id="174b68cc-69aa-c969-1ffd-c227be005769" path="$wikipediaZim" title="Wikipedia" description="Wikipedia tiếng Việt (bản rút gọn)" language="vie" creator="Wikipedia" publisher="Kiwix" name="wikipedia_vi_all_mini" flavour="mini" category="wikipedia" tags="_pictures:no;_videos:no;_details:no;_ftindex:yes;wikipedia" date="2025-11-01" articleCount="1608613" mediaCount="7184" size="$wikipediaKb" />
  <book id="85679565-5cc4-3b39-890e-a57ac1b431ab" path="$wiktionaryZim" title="Wiktionary" description="Từ điển Wiktionary tiếng Việt (không có hình ảnh)" language="vie" creator="Wiktionary" publisher="Kiwix" name="wiktionary_vi_all_nopic" flavour="nopic" category="wiktionary" tags="_pictures:no;_videos:no;_details:no;_ftindex:yes;wiktionary" date="2025-12-01" articleCount="326807" mediaCount="1377" size="$wiktionaryKb" />
</library>
"@

# Write as UTF-8 without BOM (matches what Configure-Laptop.ps1 deploys)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($libraryFile, $libraryXml, $utf8NoBom)

# Restore Student's modify access on the dir tree (the file may inherit, but be
# explicit — the agent runs as SYSTEM and writes Admin-owned files by default).
icacls $libraryDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

Write-Host "Fix-Kiwix-Library: wrote $libraryFile ($([math]::Round((Get-Item $libraryFile).Length / 1KB, 2)) KB)"
Write-Host "Fix-Kiwix-Library: done. Library will reflect new metadata on next Kiwix launch."
exit 0
