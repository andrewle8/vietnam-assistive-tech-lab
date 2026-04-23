param(
    [string]$ReleaseBase = "https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/download/installers-v1",
    [string]$StudentDbPath = "C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\databases\app_database.db",
    [string]$StagingDir = "C:\LabTools\update-agent\staging\books"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ────────────────────────────────────────────────────────────
# BOOK LIST — add entries here when pushing a batch.
# Format: @{ name = "<filename>.epub"; folder = "<curriculum subfolder>" }
# The folder determines the subdirectory under SM Readmate's file/ directory.
# Valid folders match the existing deployment: "Canh Dieu", "Ket Noi Tri Thuc",
# "Chan Troi Sang Tao", "Tieng Anh".
# When this array is empty, the script is a no-op.
# ────────────────────────────────────────────────────────────
$books = @(
    # @{ name = "Toan_6_Tap_2_KNTT.epub";   folder = "Ket Noi Tri Thuc" }
    # @{ name = "Ngu_Van_7_Tap_2_CD.epub";  folder = "Canh Dieu" }
)

if ($books.Count -eq 0) {
    Write-Host "Import-Books-Remote: book list is empty. Nothing to do."
    exit 0
}

# ────────────────────────────────────────────────────────────
# SQLite P/Invoke (uses winsqlite3.dll, ships with Windows 10/11)
# ────────────────────────────────────────────────────────────
$sqlitePInvoke = @'
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_open_v2([MarshalAs(UnmanagedType.LPUTF8Str)] string filename, out IntPtr ppDb, int flags, IntPtr zVfs);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_close", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_close(IntPtr db);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_exec", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_exec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, IntPtr callback, IntPtr arg, out IntPtr errmsg);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_prepare_v2(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int nByte, out IntPtr stmt, out IntPtr pzTail);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_text", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_text(IntPtr stmt, int index, [MarshalAs(UnmanagedType.LPUTF8Str)] string val, int nBytes, IntPtr destructor);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_double", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_double(IntPtr stmt, int index, double val);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_int", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_int(IntPtr stmt, int index, int val);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_step", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_step(IntPtr stmt);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_reset", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_reset(IntPtr stmt);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_finalize(IntPtr stmt);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_text", CallingConvention=CallingConvention.Cdecl)]
public static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_errmsg", CallingConvention=CallingConvention.Cdecl)]
public static extern IntPtr sqlite3_errmsg(IntPtr db);
'@

if (-not ([System.Management.Automation.PSTypeName]'Win32.SQLite3').Type) {
    Add-Type -MemberDefinition $sqlitePInvoke -Name 'SQLite3' -Namespace 'Win32'
}

$SQLITE_OK             = 0
$SQLITE_ROW            = 100
$SQLITE_DONE           = 101
$SQLITE_OPEN_READWRITE = 2
$SQLITE_OPEN_CREATE    = 4
$SQLITE_TRANSIENT      = [IntPtr]::New(-1)

function Get-SqliteError([IntPtr]$db) {
    $ptr = [Win32.SQLite3]::sqlite3_errmsg($db)
    if ($ptr -ne [IntPtr]::Zero) { return [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr) }
    return "(unknown error)"
}

function Get-BookTitle([string]$fileName) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    return $name -replace '_', ' '
}

$createSchema = @"
CREATE TABLE IF NOT EXISTS tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, cover_path TEXT, file_path TEXT,
  last_read_position TEXT, reading_percentage REAL,
  author TEXT, is_deleted INTEGER, description TEXT,
  create_time TEXT, update_time TEXT, rating REAL, group_id INTEGER);
CREATE TABLE IF NOT EXISTS tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER, content TEXT, cfi TEXT, chapter TEXT,
  type TEXT, color TEXT, create_time TEXT, update_time TEXT, reader_note TEXT);
CREATE TABLE IF NOT EXISTS tb_reading_time (
  id INTEGER PRIMARY KEY, book_id INTEGER, date TEXT, reading_time INTEGER);
CREATE TABLE IF NOT EXISTS tb_styles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  font_size REAL, font_family TEXT, line_height REAL, letter_spacing REAL,
  word_spacing REAL, paragraph_spacing REAL, side_margin REAL,
  top_margin REAL, bottom_margin REAL);
CREATE TABLE IF NOT EXISTS tb_themes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  background_color TEXT, text_color TEXT, background_image_path TEXT);
"@

# ────────────────────────────────────────────────────────────
# Download books
# ────────────────────────────────────────────────────────────
New-Item -Path $StagingDir -ItemType Directory -Force | Out-Null
Write-Host "Downloading $($books.Count) book(s) to $StagingDir..."

$downloadedCount = 0
foreach ($book in $books) {
    $targetDir = Join-Path $StagingDir $book.folder
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    $outFile = Join-Path $targetDir $book.name

    if (Test-Path $outFile) {
        Write-Host "  Already staged: $($book.name)"
        $downloadedCount++
        continue
    }

    $url = "$ReleaseBase/$($book.name)"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -TimeoutSec 300
        Write-Host "  Downloaded: $($book.name)"
        $downloadedCount++
    } catch {
        Write-Warning "  Download failed for $($book.name): $($_.Exception.Message)"
    }
}

if ($downloadedCount -eq 0) {
    Write-Warning "No books downloaded. Aborting import."
    exit 1
}

# ────────────────────────────────────────────────────────────
# Resolve SM Readmate file folder from the DB path
# DbPath = ...\SM Readmate\databases\app_database.db → base = ...\SM Readmate
# ────────────────────────────────────────────────────────────
$dbDir     = Split-Path $StudentDbPath -Parent
$smBaseDir = Split-Path $dbDir -Parent
$smFileDir = Join-Path $smBaseDir "file"

foreach ($d in @($smBaseDir, $dbDir, $smFileDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ────────────────────────────────────────────────────────────
# Copy staged EPUBs into SM Readmate's file folder (preserving subfolders)
# ────────────────────────────────────────────────────────────
$epubFiles = Get-ChildItem -Path $StagingDir -Filter "*.epub" -Recurse -ErrorAction Stop | Sort-Object FullName
$stagingRoot = (Resolve-Path $StagingDir).Path.TrimEnd('\') + '\'
$copied = 0

foreach ($epub in $epubFiles) {
    $relPath  = $epub.FullName.Substring($stagingRoot.Length)
    $destFile = Join-Path $smFileDir $relPath
    $destDir  = Split-Path $destFile -Parent
    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $destFile)) {
        Copy-Item -Path $epub.FullName -Destination $destFile -Force
        $copied++
    }
}
Write-Host "Copied $copied new EPUB file(s) into SM Readmate library folder."

# ────────────────────────────────────────────────────────────
# Open database (create schema if fresh)
# ────────────────────────────────────────────────────────────
$db = [IntPtr]::Zero
$rc = [Win32.SQLite3]::sqlite3_open_v2($StudentDbPath, [ref]$db, ($SQLITE_OPEN_READWRITE -bor $SQLITE_OPEN_CREATE), [IntPtr]::Zero)
if ($rc -ne $SQLITE_OK) {
    Write-Error "Failed to open database: $(Get-SqliteError $db) (rc=$rc)"
    exit 1
}

try {
    $errMsg = [IntPtr]::Zero
    $rc = [Win32.SQLite3]::sqlite3_exec($db, $createSchema, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg)
    if ($rc -ne $SQLITE_OK) {
        Write-Error "Failed to create schema: $(Get-SqliteError $db)"
        exit 1
    }

    $existingPaths = @{}
    $stmt = [IntPtr]::Zero; $tail = [IntPtr]::Zero
    [Win32.SQLite3]::sqlite3_prepare_v2($db, "SELECT file_path FROM tb_books WHERE is_deleted = 0;", -1, [ref]$stmt, [ref]$tail) | Out-Null
    while ([Win32.SQLite3]::sqlite3_step($stmt) -eq $SQLITE_ROW) {
        $ptr = [Win32.SQLite3]::sqlite3_column_text($stmt, 0)
        if ($ptr -ne [IntPtr]::Zero) {
            $existingPaths[[System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)] = $true
        }
    }
    [Win32.SQLite3]::sqlite3_finalize($stmt) | Out-Null
    Write-Host "Existing non-deleted books in database: $($existingPaths.Count)"

    [Win32.SQLite3]::sqlite3_exec($db, "BEGIN TRANSACTION;", [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg) | Out-Null

    $insertSql = "INSERT INTO tb_books (title, cover_path, file_path, last_read_position, reading_percentage, " +
                  "author, is_deleted, description, create_time, update_time, rating, group_id) " +
                  "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12);"

    $insertStmt = [IntPtr]::Zero; $tail = [IntPtr]::Zero
    [Win32.SQLite3]::sqlite3_prepare_v2($db, $insertSql, -1, [ref]$insertStmt, [ref]$tail) | Out-Null

    $inserted = 0
    $skipped  = 0
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")

    foreach ($epub in $epubFiles) {
        $relPath  = $epub.FullName.Substring($stagingRoot.Length)
        $filePath = "file\$relPath"
        $title    = Get-BookTitle $epub.Name

        if ($existingPaths.ContainsKey($filePath)) {
            $skipped++
            continue
        }

        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   1, $title,    -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   2, "",        -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   3, $filePath, -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   4, "",        -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_double($insertStmt, 5, 0.0)                              | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   6, "",        -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_int($insertStmt,    7, 0)                                | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   8, "",        -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,   9, $now,      -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt,  10, $now,      -1, $SQLITE_TRANSIENT) | Out-Null
        [Win32.SQLite3]::sqlite3_bind_double($insertStmt,11, 0.0)                              | Out-Null
        [Win32.SQLite3]::sqlite3_bind_int($insertStmt,   12, 0)                                | Out-Null

        $rc = [Win32.SQLite3]::sqlite3_step($insertStmt)
        if ($rc -ne $SQLITE_DONE) {
            Write-Warning "  FAIL: $title - $(Get-SqliteError $db)"
        } else {
            $inserted++
        }
        [Win32.SQLite3]::sqlite3_reset($insertStmt) | Out-Null
    }

    [Win32.SQLite3]::sqlite3_finalize($insertStmt) | Out-Null
    [Win32.SQLite3]::sqlite3_exec($db, "COMMIT;", [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg) | Out-Null

    Write-Host ""
    Write-Host "=== Summary ==="
    Write-Host "Inserted: $inserted"
    Write-Host "Skipped (already existed): $skipped"
    Write-Host "Total EPUBs processed: $($epubFiles.Count)"

} finally {
    [Win32.SQLite3]::sqlite3_close($db) | Out-Null
    Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}
