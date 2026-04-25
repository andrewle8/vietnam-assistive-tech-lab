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

# All removable (USB) drives, regardless of label.
function Get-RemovableDrives {
    Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
}

# Removable drives that are candidates for STU- preparation: skip anything labeled
# DEPLOY_* (deploy media — formatting one would destroy 60 GB of installers and
# would have to be rebuilt from scratch) and skip already-prepared STU-### drives
# (re-running the script on a labeled drive shouldn't blow it away).
function Get-CandidateDrives {
    Get-RemovableDrives | Where-Object {
        $label = "$($_.VolumeName)"
        ($label -notmatch '^DEPLOY_') -and ($label -notmatch '^STU-\d{3}$')
    }
}

# Find the portable-golden NVDA source from a connected DEPLOY_ USB. We need
# this because the 285 MB portable can't live in git -- it only exists on the
# DEPLOY USBs. Returns the path to the NVDA folder (containing nvda.exe), or
# $null if no DEPLOY USB has it.
function Find-PortableGoldenSource {
    $deployDrives = Get-RemovableDrives | Where-Object { "$($_.VolumeName)" -match '^DEPLOY_' }
    foreach ($d in $deployDrives) {
        $candidate = Join-Path $d.DeviceID "Installers\NVDA\portable-golden\NVDA"
        if (Test-Path (Join-Path $candidate "nvda.exe")) {
            return $candidate
        }
    }
    return $null
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Batch USB Preparation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($StartStudent -lt 1 -or $StartStudent -gt 999) {
    Write-Log "Invalid -StartStudent value: $StartStudent. Must be 1-999." "ERROR"
    exit 1
}

# Source for NVDA portable. Resolved from a connected DEPLOY_ USB.
$portableSource = Find-PortableGoldenSource
if (-not $portableSource) {
    Write-Log "No DEPLOY_ USB with Installers\NVDA\portable-golden\NVDA\nvda.exe found." "ERROR"
    Write-Host "Plug in at least one DEPLOY_ USB (it is the source for the NVDA portable copy)." -ForegroundColor Yellow
    Write-Host "Detected removable drives:" -ForegroundColor Yellow
    Get-RemovableDrives | ForEach-Object {
        $lbl = if ($_.VolumeName) { $_.VolumeName } else { "(no label)" }
        Write-Host ("  {0}  {1}" -f $_.DeviceID, $lbl) -ForegroundColor Yellow
    }
    pause
    exit 1
}
Write-Log "NVDA portable source: $portableSource" "INFO"

$drives = @(Get-CandidateDrives)
if ($drives.Count -eq 0) {
    Write-Log "No candidate drives found (all DEPLOY_ or already STU- labeled)." "ERROR"
    Write-Host "Plug in blank USBs (or USBs you want re-prepped without STU label)." -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "Removable drives detected ($($drives.Count) candidates):" -ForegroundColor Yellow
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

$skippedDeploy = @(Get-RemovableDrives | Where-Object { "$($_.VolumeName)" -match '^DEPLOY_' })
if ($skippedDeploy.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped (DEPLOY_ — never touched):" -ForegroundColor DarkGray
    foreach ($d in $skippedDeploy) {
        Write-Host ("  {0}\  {1}" -f $d.DeviceID, $d.VolumeName) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "ALL DATA on the candidate drives will be erased if not already NTFS." -ForegroundColor Red
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
    Write-Log "No drives were prepared successfully. Aborting." "ERROR"
    pause
    exit 1
}

# ----------------------------------------------------------------------------
# NVDA portable copy. Each STU- USB gets a self-contained portable NVDA so the
# student can run their screen reader on any Windows machine without admin
# rights or installation. Layout per USB:
#   <STU>:\NVDA\nvda.exe            <- the portable executable
#   <STU>:\NVDA\userConfig\         <- baked Vi-Vu + 11 addons + lab settings
#   <STU>:\Khởi động NVDA.lnk       <- one-click launcher at USB root
#   <STU>:\Tài liệu\, Âm thanh\, Bài tập\
#   <STU>:\.student-id (hidden)
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "NVDA PORTABLE COPY PHASE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Source: $portableSource" -ForegroundColor Cyan
Write-Host "Copying ~285 MB to each STU drive (sequential, robocopy /MT:8)..." -ForegroundColor Cyan
Write-Host ""

$copyResults = @()
foreach ($r in $succeeded) {
    $stuRoot = "$($r.Letter):\"
    $stuNvda = Join-Path $stuRoot "NVDA"
    Write-Host "  -> $($r.StudentId) ($stuNvda) ..." -ForegroundColor White -NoNewline

    # robocopy: /E recurse incl. empty, /MT:8 multithread, /R:1 retry, /W:1 wait,
    # /NFL/NDL/NJH/NJS/NP keep output quiet (we only care about exit code).
    $rcArgs = @($portableSource, $stuNvda, "/E", "/MT:8", "/R:1", "/W:1",
                "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
    & robocopy @rcArgs | Out-Null
    $rcExit = $LASTEXITCODE

    # robocopy exit codes: 0=no change, 1=copied OK, 2=extras, 3=copied+extras.
    # 0-7 = success; 8+ = failure.
    if ($rcExit -lt 8 -and (Test-Path (Join-Path $stuNvda "nvda.exe"))) {
        # Create launcher .lnk at USB root pointing to NVDA\nvda.exe.
        try {
            $lnkPath = Join-Path $stuRoot "Khởi động NVDA.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($lnkPath)
            $sc.TargetPath       = (Join-Path $stuNvda "nvda.exe")
            $sc.WorkingDirectory = $stuNvda
            $sc.IconLocation     = (Join-Path $stuNvda "nvda.exe") + ",0"
            $sc.Description      = "Khởi động NVDA từ USB"
            $sc.Save()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
        } catch {
            Write-Host " (lnk failed: $($_.Exception.Message))" -ForegroundColor Yellow
        }

        Write-Host " OK (robocopy exit $rcExit)" -ForegroundColor Green
        Write-Log "$($r.Letter): NVDA portable + launcher deployed (rc=$rcExit)" "SUCCESS"
        $copyResults += [PSCustomObject]@{ Letter = $r.Letter; StudentId = $r.StudentId; Success = $true }
    } else {
        Write-Host " FAILED (robocopy exit $rcExit)" -ForegroundColor Red
        Write-Log "$($r.Letter): NVDA portable copy FAILED (rc=$rcExit)" "ERROR"
        $copyResults += [PSCustomObject]@{ Letter = $r.Letter; StudentId = $r.StudentId; Success = $false }
    }
}

$copyFailed = @($copyResults | Where-Object { -not $_.Success })
if ($copyFailed.Count -gt 0) {
    Write-Host ""
    Write-Host "$($copyFailed.Count) drive(s) failed NVDA copy. They are formatted/labeled but missing NVDA — re-run script to retry." -ForegroundColor Red
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
