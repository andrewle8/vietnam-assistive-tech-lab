# Vietnam Lab Deployment - Master Orchestration Script
# Run from i9 orchestration workstation
# Deploys software pipeline to all 19 laptops in parallel batches

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Discovery","Install","Verify","Configure","HealthCheck","All")]
    [string]$Phase,

    [string]$PCList,
    [int]$BatchSize = 5,
    [int]$TotalPCs = 19,
    [string]$ScriptsPath = "\\AndrewServer\Data\Vietnam-Lab-Kit\Scripts",
    [string]$LogDir = "$PSScriptRoot\logs"
)

# ---- Setup ----

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir "deploy-$Phase-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        default   { "Gray" }
    }
    Write-Host $line -ForegroundColor $color
}

# Build PC list
if ($PCList) {
    $pcs = $PCList -split "," | ForEach-Object { $_.Trim() }
} else {
    $pcs = 1..$TotalPCs | ForEach-Object { "PC-{0:D2}" -f $_ }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Deployment Orchestrator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase:      $Phase" -ForegroundColor White
Write-Host "Targets:    $($pcs -join ', ')" -ForegroundColor White
Write-Host "Batch size: $BatchSize" -ForegroundColor White
Write-Host "Log file:   $logFile" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Log "Deployment started - Phase: $Phase, Targets: $($pcs -join ', ')"

# ---- Configure TrustedHosts ----

$currentTrusted = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
if ($currentTrusted -ne "*") {
    Write-Log "Setting TrustedHosts to * for WinRM"
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
}

# ---- Phase Definitions ----

$phaseMap = @{
    "Install"     = @{ Script = "1-Install-All.ps1";         Desc = "Software Installation" }
    "Verify"      = @{ Script = "2-Verify-Installation.ps1"; Desc = "Installation Verification" }
    "Configure"   = @{ Script = "3-Configure-NVDA.ps1";      Desc = "NVDA Configuration" }
    "HealthCheck" = @{ Script = "6-Health-Check.ps1";         Desc = "Health Check" }
}

# ---- Discovery ----

function Invoke-Discovery {
    param([string[]]$PCNames)

    Write-Log "--- Discovery Phase ---"
    $results = @()

    foreach ($pc in $PCNames) {
        $ping = Test-Connection -ComputerName $pc -Count 1 -Quiet -ErrorAction SilentlyContinue
        $winrm = $false
        $ip = "-"

        if ($ping) {
            try {
                $dns = [System.Net.Dns]::GetHostAddresses($pc) | Where-Object { $_.AddressFamily -eq "InterNetwork" }
                $ip = $dns[0].ToString()
            } catch { $ip = "?" }

            try {
                $s = New-PSSession -ComputerName $pc -ErrorAction Stop
                $winrm = $true
                Remove-PSSession $s
            } catch {}
        }

        $status = if ($winrm) { "Ready" } elseif ($ping) { "Online (no WinRM)" } else { "Offline" }
        Write-Log "$pc - $status (IP: $ip)"

        $results += [PSCustomObject]@{
            PC     = $pc
            IP     = $ip
            Status = $status
            Phase  = "Discovery"
            Result = if ($winrm) { "PASS" } else { "FAIL" }
            Duration = "-"
            Error  = ""
        }
    }

    return $results
}

# ---- Remote Execution ----

function Invoke-RemotePhase {
    param(
        [string[]]$PCNames,
        [string]$PhaseName
    )

    $info = $phaseMap[$PhaseName]
    $scriptFullPath = Join-Path $ScriptsPath $info.Script
    Write-Log "--- $($info.Desc) Phase ---"
    Write-Log "Running $($info.Script) on $($PCNames.Count) PCs in batches of $BatchSize"

    $allResults = @()
    $batches = @()
    for ($i = 0; $i -lt $PCNames.Count; $i += $BatchSize) {
        $end = [Math]::Min($i + $BatchSize, $PCNames.Count)
        $batches += ,($PCNames[$i..($end-1)])
    }

    $batchNum = 0
    foreach ($batch in $batches) {
        $batchNum++
        Write-Log "Batch $batchNum/$($batches.Count): $($batch -join ', ')"

        $jobs = @()
        foreach ($pc in $batch) {
            $jobs += Start-Job -Name $pc -ScriptBlock {
                param($ComputerName, $ScriptPath, $ShareRoot)
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $output = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                        param($sp, $sr)
                        Set-Location $sr
                        & $sp
                    } -ArgumentList $ScriptPath, $ShareRoot -ErrorAction Stop
                    $timer.Stop()
                    return @{
                        PC       = $ComputerName
                        Result   = "PASS"
                        Duration = "{0:N1}m" -f $timer.Elapsed.TotalMinutes
                        Error    = ""
                        Output   = ($output | Out-String)
                    }
                } catch {
                    $timer.Stop()
                    return @{
                        PC       = $ComputerName
                        Result   = "FAIL"
                        Duration = "{0:N1}m" -f $timer.Elapsed.TotalMinutes
                        Error    = $_.Exception.Message
                        Output   = ""
                    }
                }
            } -ArgumentList $pc, $scriptFullPath, $ScriptsPath
        }

        # Wait for batch to complete
        $jobs | Wait-Job | Out-Null

        foreach ($job in $jobs) {
            $data = Receive-Job -Job $job
            $level = if ($data.Result -eq "PASS") { "SUCCESS" } else { "ERROR" }
            Write-Log "$($data.PC): $($data.Result) ($($data.Duration)) $($data.Error)" $level

            if ($data.Output) {
                Add-Content -Path $logFile -Value "--- Output from $($data.PC) ---"
                Add-Content -Path $logFile -Value $data.Output
            }

            $allResults += [PSCustomObject]@{
                PC       = $data.PC
                IP       = "-"
                Status   = $data.Result
                Phase    = $PhaseName
                Result   = $data.Result
                Duration = $data.Duration
                Error    = $data.Error
            }
            Remove-Job -Job $job
        }
    }

    return $allResults
}

# ---- Main Execution ----

$allResults = @()

if ($Phase -eq "Discovery") {
    $allResults += Invoke-Discovery -PCNames $pcs
}
elseif ($Phase -eq "All") {
    # Run discovery first to find reachable PCs
    $disco = Invoke-Discovery -PCNames $pcs
    $allResults += $disco
    $reachable = ($disco | Where-Object { $_.Result -eq "PASS" }).PC

    if ($reachable.Count -eq 0) {
        Write-Log "No reachable PCs found. Aborting." "ERROR"
    } else {
        Write-Log "$($reachable.Count) PCs reachable. Proceeding with deployment."
        foreach ($p in @("Install","Verify","Configure","HealthCheck")) {
            $allResults += Invoke-RemotePhase -PCNames $reachable -PhaseName $p
        }
    }
}
else {
    $allResults += Invoke-RemotePhase -PCNames $pcs -PhaseName $Phase
}

# ---- Summary ----

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$allResults | Format-Table PC, Phase, Result, Duration, Error -AutoSize

$passed = ($allResults | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($allResults | Where-Object { $_.Result -eq "FAIL" }).Count
Write-Host "Passed: $passed  Failed: $failed  Total: $($allResults.Count)" -ForegroundColor White

if ($failed -gt 0) {
    Write-Host "`nFailed PCs:" -ForegroundColor Red
    $allResults | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "  $($_.PC) - $($_.Phase): $($_.Error)" -ForegroundColor Red
    }
}

Write-Host "`nFull log: $logFile" -ForegroundColor DarkGray
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Log "Deployment complete. Passed: $passed, Failed: $failed"
