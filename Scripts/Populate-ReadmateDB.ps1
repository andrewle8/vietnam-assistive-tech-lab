<#
.SYNOPSIS
    Populates SM Readmate's SQLite database with all EPUB textbooks from C:\Ebooks.
.DESCRIPTION
    Uses winsqlite3.dll (ships with Windows 10/11) via P/Invoke to INSERT book
    records into SM Readmate's app_database.db.  No external dependencies required.

    For each .epub file found under C:\Ebooks, inserts a row into tb_books with:
      - title:   derived from filename (underscores -> spaces, no extension)
      - file_path: absolute path to the .epub file
      - create_time / update_time: current UTC timestamp (ISO-8601)
      - is_deleted: 0
      - reading_percentage: 0.0
      - All other optional columns: NULL

    Skips any file_path that already exists in the database (idempotent).
.NOTES
    Approach: winsqlite3.dll P/Invoke
    - sqlite3.exe is NOT on this system's PATH.
    - System.Data.SQLite and Microsoft.Data.Sqlite .NET assemblies are NOT installed.
    - winsqlite3.dll (Windows built-in, SQLite 3.51.1) is present in System32 and
      fully functional via C# P/Invoke from PowerShell.
#>

param(
    [string]$EbookDir   = "C:\Ebooks",
    [string]$DbPath     = "$env:APPDATA\SaoMai\SM Readmate\databases\app_database.db",
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── P/Invoke declarations for winsqlite3.dll ──────────────────────────
$sqlitePInvoke = @'
[DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_open_v2(
    [MarshalAs(UnmanagedType.LPUTF8Str)] string filename,
    out IntPtr ppDb,
    int flags,
    IntPtr zVfs);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_close", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_close(IntPtr db);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_exec", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_exec(
    IntPtr db,
    [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
    IntPtr callback,
    IntPtr arg,
    out IntPtr errmsg);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_prepare_v2(
    IntPtr db,
    [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
    int nByte,
    out IntPtr stmt,
    out IntPtr pzTail);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_text", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_text(
    IntPtr stmt,
    int index,
    [MarshalAs(UnmanagedType.LPUTF8Str)] string val,
    int nBytes,
    IntPtr destructor);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_double", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_double(IntPtr stmt, int index, double val);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_int", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_int(IntPtr stmt, int index, int val);

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_bind_null", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_bind_null(IntPtr stmt, int index);

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

[DllImport("winsqlite3.dll", EntryPoint="sqlite3_changes", CallingConvention=CallingConvention.Cdecl)]
public static extern int sqlite3_changes(IntPtr db);
'@

# Load the P/Invoke type (idempotent — Add-Type will error if already loaded in this session,
# so we check first)
if (-not ([System.Management.Automation.PSTypeName]'Win32.SQLite3').Type) {
    Add-Type -MemberDefinition $sqlitePInvoke -Name 'SQLite3' -Namespace 'Win32'
}

# Constants
$SQLITE_OK        = 0
$SQLITE_ROW       = 100
$SQLITE_DONE      = 101
$SQLITE_OPEN_READWRITE = 2
$SQLITE_OPEN_CREATE    = 4
$SQLITE_TRANSIENT = [IntPtr]::New(-1)   # SQLITE_TRANSIENT tells SQLite to copy the string

# ── Helper: get the error message from the db handle ──────────────────
function Get-SqliteError([IntPtr]$db) {
    $ptr = [Win32.SQLite3]::sqlite3_errmsg($db)
    if ($ptr -ne [IntPtr]::Zero) {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)
    }
    return "(unknown error)"
}

# ── Derive a human-readable title from the EPUB filename ─────────────
function Get-BookTitle([string]$fileName) {
    # "Toan_11_Tap_1_CD.epub" -> "Toan 11 Tap 1 CD"
    $name = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    return $name -replace '_', ' '
}

# ── SM Readmate database schema (for creating on fresh installs) ─────
$createSchema = @"
CREATE TABLE IF NOT EXISTS tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  cover_path TEXT,
  file_path TEXT,
  last_read_position TEXT,
  reading_percentage REAL,
  author TEXT,
  is_deleted INTEGER,
  description TEXT,
  create_time TEXT,
  update_time TEXT,
  rating REAL,
  group_id INTEGER);
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

# ── Validate inputs ──────────────────────────────────────────────────
if (-not (Test-Path $EbookDir)) {
    Write-Error "Ebook directory not found: $EbookDir"
    exit 1
}

# Create database directory and file if they don't exist (fresh install)
$dbDir = Split-Path $DbPath -Parent
if (-not (Test-Path $dbDir)) {
    New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
    Write-Host "Created database directory: $dbDir"
}

# Discover EPUB files
$epubFiles = Get-ChildItem -Path $EbookDir -Filter "*.epub" -Recurse -ErrorAction Stop |
             Sort-Object FullName
if ($epubFiles.Count -eq 0) {
    Write-Warning "No .epub files found under $EbookDir"
    exit 0
}
Write-Host "Found $($epubFiles.Count) EPUB files under $EbookDir"

if ($WhatIf) {
    Write-Host "`n[WhatIf] Would insert the following books:"
    foreach ($f in $epubFiles) {
        $title = Get-BookTitle $f.Name
        Write-Host "  Title: $title"
        Write-Host "  Path:  $($f.FullName)"
        Write-Host ""
    }
    Write-Host "[WhatIf] No changes made."
    exit 0
}

# ── Open database (create if it doesn't exist) ──────────────────────
$db = [IntPtr]::Zero
$rc = [Win32.SQLite3]::sqlite3_open_v2($DbPath, [ref]$db, ($SQLITE_OPEN_READWRITE -bor $SQLITE_OPEN_CREATE), [IntPtr]::Zero)
if ($rc -ne $SQLITE_OK) {
    $err = Get-SqliteError $db
    Write-Error "Failed to open database: $err (rc=$rc)"
    exit 1
}
Write-Host "Opened database: $DbPath"

# Ensure schema exists (idempotent — uses CREATE TABLE IF NOT EXISTS)
$errMsg = [IntPtr]::Zero
$rc = [Win32.SQLite3]::sqlite3_exec($db, $createSchema, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg)
if ($rc -ne $SQLITE_OK) {
    Write-Error "Failed to create schema: $(Get-SqliteError $db)"
    [Win32.SQLite3]::sqlite3_close($db) | Out-Null
    exit 1
}

try {
    # ── Collect existing file_path values to skip duplicates ─────────
    $existingPaths = @{}
    $stmt = [IntPtr]::Zero; $tail = [IntPtr]::Zero
    $rc = [Win32.SQLite3]::sqlite3_prepare_v2($db, "SELECT file_path FROM tb_books WHERE is_deleted = 0;", -1, [ref]$stmt, [ref]$tail)
    if ($rc -eq $SQLITE_OK) {
        while ([Win32.SQLite3]::sqlite3_step($stmt) -eq $SQLITE_ROW) {
            $ptr = [Win32.SQLite3]::sqlite3_column_text($stmt, 0)
            if ($ptr -ne [IntPtr]::Zero) {
                $path = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)
                $existingPaths[$path] = $true
            }
        }
    }
    [Win32.SQLite3]::sqlite3_finalize($stmt) | Out-Null
    Write-Host "Existing non-deleted books in database: $($existingPaths.Count)"

    # ── Begin transaction ────────────────────────────────────────────
    $errMsg = [IntPtr]::Zero
    $rc = [Win32.SQLite3]::sqlite3_exec($db, "BEGIN TRANSACTION;", [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg)
    if ($rc -ne $SQLITE_OK) {
        Write-Error "BEGIN TRANSACTION failed: $(Get-SqliteError $db)"
        exit 1
    }

    # ── Prepare the INSERT statement ─────────────────────────────────
    # Parameters: 1=title, 2=file_path, 3=is_deleted, 4=reading_percentage, 5=create_time, 6=update_time
    $insertSql = "INSERT INTO tb_books (title, cover_path, file_path, last_read_position, reading_percentage, " +
                  "author, is_deleted, description, create_time, update_time, rating, group_id) " +
                  "VALUES (?1, NULL, ?2, NULL, ?3, NULL, ?4, NULL, ?5, ?6, NULL, NULL);"

    $insertStmt = [IntPtr]::Zero; $tail = [IntPtr]::Zero
    $rc = [Win32.SQLite3]::sqlite3_prepare_v2($db, $insertSql, -1, [ref]$insertStmt, [ref]$tail)
    if ($rc -ne $SQLITE_OK) {
        Write-Error "Failed to prepare INSERT: $(Get-SqliteError $db)"
        exit 1
    }

    # ── Insert each EPUB ─────────────────────────────────────────────
    $inserted = 0
    $skipped  = 0
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")

    foreach ($epub in $epubFiles) {
        $filePath = $epub.FullName
        $title    = Get-BookTitle $epub.Name

        # Skip if already in database
        if ($existingPaths.ContainsKey($filePath)) {
            Write-Host "  SKIP (exists): $title"
            $skipped++
            continue
        }

        # Bind parameters
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt, 1, $title, -1, $SQLITE_TRANSIENT)    | Out-Null  # title
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt, 2, $filePath, -1, $SQLITE_TRANSIENT) | Out-Null  # file_path
        [Win32.SQLite3]::sqlite3_bind_double($insertStmt, 3, 0.0)                            | Out-Null  # reading_percentage
        [Win32.SQLite3]::sqlite3_bind_int($insertStmt, 4, 0)                                 | Out-Null  # is_deleted
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt, 5, $now, -1, $SQLITE_TRANSIENT)      | Out-Null  # create_time
        [Win32.SQLite3]::sqlite3_bind_text($insertStmt, 6, $now, -1, $SQLITE_TRANSIENT)      | Out-Null  # update_time

        $rc = [Win32.SQLite3]::sqlite3_step($insertStmt)
        if ($rc -ne $SQLITE_DONE) {
            Write-Warning "  FAIL: $title - $(Get-SqliteError $db)"
        } else {
            Write-Host "  INSERT: $title"
            $inserted++
        }

        [Win32.SQLite3]::sqlite3_reset($insertStmt) | Out-Null
    }

    [Win32.SQLite3]::sqlite3_finalize($insertStmt) | Out-Null

    # ── Commit ───────────────────────────────────────────────────────
    $rc = [Win32.SQLite3]::sqlite3_exec($db, "COMMIT;", [IntPtr]::Zero, [IntPtr]::Zero, [ref]$errMsg)
    if ($rc -ne $SQLITE_OK) {
        Write-Error "COMMIT failed: $(Get-SqliteError $db)"
        exit 1
    }

    Write-Host "`n=== Summary ==="
    Write-Host "Inserted: $inserted"
    Write-Host "Skipped (already existed): $skipped"
    Write-Host "Total EPUBs found: $($epubFiles.Count)"

} finally {
    # Always close the database handle
    [Win32.SQLite3]::sqlite3_close($db) | Out-Null
    Write-Host "Database closed."
}
