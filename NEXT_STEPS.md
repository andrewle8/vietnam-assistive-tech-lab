# Immediate Next Steps - Vietnam Lab Deployment

## 📥 STEP 1: Download Software (This Week)

### Download these installers and save to `F:\Vietnam-Lab-Kit\Installers\`:

**1. NVDA (50 MB)**
- Go to: https://www.nvaccess.org/download/
- Download: "NVDA 2025.3.2 installer" (or latest stable)
- Save to: `F:\Vietnam-Lab-Kit\Installers\NVDA\nvda_2025.3.2.exe`
- Also download: Portable version as backup

**2. Sao Mai VNVoice (Vietnamese TTS)**
- Go to: https://saomaicenter.org/en/downloads
- Look for: "VNVoice" or "Vietnamese Voice"
- Save to: `F:\Vietnam-Lab-Kit\Installers\SaoMai\SaoMai_VNVoice_1.0.exe`

**3. Sao Mai Typing Tutor**
- Go to: https://saomaicenter.org/en/downloads/vietnamese-talking-software/sao-mai-typing-tutor-smtt
- Download latest version
- Save to: `F:\Vietnam-Lab-Kit\Installers\SaoMai\SaoMai_TypingTutor.exe`

**4. LibreOffice (300 MB)**
- Go to: https://www.libreoffice.org/download/download/
- Select: "Windows x86-64 (MSI)"
- Version: 24.8.x LTS
- Save to: `F:\Vietnam-Lab-Kit\Installers\LibreOffice\LibreOffice_24.8_Win_x86-64.msi`

**5. Firefox ESR (60 MB)**
- Go to: https://www.mozilla.org/en-US/firefox/enterprise/
- Download: "Windows 64-bit MSI" or EXE
- Save to: `F:\Vietnam-Lab-Kit\Installers\Firefox\Firefox_ESR_128_Setup.exe`

**6. VLC Media Player (40 MB)**
- Go to: https://www.videolan.org/vlc/
- Download: Windows 64-bit installer
- Save to: `F:\Vietnam-Lab-Kit\Installers\Utilities\VLC-3.0.x.exe`

**7. VLC NVDA Add-on (for VLC accessibility)**
- Go to: https://addons.nvda-project.org/
- Search for: "VLC"
- Download: `.nvda-addon` file
- Save to: `F:\Vietnam-Lab-Kit\Installers\NVDA\addons\VLC.nvda-addon`

**8. LEAP Games (Educational audio games)**
- Go to: https://www.gamesfortheblind.org/
- Download: Windows 64-bit versions of Tic-Tac-Toe, Tennis, and Curve
- Save to: `F:\Vietnam-Lab-Kit\Installers\Educational\`

> **Note:** 7-Zip has been removed from the software stack. Windows 11 (24H2) has built-in support for ZIP, 7z, RAR, and other archive formats.

---

## 🧪 STEP 2: Test Deployment (Next Week)

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

4. **Test with Orbit Reader 20:**
   - Connect Orbit Reader via USB
   - NVDA should auto-detect it
   - Test braille output

5. **Time the process** - Should complete in 30-45 minutes

6. **Document any issues** in a notebook or GitHub Issues

---

## 📞 STEP 3: Contact Sao Mai Center (2-3 Weeks Before April)

**Email or call Sao Mai Center:**
- Website: https://saomaicenter.org/en/contact
- Explain your project (10 PCs for blind children in orphanages)
- Request:
  - Vietnamese NVDA training materials (PDF/DOCX)
  - Vietnamese typing tutor lesson plans
  - Basic LibreOffice guides in Vietnamese
  - Contact for technical support during deployment
  - Availability of staff during April deployment

**Send them your GitHub repo:**
- Share: https://github.com/andrewle8/vietnam-assistive-tech-lab
- Ask for feedback and collaboration

---

## 🛒 STEP 4: Order Additional Equipment

**Order these items (if not already purchased):**

- [ ] **10x wired headphones** (over-ear, 3.5mm jack, durable)
  - Budget: $10-15 each = $100-150 total

- [ ] **10x USB extension cables** (6ft/2m each)
  - For flexible Orbit Reader positioning
  - Budget: $5 each = $50 total

- [ ] **3x USB drives** (16GB or larger)
  - For deployment kit (primary + 2 backups)
  - Budget: $10 each = $30 total

- [ ] **Label maker** with extra tape
  - For labeling PCs 1-10
  - Budget: $20-30

- [ ] **Extra USB cables** (USB-A to USB-B/Micro for Orbit Readers)
  - At least 5 spares
  - Budget: $20-30

**Total estimated cost: ~$250-300**

---

## 📋 STEP 5: Prepare the 10 Windows 11 PCs (1-2 Weeks Before April)

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

## 🔋 STEP 6: Prepare Orbit Reader 20 Devices (Week Before April)

**For each Orbit Reader:**

1. **Charge fully** (4+ hours)
2. **Update firmware** (if updates available from APH)
3. **Test USB connection** with one PC
4. **Label each device** (OR-1 through OR-10) to match PCs
5. **Pack USB cables** separately in labeled bags

---

## 📚 STEP 7: Prepare Documentation (Week Before April)

1. **Print these documents:**
   - [ ] Deployment Plan (from `Documentation/Deployment-Plan.md`)
   - [ ] Scripts README (English + Vietnamese)
   - [ ] Pre-Deployment Checklist
   - [ ] Troubleshooting Guide (create or request from Sao Mai)
   - [ ] Contact list with emergency numbers

2. **Organize in a binder** with tabs

3. **Create laminated quick-reference cards** (10+ copies)
   - Basic NVDA commands
   - How to connect Orbit Reader
   - Emergency contacts

---

## ✈️ STEP 8: Travel Preparation (1 Week Before)

- [ ] Book flights to Vietnam
- [ ] Book accommodation near deployment site
- [ ] Get travel insurance
- [ ] Prepare international phone plan or buy local SIM
- [ ] Pack all equipment (use checklist in `Pre-Deployment-Checklist.md`)
- [ ] Share itinerary with Sao Mai Center
- [ ] Confirm arrival time with orphanage

---

## 📊 Quick Timeline

**NOW → 1 week:**
- Download all software installers
- Test deployment on one PC

**2 weeks before April:**
- Contact Sao Mai Center
- Order additional equipment
- Start updating the 10 PCs

**1 week before April:**
- Finish preparing all PCs and Orbit Readers
- Create 3 USB deployment kits
- Print all documentation
- Pack equipment

**April (1-3 days on-site):**
- Deploy lab using your scripts
- Train Sao Mai staff
- Test with students
- Hand off documentation

---

## 🆘 Need Help?

**Immediate Questions:**
- Check: `F:\Vietnam-Lab-Kit\Documentation\`
- GitHub Issues: https://github.com/andrewle8/vietnam-assistive-tech-lab/issues

**Technical Support:**
- Sao Mai Center: https://saomaicenter.org/en/contact
- NVDA Community: https://www.nvaccess.org/get-help/
- APH (Orbit Reader): https://www.aph.org/orbit-reader/

---

## ✅ Current Status

- [x] GitHub repository created
- [x] Deployment scripts written
- [x] NVDA configuration prepared
- [x] Documentation completed
- [ ] **→ NEXT: Download software installers**
- [ ] Test deployment
- [ ] Contact Sao Mai Center
- [ ] Order equipment
- [ ] Prepare PCs

---

**You're on track for April 2026 deployment!** 🎉

Start with downloading the software installers this week, then test on one PC to make sure everything works.
