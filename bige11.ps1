param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH
)

if (-not $SCRATCH) {
    $ScratchDisk = "C:"
} else {
    $ScratchDisk = $SCRATCH + ":"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$TempBase = "$ScratchDisk\BigE11_Temp_$timestamp"
$ScratchDir = "$TempBase\scratchdir"
$BigE11Dir = "$TempBase\BigE11"

Write-Output "Using temp folder: $TempBase"
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
New-Item -ItemType Directory -Force -Path $BigE11Dir | Out-Null

function Cleanup-Temp {
    Write-Output "Cleaning up temp folder: $TempBase"
    if (Test-Path $TempBase) {
        & takeown /f "$TempBase" /r /d y 2>&1 | Out-Null
        & icacls "$TempBase" /grant administrators:F /t /c /q 2>&1 | Out-Null
        Remove-Item -Path $TempBase -Recurse -Force -ErrorAction SilentlyContinue
        cmd /c "rd /s /q `"$TempBase`"" 2>&1 | Out-Null
    }
}

Register-EngineEvent -SupportEvent PowerShell.Exiting -Action {
    & {
        param($path)
        Write-Output "Cleaning up: $path"
        if (Test-Path $path) {
            takeown /f "$path" /r /d y 2>&1 | Out-Null
            icacls "$path" /grant administrators:F /t /c /q 2>&1 | Out-Null
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            cmd /c "rd /s /q `"$path`"" 2>&1 | Out-Null
        }
    } -ArgumentList $TempBase
} | Out-Null

function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
    } catch {
        Write-Output "Error setting registry value: $_"
    }
}

function Remove-RegistryKey {
    param (
        [string]$path
    )
    try {
        & 'reg' 'delete' $path '/f' | Out-Null
    } catch {
        Write-Output "Error removing registry key: $_"
    }
}

function Remove-RegistryValue {
    param (
        [string]$path,
        [string]$name
    )
    try {
        & 'reg' 'delete' $path '/v' $name '/f' | Out-Null
    } catch {
        Write-Output "Error removing registry value: $_"
    }
}

function Set-ServiceStart {
    param (
        [string]$service,
        [int]$startType
    )
    Set-RegistryValue "HKLM\zSYSTEM\ControlSet001\Services\$service" "Start" "REG_DWORD" $startType
}

# Check for wallpaper
$WallpaperSource = "$PSScriptRoot\w1.jpg"
$UseWallpaper = $false
if (Test-Path $WallpaperSource) {
    $UseWallpaper = $true
    Write-Output "Found w1.jpg - will integrate as default wallpaper"
} else {
    Write-Output "No w1.jpg found - skipping wallpaper integration"
}

if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Output "Execution policy is Restricted. Change to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Output "Cannot run script. Exiting..."
        Cleanup-Temp
        exit
    }
}

$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Output "Restarting as admin..."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

if (-not (Test-Path -Path "$PSScriptRoot\autounattend.xml")) {
    Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile "$PSScriptRoot\autounattend.xml"
}

Start-Transcript -Path "$PSScriptRoot\BigE11_$(get-date -f yyyyMMdd_HHmms).log"

$Host.UI.RawUI.WindowTitle = "BigE11"
Clear-Host
Write-Output "BigE11 - Windows 11 Optimization Script"
Write-Output "Temp folder: $TempBase"
Write-Output "WARNING: Edge WebView2 is completely removed from WinSxS."
Write-Output "This may affect Windows Update stability."

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
do {
    if (-not $ISO) {
        $DriveLetter = Read-Host "Enter drive letter for Windows 11 image"
    } else {
        $DriveLetter = $ISO
    }
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
    } else {
        Write-Output "Invalid drive letter. Enter a letter between C and Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

Write-Output "Step 1/11: Checking for Windows installation files..."
if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Output "Found install.esd, converting to install.wim..."
        Get-WindowsImage -ImagePath $DriveLetter\sources\install.esd
        $index = Read-Host "Enter image index"
        Write-Output 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath "$BigE11Dir\sources\install.wim" -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "Can't find Windows installation files in the specified drive."
        Cleanup-Temp
        exit
    }
}

Write-Output "Step 2/11: Copying Windows image (using robocopy for speed)..."
robocopy "$DriveLetter" "$BigE11Dir" /E /COPY:DAT /MT:8 /NP /NFL /NDL /NJH /NJS
Set-ItemProperty -Path "$BigE11Dir\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$BigE11Dir\sources\install.esd" > $null 2>&1
Write-Output "Copy complete."
Start-Sleep -Seconds 2
Clear-Host
Write-Output "Step 3/11: Getting image information..."
$ImagesIndex = (Get-WindowsImage -ImagePath "$BigE11Dir\sources\install.wim").ImageIndex
while ($ImagesIndex -notcontains $index) {
    Get-WindowsImage -ImagePath "$BigE11Dir\sources\install.wim"
    $index = Read-Host "Enter image index"
}
Write-Output "Mounting Windows image. This may take a while."
$wimFilePath = "$BigE11Dir\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Error "$wimFilePath not found"
}
New-Item -ItemType Directory -Force -Path $ScratchDir > $null
Mount-WindowsImage -ImagePath "$BigE11Dir\sources\install.wim" -Index $index -Path $ScratchDir

$imageIntl = & dism /English /Get-Intl "/Image:$ScratchDir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
if ($languageLine) {
    $languageCode = $Matches[1]
} else {
    $languageCode = "en-US"
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$BigE11Dir\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'
foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        if ($architecture -eq 'x64') { $architecture = 'amd64' }
        break
    }
}
if (-not $architecture) { $architecture = 'amd64' }

Write-Output "Step 4/11: Removing bloatware applications..."
$packages = & 'dism' '/English' "/image:$ScratchDir" '/Get-ProvisionedAppxPackages' |
    ForEach-Object { if ($_ -match 'PackageName : (.*)') { $matches[1] } }

$packagePrefixes = 'AppUp.IntelManagementandSecurityStatus','Clipchamp.Clipchamp','DolbyLaboratories.DolbyAccess','DolbyLaboratories.DolbyDigitalPlusDecoderOEM','Microsoft.BingNews','Microsoft.BingSearch','Microsoft.BingWeather','Microsoft.Copilot','Microsoft.Windows.CrossDevice','Microsoft.GamingApp','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.Microsoft3DViewer','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.MicrosoftStickyNotes','Microsoft.MixedReality.Portal','Microsoft.MSPaint','Microsoft.Office.OneNote','Microsoft.OfficePushNotificationUtility','Microsoft.OutlookForWindows','Microsoft.Paint','Microsoft.People','Microsoft.PowerAutomateDesktop','Microsoft.SkypeApp','Microsoft.StartExperiencesApp','Microsoft.Todos','Microsoft.Wallet','Microsoft.Windows.DevHome','Microsoft.Windows.Copilot','Microsoft.Windows.Teams','Microsoft.WindowsAlarms','Microsoft.WindowsCamera','microsoft.windowscommunicationsapps','Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.WindowsSoundRecorder','Microsoft.WindowsTerminal','Microsoft.Xbox.TCUI','Microsoft.XboxApp','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','MicrosoftCorporationII.MicrosoftFamily','MicrosoftCorporationII.QuickAssist','MSTeams','MicrosoftTeams','Microsoft.WindowsTerminal','Microsoft.549981C3F5F10','Microsoft.Advertising','Microsoft.Bing','Microsoft.Cortana','Microsoft.PeopleHub','Microsoft.Mail','Microsoft.Calendar','Microsoft.Windows.Photos'

$packagesToRemove = $packages | Where-Object {
    $packageName = $_
    $packagePrefixes -contains ($packagePrefixes | Where-Object { $packageName -like "*$_*" })
}
$totalPackages = $packagesToRemove.Count
$currentPackage = 0
foreach ($package in $packagesToRemove) {
    $currentPackage++
    Write-Progress -Activity "Removing bloatware" -Status "$currentPackage of $totalPackages" -PercentComplete (($currentPackage / $totalPackages) * 100)
    & 'dism' '/English' "/image:$ScratchDir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}
Write-Progress -Activity "Removing bloatware" -Completed

Write-Output "Step 5/11: Removing Edge and WebView2..."
Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$ScratchDir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

Write-Output "WARNING: Removing Edge WebView2 from WinSxS - This may break Windows Update!"
Write-Output "If you experience issues, run: sfc /scannow"
if ($architecture -eq 'amd64') {
    $foldersToRemove = Get-ChildItem -Path "$ScratchDir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory -ErrorAction SilentlyContinue
    
    foreach ($folder in $foldersToRemove) {
        Write-Output "Processing: $($folder.FullName)"
        & takeown /f "$($folder.FullName)" /r /d y 2>&1 | Out-Null
        & icacls "$($folder.FullName)" /grant "$($adminGroup.Value):(F)" /t /c /q 2>&1 | Out-Null
        & attrib -r -s -h "$($folder.FullName)\*.*" /s /d 2>&1 | Out-Null
        try {
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
            Write-Output "Removed: $($folder.FullName)"
        } catch {
            Write-Output "Fallback: using RD command for $($folder.FullName)"
            & cmd /c "rd /s /q `"$($folder.FullName)`"" 2>&1 | Out-Null
        }
    }
}

Write-Output "Removing WebView2 from System32..."
& 'takeown' '/f' "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" '/r' | Out-Null
& 'icacls' "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
Remove-Item -Path "$ScratchDir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

Write-Output "Removing OneDrive..."
& 'takeown' '/f' "$ScratchDir\Windows\System32\OneDriveSetup.exe" | Out-Null
& 'icacls' "$ScratchDir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
Remove-Item -Path "$ScratchDir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue | Out-Null

Write-Output "Step 6/11: Removing Windows Features..."
$featuresToRemove = @(
    "FaxServicesClientPackage","Printing-PrintToPDFServices-Features","Printing-XPSServices-Features",
    "WorkFolders-Client","IIS-WebServerRole","IIS-WebServer",
    "IIS-CommonHttpFeatures","IIS-HttpErrors","IIS-HttpRedirect","IIS-ApplicationDevelopment",
    "IIS-HealthAndDiagnostics","IIS-Security","IIS-Performance","IIS-WebServerManagementTools",
    "IIS-ManagementConsole","IIS-IIS6ManagementCompatibility","IIS-Metabase","IIS-WMICompatibility",
    "IIS-LegacySnapIn","IIS-FTPPublishingService","IIS-FTPServer","IIS-FTPService","IIS-WebDAV",
    "TelnetClient","TFTPClient","SimpleTCPIPServices","DirectPlay","Windows-Identity-Foundation",
    "Windows-TIFF-IFilter","XPS-Viewer","Printing-Foundation-InternetPrinting-Client",
    "Windows-Printing-XPSServices","WorkFolders-Client"
)
foreach ($feature in $featuresToRemove) {
    Write-Output "Removing feature: $feature"
    $result = & dism "/Image:$ScratchDir" "/Disable-Feature" "/FeatureName:$feature" "/Remove" "/Quiet"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to remove feature: $feature (exit code: $LASTEXITCODE)"
    }
}

Write-Output "Step 7/11: Disabling Services (via registry - offline image)..."
$servicesToDisable = @(
    "DiagTrack","diagnosticshub.standardcollector.service","DPS","WdiServiceHost","WdiSystemHost",
    "TrkWks","Fax","lfsvc","RetailDemo","XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc",
    "XboxGameCallableUI","PcaSvc","ParentalControls","WpnUserService","BcastDVRUserService",
    "MessagingService","PimIndexMaintenanceSvc","UnistoreSvc","UserDataSvc","WSearch"
)
foreach ($service in $servicesToDisable) {
    Write-Output "Disabling service: $service"
    Set-ServiceStart $service 4
}

Write-Output "Removing Biometric Services (specific files)..."
Remove-Item -Path "$ScratchDir\Windows\System32\WinBio.dll" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ScratchDir\Windows\System32\winbio.dat" -Force -ErrorAction SilentlyContinue

Write-Output "Step 8/11: Loading registry..."
reg load HKLM\zCOMPONENTS "$ScratchDir\Windows\System32\config\COMPONENTS" | Out-Null
reg load HKLM\zDEFAULT "$ScratchDir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSOFTWARE "$ScratchDir\Windows\System32\config\SOFTWARE" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDir\Windows\System32\config\SYSTEM" | Out-Null

# Wallpaper integration
if ($UseWallpaper) {
    Write-Output "Integrating custom wallpaper and theme..."
    
    # Create Web folder for wallpaper
    $WebFolder = "$ScratchDir\Windows\Web\Wallpaper\BigE11"
    New-Item -ItemType Directory -Force -Path $WebFolder | Out-Null
    
    # Copy wallpaper
    Copy-Item -Path $WallpaperSource -Destination "$WebFolder\e11w1.jpg" -Force
    
    # Set as default wallpaper in registry
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Desktop' 'Wallpaper' 'REG_SZ' '%SystemRoot%\Web\Wallpaper\BigE11\e11w1.jpg'
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Desktop' 'WallpaperStyle' 'REG_SZ' '2'  # 0=Center, 1=Tile, 2=Stretch, 6=Fit, 10=Fill
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Desktop' 'TileWallpaper' 'REG_SZ' '0'
    
    # Set for default user
    Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\Desktop' 'Wallpaper' 'REG_SZ' '%SystemRoot%\Web\Wallpaper\BigE11\e11w1.jpg'
    Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\Desktop' 'WallpaperStyle' 'REG_SZ' '2'
    Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\Desktop' 'TileWallpaper' 'REG_SZ' '0'
    
    # Orange theme - dark mode with orange accents
    # Set theme colors (orange: R=255, G=140, B=0)
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\DWM' 'AccentColor' 'REG_DWORD' '0xFF8C00'  # Orange
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\DWM' 'ColorizationColor' 'REG_DWORD' '0xC4FF8C00'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\DWM' 'ColorizationAfterglow' 'REG_DWORD' '0xC4FF8C00'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\DWM' 'ColorizationBlurBalance' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\DWM' 'EnableWindowColorization' 'REG_DWORD' '1'
    
    # Enable dark mode for default user
    Set-RegistryValue 'HKLM\zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zDEFAULT\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zDEFAULT\SOFTWARE\Microsoft\Windows\DWM' 'AccentColor' 'REG_DWORD' '0xFF8C00'
    Set-RegistryValue 'HKLM\zDEFAULT\SOFTWARE\Microsoft\Windows\DWM' 'ColorizationColor' 'REG_DWORD' '0xC4FF8C00'
    
    # Set orange as system accent color
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu' 'REG_DWORD' '0xFF8C00'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'StartColorMenu' 'REG_DWORD' '0xFF8C00'
    
    # Branding in System Properties
    Write-Output "Adding BigE11 branding to System Properties..."
    
    # Check if OEMInformation exists, create if not
    $OEMPath = 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    
    # Try to set via registry
    Set-RegistryValue $OEMPath 'Model' 'REG_SZ' 'Optimized by BigE11'
    Set-RegistryValue $OEMPath 'SupportHours' 'REG_SZ' 'Optimized by BigE11'
    Set-RegistryValue $OEMPath 'SupportPhone' 'REG_SZ' 'Optimized by BigE11'
    Set-RegistryValue $OEMPath 'SupportURL' 'REG_SZ' 'Optimized by BigE11'
    
    # Alternative: Set in CurrentVersion
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion' 'RegisteredOrganization' 'REG_SZ' 'BigE11'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion' 'RegisteredOwner' 'REG_SZ' 'BigE11 User'
    
    # Set branding in System (this appears in winver and system properties)
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'legalnoticecaption' 'REG_SZ' 'BigE11'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'legalnoticetext' 'REG_SZ' 'This system has been optimized by BigE11'
}

Write-Output "Applying registry tweaks..."
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
Remove-RegistryKey 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
Remove-RegistryKey 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDir\Windows\System32\Sysprep\autounattend.xml" -Force | Out-Null

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'

Remove-RegistryKey "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
Remove-RegistryKey "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"

Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"

Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
Remove-RegistryKey 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryKey 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'

Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 'REG_DWORD' '2'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'FSEBehaviorMode' 'REG_DWORD' '2'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'IsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'PerformanceMode' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\GameBar' 'AutoGameModeEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\GameBar' 'AllowScreenCapture' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\GameBar' 'GameDVR_Enabled' 'REG_DWORD' '0'

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 'REG_DWORD' '8'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 'REG_DWORD' '6'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'REG_SZ' 'High'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'SFIO Priority' 'REG_SZ' 'High'

Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableDeleteNotification' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout' 'EnableAutoLayout' 'REG_DWORD' '0'

Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'EnablePreemption' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 'REG_DWORD' '2'

Write-Output "Step 9/11: Removing scheduled tasks..."
$tasksPath = "$ScratchDir\Windows\System32\Tasks"
$tasksToRemove = @(
    "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program",
    "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "$tasksPath\Microsoft\Windows\Chkdsk\Proxy",
    "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting",
    "$tasksPath\Microsoft\Windows\Application Experience\AitAgent",
    "$tasksPath\Microsoft\Windows\Application Experience\InventoryCollector",
    "$tasksPath\Microsoft\Windows\Application Experience\StartupAppTask",
    "$tasksPath\Microsoft\Windows\CloudExperienceHost\CreateObjectTask",
    "$tasksPath\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "$tasksPath\Microsoft\Windows\DiskFootprint\StorageSense",
    "$tasksPath\Microsoft\Windows\FileHistory\File History",
    "$tasksPath\Microsoft\Windows\Maintenance\WinSAT",
    "$tasksPath\Microsoft\Windows\Maps\MapsToastTask",
    "$tasksPath\Microsoft\Windows\Maps\MapsUpdateTask",
    "$tasksPath\Microsoft\Windows\Media Center",
    "$tasksPath\Microsoft\Windows\Mobile Broadband Accounts\MNO Metadata Parser",
    "$tasksPath\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
    "$tasksPath\Microsoft\Windows\RecoveryEnvironment\VerifyWinRE",
    "$tasksPath\Microsoft\Windows\Speech\SpeechModelDownloadTask",
    "$tasksPath\Microsoft\Windows\Windows Update",
    "$tasksPath\Microsoft\Windows\Defrag"
)
foreach ($task in $tasksToRemove) {
    Remove-Item -Path $task -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Creating SetupComplete.cmd for first-boot tweaks..."
$setupScriptsDir = "$ScratchDir\Windows\Setup\Scripts"
New-Item -ItemType Directory -Force -Path $setupScriptsDir | Out-Null

$setupCompleteContent = @'
@echo off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v Enabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v FSEBehaviorMode /t REG_DWORD /d 2 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v IsEnabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v PerformanceMode /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\GameBar" /v AllowScreenCapture /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\GameBar" /v GameDVR_Enabled /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d High /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d High /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler" /v EnablePreemption /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" /v Win32PrioritySeparation /t REG_DWORD /d 2 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisableLastAccessUpdate /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v NtfsDisableDeleteNotification /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OptimalLayout" /v EnableAutoLayout /t REG_DWORD /d 0 /f
bcdedit /set useplatformclock true
bcdedit /set disabledynamictick yes
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61
'@

if ($UseWallpaper) {
    $setupCompleteContent += @'

REM Apply wallpaper and orange theme after first boot
reg add "HKCU\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "%SystemRoot%\Web\Wallpaper\BigE11\e11w1.jpg" /f
reg add "HKCU\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "2" /f
reg add "HKCU\Control Panel\Desktop" /v TileWallpaper /t REG_SZ /d "0" /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\DWM" /v AccentColor /t REG_DWORD /d 0xff8c00 /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\DWM" /v ColorizationColor /t REG_DWORD /d 0xc4ff8c00 /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\DWM" /v ColorizationAfterglow /t REG_DWORD /d 0xc4ff8c00 /f
reg add "HKCU\SOFTWARE\Microsoft\Windows\DWM" /v EnableWindowColorization /t REG_DWORD /d 1 /f
RUNDLL32.EXE USER32.DLL,UpdatePerUserSystemParameters
'@
}

$setupCompleteContent | Out-File -FilePath "$setupScriptsDir\SetupComplete.cmd" -Encoding ASCII

Write-Output "Step 10/11: Unmounting and exporting..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Output "Cleaning up image..."
$result = dism.exe /Image:$ScratchDir /Cleanup-Image /StartComponentCleanup /ResetBase
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Component cleanup exit code: $LASTEXITCODE"
}

Write-Output "Unmounting image..."
Dismount-WindowsImage -Path $ScratchDir -Save

Write-Output "Exporting image (default compression)..."
$result = Dism.exe /Export-Image /SourceImageFile:"$BigE11Dir\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$BigE11Dir\sources\install2.wim"
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Export exit code: $LASTEXITCODE"
}
Remove-Item -Path "$BigE11Dir\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$BigE11Dir\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Output "Processing boot.wim..."
$wimFilePath = "$BigE11Dir\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false

$bootIndex = 2
$bootInfo = Get-WindowsImage -ImagePath $wimFilePath
if ($bootInfo.ImageIndex -contains 1 -and $bootInfo | Where-Object { $_.ImageIndex -eq 2 }) {
    $bootIndex = 2
} else {
    Write-Output "Using boot index: $($bootInfo.ImageIndex[0])"
    $bootIndex = $bootInfo.ImageIndex[0]
}

Mount-WindowsImage -ImagePath "$BigE11Dir\sources\boot.wim" -Index $bootIndex -Path $ScratchDir

reg load HKLM\zDEFAULT "$ScratchDir\Windows\System32\config\default" | Out-Null
reg load HKLM\zNTUSER "$ScratchDir\Users\Default\ntuser.dat" | Out-Null
reg load HKLM\zSYSTEM "$ScratchDir\Windows\System32\config\SYSTEM" | Out-Null

Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'

reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Dismount-WindowsImage -Path $ScratchDir -Save

Write-Output "Step 11/11: Creating ISO..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$BigE11Dir\autounattend.xml" -Force | Out-Null

$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostarchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"
if ([System.IO.Directory]::Exists($ADKDepTools)) {
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Output "Downloading oscdimg.exe from symbol server..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath
        } catch {
            Write-Warning "Failed to download oscdimg.exe. ISO creation will fail."
            Cleanup-Temp
            exit
        }
    }
    $OSCDIMG = $localOSCDIMGPath
}
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$BigE11Dir\boot\etfsboot.com#pEF,e,b$BigE11Dir\efi\microsoft\boot\efisys.bin" "$BigE11Dir" "$PSScriptRoot\BigE11.iso"

$desktopPath = [Environment]::GetFolderPath("Desktop")
$toolBatContent = '@echo off
echo Running Windows Optimization Tool...
echo This will run the Chris Titus Tech Windows Utility
echo.
echo Press Ctrl+C to cancel or any key to continue...
pause >nul
powershell -Command "irm https://christitus.com/win | iex"
echo.
echo Tool completed!
pause'
$toolBatPath = Join-Path $desktopPath "tool.bat"
$toolBatContent | Out-File -FilePath $toolBatPath -Encoding ASCII

Write-Output "Performing Cleanup..."
Cleanup-Temp
Get-Volume -DriveLetter $DriveLetter[0] | Get-DiskImage | Dismount-DiskImage | Out-Null
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

Write-Output "BigE11 creation completed."
Write-Output "ISO: $PSScriptRoot\BigE11.iso"
Write-Output "Tool: $toolBatPath"

if ($UseWallpaper) {
    Write-Output "Custom wallpaper integrated: e11w1.jpg"
    Write-Output "Orange dark theme applied"
    Write-Output "BigE11 branding added to System Properties"
}

Stop-Transcript
exit
