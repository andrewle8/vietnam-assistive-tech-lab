# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Deployment:** April 2026 (1-3 days on-site)

This repo contains everything needed to deploy and remotely manage an assistive technology lab for blind children in Vietnam. Includes automated software installation, Tailscale VPN for remote access, pull-based auto-updates, and fleet health monitoring via Google Drive.

---

## Software Stack

| Component | License | Purpose |
|-----------|---------|---------|
| **NVDA 2025.3.3** | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | Free (non-commercial) | Vietnamese text-to-speech (SAPI5) |
| **Sao Mai Typing Tutor** | Free (non-commercial) | Vietnamese typing lessons with audio |
| **LibreOffice 26.2.0** | MPL-2.0 | Office suite |
| **Firefox 147** | MPL-2.0 | Accessible web browser |
| **VLC Media Player 3.0.23** | GPL-2.0 | Media playback |
| **Audacity 3.7** | GPL-3.0 | Audio recording/editing |
| **Quorum Studio** | BSD | Accessible IDE purpose-built for blind students |
| **UniKey 4.6** | GPL | Vietnamese Telex keyboard input |
| **Kiwix 2.5.1** | GPL-3.0 | Offline encyclopedia reader |
| **Vietnamese Wikipedia** | CC BY-SA | Offline Vietnamese encyclopedia (~550 MB) |
| **Vietnamese Wiktionary** | CC BY-SA | Offline Vietnamese dictionary via Kiwix |
| **Vietnamese Wikisource** | CC BY-SA | Offline Vietnamese literature via Kiwix |
| **Thorium Reader 3.3.0** | BSD-3 | EPUB/DAISY ebook reader for accessible reading |
| **SumatraPDF 3.5.2** | GPL-3.0 | Lightweight PDF reader for textbooks |
| **GoldenDict** | GPL-3.0 | Offline dictionary (Vietnamese-English, Vietnamese-Vietnamese) |
| **LEAP Games** | Apache-2.0 | Educational audio games for blind children |
| **Tailscale** | BSD-3 | Mesh VPN for remote management from the US |

**NVDA Add-ons:** VLC, Speech History, NVDA Remote, Focus Highlight, Audacity Access, Clock & Calendar, MathCAT — see [NVDA Add-on Store](https://addonstore.nvaccess.org/)

### Hardware
- 19x Dell Latitude 5420 (enterprise grade) upgraded to Windows 11
- 21x Audio-Technica ATH-M40x Headphones (trusted by blind professionals and schools)
- Student Personal USB Drives with unique identifiers labeled in Braille

> [Hardware Details](https://github.com/andrewle8/vietnam-assistive-tech-lab/blob/main/Documentation/Hardware.md)

---

## Quick Start

### 1. Download Installers

Smart downloads from vendor URLs, GitHub Releases, and Kiwix — no manual file hunting:

```powershell
.\Scripts\0-Download-Installers.ps1    # Downloads all installers
.\Scripts\Verify-Installers.ps1        # Validates files + SHA256 checksums
```

### 2. Set Up Tailscale

Before configuring PCs, set up your Tailscale account for remote management:

1. Create account at [tailscale.com](https://tailscale.com)
2. Generate a **non-expiring, reusable** pre-auth key (tag: `tag:vietnam-lab`)
3. Replace `tskey-auth-CHANGE_ME` in `Scripts/Install-Tailscale.ps1` with your key

### 3. Configure Laptops

Test on one PC first, then batch the remaining 18:

```powershell
# Run as Administrator on each PC
.\Scripts\Bootstrap-Laptop.ps1 -PCNumber 1   # Full setup: install, configure, Tailscale, scheduled tasks
.\Scripts\7-Audit.ps1                         # Verify machine matches manifest.json
```

### 4. Pre-Flight Validation

Run from your machine before traveling:

```powershell
.\Scripts\Pre-Deployment-Check.ps1    # Validates everything is ready for deployment
```

### 5. Remote Management (Post-Deployment)

From the US, monitor and manage all 19 PCs:

```powershell
.\Scripts\Get-FleetStatus.ps1             # Dashboard: heartbeats from Google Drive
.\Scripts\Check-Fleet.ps1 -UseTailscale   # Ping all PCs via Tailscale VPN
.\Scripts\Deploy-All.ps1 -UseTailscale    # Run commands on all PCs remotely
```

Software updates are automatic — edit `update-manifest.json`, push to GitHub, and all online PCs update within 24 hours.

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `0-Download-Installers.ps1` | Smart download from vendor URLs, GitHub, Kiwix |
| `0.5-Upgrade-Windows11.ps1` | Upgrade Windows 10 to 11 |
| `1-Install-All.ps1` | Install all software silently |
| `2-Verify-Installation.ps1` | Verify all software installed correctly |
| `3-Configure-NVDA.ps1` | Configure NVDA with Vietnamese voice |
| `4-Prepare-Student-USB.ps1` | Prepare student USB drives |
| `7-Audit.ps1` | Full audit against manifest.json (with JSON output) |
| `Bootstrap-Laptop.ps1` | End-to-end PC setup (calls 1-Install, 2-Verify, 3-Configure, Tailscale, scheduled tasks) |
| `Configure-Laptop.ps1` | Windows hardening, power settings, scheduled tasks |
| `Install-Tailscale.ps1` | Install Tailscale VPN and join tailnet |
| `Deploy-All.ps1` | Run scripts across fleet (local LAN or Tailscale) |
| `Check-Fleet.ps1` | Ping all PCs (local LAN or Tailscale) |
| `Get-FleetStatus.ps1` | Fleet dashboard from Google Drive heartbeats |
| `Get-FleetTailscaleIPs.ps1` | List Tailscale IPs from API |
| `Update-Agent.ps1` | Auto-update agent (runs as scheduled task on each PC) |
| `Report-FleetHealth.ps1` | Fleet health reporter (runs as scheduled task on each PC) |
| `Verify-Installers.ps1` | Validate installer files and SHA256 checksums |
| `Pre-Deployment-Check.ps1` | Pre-trip validation of entire deployment kit |
| `Setup-Rclone-Auth.ps1` | Configure rclone with Google Drive OAuth |
| `backup-usb.ps1` | Sync student USB drives to Google Drive via rclone |

---

## License

This deployment kit uses 100% free and open-source software:
- See respective licenses (GPL, MPL, LGPL)
---

## Acknowledgments

- **NV Access** - NVDA screen reader
- **Sao Mai Center** - NVDA Vietnamese modules and VNVoice TTS
- **LibreOffice Community** - Free office suite
- **Mozilla Foundation** - Firefox browser
- **SciFY** - LEAP educational games for blind children
- **Tailscale** - Mesh VPN for remote management

---

## Contact

**Project Lead:** Andrew Le - andrew@monarchmissions.org

---

## Version History

- **v0.2** (February 2026): Remote fleet management (Tailscale VPN, auto-update agent, fleet health monitoring), smart installer downloads, pre-deployment validation
- **v0.1** (February 2026): Initial deployment kit created
