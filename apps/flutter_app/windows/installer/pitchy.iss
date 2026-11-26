; Pitchy Windows installer (Inno Setup 6.3 or newer). P-08.
;
; Build the app first, then from apps/flutter_app/:
;   ISCC.exe /DAppVersion=X.Y.Z /DOutputDir=D:\dev\release\vX.Y.Z windows\installer\pitchy.iss
; Output: pitchy-X.Y.Z-windows-setup.exe (the exact name the in-app updater
; expects, P-26). The installer is unsigned (no certificate budget), so Windows
; SmartScreen warns on first run.
;
; Per-user install: no administrator prompt, so the in-app updater can start
; this file with no arguments and the update runs without a UAC prompt.

#ifndef AppVersion
  #error Pass the version: ISCC /DAppVersion=X.Y.Z pitchy.iss
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif
; Folder of the Flutter Windows release build, relative to this script.
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: Windows uses it to recognise later versions as updates.
AppId={{3F89BB40-C908-440D-B7F0-5574B3BA6340}
AppName=Pitchy
AppVersion={#AppVersion}
AppVerName=Pitchy {#AppVersion}
AppPublisher=Pitchy project team
AppPublisherURL=https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS
AppSupportURL=https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/issues
AppUpdatesURL=https://github.com/Happii-Ceasar-Ivan/Pitchy_App_A_Weather_DSS/releases
VersionInfoVersion={#AppVersion}
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Pitchy
DefaultGroupName=Pitchy
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=pitchy-{#AppVersion}-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\pitchy.exe
UninstallDisplayName=Pitchy
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Pitchy closes itself before starting an update; this also catches a copy
; the user left open.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Remove files from the previous version so nothing stale is left behind.
Type: filesandordirs; Name: "{app}\data"

[Files]
; The release checklist copies the Visual C++ runtime (msvcp140.dll,
; vcruntime140.dll, vcruntime140_1.dll) into BuildDir first, so PCs without
; the VC++ redistributable can run Pitchy. They are required here:
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#if !FileExists(AddBackslash(SourcePath) + BuildDir + "\vcruntime140.dll")
  #error vcruntime140.dll missing from the build folder: run the copy step in the release checklist
#endif

[Icons]
Name: "{group}\Pitchy"; Filename: "{app}\pitchy.exe"
Name: "{group}\Uninstall Pitchy"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Pitchy"; Filename: "{app}\pitchy.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pitchy.exe"; Description: "{cm:LaunchProgram,Pitchy}"; Flags: nowait postinstall skipifsilent
