# Vietnam Lab Deployment - Fleet Health Reporter
# Runs as scheduled task on each PC. Executes audit and uploads to Google Drive.
# Scheduled by Configure-Laptop.ps1 (LabFleetReport task)
# Last Updated: February 2026

param(
    [string]$ManifestPath = "C:\LabTools\manifest.json",
    [string]$AuditScript = "C:\LabTools\update-agent\7-Audit.ps1",
    [string]$RcloneExe = "C:\LabTools\rclone\rclone.exe",
    [string]$RcloneConf = "C:\LabTools\rclone\rclone.conf",
    [string]$ResultsDir = "C:\LabTools\fleet-reports"
)

$ErrorActionPreference = "Stop"

# Create results directory
if (-not (Test-Path $ResultsDir)) {
    New-Item -Path $ResultsDir -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $ResultsDir "report.log"
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$ts] $Message" -ErrorAction SilentlyContinue
}

# ---- Check internet ----

try {
    $dns = [System.Net.Dns]::GetHostAddresses("google.com")
    if (-not $dns) { throw "No DNS" }
} catch {
    Write-Log "No internet. Skipping report."
    exit 0
}

Write-Log "Starting fleet health report for $env:COMPUTERNAME"

# ---- Get Tailscale IP ----

$tailscaleIP = $null
$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tailscaleExe) {
    try {
        $tsIP = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
        if ($tsIP -match "^100\.") { $tailscaleIP = $tsIP.Trim() }
    } catch {}
}

# ---- Get system uptime ----

$uptimeDays = 0
try {
    $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeDays = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)
} catch {}

# ---- Get manifest version ----

$manifestVersion = "unknown"
if (Test-Path $ManifestPath) {
    try {
        $m = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $manifestVersion = $m.manifest_version
    } catch {}
}

# ---- Get update status ----

$updateStatus = "unknown"
$lastUpdateCheck = $null
$updateResultsDir = "C:\LabTools\update-agent\results"
if (Test-Path $updateResultsDir) {
    $latestResult = Get-ChildItem $updateResultsDir -Filter "update-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestResult) {
        try {
            $result = Get-Content $latestResult.FullName -Raw | ConvertFrom-Json
            $updateStatus = $result.status
            $lastUpdateCheck = $latestResult.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        } catch {}
    } else {
        $updateStatus = "no_updates_yet"
    }
}

# ---- Get rclone last backup timestamp ----

$lastBackup = $null
$rcloneLogDir = "C:\LabTools\rclone\logs"
if (Test-Path $rcloneLogDir) {
    $latestLog = Get-ChildItem $rcloneLogDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        $lastBackup = $latestLog.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
    }
}

# ---- Run audit if available ----

$auditPass = 0
$auditWarn = 0
$auditFail = 0

# Fallback: try to find audit script
if (-not (Test-Path $AuditScript)) {
    $AuditScript = Join-Path (Split-Path $PSScriptRoot) "Scripts\7-Audit.ps1"
}

$auditJsonPath = Join-Path $ResultsDir "audit-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd').json"
if (Test-Path $AuditScript) {
    try {
        & $AuditScript -ManifestPath $ManifestPath -OutputJson -LogPath (Join-Path $ResultsDir "audit.log") 2>&1 | Out-Null

        # Find the generated audit JSON
        $generatedAudit = Get-ChildItem (Split-Path $AuditScript) -Filter "audit-$env:COMPUTERNAME-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($generatedAudit) {
            $auditData = Get-Content $generatedAudit.FullName -Raw | ConvertFrom-Json
            $auditPass = $auditData.pass
            $auditWarn = $auditData.warn
            $auditFail = $auditData.fail
            Copy-Item $generatedAudit.FullName -Destination $auditJsonPath -Force
        }
    } catch {
        Write-Log "Audit script failed: $($_.Exception.Message)"
    }
}

# ---- Build heartbeat ----

$heartbeat = @{
    pc               = $env:COMPUTERNAME
    last_seen        = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    manifest_version = $manifestVersion
    tailscale_ip     = if ($tailscaleIP) { $tailscaleIP } else { "none" }
    pass             = $auditPass
    warn             = $auditWarn
    fail             = $auditFail
    uptime_days      = $uptimeDays
    update_status    = $updateStatus
    last_update_check = $lastUpdateCheck
    last_backup      = $lastBackup
}

$heartbeatPath = Join-Path $ResultsDir "heartbeat.json"
$heartbeat | ConvertTo-Json -Depth 3 | Out-File $heartbeatPath -Encoding UTF8

Write-Log "Heartbeat generated: pass=$auditPass warn=$auditWarn fail=$auditFail"

# ---- Upload to Google Drive ----

if ((Test-Path $RcloneExe) -and (Test-Path $RcloneConf)) {
    $pcName = $env:COMPUTERNAME
    $rcloneArgs = "--config `"$RcloneConf`" --quiet --retries 3 --low-level-retries 10"

    try {
        # Upload heartbeat
        & $RcloneExe copyto $heartbeatPath "gdrive:VietnamLabFleet/heartbeats/$pcName.json" --config $RcloneConf --quiet 2>&1 | Out-Null
        Write-Log "Heartbeat uploaded to gdrive:VietnamLabFleet/heartbeats/$pcName.json"

        # Upload full audit report
        if (Test-Path $auditJsonPath) {
            & $RcloneExe copy $auditJsonPath "gdrive:VietnamLabFleet/$pcName/" --config $RcloneConf --quiet 2>&1 | Out-Null
            Write-Log "Audit report uploaded to gdrive:VietnamLabFleet/$pcName/"
        }

        Write-Log "Fleet report upload complete"
    } catch {
        Write-Log "Upload failed: $($_.Exception.Message)"
    }
} else {
    Write-Log "rclone not available. Report saved locally only."
}
