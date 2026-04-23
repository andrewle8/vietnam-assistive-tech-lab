# Uninstall-Legacy.ps1 — one-shot cleanup for laptops that were partially deployed
# under an older stack. Removes: Tailscale, rclone, Quorum Studio, Thorium Reader,
# nvdaRemote addon, Top Speed 3 (LEAP), fleet-report + USB-backup scheduled tasks.
#
# Run only on laptops that may have those artifacts. Fresh laptops don't need this.
# Requires Administrator.

#Requires -RunAsAdministrator

$labToolsDir = "C:\LabTools"

Write-Host "Cleaning legacy deployment artifacts..." -ForegroundColor Cyan

# File artifacts
foreach ($legacy in @(
    "$labToolsDir\rclone",
    "$labToolsDir\fleet-reports",
    "$labToolsDir\start-tailscale.ps1",
    "$labToolsDir\start-tailscale.vbs",
    "$labToolsDir\Report-FleetHealth.ps1",
    "$labToolsDir\backup-usb.ps1",
    "$labToolsDir\start-unikey.vbs",
    "$labToolsDir\welcome-audio.ps1",
    "$labToolsDir\nvdaControllerClient64.dll",
    "$labToolsDir\toggle-language.ps1",
    "C:\Games\LEAP"
)) {
    if (Test-Path $legacy) {
        Remove-Item -Path $legacy -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $legacy"
    }
}

# Scheduled tasks
foreach ($taskName in @("LabUSBBackup", "LabFleetReport")) {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Removed scheduled task: $taskName"
    }
}

# Startup shortcuts
Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\LabWelcome.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -Force -ErrorAction SilentlyContinue

# Tailscale service + app
$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($tsService) {
    Stop-Service -Name "Tailscale" -Force -ErrorAction SilentlyContinue
    Get-Process -Name "tailscale*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $tsUninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq "Tailscale" } | Select-Object -First 1
    if ($tsUninstall -and $tsUninstall.UninstallString -match 'MsiExec') {
        $guid = [regex]::Match($tsUninstall.UninstallString, '\{[0-9A-Fa-f\-]+\}').Value
        if ($guid) {
            Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
    }
    Remove-Item "C:\Program Files\Tailscale" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Uninstalled Tailscale"
}

# Quorum Studio
$quorumPath = "C:\Program Files\QuorumStudio"
if (Test-Path $quorumPath) {
    $quorumUninstall = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                          "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "Quorum" } | Select-Object -First 1
    if ($quorumUninstall -and $quorumUninstall.UninstallString) {
        Start-Process cmd.exe -ArgumentList "/c", "`"$($quorumUninstall.UninstallString)`" /S" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    Remove-Item $quorumPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Public\Desktop\Quorum Studio.lnk" -Force -ErrorAction SilentlyContinue
    Write-Host "  Uninstalled Quorum Studio"
}

# Thorium Reader (per-user)
foreach ($userName in @("Admin", "Student")) {
    $thPath = "C:\Users\$userName\AppData\Local\Programs\Thorium"
    if (Test-Path $thPath) {
        Remove-Item $thPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Thorium from $userName profile"
    }
}
Remove-Item "C:\Users\Public\Desktop\Thorium Reader.lnk" -Force -ErrorAction SilentlyContinue

# nvdaRemote addon (all profiles)
Get-ChildItem "C:\Users\*\AppData\Roaming\nvda\addons\remote*" -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Top Speed 3 (LEAP audio game) — Inno Setup uninstaller
$topSpeedUninstall = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "Top Speed" } | Select-Object -First 1
if ($topSpeedUninstall -and $topSpeedUninstall.UninstallString) {
    $uninstallExe = ($topSpeedUninstall.UninstallString -replace '"', '')
    if (Test-Path $uninstallExe) {
        Start-Process $uninstallExe -ArgumentList "/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    Remove-Item "C:\Program Files (x86)\Playing in the dark" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\*\Desktop\Top Speed*.lnk" -Force -ErrorAction SilentlyContinue
    Write-Host "  Uninstalled Top Speed 3 (LEAP)"
}

Write-Host "Legacy cleanup complete." -ForegroundColor Green
