# Windows setup, repair and removal

The all-users setup installs Desktop and the BAT scanner under `Program Files\HWID Checker`. Windows requests administrator approval. Normal scans still run as the current user. The portable ZIP remains available. Moving from the 1.4.x single-file package to 1.5.0 requires the complete setup or a newly extracted ZIP; the older updater cannot install the new runtime folder layout.

## Install

Run `HWID-Checker-Setup-<version>-win-x64.exe`, read the setup notice, and install. The Start menu includes **HWID Checker** and **Repair HWID Checker**. A desktop shortcut is optional. Setup includes the .NET runtime and checks that Windows PowerShell exists; it does not install Windows components or change execution policies. The scanner also needs PowerShell 5.1 or newer in FullLanguage mode and working Windows providers.

Setup targets Windows 10/11 on x64-compatible systems and requires Windows build 14393 or later for the native launcher's DPI APIs. The bundled .NET runtime has its own [Windows lifecycle requirements](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md). A target declaration is not a claim that every Windows edition, policy or device has been tested. The application and setup are not code-signed by this project.

## Repair

Run the same setup again, choose **Repair HWID Checker** in Start, or open **Setup & repair → Repair installed application** in Desktop. Setup reinstalls its managed files and shortcuts and rejects downgrades. It keeps a copy of the complete setup in the admin-owned `Maintenance` folder for offline repair. If both the app and cached setup are missing, download setup again. Save the current scan before allowing setup to close the app.

Desktop detects a missing scanner at startup. **Open BAT console** checks the scanner and asks before restoring its bundled offline copy to the current user's local data folder. This is separate from repairing the full installation and cannot repair a blocked Windows runtime or device driver.

## Reports, privacy and updates

- Installed Desktop and BAT default to `%LOCALAPPDATA%\HWID Checker\HWID-Reports` for the current Windows user. Existing shared-library folder choices take precedence.
- Settings and folder registrations remain per-user. Setup does not write into another user's profile or migrate/delete portable copies.
- Reports and clipboard copies contain full identifiers. Reports are not encrypted by HWID Checker; access follows the selected folder's Windows permissions. Cloud-folder and clipboard sync are managed by Windows or the corresponding service.
- Installed copies check versions, but updates require the newer setup and administrator approval. The portable updater refuses writes to a setup-managed installation or Program Files, including when its installation marker is missing.

## Uninstall

Open **Windows Settings → Apps → Installed apps**, select **HWID Checker**, and choose **Uninstall**. Administrator approval is required. Uninstall removes files and shortcuts installed by setup. It keeps snapshots, exported reports, custom files and per-user settings. There is no recursive user-data cleanup. Remove retained files yourself only when you no longer need them.

## Build and verify

First build a complete package with `desktop/build-desktop.ps1`. Install [Inno Setup 7 or later](https://jrsoftware.org/isdl.php) for long-path support, then run:

```powershell
.\desktop\build-setup.ps1 -PackageDirectory '<build>\HWID Checker Desktop' -CompilerPath '<Inno Setup>\ISCC.exe' -OutputDirectory '<setup-output>'
```

The build checks the package manifest, rejects unlisted files and user-data folders, and writes a separate setup checksum. Do not point it at a live installation.

`-TestInstall` creates a clearly named `-TEST.exe` with a separate application identity and per-user privileges, for isolated install/repair/uninstall tests. It creates no Start menu or desktop shortcuts. It must never be published as the all-users installer. Test-mode results do not verify production UAC prompts, HKLM registration or other users' sessions.

Production setup uses Inno Setup's [administrative install mode](https://jrsoftware.org/ishelp/topic_admininstallmode.htm), [application-close handling](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm) and tracked-file uninstaller. It deliberately avoids wildcard [uninstall deletion](https://jrsoftware.org/ishelp/topic_uninstalldeletesection.htm).
