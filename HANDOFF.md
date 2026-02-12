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

- PCs are labeled **PC-1** through **PC-10**
- Student USB drives are labeled **STU-001**, **STU-002**, etc.
- Each USB has folders: Documents, Audio, Schoolwork

---

## If NVDA Stops Talking

Press **Ctrl + Alt + N** to restart NVDA.

NVDA starts automatically when the PC turns on. If it doesn't, look for the NVDA icon on the desktop or in the Start menu.

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
