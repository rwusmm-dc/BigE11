# BigE11

 <img width="1920" height="1080" alt="w1" src="https://github.com/user-attachments/assets/1f408254-e524-4c7d-ab69-43164c13dc84" />


BigE11 is a comprehensive Windows 11 ISO optimization script that processes installation media up to version 25H2, producing a streamlined and performance-tuned output image.

## How to Use

1. Mount your Windows 11 ISO (must be from an official Microsoft source, preferably unaltered)
2. Run the script and enter the drive letter assigned to the mounted ISO drive when prompted (e.g., F:), note, the w1.jpg is required to be besides the script .ps1 for the OS to have the designated wallpaper.

## Process Overview

The script performs the following operations in sequence:

### Media Preparation
- Copies the complete Windows 11 installation media to a designated scratch drive
- Automatically converts install.esd to install.wim format when install.wim is not present
- Provides interactive selection of the correct image index for multi-edition sources
- Detects system architecture with AMD64 retention and ARM component removal
- Identifies the default system language to target only relevant language packs for removal (Handwriting, OCR, Speech, TTS)

### Bloatware and Application Removal
- Removes all pre-installed Windows applications including:
  - AppUp, Clipchamp, Dolby
  - Bing News, Search, Weather
  - Copilot, CrossDevice
  - GamingApp, GetHelp, Getstarted
  - 3DViewer, OfficeHub, Solitaire, StickyNotes
  - MixedReality Portal, MSPaint, OneNote, OfficePush
  - Outlook, Paint, People, PowerAutomate
  - Skype, StartExperiences, Todos, Wallet
  - DevHome, Teams, Alarms, Camera
  - Mail/Calendar, FeedbackHub, Maps, SoundRecorder
  - Terminal, Xbox TCUI/App/GameOverlay/GamingOverlay/IdentityProvider/SpeechToText
  - YourPhone, ZuneMusic, ZuneVideo
  - MicrosoftFamily, QuickAssist, Advertising
  - Cortana, PeopleHub, Photos

### Browser and Component Removal
- Complete removal of Microsoft Edge browser including all associated folders (Program Files, EdgeUpdate, EdgeCore)
- Removal of Microsoft Edge WebView2 from System32 and WinSxS (AMD64 architecture only)
- Removal of OneDriveSetup.exe from System32

### Windows Features Uninstallation
- Fax Services
- Print to PDF
- XPS Services
- Work Folders Client
- IIS (entire web server role including FTP, management tools, and legacy compatibility)
- Telnet Client
- TFTP Client
- Simple TCP/IP Services
- DirectPlay
- Windows Identity Foundation
- TIFF IFilter
- XPS Viewer
- Internet Printing Client

### Component Preservation
- Windows Media Player remains intact
- Windows Recovery Environment (WinRE) remains untouched
- Windows Defender and associated services maintain full functionality

### System Service Optimization
Disables services that consume system resources:
- DiagTrack, diagnosticshub, DPS
- WdiServiceHost/System, TrkWks
- Fax, lfsvc (Geolocation)
- RetailDemo
- All Xbox services (Auth, GameSave, NetApi, GipSvc, GameCallableUI)
- PcaSvc, ParentalControls
- WPNSvc, BcastDVR
- Messaging, PimIndex
- Unistore, UserData
- Windows Search

### Security and Authentication Modifications
- Removal of all biometric and Windows Hello components (WinBio.dll and winbio* files)

### Registry Modifications
- Loads offline registry hives (COMPONENTS, DEFAULT, NTUSER, SOFTWARE, SYSTEM) for persistent tweak application

### Installation Requirements Bypass
- Bypasses TPM 2.0, Secure Boot, RAM, CPU, and storage checks on the image
- Applies identical bypasses to the boot.wim setup environment

### User Experience Customizations
- Disables sponsored apps and content delivery manager (OemPreInstalled, PreInstalled, SilentInstalled, SubscribedContent IDs, consumer features, cloud content)
- Removes pre-pinned start menu suggestions
- Disables push-to-install functionality
- Enables local account creation during OOBE (BypassNRO)
- Copies autounattend.xml to Sysprep folder for unattended setup
- Disables Reserved Storage
- Disables BitLocker device encryption by default
- Hides Chat icon from taskbar
- Removes all Edge registry entries from Uninstall keys
- Disables OneDrive folder backup prompts

### Telemetry and Data Collection
Disables telemetry and targeted advertising features:
- AdvertisingInfo
- TailoredExperiences
- Speech recognition opt-in
- Input personalization
- Ink/text collection
- DMWappushservice

### Application Installation Prevention
- Prevents automatic installation of DevHome and Outlook via Windows Update orchestrator
- Disables Copilot in Windows and Edge sidebar
- Prevents Teams and New Outlook from auto-installing

### Performance Optimizations
Applies low-latency game tweaks:
- GPU Priority = 8
- Priority = 6
- Scheduling Category = High
- SFIO Priority = High within Multimedia/SystemProfile/Tasks/Games key
- Enables GPU hardware scheduling (HwSchMode = 2)

### Game Bar and Recording Disablement
- GameDVR and Game Bar capture completely disabled (AppCapture, Enabled, FSEBehavior, IsEnabled, PerformanceMode, AutoGameMode, AllowScreenCapture)

### Storage Optimizations for SSDs
- Disables last access timestamp updates (NtfsDisableLastAccessUpdate = 1)
- Ensures TRIM is active (NtfsDisableDeleteNotification = 0)
- Disables automatic defragmentation/optimization (EnableAutoLayout = 0)

### System Stability Defaults
- EnablePreemption remains at 1 (stable default)
- Win32PrioritySeparation remains at 2 (Windows default)
  - Note: Both values can be modified in the script for more aggressive gaming optimizations

### Scheduled Task Cleanup
Removes tasks that consume system resources:
- Appraiser
- CEIP, ProgramDataUpdater
- Chkdsk Proxy, QueueReporting
- AitAgent, InventoryCollector
- StartupAppTask, CreateObjectTask
- DiskDiagnostic, StorageSense
- File History, WinSAT
- Maps tasks, Media Center tasks
- MNO Parser, Power Efficiency Analyzer
- VerifyWinRE, SpeechModelDownload
- Windows Update tasks
- Entire Defrag task

### Post-Setup Configuration
Creates SetupComplete.cmd within the mounted image (Windows\Setup\Scripts) executing once at setup completion:
- Reapplies GameDVR, Game Bar, GPU priority, HwSchMode, and SSD optimizations
- Executes bcdedit commands for platform clock and dynamic tick configuration
- Duplicates the Ultimate Performance power plan (GUID e9a42b02-d5df-448d-aa00-03f14749eb61) and sets it active

### Image Processing
- Unmounts install.wim
- Executes component cleanup with ResetBase for image size reduction
- Exports recovery-compressed ESD
- Rebuilds ISO

### Additional Features
- Creates tool.bat on desktop executing `irm https://christitus.com/win | iex` when run

### Cleanup Operations
- Removes all temporary directories (BigE11, scratchdir)
- Dismounts source ISO drive
- Removes oscdimg.exe and autounattend.xml

## Output
The script generates:
- Single ISO file named BigE11.iso in the script directory
- tool.bat utility file on the desktop
