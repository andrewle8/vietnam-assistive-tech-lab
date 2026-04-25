# Apply-BIOS-Settings.ps1 - Apply Dell BIOS settings via Dell Command | Configure (cctk.exe)
# Called by Configure-Laptop.ps1 (USB primary path) and Update-Agent.ps1 (remote safety net).
# Idempotent: dumps current BIOS state once, only writes settings whose values differ.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Settings,

    [string]$LogFile
)

$cctkCandidates = @(
    "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files\Dell\Command Configure\X86_64\cctk.exe",
    "C:\Program Files (x86)\Dell\Command Configure\X86\cctk.exe"
)

function Write-BiosLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] [BIOS] $Message"
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default   { "Cyan" }
    }
    Write-Host $line -ForegroundColor $color
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
    }
}

$cctk = $cctkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $cctk) {
    Write-BiosLog "cctk.exe not found. Dell Command | Configure must be installed before BIOS settings can be applied." "ERROR"
    Write-BiosLog "Searched: $($cctkCandidates -join '; ')" "ERROR"
    return [PSCustomObject]@{
        Status   = "MISSING_CCTK"
        Applied  = 0
        Skipped  = 0
        Failed   = 0
        Total    = $Settings.Count
        Settings = @{}
    }
}

# Dump current BIOS state in one call. cctk-per-setting queries are ~10s each;
# a single -o dump is ~10s for ALL settings, so we read once and compare in memory.
$dumpFile = Join-Path $env:TEMP ("apply-bios-dump-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
try {
    $dumpOut = & $cctk -o $dumpFile 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dumpFile)) {
        Write-BiosLog "Failed to dump current BIOS state (cctk exit $LASTEXITCODE): $dumpOut" "ERROR"
        return [PSCustomObject]@{
            Status   = "DUMP_FAILED"
            Applied  = 0
            Skipped  = 0
            Failed   = 0
            Total    = $Settings.Count
            Settings = @{}
        }
    }
} catch {
    Write-BiosLog "Exception dumping BIOS state: $($_.Exception.Message)" "ERROR"
    return [PSCustomObject]@{
        Status   = "DUMP_FAILED"
        Applied  = 0
        Skipped  = 0
        Failed   = 0
        Total    = $Settings.Count
        Settings = @{}
    }
}

# Parse dump (format is "Key=Value", one per line, with comment/header lines starting with [ or ;)
$current = @{}
foreach ($line in (Get-Content $dumpFile)) {
    if ($line -match "^([A-Za-z][A-Za-z0-9]*)=(.*)$") {
        # Some keys (e.g. BootOrder, Advsm) appear multiple times; keep the first as the
        # representative value. Multi-line settings should not be managed via this script anyway.
        if (-not $current.ContainsKey($Matches[1])) {
            $current[$Matches[1]] = $Matches[2].Trim()
        }
    }
}
Remove-Item $dumpFile -ErrorAction SilentlyContinue

Write-BiosLog "Using cctk: $cctk (parsed $($current.Count) current settings, applying $($Settings.Count) desired)" "INFO"

$results = @{}
$applied = 0
$skipped = 0
$failed  = 0

foreach ($key in $Settings.Keys) {
    if ($key.StartsWith("_")) { continue }
    $desired = "$($Settings[$key])"
    $cur = $current[$key]

    if ($null -ne $cur -and $cur -eq $desired) {
        Write-BiosLog "$key already '$desired' - skipped" "INFO"
        $results[$key] = @{ Status = "Skipped"; Current = $cur; Desired = $desired }
        $skipped++
        continue
    }

    $applyOut = & $cctk "--$key=$desired" 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Write-BiosLog "$key='$desired' applied (was '$cur')" "SUCCESS"
        $results[$key] = @{ Status = "Applied"; Previous = $cur; Desired = $desired }
        $applied++
    } else {
        $errMsg = ($applyOut | Out-String).Trim()
        Write-BiosLog "$key='$desired' FAILED (exit $exitCode): $errMsg" "ERROR"
        $results[$key] = @{
            Status   = "Failed"
            Previous = $cur
            Desired  = $desired
            Error    = $errMsg
            ExitCode = $exitCode
        }
        $failed++
    }
}

$status = if ($failed -eq 0) { "SUCCESS" }
          elseif ($applied -gt 0 -or $skipped -gt 0) { "PARTIAL" }
          else { "FAILED" }

$summaryLevel = if ($failed -gt 0) { "WARNING" } else { "SUCCESS" }
Write-BiosLog "BIOS apply complete: $applied applied, $skipped already correct, $failed failed" $summaryLevel

return [PSCustomObject]@{
    Status   = $status
    Applied  = $applied
    Skipped  = $skipped
    Failed   = $failed
    Total    = ($Settings.Keys | Where-Object { -not $_.StartsWith("_") }).Count
    Settings = $results
}
