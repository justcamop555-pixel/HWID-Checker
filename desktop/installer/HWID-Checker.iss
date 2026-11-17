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
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UsePreviousPrivileges=no
DefaultDirName={autopf}\HWID Checker
OutputBaseFilename={#SetupFile}
#endif
AppVersion={#AppVersion}
AppPublisher=HWID Checker contributors
AppPublisherURL=https://github.com/justcamop555-pixel/HWID-Checker
AppSupportURL=https://github.com/justcamop555-pixel/HWID-Checker/issues
AppUpdatesURL=https://github.com/justcamop555-pixel/HWID-Checker/releases/latest
AppModifyPath="{app}\Maintenance\{#SetupFile}.exe" {code:ScopeArgument}
UninstallDisplayName=HWID Checker ({code:ScopeLabel})
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

[Messages]
WindowsVersionNotSupported=HWID Checker Desktop needs Windows 10 build 14393 or newer. Windows 7, Windows 8/8.1 and older Windows 10 builds cannot run this desktop package.
OnlyOnTheseArchitectures=This package needs x64-compatible Windows. It cannot run on 32-bit Windows. Windows 11 on ARM64 needs working x64 emulation.%n%nRequired architecture: %1
PrivilegesRequiredOverrideTitle=Choose who can use HWID Checker
PrivilegesRequiredOverrideInstruction=Choose an installation type
PrivilegesRequiredOverrideText1=Choose Just for me to install without administrator access, or All users with administrator approval.
PrivilegesRequiredOverrideText2=Choose Just for me to install without administrator access, or All users with administrator approval.
PrivilegesRequiredOverrideAllUsers=&All users (administrator required)
PrivilegesRequiredOverrideAllUsersRecommended=&All users (administrator required)
PrivilegesRequiredOverrideCurrentUser=&Just for me (no administrator needed)
PrivilegesRequiredOverrideCurrentUserRecommended=&Just for me (no administrator needed, recommended)

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "installation-marker.ini"; DestDir: "{app}"; DestName: "HWID-SETUP.ini"; Flags: ignoreversion
; Keep a complete offline setup for repair even if the original download is deleted.
Source: "{srcexe}"; DestDir: "{app}\Maintenance"; DestName: "{#SetupFile}.exe"; Flags: external ignoreversion; Check: CacheSetup

[INI]
Filename: "{app}\HWID-SETUP.ini"; Section: "Installation"; Key: "Scope"; String: "{code:ScopeValue}"

#ifndef TestInstall
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{autoprograms}\HWID Checker\{code:AppShortcutName}"; Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\HWID Checker\{code:RepairShortcutName}"; Filename: "{app}\Maintenance\{#SetupFile}.exe"; Parameters: "{code:ScopeArgument}"
Name: "{autodesktop}\{code:AppShortcutName}"; Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\HWID Checker.exe"; WorkingDir: "{app}"; Description: "Open HWID Checker"; Flags: postinstall nowait skipifsilent unchecked runasoriginaluser
#endif

; Never delete report folders, per-user data or arbitrary files during uninstall.
[Code]
function ScopeValue(Param: String): String;
begin
  if IsAdminInstallMode then Result := 'AllUsers' else Result := 'CurrentUser';
end;

function ScopeLabel(Param: String): String;
begin
  if IsAdminInstallMode then Result := 'all users' else Result := 'current user';
end;

function ScopeArgument(Param: String): String;
begin
  if IsAdminInstallMode then Result := '/ALLUSERS' else Result := '/CURRENTUSER';
end;

function AppShortcutName(Param: String): String;
begin
  if IsAdminInstallMode then Result := 'HWID Checker' else Result := 'HWID Checker (current user)';
end;

function RepairShortcutName(Param: String): String;
begin
  if IsAdminInstallMode then Result := 'Repair HWID Checker' else Result := 'Repair HWID Checker (current user)';
end;

function CacheSetup: Boolean;
begin
  Result := CompareText(ExpandConstant('{srcexe}'), ExpandConstant('{app}\Maintenance\{#SetupFile}.exe')) <> 0;
end;

function WindowsCompatibilityProblem(Major, Build: Cardinal): String;
begin
  Result := '';
  if (Major < 10) or ((Major = 10) and (Build < 14393)) then
    Result := 'This desktop package needs Windows 10 build 14393 or newer. Use a Windows version supported by the included .NET runtime.';
end;

function PowerShellPresenceProblem(WindowsPowerShellFound, PowerShell7Found: Boolean): String;
begin
  Result := '';
  if not WindowsPowerShellFound and not PowerShell7Found then
    Result := 'Windows PowerShell 5.1 or PowerShell 7 is required for scanning. Install or enable an approved runtime, then run setup again. Setup does not change Windows policies.';
end;

function TargetMutexName: String;
var
  Directory: String;
  I, Ch: Integer;
begin
  Directory := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  for I := 1 to Length(Directory) do
  begin
    Ch := Ord(Directory[I]);
    if (Ch >= 97) and (Ch <= 122) then Directory[I] := Chr(Ch - 32);
  end;
  Result := 'Local\HWID-Desktop-' + Lowercase(GetSHA256OfUnicodeString(Directory));
end;

function TargetIsRunning: Boolean;
begin
  Result := CheckForMutexes(TargetMutexName);
end;

function InitializeSetup: Boolean;
var
  Version: TWindowsVersion;
  Problem: String;
begin
#ifdef TestInstall
  // Exercise the actual Pascal policy at boundaries without an older OS VM.
  if (WindowsCompatibilityProblem(6, 7601) = '') or
     (WindowsCompatibilityProblem(6, 9600) = '') or
     (WindowsCompatibilityProblem(10, 14392) = '') or
     (WindowsCompatibilityProblem(10, 14393) <> '') or
     (WindowsCompatibilityProblem(10, 22000) <> '') or
     (PowerShellPresenceProblem(False, False) = '') or
     (PowerShellPresenceProblem(True, False) <> '') or
     (PowerShellPresenceProblem(False, True) <> '') then
    RaiseException('Installer compatibility policy verification failed.');
  Log('PASS: 8 Windows/runtime policy cases.');
#endif
  GetWindowsVersionEx(Version);
  Problem := WindowsCompatibilityProblem(Version.Major, Version.Build);
  Result := Problem = '';
  if not Result then SuppressibleMsgBox(Problem, mbCriticalError, MB_OK, IDOK);
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
    Result := 'This setup must use its selected installation folder. Choose Just for me for your personal Programs folder, or All users for Program Files. Use the portable ZIP for another folder.';
    Exit;
  end;
#endif
  Result := PowerShellPresenceProblem(
    FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')),
    FileExists(ExpandConstant('{commonpf64}\PowerShell\7\pwsh.exe')) or (FileSearch('pwsh.exe', GetEnv('PATH')) <> ''));
  if Result <> '' then Exit;
  if TargetIsRunning then
  begin
    Result := 'This copy of HWID Checker Desktop is running. Save its current scan, close its window, then retry setup. Other installation folders are separate.';
    Exit;
  end;
  if GetVersionNumbersString(ExpandConstant('{app}\HWID Checker.exe'), InstalledVersion) then
    if StrToVersion(InstalledVersion, InstalledPacked) and StrToVersion('{#AppVersion}', IncomingPacked) then
      if ComparePackedVersion(InstalledPacked, IncomingPacked) > 0 then
        Result := 'A newer HWID Checker is installed. Use that version''s setup to repair it. Setup will not downgrade the application.';
end;

function InitializeUninstall: Boolean;
begin
  if TargetIsRunning then
  begin
    SuppressibleMsgBox('This copy of HWID Checker Desktop is running. Save your current scan and close that window before uninstalling. No files were removed.', mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;
  Result := True;
  if not UninstallSilent then
    Result := MsgBox('Remove HWID Checker application files and shortcuts?' + #13#10 + #13#10 +
      'Saved snapshots, exported reports and per-user settings will be kept. Close HWID Checker and save any current scan before continuing.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;
