# Vietnam Assistive Technology Lab Deployment Plan

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Timeline:** April 2026 deployment (1-3 days on-site)
**Equipment:** 10x Dell Latitude 5420 (refurbished, i5-1145G7, 8GB RAM, 256GB SSD)
**Users:** 10+ children, complete beginners to basic computer familiarity

---

## Executive Summary

Deploy a fully **offline, open-source** assistive technology lab enabling blind children to learn computing through **speech output** from day one.

**Pre-trip**
- Pre-configure computers before arrival using install scripts
- Label each computer
- Prep Personal USB sticks with Asset ID's and 3D Print Braille identifiers.
- Documentation in Vietnamese and English

---

## Software Stack (100% Free/Open Source)

| Component | Version | License | Notes |
|-----------|---------|---------|-------|
| **Windows 11** | Upgraded from Win 10 Pro | OEM License | Dell Latitude 5420 ships with Win 10 Pro, free upgrade to 11 |
| **NVDA** | 2025.3.2 (latest stable) | GPL-2.0 | Includes Vietnamese interface |
| **Sao Mai VNVoice** | v1.0 | Free for non-commercial | Vietnamese TTS (Minh Du/Mai Dung voices), SAPI5 |
| **Sao Mai Typing Tutor (SMTT)** | Latest | Free | Vietnamese typing lessons with speech |
| **LibreOffice** | 26.2.0 | MPL-2.0 | Replace MS Office - free, fully accessible |
| **Firefox** | 147 | MPL-2.0 | Better accessibility than Chrome, offline installer |
| **VLC Media Player** | 3.0.23 | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | Latest | GPL-2.0 | VLC accessibility enhancement |
| **Access8Math NVDA Add-on** | 4.3 | GPL-3.0 | Math content reading/writing via speech |
| **LEAP Games** | Latest | Apache-2.0 | Educational audio games (Tic-Tac-Toe, Tennis, Curve) |

---

## On-Site Deployment Timeline

Day 1: Physical Setup & Software Installation

1. **Unpack and arrange equipment**
   - Set up all 10 PCs on desks
   - Label each PC (1-10) with physical labels
   - Connect power, keyboards, mice
   - Test power and boot sequence

3. **Configure NVDA and test speech**
   - Run configuration script on all PCs
   - Test VNVoice speech output on each PC
   - Adjust volume levels
   - Verify auto-start functionality

4. **End-of-day verification**
   - Document any failures
   - Plan fixes for Day 2

### Day 2: Configuration, Testing & Training Prep
1. **Fix any Day 1 issues**
2. **Deploy training materials**
3. **Configure user experience**
4. **Conduct walkthrough with staff**
5. **Create station documentation**
6. **Pilot test with 1-2 students**

### Day 3: Final Testing & Handoff
1. **Full lab walkthrough and checks**
2. **Train staff on maintenance**

---

## Technical Configuration Details

### LibreOffice Accessibility

1. Enable "Support assistive technology tools"
2. Set default format to `.odt` (best NVDA support)
3. Configure Vietnamese language and keyboard
4. Disable animations and auto-correct

---

## Post-Deployment Support Plan

### Week 1-2: Intensive Monitoring
- Daily check-in with staff
- Remote troubleshooting as needed
- Document all issues

### Week 3-4: Stabilization
- Every 2-3 days check-in
- Review student feedback

### Month 2+: Ongoing Support
- Monthly progress reviews / check-in calls
- Quarterly maintenance planning

---

## Success Metrics (3-Month Evaluation)

1. **Technical Reliability:** 90%+ uptime across all 10 stations
2. **User Adoption:** All students can independently log in and launch NVDA
3. **Skill Progression:** 80%+ students complete typing tutor Lesson 3
4. **Equipment Durability:** No major hardware failures
5. **Staff Confidence:** Staff handle 90%+ of issues independently

---

**Status:** Ready for implementation
