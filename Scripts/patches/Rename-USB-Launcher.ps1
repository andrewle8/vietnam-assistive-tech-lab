#requires -Version 5.1
<#
Rename-USB-Launcher.ps1

Renames the USB-root NVDA launcher from `NVDA.lnk` to `Start-NVDA.lnk` on
already-deployed STU- student USB drives.

Why: Both `NVDA` (folder) and `NVDA.lnk` (shortcut) start with the letter N,
so a blind student pressing "N" in File Explorer at the USB root lands on the
folder first (folders sort before files in default view) and pressing Enter
opens the folder rather than launching NVDA. Renaming the launcher to
`Start-NVDA.lnk` lets the student press "S" — no other root item starts with
S — and reach the launcher unambiguously.

Self-healing contract: ensure `<root>\Start-NVDA.lnk` exists with the correct
target, and remove any leftover `<root>\NVDA.lnk`. Safe to re-run on any
mix of old-state, new-state, partial-state, and missing-state drives.

Targets connected removable drives whose volume label matches `^STU-\d{3}$`.
Skips DEPLOY_ media. Runs in parallel with throttling (default 5 concurrent)
to match the prep script's hub-friendly behaviour.

Usage (on a Windows lab laptop with STU- USBs plugged in via powered hub):
    # Preview which drives would be touched, no changes:
    .\Rename-USB-Launcher.ps1 -WhatIf

    # Apply:
    .\Rename-USB-Launcher.ps1

    # Custom concurrency for unpowered hubs:
    .\Rename-USB-Launcher.ps1 -MaxConcurrent 3
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [int]$MaxConcurrent = 5,
    [string]$LogPath = "$PSScriptRoot\rename-launcher.log"
)

chcp 65001 | Out-Null
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "SKIP"    { "DarkGray" }
        default   { "Cyan" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# All removable (USB) drives with media present. Same filter as prep script.
function Get-StuDrives {
    Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object {
        $_.DriveType -eq 2 -and $_.Size -gt 0 -and "$($_.VolumeName)" -match '^STU-\d{3}$'
    }
}

Write-Log "Rename-USB-Launcher starting. MaxConcurrent=$MaxConcurrent" "INFO"

$drives = @(Get-StuDrives)
if ($drives.Count -eq 0) {
    Write-Log "No connected STU-### drives found. Nothing to do." "WARN"
    Write-Host "Plug in one or more STU- USB drives and re-run." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Detected STU- drives ($($drives.Count)):" -ForegroundColor Yellow
foreach ($d in $drives) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Host ("  {0}\  {1,-10}  {2,5:N1} GB" -f $d.DeviceID, $d.VolumeName, $sizeGB) -ForegroundColor White
}
Write-Host ""

if ($PSCmdlet.ShouldProcess("$($drives.Count) STU- drive(s)", "Ensure Start-NVDA.lnk and remove NVDA.lnk")) {
    # Proceed.
} else {
    Write-Log "WhatIf mode: no changes made." "INFO"
    exit 0
}

# Per-drive worker. Runs in a job. Receives the drive letter (no colon) and
# returns a hashtable with the result.
$worker = {
    param($Letter, $StudentId)
    $result = @{
        Letter      = $Letter
        StudentId   = $StudentId
        Action      = $null    # 'renamed' | 'created' | 'noop' | 'cleanup' | 'skip-no-nvda' | 'error'
        OldRemoved  = $false
        NewExists   = $false
        Error       = $null
    }
    try {
        $root      = "$($Letter):\"
        $oldLnk    = Join-Path $root "NVDA.lnk"
        $newLnk    = Join-Path $root "Start-NVDA.lnk"
        $nvdaDir   = Join-Path $root "NVDA"
        $nvdaExe   = Join-Path $nvdaDir "nvda.exe"
        $oldExists = Test-Path -LiteralPath $oldLnk
        $newExists = Test-Path -LiteralPath $newLnk

        # Refuse to create a dead launcher. If nvda.exe is missing, the drive
        # is in an unexpected state — don't touch anything; let the operator
        # investigate.
        if (-not (Test-Path -LiteralPath $nvdaExe)) {
            $result.Action = 'skip-no-nvda'
            $result.Error = "NVDA\nvda.exe not found at $($Letter):\NVDA\nvda.exe"
            return $result
        }

        # Always create/overwrite Start-NVDA.lnk to ensure the target points
        # at the current portable NVDA path. CreateShortcut overwrites
        # silently if a same-named .lnk already exists.
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($newLnk)
        $sc.TargetPath       = $nvdaExe
        $sc.WorkingDirectory = $nvdaDir
        $sc.IconLocation     = "$nvdaExe,0"
        $sc.Description      = "NVDA"
        $sc.Save()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null

        $result.NewExists = Test-Path -LiteralPath $newLnk

        # Remove the legacy NVDA.lnk if present.
        if ($oldExists) {
            Remove-Item -LiteralPath $oldLnk -Force -ErrorAction Stop
            $result.OldRemoved = $true
        }

        # Classify what actually happened for a useful log line.
        if ($oldExists -and $newExists) {
            $result.Action = 'cleanup'   # both existed; kept new, removed old
        } elseif ($oldExists) {
            $result.Action = 'renamed'   # only old existed; created new + removed old
        } elseif ($newExists) {
            $result.Action = 'noop'      # only new existed; refreshed shortcut
        } else {
            $result.Action = 'created'   # neither existed; created new from scratch
        }
        return $result
    } catch {
        $result.Action = 'error'
        $result.Error  = $_.Exception.Message
        return $result
    }
}

# Throttled parallel processing. Reuses the same queue pattern as
# 4-Prepare-Student-USB-Batch.ps1 lines 212-276.
$queue = [System.Collections.Generic.Queue[object]]::new()
foreach ($d in $drives) {
    $queue.Enqueue([PSCustomObject]@{
        Letter    = $d.DeviceID.TrimEnd(':')
        StudentId = $d.VolumeName
    })
}

$running = @{}
$results = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $MaxConcurrent) {
        $item = $queue.Dequeue()
        $job = Start-Job -ScriptBlock $worker -ArgumentList $item.Letter, $item.StudentId
        $running[$job.Id] = @{ Job = $job; Item = $item; StartedAt = Get-Date }
        Write-Host "[$(Get-Date -Format HH:mm:ss)] START $($item.StudentId) ($($item.Letter):)" -ForegroundColor Cyan
    }

    Start-Sleep -Milliseconds 500

    # Only treat truly-finished states as ready to receive. Excluding NotStarted
    # avoids racing on a job that hasn't begun executing yet (PS 5.1 quirk:
    # Start-Job can briefly return a job in NotStarted state before the runspace
    # spins up).
    $finishedIds = @($running.Keys | Where-Object { $running[$_].Job.State -in 'Completed','Failed','Stopped' })
    foreach ($id in $finishedIds) {
        $entry = $running[$id]
        $r     = Receive-Job -Job $entry.Job
        Remove-Job -Job $entry.Job
        $running.Remove($id)
        $results += $r

        $elapsed = [int]((Get-Date) - $entry.StartedAt).TotalSeconds
        $tag = "$($r.StudentId) ($($r.Letter):)"
        switch ($r.Action) {
            'renamed' { Write-Log "$tag renamed NVDA.lnk -> Start-NVDA.lnk (${elapsed}s)" "SUCCESS" }
            'cleanup' { Write-Log "$tag both .lnk present, kept Start-NVDA.lnk and removed NVDA.lnk (${elapsed}s)" "SUCCESS" }
            'noop'    { Write-Log "$tag already migrated; refreshed Start-NVDA.lnk target (${elapsed}s)" "SUCCESS" }
            'created' { Write-Log "$tag no launcher present, created Start-NVDA.lnk (${elapsed}s)" "SUCCESS" }
            'skip-no-nvda' { Write-Log "$tag SKIPPED: $($r.Error)" "WARN" }
            'error'   { Write-Log "$tag FAILED: $($r.Error) (${elapsed}s)" "ERROR" }
            default   { Write-Log "$tag unknown action='$($r.Action)' (${elapsed}s)" "WARN" }
        }
    }
}

Write-Host ""
$ok       = @($results | Where-Object { $_.Action -in 'renamed','cleanup','noop','created' })
$skipped  = @($results | Where-Object { $_.Action -eq 'skip-no-nvda' })
$failed   = @($results | Where-Object { $_.Action -eq 'error' })

Write-Host "----- Summary -----" -ForegroundColor Yellow
Write-Host ("  Succeeded: {0}" -f $ok.Count) -ForegroundColor Green
if ($skipped.Count -gt 0) { Write-Host ("  Skipped:   {0} (no NVDA portable on drive)" -f $skipped.Count) -ForegroundColor DarkGray }
if ($failed.Count -gt 0)  { Write-Host ("  Failed:    {0}" -f $failed.Count) -ForegroundColor Red }
Write-Host ""

if ($failed.Count -gt 0) { exit 1 }
exit 0
