# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Deployment:** April 2026 (1-3 days on-site)
**Equipment:** 10 Windows 11 PCs / Laptops (x86-64)
**Partner:** Sao Mai Center for the Blind

---

## Project Overview

This repository contains everything needed to deploy a fully **offline, open-source** assistive technology lab for blind children in Vietnam.

### Key Features
- 100% Free/Open Source software stack
- Fully offline operation (no internet required)
- Vietnamese language support (interface + TTS)
- Automated PowerShell deployment scripts
- Complete documentation in Vietnamese and English
- Partnership with Sao Mai Center

---

## What's Included
-  Note: If office is provided with Windows 11 PCs/Laptops, omit LibreOffice

### Software Stack (All Free/Open Source)
| Component | License | Purpose |
|-----------|---------|---------|
| **NVDA 2025.3.2** | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | Free (non-commercial) | Vietnamese text-to-speech (SAPI5) |
| **Sao Mai Typing Tutor** | Free | Vietnamese typing lessons with audio |
| **LibreOffice 26.2.0** | MPL-2.0 | Office suite (Word/Excel alternative) |
| **Firefox 147** | MPL-2.0 | Accessible web browser |
| **VLC Media Player 3.0.23** | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | GPL-2.0 | VLC accessibility enhancement for NVDA |
| **LEAP Games** | Apache-2.0 | Educational audio games for blind children |

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

All installers are hosted on GitHub Releases and downloaded automatically by `0-Download-Installers.ps1`. No manual downloads required.

**GitHub Releases:** https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/tag/installers-v1

For reference, the original software sources:

1. **NVDA:** https://www.nvaccess.org/download/
2. **Sao Mai VNVoice:** https://saomaicenter.org/en/downloads
3. **Sao Mai Typing Tutor:** https://saomaicenter.org/en/downloads/vietnamese-talking-software/sao-mai-typing-tutor-smtt
4. **LibreOffice:** https://www.libreoffice.org/download/download/
5. **Firefox:** https://www.mozilla.org/en-US/firefox/
6. **VLC:** https://www.videolan.org/vlc/
7. **VLC NVDA Add-on:** https://addons.nvda-project.org/
8. **LEAP Games:** https://www.gamesfortheblind.org/ (Tic-Tac-Toe, Tennis, Curve)

---

## Deployment Timeline

### Pre-Deployment
- Build USB deployment kit
- Test scripts on one PC
- Coordinate with Sao Mai Center
- Prepare all documentation

### Day 1 (6-8 hours): Installation
- Physical setup and PC arrangement
- Run automated deployment scripts
- Verify all 10 stations

### Day 2 (6-8 hours): Configuration & Testing
- Fix any issues from Day 1
- Deploy training materials
- Train staff on troubleshooting
- Pilot test with students

### Day 3 (4-6 hours): Handoff
- Final testing and validation
- Staff training on maintenance
- Documentation handoff
- Schedule follow-up support

---


## Student Personal Files (Proposed Solution)

Since the PCs are shared and students cannot keep them, we need a way for each student to save and access their personal files across sessions. The current proposed approach uses **personal USB drives**:

### How It Works
1. Each student receives a USB drive labeled with a unique ID (e.g., `STU-001`, `STU-002`)
2. The USB contains pre-created folders: **Documents**, **Audio**, and **Schoolwork**
3. Students plug in their USB when they check out a PC, and save all work to the USB
4. When done, they take their USB with them — their files go wherever they go

### Cloud Backup (Optional, requires internet)
If the lab has internet access, the laptops can automatically back up student USBs to Google Drive every 15 minutes using rclone. This protects against lost or damaged USB drives. Backups are organized per student under `VietnamLabBackups/STU-###/` on Google Drive.

### Scripts
| Script | Purpose |
|--------|---------|
| `4-Prepare-Student-USB.ps1` | Formats and labels a USB drive for one student (sets volume label, creates folders, writes a hidden `.student-id` file) |
| `5-Configure-Loaner-Laptop.ps1` | Configures a lab PC for USB backups — deploys rclone, creates a scheduled backup task, sets AutoPlay to open folders, adds a "My USB" desktop shortcut |
| `backup-usb.ps1` | Runs on a schedule to sync student USB contents to Google Drive via rclone |
| `Setup-Rclone-Auth.ps1` | One-time setup to authorize rclone with a Google Drive account |

> **Note:** This approach is still under evaluation. Alternatives (e.g., per-student Windows profiles, a shared network folder) may be considered depending on the on-site environment and feedback from Sao Mai Center.

---

## Partnership with Sao Mai Center
- Training materials in Vietnamese

---

## Language Support

All materials available in:
- **Vietnamese** (primary)
- **English** (backup/technical reference)

---

## License

This deployment kit uses 100% free and open-source software:
- Code and scripts: MIT License
- Documentation: CC BY-SA 4.0
- Individual software components: See respective licenses (GPL, MPL, LGPL)

---

## Acknowledgments

- **Sao Mai Center for the Blind** - Vietnamese TTS, typing tutor, and ongoing support
- **NV Access** - NVDA screen reader
- **LibreOffice Community** - Free office suite
- **Mozilla Foundation** - Firefox browser
- **SciFY** - LEAP educational games for blind children

---

## Contact

For questions about this deployment:
- **Project Lead:** Andrew Le - andrewle@monarchmissions.org
- **Sao Mai Center:** https://saomaicenter.org/en/contact

---

## Version History

- **v0.1** (February 2026): Initial deployment kit created

---

**Last Updated:** February 5, 2026
**Status:** Ready for deployment preparation
