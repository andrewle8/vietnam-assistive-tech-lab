# Reassign-StudentUSB.ps1
# Pins any volume labeled STU-### to drive letter D:.
#
# Rationale: Word, Excel, PowerPoint, Firefox, and Audacity all have their default
# save/download locations pinned to D:\ for blind students. If a non-student USB
# ever claims D: first (friend's stick, tech's DEPLOY drive during maintenance),
# the Mount Manager permanently binds that volume's GUID to D:, and the student's
# save USB gets pushed to E:. Every subsequent app save would silently land on the
# wrong drive, which a blind student cannot visually detect.
#
# Behavior:
#   1. Find any volume whose label matches ^STU-\d{3}$
#   2. If that volume is already on D:, exit (no-op)
#   3. If D: is vacant, assign the STU volume to D:
#   4. If D: is held by any other drive, do nothing (never touch another drive's letter)
#
# Registered as a scheduled task running as SYSTEM with three triggers:
#   - AtStartup          (catches USBs plugged in before boot)
#   - AtLogOn            (catches USBs plugged in before login screen)
#   - Every 1 min repeat (catches mid-session plug-in; Task Scheduler API enforces
#                         a 1-min minimum repetition interval)

try {
    # Retry: on volume-arrival events, the volume may not be visible to Get-Volume
    # for up to ~2s after the event fires.
    $stuVol = $null
    for ($i = 1; $i -le 3; $i++) {
        $stuVol = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.FileSystemLabel -match '^STU-\d{3}$' -and $_.DriveType -eq 'Removable' } |
            Select-Object -First 1
        if ($stuVol) { break }
        Start-Sleep -Seconds 1
    }

    if (-not $stuVol) { exit 0 }
    if ($stuVol.DriveLetter -eq 'D') { exit 0 }

    # D: must be vacant. If anything else holds D:, leave it alone.
    if (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue) { exit 0 }

    # Reassign via Win32_Volume CIM (works on both partitioned and superfloppy USBs).
    $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$($stuVol.DriveLetter):'" -ErrorAction Stop
    Set-CimInstance -InputObject $vol -Property @{ DriveLetter = 'D:' } -ErrorAction Stop
    exit 0
} catch {
    exit 1
}
