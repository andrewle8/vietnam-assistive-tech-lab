# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Deployment:** April 2026 (1-3 days on-site)
**Equipment:** 10 Windows 11 PCs / Laptops (x86-64)

---

## Project Overview

This repository contains everything needed to deploy a fully **offline, open-source** assistive technology lab for blind children in Vietnam.

### Key Features
- 100% Free/Open Source software stack
- Fully offline operation (no internet required)
- Vietnamese language support (interface + TTS)
- Automated PowerShell deployment scripts
- Complete documentation in Vietnamese and English

---

## Software Stack (All Free/Open Source)

> If Office is already provided with the PCs, omit LibreOffice.
| Component | License | Purpose |
|-----------|---------|---------|
| **NVDA 2025.3.2** | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | Free (non-commercial) | Vietnamese text-to-speech (SAPI5) |
| **Sao Mai Typing Tutor** | Free | Vietnamese typing lessons with audio |
| **LibreOffice 26.2.0** | MPL-2.0 | Office suite (Word/Excel alternative) |
| **Firefox 147** | MPL-2.0 | Accessible web browser |
| **VLC Media Player 3.0.23** | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | GPL-2.0 | VLC accessibility enhancement for NVDA |
| **Access8Math NVDA Add-on** | GPL-3.0 | Math content reading/writing via speech |
| **LEAP Games** | Apache-2.0 | Educational audio games for blind children |

> **NVDA Add-ons:** [NVDA Add-on Store](https://addonstore.nvaccess.org/)

> **Architecture:** This kit assumes Windows 11 on **x86-64** (Intel/AMD). If the PCs use ARM processors (e.g. Snapdragon), the software stack will need to be replaced with ARM-compatible builds.

**Total Software Cost: $0**

### Hardware (Already Purchased)
- 10x Windows 11 PCs
- Headphones

---

## Quick Start

### For Deployment (On-Site in Vietnam)

1. **Download all installers** (fully automated from GitHub Releases)
   ```powershell
   cd F:\Vietnam-Lab-Kit\Scripts
   .\0-Download-Installers.ps1
   ```

2. **Copy entire folder to USB drive** (8GB+)

3. **Run deployment scripts** on each PC:
   ```powershell
   # Run as Administrator
   cd X:\Scripts
   .\1-Install-All.ps1
   .\2-Verify-Installation.ps1
   .\3-Configure-NVDA.ps1
   ```
4. **(Optional) Prepare student USB drives:**
   ```powershell
   .\4-Prepare-Student-USB.ps1
   .\5-Configure-Loaner-Laptop.ps1
   ```
5. **Test complete workflow** on each station


**Note:** Installer files are NOT included in git (too large). Run `0-Download-Installers.ps1` to download everything automatically from [GitHub Releases](#download-urls).

---

## Repository Structure

```
Vietnam-Lab-Kit/
├── Installers/           # Software installers (download separately)
│   ├── NVDA/
│   │   └── addons/       # NVDA add-on files (.nvda-addon)
│   ├── SaoMai/
│   ├── LibreOffice/
│   ├── Firefox/
│   ├── Utilities/
│   └── Educational/      # LEAP Games for blind children
├── Config/               # Pre-configured settings
│   ├── nvda-config/      # NVDA Vietnamese profile
│   └── firefox-profile/  # Accessibility-optimized Firefox
├── Scripts/              # PowerShell deployment automation
│   ├── 1-Install-All.ps1
│   ├── 2-Verify-Installation.ps1
│   ├── 3-Configure-NVDA.ps1
│   ├── 4-Prepare-Student-USB.ps1    # (Proposed) Set up a student USB drive
│   ├── 5-Configure-Loaner-Laptop.ps1 # (Proposed) Configure PC for USB backups
│   ├── backup-usb.ps1               # (Proposed) Scheduled USB-to-cloud sync
│   ├── Setup-Rclone-Auth.ps1        # (Proposed) One-time Google Drive auth
│   └── README.txt
├── Training/             # Vietnamese training materials
│   ├── NVDA-Basics-VN/
│   ├── Typing-Lessons-VN/
│   └── LibreOffice-VN/
├── Documentation/        # Guides and troubleshooting
│   ├── Deployment-Plan.md
│   ├── Troubleshooting-Guide-VN.docx
│   └── Quick-Start-Guide-VN.docx
└── Backup/              # Backup copies for redundancy
```

---

## Download URLs

All installers are downloaded automatically by `0-Download-Installers.ps1` from [GitHub Releases](https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/tag/installers-v1). See `Installers/README.md` for the full file list and original source URLs.

---

## Optional Software (Under Evaluation)

Not yet in deployment scripts — to be tested separately.

| Software | Purpose | Notes |
|----------|---------|-------|
| **Python 3.14** | Programming + IDLE editor | Works with NVDA, ~30MB |
| **Audacity 3.7** | Audio recording/editing | GPL-3.0, ~30MB |
| **VSCodium** | Open-source code editor | Best NVDA support of any IDE |
| **Quorum Studio** | IDE for blind students | Purpose-built accessible language |

---

## Deployment Timeline

See `Documentation/Deployment-Plan.md` for the full plan. Summary:

- **Pre-Deployment:** Build USB kit, test on one PC
- **Day 1 (6-8h):** Install software on all 10 PCs
- **Day 2 (6-8h):** Configure, test, train staff
- **Day 3 (4-6h):** Final testing and handoff

---

## Student Personal Files (Proposed)

Each student gets a labeled USB drive (`STU-001`, etc.) with pre-created folders (Documents, Audio, Schoolwork). Optional Google Drive backup via rclone syncs every 15 minutes if internet is available.

| Script | Purpose |
|--------|---------|
| `4-Prepare-Student-USB.ps1` | Format and label a student USB |
| `5-Configure-Loaner-Laptop.ps1` | Set up a lab PC for USB backups |
| `backup-usb.ps1` | Scheduled USB-to-Google-Drive sync |
| `Setup-Rclone-Auth.ps1` | One-time Google Drive authorization |

---

## License

This deployment kit uses 100% free and open-source software:
- Code and scripts: MIT License
- Documentation: CC BY-SA 4.0
- Individual software components: See respective licenses (GPL, MPL, LGPL)

---

## License

- Code and scripts: MIT License
- Documentation: CC BY-SA 4.0
- Individual software: See respective licenses (GPL, MPL, LGPL)

---

## Acknowledgments

- **NV Access** - NVDA screen reader
- **LibreOffice Community** - Free office suite
- **Mozilla Foundation** - Firefox browser
- **SciFY** - LEAP educational games for blind children

---

## Contact

**Project Lead:** Andrew Le - andrewle@monarchmissions.org

---

## Version History

- **v0.1** (February 2026): Initial deployment kit created

---

**Last Updated:** February 6, 2026
