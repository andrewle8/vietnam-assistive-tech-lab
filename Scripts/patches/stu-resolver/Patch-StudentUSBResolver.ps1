# Patch-StudentUSBResolver.ps1
# Patch ID: stu-resolver
#
# Idempotent setup helper for the STU- prefix resolver patch. Called by:
#   - Scripts\patches\stu-resolver\Apply-Patch.ps1  (in-field, already-shipped fleet)
#   - Scripts\Configure-Laptop.ps1                  (fresh-image deploys)
#
# Steps:
#   1. Resolve resolver source from $PSScriptRoot\..\..\Reassign-StudentUSB.ps1
#   2. Create C:\LabTools (do NOT pre-create C:\StudentUSB -- resolver owns its lifecycle)
#   3. Copy resolver to C:\LabTools\Reassign-StudentUSB.ps1
#   4. Re-register LabReassignStudentUSB scheduled task with 4 triggers:
#        boot, logon (any user), 1-min repeat, Ntfs/Operational EventID 4
#   5. Write registry stamp HKLM:\SOFTWARE\LabConfig\PatchVersion
#   6. Run resolver once synchronously to apply current state
#
# Idempotent. Safe to re-run; behavior on second run is no-op for already-correct state.
# Requires Administrator (caller must enforce).

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$patchVersion  = 'stu-resolver'
$labTools      = 'C:\LabTools'
$resolverDest  = Join-Path $labTools 'Reassign-StudentUSB.ps1'
$taskName      = 'LabReassignStudentUSB'

function Write-Step { param([string]$M) Write-Host "  [helper] $M" }

#---- 1. Resolve source -----------------------------------------------------

$repoRoot       = (Resolve-Path "$PSScriptRoot\..\..").Path
$resolverSource = Join-Path $repoRoot 'Reassign-StudentUSB.ps1'
if (-not (Test-Path -LiteralPath $resolverSource)) {
    throw "Resolver source not found at $resolverSource"
}
Write-Step "resolver source: $resolverSource"

#---- 2. Create C:\LabTools -------------------------------------------------

if (-not (Test-Path $labTools)) {
    New-Item -Path $labTools -ItemType Directory -Force | Out-Null
}
Write-Step "C:\LabTools ready"

#---- 3. Copy resolver ------------------------------------------------------

Copy-Item -Path $resolverSource -Destination $resolverDest -Force
Write-Step "copied resolver -> $resolverDest"

#---- 4. Re-register scheduled task -----------------------------------------

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Step "removed existing $taskName"
}

# StartBoundary 1 min in the future matches Configure-Laptop's pre-patch pattern.
# Subsequent repetitions fire every 1 min. The Ntfs/4 event trigger is the primary
# fast-response path; the 1-min poll is the safety net.
$startBoundary = (Get-Date).AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Resolves any STU- prefixed USB to a stable mount point at C:\StudentUSB and propagates that path to Office/Firefox/Audacity defaults. Patch $patchVersion. See C:\LabTools\Reassign-StudentUSB.ps1.</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <Duration>P3650D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-Ntfs/Operational"&gt;&lt;Select Path="Microsoft-Windows-Ntfs/Operational"&gt;*[System[Provider[@Name='Microsoft-Windows-Ntfs'] and (EventID=4)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "$resolverDest"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName $taskName -Xml $xml -Force | Out-Null
Write-Step "registered $taskName (4 triggers: boot, logon, 1-min poll, Ntfs/4 event)"

#---- 5. Patch version stamp ------------------------------------------------

$lcKey = 'HKLM:\SOFTWARE\LabConfig'
if (-not (Test-Path $lcKey)) { New-Item -Path $lcKey -Force | Out-Null }
Set-ItemProperty -Path $lcKey -Name 'PatchVersion' -Value $patchVersion -Force
Write-Step "registry stamp: HKLM\SOFTWARE\LabConfig\PatchVersion = $patchVersion"

#---- 6. Run resolver once --------------------------------------------------

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $resolverDest | Out-Null
Write-Step "resolver invoked once synchronously"
