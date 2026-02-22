Vietnam Assistive Technology Lab - Setup Guide
================================================

HOW TO RUN SCRIPTS
------------------
All scripts must be run from an Administrator PowerShell window.
Windows 11 does not have a "Run as Administrator" option in the
right-click menu for .ps1 files, so you must use the command line.

1. Open PowerShell as Administrator
   (Start menu > type "PowerShell" > right-click > Run as Administrator)

2. Run this once to allow scripts to execute:
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

3. Navigate to the project folder:
   cd C:\path\to\vietnam-assistive-tech-lab

4. Run all scripts from this PowerShell window (see steps below).


SETUP STEPS
-----------

Step 1: Download Installers
  .\Scripts\0-Download-Installers.ps1
  Downloads all installers (~800 MB) automatically.

  Then validate files and checksums:
  .\Scripts\Verify-Installers.ps1

  Optional - pre-download the Vietnamese language pack for offline install
  (without this, Bootstrap-Laptop.ps1 will download it from the internet):
  .\Scripts\0.6-Download-LanguagePack.ps1

Step 2: Download Windows 11 ISO (if upgrading from Windows 10)
  The Dell Latitude 5420s may ship with Windows 10. To upgrade:
  1. Download "Windows 11 (multi-edition ISO for x64 devices)" from:
     https://www.microsoft.com/en-us/software-download/windows11
  2. Create the folder Installers\Windows\ if it doesn't exist
  3. Place the ISO there (expected name: Win11_25H2_English_x64.iso)
  4. Run the upgrade script on each PC that needs it:
     .\Scripts\0.5-Upgrade-Windows11.ps1
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
  .\Scripts\Bootstrap-Laptop.ps1
  It will prompt you:

    Supply values for the following parameters:
    PCNumber: _

  Enter a number 1-19 for each laptop. The script handles everything:
  hostname, Wi-Fi, software install, NVDA config, Windows hardening,
  Tailscale, and scheduled tasks.

  Microsoft Office setup (before running Bootstrap):
  1. Download the Office Deployment Tool from Microsoft
  2. Extract setup.exe to Installers\MSOffice\
  3. Run: .\setup.exe /download configuration.xml
  4. This downloads ~2 GB of Office installer files
  The Bootstrap script installs Office automatically. Activate with your
  non-profit license after deployment.

Step 5: Verify
  .\Scripts\7-Audit.ps1
  Checks all software, Windows settings, and remote management.
  Green = OK, Yellow = warning, Red = problem.

Individual scripts (if running separately instead of Bootstrap):
  .\Scripts\0-Download-Installers.ps1        Downloads all installers (~800 MB)
  .\Scripts\0.5-Upgrade-Windows11.ps1        Upgrades Windows 10 to 11 (if needed)
  .\Scripts\0.6-Download-LanguagePack.ps1    Downloads Vietnamese language pack (optional)
  .\Scripts\1-Install-All.ps1                Installs all software
  .\Scripts\2-Verify-Installation.ps1        Verifies everything installed
  .\Scripts\3-Configure-NVDA.ps1             Configures NVDA + Vietnamese voice
  .\Scripts\Configure-Laptop.ps1             Windows hardening + accessibility
  .\Scripts\7-Audit.ps1                      Final audit to confirm everything works


TROUBLESHOOTING
---------------
- If a script fails, read the error in the PowerShell window
- Re-run the failed script after fixing the issue
- Use .\7-Audit.ps1 to check what's missing
- For full documentation see the GitHub repo:
  https://github.com/andrewle8/vietnam-assistive-tech-lab
