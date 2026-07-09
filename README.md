# BigE11
BigE11 is a script that lets you place in a Windows 11 ISO (up to 25H2) that optimizes and spits out a better ISO.

# Changes:

Copies the entire Windows 11 install media (DVD/ISO) to a scratch drive.

Converts install.esd to install.wim automatically if install.wim is missing.

Lets you pick the correct image index if the source has multiple editions.

Detects the image architecture (AMD64 only – removes ARM leftovers).

Detects the default system language to remove only the correct language‑packs (Handwriting, OCR, Speech, TTS).

Removes all pre‑installed bloatware packages (AppUp, Clipchamp, Dolby, Bing News/Search/Weather, Copilot, CrossDevice, GamingApp, GetHelp, Getstarted, 3DViewer, OfficeHub, Solitaire, StickyNotes, MixedReality Portal, MSPaint, OneNote, OfficePush, Outlook, Paint, People, PowerAutomate, Skype, StartExperiences, Todos, Wallet, DevHome, Teams, Alarms, Camera, Mail/Calendar, FeedbackHub, Maps, SoundRecorder, Terminal, Xbox TCUI/App/GameOverlay/GamingOverlay/IdentityProvider/SpeechToText, YourPhone, ZuneMusic, ZuneVideo, MicrosoftFamily, QuickAssist, Advertising, Cortana, PeopleHub, Photos).

Completely removes Microsoft Edge browser and all its folders (Program Files, EdgeUpdate, EdgeCore).

Removes Microsoft Edge WebView2 from System32 and its WinSxS folder (AMD64 only).

Removes OneDriveSetup.exe from System32.

Uninstalls these Windows Features: Fax Services, Print to PDF, XPS Services, Work Folders Client, IIS (entire web server role including FTP, management tools, legacy compatibility), Telnet Client, TFTP Client, Simple TCP/IP Services, DirectPlay, Windows Identity Foundation, TIFF IFilter, XPS Viewer, Internet Printing Client.

Keeps Windows Media Player (deliberately left in).

Keeps Windows Recovery Environment (WinRE) – not touched.

Keeps Windows Defender (all services and signatures stay intact).

Disables services that eat RAM/CPU: DiagTrack, diagnosticshub, DPS, WdiServiceHost/System, TrkWks, Fax, lfsvc (Geolocation), RetailDemo, all Xbox services (Auth, GameSave, NetApi, GipSvc, GameCallableUI), PcaSvc, ParentalControls, WPNSvc, BcastDVR, Messaging, PimIndex, Unistore, UserData, Windows Search.

Removes all biometric/WinHello components (WinBio.dll and winbio* files).

Loads the offline registry hives (COMPONENTS, DEFAULT, NTUSER, SOFTWARE, SYSTEM) to apply persistent tweaks.

Bypasses TPM 2.0, Secure Boot, RAM, CPU, and storage checks on the image itself.

Bypasses the same checks on the boot.wim setup environment.

Disables sponsored apps and content delivery manager (OemPreInstalled, PreInstalled, SilentInstalled, all SubscribedContent IDs, consumer features, cloud content).

Removes the pre‑pinned start menu suggestions and disables push‑to‑install.

Enables local account creation during OOBE (BypassNRO).

Copies autounattend.xml to Sysprep folder for unattended setup.

Disables Reserved Storage.

Disables BitLocker device encryption by default.

Hides the Chat icon from taskbar.

Removes all Edge leftover registry entries from Uninstall keys.

Disables OneDrive folder backup prompts.

Disables telemetry and targeted ads (AdvertisingInfo, TailoredExperiences, speech recognition opt‑in, input personalization, ink/text collection, DMWappushservice).

Prevents automatic installation of DevHome and Outlook via Windows Update orchestrator.

Disables Copilot in Windows and Edge sidebar.

Prevents Teams and New Outlook from auto‑installing.

Applies low‑latency game tweaks: GPU Priority = 8, Priority = 6, Scheduling Category = High, SFIO Priority = High inside the Multimedia/SystemProfile/Tasks/Games key.

Enables GPU hardware scheduling (HwSchMode = 2).

Disables GameDVR and Game Bar capture completely (AppCapture, Enabled, FSEBehavior, IsEnabled, PerformanceMode, AutoGameMode, AllowScreenCapture).

SSD‑specific optimisations: disables last access timestamp updates (NtfsDisableLastAccessUpdate = 1), ensures TRIM is active (NtfsDisableDeleteNotification = 0), disables automatic defrag/optimisation (EnableAutoLayout = 0).

Leaves EnablePreemption at 1 (stable default) and Win32PrioritySeparation at 2 (Windows default) – you can edit those two lines in the script if you want the aggressive gaming values instead.

Deletes all scheduled tasks that waste cycles: Appraiser, CEIP, ProgramDataUpdater, Chkdsk Proxy, QueueReporting, AitAgent, InventoryCollector, StartupAppTask, CreateObjectTask, DiskDiagnostic, StorageSense, File History, WinSAT, Maps tasks, Media Center tasks, MNO Parser, Power Efficiency Analyzer, VerifyWinRE, SpeechModelDownload, Windows Update tasks, and the entire Defrag task.

Creates SetupComplete.cmd inside the mounted image (Windows\Setup\Scripts) – this runs once at the end of Windows setup, before the first logon, applying:

All the GameDVR, Game Bar, GPU priority, HwSchMode, SSD tweaks again (to cover any first‑boot resets).

bcdedit /set useplatformclock true and disabledynamictick yes.

Duplicates the Ultimate Performance power plan (GUID e9a42b02‑d5df‑448d‑aa00‑03f14749eb61) and sets it active.

Unmounts the install.wim, runs a component cleanup with ResetBase to shrink the image, exports a recovery‑compressed ESD, then rebuilds the ISO.

Creates a tool.bat on your desktop that runs irm https://christitus.com/win | iex when executed.

Cleans up all temporary folders (BigE11, scratchdir), dismounts the source ISO drive, removes oscdimg.exe and autounattend.xml.

Final output: one ISO file named BigE11.iso in the script’s directory, plus the tool.bat on your desktop.
