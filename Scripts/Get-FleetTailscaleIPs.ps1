# Vietnam Lab - Fleet Tailscale IP Lookup
# Queries the Tailscale API to list all devices tagged vietnam-lab
# Run from operator's machine in the US
# Requires: Tailscale API key (create at https://login.tailscale.com/admin/settings/keys)
# Last Updated: February 2026

param(
    [string]$TailnetName,
    [string]$ApiKey,
    [string]$Tag = "vietnam-lab",
    [switch]$OutputJson
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Fleet Tailscale IPs" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

# Get API key from param or environment
if (-not $ApiKey) {
    $ApiKey = $env:TAILSCALE_API_KEY
}
if (-not $ApiKey) {
    Write-Host "[ERROR] Tailscale API key required." -ForegroundColor Red
    Write-Host "  Set environment variable TAILSCALE_API_KEY or pass -ApiKey" -ForegroundColor Yellow
    Write-Host "  Create at: https://login.tailscale.com/admin/settings/keys" -ForegroundColor Yellow
    exit 1
}

# Get tailnet name from param or try to detect
if (-not $TailnetName) {
    $TailnetName = $env:TAILSCALE_TAILNET
}
if (-not $TailnetName) {
    # Try to get from local tailscale status
    try {
        $localStatus = & tailscale status --json 2>$null | ConvertFrom-Json
        $TailnetName = $localStatus.MagicDNSSuffix -replace '\.ts\.net$', ''
    } catch {}
}
if (-not $TailnetName) {
    Write-Host "[ERROR] Tailnet name required." -ForegroundColor Red
    Write-Host "  Set environment variable TAILSCALE_TAILNET or pass -TailnetName" -ForegroundColor Yellow
    exit 1
}

# Query Tailscale API
$apiUrl = "https://api.tailscale.com/api/v2/tailnet/$TailnetName/devices"
$headers = @{
    "Authorization" = "Bearer $ApiKey"
}

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
} catch {
    Write-Host "[ERROR] API request failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Filter devices by tag
$labDevices = $response.devices | Where-Object {
    $_.tags -contains "tag:$Tag"
} | Sort-Object { $_.hostname }

if ($labDevices.Count -eq 0) {
    Write-Host "No devices found with tag '$Tag'" -ForegroundColor Yellow
    Write-Host "Ensure devices are tagged 'tag:$Tag' in the Tailscale admin console" -ForegroundColor Yellow
    exit 0
}

# Build results
$results = @()
foreach ($device in $labDevices) {
    $ipv4 = $device.addresses | Where-Object { $_ -match "^100\." } | Select-Object -First 1
    $lastSeen = if ($device.lastSeen) { [datetime]::Parse($device.lastSeen).ToString("yyyy-MM-dd HH:mm") } else { "Never" }

    $results += [PSCustomObject]@{
        Hostname   = $device.hostname
        TailscaleIP = if ($ipv4) { $ipv4 } else { "-" }
        Online     = if ($device.online) { "Online" } else { "Offline" }
        LastSeen   = $lastSeen
        OS         = $device.os
    }
}

# Output
if ($OutputJson) {
    $results | ConvertTo-Json -Depth 3
} else {
    $results | Format-Table -AutoSize

    $online = ($results | Where-Object { $_.Online -eq "Online" }).Count
    Write-Host "Devices: $($results.Count)  Online: $online  Offline: $($results.Count - $online)" -ForegroundColor White
}

Write-Host "`n========================================" -ForegroundColor Cyan
