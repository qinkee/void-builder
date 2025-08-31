#define RootLicenseFileName FileExists(RepoDir + '\LICENSE.rtf') ? 'LICENSE.rtf' : 'LICENSE.txt'
#define LocalizedLanguageFile(Language = "") \
    DirExists(RepoDir + "\licenses") && Language != "" \
      ? ('; LicenseFile: "' + RepoDir + '\licenses\LICENSE-' + Language + '.rtf"') \
      : '; LicenseFile: "' + RepoDir + '\' + RootLicenseFileName + '"'

[Setup]
AppId={#AppId}
AppName={#NameLong}
AppVerName={#NameVersion}
AppPublisher=Microsoft Corporation
AppPublisherURL=https://code.visualstudio.com/
AppSupportURL=https://code.visualstudio.com/
AppUpdatesURL=https://code.visualstudio.com/
DefaultGroupName={#NameLong}
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=VSCodeSetup
Compression=lzma
SolidCompression=yes
AppMutex={code:GetAppMutex}
SetupMutex={#AppMutex}setup
WizardSmallImageFile="{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp,{#RepoDir}\resources\win32\inno-void.bmp"
SetupIconFile={#RepoDir}\resources\win32\code.ico
UninstallDisplayIcon={app}\{#ExeBasename}.exe
ChangesEnvironment=true
ChangesAssociations=true
MinVersion=10.0
SourceDir={#SourceDir}
AppVersion={#Version}
VersionInfoVersion={#RawVersion}
ShowLanguageDialog=auto
ArchitecturesAllowed={#ArchitecturesAllowed}
ArchitecturesInstallIn64BitMode={#ArchitecturesInstallIn64BitMode}
WizardStyle=modern

; 静默安装相关设置
DisableWelcomePage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
DisableDirPage=yes
AlwaysShowComponentsList=no
ShowComponentSizes=no
FlatComponentsList=yes
PrivilegesRequiredOverridesAllowed=commandline

; 强制关闭应用
CloseApplications=force

#ifdef Sign
SignTool=esrp
#endif

#if "user" == InstallTarget
DefaultDirName={userpf}\{#DirName}
PrivilegesRequired=lowest
#else
DefaultDirName={pf}\{#DirName}
#endif

[Languages]
; 只使用简体中文和英文
Name: "english"; MessagesFile: "compiler:Default.isl,{#RepoDir}\build\win32\i18n\messages.en.isl" {#LocalizedLanguageFile}
Name: "simplifiedChinese"; MessagesFile: "{#RepoDir}\build\win32\i18n\Default.zh-cn.isl,{#RepoDir}\build\win32\i18n\messages.zh-cn.isl" {#LocalizedLanguageFile("chs")}

[InstallDelete]
Type: filesandordirs; Name: "{app}\resources\app\out"; Check: IsNotBackgroundUpdate
Type: filesandordirs; Name: "{app}\resources\app\plugins"; Check: IsNotBackgroundUpdate
Type: filesandordirs; Name: "{app}\resources\app\extensions"; Check: IsNotBackgroundUpdate
Type: filesandordirs; Name: "{app}\resources\app\node_modules"; Check: IsNotBackgroundUpdate
Type: filesandordirs; Name: "{app}\resources\app\node_modules.asar.unpacked"; Check: IsNotBackgroundUpdate
Type: files; Name: "{app}\resources\app\node_modules.asar"; Check: IsNotBackgroundUpdate
Type: files; Name: "{app}\resources\app\Credits_45.0.2454.85.html"; Check: IsNotBackgroundUpdate

[UninstallDelete]
Type: filesandordirs; Name: "{app}\_"

[Tasks]
; 静默安装时默认选中所有任务
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce; OnlyBelowVersion: 0,6.1
Name: "addcontextmenufiles"; Description: "{cm:AddContextMenuFiles,{#NameShort}}"; GroupDescription: "{cm:Other}"; Flags: checkedonce
Name: "addcontextmenufolders"; Description: "{cm:AddContextMenuFolders,{#NameShort}}"; GroupDescription: "{cm:Other}"; Flags: checkedonce; Check: not (IsWindows11OrLater and QualityIsInsiders)
Name: "associatewithfiles"; Description: "{cm:AssociateWithFiles,{#NameShort}}"; GroupDescription: "{cm:Other}"; Flags: checkedonce
Name: "addtopath"; Description: "{cm:AddToPath}"; GroupDescription: "{cm:Other}"; Flags: checkedonce
Name: "runcode"; Description: "{cm:RunAfter,{#NameShort}}"; GroupDescription: "{cm:Other}"; Flags: checkedonce; Check: WizardSilent

[Dirs]
Name: "{app}"; AfterInstall: DisableAppDirInheritance

[Files]
Source: "*"; Excludes: "\CodeSignSummary*.md,\tools,\tools\*,\appx,\appx\*,\resources\app\product.json"; DestDir: "{code:GetDestDir}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "{#ProductJsonPath}"; DestDir: "{code:GetDestDir}\resources\app"; Flags: ignoreversion
#ifdef AppxPackageFullname
Source: "appx\*"; DestDir: "{app}\appx"; BeforeInstall: RemoveAppxPackage; AfterInstall: AddAppxPackage; Flags: ignoreversion; Check: IsWindows11OrLater and QualityIsInsiders
#endif

[Icons]
Name: "{group}\{#NameLong}"; Filename: "{app}\{#ExeBasename}.exe"; AppUserModelID: "{#Win32AppUserModelId}"
Name: "{group}\{cm:UninstallProgram,{#NameLong}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#NameLong}"; Filename: "{app}\{#ExeBasename}.exe"; Tasks: desktopicon; AppUserModelID: "{#Win32AppUserModelId}"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#NameLong}"; Filename: "{app}\{#ExeBasename}.exe"; Tasks: quicklaunchicon; AppUserModelID: "{#Win32AppUserModelId}"

[Run]
; 静默安装完成后自动启动应用
Filename: "{app}\{#ExeBasename}.exe"; Description: "{cm:LaunchProgram,{#NameLong}}"; Flags: nowait postinstall runascurrentuser skipifsilent; Check: ShouldRunAfterUpdate

#include "code-code.iss"