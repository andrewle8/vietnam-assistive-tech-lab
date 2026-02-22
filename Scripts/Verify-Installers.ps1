# Vietnam Lab Deployment - Installer Verification
# Pre-flight validation: verifies all installer files exist with correct checksums
# Run before getting on the plane!
# Last Updated: February 2026

param(
    [string]$DestinationRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Installers"),
    [string]$SourcesFile = (Join-Path $PSScriptRoot "installer-sources.json"),
    [string]$ManifestFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"),
    [string]$ChecksumFile = (Join-Path $PSScriptRoot "installer-checksums.json")
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Installer Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pre-flight check: all files present + correct checksums" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $SourcesFile)) {
    Write-Host "[ERROR] installer-sources.json not found" -ForegroundColor Red
    pause; exit 1
}
if (-not (Test-Path $ManifestFile)) {
    Write-Host "[ERROR] manifest.json not found" -ForegroundColor Red
    pause; exit 1
}

$sources = Get-Content $SourcesFile -Raw | ConvertFrom-Json
$manifest = Get-Content $ManifestFile -Raw | ConvertFrom-Json

$checksums = @{}
if (Test-Path $ChecksumFile) {
    $existing = Get-Content $ChecksumFile -Raw | ConvertFrom-Json
    foreach ($prop in $existing.PSObject.Properties) {
        $checksums[$prop.Name] = $prop.Value
    }
} else {
    Write-Host "[WARN] No checksum file found. Run 0-Download-Installers.ps1 first." -ForegroundColor Yellow
}

$pass = 0
$fail = 0
$warn = 0
$results = @()

function Get-VersionForPackage {
    param([string]$PackageId)
    $sw = $manifest.software.PSObject.Properties | Where-Object { $_.Name -eq $PackageId }
    if ($sw) { return $sw.Value.version }
    return $null
}

foreach ($entry in ($sources.PSObject.Properties | Where-Object { $_.Name -notlike "_*" })) {
    $id = $entry.Name
    $info = $entry.Value
    $version = if ($info.version) { $info.version } else { Get-VersionForPackage $id }
    if (-not $version) { $version = "" }

    # Determine what file(s) to check
    $filesToCheck = @()

    if ($info.source -eq "manual") {
        $basePath = Join-Path $DestinationRoot $info.expected_path

        if ($info.files) {
            foreach ($f in $info.files) {
                $filesToCheck += @{ Id = "$id/$f"; Path = (Join-Path $basePath $f); Critical = $false }
            }
        } elseif ($basePath.EndsWith("/") -or $basePath.EndsWith("\")) {
            $filesToCheck += @{ Id = $id; Path = $basePath; IsDir = $true; Critical = $false }
        } else {
            $filesToCheck += @{ Id = $id; Path = $basePath; Critical = $false }
        }
    } else {
        # Vendor, GitHub, or Kiwix - check the final file
        if ($info.extract -and $info.final_path) {
            $fpRaw = $info.final_path.Replace("{version}", $version)
            $filePath = Join-Path $DestinationRoot $fpRaw
        } elseif ($info.source -eq "kiwix") {
            $kiwixContent = $manifest.kiwix_content.PSObject.Properties | Where-Object { $_.Name -eq $id }
            if ($kiwixContent) {
                $filename = $kiwixContent.Value
                $destRelative = $info.destination.Replace("{filename}", $filename)
                $filePath = Join-Path $DestinationRoot $destRelative
            } else {
                $filePath = $null
            }
        } else {
            $destRelative = $info.destination.Replace("{version}", $version)
            $filePath = Join-Path $DestinationRoot $destRelative
        }

        if ($filePath) {
            $isCritical = $false
            $sw = $manifest.software.PSObject.Properties | Where-Object { $_.Name -eq $id }
            if ($sw -and $sw.Value.critical) { $isCritical = $true }
            $isDir = $info.final_path -and ($info.final_path.EndsWith("/") -or $info.final_path.EndsWith("\"))
            $filesToCheck += @{ Id = $id; Path = $filePath; IsDir = $isDir; Critical = $isCritical }
        }
    }

    # Verify each file
    foreach ($file in $filesToCheck) {
        $fileId = $file.Id
        $filePath = $file.Path
        $status = "PASS"
        $detail = ""

        if ($file.IsDir) {
            if (Test-Path $filePath) {
                $contents = @(Get-ChildItem -Path $filePath -ErrorAction SilentlyContinue)
                if ($contents.Count -gt 0) {
                    $detail = "$($contents.Count) files"
                    $status = "PASS"
                } else {
                    $detail = "Empty directory"
                    $status = "WARN"
                }
            } else {
                $detail = "Directory missing"
                $status = "FAIL"
            }
        } elseif (-not (Test-Path $filePath)) {
            $detail = "FILE MISSING"
            $status = if ($file.Critical) { "FAIL" } else { "WARN" }
        } else {
            $fileInfo = Get-Item $filePath
            if ($fileInfo.Length -eq 0) {
                $detail = "ZERO BYTES"
                $status = "FAIL"
            } else {
                $sizeMB = [math]::Round($fileInfo.Length / 1MB, 1)
                $detail = "${sizeMB} MB"

                # Check SHA256 if we have a recorded checksum
                # Try exact fileId first (e.g. "nvda_addons/VLC-2025.1.0.nvda-addon"), then base id
                $checksumId = $fileId
                if (-not $checksums.ContainsKey($checksumId)) {
                    $checksumId = $fileId -replace '/.*$', ''
                }
                if ($checksums.ContainsKey($checksumId) -and -not $file.IsDir) {
                    $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLower()
                    if ($actualHash -ne $checksums[$checksumId]) {
                        $detail += " CHECKSUM MISMATCH"
                        $status = "FAIL"
                    } else {
                        $detail += " checksum OK"
                    }
                } else {
                    $detail += " (no checksum)"
                    $status = "WARN"
                }
            }
        }

        $icon = switch ($status) { "PASS" { "PASS" } "FAIL" { "FAIL" } "WARN" { "WARN" } }
        $color = switch ($status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }

        Write-Host "[$icon] " -ForegroundColor $color -NoNewline
        Write-Host "$fileId" -NoNewline
        Write-Host " - $detail" -ForegroundColor $color

        switch ($status) {
            "PASS" { $pass++ }
            "FAIL" { $fail++ }
            "WARN" { $warn++ }
        }

        $results += [PSCustomObject]@{
            Id     = $fileId
            Path   = $filePath
            Status = $status
            Detail = $detail
        }
    }
}

# ---- Summary ----
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:   $pass" -ForegroundColor Green
Write-Host "Warnings: $warn" -ForegroundColor $(if($warn -gt 0){"Yellow"}else{"Green"})
Write-Host "Failed:   $fail" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})

if ($fail -gt 0) {
    Write-Host "`nFailed items:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  $($_.Id): $($_.Detail)" -ForegroundColor Red
    }
    Write-Host "`nRun 0-Download-Installers.ps1 to download missing files." -ForegroundColor Yellow
}

if ($fail -eq 0 -and $warn -eq 0) {
    Write-Host "`nAll installers verified. Ready for deployment!" -ForegroundColor Green
} elseif ($fail -eq 0) {
    Write-Host "`nNo critical failures. Review warnings above." -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan

pause
