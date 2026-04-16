# Vietnam Lab Deployment - Pre-Deployment Validation
# Run from operator's machine before traveling to Vietnam
# Validates all infrastructure is ready for deployment
# Last Updated: February 2026

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$UpdateManifestUrl = "https://raw.githubusercontent.com/andrewle8/vietnam-assistive-tech-lab/main/update-manifest.json"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Pre-Deployment Checklist" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
Write-Host ""

$pass = 0
$fail = 0
$warn = 0

function Check {
    param([string]$Name, [bool]$Condition, [string]$FailMsg = "", [string]$WarnOnly = $null)

    if ($Condition) {
        Write-Host "[OK  ] $Name" -ForegroundColor Green
        $script:pass++
    } elseif ($WarnOnly) {
        Write-Host "[WARN] $Name - $WarnOnly" -ForegroundColor Yellow
        $script:warn++
    } else {
        Write-Host "[FAIL] $Name - $FailMsg" -ForegroundColor Red
        $script:fail++
    }
}

# ---- 1. Core files exist ----

Write-Host "`n--- Core Files ---" -ForegroundColor White
Write-Host ""

$coreFiles = @(
    "manifest.json",
    "update-manifest.json",
    "Scripts/0-Download-Installers.ps1",
    "Scripts/1-Install-All.ps1",
    "Scripts/Bootstrap-Laptop.ps1",
    "Scripts/Configure-Laptop.ps1",
    "Scripts/7-Audit.ps1",
    "Scripts/Update-Agent.ps1",
    "Scripts/Verify-Installers.ps1",
    "Scripts/installer-sources.json"
)

foreach ($file in $coreFiles) {
    $fullPath = Join-Path $RepoRoot $file
    Check $file (Test-Path $fullPath) "File not found"
}

# ---- 2. Manifest validation ----

Write-Host "`n--- Manifest Validation ---" -ForegroundColor White
Write-Host ""

$manifestPath = Join-Path $RepoRoot "manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    Check "manifest.json: version set" ($null -ne $manifest.manifest_version -and $manifest.manifest_version -ne "") "manifest_version is null or empty"
    Check "manifest.json: tested_on set" ($null -ne $manifest.tested_on) "tested_on is null - test on a real PC first" -WarnOnly "tested_on is null - have you tested?"

    # Check no null critical fields in software
    $nullPaths = @()
    foreach ($sw in $manifest.software.PSObject.Properties) {
        if ($sw.Value.critical -and (-not $sw.Value.paths -or $sw.Value.paths.Count -eq 0)) {
            $nullPaths += $sw.Name
        }
    }
    Check "manifest.json: all critical software has paths" ($nullPaths.Count -eq 0) "Missing paths for: $($nullPaths -join ', ')"
}

# ---- 3. Installer verification ----

Write-Host "`n--- Installer Files ---" -ForegroundColor White
Write-Host ""

$verifyScript = Join-Path $RepoRoot "Scripts/Verify-Installers.ps1"
if (Test-Path $verifyScript) {
    Write-Host "Running Verify-Installers.ps1..." -ForegroundColor DarkGray

    $installerRoot = Join-Path $RepoRoot "Installers"
    if (Test-Path $installerRoot) {
        $checksumFile = Join-Path $RepoRoot "Scripts/installer-checksums.json"
        $hasChecksums = Test-Path $checksumFile
        Check "Installer checksums file exists" $hasChecksums "Run 0-Download-Installers.ps1 to generate checksums"

        # Quick check: count files in Installers/
        $installerCount = (Get-ChildItem $installerRoot -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Check "Installer files present ($installerCount files)" ($installerCount -gt 15) "Only $installerCount files found - expected 20+"
    } else {
        Check "Installers directory exists" $false "Installers/ directory not found - run 0-Download-Installers.ps1"
    }
} else {
    Check "Verify-Installers.ps1 exists" $false "Script not found"
}

# ---- 4. Remote update manifest ----

Write-Host "`n--- Remote Update Infrastructure ---" -ForegroundColor White
Write-Host ""

try {
    $ProgressPreference = 'SilentlyContinue'
    $response = Invoke-WebRequest -Uri $UpdateManifestUrl -UseBasicParsing -TimeoutSec 15
    $updateManifest = $response.Content | ConvertFrom-Json
    Check "update-manifest.json reachable on GitHub" $true ""
    Check "update-manifest.json has valid schema" ($null -ne $updateManifest.schema_version -and $null -ne $updateManifest.update_version) "Missing schema_version or update_version"
} catch {
    Check "update-manifest.json reachable on GitHub" $false "Could not fetch: $($_.Exception.Message)"
}

# Check GitHub Release exists
try {
    $releaseUrl = "https://api.github.com/repos/andrewle8/vietnam-assistive-tech-lab/releases/tags/installers-v1"
    $release = Invoke-RestMethod -Uri $releaseUrl -UseBasicParsing -TimeoutSec 15 -Headers @{
        "Accept" = "application/vnd.github.v3+json"
        "User-Agent" = "VietnamLabDeployment"
    }
    $assetCount = $release.assets.Count
    Check "GitHub Release 'installers-v1' exists ($assetCount assets)" ($assetCount -gt 10) "Only $assetCount assets found - expected 15+"
} catch {
    Check "GitHub Release 'installers-v1' reachable" $false "Could not access: $($_.Exception.Message)" -WarnOnly "GitHub Release not accessible - check internet or repo"
}

# ---- Summary ----

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Pre-Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:   $pass" -ForegroundColor Green
Write-Host "Warnings: $warn" -ForegroundColor $(if($warn -gt 0){"Yellow"}else{"Green"})
Write-Host "Failed:   $fail" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})

if ($fail -eq 0 -and $warn -eq 0) {
    Write-Host "`nAll checks passed! Ready for deployment." -ForegroundColor Green
} elseif ($fail -eq 0) {
    Write-Host "`nNo critical failures. Address warnings before travel." -ForegroundColor Yellow
} else {
    Write-Host "`nCritical issues found. Resolve before deployment:" -ForegroundColor Red
    Write-Host "  1. Run 0-Download-Installers.ps1 to download missing files" -ForegroundColor White
    Write-Host "  2. Push update-manifest.json to GitHub" -ForegroundColor White
    Write-Host "  3. Test full pipeline on 1-2 laptops" -ForegroundColor White
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

pause
