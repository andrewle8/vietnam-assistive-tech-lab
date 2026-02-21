# Vietnam Assistive Technology Lab Deployment Plan

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Timeline:** April 2026 deployment (1-3 days on-site)
**Equipment:** 19x Dell Latitude 5420
**Users:** 19+ children, complete beginners to basic computer familiarity

---

## Executive Summary

Deploy a fully **offline, open-source** assistive technology lab enabling blind children to learn computing through **speech output** from day one. All 19 PCs include **Tailscale VPN** for remote management from the US, **automated updates** via a pull-based update agent, and **fleet health monitoring** via Google Drive.

**Pre-trip**
- Set up Tailscale account and generate reusable auth key with `tag:vietnam-lab` (see Pre-Trip: Tailscale Setup)
- Pre-configure all 19 laptops using install scripts and verify end-to-end
- Label each computer (PC-1 through PC-19)
- Prep personal USB sticks with asset IDs and 3D-printed Braille identifiers
- Contact Sao Mai Center to obtain accessible Vietnamese books (see Pre-Trip: Content Sourcing)
- Prepare 3 identical deployment USB drives
- Run `Pre-Deployment-Check.ps1` — all checks green
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
| **Microsoft Office 365** | Latest | Non-profit license | Office suite (Word, Excel, PowerPoint, Outlook) |
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
| **Tailscale** | 1.82.0 | BSD-3 | Mesh VPN for remote management from the US |
| **rclone** | Latest | MIT | Google Drive sync for fleet health reports and student backups |

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

## Pre-Trip: Tailscale Setup

Tailscale creates a mesh VPN — no port forwarding needed, survives NAT changes, auto-reconnects. This gives you SSH/WinRM access to all 19 PCs from the US. Free tier supports 100 devices and 3 users.

**Action items (complete 2-3 weeks before travel):**

1. **Create a Tailscale account** at [tailscale.com](https://tailscale.com)
2. **Add tag to Access Controls** — in the Tailscale admin console, add `"tag:vietnam-lab"` to `tagOwners` under your admin group
3. **Generate a pre-auth key** in the Tailscale admin console:
   - Go to Settings > Keys > Generate auth key
   - **Reusable:** checked
   - **Ephemeral:** unchecked
   - **Tags:** `tag:vietnam-lab` (this disables node key expiry — devices stay connected permanently)
   - **Expiration:** 90 days (max allowed; only needed during initial setup, not after)
4. **Update `Install-Tailscale.ps1`** — replace the placeholder `tskey-auth-CHANGE_ME` with your real auth key
5. **Install Tailscale on your own machine** (macOS/Windows) — this is how you'll connect to PCs remotely
6. **Download the Tailscale MSI** — `0-Download-Installers.ps1` fetches it automatically from GitHub

**How it works during deployment:**
- `Bootstrap-Laptop.ps1` installs Tailscale on each PC as part of the setup flow
- Each PC joins your tailnet as `PC-01`, `PC-02`, etc. with a `100.x.x.x` IP
- After deployment, you can reach any PC from the US via its Tailscale IP
- `Deploy-All.ps1 -UseTailscale` and `Check-Fleet.ps1 -UseTailscale` work over the VPN

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

### GoldenDict Vietnamese Dictionaries

GoldenDict is installed on all 19 PCs but needs dictionary files to be useful. The Open Vietnamese Dictionary Project provides free StarDict-format dictionaries that GoldenDict can load directly.

**Action items (complete before April):**

1. **Download StarDict Vietnamese dictionaries** from [github.com/dynamotn/stardict-vi](https://github.com/dynamotn/stardict-vi) — get Vietnamese-Vietnamese and Vietnamese-English dictionary files
2. **Pre-load dictionaries** into GoldenDict's dictionary folder on each PC (typically `C:\Program Files\GoldenDict\content\` or configure via GoldenDict settings)
3. **Test dictionary lookup** — verify GoldenDict can look up Vietnamese words with NVDA reading the definitions

---

## Pre-Trip: Test & Pack

### Windows 10 First Boot (OOBE)

Each Dell Latitude 5420 ships with Windows 10 Pro. On first power-on, walk through the setup:

1. **Region** — United States (scripts change this later)
2. **Keyboard** — US
3. **Second keyboard** — Skip
4. **Network** — Skip if possible. If Windows forces you to connect, press **Shift+F10** to open Command Prompt and type `oobe\bypassnro` to restart OOBE with a "I don't have internet" option. Alternatively, connect to Wi-Fi — either way works.
5. **How would you like to set up?** — Either option works:
   - **Set up for an organization** → click **Domain join instead** (bottom left), OR
   - **Set up for personal use** / **I don't have internet** → **Limited setup**
   - Both create a local account — the scripts don't care which path you took
6. **Who's going to use this PC?** — `Admin` (Bootstrap-Laptop renames it later)
7. **Password** — Set something simple or leave blank
8. **Security questions** — Put anything (e.g. "a", "a", "a") — this account is temporary
9. **Privacy settings** — Toggle everything off, click Accept
10. **Cortana** — Skip / Not now

### BIOS Setup (Required Before Win11 Upgrade)

Windows 11 requires Secure Boot and TPM 2.0. Enable these **before** running the upgrade:

1. Restart the PC
2. Press **F2** repeatedly at the Dell logo to enter BIOS
3. Go to **Security** tab
4. Enable **Secure Boot**
5. Verify **TPM 2.0** is enabled (same Security tab)
6. **Save and Exit** (Apply Changes)

### Upgrade to Windows 11

You're now on the Win10 desktop. Open PowerShell as Admin and set execution policy:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

Plug in the deployment USB and navigate to the project folder, then:

```powershell
.\Scripts\0.5-Upgrade-Windows11.ps1
```

This upgrades Win10 to Win11 25H2 from the ISO on your USB. The PC will reboot — wait for it to finish (may take 15-30 min). After reboot, run `winver` to confirm you're on Windows 11.

### Run Bootstrap

After confirming Win11, open PowerShell as Admin, navigate to the USB, and run:

```powershell
.\Scripts\Bootstrap-Laptop.ps1 -PCNumber 1
```

This does everything: install all software, configure NVDA, set up Vietnamese language, harden Windows, create LabAdmin + Student accounts, install Tailscale, and register scheduled tasks. Takes ~30-45 min.

### Verify

After Bootstrap completes:

```powershell
.\Scripts\7-Audit.ps1
```

All checks should pass. Then manually verify:
- NVDA is speaking Vietnamese
- Each app opens correctly
- UniKey Vietnamese keyboard input works

### Pre-Setup Steps (Done Once on Your Setup PC, Not Per-Laptop)

These are done **once** on your setup PC with internet before deploying any laptops:

1. `.\Scripts\0-Download-Installers.ps1` — downloads all software to the USB
2. `.\Scripts\Verify-Installers.ps1` — all files present with correct SHA256 checksums
3. `.\Scripts\0.6-Download-LanguagePack.ps1` — extracts Vietnamese language pack cabs to USB
4. `.\Scripts\Setup-Rclone-Auth.ps1` — authorizes Google Drive (creates rclone.conf)
5. Place `setup.exe` in `Installers\MSOffice\` and run `setup.exe /download configuration.xml` (in CMD)
6. Place Win11 25H2 ISO as `Installers\Windows\Win11_25H2_English_x64.iso`
7. Update Tailscale auth key in `Install-Tailscale.ps1` (replace `tskey-auth-CHANGE_ME`)

### Per-Laptop Deployment Summary

For each of the 19 laptops, the process is:

1. **OOBE** — create temporary local Admin account
2. **BIOS** — enable Secure Boot + TPM 2.0 (F2 at Dell logo)
3. **Upgrade** — `0.5-Upgrade-Windows11.ps1` → reboot → confirm with `winver`
4. **Bootstrap** — `Bootstrap-Laptop.ps1 -PCNumber N` (where N = 1-19)
5. **Verify** — `7-Audit.ps1` → all green
6. **Label** — apply physical PC-N label

### Full End-to-End Test (First Laptop)

Run the full process on **one laptop** first to verify everything works:

1. Complete steps 1-5 above for PC-1
2. Verify Tailscale: PC appears in your tailnet as `PC-01` with a `100.x.x.x` IP
3. Manually test: open each app, verify NVDA reads it correctly
4. Test Thorium Reader with a sample EPUB/DAISY file
5. Test student USB workflow with `.\Scripts\4-Prepare-Student-USB.ps1`
6. From your machine: `.\Scripts\Check-Fleet.ps1 -UseTailscale` — PC-01 shows as reachable

Fix any issues, then proceed to configure the remaining 18 laptops.

### Pre-Configure All 19 Laptops

After the test PC passes, configure the remaining 18 PCs. On each PC, open PowerShell as Administrator, `cd` to the project folder, then:

1. `.\Scripts\Bootstrap-Laptop.ps1` — it will prompt for `PCNumber`, enter 1–19
   - This runs: install software (including Microsoft Office), verify, configure NVDA, set up Windows hardening, install Tailscale, register scheduled tasks (update agent + fleet reporter)
2. Verify each PC appears in your Tailscale admin console
3. `.\Scripts\7-Audit.ps1` on each — all green
4. Label each PC (PC-1 through PC-19) with physical label
5. Charge all laptops to 100%

### Prepare USB Drives

1. Run `0-Download-Installers.ps1` to populate `Installers/` (smart downloads from vendor URLs, GitHub, and Kiwix)
2. Run `Verify-Installers.ps1` — all files present and checksums match
3. Copy entire `Vietnam-Lab-Kit` folder to 3 separate USB drives
4. Label drives: PRIMARY, BACKUP-1, BACKUP-2
5. Prepare student USB drives with `4-Prepare-Student-USB.ps1`
6. Store deployment and student USB drives separately to prevent loss

### Final Pre-Trip Validation

Run from your machine the day before travel:

```powershell
.\Pre-Deployment-Check.ps1
```

This validates:
- All core scripts and config files exist
- `manifest.json` has no null critical fields
- All installers present with correct checksums
- Tailscale auth key is configured (not placeholder)
- `update-manifest.json` is reachable on GitHub
- GitHub Release `installers-v1` has expected assets
- rclone can reach Google Drive

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

2. **Run Bootstrap on any PCs not pre-configured**
   - Insert deployment USB drive
   - Open PowerShell as Administrator, `cd` to the project folder on the USB drive
   - Run `.\Scripts\Bootstrap-Laptop.ps1` — it will prompt for `PCNumber`, enter the PC number (1–19)
   - This handles everything: software install, NVDA config, hardening, Tailscale, scheduled tasks
   - If PCs were pre-configured before travel, skip to step 3

3. **Configure NVDA and test speech on every PC**
   - Test VNVoice speech output on each PC with headphones plugged in
   - Adjust volume levels per station
   - Verify NVDA auto-start on boot
   - Verify Vietnamese keyboard input (UniKey) is working

4. **End-of-day verification**
   - Run `7-Audit.ps1` on all 19 PCs — check for failures
   - Verify all PCs appear online in Tailscale admin console
   - If internet is available: run `Get-FleetStatus.ps1` from your laptop to confirm heartbeats are uploading
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
   - Configure default apps (Microsoft Office for documents, Firefox for web)
   - Set NVDA speech rate to a comfortable starting speed

4. **Conduct walkthrough with staff**
   - Show staff how to power on/off PCs
   - Demonstrate NVDA restart (Ctrl+Alt+N)
   - Walk through each installed application
   - Show staff how to run `7-Audit.ps1`
   - Explain the HANDOFF.md reference card

5. **Pilot test with 1-2 students**
   - Have students sit at a station with headphones
   - Walk them through: boot up, hear NVDA speak, open typing tutor
   - Note any confusion points or UX issues
   - Adjust volume, speech rate, or configuration based on feedback

### Day 3: Final Testing & Handoff

1. **Full lab walkthrough**
   - Run `7-Audit.ps1` on all 19 PCs — all green
   - Test every headphone jack
   - Verify student USB drives mount and are recognized
   - Spot-check 2-3 apps per PC (NVDA reads them correctly)

2. **Verify remote management**
   - All 19 PCs show online in Tailscale admin console
   - From your laptop: `Check-Fleet.ps1 -UseTailscale` — all 19 PCs reachable
   - From your laptop: `Get-FleetStatus.ps1` — heartbeats uploading to Google Drive
   - Test remote command: `Deploy-All.ps1 -UseTailscale -ScriptBlock { hostname }` — all PCs respond

3. **Train staff on maintenance**
   - How to restart NVDA if it stops talking
   - How to run the health check script
   - How to re-image a PC from USB if needed (run `Bootstrap-Laptop.ps1`)
   - How to replace a headphone cable
   - Explain that software updates happen automatically when PCs are connected to internet
   - How to contact for remote support (see Post-Deployment Support)

4. **Handoff documentation**
   - Leave printed HANDOFF.md reference cards at each station
   - Leave one deployment USB drive with staff (BACKUP-2)
   - Confirm staff contact method for ongoing support

---

## Technical Configuration Details

### Office Suite Accessibility

**Microsoft Office 365** (non-profit license):
- NVDA has built-in MS Office support via UIA — no add-on needed
- Installed via Office Deployment Tool with `configuration.xml` (en-us + vi-vn)
- Activate with non-profit license post-deployment
- If MS Office is already installed, the script skips installation and just verifies

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
3. Run `Bootstrap-Laptop.ps1 -PCNumber N` (where N matches the PC label)
4. Run `7-Audit.ps1` to confirm everything passes

Total reimage time: ~30-45 minutes. Tailscale, update agent, and fleet reporter are all re-installed automatically.

### Remote Reimaging (from the US)

If a PC is online via Tailscale, you can push fixes remotely:

```powershell
# From your machine
Deploy-All.ps1 -UseTailscale -PCList "PC-07" -ScriptBlock { & C:\LabTools\update-agent\Update-Agent.ps1 }
```

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
| **Tailscale not connecting** | Check internet first. Run `tailscale up` manually. If auth key expired, generate a new one and re-run `Install-Tailscale.ps1`. |
| **PC not reporting to Google Drive** | Check internet and rclone config. Run `Report-FleetHealth.ps1` manually. Check `C:\LabTools\fleet-reports\report.log`. |

---

## Remote Management Infrastructure

All 19 PCs have three automated systems that work when internet is available:

### Tailscale VPN

- Each PC has a Tailscale `100.x.x.x` IP accessible from the US
- Run `Check-Fleet.ps1 -UseTailscale` to ping all PCs
- Run `Deploy-All.ps1 -UseTailscale` to execute commands remotely via WinRM
- Run `Get-FleetTailscaleIPs.ps1` to list all device IPs from the Tailscale API

### Auto-Update Agent (`Update-Agent.ps1`)

Scheduled task on each PC, runs daily at 2-4 AM:
1. Checks `update-manifest.json` on GitHub for new versions
2. Downloads updated installers with SHA256 verification
3. Installs silently, verifies with `7-Audit.ps1`
4. Rolls back critical packages (NVDA, VNVoice) if install fails
5. Reports results to Google Drive

**To push an update:** Edit `update-manifest.json` in the repo with new package versions and SHA256 hashes, push to main. All online PCs pick it up within 24 hours.

### Fleet Health Reporter (`Report-FleetHealth.ps1`)

Scheduled task on each PC, runs daily at 3 AM (staggered per PC):
1. Runs `7-Audit.ps1` to check machine state against `manifest.json`
2. Uploads heartbeat JSON to `gdrive:VietnamLabFleet/heartbeats/PC-XX.json`
3. Uploads full audit report to `gdrive:VietnamLabFleet/PC-XX/`

**To check fleet status:** Run `Get-FleetStatus.ps1` from your machine — downloads heartbeats from Google Drive and displays a dashboard with status, Tailscale IPs, audit results, and staleness warnings.

---

## Post-Deployment Support Plan

### Communication Channel

Establish a primary contact method **before leaving**:
- **WhatsApp or Zalo** (most common in Vietnam) group chat with staff
- Email as backup: staff sends description + PC number, you respond with steps
- **NVDA Remote** add-on is installed on all PCs — if internet becomes available, you can remote-control a student's NVDA session to diagnose issues in real time

### Week 1-2: Intensive Monitoring
- Daily check-in with staff via chat
- Run `Get-FleetStatus.ps1` daily — check for stale or failing PCs
- Connect to individual PCs via Tailscale for remote troubleshooting if needed
- Document all issues and resolutions

### Week 3-4: Stabilization
- Check-in every 2-3 days
- Review fleet dashboard for any drift or failures
- Address any recurring issues by pushing updates via `update-manifest.json`

### Month 2+: Ongoing Support
- Weekly `Get-FleetStatus.ps1` check — flag any PC not seen in 7+ days
- Push software updates remotely via `update-manifest.json` as new versions release
- Monthly progress reviews / check-in calls with staff
- Quarterly maintenance planning
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
