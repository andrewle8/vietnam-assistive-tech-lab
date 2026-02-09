# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Deployment:** April 2026 (1-3 days on-site)

---

## Project Overview

This repository contains everything needed to deploy a fully offline assistive technology lab for blind children in Vietnam.

---

## Software Stack (All Free/Open Source)

| Component | License | Purpose |
|-----------|---------|---------|
| **NVDA 2025.3.2** | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | Free (non-commercial) | Vietnamese text-to-speech (SAPI5) |
| **Sao Mai Typing Tutor** | Free (non-commercial) | Vietnamese typing lessons with audio |
| **LibreOffice 26.2.0** | MPL-2.0 | Office suite |
| **Firefox 147** | MPL-2.0 | Accessible web browser |
| **VLC Media Player 3.0.23** | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | GPL-2.0 | VLC accessibility enhancement for NVDA |
| **Access8Math NVDA Add-on** | GPL-3.0 | Math content reading/writing via speech |
| **LEAP Games** | Apache-2.0 | Educational audio games for blind children |

> **NVDA Add-ons:** [NVDA Add-on Store](https://addonstore.nvaccess.org/)

### Hardware
- 10x Dell Latitude 5420 (enterprise grade) upgraded to Windows 11
- 10x Audio Technica ATH-M40x Headphones (trusted by blind professionals and schools)
- Student Personal USB Drives with unique identifiers labeled in braiile
  
> [Hardware Details](https://github.com/andrewle8/vietnam-assistive-tech-lab/blob/main/Documentation/Hardware.md)

---

## Quick Start

### For Deployment

1. **Download all installers** (fully automated from GitHub Releases)
   ```powershell
   cd F:\Vietnam-Lab-Kit\Scripts
   .\0-Download-Installers.ps1
   ```

2. **Copy entire folder to USB drive**

3. **Run deployment scripts** on each PC:
   ```powershell
   # Run as Administrator
   cd X:\Scripts
   .\1-Install-All.ps1
   .\2-Verify-Installation.ps1
   .\3-Configure-NVDA.ps1
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

## License

This deployment kit uses 100% free and open-source software:
- See respective licenses (GPL, MPL, LGPL)
---

## Acknowledgments

- **NV Access** - NVDA screen reader
- **Sao Mai Center** - NVDA Vietnamese modules
- **LibreOffice Community** - Free office suite
- **Mozilla Foundation** - Firefox browser
- **SciFY** - LEAP educational games for blind children

---

## Contact

**Project Lead:** Andrew Le - andrewle@monarchmissions.org

---

## Version History

- **v0.1** (February 2026): Initial deployment kit created
