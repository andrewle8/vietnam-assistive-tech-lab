# Installers Folder

This folder should contain all software installers needed for deployment.

## How to Download

The installer files are **NOT included in this git repository** because they are too large. All installers are hosted on **GitHub Releases** and downloaded automatically:

```powershell
cd F:\Vietnam-Lab-Kit\Scripts
.\0-Download-Installers.ps1
```

**No manual downloads required.** The script pulls everything from:
https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/tag/installers-v1

## What Gets Downloaded

| Folder | File | Size |
|--------|------|------|
| `NVDA/` | `nvda_2025.3.2.exe` | ~50 MB |
| `NVDA/addons/` | `VLC.nvda-addon` | ~1 MB |
| `SaoMai/` | `SaoMai_VNVoice_1.0.exe` | — |
| `SaoMai/` | `SaoMai_TypingTutor.exe` | — |
| `LibreOffice/` | `LibreOffice_26.2.0_Win_x86-64.msi` | ~300 MB |
| `Firefox/` | `Firefox Setup 147.0.3.msi` | ~60 MB |
| `Utilities/` | `VLC-3.0.23.exe` | ~40 MB |
| `Educational/` | LEAP Games (Tic-Tac-Toe, Tennis, Curve) | ~50 MB |

## Pre-Deployment Checklist

After running `0-Download-Installers.ps1`, verify all files are present:

```
Installers/
├── NVDA/
│   ├── nvda_2025.3.2.exe
│   ├── nvda-portable.zip           (backup)
│   └── addons/
│       └── VLC.nvda-addon
├── SaoMai/
│   ├── SaoMai_VNVoice_1.0.exe
│   └── SaoMai_TypingTutor.exe
├── LibreOffice/
│   └── LibreOffice_26.2.0_Win_x86-64.msi
├── Firefox/
│   └── Firefox Setup 147.0.3.msi
├── Utilities/
│   └── VLC-3.0.23.exe
└── Educational/
    ├── TicTacToe/
    │   ├── tictactoe_eng_win64.exe
    │   └── tictactoe_eng_win64_Data/
    ├── Tennis/
    │   ├── tennis_eng_win64.exe
    │   └── tennis_eng_win64_Data/
    └── Curve/
        ├── curve_eng_win64.exe
        └── curve_eng_win64_Data/
```

## Version Notes

- **NVDA:** Use latest stable (2025.3.2 or newer)
- **Firefox:** 147 or newer
- **LibreOffice:** 26.2.0 or newer
- **VLC:** Use stable release (3.0.23 or newer)

## Storage Requirements

Total installer package size: ~500-600 MB
Recommended USB drive: 8 GB or larger (to include training materials)

## Testing

**Before deployment**, test the installation process on one PC to verify:
1. All installers run silently without errors
2. Scripts complete successfully
3. No missing dependencies
4. Offline operation confirmed

## Backup Strategy

Create **3 USB drives** with identical content:
1. Primary deployment drive
2. Backup drive #1
3. Backup drive #2 (emergency)

Store drives separately to prevent loss.
