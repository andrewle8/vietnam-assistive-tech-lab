# Installers Folder

This folder contains all software installers needed for deployment. Files are **NOT included in git** because they are too large.

## How to Download

```powershell
.\Scripts\0-Download-Installers.ps1    # Smart download from multiple sources
.\Scripts\Verify-Installers.ps1        # Validate all files + SHA256 checksums
```

The download script automatically fetches installers from the best source for each package:

| Source | What | Example |
|--------|------|---------|
| **Vendor URL** | Direct from software publisher | NVDA, Firefox, VLC |
| **GitHub Releases** | From the project's GitHub repo | Audacity, Thorium, SumatraPDF, Tailscale, rclone |
| **Kiwix** | ZIM files from download.kiwix.org | Vietnamese Wikipedia, Wiktionary, Wikisource |
| **Manual** | Must be pre-placed or on GitHub Release `installers-v1` | Sao Mai VNVoice, Typing Tutor, LEAP Games, NVDA Addons |

Source definitions are in `Scripts/installer-sources.json`. Versions come from `manifest.json`.

## What Gets Downloaded

| Folder | File | Source | Size |
|--------|------|--------|------|
| `NVDA/` | `nvda_2025.3.3.exe` | Vendor (nvaccess.org) | ~50 MB |
| `NVDA/addons/` | 7 NVDA add-ons (.nvda-addon) | Manual (GitHub Release) | ~13 MB |
| `SaoMai/` | `SaoMai_VNVoice_1.0.exe` | Manual | -- |
| `SaoMai/` | `SaoMai_TypingTutor.exe` | Manual | -- |
| `MSOffice/` | Office Deployment Tool + Office files | Manual (microsoft.com) | ~2 GB |
| `Firefox/` | `Firefox Setup 147.0.4.msi` | Vendor (mozilla.org) | ~60 MB |
| `Utilities/` | `VLC-3.0.23.exe` | Vendor (videolan.org) | ~40 MB |
| `Utilities/UniKey/` | `UniKeyNT.exe` | Manual (GitHub Release) | ~1 MB |
| `Audacity/` | `audacity-win-3.7.7-64bit.exe` | GitHub (audacity/audacity) | ~30 MB |
| `Quorum/` | `QuorumStudio-win64.exe` | Manual (GitHub Release) | ~335 MB |
| `Kiwix/` | Kiwix desktop + 3 Vietnamese ZIM files | GitHub + Kiwix | ~770 MB |
| `Thorium/` | `Thorium.Setup.3.3.0.exe` | GitHub (edrlab/thorium-reader) | ~117 MB |
| `Utilities/SumatraPDF/` | `SumatraPDF-3.5.2-64-install.exe` | GitHub (sumatrapdfreader/sumatrapdf) | ~15 MB |
| `Utilities/GoldenDict/` | GoldenDict portable | Manual (GitHub Release) | ~30 MB |
| `Utilities/Tailscale/` | `tailscale-setup-1.82.0-amd64.msi` | GitHub (tailscale/tailscale) | ~30 MB |
| `Utilities/rclone/` | rclone portable | GitHub (rclone/rclone) | ~15 MB |
| `Educational/` | LEAP Games (Tic-Tac-Toe, Tennis, Curve) | Manual (GitHub Release) | ~50 MB |

## Pre-Deployment Checklist

After running `0-Download-Installers.ps1`, validate with:

```powershell
.\Scripts\Verify-Installers.ps1
```

This checks every file exists and matches the SHA256 checksum recorded during download (stored in `Scripts/installer-checksums.json`).

### Expected directory structure

```
Installers/
├── NVDA/
│   ├── nvda_2025.3.3.exe
│   └── addons/
│       ├── VLC-2025.1.0.nvda-addon
│       ├── speechHistory-2024.3.1.nvda-addon
│       ├── nvdaRemote-2.6.4.nvda-addon
│       ├── focusHighlight-2.4.nvda-addon
│       ├── audacityAccessEnhancement-3.3.2.nvda-addon
│       ├── clock-20250714.nvda-addon
│       └── MathCAT.nvda-addon
├── SaoMai/
│   ├── SaoMai_VNVoice_1.0.exe
│   └── SaoMai_TypingTutor.exe
├── MSOffice/
│   ├── setup.exe (Office Deployment Tool)
│   ├── configuration.xml
│   └── Office/ (downloaded via setup.exe /download)
├── Firefox/
│   └── Firefox Setup 147.0.4.msi
├── Audacity/
│   └── audacity-win-3.7.7-64bit.exe
├── Quorum/
│   └── QuorumStudio-win64.exe
├── Utilities/
│   ├── VLC-3.0.23.exe
│   ├── UniKey/
│   │   └── UniKeyNT.exe
│   ├── SumatraPDF/
│   │   └── SumatraPDF-3.5.2-64-install.exe
│   ├── GoldenDict/
│   │   └── GoldenDict.exe (+ dependencies)
│   ├── Tailscale/
│   │   └── tailscale-setup-1.82.0-amd64.msi
│   └── rclone/
│       └── rclone.exe
├── Thorium/
│   └── Thorium.Setup.3.3.0.exe
├── Kiwix/
│   ├── kiwix-desktop.exe (+ dependencies)
│   ├── wikipedia_vi_all_mini_2025-11.zim
│   ├── wiktionary_vi_all_maxi_2025-11.zim
│   └── wikisource_vi_all_maxi_2025-11.zim
└── Educational/
    ├── TicTacToe/
    ├── Tennis/
    └── Curve/
```

## Version Notes

- **NVDA:** Use latest stable (2025.3.3 or newer)
- **Firefox:** 147 or newer
- **Microsoft Office:** 365 ProPlus (non-profit license, installed via ODT)
- **VLC:** Use stable release (3.0.23 or newer)
- **UniKey:** 4.6 RC2 or newer (Vietnamese keyboard)
- **Audacity:** 3.7.7 or newer
- **Quorum Studio:** Latest release from quorumlanguage.com
- **Thorium Reader:** 3.3.0 or newer (EPUB/DAISY reader from EDRLab)
- **Kiwix:** 2.5.1 or newer
- **SumatraPDF:** 3.5.2 or newer
- **GoldenDict:** 1.5.0 portable
- **Tailscale:** 1.82.0 or newer (mesh VPN for remote management)
- **rclone:** Latest (Google Drive sync for fleet health reports)

## Storage Requirements

Total installer package size: ~3-4 GB (including Office files, ZIM files, and Tailscale/rclone)
Recommended USB drive: 16 GB or larger (to include training materials)

## Backup Strategy

Create **3 USB drives** with identical content:
1. Primary deployment drive
2. Backup drive #1
3. Backup drive #2 (emergency)

Store drives separately to prevent loss.
