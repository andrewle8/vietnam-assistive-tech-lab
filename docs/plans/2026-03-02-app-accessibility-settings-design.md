# App Accessibility Settings for Blind Users

**Date:** 2026-03-02
**Status:** Approved

## Goal

Pre-configure all installed applications with optimal settings for blind children using NVDA screen readers on Windows 11 laptops.

## Approach

Config file copy pattern — same as existing NVDA (nvda.ini) and Firefox (policies.json) deployment. Each app gets a pre-built config file in `Config/`, copied to the correct Windows path during `Configure-Laptop.ps1`.

## New Config Files

```
Config/
  vlc-config/vlcrc
  audacity-config/audacity.cfg
  sumatrapdf-config/SumatraPDF-settings.txt
  kiwix-config/Kiwix-desktop.conf
  goldendict-config/config             (XML, no extension)
  goldendict-config/styles/article-style.css
```

## Updated Config Files

- `Config/firefox-profile/policies.json` — add ~30 accessibility preferences

## Deploy Targets (per app)

| App | Source | Target Path |
|-----|--------|-------------|
| Firefox | `Config/firefox-profile/policies.json` | `C:\Program Files\Mozilla Firefox\distribution\policies.json` |
| VLC | `Config/vlc-config/vlcrc` | `C:\Users\Student\AppData\Roaming\vlc\vlcrc` |
| Audacity | `Config/audacity-config/audacity.cfg` | `C:\Users\Student\AppData\Roaming\audacity\audacity.cfg` |
| SumatraPDF | `Config/sumatrapdf-config/SumatraPDF-settings.txt` | `C:\Users\Student\AppData\Local\SumatraPDF\SumatraPDF-settings.txt` |
| Kiwix | `Config/kiwix-config/Kiwix-desktop.conf` | `C:\Users\Student\AppData\Local\kiwix-desktop\Kiwix-desktop.conf` |
| GoldenDict | `Config/goldendict-config/config` | `C:\Users\Student\AppData\Roaming\GoldenDict\config` |
| GoldenDict CSS | `Config/goldendict-config/styles/article-style.css` | `C:\Users\Student\AppData\Roaming\GoldenDict\styles\article-style.css` |

## Key Settings Per App

### Firefox (policies.json additions)

- `accessibility.force_disabled = 0` (locked) — prevent AT from being disabled
- `accessibility.browsewithcaret = true` — caret browsing for arrow-key page navigation
- `accessibility.tabfocus = 7` — Tab reaches links + form fields + text
- `media.autoplay.default = 5` — block all autoplay
- `browser.link.open_newwindow.restriction = 0` — force popups into tabs
- `signon.rememberSignons = false` — no password prompts (shared machines)
- `browser.download.useDownloadDir = true` — auto-save downloads without dialog
- `ui.prefersReducedMotion = 1` — reduce animations
- `privacy.trackingprotection.enabled = true` — block trackers
- `dom.popup_maximum = 2` — limit popup storms
- Remove `toolkit.telemetry.enabled` (outside allowed prefix list; telemetry already blocked by `datareporting.policy.dataSubmissionEnabled`)

### VLC (vlcrc)

- `video=0` — audio-only mode
- `audio-visual=none` — no visualizations
- `qt-privacy-ask=0` — skip first-run dialog
- `qt-name-in-title=1` — NVDA reads track from window title
- `qt-system-tray=0` — no hiding to tray
- `qt-max-volume=100` — volume safety cap
- `one-instance=1` — enqueue files instead of new windows
- `qt-recentplay=0` — no recent files (privacy on shared machines)
- `qt-notification=1` — track change notifications for NVDA
- `metadata-network-access=0` — no network fetches

### Audacity (audacity.cfg)

- `Host=MME` — avoids WASAPI stealing audio from NVDA
- `ShowSplashScreen=0` — no splash dialog
- `BeepOnCompletion=1` — audio feedback on long operations
- `CircularTrackNavigation=1` — Tab wraps between tracks
- `SelectAllOnNone=1` — auto-select all when nothing selected
- `RecordChannels=1` — mono default
- `Maximized=1` — start maximized

### SumatraPDF (SumatraPDF-settings.txt)

- `DefaultDisplayMode = continuous` — continuous scroll
- `DefaultZoom = fit width` — full-width layout
- `UseSysColors = true` — honor Windows high-contrast
- `ShowToc = true` — table of contents sidebar
- `EbookUI.FontSize = 16` — larger EPUB font

### Kiwix (Kiwix-desktop.conf)

- `view/zoomFactor = 1.3` — 130% default zoom
- `reopenTab = true` — restore last tab on launch

### GoldenDict (config XML + CSS)

- `zoomFactor = 1.5` — 150% article zoom
- `wordsZoomLevel = 2` — larger word list
- `scanPopupUseUIAutomation = 1` — UI Automation for NVDA
- Article CSS: 18px font, 1.6 line-height

## Excluded Apps

- **Thorium Reader**: Config is version-sensitive Redux JSON. "Enhance Screen Reader Experience" checkbox must be enabled manually. Document in training materials.
- **Quorum Studio**: Programming IDE configured by students during learning.
- **UniKey**: Already installed + autostart. No additional config needed.

## Script Changes

Add Steps 30-34 to `Configure-Laptop.ps1`:
- Step 30: Deploy VLC config
- Step 31: Deploy Audacity config
- Step 32: Deploy SumatraPDF config
- Step 33: Deploy Kiwix config
- Step 34: Deploy GoldenDict config + CSS

Each step: create target dir if needed, copy file, log result. Target the Student user profile with fallback to current user.

Firefox policies.json update requires no script change (Step 13 already copies it).
