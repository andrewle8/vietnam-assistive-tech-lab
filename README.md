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
| **Firefox 149** | MPL-2.0 | Accessible web browser |
| **VLC Media Player 3.0.23** | GPL-2.0 | Media playback |
| **Audacity 3.7** | GPL-3.0 | Audio recording/editing |
| **UniKey 4.6** | GPL | Vietnamese Telex keyboard input |
| **Kiwix 2.5.1 + kiwix-tools 3.8.1** | GPL-3.0 | Offline encyclopedia reader (kiwix-desktop for sighted users; kiwix-serve for the Firefox-fronted accessible path) |
| **Vietnamese Wikipedia** | CC BY-SA | Offline Vietnamese encyclopedia (~550 MB), served on `localhost:21808` |
| **Vietnamese Wiktionary** | CC BY-SA | Offline Vietnamese dictionary via Kiwix |
| **SilverDict 1.3.1** | GPL-3.0 | Flask-based StarDict server for the NVDA-accessible dictionary path; serves on `localhost:2628`, viewed in Firefox |
| **GoldenDict 1.5.1** | GPL-3.0 | Offline dictionary with bundled Vietnamese↔English StarDicts; sighted-user UI (Start Menu only — see Accessibility Architecture below for why) |

**NVDA Add-ons:** VLC, Speech History, Focus Highlight, Audacity Access, Clock & Calendar, MathCAT, Training Keyboard Commands — see [NVDA Add-on Store](https://addonstore.nvaccess.org/)

### Hardware
- 19x Dell Latitude 5420, upgraded to Windows 11
- 21x Audio-Technica ATH-M40x headphones
- Student USB drives, labeled in print and Braille

See [Hardware.md](Documentation/Hardware.md) for full specs.

---

## Accessibility Architecture: localhost HTTP + Firefox

The lab uses a deliberate architectural pattern to work around a long-standing screen-reader limitation. It's the load-bearing design decision behind the whole deployment, so it's worth describing.

### The problem

NVDA cannot browse-mode any **QtWebEngine** surface — the article view in GoldenDict, kiwix-desktop's reader, goldendict-ng, and any other Qt-based content app. NVDA's browse-mode whitelist (in `browseMode.py`) is hard-keyed on Firefox / Chrome / Edge / Internet Explorer process names. Tracked as [NVDA issue #10838](https://github.com/nvaccess/nvda/issues/10838) — **closed as Abandoned 2024-07-02**, no upstream fix is planned. The QtWebEngine accessibility tree is buried inside Chromium under Qt's UIA wrapper and is unreachable from NVDA's process.

For a deployment serving blind students, that means the off-the-shelf "open the desktop reader" experience is unusable: NVDA+Space does nothing, browse-mode keys (H, K, Tab, ↓) don't navigate, and the article surface reads as an unlabeled control.

### The pattern

For any application whose content can be served over HTTP locally, we run that server as a Student-logon scheduled task and front it with Firefox. **NVDA in Firefox is bulletproof** — full browse-mode, headings list (NVDA+F7), arrow-key reading, all the muscle memory students already have from web pages.

```
Student logs in
   ↓
Scheduled task (KiwixServe / SilverDictServe) fires
   ↓
wscript.exe runs hidden VBS launcher (no console flicker)
   ↓
Server binary listens on 127.0.0.1:<port>
   ↓
Student clicks desktop icon ("Wikipedia" / "Từ Điển")
   ↓
Firefox opens http://localhost:<port>/...
   ↓
NVDA reads everything natively
```

Three integrations currently use this pattern:

| Surface | Server | Port | Desktop shortcut | Status |
|---|---|---|---|---|
| **Wikipedia + Wiktionary** | `kiwix-serve.exe` (kiwix-tools) | 21808 | `Wikipedia.lnk` → Firefox at `/` | shipped |
| **Vietnamese ↔ English dictionary** | `SilverDict` (Flask + bundled Python) | 2628 | `Từ Điển.lnk` → Firefox at `/dict.html` | shipped |
| **GoldenDict** (no HTTP API) | n/a — sighted Start Menu only | n/a | n/a (Start Menu) | sighted-only |

The original Qt apps (kiwix-desktop, GoldenDict) stay installed and reachable from the Start Menu so sighted lab assistants and family members can use the familiar desktop UI. **Nobody loses anything; blind students get a parallel path that actually works.**

### Why this is robust

1. **Set-and-forget.** Each integration is a hidden VBS launcher + scheduled task at logon + idempotent patch script. No daemon to babysit, no sysadmin needed post-deploy.
2. **Two-tier by design.** Sighted users keep the native Qt UI; blind students get the Firefox-rendered version. The architecture acknowledges that the lab serves both populations.
3. **Idempotent USB-walkup patches.** Every Firefox-fronted integration ships with a `Scripts/patches/Fix-<App>.ps1` that brings any already-deployed laptop up to current state when an installer USB is plugged in. Wrapped together by `Apply-All-Field-Patches.ps1` for one-pass field rollouts.
4. **Pattern, not one-off.** Wikipedia came first (the original insight). Dictionaries followed. Any future app with an HTTP/headless mode plugs in by copying the same shape: bundle in `Installers/`, NVDA-friendly HTML overrides in `Config/<app>-config/`, scheduled task + VBS launcher + Firefox shortcut, idempotent patch script under `Scripts/patches/`.

### Custom NVDA-friendly HTML

For SilverDict specifically, three of the bundle's HTML templates are replaced with semantic-HTML versions tuned for NVDA:

- `dict.html` — entry page, search box with `autofocus` and `lang="vi"` for the Vietnamese voice
- `articles_standalone.html` — results page with `<h1>{{key}}</h1>`, `<h2>` per dictionary heading, search box at the top so back-to-back lookups never leave the page
- `suggestions.html` — "không tìm thấy" page with the same search box plus suggestion `<a>` links

All three are pure HTML with one tiny `<script>` for the form-submit handler. NVDA's `H` key navigates between dictionary headings; `K` walks suggestion links; `Tab` returns to the search box. Reading speed is comparable to a native screen-reader-optimized desktop dictionary, with none of the QtWebEngine wall.

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
| `patches/Apply-All-Field-Patches.ps1` | One-shot field patch wrapper for already-deployed laptops (self-elevates, runs Kiwix/GoldenDict/Readmate/STU-resolver/NVDA refresh in sequence with transcript log) |
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
