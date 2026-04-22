# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind children's computer lab — Vietnam orphanages
**Deployment:** April 2026 (1–3 days on-site)

Scripts and config to deploy 19 Windows 11 laptops with NVDA, a Vietnamese TTS voice, 103 pre-loaded Vietnamese textbooks, and offline reference material.

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
| **UniKey 4.6** | GPL | Vietnamese Telex keyboard input |
| **Kiwix 2.5.1** | GPL-3.0 | Offline encyclopedia reader |
| **Vietnamese Wikipedia** | CC BY-SA | Offline Vietnamese encyclopedia (~550 MB) |
| **Vietnamese Wiktionary** | CC BY-SA | Offline Vietnamese dictionary via Kiwix |
| **GoldenDict** | GPL-3.0 | Offline dictionary (Vietnamese-English, Vietnamese-Vietnamese) |

**NVDA Add-ons:** VLC, Speech History, Focus Highlight, Audacity Access, Clock & Calendar, MathCAT, Training Keyboard Commands — see [NVDA Add-on Store](https://addonstore.nvaccess.org/)

### Hardware
- 19x Dell Latitude 5420, upgraded to Windows 11
- 21x Audio-Technica ATH-M40x headphones
- Student USB drives, labeled in print and Braille

See [Hardware.md](Documentation/Hardware.md) for full specs.

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

Downloads ~800 MB of installers from vendor URLs, GitHub Releases, and Kiwix.

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

### 3. Configure Laptops

Test on one PC first, then batch the remaining 18.

```powershell
.\Scripts\Bootstrap-Laptop.ps1
```

It will prompt:

```
Supply values for the following parameters:
PCNumber: _
```

Enter a number 1–19 for each laptop. The script handles everything: hostname, software install, NVDA config, Windows hardening, and scheduled tasks. Wi-Fi is configured manually on-site after deployment.

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

### 4. Pre-Flight Validation

Run from your machine before traveling:

```powershell
.\Scripts\Pre-Deployment-Check.ps1    # Validates everything is ready for deployment
```

### 5. Updates (Post-Deployment)

Software updates are automatic — edit `update-manifest.json`, push to GitHub, and all online PCs pull updates within 24 hours via the update agent.

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `0-Download-Installers.ps1` | Download installers from vendor URLs, GitHub, Kiwix |
| `0.5-Upgrade-Windows11.ps1` | Upgrade Windows 10 to 11 |
| `0.6-Download-LanguagePack.ps1` | Download Vietnamese language pack for offline install |
| `1-Install-All.ps1` | Install all software silently (including Microsoft Office) |
| `2-Verify-Installation.ps1` | Verify installs |
| `3-Configure-NVDA.ps1` | Configure NVDA with Vietnamese voice |
| `4-Prepare-Student-USB-Batch.ps1` | Batch-prepare student USB drives (parallel format, unplug-to-label) |
| `7-Audit.ps1` | Audit machine against manifest.json |
| `Bootstrap-Laptop.ps1` | Full per-PC setup (hostname, software, NVDA, hardening) |
| `Configure-Laptop.ps1` | Windows hardening, power, shortcuts, scheduled tasks (called by Bootstrap) |
| `Populate-ReadmateDB.ps1` | Import 103 Vietnamese textbooks into SM Readmate library |
| `Debloat-Windows.ps1` | Remove Windows bloatware (standalone re-run) |
| `Fix-Student-Account.ps1` | Repair per-user app paths and shortcuts for Student profile |
| `Uninstall-Legacy.ps1` | Remove obsolete fleet/Tailscale/rclone scripts from older deploys |
| `Update-Agent.ps1` | Daily scheduled task — pulls update-manifest.json from GitHub |
| `Verify-Installers.ps1` | Validate installer files and SHA256 checksums |
| `Pre-Deployment-Check.ps1` | Pre-trip validation of the deployment kit |

---

## License

Free and open-source software (GPL/MPL/LGPL) plus Microsoft Office 365 under non-profit licensing. See each component's license for details.

## Acknowledgments

NV Access (NVDA), Sao Mai Center (Vietnamese modules, VNVoice TTS, Readmate, SMTT), Microsoft (Office 365 non-profit), Mozilla (Firefox).

## Contact

Andrew Le — [GitHub Issues](https://github.com/andrewle8/vietnam-assistive-tech-lab/issues)
