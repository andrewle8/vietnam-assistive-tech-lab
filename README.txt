Vietnam Assistive Technology Lab - Setup Guide
================================================

BEFORE YOU START
----------------
1. Open PowerShell as Administrator
   (Start menu > type "PowerShell" > right-click > Run as Administrator)

2. Run this once to allow scripts to execute:
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

3. After that, you can right-click any .ps1 file and choose
   "Run with PowerShell" and it will work.


SETUP STEPS
-----------

Step 1: Download Installers
  Right-click 0-Download-Installers.ps1 > Run with PowerShell
  Downloads all installers (~800 MB) automatically.

  Then right-click Verify-Installers.ps1 > Run with PowerShell
  Validates files and checksums.

  Optional: Right-click 0.6-Download-LanguagePack.ps1 > Run with PowerShell
  Pre-downloads the Vietnamese language pack for offline install.
  (Without this, Bootstrap-Laptop.ps1 will download it from the internet.)

Step 2: Download Windows 11 ISO (if upgrading from Windows 10)
  The Dell Latitude 5420s may ship with Windows 10. To upgrade:
  1. Download "Windows 11 (multi-edition ISO for x64 devices)" from:
     https://www.microsoft.com/en-us/software-download/windows11
  2. Create the folder Installers\Windows\ if it doesn't exist
  3. Place the ISO there (expected name: Win11_25H2_English_x64.iso)
  4. Right-click 0.5-Upgrade-Windows11.ps1 > Run with PowerShell
     on each PC that needs upgrading
  Note: The Arm64 ISO is NOT needed. Dell Latitude 5420 is x64.

Step 3: Set Up Tailscale (for remote management)
  Go to tailscale.com and create an account.
  In Access Controls, add "tag:vietnam-lab" to tagOwners.
  Generate a reusable pre-auth key:
    - Reusable: checked
    - Ephemeral: unchecked
    - Tags: tag:vietnam-lab (disables node key expiry = devices stay connected permanently)
    - Expiration: 90 days is fine (only needed during initial setup)
  Open Scripts\Install-Tailscale.ps1 in Notepad and replace
  tskey-auth-CHANGE_ME with your key.

Step 4: Set Up Each Laptop
  Right-click Bootstrap-Laptop.ps1 > Run with PowerShell
  It will prompt you:

    Supply values for the following parameters:
    PCNumber: _

  Enter a number 1-19 for each laptop. The script handles everything:
  hostname, Wi-Fi, software install, NVDA config, Windows hardening,
  Tailscale, and scheduled tasks.

Step 5: Verify
  Right-click 7-Audit.ps1 > Run with PowerShell
  Checks all software, Windows settings, and remote management.
  Green = OK, Yellow = warning, Red = problem.

OR run individual scripts in order from a PowerShell window:
  .\0-Download-Installers.ps1        Downloads all installers (~800 MB)
  .\0.5-Upgrade-Windows11.ps1        Upgrades Windows 10 to 11 (if needed)
  .\0.6-Download-LanguagePack.ps1    Downloads Vietnamese language pack (optional)
  .\1-Install-All.ps1                Installs all software
  .\2-Verify-Installation.ps1        Verifies everything installed
  .\3-Configure-NVDA.ps1             Configures NVDA + Vietnamese voice
  .\Configure-Laptop.ps1             Windows hardening + accessibility
  .\7-Audit.ps1                      Final audit to confirm everything works


TROUBLESHOOTING
---------------
- If a script fails, read the error in the PowerShell window
- Re-run the failed script after fixing the issue
- Use .\7-Audit.ps1 to check what's missing
- For full documentation see the GitHub repo:
  https://github.com/andrewle8/vietnam-assistive-tech-lab
