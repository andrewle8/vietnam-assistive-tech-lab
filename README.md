# Vietnam Assistive Technology Lab Deployment Kit

**Project:** Blind children's computer lab — Vietnam orphanages
**Deployment:** April 2026 (~3 days on-site)

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

Updates deferred for 365 days. ~Windows 11 26H2 release. Re-evaluation for update in one year.


Updates (Post-Deployment)

Software updates are automatic — push update-manifest.json and all online PCs pull updates within 24 hours via the update agent.

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
