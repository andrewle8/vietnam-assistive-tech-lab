# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Deployment:** April 2026 (1-3 days on-site)
**Equipment:** 10 Windows 11 PCs + 10 Orbit Reader 20 Braille Displays
**Partner:** Sao Mai Center for the Blind

---

## Project Overview

This repository contains everything needed to deploy a fully **offline, open-source** assistive technology lab for blind children in Vietnam. The lab enables students to learn computing through **simultaneous speech and braille output** from day one.

### Key Features
- 100% Free/Open Source software stack
- Fully offline operation (no internet required)
- Vietnamese language support (interface + TTS)
- Automated PowerShell deployment scripts
- Complete documentation in Vietnamese and English
- Partnership with Sao Mai Center for ongoing support

---

## What's Included

### Software Stack (All Free/Open Source)
| Component | License | Purpose |
|-----------|---------|---------|
| **NVDA 2025.3.2** | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | Free (non-commercial) | Vietnamese text-to-speech (SAPI5) |
| **Sao Mai Typing Tutor** | Free | Vietnamese typing lessons with audio |
| **LibreOffice 24.8 LTS** | MPL-2.0 | Office suite (Word/Excel alternative) |
| **Firefox ESR 128** | MPL-2.0 | Accessible web browser |
| **VLC Media Player** | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | GPL-2.0 | VLC accessibility enhancement for NVDA |
| **LEAP Games** | Apache-2.0 | Educational audio games for blind children |

> **Note:** 7-Zip removed - Windows 11 (24H2) has built-in support for ZIP, 7z, RAR, TAR, and other archive formats.

**Total Software Cost: $0**

### Hardware (Already Purchased)
- 10x Windows 11 PCs
- 10x Orbit Reader 20 Braille Displays
- Headphones, USB cables, accessories

---

## Quick Start

### For Deployment (On-Site in Vietnam)

1. **Download all installers** (BEFORE traveling - run on your main PC)
   ```powershell
   cd F:\Vietnam-Lab-Kit\Scripts
   .\0-Download-Installers.ps1
   ```
   Then manually download the 2 Sao Mai programs (see script output)

2. **Copy entire folder to USB drive** (8GB+)

3. **Run deployment scripts** on each PC:
   ```powershell
   # Run as Administrator
   cd X:\Scripts
   .\1-Install-All.ps1
   .\2-Verify-Installation.ps1
   .\3-Configure-NVDA.ps1
   ```
4. **Connect Orbit Reader 20** devices via USB
5. **Test complete workflow** on each station

### For Contributors

```bash
git clone https://github.com/YourUsername/vietnam-assistive-tech-lab.git
cd vietnam-assistive-tech-lab
```

**Note:** Installer files are NOT included in git (too large). Download separately from [Software Sources](#download-urls).

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

**Download these installers BEFORE traveling to Vietnam:**

1. **NVDA:** https://www.nvaccess.org/download/
   - Get "Installer" version + "Portable" backup

2. **Sao Mai VNVoice:** https://saomaicenter.org/en/downloads
   - Vietnamese TTS with Minh Du/Mai Dung voices

3. **Sao Mai Typing Tutor:** https://saomaicenter.org/en/downloads/vietnamese-talking-software/sao-mai-typing-tutor-smtt

4. **LibreOffice:** https://www.libreoffice.org/download/download/
   - Select "Windows x86-64 (MSI)"

5. **Firefox ESR:** https://www.mozilla.org/en-US/firefox/enterprise/
   - Download "Windows 64-bit MSI" installer

6. **VLC:** https://www.videolan.org/vlc/

7. **VLC NVDA Add-on:** https://addons.nvda-project.org/
   - Search for "VLC" or download from NVDA add-ons store
   - Place `.nvda-addon` file in `Installers/NVDA/addons/`

8. **LEAP Games:** https://www.gamesfortheblind.org/
   - Download Windows 64-bit versions of Tic-Tac-Toe, Tennis, and Curve
   - Place `.exe` files in `Installers/Educational/`

---

## Deployment Timeline

### Pre-Deployment (2-3 weeks before travel)
- Build USB deployment kit
- Test scripts on one PC
- Coordinate with Sao Mai Center
- Prepare all documentation
- Update all Orbit Reader firmware

### Day 1 (6-8 hours): Installation
- Physical setup and PC arrangement
- Run automated deployment scripts
- Connect and configure Orbit Readers
- Verify all 10 stations

### Day 2 (6-8 hours): Configuration & Testing
- Fix any issues from Day 1
- Deploy training materials
- Train Sao Mai staff on troubleshooting
- Pilot test with students

### Day 3 (4-6 hours): Handoff
- Final testing and validation
- Staff training on maintenance
- Documentation handoff
- Schedule follow-up support

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
- **APH (American Printing House for the Blind)** - Orbit Reader 20
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
