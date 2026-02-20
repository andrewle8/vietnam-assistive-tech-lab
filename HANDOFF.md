# Lab Reference Card

**Vietnam Assistive Technology Lab**
**Deployed:** April 2026

---

## What's Installed (Every PC)

| Software | What It Does |
|----------|-------------|
| **NVDA** | Screen reader — speaks everything on screen in Vietnamese |
| **Sao Mai VNVoice** | Vietnamese voice for NVDA (Minh Du / Mai Dung) |
| **Sao Mai Typing Tutor** | Typing lessons with audio feedback |
| **LibreOffice** | Word processing, spreadsheets (like Microsoft Office) |
| **Firefox** | Web browser |
| **VLC** | Music and video player |
| **Thorium Reader** | EPUB/DAISY ebook and audiobook reader |
| **LEAP Games** | Audio games (Tic-Tac-Toe, Tennis, Curve) |

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

### Backup: Windows Narrator

If NVDA crashes and Ctrl+Alt+N doesn't restart it, Windows has a built-in backup screen reader:

- **Win + Ctrl + Enter** — Toggle Windows Narrator on/off

Narrator is less capable than NVDA but provides basic speech output until NVDA can be restarted. To restart NVDA after using Narrator, press Win+Ctrl+Enter again to turn off Narrator, then open the NVDA shortcut from the desktop or Start menu.

---

## Low-Vision Mode

Some students may have partial vision. These tools are pre-configured on every laptop:

| Shortcut | What It Does |
|----------|-------------|
| **Win + Plus (+)** | Launch Windows Magnifier (starts at 200% zoom, lens mode) |
| **Win + Minus (-)** | Zoom out while Magnifier is running |
| **Win + Esc** | Close Magnifier |
| **Win + Left Alt + Print Screen** | Toggle High Contrast mode |

Magnifier and NVDA can run at the same time for students with some remaining vision who also benefit from speech output.

---

## Switching Language / Chuyển đổi ngôn ngữ

Windows is set to **Vietnamese** by default. To switch between Vietnamese and English:

1. Open the **"Đổi Ngôn Ngữ - Switch Language"** shortcut on the desktop
2. A message will confirm the switch
3. **Sign out and sign back in** for the change to take effect

This is useful for staff or volunteers who need English temporarily. The keyboard input method (UniKey/Telex) is separate and works in both languages.

---

## Quick Health Check

To check if everything is working on a PC, run this script:

1. Right-click Start button → **Terminal (Admin)** or **PowerShell (Admin)**
2. Type: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
3. Navigate to the scripts folder on the USB drive
4. Run: `.\6-Health-Check.ps1`

The script checks all software and shows green (OK) or red (problem).

---

## Contact

**Andrew Le** — andrewle@monarchmissions.org
GitHub: https://github.com/andrewle8/vietnam-assistive-tech-lab/issues

For detailed troubleshooting, see the **Documentation/** folder on the USB drive.
