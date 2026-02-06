# Immediate Next Steps - Vietnam Lab Deployment

## STEP 1: Download Software (This Week)

All installers are hosted on **GitHub Releases** and downloaded automatically — no manual downloads needed.

```powershell
cd F:\Vietnam-Lab-Kit\Scripts
.\0-Download-Installers.ps1
```

This downloads everything from: https://github.com/andrewle8/vietnam-assistive-tech-lab/releases/tag/installers-v1

After the script finishes, verify the `Installers/` folder contains all files (see `Installers/README.md` for the full list).

---

## STEP 2: Test Deployment (Next Week)

1. **Find a test Windows 11 PC** (or use one of the 10 PCs you purchased)

2. **Copy the entire `F:\Vietnam-Lab-Kit` folder to a USB drive** (8GB or larger)

3. **Test the deployment:**
   ```powershell
   # Insert USB, open PowerShell as Administrator
   cd X:\Scripts  # Replace X: with your USB drive letter
   .\1-Install-All.ps1
   .\2-Verify-Installation.ps1
   .\3-Configure-NVDA.ps1
   ```

4. **Time the process** - Should complete in 30-45 minutes

6. **Document any issues** in a notebook or GitHub Issues

---

## STEP 3: Prepare Student USB Drives (Proposed)

Since students share PCs and cannot keep them, each student gets a personal USB drive to store their files. This step is optional and depends on the final approach chosen.

1. **Purchase USB drives** (one per student, 4GB+ recommended)

2. **Authorize Google Drive** (one-time, requires internet):
   ```powershell
   cd F:\Vietnam-Lab-Kit\Scripts
   .\Setup-Rclone-Auth.ps1
   ```

3. **Prepare each student's USB:**
   ```powershell
   .\4-Prepare-Student-USB.ps1
   # Follow prompts to assign student ID (STU-001, STU-002, etc.)
   # Creates folders: Documents, Audio, Schoolwork
   ```

4. **Configure each lab PC for USB backups:**
   ```powershell
   .\5-Configure-Loaner-Laptop.ps1
   # Deploys rclone, creates scheduled backup task (every 15 min),
   # adds "My USB" desktop shortcut
   ```

> **Note:** Cloud backup requires internet. If the lab is fully offline, students still keep their files on the USB — backups just won't sync to Google Drive.

---

## STEP 4: Prepare the 10 Windows 11 PCs (1-2 Weeks Before April)

**For each PC:**

1. **Update Windows fully**
   - Run Windows Update multiple times
   - Install all updates (may take 2-3 hours per PC)
   - Restart as needed

2. **Remove bloatware**
   - Uninstall unnecessary manufacturer software
   - Keep: Windows Defender, basic utilities

3. **Create user accounts**
   - Simple username: "Student" or "Lab1", "Lab2", etc.
   - Simple password (document it!)

4. **Configure power settings**
   - Settings → System → Power
   - Set "Screen" and "Sleep" to "Never"

5. **Disable Windows Update** (for offline operation)
   - After fully updating, disable automatic updates
   - Services → Windows Update → Disable

6. **Test offline mode**
   - Disconnect from internet
   - Verify PC boots and functions normally

7. **Label each PC** (PC-1 through PC-10)

---

## STEP 5: Prepare Documentation (Week Before April)

1. **Print these documents:**
   - [ ] Deployment Plan (from `Documentation/Deployment-Plan.md`)
   - [ ] Scripts README (English + Vietnamese)
   - [ ] Pre-Deployment Checklist
   - [ ] Troubleshooting Guide
   - [ ] Contact list with emergency numbers

2. **Organize in a binder** with tabs

---

## Quick Timeline

**NOW → 1 week:**
- Download all software installers
- Test deployment on one PC

**2 weeks before April:**
- Start updating the 10 PCs

**1 week before April:**
- Finish preparing all PCs
- Create 3 USB deployment kits
- Print all documentation
- Pack equipment

**April (1-3 days on-site):**
- Deploy lab using your scripts
- Test with students
- Hand off documentation

---

## Need Help?

**Immediate Questions:**
- Check: `F:\Vietnam-Lab-Kit\Documentation\`
- GitHub Issues: https://github.com/andrewle8/vietnam-assistive-tech-lab/issues

**Technical Support:**
- NVDA Community: https://www.nvaccess.org/get-help/

---

## Current Status

- [x] GitHub repository created
- [x] Deployment scripts written
- [x] NVDA configuration prepared
- [x] Documentation completed
- [ ] **→ NEXT: Run `0-Download-Installers.ps1` to download all software**
- [ ] Test deployment
- [ ] Prepare student USB drives
- [ ] Prepare PCs

---

**You're on track for April 2026 deployment!**
Start with downloading the software installers this week, then test on one PC to make sure everything works.
