# Vietnam Lab Deployment - Installation Verification Script
# Version: 1.0
# Run after 1-Install-All.ps1
# Last Updated: February 2026

param(
    [string]$LogPath = "$PSScriptRoot\verification.log"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Vietnam Lab - Installation Verification" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "=== Verification Started on $env:COMPUTERNAME ===" "INFO"

# Define checks with multiple possible paths
$checks = @(
    @{
        Name = "NVDA"
        Paths = @(
            "C:\Program Files\NVDA\nvda.exe",
            "C:\Program Files (x86)\NVDA\nvda.exe"
        )
        Critical = $true
    },
    @{
        Name = "VNVoice (SAPI5)"
        Paths = @(
            "C:\Windows\Speech\Engines\TTS\*vnvoice*",
            "C:\Windows\Speech\Engines\TTS\*VNVoice*",
            "C:\Windows\Speech\Engines\TTS\*SaoMai*",
            "C:\Program Files\SaoMai\VNVoice\*",
            "C:\Program Files (x86)\SaoMai\VNVoice\*",
            "C:\Program Files\SaoMai\*voice*"
        )
        RegCheck = "HKLM:\SOFTWARE\Microsoft\Speech\Voices\Tokens\*VN*"
        Critical = $true
    },
    @{
        Name = "Sao Mai Typing Tutor"
        Paths = @(
            "C:\Program Files\SaoMai\TypingTutor\*",
            "C:\Program Files (x86)\SaoMai\TypingTutor\*",
            "C:\Program Files\SaoMai\SMTTypingTutor\*",
            "C:\Program Files (x86)\SaoMai\SMTTypingTutor\*",
            "C:\Program Files\Sao Mai\*",
            "C:\Program Files (x86)\Sao Mai\*"
        )
        Critical = $false
    },
    @{
        Name = "Microsoft Office"
        Paths = @(
            "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE",
            "C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE"
        )
        Critical = $true
    },
    @{
        Name = "Firefox ESR"
        Paths = @(
            "C:\Program Files\Mozilla Firefox\firefox.exe",
            "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
        )
        Critical = $true
    },
    @{
        Name = "VLC Media Player"
        Paths = @(
            "C:\Program Files\VideoLAN\VLC\vlc.exe",
            "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        )
        Critical = $false
    },
    @{
        Name = "Thorium Reader"
        Paths = @(
            "$env:LOCALAPPDATA\Programs\Thorium\Thorium.exe",
            "C:\Program Files\Thorium\Thorium.exe",
            "C:\Program Files (x86)\Thorium\Thorium.exe"
        )
        Critical = $false
    },
    @{
        Name = "Audacity"
        Paths = @(
            "C:\Program Files\Audacity\Audacity.exe",
            "C:\Program Files (x86)\Audacity\Audacity.exe"
        )
        Critical = $false
    },
    @{
        Name = "Quorum Studio"
        Paths = @(
            "C:\Program Files\QuorumStudio\*"
        )
        Critical = $false
    },
    @{
        Name = "SumatraPDF"
        Paths = @(
            "C:\Program Files\SumatraPDF\SumatraPDF.exe",
            "C:\Program Files (x86)\SumatraPDF\SumatraPDF.exe",
            "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe"
        )
        Critical = $false
    },
    @{
        Name = "GoldenDict"
        Paths = @(
            "C:\Program Files\GoldenDict\GoldenDict.exe",
            "C:\Program Files (x86)\GoldenDict\GoldenDict.exe"
        )
        Critical = $false
    },
    @{
        Name = "Kiwix"
        Paths = @(
            "C:\Program Files\Kiwix\kiwix-desktop.exe"
        )
        Critical = $false
    },
    @{
        Name = "UniKey"
        Paths = @(
            "C:\Program Files\UniKey\UniKeyNT.exe"
        )
        Critical = $true
    },
    @{
        Name = "LEAP Games"
        Paths = @(
            "C:\Games\LEAP\TicTacToe\*.exe",
            "C:\Games\LEAP\Tennis\*.exe",
            "C:\Games\LEAP\Curve\*.exe"
        )
        Critical = $false
    }
)

$results = @{
    Pass = 0
    Fail = 0
    Critical = 0
}

foreach ($check in $checks) {
    $found = $false
    $foundPath = ""

    foreach ($path in $check.Paths) {
        if (Test-Path $path) {
            $found = $true
            $foundPath = $path
            break
        }
    }

    # Also check registry if a RegCheck pattern is defined
    if (-not $found -and $check.RegCheck) {
        if (Test-Path $check.RegCheck) {
            $found = $true
            $foundPath = "Registry: $($check.RegCheck)"
        }
    }

    if ($found) {
        Write-Host "[" -NoNewline
        Write-Host "OK" -ForegroundColor Green -NoNewline
        Write-Host "] $($check.Name)" -NoNewline
        Write-Host " - $foundPath" -ForegroundColor DarkGray
        Write-Log "$($check.Name): FOUND at $foundPath" "SUCCESS"
        $results.Pass++
    } else {
        $severity = if ($check.Critical) { "CRITICAL" } else { "WARNING" }
        Write-Host "[" -NoNewline
        Write-Host "FAIL" -ForegroundColor Red -NoNewline
        Write-Host "] $($check.Name)" -NoNewline
        if ($check.Critical) {
            Write-Host " [CRITICAL]" -ForegroundColor Red
            $results.Critical++
        } else {
            Write-Host " [Optional]" -ForegroundColor Yellow
        }
        Write-Log "$($check.Name): NOT FOUND" $severity
        $results.Fail++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $($results.Pass)" -ForegroundColor Green
Write-Host "Failed: $($results.Fail)" -ForegroundColor $(if($results.Fail -gt 0){"Red"}else{"Green"})
Write-Host "Critical Issues: $($results.Critical)" -ForegroundColor $(if($results.Critical -gt 0){"Red"}else{"Green"})

Write-Log "Verification Summary - Pass: $($results.Pass), Fail: $($results.Fail), Critical: $($results.Critical)" "INFO"

if ($results.Critical -gt 0) {
    Write-Host "`n" -NoNewline
    Write-Host "CRITICAL SOFTWARE MISSING!" -ForegroundColor Red
    Write-Host "The lab cannot function without these components." -ForegroundColor Red
    Write-Host "Please re-run 1-Install-All.ps1 or install manually." -ForegroundColor Yellow
} elseif ($results.Fail -gt 0) {
    Write-Host "`n" -NoNewline
    Write-Host "Some optional software is missing" -ForegroundColor Yellow
    Write-Host "The lab will function, but some features may be unavailable." -ForegroundColor Yellow
} else {
    Write-Host "`n" -NoNewline
    Write-Host "All software verified successfully!" -ForegroundColor Green
    Write-Host "`nNext step: Run .\3-Configure-NVDA.ps1" -ForegroundColor Yellow
}

Write-Host "`nLog file: $LogPath" -ForegroundColor Cyan
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "=== Verification Complete ===" "INFO"

if (-not $env:LAB_BOOTSTRAP) { pause }
