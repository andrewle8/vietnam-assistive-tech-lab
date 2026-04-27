# Apply-Patch.ps1
# Patch ID: stu-resolver
#
# Field entry point for the STU- prefix resolver patch. Run as Administrator.
#
# Apply (default):
#   PS> & "<DEPLOY-drive>:\Scripts\patches\stu-resolver\Apply-Patch.ps1"
#
# Undo:
#   PS> & "<DEPLOY-drive>:\Scripts\patches\stu-resolver\Apply-Patch.ps1" -Undo
#
# Idempotent. Safe to re-run. Logs to C:\LabTools\stu-patch.log.

[CmdletBinding()]
param(
    [switch]$Undo
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$patchVersion   = 'stu-resolver'
$labTools       = 'C:\LabTools'
$mountPoint     = 'C:\StudentUSB'
$resolverDest   = Join-Path $labTools 'Reassign-StudentUSB.ps1'
$resolverBackup = "$resolverDest.pre-patch"
$patchLog       = Join-Path $labTools 'stu-patch.log'
$taskName       = 'LabReassignStudentUSB'
$studentSidQuery = (Get-CimInstance Win32_UserAccount -Filter "Name='Student'" -ErrorAction SilentlyContinue).SID

#---- Admin gate ------------------------------------------------------------

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Apply-Patch.ps1 must run as Administrator. Open an elevated PowerShell and re-run." -ForegroundColor Red
    exit 1
}

#---- Helpers ---------------------------------------------------------------

if (-not (Test-Path $labTools)) { New-Item -Path $labTools -ItemType Directory -Force | Out-Null }

$results = New-Object System.Collections.Generic.List[object]
function Add-Result { param([string]$Step, [string]$Status, [string]$Detail)
    $r = [PSCustomObject]@{ Step=$Step; Status=$Status; Detail=$Detail }
    $results.Add($r)
    $color = switch ($Status) { 'PASS' {'Green'} 'FAIL' {'Red'} default {'Yellow'} }
    $icon  = switch ($Status) { 'PASS' {'OK  '} 'FAIL' {'FAIL'} default {'WARN'} }
    Write-Host "[$icon] " -NoNewline -ForegroundColor $color
    Write-Host "$Step" -NoNewline
    if ($Detail) { Write-Host " - $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
}

function Append-PatchLog {
    param([string]$Header)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $patchLog -Value "" -ErrorAction SilentlyContinue
    Add-Content -Path $patchLog -Value "[$stamp] $Header" -ErrorAction SilentlyContinue
    foreach ($r in $results) {
        Add-Content -Path $patchLog -Value ("  [{0}] {1} {2}" -f $r.Status, $r.Step, $r.Detail) -ErrorAction SilentlyContinue
    }
}

function Set-RegValue { param([string]$Path,[string]$Name,$Value,[string]$Type='String')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

#---- APPLY -----------------------------------------------------------------

if (-not $Undo) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  Applying patch $patchVersion" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""

    # 1. Backup existing resolver if it predates this patch (for clean Undo).
    try {
        if ((Test-Path $resolverDest) -and -not (Test-Path $resolverBackup)) {
            $existing = Get-Content $resolverDest -Raw -ErrorAction Stop
            if ($existing -notmatch [regex]::Escape($patchVersion)) {
                Copy-Item -Path $resolverDest -Destination $resolverBackup -Force
                Add-Result 'Backup pre-patch resolver' 'PASS' "$resolverBackup"
            } else {
                Add-Result 'Backup pre-patch resolver' 'WARN' 'already patched, no backup needed'
            }
        } elseif (Test-Path $resolverBackup) {
            Add-Result 'Backup pre-patch resolver' 'PASS' "already exists at $resolverBackup"
        } else {
            Add-Result 'Backup pre-patch resolver' 'WARN' 'no existing resolver to back up (fresh laptop)'
        }
    } catch {
        Add-Result 'Backup pre-patch resolver' 'FAIL' $_.Exception.Message
    }

    # 2. Invoke the helper.
    try {
        $helper = Join-Path $PSScriptRoot 'Patch-StudentUSBResolver.ps1'
        if (-not (Test-Path $helper)) { throw "Helper not found at $helper" }
        & $helper
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Helper exited with code $LASTEXITCODE" }
        Add-Result 'Run setup helper' 'PASS' 'Patch-StudentUSBResolver.ps1 completed'
    } catch {
        Add-Result 'Run setup helper' 'FAIL' $_.Exception.Message
    }

    # 3. Verify resulting state.
    try {
        $stamp = (Get-ItemProperty 'HKLM:\SOFTWARE\LabConfig' -Name 'PatchVersion' -ErrorAction SilentlyContinue).PatchVersion
        if ($stamp -eq $patchVersion) { Add-Result 'Registry stamp' 'PASS' $stamp } else { Add-Result 'Registry stamp' 'FAIL' "expected $patchVersion, found '$stamp'" }
    } catch { Add-Result 'Registry stamp' 'FAIL' $_.Exception.Message }

    try {
        $t = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $hasEvent = $t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskEventTrigger' -and $_.Subscription -match 'Microsoft-Windows-Ntfs/Operational' }
        if ($hasEvent) { Add-Result 'Scheduled task' 'PASS' "$($t.Triggers.Count) triggers including Ntfs/4 EventTrigger" } else { Add-Result 'Scheduled task' 'FAIL' 'Ntfs/4 EventTrigger missing' }
    } catch { Add-Result 'Scheduled task' 'FAIL' $_.Exception.Message }

    Append-PatchLog -Header "APPLY $patchVersion"
}

#---- UNDO ------------------------------------------------------------------

else {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host "  Reverting patch $patchVersion" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host ""

    # 1. Tear down mount point + folder.
    try {
        if (Test-Path -LiteralPath $mountPoint) {
            & mountvol $mountPoint /D 2>&1 | Out-Null
            & cmd.exe /c "rmdir `"$mountPoint`"" 2>&1 | Out-Null
        }
        if (-not (Test-Path -LiteralPath $mountPoint)) { Add-Result 'Detach mount + remove folder' 'PASS' "$mountPoint gone" } else { Add-Result 'Detach mount + remove folder' 'FAIL' "still present" }
    } catch { Add-Result 'Detach mount + remove folder' 'FAIL' $_.Exception.Message }

    # 2. Revert Office regs to D:\.
    try {
        if ($studentSidQuery -and (Test-Path "Registry::HKEY_USERS\$studentSidQuery")) {
            $hive = "Registry::HKEY_USERS\$studentSidQuery"
            Set-RegValue "$hive\Software\Microsoft\Office\16.0\Word\Options"       'DOC-PATH'     'D:\'
            Set-RegValue "$hive\Software\Microsoft\Office\16.0\Word\Options"       'PICTURE-PATH' 'D:\'
            # DefaultPath was not pre-set on Word in the original deploy; remove it.
            Remove-ItemProperty -Path "$hive\Software\Microsoft\Office\16.0\Word\Options" -Name 'DefaultPath' -Force -ErrorAction SilentlyContinue
            Set-RegValue "$hive\Software\Microsoft\Office\16.0\Excel\Options"      'DefaultPath'  'D:\'
            Set-RegValue "$hive\Software\Microsoft\Office\16.0\PowerPoint\Options" 'DefaultPath'  'D:\'
            # PreferCloudSaveLocations was not pre-set originally; remove it.
            Remove-ItemProperty -Path "$hive\Software\Microsoft\Office\16.0\Common\General" -Name 'PreferCloudSaveLocations' -Force -ErrorAction SilentlyContinue
            Add-Result 'Revert Office regs' 'PASS' 'D:\'
        } else { Add-Result 'Revert Office regs' 'WARN' 'Student SID hive not loaded; skipped' }
    } catch { Add-Result 'Revert Office regs' 'FAIL' $_.Exception.Message }

    # 3. Revert Firefox policies.json browser.download.dir.
    try {
        $ff = 'C:\Program Files\Mozilla Firefox\distribution\policies.json'
        if (Test-Path -LiteralPath $ff) {
            $raw = [System.IO.File]::ReadAllText($ff, [System.Text.Encoding]::UTF8)
            $json = $raw | ConvertFrom-Json
            if ($json.policies.Preferences.'browser.download.dir') {
                $json.policies.Preferences.'browser.download.dir'.Value = 'D:\'
                [System.IO.File]::WriteAllText($ff, ($json | ConvertTo-Json -Depth 20), [System.Text.Encoding]::UTF8)
            }
            Add-Result 'Revert Firefox policies.json' 'PASS' 'browser.download.dir = D:\'
        } else { Add-Result 'Revert Firefox policies.json' 'WARN' 'file not present' }
    } catch { Add-Result 'Revert Firefox policies.json' 'FAIL' $_.Exception.Message }

    # 4. Revert Audacity audacity.cfg [Directories/*] Default entries.
    try {
        $ac = 'C:\Users\Student\AppData\Roaming\audacity\audacity.cfg'
        if (Test-Path -LiteralPath $ac) {
            $lines = [System.IO.File]::ReadAllLines($ac, [System.Text.Encoding]::UTF8)
            $inDirSection = $false
            $newLines = New-Object System.Collections.Generic.List[string]
            foreach ($line in $lines) {
                if ($line -match '^\[Directories(/.*)?\]\s*$') { $inDirSection = ($line -match '^\[Directories/'); $newLines.Add($line); continue }
                if ($line -match '^\[') { $inDirSection = $false; $newLines.Add($line); continue }
                if ($inDirSection -and $line -match '^Default\s*=') { $newLines.Add('Default=D:\\'); continue }
                $newLines.Add($line)
            }
            [System.IO.File]::WriteAllLines($ac, $newLines, [System.Text.Encoding]::UTF8)
            Add-Result 'Revert Audacity audacity.cfg' 'PASS' '[Directories/*] Default = D:\\'
        } else { Add-Result 'Revert Audacity audacity.cfg' 'WARN' 'file not present' }
    } catch { Add-Result 'Revert Audacity audacity.cfg' 'FAIL' $_.Exception.Message }

    # 5. Restore "USB" desktop shortcut to pre-patch target (explorer.exe shell:MyComputerFolder).
    try {
        $lnkPath = 'C:\Users\Public\Desktop\USB.lnk'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnkPath)
        $sc.TargetPath       = 'C:\WINDOWS\explorer.exe'
        $sc.Arguments        = 'shell:MyComputerFolder'
        $sc.WorkingDirectory = ''
        $sc.IconLocation     = '%SystemRoot%\System32\imageres.dll,109'
        $sc.Description      = 'Open This PC to access your USB drive'
        $sc.Save()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($sc) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
        Add-Result 'Restore USB.lnk' 'PASS' 'shell:MyComputerFolder'
    } catch { Add-Result 'Restore USB.lnk' 'FAIL' $_.Exception.Message }

    # 6. Re-register scheduled task with original 3 triggers (no Ntfs event).
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                        -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $resolverDest)
        $trigBoot  = New-ScheduledTaskTrigger -AtStartup
        $trigLogon = New-ScheduledTaskTrigger -AtLogOn
        $trigPoll  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                        -RepetitionInterval (New-TimeSpan -Minutes 1) `
                        -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action `
            -Trigger @($trigBoot, $trigLogon, $trigPoll) -Settings $settings -Principal $principal `
            -Description 'Pins any STU-### labeled USB to drive letter D: (boot/logon/1min)' | Out-Null
        Add-Result 'Re-register task (3 triggers)' 'PASS' 'boot/logon/1-min poll'
    } catch { Add-Result 'Re-register task (3 triggers)' 'FAIL' $_.Exception.Message }

    # 7. Restore pre-patch resolver if backup exists.
    try {
        if (Test-Path $resolverBackup) {
            Copy-Item -Path $resolverBackup -Destination $resolverDest -Force
            Remove-Item $resolverBackup -Force -ErrorAction SilentlyContinue
            Add-Result 'Restore pre-patch resolver' 'PASS' 'from .pre-patch'
        } else {
            Add-Result 'Restore pre-patch resolver' 'WARN' 'no backup found; current resolver retained'
        }
    } catch { Add-Result 'Restore pre-patch resolver' 'FAIL' $_.Exception.Message }

    # 8. Remove patch version stamp.
    try {
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\LabConfig' -Name 'PatchVersion' -Force -ErrorAction SilentlyContinue
        Add-Result 'Remove registry stamp' 'PASS' ''
    } catch { Add-Result 'Remove registry stamp' 'FAIL' $_.Exception.Message }

    Append-PatchLog -Header "UNDO $patchVersion"
}

#---- Summary ---------------------------------------------------------------

$pass = @($results | Where-Object Status -eq 'PASS').Count
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$warn = @($results | Where-Object Status -eq 'WARN').Count

Write-Host ""
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("  Result: {0} pass / {1} fail / {2} warn" -f $pass, $fail, $warn)
Write-Host ("  Log:    {0}" -f $patchLog) -ForegroundColor DarkGray
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if ($fail -gt 0) { exit 1 } else { exit 0 }
