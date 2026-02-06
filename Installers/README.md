# Installers Folder

This folder should contain all software installers needed for deployment.

## IMPORTANT: Download Required

The installer files are **NOT included in this git repository** because they are too large. You must download them separately before deployment.

## Required Downloads

### 1. NVDA/
- **File:** `nvda_2025.3.2.exe` (or latest stable)
- **Source:** https://www.nvaccess.org/download/
- **Type:** Installer + Portable backup
- **Size:** ~50 MB

#### NVDA Add-ons (in `NVDA/addons/` subfolder)
- **File:** `VLC.nvda-addon` (or similar name)
- **Source:** https://addons.nvda-project.org/ (search for "VLC")
- **Notes:** Provides enhanced VLC accessibility (tab navigation, status announcements)

### 2. SaoMai/
- **File:** `SaoMai_VNVoice_1.0.exe`
- **Source:** https://saomaicenter.org/en/downloads
- **Notes:** Vietnamese TTS engine (SAPI5)

- **File:** `SaoMai_TypingTutor.exe`
- **Source:** https://saomaicenter.org/en/downloads/vietnamese-talking-software/sao-mai-typing-tutor-smtt
- **Notes:** Vietnamese typing lessons

### 3. LibreOffice/
- **File:** `LibreOffice_26.2.0_Win_x86-64.msi`
- **Source:** https://www.libreoffice.org/download/download/
- **Type:** Windows x86-64 MSI installer
- **Size:** ~300 MB

### 4. Firefox/
- **File:** `Firefox Setup 147.0.3.msi`
- **Source:** https://www.mozilla.org/en-US/firefox/
- **Type:** Windows 64-bit MSI
- **Size:** ~60 MB

### 5. Utilities/
- **File:** `VLC-3.0.x.exe`
- **Source:** https://www.videolan.org/vlc/
- **Size:** ~40 MB

### 6. Educational/
- **Files:** LEAP Games (Tic-Tac-Toe, Tennis, Curve) - Windows 64-bit executables
- **Source:** https://www.gamesfortheblind.org/
- **Notes:** Educational audio games designed for blind children by SciFY
- **Size:** ~50 MB total

> **Note:** 7-Zip has been removed from the software stack. Windows 11 (24H2) has built-in support for ZIP, 7z, RAR, TAR, GZ, BZ2, and XZ archive formats.

## Pre-Deployment Checklist

Before traveling to Vietnam, verify all files are present:

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
│   └── VLC-3.0.x.exe
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
- **VLC:** Use stable release (3.0.x)

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

Store drives separately during travel to prevent loss.
