# Vietnam Lab Deployment - Fleet Status Check
# Run from orchestration workstation or remotely via Tailscale
# Shows online/offline and WinRM status for all 19 PCs

param(
    [int]$TotalPCs = 19,
    [switch]$UseTailscale,
    [string]$TailscaleIPFile = (Join-Path $PSScriptRoot "tailscale-ips.json")
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Fleet Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Load Tailscale IPs if needed
$tailscaleIPs = @{}
if ($UseTailscale) {
    if (Test-Path $TailscaleIPFile) {
        $ipData = Get-Content $TailscaleIPFile -Raw | ConvertFrom-Json
        foreach ($prop in $ipData.PSObject.Properties) {
            $tailscaleIPs[$prop.Name] = $prop.Value
        }
        Write-Host "Mode: Tailscale VPN ($($tailscaleIPs.Count) IPs loaded)" -ForegroundColor Cyan
    } else {
        Write-Host "Mode: Tailscale VPN (no IP file found - run Get-FleetTailscaleIPs.ps1 -OutputJson first)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Mode: Local LAN" -ForegroundColor Cyan
}
Write-Host "Checking $TotalPCs laptops..." -ForegroundColor DarkGray
Write-Host ""

$results = @()

for ($i = 1; $i -le $TotalPCs; $i++) {
    $pcName = "PC-{0:D2}" -f $i
    Write-Host "  Checking $pcName..." -ForegroundColor DarkGray -NoNewline

    # Resolve target (Tailscale IP or hostname)
    $target = if ($UseTailscale -and $tailscaleIPs.ContainsKey($pcName)) {
        $tailscaleIPs[$pcName]
    } else {
        $pcName
    }

    $ping = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
    $ip = $null
    $winrm = $false

    if ($ping) {
        if ($UseTailscale -and $tailscaleIPs.ContainsKey($pcName)) {
            $ip = $tailscaleIPs[$pcName]
        } else {
            try {
                $dns = [System.Net.Dns]::GetHostAddresses($target) | Where-Object { $_.AddressFamily -eq "InterNetwork" }
                $ip = $dns[0].ToString()
            } catch {
                $ip = "?"
            }
        }

        try {
            $session = New-PSSession -ComputerName $target -ErrorAction Stop
            $winrm = $true
            Remove-PSSession $session
        } catch {
            $winrm = $false
        }
    }

    $results += [PSCustomObject]@{
        PC     = $pcName
        IP     = if ($ip) { $ip } else { "-" }
        Online = if ($ping) { "Online" } else { "Offline" }
        WinRM  = if ($winrm) { "OK" } else { "-" }
    }

    if ($ping) {
        Write-Host " Online" -ForegroundColor Green -NoNewline
        if ($winrm) { Write-Host " (WinRM OK)" -ForegroundColor Green } else { Write-Host " (no WinRM)" -ForegroundColor Yellow }
    } else {
        Write-Host " Offline" -ForegroundColor Red
    }
}

$online  = ($results | Where-Object { $_.Online -eq "Online" }).Count
$withRM  = ($results | Where-Object { $_.WinRM -eq "OK" }).Count

Write-Host "`n========================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Online: $online/$TotalPCs    WinRM Ready: $withRM/$TotalPCs" -ForegroundColor White
if ($UseTailscale) {
    Write-Host "Via: Tailscale VPN" -ForegroundColor Cyan
}
Write-Host "`n========================================" -ForegroundColor Cyan
