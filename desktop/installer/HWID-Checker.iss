; Build through build-setup.ps1 using a verified desktop package.
#if VER < EncodeVer(7, 0, 0)
  #error Use Inno Setup 7 or later for long package paths
#endif
#ifndef PackageDir
  #error PackageDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#define SetupFile "HWID-Checker-Setup-" + AppVersion + "-win-x64"

[Setup]
#ifdef TestInstall
AppId=HWIDChecker.SetupVerification
AppName=HWID Checker Setup Verification
PrivilegesRequired=lowest
DefaultDirName={localappdata}\HWID Checker Setup Verification
OutputBaseFilename={#SetupFile}-TEST
#else
AppId={{492BF2C2-619B-4DDE-B594-F90D2C3AC922}
AppName=HWID Checker
PrivilegesRequired=admin
DefaultDirName={autopf}\HWID Checker
OutputBaseFilename={#SetupFile}
#endif
AppVersion={#AppVersion}
AppPublisher=HWID Checker contributors
AppPublisherURL=https://github.com/justcamop555-pixel/HWID-Checker
AppSupportURL=https://github.com/justcamop555-pixel/HWID-Checker/issues
AppUpdatesURL=https://github.com/justcamop555-pixel/HWID-Checker/releases/latest
AppModifyPath="{app}\Maintenance\{#SetupFile}.exe"
UninstallDisplayName=HWID Checker
UninstallDisplayIcon={app}\HWID Checker.exe
VersionInfoVersion={#AppVersion}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.14393
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=no
DefaultGroupName=HWID Checker
OutputDir={#OutputDir}
SetupIconFile=..\assets\Hwid.ico
WizardStyle=modern
Compression=lzma2/fast
SolidCompression=yes
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.bat,*.ps1
RestartApplications=no
SetupMutex=Global\HWIDCheckerSetup
UninstallLogging=yes
#ifdef LicensePath
LicenseFile={#LicensePath}
#endif
InfoBeforeFile=setup-notice.txt

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "installation-marker.ini"; DestDir: "{app}"; DestName: "HWID-SETUP.ini"; Flags: ignoreversion
; Keep a complete offline setup for repair even if the original download is deleted.
Source: "{srcexe}"; DestDir: "{app}\Maintenance"; DestName: "{#SetupFile}.exe"; Flags: external ignoreversion; Check: CacheSetup

#ifndef TestInstall
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut for all users"; Flags: unchecked

[Icons]
Name: "{commonprograms}\HWID Checker\HWID Checker"; Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"
Name: "{commonprograms}\HWID Checker\Repair HWID Checker"; Filename: "{app}\Maintenance\{#SetupFile}.exe"
Name: "{commondesktop}\HWID Checker"; Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"; Description: "Open HWID Checker"; Flags: postinstall nowait skipifsilent unchecked runasoriginaluser
#endif

; Never delete report folders, per-user data or arbitrary files during uninstall.
[Code]
function CacheSetup: Boolean;
begin
  Result := CompareText(ExpandConstant('{srcexe}'), ExpandConstant('{app}\Maintenance\{#SetupFile}.exe')) <> 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstalledVersion: String;
  InstalledPacked, IncomingPacked: Int64;
begin
  Result := '';
#ifndef TestInstall
  if CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), RemoveBackslashUnlessRoot(ExpandConstant('{autopf}\HWID Checker'))) <> 0 then
  begin
    Result := 'The all-users setup must install in Program Files\HWID Checker. Use the portable ZIP for another folder.';
    Exit;
  end;
#endif
  if not FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) then
    Result := 'Windows PowerShell is missing. Repair Windows PowerShell 5.1, then run setup again. No execution policies or Windows components will be changed by setup.';
  if GetVersionNumbersString(ExpandConstant('{app}\HWID Checker.exe'), InstalledVersion) then
    if StrToVersion(InstalledVersion, InstalledPacked) and StrToVersion('{#AppVersion}', IncomingPacked) then
      if ComparePackedVersion(InstalledPacked, IncomingPacked) > 0 then
        Result := 'A newer HWID Checker is installed. Use that version''s setup to repair it. Setup will not downgrade the application.';
end;

function InitializeUninstall: Boolean;
begin
  Result := True;
  if not UninstallSilent then
    Result := MsgBox('Remove HWID Checker application files and shortcuts?' + #13#10 + #13#10 +
      'Saved snapshots, exported reports and per-user settings will be kept. Close HWID Checker and save any current scan before continuing.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;
