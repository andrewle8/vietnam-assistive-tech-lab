# Vietnam Lab Deployment - Fleet Status Check
# Run from orchestration workstation
# Shows online/offline and WinRM status for all 19 PCs

param(
    [int]$TotalPCs = 19
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Fleet Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Checking $TotalPCs laptops...`n" -ForegroundColor DarkGray

$results = @()

for ($i = 1; $i -le $TotalPCs; $i++) {
    $pcName = "PC-{0:D2}" -f $i
    Write-Host "  Checking $pcName..." -ForegroundColor DarkGray -NoNewline

    $ping = Test-Connection -ComputerName $pcName -Count 1 -Quiet -ErrorAction SilentlyContinue
    $ip = $null
    $winrm = $false

    if ($ping) {
        try {
            $dns = [System.Net.Dns]::GetHostAddresses($pcName) | Where-Object { $_.AddressFamily -eq "InterNetwork" }
            $ip = $dns[0].ToString()
        } catch {
            $ip = "?"
        }

        try {
            $session = New-PSSession -ComputerName $pcName -ErrorAction Stop
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
        Write-Host " Online" -ForegroundColor Green
    } else {
        Write-Host " Offline" -ForegroundColor Red
    }
}

$online  = ($results | Where-Object { $_.Online -eq "Online" }).Count
$withRM  = ($results | Where-Object { $_.WinRM -eq "OK" }).Count

Write-Host "`n========================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Online: $online/$TotalPCs    WinRM Ready: $withRM/$TotalPCs" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan
