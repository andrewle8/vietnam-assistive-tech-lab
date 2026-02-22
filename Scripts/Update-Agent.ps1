# Vietnam Lab Deployment - Auto-Update Agent
# Pull-based update agent that runs as a scheduled task on each PC
# Checks GitHub for update-manifest.json, downloads and applies updates
# Runs daily at 2-4 AM. Never runs during school hours (8AM-6PM).
# Last Updated: February 2026

param(
    [string]$ManifestUrl = "https://raw.githubusercontent.com/andrewle8/vietnam-assistive-tech-lab/main/update-manifest.json",
    [string]$LocalManifest = "C:\LabTools\manifest.json",
    [string]$AgentDir = "C:\LabTools\update-agent",
    [string]$AuditScript = "C:\LabTools\update-agent\7-Audit.ps1",
    [string]$RcloneExe = "C:\LabTools\rclone\rclone.exe",
    [string]$RcloneConf = "C:\LabTools\rclone\rclone.conf"
)

$ErrorActionPreference = "Stop"

# ---- Directories ----
$stagingDir  = Join-Path $AgentDir "staging"
$rollbackDir = Join-Path $AgentDir "rollback"
$resultsDir  = Join-Path $AgentDir "results"
$logsDir     = Join-Path $AgentDir "logs"
$lockFile    = Join-Path $AgentDir "update.lock"

foreach ($dir in @($AgentDir, $stagingDir, $rollbackDir, $resultsDir, $logsDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

# ---- Logging ----
$logFile = Join-Path $logsDir "$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-AgentLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Result {
    param([hashtable]$Result)
    $resultFile = Join-Path $resultsDir "update-$(Get-Date -Format 'yyyy-MM-dd').json"
    $Result | ConvertTo-Json -Depth 5 | Out-File $resultFile -Encoding UTF8
    Write-AgentLog "Result written to $resultFile"

    # Upload to Google Drive if rclone is available
    if ((Test-Path $RcloneExe) -and (Test-Path $RcloneConf)) {
        $pcName = $env:COMPUTERNAME
        try {
            & $RcloneExe copy $resultFile "gdrive:VietnamLabFleet/$pcName/" --config $RcloneConf --quiet 2>&1 | Out-Null
            Write-AgentLog "Result uploaded to gdrive:VietnamLabFleet/$pcName/"
        } catch {
            Write-AgentLog "Could not upload result: $($_.Exception.Message)" "WARN"
        }
    }
}

# ---- Safety checks ----

# Check: not during school hours (8AM-6PM local time)
$hour = (Get-Date).Hour
if ($hour -ge 8 -and $hour -lt 18) {
    Write-AgentLog "School hours (8AM-6PM). Skipping update check."
    exit 0
}

# Check: internet connectivity
try {
    $dns = [System.Net.Dns]::GetHostAddresses("github.com")
    if (-not $dns) { throw "No DNS" }
} catch {
    Write-AgentLog "No internet. Skipping update check."
    exit 0
}

# Check: lock file (prevent concurrent runs)
if (Test-Path $lockFile) {
    $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($lockAge.TotalHours -lt 4) {
        Write-AgentLog "Lock file exists (age: $([math]::Round($lockAge.TotalMinutes))m). Another update may be in progress."
        exit 0
    } else {
        Write-AgentLog "Stale lock file (age: $([math]::Round($lockAge.TotalHours, 1))h). Removing." "WARN"
        Remove-Item $lockFile -Force
    }
}

# ---- Step 1: Fetch remote update manifest ----

Write-AgentLog "Checking for updates from $ManifestUrl"

try {
    $ProgressPreference = 'SilentlyContinue'
    $response = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing -TimeoutSec 30
    $remoteManifest = $response.Content | ConvertFrom-Json
} catch {
    Write-AgentLog "Could not fetch update manifest: $($_.Exception.Message)" "WARN"
    exit 0
}

# ---- Step 2: Compare versions ----

if (-not (Test-Path $LocalManifest)) {
    Write-AgentLog "Local manifest not found at $LocalManifest" "WARN"
    exit 0
}

$localData = Get-Content $LocalManifest -Raw | ConvertFrom-Json
$localVersion = $localData.manifest_version
$remoteVersion = $remoteManifest.update_version

Write-AgentLog "Local version: $localVersion | Remote version: $remoteVersion"

if ($remoteVersion -le $localVersion) {
    Write-AgentLog "Already up to date. No action needed."
    exit 0
}

# Check minimum version requirement
if ($remoteManifest.min_local_version -and $localVersion -lt $remoteManifest.min_local_version) {
    Write-AgentLog "Local version $localVersion is below minimum $($remoteManifest.min_local_version). Cannot apply update." "ERROR"
    Write-Result @{
        computer = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        status = "FAILED"
        error = "Local version below minimum requirement"
        local_version = $localVersion
        remote_version = $remoteVersion
    }
    exit 1
}

# Check if there are any packages to update
if (-not $remoteManifest.packages -or $remoteManifest.packages.Count -eq 0) {
    Write-AgentLog "Update manifest has no packages. Nothing to do."
    exit 0
}

# ---- Step 3: Acquire lock ----

"PID=$PID timestamp=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Out-File $lockFile -Force
Write-AgentLog "Lock acquired"

try {
    # ---- Step 4: Pre-download checks ----

    $totalSize = ($remoteManifest.packages | ForEach-Object { $_.size_bytes } | Measure-Object -Sum).Sum
    if (-not $totalSize) { $totalSize = 0 }
    $freeBytes = (Get-PSDrive C).Free
    $requiredBytes = $totalSize * 2  # 2x safety margin

    if ($requiredBytes -gt 0 -and $freeBytes -lt $requiredBytes) {
        Write-AgentLog "Insufficient disk space. Need $([math]::Round($requiredBytes/1MB))MB, have $([math]::Round($freeBytes/1MB))MB" "ERROR"
        Write-Result @{
            computer = $env:COMPUTERNAME
            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            status = "FAILED"
            error = "Insufficient disk space"
            local_version = $localVersion
            remote_version = $remoteVersion
        }
        return
    }

    $releaseBase = $remoteManifest.release_base
    $packageResults = @()
    $allSuccess = $true

    # ---- Step 5: Download and verify packages ----

    foreach ($pkg in $remoteManifest.packages) {
        Write-AgentLog "Processing package: $($pkg.id) v$($pkg.version)"

        $stagingPath = Join-Path $stagingDir $pkg.filename
        $downloadUrl = "$releaseBase/$($pkg.filename)"

        # Download
        try {
            $ProgressPreference = 'SilentlyContinue'
            $tmpPath = "$stagingPath.tmp"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpPath -UseBasicParsing -TimeoutSec 300
        } catch {
            Write-AgentLog "Download failed for $($pkg.id): $($_.Exception.Message)" "ERROR"
            $packageResults += @{ id = $pkg.id; status = "DOWNLOAD_FAILED"; error = $_.Exception.Message }
            $allSuccess = $false
            if ($pkg.critical) { break }
            continue
        }

        # Verify SHA256
        if ($pkg.sha256) {
            $actualHash = (Get-FileHash $tmpPath -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -ne $pkg.sha256.ToLower()) {
                Write-AgentLog "SHA256 mismatch for $($pkg.id). Expected: $($pkg.sha256), Got: $actualHash" "ERROR"
                Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
                $packageResults += @{ id = $pkg.id; status = "SHA256_MISMATCH"; error = "Hash verification failed" }
                $allSuccess = $false
                if ($pkg.critical) { break }
                continue
            }
            Write-AgentLog "SHA256 verified for $($pkg.id)"
        }

        # Move to final staging path
        Move-Item -Path $tmpPath -Destination $stagingPath -Force

        # ---- Step 6: Install ----

        # Backup current installer to rollback dir
        $rollbackPath = Join-Path $rollbackDir $pkg.filename
        if ($localData.software.PSObject.Properties[$pkg.id]) {
            $currentInstaller = $localData.software.$($pkg.id).installer
            # Try to find the current installer
            $usbRoot = Split-Path -Parent (Split-Path -Parent $AgentDir)
            $currentPath = Join-Path $usbRoot "Installers" | Get-ChildItem -Recurse -Filter $currentInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($currentPath) {
                Copy-Item $currentPath.FullName -Destination $rollbackPath -Force -ErrorAction SilentlyContinue
            }
        }

        # Build install command
        $installArgs = if ($pkg.install_args) { $pkg.install_args } else { @() }
        $ext = [System.IO.Path]::GetExtension($pkg.filename).ToLower()

        try {
            Write-AgentLog "Installing $($pkg.id)..."
            switch ($ext) {
                ".msi" {
                    $msiArgs = "/i `"$stagingPath`" /quiet /norestart"
                    $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
                }
                ".exe" {
                    $exeArgs = ($installArgs -join " ")
                    if (-not $exeArgs) { $exeArgs = "/S" }
                    $proc = Start-Process $stagingPath -ArgumentList $exeArgs -Wait -PassThru
                }
                default {
                    Write-AgentLog "Unknown installer type: $ext" "ERROR"
                    $packageResults += @{ id = $pkg.id; status = "UNKNOWN_TYPE"; error = "Unsupported installer extension: $ext" }
                    continue
                }
            }

            if ($proc.ExitCode -ne 0) {
                throw "Installer exited with code $($proc.ExitCode)"
            }

            Write-AgentLog "Install completed for $($pkg.id)"

            # Verify installation by checking paths
            $verified = $false
            if ($localData.software.PSObject.Properties[$pkg.id]) {
                foreach ($path in $localData.software.$($pkg.id).paths) {
                    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
                    if (Test-Path $expandedPath) { $verified = $true; break }
                }
            } else {
                $verified = $true  # No path to check
            }

            if ($verified) {
                Write-AgentLog "$($pkg.id) verified successfully"
                $packageResults += @{ id = $pkg.id; status = "SUCCESS"; version = $pkg.version }
            } else {
                throw "Post-install verification failed - binary not found at expected path"
            }

        } catch {
            Write-AgentLog "Install failed for $($pkg.id): $($_.Exception.Message)" "ERROR"

            # Rollback for critical packages
            if ($pkg.critical -and (Test-Path $rollbackPath)) {
                Write-AgentLog "Rolling back $($pkg.id)..." "WARN"
                try {
                    switch ($ext) {
                        ".msi" {
                            Start-Process "msiexec.exe" -ArgumentList "/i `"$rollbackPath`" /quiet /norestart" -Wait
                        }
                        ".exe" {
                            Start-Process $rollbackPath -ArgumentList "/S" -Wait
                        }
                    }
                    Write-AgentLog "Rollback completed for $($pkg.id)"
                } catch {
                    Write-AgentLog "CRITICAL: Rollback failed for $($pkg.id): $($_.Exception.Message)" "ERROR"
                }
            }

            $packageResults += @{ id = $pkg.id; status = "INSTALL_FAILED"; error = $_.Exception.Message }
            $allSuccess = $false
            if ($pkg.critical) { break }
        }
    }

    # ---- Step 7: Run update scripts ----

    if ($remoteManifest.scripts -and $remoteManifest.scripts.Count -gt 0) {
        foreach ($script in $remoteManifest.scripts) {
            Write-AgentLog "Running update script: $($script.id)"
            $scriptPath = Join-Path $stagingDir $script.filename
            $scriptUrl = "$releaseBase/$($script.filename)"

            try {
                Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing -TimeoutSec 60

                if ($script.sha256) {
                    $actualHash = (Get-FileHash $scriptPath -Algorithm SHA256).Hash.ToLower()
                    if ($actualHash -ne $script.sha256.ToLower()) {
                        Write-AgentLog "SHA256 mismatch for script $($script.id)" "ERROR"
                        continue
                    }
                }

                & $scriptPath 2>&1 | ForEach-Object { Write-AgentLog "  $_" }
                Write-AgentLog "Script $($script.id) completed"
            } catch {
                Write-AgentLog "Script $($script.id) failed: $($_.Exception.Message)" "ERROR"
            }
        }
    }

    # ---- Step 8: Update local manifest version ----

    if ($allSuccess -and (Test-Path $LocalManifest)) {
        $localData.manifest_version = $remoteVersion
        $localData | ConvertTo-Json -Depth 5 | Out-File $LocalManifest -Encoding UTF8
        Write-AgentLog "Local manifest updated to version $remoteVersion"
    }

    # ---- Step 9: Report results ----

    $overallStatus = if ($allSuccess) { "SUCCESS" } else { "PARTIAL_FAILURE" }
    Write-AgentLog "Update complete. Status: $overallStatus"

    Write-Result @{
        computer = $env:COMPUTERNAME
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        status = $overallStatus
        local_version = $localVersion
        remote_version = $remoteVersion
        packages = $packageResults
    }

} finally {
    # ---- Always release lock ----
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        Write-AgentLog "Lock released"
    }

    # Clean staging
    Get-ChildItem $stagingDir -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
