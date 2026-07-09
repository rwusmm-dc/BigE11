param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH
)

if (-not $SCRATCH) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $SCRATCH + ":"
}

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

function Remove-RegistryValue {
    param (
        [string]$path
    )
    try {
        & 'reg' 'delete' $path '/f' | Out-Null
    } catch {
        Write-Output "Error removing registry value: $_"
    }
}

if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Output "Execution policy is Restricted. Change to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Output "Cannot run script. Exiting..."
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

if (-not (Test-Path -Path "$PSScriptRoot/autounattend.xml")) {
    Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile "$PSScriptRoot/autounattend.xml"
}

Start-Transcript -Path "$PSScriptRoot\BigE11_$(get-date -f yyyyMMdd_HHmms).log"

$Host.UI.RawUI.WindowTitle = "BigE11"
Clear-Host
Write-Output "BigE11 - Windows 11 Optimization Script"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\BigE11\sources" | Out-Null
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
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath $ScratchDisk\BigE11\sources\install.wim -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "Can't find Windows installation files in the specified drive."
        exit
    }
}

Write-Output "Step 2/11: Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\BigE11" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\BigE11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$ScratchDisk\BigE11\sources\install.esd" > $null 2>&1
Write-Output "Copy complete."
Start-Sleep -Seconds 2
Clear-Host
Write-Output "Step 3/11: Getting image information..."
$ImagesIndex = (Get-WindowsImage -ImagePath $ScratchDisk\BigE11\sources\install.wim).ImageIndex
while ($ImagesIndex -notcontains $index) {
    Get-WindowsImage -ImagePath $ScratchDisk\BigE11\sources\install.wim
    $index = Read-Host "Enter image index"
}
Write-Output "Mounting Windows image. This may take a while."
$wimFilePath = "$ScratchDisk\BigE11\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Error "$wimFilePath not found"
}
New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath $ScratchDisk\BigE11\sources\install.wim -Index $index -Path $ScratchDisk\scratchdir

$imageIntl = & dism /English /Get-Intl "/Image:$($ScratchDisk)\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
if ($languageLine) {
    $languageCode = $Matches[1]
} else {
    $languageCode = "en-US"
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($ScratchDisk)\BigE11\sources\install.wim" "/index:$index"
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
$packages = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Get-ProvisionedAppxPackages' |
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
    & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}
Write-Progress -Activity "Removing bloatware" -Completed

Write-Output "Step 5/11: Removing Edge and WebView2..."
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
& 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' | Out-Null
& 'icacls' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
if ($architecture -eq 'amd64') {
    $folderPath = Get-ChildItem -Path "$ScratchDisk\scratchdir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName
    if ($folderPath) {
        & 'takeown' '/f' $folderPath '/r' >null
        & icacls $folderPath  "/grant" "$($adminGroup.Value):(F)" '/T' '/C' >null
        Remove-Item -Path $folderPath -Recurse -Force >null
    }
}

Write-Output "Removing OneDrive..."
& 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" | Out-Null
& 'icacls' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force | Out-Null

Write-Output "Step 6/11: Removing Windows Features..."
$featuresToRemove = @(
    "FaxServicesClientPackage","Printing-Foundation-Features","Printing-PrintToPDFServices-Features",
    "Printing-XPSServices-Features","WorkFolders-Client","IIS-WebServerRole","IIS-WebServer",
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
    & dism "/Image:$($ScratchDisk)\scratchdir" "/Disable-Feature" "/FeatureName:$feature" "/Remove" "/Quiet" | Out-Null
}

Write-Output "Step 7/11: Disabling Services..."
$servicesToDisable = @(
    "DiagTrack","diagnosticshub.standardcollector.service","DPS","WdiServiceHost","WdiSystemHost",
    "TrkWks","Fax","lfsvc","RetailDemo","XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc",
    "XboxGameCallableUI","PcaSvc","ParentalControls","WpnUserService_*","BcastDVRUserService_*",
    "MessagingService_*","PimIndexMaintenanceSvc_*","UnistoreSvc_*","UserDataSvc_*","WSearch"
)
foreach ($service in $servicesToDisable) {
    Write-Output "Disabling service: $service"
    & sc.exe config $service start= disabled | Out-Null
    & sc.exe stop $service | Out-Null
}

Write-Output "Removing Biometric Services..."
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\WinBio.dll" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\winbio*" -Force -ErrorAction SilentlyContinue

Write-Output "Step 8/11: Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM | Out-Null

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
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\scratchdir\Windows\System32\Sysprep\autounattend.xml" -Force | Out-Null

Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'

Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'

Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"

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
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'

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

# Safer defaults for these two tweaks – edit the lines below if you want more aggressive values
Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler' 'EnablePreemption' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 'REG_DWORD' '2'

Write-Output "Step 9/11: Removing scheduled tasks..."
$tasksPath = "$ScratchDisk\scratchdir\Windows\System32\Tasks"
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
$setupScriptsDir = "$ScratchDisk\scratchdir\Windows\Setup\Scripts"
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
$setupCompleteContent | Out-File -FilePath "$setupScriptsDir\SetupComplete.cmd" -Encoding ASCII

Write-Output "Step 10/11: Unmounting and exporting..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Output "Cleaning up image..."
dism.exe /Image:$ScratchDisk\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null

Write-Output "Unmounting image..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save

Write-Output "Exporting image..."
Dism.exe /Export-Image /SourceImageFile:"$ScratchDisk\BigE11\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$ScratchDisk\BigE11\sources\install2.wim" /Compress:recovery | Out-Null
Remove-Item -Path "$ScratchDisk\BigE11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\BigE11\sources\install2.wim" -NewName "install.wim" | Out-Null

Write-Output "Processing boot.wim..."
$wimFilePath = "$ScratchDisk\BigE11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false
Mount-WindowsImage -ImagePath $ScratchDisk\BigE11\sources\boot.wim -Index 2 -Path $ScratchDisk\scratchdir

reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM | Out-Null

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

Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save

Write-Output "Step 11/11: Creating ISO..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\BigE11\autounattend.xml" -Force | Out-Null

$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostarchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"
if ([System.IO.Directory]::Exists($ADKDepTools)) {
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath
    }
    $OSCDIMG = $localOSCDIMGPath
}
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\BigE11\boot\etfsboot.com#pEF,e,b$ScratchDisk\BigE11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\BigE11" "$PSScriptRoot\BigE11.iso"

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
Remove-Item -Path "$ScratchDisk\BigE11" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null
Get-Volume -DriveLetter $DriveLetter[0] | Get-DiskImage | Dismount-DiskImage | Out-Null
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

Write-Output "BigE11 creation completed."
Write-Output "ISO: $PSScriptRoot\BigE11.iso"
Write-Output "Tool: $toolBatPath"

Stop-Transcript
exit
