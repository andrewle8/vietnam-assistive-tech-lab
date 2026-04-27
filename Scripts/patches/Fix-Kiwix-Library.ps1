# Fix-Kiwix-Library.ps1
# USB-walkup patch: copies the canonical Kiwix library.xml (with full metadata —
# size, description, creator, date) into the Student-profile location so the
# Wikipedia + Wiktionary entries appear correctly in the kiwix-desktop "Local
# files" tab. Without `size`, kiwix-desktop 2.5.1 either lists books with 0
# bytes or hides them entirely.
#
# Source library.xml lives at <USB>\Config\kiwix-config\library.xml. The path
# is resolved relative to this script's own location so it works from any
# DEPLOY_ USB regardless of drive letter.
#
# Run from elevated PowerShell:
#   & "<USB>:\Scripts\patches\Fix-Kiwix-Library.ps1"
#
# Idempotent. Does not restart Kiwix; new metadata is picked up on next launch.

param(
    [string]$StudentProfile = "C:\Users\Student",
    [string]$LibrarySource  = (Join-Path $PSScriptRoot "..\..\Config\kiwix-config\library.xml")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $StudentProfile)) {
    Write-Host "Fix-Kiwix-Library: Student profile not found at $StudentProfile - skipping."
    exit 0
}

if (-not (Test-Path $LibrarySource)) {
    Write-Error "Fix-Kiwix-Library: source library.xml not found at $LibrarySource"
    exit 1
}

$libraryDir  = Join-Path $StudentProfile "AppData\Roaming\kiwix-desktop"
$libraryFile = Join-Path $libraryDir "library.xml"

if (-not (Test-Path $libraryDir)) {
    New-Item -Path $libraryDir -ItemType Directory -Force | Out-Null
}

Copy-Item -Path $LibrarySource -Destination $libraryFile -Force

# Restore Student modify access (script may run as Admin/SYSTEM and leave
# Admin-owned files behind otherwise).
icacls $libraryDir /grant "Student:(OI)(CI)M" /T /Q 2>$null | Out-Null

$srcSize = (Get-Item $LibrarySource).Length
$dstSize = (Get-Item $libraryFile).Length
Write-Host "Fix-Kiwix-Library: copied $LibrarySource -> $libraryFile"
Write-Host "Fix-Kiwix-Library: $srcSize bytes -> $dstSize bytes"
Write-Host "Fix-Kiwix-Library: done. Library will reflect new metadata on next Kiwix launch."
exit 0
