# Vietnam Assistive Technology Lab Deployment Plan

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Timeline:** April 2026 deployment (1-3 days on-site)
**Equipment:** 19x Dell Latitude 5420
**Users:** 19+ children, complete beginners to basic computer familiarity

---

## Executive Summary

Deploy a fully **offline, open-source** assistive technology lab enabling blind children to learn computing through **speech output** from day one.

**Pre-trip**
- Pre-configure all 19 laptops using install scripts and verify end-to-end
- Label each computer (PC-1 through PC-19)
- Prep personal USB sticks with asset IDs and 3D-printed Braille identifiers
- Contact Sao Mai Center to obtain accessible Vietnamese books (see Pre-Trip: Content Sourcing)
- Prepare 3 identical deployment USB drives
- Documentation in Vietnamese and English
- Test full deployment on one PC before packing

---

## Software Stack

| Component | Version | License | Notes |
|-----------|---------|---------|-------|
| **Windows 11** | Upgraded from Win 10 Pro | OEM License | Dell Latitude 5420 ships with Win 10 Pro, free upgrade to 11 |
| **NVDA** | 2025.3.3 | GPL-2.0 | Screen reader with Vietnamese interface |
| **Sao Mai VNVoice** | v1.0 | Free (non-commercial) | Vietnamese TTS (Minh Du/Mai Dung voices), SAPI5 |
| **Sao Mai Typing Tutor** | Latest | Free | Vietnamese typing lessons with speech |
| **LibreOffice** | 26.2.0 | MPL-2.0 | Office suite |
| **Firefox** | 147 | MPL-2.0 | Accessible web browser |
| **VLC Media Player** | 3.0.23 | GPL-2.0 | Media playback |
| **Audacity** | 3.7.7 | GPL-3.0 | Audio recording/editing |
| **Quorum Studio** | 7.3.0 | BSD | Accessible IDE purpose-built for blind students |
| **UniKey** | 4.6 | GPL | Vietnamese Telex keyboard input |
| **Kiwix** | 2.5.1 | GPL-3.0 | Offline encyclopedia reader |
| **Vietnamese Wikipedia** | Nov 2025 | CC BY-SA | Offline Vietnamese encyclopedia (~550 MB) |
| **Thorium Reader** | 3.3.0 | BSD-3 | EPUB/DAISY ebook reader for accessible reading |
| **SumatraPDF** | 3.5.2 | GPL-3.0 | Lightweight PDF reader for Vietnamese textbooks |
| **GoldenDict** | 1.5.0 | GPL-3.0 | Offline dictionary (Vietnamese-English/Vietnamese-Vietnamese) |
| **LEAP Games** | Latest | Apache-2.0 | Educational audio games (Tic-Tac-Toe, Tennis, Curve) |

**NVDA Add-ons:**

| Add-on | Purpose |
|--------|---------|
| VLC | VLC accessibility enhancement |
| Speech History | Review/copy last 100 NVDA utterances (F12) |
| NVDA Remote | Remote control between NVDA computers for post-deployment support |
| Focus Highlight | Visual focus indicator — helps sighted teachers follow student activity |
| Audacity Access Enhancement | NVDA scripts for Audacity (position, selection, transport) |
| Clock and Calendar | Time/date announcements (NVDA+F12) |
| MathCAT | Math speech/braille with Vietnamese support |

---

## Pre-Trip: Content Sourcing

### Sao Mai Center for the Blind (sachtiepcan.vn)

Sao Mai operates Vietnam's largest accessible book library (~10,000 titles) in DAISY, EPUB, Braille, and audio formats. Books cover education, literature, science, and children's content — ideal for the lab. Access requires registration and organizational eligibility under the Marrakesh Treaty.

**Action items (complete before April):**

1. **Email Sao Mai Center** — request an organizational account on [sachtiepcan.vn](https://sachtiepcan.vn/) for the orphanage
2. **Request offline content** — ask to pre-download age-appropriate DAISY/EPUB books for children (primary/secondary level)
3. **Ask for recommendations** — Vietnamese textbooks and children's literature suitable for blind students
4. **Pre-load books** onto each PC's Thorium Reader library before deployment

**Contact:** [saomaicenter.org/en](https://saomaicenter.org/en) (Ho Chi Minh City) — they produce the VNVoice TTS already in our stack, so there is an existing relationship.

---

## Pre-Trip: Test & Pack

### Full End-to-End Test (2-3 weeks before travel)

Run the entire deployment process on one laptop to verify:

1. Run `0-Download-Installers.ps1` — all downloads succeed
2. Run `0.5-Upgrade-Windows11.ps1` — upgrade from Win 10 to Win 11 if needed
3. Run `1-Install-All.ps1` — all software installs silently
4. Run `2-Verify-Installation.ps1` — all checks pass
5. Run `3-Configure-NVDA.ps1` — speech works, Vietnamese voice active
6. Run `6-Health-Check.ps1` — all green
7. Run `7-Audit.ps1` — compare machine state against manifest.json
8. Manually test: open each app, verify NVDA reads it correctly
9. Test Thorium Reader with a sample EPUB/DAISY file
10. Test student USB workflow with `4-Prepare-Student-USB.ps1`

Fix any issues, then repeat on a second laptop to confirm consistency.

### Pre-Configure All 19 Laptops

Run scripts 1-3 on all 19 laptops before packing. This saves significant time on-site.

1. Install software on all PCs (`1-Install-All.ps1`)
2. Verify all PCs (`2-Verify-Installation.ps1`)
3. Configure NVDA on all PCs (`3-Configure-NVDA.ps1`)
4. Apply Windows lockdown on all PCs (see Windows Hardening section)
5. Run health check on all PCs (`6-Health-Check.ps1`)
6. Label each PC (PC-1 through PC-19) with physical label
7. Charge all laptops to 100%

### Prepare USB Drives

1. Run `0-Download-Installers.ps1` to populate `Installers/`
2. Copy entire `Vietnam-Lab-Kit` folder to 3 separate USB drives
3. Label drives: PRIMARY, BACKUP-1, BACKUP-2
4. Prepare student USB drives with `4-Prepare-Student-USB.ps1`
5. Store deployment and student USB drives separately to prevent loss

### Packing List

**Computers & Accessories**
- [ ] 19x Dell Latitude 5420 (pre-configured, charged)
- [ ] 19x Dell power adapters (Vietnam uses Type A/C, same as US — no converter needed)
- [ ] 2x spare power adapters
- [ ] 21x Audio-Technica ATH-M40x headphones (19 stations + 2 spares)
- [ ] 5x spare headphone cables
- [ ] 4x replacement earpads

**USB Drives**
- [ ] 3x deployment USB drives (PRIMARY, BACKUP-1, BACKUP-2)
- [ ] 19+ student USB drives (labeled with print + Braille)
- [ ] 1x USB hub (for faster multi-PC setup if needed)

**Physical Labels & Accessories**
- [ ] PC labels (PC-1 through PC-19)
- [ ] Bump dots / tactile stickers for keyboard landmarks (F, J, and other keys)
- [ ] Ethernet cable (in case Wi-Fi config is needed on-site)
- [ ] Small Phillips screwdriver (for any hardware maintenance)

**Documentation**
- [ ] Printed HANDOFF.md reference cards (English + Vietnamese)
- [ ] Printed troubleshooting guide for staff

---

## On-Site Deployment Timeline

### Day 1: Physical Setup & Software Installation

1. **Unpack and arrange equipment**
   - Set up all 19 PCs on desks
   - Label each PC (PC-1 through PC-19) with physical labels if not already done
   - Connect power adapters
   - Distribute headphones to each station
   - Apply bump dots to F and J keys (and other landmarks) on any keyboards that lack tactile markers

2. **Run install scripts on any PCs not pre-configured**
   - Insert deployment USB drive
   - Run as Administrator:
     ```
     .\1-Install-All.ps1
     .\2-Verify-Installation.ps1
     .\3-Configure-NVDA.ps1
     ```
   - If PCs were pre-configured before travel, skip to step 3

3. **Configure NVDA and test speech on every PC**
   - Test VNVoice speech output on each PC with headphones plugged in
   - Adjust volume levels per station
   - Verify NVDA auto-start on boot
   - Verify Vietnamese keyboard input (UniKey) is working

4. **End-of-day verification**
   - Run `6-Health-Check.ps1` on all 19 PCs
   - Document any failures with PC number
   - Plan fixes for Day 2

### Day 2: Configuration, Testing & Training Prep

1. **Fix any Day 1 issues**
   - Re-run failed installs from backup USB drive
   - If a laptop is DOA, see Contingency Plan below

2. **Deploy content and training materials**
   - Load Sao Mai ebooks into Thorium Reader on each PC
   - Verify Kiwix Vietnamese Wikipedia opens correctly
   - Copy training audio files (if any) to each PC

3. **Configure user experience**
   - Set up student user accounts (restricted, see Windows Hardening)
   - Set desktop shortcuts to consistent layout across all PCs
   - Configure default apps (LibreOffice for documents, Firefox for web)
   - Set NVDA speech rate to a comfortable starting speed

4. **Conduct walkthrough with staff**
   - Show staff how to power on/off PCs
   - Demonstrate NVDA restart (Ctrl+Alt+N)
   - Walk through each installed application
   - Show staff how to run `6-Health-Check.ps1`
   - Explain the HANDOFF.md reference card

5. **Pilot test with 1-2 students**
   - Have students sit at a station with headphones
   - Walk them through: boot up, hear NVDA speak, open typing tutor
   - Note any confusion points or UX issues
   - Adjust volume, speech rate, or configuration based on feedback

### Day 3: Final Testing & Handoff

1. **Full lab walkthrough**
   - Run `6-Health-Check.ps1` on all 19 PCs — all green
   - Test every headphone jack
   - Verify student USB drives mount and are recognized
   - Spot-check 2-3 apps per PC (NVDA reads them correctly)

2. **Train staff on maintenance**
   - How to restart NVDA if it stops talking
   - How to run the health check script
   - How to re-image a PC from USB if needed (run scripts 1-3 again)
   - How to replace a headphone cable
   - How to contact for remote support (see Post-Deployment Support)

3. **Handoff documentation**
   - Leave printed HANDOFF.md reference cards at each station
   - Leave one deployment USB drive with staff (BACKUP-2)
   - Confirm staff contact method for ongoing support

---

## Technical Configuration Details

### LibreOffice Accessibility

1. Enable "Support assistive technology tools"
2. Set default format to `.odt` (best NVDA support)
3. Configure Vietnamese language and keyboard
4. Disable animations and auto-correct

### Windows Hardening (Student Machines)

These are shared machines for children. Lock them down to prevent accidental damage.

**Student accounts (standard user, not admin):**
- Create a local account `Student` with no password (ease of use for blind children)
- Admin account retains a password known only to staff

**Disable unnecessary features:**
- Disable Windows Update (offline machines, saves disk space and prevents unexpected reboots)
- Disable Cortana and web search in Start menu
- Disable lock screen ads and tips
- Disable Windows Store (prevents accidental installs)

**Protect the environment:**
- Set NVDA and UniKey as startup items for the Student account
- Prevent students from uninstalling software (standard user accounts handle this)
- Disable guest account

**Power settings:**
- Set display sleep to 15 minutes (saves battery during class)
- Set sleep to 30 minutes
- Disable hibernate (prevents confusion — blind students can't tell if the screen is off vs hibernated)

---

## Backup & Recovery

### If a PC Needs Reimaging

All software can be reinstalled from the deployment USB drive:

1. Log in as Administrator
2. Insert deployment USB
3. Run `1-Install-All.ps1`, `2-Verify-Installation.ps1`, `3-Configure-NVDA.ps1`
4. Re-apply Windows hardening settings
5. Run `6-Health-Check.ps1` to confirm

Total reimage time: ~30-45 minutes.

### Student Work Backup

- Student USB drives are the primary storage for student work
- If internet is available, `backup-usb.ps1` syncs to Google Drive via rclone (every 15 min)
- Staff should periodically copy student USB contents to a shared backup drive

---

## Contingency Plan

| Problem | Solution |
|---------|----------|
| **Laptop DOA on-site** | Redistribute students across remaining PCs. Reimage a spare from USB. |
| **Installer fails with no internet** | All installers are on the deployment USB — no internet required. Try BACKUP-1 or BACKUP-2 USB. |
| **NVDA stops speaking** | Ctrl+Alt+N restarts NVDA. If that fails, reboot. If persistent, re-run `3-Configure-NVDA.ps1`. |
| **Headphone jack broken** | Use USB audio adapter (consider packing 2 as spares) or Bluetooth with the ATH-M40x cable. |
| **Deployment USB corrupted** | 3 identical copies. Switch to BACKUP-1 or BACKUP-2. |
| **Power outage** | Laptops have batteries (~6 hrs). Charge overnight. No data loss risk with SSDs. |
| **Wrong keyboard layout** | Re-run UniKey setup. Verify Telex input method is selected. |

---

## Post-Deployment Support Plan

### Communication Channel

Establish a primary contact method **before leaving**:
- **WhatsApp or Zalo** (most common in Vietnam) group chat with staff
- Email as backup: staff sends description + PC number, you respond with steps
- **NVDA Remote** add-on is installed on all PCs — if internet becomes available, you can remote-control a student's NVDA session to diagnose issues in real time

### Week 1-2: Intensive Monitoring
- Daily check-in with staff via chat
- Remote troubleshooting via NVDA Remote if internet is available
- Document all issues and resolutions
- Staff sends health check results if problems arise

### Week 3-4: Stabilization
- Check-in every 2-3 days
- Review student feedback (staff relays)
- Address any recurring issues with updated scripts if needed

### Month 2+: Ongoing Support
- Monthly progress reviews / check-in calls
- Quarterly maintenance planning
- Plan remote software updates if internet becomes available
- Evaluate whether additional content (ebooks, games) should be shipped on USB

---

## Success Metrics (3-Month Evaluation)

1. **Technical Reliability:** 90%+ uptime across all 19 stations
2. **User Adoption:** All students can independently log in and launch NVDA
3. **Skill Progression:** 80%+ students complete typing tutor Lesson 3
4. **Equipment Durability:** No major hardware failures
5. **Staff Confidence:** Staff handle 90%+ of issues independently
6. **Content Usage:** Students are actively reading books in Thorium Reader

---

**Status:** Ready for implementation
