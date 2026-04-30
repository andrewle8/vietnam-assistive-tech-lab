# Reorganize-UserGuide.ps1
# One-shot tool: reorganize H2 sections in docs/Huong-Dan-Su-Dung-Full.md and
# docs/User-Guide.md per the structural review (2026-05-01).
#
# What this script does (PURELY STRUCTURAL — no content rewrites):
#   1. Splits the source MD into sections at "^## " H2 boundaries.
#   2. Reassembles in a new order designed for a beginner blind student:
#       hardware -> keyboard basics -> SAFETY NETS (NVDA+1, Ctrl+Alt+N)
#       BEFORE shortcut tables -> reference tables -> USB -> typing -> apps.
#   3. Deletes the duplicate "Daily NVDA Shortcuts (Summary)" table that
#      ~70% overlapped the main table; absorbs 2 unique rows into the main
#      table (NVDA+. = phonetic char read; NVDA+C = read clipboard).
#   4. Demotes the "Hearing Tone Marks" 3-line H2 to an H3 subsection of
#      "Typing Vietnamese" (where it conceptually belongs).
#   5. Trims the duplicate "Switch Vietnamese/English: Ctrl+Shift" line that
#      appears twice in the Typing Vietnamese section.
#
# Both VI and EN files get the same structural treatment so they stay mirror.
#
# Backup: writes a .bak.<timestamp> copy of each file before rewriting. The
# Build-Help-HTML.ps1 script must be re-run after this (regenerates HTMLs).
#
# Usage (from repo root):
#     .\Scripts\Reorganize-UserGuide.ps1
#
# Note: this file is saved with a UTF-8 BOM so the Vietnamese H2 titles in
# the order arrays below round-trip correctly under PowerShell 5.1.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

# ----- Section orders (new, by exact H2 title) ---------------------------------
# Sections NOT listed here are dropped. Order = position in the rebuilt file.

$newOrderVi = @(
    'Cổng Kết Nối'
    'Cổng Quan Trọng'
    'Tai Nghe'
    'Tư Thế Đặt Tay Khi Gõ Phím'
    'Bố Cục Bàn Phím'
    'Học Phím'                              # MOVED UP from pos 10 (safety net #1)
    'Khi NVDA Không Đọc Hoặc Đọc Sai:'      # MOVED UP from pos 21 (safety net #2)
    'Điều Hướng Trên Desktop'
    'Các Phím Tắt NVDA Quan Trọng'          # absorbs 2 rows from deleted "Daily Summary"
    'Các Phím Tắt Windows Hữu Ích'
    'USB Của Bạn'                            # MOVED DOWN from pos 4
    'Gõ Tiếng Việt'                          # absorbs "Hearing Tone Marks" as H3
    'Đọc Sách Giáo Khoa'
    'Duyệt Web Với Firefox'
    'Wikipedia Và Wiktionary Offline'
    'Đọc File PDF Với Microsoft Edge'
    'Từ Điển Anh-Việt'
    'Nghe Nhạc Và Sách Nói Với VLC'          # moved past Wikipedia/PDF/Dictionary
    'Máy Tính Bỏ Túi (Calculator)'
    'Bảo Quản Máy'
    'Dùng NVDA Trên Máy Tính Khác'
)

$newOrderEn = @(
    'Ports and Connections'
    'Important Ports'
    'Headphones'
    'Typing Position'
    'Keyboard Layout'
    'Learning Keys'
    'If NVDA stops talking or speaks incorrectly:'
    'Desktop Navigation'
    'Important NVDA Shortcuts'
    'Useful Windows Shortcuts'
    'Your USB Drive'
    'Typing Vietnamese'
    'Reading Textbooks'
    'Browsing the Web with Firefox'
    'Offline Wikipedia and Wiktionary'
    'Reading PDFs with Microsoft Edge'
    'English-Vietnamese Dictionary'
    'Music and Audiobooks with VLC'
    'Calculator'
    'Hardware Care'
    'Using NVDA on Other Computers'
)

# ----- Helpers -----------------------------------------------------------------

function Split-IntoSections {
    param([string]$Content)

    # Returns an OrderedDictionary: '__preamble__' -> text before first H2,
    # then each H2 title -> full section text (including the ## header line
    # and trailing blank line).
    $sections = [ordered]@{}
    $sections['__preamble__'] = ''
    $currentTitle = '__preamble__'
    $buffer = New-Object System.Text.StringBuilder

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^## (.+?)\s*$') {
            # Save the previous section (replace, not append, since titles can
            # repeat in pathological cases — last one wins).
            $sections[$currentTitle] = $buffer.ToString()
            $currentTitle = $matches[1].Trim()
            $buffer = New-Object System.Text.StringBuilder
            [void]$buffer.AppendLine($line)
        } else {
            [void]$buffer.AppendLine($line)
        }
    }
    $sections[$currentTitle] = $buffer.ToString()
    return $sections
}

function Strip-LeadingHorizontalRule {
    # If a section's last lines are "---\n\n" (the visual separator between
    # H2s in the source), strip them so reassembly doesn't accumulate doubles.
    # We add our own "---\n" between sections at write time.
    param([string]$Section)
    return ($Section -replace "(?s)\s*---\s*$", '')
}

function Get-SectionWithoutTrailingHr {
    param([string]$Section)
    # Trim trailing whitespace + remove a trailing "---" + trim again
    $s = $Section.TrimEnd()
    if ($s -match "(?s)^(.*?)\r?\n---\s*$") { $s = $matches[1].TrimEnd() }
    return $s
}

# ----- Per-file reorganization -------------------------------------------------

function Reorganize-File {
    param(
        [string]$Path,
        [string[]]$NewOrder,
        [string]$Lang   # 'vi' or 'en' for the targeted transforms
    )

    if (-not (Test-Path $Path)) { throw "File not found: $Path" }

    $original = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))

    # Backup
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$Path.bak.$stamp"
    [System.IO.File]::WriteAllText($backupPath, $original, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Backup: $backupPath" -ForegroundColor DarkGray

    $sections = Split-IntoSections $original

    # ---- Targeted transforms BEFORE reassembly ----

    if ($Lang -eq 'vi') {
        # 1. Absorb 2 unique rows from the deleted Daily Summary table into
        #    'Các Phím Tắt NVDA Quan Trọng'. Insert before "## Các Phím Tắt Windows".
        $mainTbl = $sections['Các Phím Tắt NVDA Quan Trọng']
        $extraRows = @(
            "| NVDA + dấu chấm (.) hai lần | Đọc ký tự hiện tại theo phát âm (đọc cả tên dấu thanh) |"
            "| NVDA + C                  | Đọc nội dung clipboard (Ctrl + C để sao chép vào clipboard) |"
        ) -join "`n"
        # Insert before the "## Các Phím Tắt Windows Hữu Ích" line that may
        # appear at the end of this section's buffer. The split function
        # already placed everything before the next H2 into this section, so
        # there's no Windows H2 inside — just append rows to the end of the
        # last table (before any trailing blank lines).
        # We append to the table by inserting after the last "|" row.
        $lines = $mainTbl -split "`r?`n"
        $lastTableLineIndex = -1
        for ($i = $lines.Length - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '^\|') { $lastTableLineIndex = $i; break }
        }
        if ($lastTableLineIndex -ge 0) {
            $head = $lines[0..$lastTableLineIndex]
            $tail = if ($lastTableLineIndex -lt $lines.Length - 1) { $lines[($lastTableLineIndex + 1)..($lines.Length - 1)] } else { @() }
            $newLines = $head + ($extraRows -split "`n") + $tail
            $sections['Các Phím Tắt NVDA Quan Trọng'] = ($newLines -join "`n")
            Write-Host "  [vi] absorbed 2 rows into 'Các Phím Tắt NVDA Quan Trọng'"
        } else {
            Write-Warning "  [vi] could not find table end in 'Các Phím Tắt NVDA Quan Trọng' — skipping row absorption"
        }

        # 2. Merge 'Nghe Dấu Thanh Tiếng Việt' as H3 inside 'Gõ Tiếng Việt'.
        if ($sections.Contains('Nghe Dấu Thanh Tiếng Việt')) {
            $tonemark = $sections['Nghe Dấu Thanh Tiếng Việt']
            # Demote ## -> ###
            $tonemark = $tonemark -replace '^## (Nghe Dấu Thanh Tiếng Việt)', '### $1'
            # Append to end of Gõ Tiếng Việt (after a blank line)
            $sections['Gõ Tiếng Việt'] = (Get-SectionWithoutTrailingHr $sections['Gõ Tiếng Việt']) + "`n`n" + $tonemark.TrimStart() + "`n"
            Write-Host "  [vi] merged 'Nghe Dấu Thanh Tiếng Việt' as H3 inside 'Gõ Tiếng Việt'"
        }

        # 3. Trim the duplicate "Chuyển Việt/Anh: nhấn Ctrl + Shift." line that
        #    appears at the bottom of the Telex section (already stated at top).
        $goTV = $sections['Gõ Tiếng Việt']
        $goTVTrimmed = $goTV -replace '(?m)^Chuyển Việt/Anh: nhấn Ctrl \+ Shift\.\s*\r?\n', ''
        # Only trim if the "Để chuyển giữa..." line still exists at top (sanity)
        if ($goTV -match 'Để chuyển giữa Tiếng Việt và Tiếng Anh: nhấn Ctrl \+ Shift') {
            $sections['Gõ Tiếng Việt'] = $goTVTrimmed
            if ($goTVTrimmed -ne $goTV) {
                Write-Host "  [vi] trimmed duplicate 'Chuyển Việt/Anh' line in Gõ Tiếng Việt"
            }
        }
    }
    else {
        # EN file
        # 1. Absorb 2 unique rows into 'Important NVDA Shortcuts'
        $mainTbl = $sections['Important NVDA Shortcuts']
        $extraRows = @(
            "| NVDA + period (.) twice  | Say current character phonetically (names tone marks)         |"
            "| NVDA + C                 | Read clipboard contents (Ctrl + C is copies to the clipboard) |"
        ) -join "`n"
        $lines = $mainTbl -split "`r?`n"
        $lastTableLineIndex = -1
        for ($i = $lines.Length - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '^\|') { $lastTableLineIndex = $i; break }
        }
        if ($lastTableLineIndex -ge 0) {
            $head = $lines[0..$lastTableLineIndex]
            $tail = if ($lastTableLineIndex -lt $lines.Length - 1) { $lines[($lastTableLineIndex + 1)..($lines.Length - 1)] } else { @() }
            $newLines = $head + ($extraRows -split "`n") + $tail
            $sections['Important NVDA Shortcuts'] = ($newLines -join "`n")
            Write-Host "  [en] absorbed 2 rows into 'Important NVDA Shortcuts'"
        } else {
            Write-Warning "  [en] could not find table end in 'Important NVDA Shortcuts'"
        }

        # 2. Merge 'Hearing Vietnamese Tone Marks' as H3 inside 'Typing Vietnamese'
        if ($sections.Contains('Hearing Vietnamese Tone Marks')) {
            $tonemark = $sections['Hearing Vietnamese Tone Marks']
            $tonemark = $tonemark -replace '^## (Hearing Vietnamese Tone Marks)', '### $1'
            $sections['Typing Vietnamese'] = (Get-SectionWithoutTrailingHr $sections['Typing Vietnamese']) + "`n`n" + $tonemark.TrimStart() + "`n"
            Write-Host "  [en] merged 'Hearing Vietnamese Tone Marks' as H3 inside 'Typing Vietnamese'"
        }

        # 3. Trim duplicate "Switch Vietnamese/English" line at bottom of Telex
        $tv = $sections['Typing Vietnamese']
        $tvTrimmed = $tv -replace '(?m)^Switch Vietnamese/English: press Ctrl \+ Shift\.\s*\r?\n', ''
        if ($tv -match 'To Switch Vietnamese or English: press Ctrl \+ Shift') {
            $sections['Typing Vietnamese'] = $tvTrimmed
            if ($tvTrimmed -ne $tv) {
                Write-Host "  [en] trimmed duplicate 'Switch Vietnamese/English' line in Typing Vietnamese"
            }
        }
    }

    # ---- Reassemble ----

    $output = New-Object System.Text.StringBuilder
    [void]$output.Append($sections['__preamble__'])

    foreach ($title in $NewOrder) {
        if (-not $sections.Contains($title)) {
            Write-Warning "Section not found in file: '$title' (skipping)"
            continue
        }
        $body = (Get-SectionWithoutTrailingHr $sections[$title]).TrimEnd()
        [void]$output.AppendLine($body)
        [void]$output.AppendLine()
        [void]$output.AppendLine('---')
    }

    # Trim trailing "---" + add a final newline so the file ends cleanly
    $result = $output.ToString().TrimEnd("`r","`n"," ","-") + "`n"

    # Sections that exist in the input but are NOT in NewOrder + are NOT being
    # merged elsewhere = deleted. Report them so the user can verify.
    $kept = @($NewOrder + '__preamble__')
    if ($Lang -eq 'vi') { $kept += @('Nghe Dấu Thanh Tiếng Việt') }   # absorbed
    else                { $kept += @('Hearing Vietnamese Tone Marks') }  # absorbed
    $deleted = @($sections.Keys | Where-Object { $_ -notin $kept })
    foreach ($d in $deleted) { Write-Host "  [$Lang] DELETED section: '$d'" -ForegroundColor Yellow }

    [System.IO.File]::WriteAllText($Path, $result, [System.Text.UTF8Encoding]::new($false))

    Write-Host "  -> Rewrote $Path ($([math]::Round($result.Length/1KB,1)) KB)" -ForegroundColor Green
}

# ----- Main --------------------------------------------------------------------

$viPath = Join-Path $RepoRoot 'docs\Huong-Dan-Su-Dung-Full.md'
$enPath = Join-Path $RepoRoot 'docs\User-Guide.md'

Write-Host ""
Write-Host "=== Reorganizing Vietnamese (Huong-Dan-Su-Dung-Full.md) ===" -ForegroundColor Cyan
Reorganize-File -Path $viPath -NewOrder $newOrderVi -Lang 'vi'

Write-Host ""
Write-Host "=== Reorganizing English (User-Guide.md) ===" -ForegroundColor Cyan
Reorganize-File -Path $enPath -NewOrder $newOrderEn -Lang 'en'

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  1. Re-run .\Scripts\Build-Help-HTML.ps1 to regenerate the HTML." -ForegroundColor DarkGray
Write-Host "  2. Open docs/index.html in Firefox; press NVDA+F7 to confirm the new heading order." -ForegroundColor DarkGray
Write-Host "  3. If you want to revert: copy the .bak.<timestamp> file back over the .md." -ForegroundColor DarkGray
