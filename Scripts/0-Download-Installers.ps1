# Vietnam Lab Deployment - Smart Installer Downloader
# Version: 3.0
# Downloads software from vendor URLs, GitHub Releases, or checks manual files
# Reads installer-sources.json for source definitions, manifest.json for versions
# Records SHA256 checksums to installer-checksums.json
# Last Updated: February 2026

param(
    [string]$DestinationRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Installers"),
    [string]$SourcesFile = (Join-Path $PSScriptRoot "installer-sources.json"),
    [string]$ManifestFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"),
    [string]$ChecksumFile = (Join-Path $PSScriptRoot "installer-checksums.json"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Smart Installer Downloader" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Load configuration ----

if (-not (Test-Path $SourcesFile)) {
    Write-Host "[ERROR] installer-sources.json not found at: $SourcesFile" -ForegroundColor Red
    pause; exit 1
}
if (-not (Test-Path $ManifestFile)) {
    Write-Host "[ERROR] manifest.json not found at: $ManifestFile" -ForegroundColor Red
    pause; exit 1
}

$sources = Get-Content $SourcesFile -Raw | ConvertFrom-Json
$manifest = Get-Content $ManifestFile -Raw | ConvertFrom-Json

# Load existing checksums or start fresh
$checksums = @{}
if (Test-Path $ChecksumFile) {
    $existing = Get-Content $ChecksumFile -Raw | ConvertFrom-Json
    foreach ($prop in $existing.PSObject.Properties) {
        $checksums[$prop.Name] = $prop.Value
    }
}

# GitHub Releases fallback for manual items
$releaseBase = "https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/download/installers-v1"

$successCount = 0
$failCount = 0
$skippedCount = 0
$manualCount = 0

# ---- Helper Functions ----

function Get-VersionForPackage {
    param([string]$PackageId)
    $sw = $manifest.software.PSObject.Properties | Where-Object { $_.Name -eq $PackageId }
    if ($sw) { return $sw.Value.version }
    return $null
}

function Get-SHA256 {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
}

function Test-ChecksumMatch {
    param([string]$FilePath, [string]$Id)
    if (-not (Test-Path $FilePath)) { return $false }
    if (-not $checksums.ContainsKey($Id)) { return $false }
    $actual = Get-SHA256 $FilePath
    return $actual -eq $checksums[$Id]
}

function Save-Checksums {
    $checksums | ConvertTo-Json -Depth 2 | Out-File $ChecksumFile -Encoding UTF8
}

function Invoke-Download {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 300)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
    $ProgressPreference = 'Continue'
}

function Invoke-GitHubReleaseDownload {
    param([string]$Repo, [string]$AssetPattern, [string]$Version, [string]$OutFile)

    # Try tag formats: v{version}, {version}
    $tagFormats = @("v$Version", "$Version")
    $asset = $null

    foreach ($tag in $tagFormats) {
        $apiUrl = "https://api.github.com/repos/$Repo/releases/tags/$tag"
        try {
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30 -Headers @{ "User-Agent" = "vietnam-lab-downloader" }
            $searchPattern = $AssetPattern.Replace("{version}", $Version)
            $asset = $release.assets | Where-Object { $_.name -eq $searchPattern } | Select-Object -First 1
            if ($asset) { break }
        } catch {
            continue
        }
    }

    # Fallback: search latest releases for matching asset
    if (-not $asset) {
        try {
            $apiUrl = "https://api.github.com/repos/$Repo/releases"
            $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30 -Headers @{ "User-Agent" = "vietnam-lab-downloader" }
            $searchPattern = $AssetPattern.Replace("{version}", $Version)
            foreach ($rel in $releases) {
                $asset = $rel.assets | Where-Object { $_.name -eq $searchPattern } | Select-Object -First 1
                if ($asset) { break }
            }
        } catch {}
    }

    if (-not $asset) {
        throw "Asset matching '$($AssetPattern.Replace('{version}', $Version))' not found in $Repo releases"
    }

    Write-Host "  Found: $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)" -ForegroundColor DarkGray
    Invoke-Download -Url $asset.browser_download_url -OutFile $OutFile
}

# ---- Process each source entry ----

$entries = $sources.PSObject.Properties | Where-Object { $_.Name -notlike "_*" }
$totalItems = $entries.Count
$index = 0

foreach ($entry in $entries) {
    $id = $entry.Name
    $info = $entry.Value
    $index++

    Write-Host "`n[$index/$totalItems] $id" -ForegroundColor Yellow

    $source = $info.source

    # ---- Manual sources: check existence only ----
    if ($source -eq "manual") {
        $expectedPath = Join-Path $DestinationRoot $info.expected_path

        # Handle directory-based checks (addons, games)
        if ($info.files) {
            $allPresent = $true
            foreach ($f in $info.files) {
                $fp = Join-Path $expectedPath $f
                if (-not (Test-Path $fp)) {
                    $allPresent = $false
                    Write-Host "  [MISSING] $f" -ForegroundColor Red
                }
            }
            if ($allPresent) {
                Write-Host "  [OK] All files present" -ForegroundColor Green
                $skippedCount++
            } else {
                Write-Host "  [MANUAL] $($info.instructions)" -ForegroundColor Magenta
                $manualCount++
            }
        } elseif ($expectedPath.EndsWith("/") -or $expectedPath.EndsWith("\")) {
            if (Test-Path $expectedPath) {
                $hasFiles = Get-ChildItem -Path $expectedPath -ErrorAction SilentlyContinue
                if ($hasFiles) {
                    Write-Host "  [OK] Directory exists with files" -ForegroundColor Green
                    $skippedCount++
                } else {
                    Write-Host "  [MANUAL] $($info.instructions)" -ForegroundColor Magenta
                    $manualCount++
                }
            } else {
                Write-Host "  [MANUAL] $($info.instructions)" -ForegroundColor Magenta
                $manualCount++
            }
        } else {
            if (Test-Path $expectedPath) {
                Write-Host "  [OK] File exists: $expectedPath" -ForegroundColor Green
                # Record checksum if not yet recorded
                if (-not $checksums.ContainsKey($id)) {
                    $checksums[$id] = Get-SHA256 $expectedPath
                }
                $skippedCount++
            } else {
                Write-Host "  [MANUAL] $($info.instructions)" -ForegroundColor Magenta
                $manualCount++
            }
        }
        continue
    }

    # ---- Get version ----
    $version = Get-VersionForPackage $id
    if (-not $version -and $source -ne "kiwix") {
        Write-Host "  [SKIP] No version found in manifest.json for '$id'" -ForegroundColor DarkYellow
        $skippedCount++
        continue
    }

    # ---- Determine destination path ----
    $destRelative = $info.destination
    if ($destRelative) {
        $destRelative = $destRelative.Replace("{version}", $version)
    }

    # For kiwix sources, use filename from manifest
    if ($source -eq "kiwix") {
        $kiwixContent = $manifest.kiwix_content.PSObject.Properties | Where-Object { $_.Name -eq $id }
        if ($kiwixContent) {
            $filename = $kiwixContent.Value
            $destRelative = $info.destination.Replace("{filename}", $filename)
        } else {
            Write-Host "  [SKIP] No kiwix_content entry for '$id'" -ForegroundColor DarkYellow
            $skippedCount++
            continue
        }
    }

    $destPath = Join-Path $DestinationRoot $destRelative
    $destDir = Split-Path -Parent $destPath

    # For extractable items, check the final extracted file
    $checkPath = $destPath
    if ($info.extract -and $info.final_path) {
        $checkPath = Join-Path $DestinationRoot $info.final_path
    }

    # Skip if file exists and checksum matches (unless -Force)
    if (-not $Force -and (Test-Path $checkPath)) {
        if (Test-ChecksumMatch $checkPath $id) {
            Write-Host "  [SKIP] Already exists with valid checksum" -ForegroundColor DarkYellow
            $skippedCount++
            continue
        } elseif (-not $checksums.ContainsKey($id)) {
            # File exists but no checksum recorded — record it and skip
            $checksums[$id] = Get-SHA256 $checkPath
            Write-Host "  [SKIP] Already exists (checksum recorded)" -ForegroundColor DarkYellow
            $skippedCount++
            continue
        }
    }

    # Create destination directory
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # ---- Download by source type ----
    try {
        switch ($source) {
            "vendor" {
                $url = $info.url_template.Replace("{version}", $version)
                Write-Host "  Downloading from vendor..." -ForegroundColor Cyan
                Write-Host "  URL: $url" -ForegroundColor DarkGray
                Invoke-Download -Url $url -OutFile $destPath
            }
            "github" {
                Write-Host "  Fetching from GitHub: $($info.repo)..." -ForegroundColor Cyan
                Invoke-GitHubReleaseDownload -Repo $info.repo -AssetPattern $info.asset_pattern -Version $version -OutFile $destPath
            }
            "kiwix" {
                $date = $filename -replace '.*_(\d{4}-\d{2})\.zim$', '$1'
                $url = $info.url_template.Replace("{date}", $date)
                Write-Host "  Downloading from Kiwix..." -ForegroundColor Cyan
                Write-Host "  URL: $url" -ForegroundColor DarkGray
                Write-Host "  (This may take a while for large ZIM files)" -ForegroundColor DarkGray
                Invoke-Download -Url $url -OutFile $destPath -TimeoutSec 3600
            }
        }

        # Handle extraction if needed
        if ($info.extract) {
            Write-Host "  Extracting..." -ForegroundColor Cyan
            $tempExtract = Join-Path $destDir "temp-extract-$id"
            Expand-Archive -Path $destPath -DestinationPath $tempExtract -Force

            $extractTarget = $info.extract_file
            $found = Get-ChildItem -Path $tempExtract -Filter $extractTarget -Recurse | Select-Object -First 1
            if ($found) {
                $finalDest = Join-Path $DestinationRoot $info.final_path
                $finalDir = Split-Path -Parent $finalDest
                if (-not (Test-Path $finalDir)) {
                    New-Item -Path $finalDir -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path $found.FullName -Destination $finalDest -Force
                $checkPath = $finalDest
            } else {
                # For Kiwix: the zip extracts to a folder, keep all files
                $extractedItems = Get-ChildItem -Path $tempExtract -Recurse -File
                foreach ($item in $extractedItems) {
                    Copy-Item -Path $item.FullName -Destination $destDir -Force
                }
                $checkPath = Join-Path $DestinationRoot $info.final_path
            }

            Remove-Item -Path $destPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $checkPath = $destPath
        }

        # Record file size and checksum
        $fileSize = (Get-Item $checkPath).Length / 1MB
        $checksums[$id] = Get-SHA256 $checkPath
        Save-Checksums

        Write-Host "  [OK] Downloaded ($([math]::Round($fileSize, 1)) MB)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red

        # Clean up partial downloads
        if (Test-Path $destPath) { Remove-Item -Path $destPath -Force -ErrorAction SilentlyContinue }
        $tempDir = Join-Path $destDir "temp-extract-$id"
        if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }

        $failCount++
    }
}

# Save final checksums
Save-Checksums

# ---- Summary ----
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Download Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Downloaded:  $successCount" -ForegroundColor Green
Write-Host "Skipped:     $skippedCount" -ForegroundColor Yellow
Write-Host "Failed:      $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
Write-Host "Manual:      $manualCount" -ForegroundColor $(if($manualCount -gt 0){"Magenta"}else{"Green"})

if ($manualCount -gt 0) {
    Write-Host "`nManual downloads needed:" -ForegroundColor Magenta
    Write-Host "  These files must be downloaded manually or from GitHub Release:" -ForegroundColor White
    Write-Host "  $releaseBase" -ForegroundColor Cyan
}

if ($failCount -gt 0) {
    Write-Host "`nSome downloads failed. Check your internet connection and try again." -ForegroundColor Yellow
    Write-Host "Use -Force to re-download existing files." -ForegroundColor Yellow
}

Write-Host "`nChecksums saved to: $ChecksumFile" -ForegroundColor DarkGray
Write-Host "Next: Run .\Verify-Installers.ps1 to validate all files" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

pause
