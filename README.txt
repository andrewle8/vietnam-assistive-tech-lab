Vietnam Assistive Technology Lab - Setup Guide
================================================

BEFORE YOU START
----------------
Do NOT right-click scripts and choose "Run with PowerShell" -- the window
closes too fast to see errors.

Instead:
1. Open PowerShell as Administrator
   (Start menu > type "PowerShell" > right-click > Run as Administrator)

2. Run this once to allow scripts to execute:
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

3. Navigate to the extracted folder:
   cd C:\path\to\vietnam-assistive-tech-lab\Scripts


SETUP STEPS
-----------
Run these commands in order from the Scripts folder:

  .\0-Download-Installers.ps1    Downloads all installers (~800 MB)
  .\1-Install-All.ps1            Installs all software
  .\2-Verify-Installation.ps1    Verifies everything installed
  .\3-Configure-NVDA.ps1         Configures NVDA + Vietnamese voice
  .\Configure-Laptop.ps1         Windows hardening + accessibility
  .\7-Audit.ps1                  Final audit to confirm everything works

OR use the all-in-one script:
  .\Bootstrap-Laptop.ps1 -PCNumber 1    (change number for each PC, 1-19)


TROUBLESHOOTING
---------------
- If a script fails, read the error in the PowerShell window
- Re-run the failed script after fixing the issue
- Use .\7-Audit.ps1 to check what's missing
- For full documentation see the GitHub repo:
  https://github.com/andrewle8/vietnam-assistive-tech-lab
