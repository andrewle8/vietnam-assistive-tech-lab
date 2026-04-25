# Lab Reference Card

**Vietnam Assistive Technology Lab**
**Deployed:** April 2026

---

## What's Installed (Every PC)

| Software | What It Does |
|----------|-------------|
| **NVDA** | Screen reader — speaks everything on screen in Vietnamese |
| **Microsoft An (neural)** | Primary Vietnamese TTS for NVDA + Readmate (bilingual, offline) |
| **Sao Mai VNVoice** | Additional Vietnamese SAPI voices (Thanh Vi Southern, Minh Du Northern, etc.) |
| **Sao Mai Readmate** | Accessible EPUB reader for Vietnamese textbooks (103 books pre-loaded) |
| **Sao Mai Typing Tutor** | Typing lessons with audio feedback |
| **Microsoft Office** | Word, Excel, PowerPoint, Outlook (non-profit license) |
| **Firefox** | Web browser |
| **VLC** | Music and video player |
| **GoldenDict** | Offline Vietnamese-English dictionary (Từ Điển) |
| **Kiwix** | Offline Vietnamese Wikipedia and Wiktionary |

All software is **free** and works **offline** (no internet needed).

---

## PC and USB Labels

- PCs are labeled **PC-1** through **PC-19**
- Student USB drives are labeled **STU-001**, **STU-002**, etc.
- Each USB has folders: Documents, Audio, Schoolwork

---

## If NVDA Stops Talking

Press **Ctrl + Alt + N** to restart NVDA.

NVDA starts automatically when the PC turns on. If it doesn't, look for the NVDA icon on the desktop or in the Start menu.

### Restore NVDA Settings

If NVDA stops speaking Vietnamese or has wrong settings, robocopy the backup from `C:\LabTools\nvda-backup\` into the Student profile's NVDA config folder (typically `C:\Users\Student\AppData\Roaming\nvda\`). Must be run from an Admin session since Step 16 writes the backup machine-wide. For a full redeploy, re-run `Configure-Laptop.ps1` instead.

### Backup: Windows Narrator

The Narrator keyboard shortcut (Win+Ctrl+Enter) is **disabled** to prevent accidental activation alongside NVDA. If NVDA completely fails and cannot be restarted, Narrator can be re-enabled through Settings > Accessibility > Narrator.

---

## NVDA Learning Tools

These features help beginners learn NVDA and are useful for training sessions:

- **Input Help Mode** (NVDA+1): Learning mode -- press any key to hear what it does. Press NVDA+1 again to exit. This is the #1 beginner learning tool.
- **Screen Curtain** (NVDA+Shift+S): Turns screen black for privacy and battery savings. Press again to turn screen back on.
- **Adjust Speech Speed** (NVDA+Ctrl+Up/Down arrows): Speed up or slow down NVDA's voice.

---

## Essential NVDA Shortcuts

> **Note:** "NVDA key" = CapsLock or Insert (laptop layout — either works). Ctrl+Alt+N launches NVDA if it stops.

| Shortcut | What It Does |
|----------|-------------|
| **NVDA+1** | Input Help (learning mode) |
| **NVDA+T** | Read window title |
| **NVDA+A** | Say all (read from cursor) |
| **NVDA+L** | Read current line |
| **Tab / Shift+Tab** | Navigate controls |
| **NVDA+Space** | Toggle forms/browse mode |
| **Arrow keys** | Navigate text |
| **Ctrl** | Stop speech |
| **NVDA+S** | Cycle speech modes (talk/beep/off) |
| **NVDA+Ctrl+Up/Down** | Speech rate |
| **NVDA+Ctrl+F** | Find text in document |
| **NVDA+F7** | Elements list (links, headings) |
| **NVDA+Q** | Quit NVDA |

---

## Low-Vision Mode

Some students may have partial vision. These tools are pre-configured on every laptop:

| Shortcut | What It Does |
|----------|-------------|
| **Win + Plus (+)** | Launch Windows Magnifier (starts at 200% zoom, full-screen) |
| **Win + Minus (-)** | Zoom out while Magnifier is running |
| **Win + Esc** | Close Magnifier |
| **Win + Left Alt + Print Screen** | Toggle High Contrast mode |

Magnifier and NVDA can run at the same time for students with some remaining vision who also benefit from speech output.

---

## Vietnamese Typing (UniKey)

**Vietnamese typing is UniKey-only by design.** UniKey's **Ctrl + Shift** toggles Vietnamese ↔ English (watch the tray: V = Vietnamese, E = English). The Windows built-in Vietnamese (Telex) keyboard is still installed as a fallback, but Windows' own language-switch hotkeys (Alt+Shift, Ctrl+Shift) are disabled so they don't desync from UniKey during typing. If a staff member ever needs the Windows IME, reach it via Win+Space or Settings → Time & language → Typing → Advanced keyboard settings.

Windows UI is set to Vietnamese permanently. If an admin needs English temporarily, change it via **Settings → Time & language → Language & region**, then sign out/in.

---

## Quick Health Check

To check if everything is working on a PC, run this script:

1. Open PowerShell as Administrator
   (Start > type "PowerShell" > right-click > **Run as Administrator**)
2. Run once (first time only): `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass`
3. Navigate to the project folder: `cd C:\path\to\vietnam-assistive-tech-lab`
4. Run: `.\Scripts\7-Audit.ps1`

The script checks all software, Windows settings, NVDA config, and remote management. Shows green (OK), yellow (warning), or red (problem).

---

## Contact

**Andrew Le** — [Contact via GitHub Issues](https://github.com/andrewle8/vietnam-assistive-tech-lab/issues)

For detailed troubleshooting, see the **Documentation/** folder on the USB drive.
