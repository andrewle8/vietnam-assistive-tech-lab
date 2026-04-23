param(
    [Parameter(Mandatory=$true)]
    [int]$StartStudent,
    [string]$LogPath = "$PSScriptRoot\usb-batch-preparation.log"
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
        default   { "Cyan" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Get-RemovableDrives {
    Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Batch USB Preparation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($StartStudent -lt 1 -or $StartStudent -gt 999) {
    Write-Log "Invalid -StartStudent value: $StartStudent. Must be 1-999." "ERROR"
    exit 1
}

$drives = @(Get-RemovableDrives)
if ($drives.Count -eq 0) {
    Write-Log "No removable drives found. Plug in USB drives and try again." "ERROR"
    pause
    exit 1
}

Write-Host "Removable drives detected ($($drives.Count)):" -ForegroundColor Yellow
$assignments = @()
for ($i = 0; $i -lt $drives.Count; $i++) {
    $drive = $drives[$i]
    $studentId = "STU-{0:D3}" -f ($StartStudent + $i)
    $label = if ($drive.VolumeName) { $drive.VolumeName } else { "(no label)" }
    $sizeGB = [math]::Round($drive.Size / 1GB, 1)
    $fs = $drive.FileSystem
    Write-Host ("  {0}\  {1,-16}  {2,6:N1} GB  {3,-6}  -> {4}" -f $drive.DeviceID, $label, $sizeGB, $fs, $studentId) -ForegroundColor White
    $assignments += [PSCustomObject]@{
        DriveLetter = $drive.DeviceID.TrimEnd(':')
        DriveRoot   = $drive.DeviceID
        StudentId   = $studentId
        NeedsFormat = ($drive.FileSystem -ne "NTFS")
        SizeGB      = $sizeGB
    }
}

Write-Host ""
Write-Host "ALL DATA on these drives will be erased if not already NTFS." -ForegroundColor Red
Write-Host "Confirm: start student IDs at $($assignments[0].StudentId), end at $($assignments[-1].StudentId)" -ForegroundColor Yellow
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Log "Cancelled by user." "INFO"
    exit 0
}

Write-Log "Starting parallel format/label for $($assignments.Count) drives..." "INFO"
$jobs = @()
foreach ($a in $assignments) {
    $jobs += Start-Job -ArgumentList $a.DriveLetter, $a.StudentId, $a.NeedsFormat -ScriptBlock {
        param($letter, $studentId, $needsFormat)
        try {
            if ($needsFormat) {
                Format-Volume -DriveLetter $letter -FileSystem NTFS -NewFileSystemLabel $studentId -Confirm:$false -Force -ErrorAction Stop | Out-Null
            } else {
                Get-Volume -DriveLetter $letter | Set-Volume -NewFileSystemLabel $studentId -ErrorAction Stop
            }
            $root = "${letter}:\"
            $folders = @("Tài liệu", "Âm thanh", "Bài tập")
            foreach ($f in $folders) {
                $p = Join-Path $root $f
                if (-not (Test-Path -LiteralPath $p)) {
                    New-Item -Path $p -ItemType Directory -Force | Out-Null
                }
            }
            $idFile = Join-Path $root ".student-id"
            Set-Content -LiteralPath $idFile -Value $studentId -Force -Encoding UTF8
            (Get-Item -LiteralPath $idFile -Force).Attributes = 'Hidden'
            return @{ Success = $true; Letter = $letter; StudentId = $studentId }
        } catch {
            return @{ Success = $false; Letter = $letter; StudentId = $studentId; Error = $_.Exception.Message }
        }
    }
}

Write-Host ""
Write-Host "Formatting in parallel. This usually takes 15-45 seconds..." -ForegroundColor Cyan
$null = $jobs | Wait-Job
$results = $jobs | Receive-Job
$jobs | Remove-Job

$succeeded = @($results | Where-Object { $_.Success })
$failed    = @($results | Where-Object { -not $_.Success })

foreach ($r in $succeeded) { Write-Log "$($r.Letter): prepared as $($r.StudentId)" "SUCCESS" }
foreach ($r in $failed)    { Write-Log "$($r.Letter): FAILED ($($r.StudentId)) - $($r.Error)" "ERROR" }

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failed.Count) drive(s) failed. Review the log and re-run this script with -StartStudent $($failed[0].StudentId.Substring(4))" -ForegroundColor Red
}

if ($succeeded.Count -eq 0) {
    Write-Log "No drives were prepared successfully. Aborting labeling phase." "ERROR"
    pause
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "LABELING PHASE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Unplug ONE drive at a time. I will tell you its STU-### number." -ForegroundColor Yellow
Write-Host "Write the number on the physical drive with a Sharpie, then unplug the next." -ForegroundColor Yellow
Write-Host ""

$pendingLabels = @{}
foreach ($r in $succeeded) {
    $letter = $r.Letter
    $pendingLabels[$letter] = $r.StudentId
}

$lastSnapshot = (Get-RemovableDrives | ForEach-Object { $_.DeviceID.TrimEnd(':') })
$labeled = @()

while ($pendingLabels.Count -gt 0) {
    Write-Host "Waiting for you to unplug a drive... ($($pendingLabels.Count) remaining)" -ForegroundColor Cyan
    while ($true) {
        Start-Sleep -Milliseconds 500
        $currentSnapshot = @(Get-RemovableDrives | ForEach-Object { $_.DeviceID.TrimEnd(':') })
        $removed = @($lastSnapshot | Where-Object { $currentSnapshot -notcontains $_ })
        if ($removed.Count -gt 0) {
            $lastSnapshot = $currentSnapshot
            break
        }
    }
    foreach ($letter in $removed) {
        if ($pendingLabels.ContainsKey($letter)) {
            $id = $pendingLabels[$letter]
            Write-Host ""
            Write-Host "  >>> WRITE '$id' ON THE DRIVE YOU JUST REMOVED <<<" -ForegroundColor Green -BackgroundColor Black
            Write-Host ""
            Write-Log "User unplugged ${letter}: -> labeled $id" "SUCCESS"
            $labeled += [PSCustomObject]@{ Letter = $letter; StudentId = $id }
            $pendingLabels.Remove($letter)
        } else {
            Write-Host "  Drive ${letter}: removed but was not in this batch (ignored)." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "BATCH COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Labeled in this batch:" -ForegroundColor White
foreach ($l in $labeled) {
    Write-Host "  $($l.StudentId)" -ForegroundColor White
}
$nextStart = $StartStudent + $assignments.Count
Write-Host ""
Write-Host "Next batch: run with -StartStudent $nextStart" -ForegroundColor Cyan
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
Write-Host ""
