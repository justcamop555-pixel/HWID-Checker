# Application updates

Desktop 1.3.0 and BAT 3.85 include a shared updater for Windows x64 packages published by this project.

## Automatic updates

Automatic updates start enabled. Desktop checks in the background after opening. The BAT starts its check after you continue from the initial scan to the main menu. A check normally runs once per day. An unavailable check is retried after an hour.

A newer package is downloaded and verified in your local application data directory. Desktop applies a ready update after its window closes normally. The BAT applies a ready update after **[0] Exit** in its standalone console.

The current scan stays in memory while the application is open. Save a snapshot before closing if you want to keep it.

## Update controls

- In Desktop, open **Updates** in the sidebar. Use **Check now**, **Download update**, or **Install and restart**. The automatic-update checkbox controls background downloads and installation after closing.
- In the BAT, open **[9] → [5]** for update status and controls. A console started in an existing PowerShell window can check and prepare an update. Use the standalone launcher for automatic installation on exit.

Both interfaces use the same automatic-update preference for the current Windows account. Update status, downloaded packages and this preference are stored under `%LOCALAPPDATA%\HWID Checker\Updates`.

The desktop package updates its adjacent scanner and runtime files. A BAT connected from another folder keeps that separate installation. Open that BAT's own update controls to update it.

### Understand version messages

The app compares the package's **major.minor.patch** version. Windows may display a fourth file-version component: `1.4.3.0` and package `1.4.3` are the same package version. They do not require a restart just because one has an extra zero. Microsoft's [Version comparison documentation](https://learn.microsoft.com/en-us/dotnet/api/system.version.compareto) explains why an unspecified component otherwise compares differently.

**Restart to use the update** is shown only when a genuinely newer executable is already installed than the one running in the open window. Save a scan if needed, then close and reopen the app. Results cached by an older running version do not by themselves establish that the current app needs another update or restart.

## Verification and recovery

The updater checks published stable release tags and Windows x64 asset names, verifies the ZIP's SHA-256 digest from GitHub, and verifies its file checksums and versions before preparing it.

The installer replaces a defined set of application files. Saved reports, snapshot folder preferences and other files in the installation folder stay in place. The BAT update path replaces its BAT, launcher and updater. The Desktop update path also replaces the EXE and bundled runtime notices.

If replacement fails, the helper attempts to restore the prior application files. Application backups and a transaction journal remain in an owned `.hwid-update-*` folder. An interrupted prepared update can be retried after the application exits. Keep those backups if a failure requests manual recovery.

Network errors, missing update files and write-permission failures appear in the update status. Scanning and report comparison remain available. An older published version is never offered as a newer update.

## Publishing a compatible package

1. Set the same package version in `desktop/HwidDesktop.csproj`, `Get-CheckerPackageVersion` in `hwid.bat`, and the `HWID_PACKAGE_VERSION` stamp in `Update-HWID.ps1`.
2. Advance the scanner's own version for scanner changes.
3. Build with `desktop/build-desktop.ps1`. Keep the generated runtime files, `Update-HWID.ps1` and `SHA256SUMS.txt` in the ZIP.
4. Publish a stable GitHub release named `desktop-vMAJOR.MINOR.PATCH` and attach `HWID-Checker-Desktop-MAJOR.MINOR.PATCH-win-x64.zip`.

The updater selects numerically newer compatible package versions. Preparing a package also checks the scanner version to prevent a BAT downgrade.
