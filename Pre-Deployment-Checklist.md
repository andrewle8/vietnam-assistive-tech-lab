# Pre-Deployment Checklist for Vietnam Lab

Use this checklist to ensure you're fully prepared before deployment.

## 2-3 Weeks Before Deployment

### Software & USB Kit
- [ ] Run `0-Download-Installers.ps1` to download all installers from GitHub Releases
- [ ] NVDA 2025.3.2+ downloaded
- [ ] Sao Mai VNVoice + Typing Tutor downloaded
- [ ] LibreOffice 26.2.0 MSI downloaded
- [ ] Firefox 147 downloaded
- [ ] VLC downloaded
- [ ] VLC NVDA add-on downloaded (for VLC accessibility)
- [ ] LEAP Games downloaded (Tic-Tac-Toe, Tennis, Curve)
- [ ] All files copied to USB drives (create 3 identical drives)
- [ ] PowerShell scripts tested on one PC
- [ ] NVDA configuration file verified
- [ ] Test complete offline deployment on one PC

### Hardware Preparation
- [ ] All 10 Dell Latitude 5420 laptops upgraded from Win 10 Pro to Win 11 Pro
- [ ] Windows updates completed (before disabling internet)
- [ ] Manufacturer bloatware removed
- [ ] User accounts created (document passwords)
- [ ] Power settings configured (never sleep)
- [ ] Windows Defender configured for offline mode
- [ ] Headphones available for each station

### Student USB Drives (Proposed)
- [ ] USB drives purchased (one per student, 4GB+)
- [ ] Each USB prepared with `4-Prepare-Student-USB.ps1`
- [ ] Each lab PC configured with `5-Configure-Loaner-Laptop.ps1`
- [ ] Google Drive authorized with `Setup-Rclone-Auth.ps1` (if internet available)

### Documentation
- [ ] All documentation translated to Vietnamese
- [ ] Troubleshooting guides printed (2 copies)
- [ ] Deployment plan printed

### Backup & Contingency
- [ ] 3 USB drives created (primary + 2 backups)
- [ ] Tested on multiple PCs to verify compatibility
- [ ] Laptop + charger packed (for troubleshooting)
- [ ] Digital backup stored in cloud (without installer files)

## 1 Week Before Deployment

### Final Testing
- [ ] Full deployment rehearsal on one PC (time it!)
- [ ] Verify scripts complete in under 30 minutes per PC
- [ ] Test NVDA speech with VNVoice
- [ ] Test LibreOffice with NVDA
- [ ] Test typing tutor launches and speaks
- [ ] Verify all software works 100% offline
- [ ] Document any issues and solutions

## Equipment Inventory

### For Each of 10 Stations
- [ ] Dell Latitude 5420 (Win 11 Pro)
- [ ] Wired headphones
- [ ] Label (PC-1 through PC-10)
- [ ] Student USB drive (if using proposed USB approach)

### Shared Equipment
- [ ] 3x USB deployment kits
- [ ] 1x laptop for troubleshooting
- [ ] Label maker
- [ ] Extra cables and adapters

## Success Criteria

Before leaving the deployment site:
- [ ] All 10 PCs boot and run NVDA automatically
- [ ] Speech output works in Vietnamese on all stations
- [ ] At least 2 students have successfully used the lab
- [ ] All documentation handed over
- [ ] Follow-up support schedule confirmed

---

**Last Updated:** February 6, 2026
**Status:** Ready to use
