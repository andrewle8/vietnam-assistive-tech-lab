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
| **SM Readmate** | Free (non-commercial) | Accessible e-book reader (connects to sachtiepcan.vn library) |
| **Microsoft Office 365** | Non-profit license | Office suite (Word, Excel, PowerPoint, Outlook) |
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

> **All scripts must be run from an Administrator PowerShell window.** Windows 11 does not have a "Run as Administrator" option in the right-click menu for `.ps1` files, so you must use the command line.

**One-time setup:**

1. Open PowerShell as Administrator
   (Start > type "PowerShell" > right-click > **Run as Administrator**)
2. Allow scripts to run:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
   ```
3. Navigate to the project folder:
   ```powershell
   cd C:\path\to\vietnam-assistive-tech-lab
   ```

From here, run all scripts in this PowerShell window.

### 1. Download Installers

```powershell
.\Scripts\0-Download-Installers.ps1
```

Downloads all installers (~800 MB) from vendor URLs, GitHub Releases, and Kiwix automatically.

Then validate files and SHA256 checksums:

```powershell
.\Scripts\Verify-Installers.ps1
```

Optionally, pre-download the Vietnamese language pack for offline install (without this, `Bootstrap-Laptop.ps1` will download it from the internet):

```powershell
.\Scripts\0.6-Download-LanguagePack.ps1
```

### 2. Download Windows 11 ISO (if upgrading from Windows 10)

The Dell Latitude 5420s may ship with Windows 10. To upgrade:

1. Download the **Windows 11 (multi-edition ISO for x64 devices)** from [microsoft.com/software-download/windows11](https://www.microsoft.com/en-us/software-download/windows11)
2. Place the ISO in `Installers\Windows\` (create the folder if needed) — expected filename: `Win11_25H2_English_x64.iso`
3. Run the upgrade script on each PC that needs it:
   ```powershell
   .\Scripts\0.5-Upgrade-Windows11.ps1
   ```

> **Note:** The Arm64 ISO is not needed — Dell Latitude 5420 is x64.

### 3. Set Up Tailscale

Before configuring PCs, set up your Tailscale account for remote management:

1. Create account at [tailscale.com](https://tailscale.com)
2. In Access Controls, add `"tag:vietnam-lab"` to `tagOwners` under your admin group
3. Generate a **reusable** pre-auth key (90-day expiry is fine — only needed during setup):
   - **Reusable:** checked
   - **Ephemeral:** unchecked
   - **Tags:** `tag:vietnam-lab` (this disables node key expiry, so devices stay connected permanently)
4. Replace `tskey-auth-CHANGE_ME` in `Scripts/Install-Tailscale.ps1` with your key

### 4. Configure Laptops

Test on one PC first, then batch the remaining 18.

```powershell
.\Scripts\Bootstrap-Laptop.ps1
```

It will prompt:

```
Supply values for the following parameters:
PCNumber: _
```

Enter a number 1–19 for each laptop. The script handles everything: hostname, Wi-Fi, software install, NVDA config, Windows hardening, Tailscale, and scheduled tasks.

**Microsoft Office setup:**

Before running Bootstrap, download the Office Deployment Tool and Office files:

1. Download the [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117) and extract `setup.exe` to `Installers\MSOffice\`
2. From that folder, run: `.\setup.exe /download configuration.xml`
3. This downloads ~2 GB of Office installer files into `Installers\MSOffice\`

The Bootstrap script will install Office automatically using the included `configuration.xml` (Office 365 ProPlus, en-us + vi-vn). After deployment, activate with your non-profit license.

After it finishes, verify the machine matches `manifest.json`:

```powershell
.\Scripts\7-Audit.ps1
```

### 5. Pre-Flight Validation

Run from your machine before traveling:

```powershell
.\Scripts\Pre-Deployment-Check.ps1    # Validates everything is ready for deployment
```

### 6. Remote Management (Post-Deployment)

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
| `0.6-Download-LanguagePack.ps1` | Download Vietnamese language pack for offline install |
| `1-Install-All.ps1` | Install all software silently (including Microsoft Office) |
| `2-Verify-Installation.ps1` | Verify all software installed correctly |
| `3-Configure-NVDA.ps1` | Configure NVDA with Vietnamese voice |
| `4-Prepare-Student-USB.ps1` | Prepare student USB drives |
| `7-Audit.ps1` | Full audit against manifest.json (with JSON output) |
| `Bootstrap-Laptop.ps1` | Full PC setup (hostname, Wi-Fi, software, NVDA, hardening, Tailscale) |
| `Configure-Laptop.ps1` | Windows hardening, rclone, power settings, desktop shortcuts, scheduled tasks (called by Bootstrap) |
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

This deployment kit uses free and open-source software where possible, plus Microsoft Office 365 under non-profit licensing.
- See respective licenses (GPL, MPL, LGPL)
---

## Acknowledgments

- **NV Access** - NVDA screen reader
- **Sao Mai Center** - NVDA Vietnamese modules and VNVoice TTS
- **Microsoft** - Office 365 (non-profit licensing)
- **Mozilla Foundation** - Firefox browser
- **SciFY** - LEAP educational games for blind children
- **Tailscale** - Mesh VPN for remote management

---

## Contact

**Project Lead:** Andrew Le - REDACTED

---

## Version History

- **v0.2** (February 2026): Remote fleet management (Tailscale VPN, auto-update agent, fleet health monitoring), smart installer downloads, pre-deployment validation
- **v0.1** (February 2026): Initial deployment kit created
