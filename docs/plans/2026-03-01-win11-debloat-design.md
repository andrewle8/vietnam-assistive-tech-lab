# Windows 11 Debloat Design

## Context

19 Dell Latitude 5420 laptops for blind children at a Vietnam orphanage. NVDA screen reader + Firefox + Kiwix + Microsoft Office. Machines are offline (no internet after setup). Every unnecessary app, widget, or notification is a confusing obstacle for NVDA users.

## Approach

Aggressive debloat via pure PowerShell (no third-party tools). All changes added as new steps (23-28) in `Scripts/Configure-Laptop.ps1`.

## Step 23: Remove Bloatware Apps

Remove via `Get-AppxPackage -AllUsers | Remove-AppxPackage` and `Get-AppxProvisionedPackage -Online | Remove-AppxProvisionedPackage`:

| Package | Reason |
|---------|--------|
| Microsoft.BingNews | No internet |
| Microsoft.BingWeather | No internet |
| Microsoft.GamingApp | No gaming |
| Microsoft.Xbox.TCUI | No gaming |
| Microsoft.XboxGameOverlay | No gaming |
| Microsoft.XboxGamingOverlay | No gaming |
| Microsoft.XboxSpeechToTextOverlay | No gaming |
| Microsoft.XboxIdentityProvider | No gaming |
| Microsoft.GetHelp | No internet, confusing |
| Microsoft.Getstarted (Tips) | Confusing popups |
| Microsoft.MicrosoftOfficeHub | Have real Office installed |
| Microsoft.MicrosoftSolitaireCollection | Bloat |
| Microsoft.People | Unused |
| Microsoft.Todos | Unused |
| Microsoft.PowerAutomateDesktop | Unused |
| Microsoft.WindowsFeedbackHub | No internet |
| Microsoft.WindowsMaps | No internet |
| Microsoft.YourPhone / PhoneLink | No phones |
| Microsoft.ZuneMusic | Unused (Groove Music) |
| Microsoft.ZuneVideo | Unused (Movies & TV) |
| Microsoft.549981C3F5F10 (Cortana) | Interferes with NVDA |
| Clipchamp.Clipchamp | Unused video editor |
| MicrosoftTeams | Consumer Teams, unused |

**Keep**: Calculator, Photos, Notepad, Microsoft Store, Snipping Tool.

## Step 24: Remove OneDrive

- Run `$env:SystemRoot\SysWOW64\OneDriveSetup.exe /uninstall` (or 64-bit path)
- Remove leftover folders and scheduled tasks
- Reason: Offline machines, OneDrive nags are confusing for NVDA

## Step 25: Disable Widgets, Cortana, Search Highlights

- Widgets: `HKLM:\SOFTWARE\Policies\Microsoft\Dsh` -> `AllowNewsAndInterests` = 0
- Taskbar widget button: `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` -> `TaskbarDa` = 0
- Cortana: `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` -> `AllowCortana` = 0
- Search highlights: `HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings` -> `IsDynamicSearchBoxEnabled` = 0
- Web search in Start: `HKCU:\Software\Policies\Microsoft\Windows\Explorer` -> `DisableSearchBoxSuggestions` = 1

## Step 26: Disable/Neuter Edge

Full removal of Edge is fragile on Win11 (Microsoft re-installs it). Instead:
- Remove Edge desktop/taskbar shortcuts
- Disable Edge first-run experience via registry
- Disable Edge auto-start/background running
- Set Firefox as default browser handler for http/https/htm/html via registry + `SetUserFTA` if available

## Step 27: Clean Taskbar

- Hide Chat icon: `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` -> `TaskbarMn` = 0
- Hide Task View: `TaskbarDv` = 0
- Hide Search: `SearchboxTaskbarMode` = 0
- Hide Widgets: `TaskbarDa` = 0 (covered in Step 25)
- Unpin all default apps from taskbar
- Pin only: File Explorer

## Step 28: Reduce Telemetry

- Telemetry level to Security (0): `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` -> `AllowTelemetry` = 0
- Disable advertising ID: `HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` -> `Enabled` = 0
- Disable activity history: `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` -> `EnableActivityFeed` = 0, `PublishUserActivities` = 0
- Disable Connected User Experiences service (`DiagTrack`)

## Summary output

Update the summary block at the end of Configure-Laptop.ps1 to include debloat results.
