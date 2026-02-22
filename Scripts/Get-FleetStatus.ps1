# Vietnam Lab Deployment - Fleet Status Dashboard
# Downloads heartbeat files from Google Drive and displays fleet overview
# Run from operator's machine (macOS/Windows) in the US
# Requires: rclone configured with 'gdrive' remote
# Last Updated: February 2026

param(
    [string]$RcloneRemote = "gdrive:VietnamLabFleet/heartbeats/",
    [string]$LocalDir = (Join-Path $PSScriptRoot "fleet-heartbeats"),
    [int]$WarnDays = 7,
    [switch]$NoDownload
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Fleet Status Dashboard" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# Download heartbeats from Google Drive
if (-not $NoDownload) {
    Write-Host "Downloading heartbeats from Google Drive..." -ForegroundColor DarkGray
    if (-not (Test-Path $LocalDir)) { New-Item -Path $LocalDir -ItemType Directory -Force | Out-Null }

    try {
        $rclone = Get-Command rclone -ErrorAction Stop
        & rclone sync $RcloneRemote $LocalDir --quiet 2>&1 | Out-Null
        Write-Host "Downloaded." -ForegroundColor DarkGray
    } catch {
        Write-Host "[WARN] rclone not found or sync failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "       Install rclone and configure 'gdrive' remote, or use -NoDownload with local files" -ForegroundColor Yellow

        if (-not (Test-Path $LocalDir) -or (Get-ChildItem $LocalDir -Filter "*.json" -ErrorAction SilentlyContinue).Count -eq 0) {
            Write-Host "`nNo heartbeat files available." -ForegroundColor Red
            pause; exit 1
        }
    }
}

# Read heartbeat files
$heartbeats = @()
$files = Get-ChildItem $LocalDir -Filter "*.json" -ErrorAction SilentlyContinue

if ($files.Count -eq 0) {
    Write-Host "No heartbeat files found in $LocalDir" -ForegroundColor Yellow
    pause; exit 0
}

foreach ($file in $files) {
    try {
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $lastSeen = [DateTime]::Parse($data.last_seen)
        $daysSince = [math]::Round(((Get-Date) - $lastSeen).TotalDays, 1)

        $heartbeats += [PSCustomObject]@{
            PC         = $data.pc
            LastSeen   = $lastSeen.ToString("yyyy-MM-dd HH:mm")
            DaysAgo    = $daysSince
            Manifest   = $data.manifest_version
            Tailscale  = if ($data.tailscale_ip -and $data.tailscale_ip -ne "none") { $data.tailscale_ip } else { "-" }
            Pass       = $data.pass
            Warn       = $data.warn
            Fail       = $data.fail
            Uptime     = "$($data.uptime_days)d"
            Update     = $data.update_status
            Status     = if ($daysSince -gt $WarnDays) { "STALE" } elseif ($data.fail -gt 0) { "ISSUES" } else { "OK" }
        }
    } catch {
        Write-Host "  Could not parse $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Sort by PC name
$heartbeats = $heartbeats | Sort-Object PC

# Display table
$heartbeats | ForEach-Object {
    $color = switch ($_.Status) { "OK" { "Green" } "ISSUES" { "Yellow" } "STALE" { "Red" } default { "Gray" } }
    $line = "{0,-7} {1,-17} {2,-12} {3,-16} {4,4} {5,4} {6,4}  {7,-8} {8,-15} {9}" -f `
        $_.PC, $_.LastSeen, $_.Manifest, $_.Tailscale, $_.Pass, $_.Warn, $_.Fail, $_.Uptime, $_.Update, $_.Status
    Write-Host $line -ForegroundColor $color
}

# Summary
$totalPCs = $heartbeats.Count
$okCount = ($heartbeats | Where-Object { $_.Status -eq "OK" }).Count
$staleCount = ($heartbeats | Where-Object { $_.Status -eq "STALE" }).Count
$issueCount = ($heartbeats | Where-Object { $_.Status -eq "ISSUES" }).Count

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Reporting: $totalPCs PCs  |  OK: $okCount  |  Issues: $issueCount  |  Stale (>${WarnDays}d): $staleCount" -ForegroundColor White

if ($staleCount -gt 0) {
    Write-Host "`nStale PCs (not seen in $WarnDays+ days):" -ForegroundColor Red
    $heartbeats | Where-Object { $_.Status -eq "STALE" } | ForEach-Object {
        Write-Host "  $($_.PC) - last seen $($_.LastSeen) ($($_.DaysAgo) days ago)" -ForegroundColor Red
    }
}

if ($issueCount -gt 0) {
    Write-Host "`nPCs with audit failures:" -ForegroundColor Yellow
    $heartbeats | Where-Object { $_.Status -eq "ISSUES" } | ForEach-Object {
        Write-Host "  $($_.PC) - $($_.Fail) failed checks" -ForegroundColor Yellow
    }
}

# Check for expected PCs that are missing
$expectedPCs = 1..19 | ForEach-Object { "PC-{0:D2}" -f $_ }
$reportedPCs = $heartbeats.PC
$missingPCs = $expectedPCs | Where-Object { $_ -notin $reportedPCs }

if ($missingPCs.Count -gt 0) {
    Write-Host "`nMissing PCs (never reported):" -ForegroundColor Red
    Write-Host "  $($missingPCs -join ', ')" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
