==========================================
VIETNAM LAB DEPLOYMENT - SCRIPTS GUIDE
==========================================

Version: 1.0
Date: February 2026

These PowerShell scripts automate the deployment of the Vietnam Assistive Technology Lab.

PREREQUISITES:
--------------
- Windows 11 PCs (pre-updated, disconnected from internet)
- USB drive with all installers downloaded
- Administrator access to each PC
- 30-60 minutes per PC for full deployment

DEPLOYMENT ORDER:
-----------------

0. Run: 0-Download-Installers.ps1 (FIRST TIME ONLY - on your main PC)
   → Downloads ALL software automatically from GitHub Releases
   → No manual downloads needed

1. Run: 1-Install-All.ps1
   → Installs all software silently (15-20 minutes)
   → NVDA, VNVoice, Typing Tutor, LibreOffice, Firefox, VLC, LEAP Games
   → Creates installation.log file

2. Run: 2-Verify-Installation.ps1
   → Checks all software installed correctly
   → Reports critical failures
   → Creates verification.log file

3. Run: 3-Configure-NVDA.ps1
   → Applies Vietnamese NVDA profile
   → Enables auto-start on login
   → Creates configuration.log file

HOW TO RUN:
-----------
1. Insert USB drive into PC
2. Right-click Windows Start button
3. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"
4. Navigate to scripts folder:
   cd X:\Scripts
   (Replace X: with your USB drive letter)

5. Run first script:
   .\1-Install-All.ps1

6. Follow prompts for remaining scripts

TROUBLESHOOTING:
----------------
If scripts won't run due to "Execution Policy":

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Then run scripts normally.

POST-DEPLOYMENT:
-----------------

6. Run: 6-Health-Check.ps1 (anytime, after deployment)
   → Checks all software is still installed
   → Verifies NVDA is running and auto-start is enabled
   → Reports disk space and USB drives
   → Creates health-check.log file

LOGS:
-----
All scripts create log files in the Scripts folder:
- installation.log
- verification.log
- configuration.log
- health-check.log

Review logs if any issues occur.

==========================================
© 2026 - Vietnam Assistive Tech Lab Project
==========================================
