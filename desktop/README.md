# HWID Checker Desktop

A Windows desktop interface for the existing HWID Checker scanner. The application launches the PowerShell scanner embedded in the adjacent `hwid.bat`, then presents its results in a graphical dashboard.

Desktop **1.4.3** pairs with BAT **3.88** for a shared local snapshot library and application updates. See the [changelog](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/CHANGELOG.md) for release details.

## Start the application

1. Extract the complete portable package to a local folder.
2. Keep **HWID Checker.exe** and **hwid.bat** together.
3. Open **HWID Checker.exe**.
4. Start a scan from the dashboard.

The package targets **Windows x64** and includes its .NET desktop runtime. The scanner still requires **Windows PowerShell 5.1 or PowerShell 7**, FullLanguage mode, and the Windows CIM/WMI providers used by the console checker. Administrator access is optional; available fields depend on the hardware, Windows providers, drivers and current access.

## Use the dashboard

| Task | Behavior |
| --- | --- |
| Scan or rescan | Refresh the same 18 hardware/system sections and all-known device catalog used by the BAT. Progress and per-section results remain visible while the scan runs. |
| Inspect hardware | Browse the collected system, firmware, CPU, memory, storage, graphics, network, battery and device records. Search within a section to find a record. |
| Inspect identifiers | Read the captured identifier values and their supplied/missing/default status. |
| Review findings | Inspect unread sections, missing/default values and conflicts reported by the scanning engine. |
| Save a snapshot | Export a verified TXT and JSON report pair using the BAT engine's existing report writer. |
| Export a readable report | Use **Export CSV / HTML…** to save the identifier table as CSV and the captured inventory as a standalone HTML page. Use the JSON snapshot for later comparison. |
| Share folders with the BAT | Open **Snapshots → Folder settings…** to choose a shared save folder and manage the folders both apps watch. |
| Compare snapshots | Compare an older JSON snapshot with the current scan, or choose two saved JSON snapshots without starting a scan. Results show old/new values and exact identifier differences. |
| Export comparison results | After a comparison finds changes, save its displayed results as a text report. |
| Open BAT console | Open the connected scanner in its console. The standard package includes `Start-HWID.ps1` for the standard BAT filename. |
| Theme and restart | Switch between **Midnight** and **Daylight**, or use **Restart app** in the sidebar. |
| Updates | Check newer packages, download a verified update, and install it after closing or with **Install and restart**. |

The square layout keeps table headers aligned with their card borders. In a narrow window, the scan buttons move below the page title, PC details stack vertically, and **Hardware** uses a section dropdown. While scanning, the activity table uses the overview space. Hover over truncated text for the full value, or select a table row to read and copy its details.

You can cancel a running scan. The last completed scan remains available until a replacement finishes successfully. A scan can finish with unread sections; those results remain explicitly marked and should be reviewed before interpreting a comparison.

Scrolling to earlier scan rows preserves your reading position while new progress arrives. Page and button motion follows the Windows animation preference; disabling animations in Windows keeps navigation immediate.

Battery hardware is optional. A PC without a battery receives an explicit absence record. Battery fields reflect the properties Windows supplies; a device-instance ID is not a manufacturer serial number.

Comparisons show the selected identifier fields supported by the engine. Missing/default fields, unread sections and uncertain reader coverage may be left un-compared. Windows device nodes, grouping IDs and serial numbers have different meanings; a reported difference alone does not establish physical hardware replacement.

For the engine's field definitions, warning codes and limitations, see the [main project documentation](https://github.com/justcamop555-pixel/HWID-Checker#readme) and [usage guide](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/USAGE.md).

## Keep the BAT connection working

The application reads the companion `hwid.bat` at runtime. It does not convert or rewrite the scanner into a second implementation. If the BAT is missing, incomplete or incompatible, restore the files from the same desktop package and retry.

Use **Connect BAT…** to select an existing checker when it is stored elsewhere. The EXE uses your saved connection if that file is available, then checks for an adjacent BAT. The scanning bridge loads collection/report functions from that file and runs them in a separate, hidden PowerShell process. The desktop window presents progress and results.

Use **Connect BAT…** to select the `hwid.bat` supplied with this desktop package when upgrading an older scanner. This package includes BAT **3.85**. Earlier BAT versions can still compare a JSON report by path.

**Open BAT console** uses `Start-HWID.ps1` when it is beside the standard `hwid.bat` and Windows PowerShell is available. For a renamed BAT or a missing loader, the app opens the connected BAT directly.

## Application updates

Automatic updates start enabled. Desktop checks published releases in the background and prepares a newer compatible Windows x64 package. A ready update installs after normal window closure. Open **Updates** to change this preference, check manually, or install and restart.

The updater downloads release metadata and application files from this project's GitHub releases. Scans and report content stay outside update requests. Desktop updates its installation and adjacent BAT. A separately connected BAT uses that BAT's update controls. [Update behavior and recovery](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/UPDATES.md)

## Reports and local data

Scans and exports contain identifiers such as serial numbers, UUIDs, MAC addresses, device-instance paths and the computer name. Choose an appropriate local destination and review identifying values before sharing a report or screenshot. Exports are readable TXT/JSON files.

Saving is explicit. The desktop interface uses the engine's snapshot validation and export functions, so older supported JSON captures can be selected for comparison. Existing report pairs receive new filenames rather than being overwritten.

The saved-capture library searches the shared save folder, watched folders, the BAT's report folder, its per-user fallback and adjacent installations. Both apps use the same per-user folder preferences. On Desktop, opening **Snapshots** or using **Refresh list** reloads the folders and files. The BAT has a refresh action in its comparison picker. The engine validates the selected JSON again before comparison.

Choose a shared save folder to set the starting location of the Desktop save picker and the BAT save destination. After saving to another local folder, Desktop adds it to the shared library when settings can be updated. If that update fails, the saved pair stays available and Desktop shows its location. Removing a watched folder removes it from library search. The files stay where they were saved.

Temporary bridge/request files are created under the current user's local application data directory. Compare/export operations temporarily stage the current inventory there and attempt to remove those files when the action ends, fails or is cancelled. Shared settings store folder paths in `%LOCALAPPDATA%\HWID Checker\snapshot-library.json`. Desktop settings remember the BAT connection and last save location. Report locations may be synchronized by OneDrive or another folder service configured on the PC.

Keyboard shortcuts: **Ctrl+R** scans/rescans; **Ctrl+S** saves the current snapshot. Select an ID or hardware field to read its full value and use the copy button. A new completed scan clears comparison results that referred to the previous current scan.

## Verification

See [desktop verification](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/desktop/VERIFICATION.md) for the results of specific builds, and [test instructions](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/desktop/tests/README.md) to reproduce the checks. Historical results identify their original scanner version and section count; the current scanner has 18 normal sections plus the all-known device catalog. Synthetic fixtures cover Unicode paths, cancellation, exports, identifier comparison and saved-file discovery. Live diagnostics record counts/status rather than identifiers.

The current portable build targets Windows x64. Other architectures are not packaged by this build script. The desktop runtime is bundled; Windows hardware providers and PowerShell remain system dependencies.

## Build from source

Install the **.NET 10 SDK** on Windows. From the repository root:

```powershell
.\desktop\build-desktop.ps1 -EngineDirectory .
```

The script publishes a self-contained `win-x64` executable and creates a new build directory under `desktop/artifacts`. Each package includes the desktop executable, the selected BAT, Update-HWID.ps1, the alternative launcher when available, this README and SHA-256 checksums. SDK publish files are preserved. Original license/notice files from the exact restored .NET Core and Windows Desktop runtime packages are copied under `notices/runtime-packs`; `notices/runtime-package-sources.txt` identifies their package versions and original filenames.

To choose another output location:

```powershell
.\desktop\build-desktop.ps1 -EngineDirectory . -OutputDirectory .\desktop-builds
```

To build a folder without creating a ZIP archive:

```powershell
.\desktop\build-desktop.ps1 -EngineDirectory . -NoZip
```

Every run creates its own timestamp/GUID build directory. Previous builds and snapshots are preserved. The script checks that the original and packaged BAT hashes match. It does not publish a GitHub release or push repository changes.

## Troubleshooting

- **BAT not found:** extract the whole package and keep the EXE beside `hwid.bat`.
- **PowerShell unavailable or restricted:** use an approved compatible Windows PowerShell/PowerShell installation. The app does not install a runtime or change system execution policies.
- **Some sections unread:** review the displayed read reason and the engine's full-report details. Missing optional fields can be normal.
- **Saved file rejected:** use an original HWID Checker JSON export. TXT reports are intended for reading and cannot serve as the comparison baseline.
- **Build fails:** check the .NET SDK version and publish diagnostics. A new build directory preserves the failed run for inspection.

## License

The HWID Checker repository currently does not declare a project license. This desktop interface does not add a license grant; see the repository's [license status](https://github.com/justcamop555-pixel/HWID-Checker#license). The `notices` directory contains original files supplied with the bundled runtime packages.
