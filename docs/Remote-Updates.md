# Remote Update Playbook

How to push updates to the 19 deployed laptops after they leave your hands.

## How it works

Every laptop runs `C:\LabTools\update-agent\Update-Agent.ps1` as a scheduled task at 6 PM Vietnam time (ICT, GMT+7). The agent:

1. Fetches `https://raw.githubusercontent.com/andrewle8/vietnam-assistive-tech-lab/main/update-manifest.json`
2. Compares `update_version` (remote) against `manifest_version` (local copy at `C:\LabTools\manifest.json`)
3. If remote is newer, downloads every file listed in `packages` from the URL in `release_base`, verifies SHA256, installs
4. Runs every script listed in `scripts` (downloads + SHA256-verifies first)
5. Reports results to `C:\LabTools\update-agent\results\update-YYYY-MM-DD.json`
6. Bumps local `manifest_version` to match remote

Safety windows:
- No updates 7 AM – 5 PM (school/homework hours)
- No updates if no internet
- Lock file prevents concurrent runs

## Important: known agent quirk

The deployed `Update-Agent.ps1` has an early-exit when `packages` is empty — it will NOT run the `scripts` array alone. **Any update that runs a script must include at least one entry in `packages` first.** For book pushes, just put the first EPUB of the batch in `packages` and the rest happen in the script. A non-`.exe`/`.msi` package logs a harmless "Unknown installer type" error but doesn't block the scripts array from running.

## Pushing a book batch

### One-time prep

1. Finish downloading the EPUB files from Sao Mai (manual, limited)
2. Organize by curriculum folder on your Mac: `Canh Dieu/`, `Ket Noi Tri Thuc/`, `Chan Troi Sang Tao/`, `Tieng Anh/`

### Per batch

**1. Upload all EPUBs + the import script to the `installers-v1` release.**

```bash
# From your Mac repo root
gh release upload installers-v1 path/to/Toan_6_Tap_2_KNTT.epub --repo andrewle8/vietnam-assistive-tech-lab
gh release upload installers-v1 path/to/Ngu_Van_7_Tap_2_CD.epub --repo andrewle8/vietnam-assistive-tech-lab
# ...for each book

# Upload the script too
gh release upload installers-v1 Scripts/remote-updates/Import-Books-Remote.ps1 --repo andrewle8/vietnam-assistive-tech-lab
```

**2. Edit `Scripts/remote-updates/Import-Books-Remote.ps1`** — fill the `$books` array at the top:

```powershell
$books = @(
    @{ name = "Toan_6_Tap_2_KNTT.epub";  folder = "Ket Noi Tri Thuc" },
    @{ name = "Ngu_Van_7_Tap_2_CD.epub"; folder = "Canh Dieu" }
)
```

Filenames must exactly match what you uploaded. Folders must match the directory layout used by `Populate-ReadmateDB.ps1` at deploy time (Readmate stores books under those subfolders already).

**3. Compute SHA256 hashes.**

```bash
# For the trigger EPUB (first book in the batch)
shasum -a 256 path/to/Toan_6_Tap_2_KNTT.epub

# For the import script (use the UPDATED version with the filled $books array)
shasum -a 256 Scripts/remote-updates/Import-Books-Remote.ps1
```

The script hash must be computed on the version you uploaded. If you re-upload after editing, re-hash.

**4. Edit `update-manifest.json`** — bump version, populate arrays:

```json
{
  "schema_version": 1,
  "update_version": "2026.05.15",
  "min_local_version": "2026.04.01",
  "release_tag": "installers-v1",
  "release_base": "https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/download/installers-v1",
  "notes": "Book batch 2 — 12 new EPUBs across 4 curricula",
  "packages": [
    {
      "id": "book_batch_2_trigger",
      "version": "2026.05.15",
      "filename": "Toan_6_Tap_2_KNTT.epub",
      "sha256": "<hash from step 3>",
      "critical": false
    }
  ],
  "scripts": [
    {
      "id": "import_books_batch_2",
      "filename": "Import-Books-Remote.ps1",
      "sha256": "<hash from step 3>"
    }
  ]
}
```

Notes:
- `update_version` must be greater than the local `manifest_version` on the laptops (today: `2026.04.01`). Use `YYYY.MM.DD` to keep it monotonic.
- `min_local_version` guards against rolling this out to laptops with older agents that wouldn't understand newer fields. Leave it at `2026.04.01` for now.
- The trigger EPUB in `packages` exists only to pass the agent's early-exit check. Pick any EPUB from the batch — the script re-downloads/imports all of them anyway.

**5. Commit and push.**

```bash
git add update-manifest.json Scripts/remote-updates/Import-Books-Remote.ps1
git commit -m "update"
git push
```

**6. Wait.** At 6 PM Vietnam that evening, every powered-on laptop with internet pulls the update. Check results the next day:
- Laptops write `C:\LabTools\update-agent\results\update-YYYY-MM-DD.json`
- Laptops write logs to `C:\LabTools\update-agent\logs\YYYY-MM-DD.log`
- You can't read those remotely without physical access

**7. After success: reset the arrays.**

Once the batch has rolled out and you've confirmed it worked (on whatever laptops you can check), reset the manifest back to dormant:

```json
"packages": [],
"scripts": [],
"notes": "Batch 2 deployed YYYY-MM-DD. Ready for next push."
```

Don't reset `update_version` backward — always bump forward to prevent re-running the same update.

## Pushing a software update (e.g., NVDA 2026.1)

Same pattern, but the package is the real installer (`.exe` or `.msi`):

```json
"packages": [
  {
    "id": "nvda",
    "version": "2026.1",
    "filename": "nvda_2026.1.exe",
    "sha256": "<hash>",
    "critical": true,
    "install_args": ["--install", "--silent"]
  }
]
```

- Upload the installer to `installers-v1` release
- `critical: true` enables rollback if install fails (agent restores from `C:\LabTools\update-agent\rollback\`)
- `install_args` is passed to the installer; default for `.exe` is `/S`

## Pushing a fleet-wide one-shot script

Same pattern as the book push (trigger EPUB/file in `packages`, script in `scripts`). The script runs as SYSTEM — it can touch registry, services, scheduled tasks, any user profile via absolute paths. Be careful.

## Safety notes

- **Idempotence:** The book import script uses `SELECT file_path FROM tb_books WHERE is_deleted = 0` to skip books already in the database. Re-running the same batch does nothing.
- **Transaction atomicity:** All DB inserts wrapped in a transaction. Partial failure rolls back — no corrupt library.
- **Student profile pinned:** Script hardcodes `C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\`. It does NOT use `$env:APPDATA` (which resolves to the SYSTEM profile when run by the scheduled task).
- **No EPUB is ever deleted:** Script only appends. Existing books on the laptop — including the 77 that shipped on the USB — stay untouched.
- **Dormant by default:** When `update-manifest.json` has `packages: []` and `scripts: []`, the agent logs "Nothing to do" and exits. No side effects.

## Limits to be aware of

- **GitHub Release asset size:** 2 GB per file. EPUBs are <5 MB each, comfortably under.
- **Bandwidth at the orphanage:** 35 EPUBs × 5 MB × 19 laptops ≈ 3.3 GB concentrated at 6 PM. If the connection is thin, push in smaller batches over several nights.
- **No remote log access:** Without Tailscale/SSH, you can't see a laptop's `logs/` or `results/` directly. You'll only know an update worked if you physically check a laptop or if the laptop comes back to you later.
- **Scheduled task must be running:** If something disabled `LabUpdateAgent`, updates silently never run. Audit can catch this (`7-Audit.ps1` checks the task exists).

## What this system cannot do

- Update the `Update-Agent.ps1` itself remotely (chicken-and-egg — the buggy early-exit blocks any scripts-only fix; would need a `.exe`-wrapped self-replacer)
- Uninstall software (no logic path for it — would need a custom script)
- Update the OS
- Run anything in the Student user's interactive session (task runs as SYSTEM)
- Provide feedback about success/failure without physical access to the laptop
