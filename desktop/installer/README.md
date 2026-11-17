# Windows setup, repair and removal

One installer offers two installation types. **Just for me** is selected by default and runs without administrator access when launched normally. **All users** requests administrator approval. Normal scans run as the current user. The portable ZIP remains available.

| Choice | Installation folder | Permissions | Uninstall entry |
| --- | --- | --- | --- |
| Just for me | `%LOCALAPPDATA%\Programs\HWID Checker` | Current user; no administrator required | HWID Checker (current user) |
| All users | `Program Files\HWID Checker` | Administrator approval required | HWID Checker (all users) |

The two installations have separate locations and Windows uninstall registrations. Removing one keeps the other installation and saved reports. Settings and report-folder choices are shared by that Windows user's Desktop/BAT copies.

## Install

Run `HWID-Checker-Setup-<version>-win-x64.exe` normally, choose **Just for me** or **All users**, read the notice, and install. A desktop shortcut is optional. The personal Start menu entries include **(current user)**; all-users entries keep the existing HWID Checker names so older shortcuts upgrade consistently.

Setup includes the .NET runtime and accepts an existing Windows PowerShell or PowerShell 7 installation. It checks the Windows location, the usual PowerShell 7 folder and PATH. Presence does not guarantee that Windows policy permits execution. Scanning needs Windows PowerShell 5.1 or PowerShell 7 in FullLanguage mode and working Windows providers. Setup does not install Windows components or change execution policies.

For scripted installs, `/CURRENTUSER` chooses personal mode and `/ALLUSERS` chooses machine mode. All-users mode still requires Windows authorization. Use the same mode when upgrading an existing installation. Selecting the other mode creates a separate copy rather than moving the existing one.

Setup requires x64-compatible Windows and at least Windows 10 build 14393 for the launcher's APIs. This is a technical minimum, not a claim of support for every old Windows edition. The bundled .NET runtime follows Microsoft's [supported OS and lifecycle requirements](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md).

| System | Behavior or validation |
| --- | --- |
| Windows 10 build 14393 or later / Windows 11 x64 | Installer accepts the technical minimum; use an edition still supported by the bundled runtime. Local lifecycle checks ran on the development Windows build. |
| Windows 7, 8/8.1, or Windows 10 below build 14393 | Setup blocks installation with a clear minimum-version message. |
| 32-bit Windows | The x64 package is blocked. |
| Windows 11 ARM64 | x64 emulation is allowed by the installer; it has not been tested on ARM hardware. |
| Windows Server | Requires the minimum build and a usable desktop environment. Server editions and Server Core have not been validated. |
| Restricted or S-mode Windows | Windows policy may block this EXE or PowerShell. Setup does not bypass those restrictions. |

The application and setup are not code-signed by this project.

## Repair

Run the same setup again in the existing installation's mode, choose its **Repair HWID Checker** shortcut, or open **Setup & repair > Repair installed application** in Desktop. Repair from Desktop, Start or Windows installed apps preserves the recorded installation mode. Personal repair does not force elevation; machine repair asks for administrator approval.

Setup reinstalls its managed files and shortcuts and rejects downgrades. It keeps the complete setup in that installation's `Maintenance` folder for offline repair. If both the app and cached setup are missing, download setup again. Save the current scan before allowing setup to close the app.

Install, repair and uninstall check a running-Desktop guard for the selected installation folder. Save and close that Desktop window first. A Desktop in another installation folder has a separate guard. Close BAT consoles before replacing or removing their files. Other Windows sessions and unsupported environments have not been exercised by this guard's tests.

Desktop detects a missing scanner at startup. **Open BAT console** checks the scanner and asks before restoring its bundled offline copy to the current user's local data folder. This is separate from repairing the full installation and cannot repair a blocked Windows runtime or device driver.

## Reports, privacy and updates

- Installed Desktop and BAT default to `%LOCALAPPDATA%\HWID Checker\HWID-Reports` for the current Windows user. Existing shared-library folder choices take precedence.
- Settings and folder registrations remain per-user. Setup does not write into another user's profile or migrate/delete portable copies.
- Reports and clipboard copies contain full identifiers. Reports are not encrypted by HWID Checker; access follows the selected folder's Windows permissions. Cloud-folder and clipboard sync are managed by Windows or the corresponding service.
- Installed copies check versions; install updates using the newer setup in the same mode. Only All users requires administrator approval. The portable updater retains setup ownership and refuses writes to installed copies, including default install paths with a missing marker.

## Uninstall

Open **Windows Settings > Apps > Installed apps**, choose **HWID Checker (current user)** or **HWID Checker (all users)**, then **Uninstall**. A normally installed personal copy can be removed without administrator access. All-users removal requires administrator approval.

Uninstall removes the selected copy's installed files and shortcuts. It keeps snapshots, exports, custom files and per-user settings. There is no recursive user-data cleanup. If both copies are present, removing one does not uninstall the other. If setup itself was deliberately started elevated, Windows may require elevation to remove that installation.

## Build and verify

First build a complete package with `desktop/build-desktop.ps1`. Install [Inno Setup 7 or later](https://jrsoftware.org/isdl.php) for long-path support, then run:

```powershell
.\desktop\build-setup.ps1 -PackageDirectory '<build>\HWID Checker Desktop' -CompilerPath '<Inno Setup>\ISCC.exe' -OutputDirectory '<setup-output>'
```

The build checks the package manifest, rejects unlisted files and user-data folders, and writes a separate setup checksum. Do not point it at a live installation.

`-TestInstall` creates a clearly named `-TEST.exe` with a separate application identity and per-user privileges, for isolated install/repair/uninstall tests. It creates no Start menu or desktop shortcuts and must never be published. `desktop/tests/test-setup-current-user.ps1` verifies the production install/repair/uninstall under a standard user token, and refuses to run over an existing personal installation. Real all-users UAC, HKLM registration and multiple sessions require separate manual validation.

Production setup uses Inno Setup's [administrative install mode](https://jrsoftware.org/ishelp/topic_admininstallmode.htm), [application-close handling](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm) and tracked-file uninstaller. It deliberately avoids wildcard [uninstall deletion](https://jrsoftware.org/ishelp/topic_uninstalldeletesection.htm).
