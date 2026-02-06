# Vietnam Assistive Technology Lab Deployment Plan

**Project:** Blind Children's Computer Lab - Vietnam Orphanages
**Timeline:** April 2026 deployment (1-3 days on-site)
**Equipment:** 10 Windows 11 PCs / Laptops (x86-64)
**Users:** 10+ children, complete beginners to basic computer familiarity

---

## Executive Summary

Deploy a fully **offline, open-source** assistive technology lab enabling blind children to learn computing through **speech output** from day one. The deployment must be completed in 1-3 days on-site.

**Critical Success Factors:**
- Pre-configure everything before arrival (USB deployment kit)
- Automated, scripted installation for speed
- Zero internet dependency
- Documentation in Vietnamese and English

---

## Software Stack (100% Free/Open Source)

| Component | Version | License | Notes |
|-----------|---------|---------|-------|
| **Windows 11** | Pre-installed OEM | OEM License | Already on purchased PCs |
| **NVDA** | 2025.3.2 (latest stable) | GPL-2.0 | Includes Vietnamese interface |
| **Sao Mai VNVoice** | v1.0 | Free for non-commercial | Vietnamese TTS (Minh Du/Mai Dung voices), SAPI5 |
| **Sao Mai Typing Tutor (SMTT)** | Latest | Free | Vietnamese typing lessons with speech |
| **LibreOffice** | 26.2.0 | MPL-2.0 | Replace MS Office - free, fully accessible |
| **Firefox** | 147 | MPL-2.0 | Better accessibility than Chrome, offline installer |
| **VLC Media Player** | 3.0.x | GPL-2.0 | Media playback |
| **VLC NVDA Add-on** | Latest | GPL-2.0 | VLC accessibility enhancement |
| **LEAP Games** | Latest | Apache-2.0 | Educational audio games (Tic-Tac-Toe, Tennis, Curve) |

### Total Software Cost: $0

---

## On-Site Deployment Timeline

### Day 1: Physical Setup & Software Installation (6-8 hours)

**Morning (9 AM - 12 PM):**
1. **Unpack and arrange equipment** (1 hour)
   - Set up all 10 PCs on desks
   - Label each PC (1-10) with physical labels
   - Connect power, keyboards, mice
   - Test power and boot sequence

2. **Run deployment script on all PCs** (2-3 hours)
   - PC #1: Run full installation, verify success
   - PCs #2-10: Run in parallel (batch of 3-4 at a time)
   - Monitor for errors using verification script
   - Document any issues immediately

**Lunch Break (12 PM - 1 PM)**

**Afternoon (1 PM - 5 PM):**
3. **Configure NVDA and test speech** (2 hours)
   - Run configuration script on all PCs
   - Test VNVoice speech output on each PC
   - Adjust volume levels
   - Verify auto-start functionality

4. **End-of-day verification** (30 min)
   - Run verification script on all 10 PCs
   - Document any failures
   - Plan fixes for Day 2

### Day 2: Configuration, Testing & Training Prep (6-8 hours)

**Morning (9 AM - 12 PM):**
1. **Fix any Day 1 issues** (1-2 hours)
2. **Deploy training materials** (1 hour)
3. **Configure user experience** (1 hour)

**Afternoon (1 PM - 5 PM):**
4. **Conduct walkthrough with staff** (2-3 hours)
5. **Create station documentation** (1 hour)
6. **Pilot test with 1-2 students** (1 hour)

### Day 3: Final Testing & Handoff (4-6 hours)

**Morning (9 AM - 12 PM):**
1. **Full lab walkthrough** (1 hour)
2. **Train staff on maintenance** (2 hours)

**Afternoon (1 PM - 3 PM):**
3. **Documentation handoff** (1 hour)
4. **Final sign-off** (30 min)

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
- Weekly check-in calls
- Monthly progress reviews
- Quarterly maintenance planning

---

## Success Metrics (3-Month Evaluation)

1. **Technical Reliability:** 90%+ uptime across all 10 stations
2. **User Adoption:** All students can independently log in and launch NVDA
3. **Skill Progression:** 80%+ students complete typing tutor Lesson 3
4. **Equipment Durability:** No major hardware failures
5. **Staff Confidence:** Staff handle 90%+ of issues independently

---

## Risk Assessment & Mitigation

### Risk 1: Limited On-Site Time (1-3 days)
**Mitigation:** Pre-configured USB kit, automated scripts, parallel installation

### Risk 2: Hardware Compatibility Issues
**Mitigation:** Test deployment beforehand, backup installers, portable NVDA version

### Risk 3: Language Barriers
**Mitigation:** All documentation in Vietnamese/English

### Risk 4: No Internet for Troubleshooting
**Mitigation:** 100% offline stack, USB kit contains everything, printed guides

### Risk 5: Student Overwhelm
**Mitigation:** Gradual introduction, experienced instructors, self-paced materials

---

**Document Version:** 1.0
**Last Updated:** February 5, 2026
**Status:** Ready for implementation
