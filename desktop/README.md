# HWID Checker Desktop

A Windows desktop interface for the existing HWID Checker scanner. The application launches the PowerShell scanner embedded in the adjacent `hwid.bat`, then presents its results in a graphical dashboard.

Desktop **1.5.0** includes BAT **3.94**. Download the complete ZIP or all-users installer from [GitHub Releases](https://github.com/justcamop555-pixel/HWID-Checker/releases/tag/desktop-v1.5.0).

The update adds clearer ID search counts and empty states, responsive ID controls, device-aware list copying, accurate coverage for older captures, and staged CSV/HTML and comparison exports. The BAT retains scan text through resizing and can fall back to normal text output if native drawing remains unavailable. Published release history is in the [changelog](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/CHANGELOG.md).

## Install or repair for all users

The new all-users setup requires administrator approval and installs the app under Program Files. It provides Start menu shortcuts, offline repair and Windows uninstall registration. Saved snapshots and per-user settings are kept during repair and uninstall. See the [setup guide](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/desktop/installer/README.md) for requirements, build instructions and validation limits. The portable ZIP remains supported.

IDs, Hardware and Review rows now open a larger detail window with a double-click or Enter. ID details explain the value's status and preserve leading zeros. Review can filter read errors, missing/default IDs, conflicts and device status separately. **Clear filters** resets both search and type. Copy success messages show a count instead of repeating the sensitive value; clipboard contents still contain the full original text.

## Start the application

Download and **extract the complete ZIP** before launching `HWID Checker.exe`. Keep its companion files together in a local folder. Starting from inside an archive or waiting for a cloud-only file to download can add delays before the application can run.

Normal launches first show a small native **Starting HWID Checker** window, before the .NET desktop runtime loads. The desktop then shows its preparation window while reading settings and checking the scanner off the UI thread. Close the loading window to cancel; no hardware scan starts automatically. Windows must still verify the launcher before it can display anything, so startup time depends on storage and system load.

Version 1.5.0 packages the self-contained runtime as ordinary files, removing first-use bundle extraction. Run **HWID Checker.exe** and keep **HWID Checker.App.exe**, the DLLs, configuration files and language folders beside it. Do not copy just the EXE. No separate .NET or Visual C++ runtime installation is required.

**Upgrading from 1.4.x:** its updater expects the old single-file package and cannot install this new layout. Use the complete 1.5.0 setup or extract the complete ZIP into a new folder. Keep your saved reports and reconnect their folder in Snapshots if needed. Version 1.5.0 supports subsequent updates in the new format.

Windows fit the work area of their current monitor and respond to DPI changes. On short screens, the dashboard page gains its own scrollbar so tables and selected values remain reachable. Text stays at the normal readable size.

1. Extract the complete portable package to a local folder.
2. Keep **HWID Checker.exe** and **hwid.bat** together.
3. Open **HWID Checker.exe**.
4. Read the Desktop welcome/privacy notice, then choose **Open dashboard**.
5. Start a scan from the dashboard.

The package targets **Windows x64** and includes its .NET desktop runtime. The scanner still requires **Windows PowerShell 5.1 or PowerShell 7**, FullLanguage mode, and the Windows CIM/WMI providers used by the console checker. Administrator access is optional; available fields depend on the hardware, Windows providers, drivers and current access.

## Use the dashboard

ID and Review searches retain the selected column sort and keep a selected row when it still matches. Hiding a row clears its selection and copy/detail target. Hardware search checks record names and nested values, including large fields. Automatic snapshot-list polling pauses while minimized and waits while the welcome notice, initial connection or another refresh is active.

For a first check, choose **Scan this PC**, wait for the results, then open **Review** to see anything that needs explanation. Choose **Save snapshot** to keep a baseline before changing hardware or drivers. Later, rescan and compare with that saved JSON file. A saved snapshot is a capture from one point in time; saving again without rescanning does not collect new readings.

The Desktop-only **Welcome to HWID Checker** message explains the read-only hardware scan, sensitive report contents and saving a baseline before sharing. Saving does not redact identifiers. After **Open dashboard**, the notice stays dismissed unless **Show this message on future app launches** is selected. **Not now** leaves it available for the next cold launch. Reopen it at any time from **Welcome & privacy**. Normal session-preserving restarts skip the startup notice. The BAT does not show this dialog.

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
| Export comparison results | Save the complete comparison and coverage notes as text, including rows hidden by search or filters. |
| Open BAT console | Check the scanner, ask before restoring missing or invalid companions, then open the separate console. |
| Theme and restart | Switch between **Midnight** and **Daylight**. **Restart app** restores the current scan, filters, selections, page and comparison in a fresh desktop process. The original stays open if the replacement cannot become ready. |
| Updates | Check newer packages, download a verified update, and install it after closing or with **Install and restart**. |

The square layout keeps table headers aligned with their card borders. Body text uses regular Segoe UI with a larger default size. In a narrow window, the scan buttons move below the page title, PC details stack vertically, and **Hardware** uses a section dropdown. While scanning, the activity table uses the overview space. Hover over shortened text for the full value, or select a table row to read and copy its details.

The selected theme also colors the native title bar and frame on supported Windows versions, including the app's Updates and Folder settings windows. Windows still provides the normal caption buttons, resizing and snap behavior. Older systems keep their supported system frame, and high-contrast mode retains system frame colors. Windows-managed file pickers and message boxes use the Windows appearance.

New owned BAT consoles use matching Midnight/Daylight background, text and status colors. They read the Desktop's saved theme; the `HWID_THEME=Midnight` or `HWID_THEME=Daylight` process override takes precedence. An already open BAT keeps its launch theme. Current-window and redirected launches retain their host appearance.

**Hardware** starts with PC details rather than internal report metadata. Names such as **Memory (RAM)** and **Graphics (GPU)** describe the captured sections; scan information and diagnostics remain available further down the list. Capture times and access level use readable labels. Identifier text and saved JSON retain the Windows-reported values.

You can cancel a running scan. The last completed scan remains available until a replacement finishes successfully. A scan can finish with unread sections; those results remain explicitly marked and should be reviewed before interpreting a comparison.

Scrolling to earlier scan rows preserves your reading position while new progress arrives. Page and button motion follows the Windows animation preference; disabling animations in Windows keeps navigation immediate.

Battery hardware is optional. A PC without a battery receives an explicit absence record. Battery fields reflect the properties Windows supplies; a device-instance ID is not a manufacturer serial number.

Comparisons show the selected identifier fields supported by the engine. Missing/default fields, unread sections and uncertain reader coverage may be left un-compared. Windows device nodes, grouping IDs and serial numbers have different meanings; a reported difference alone does not establish physical hardware replacement.

### Read live scan progress

BAT and Desktop show finished checks, data reads and failed reads separately. CHECK means data was read but some values need review; it is included in the read count. The device catalog is included in overall check counts. Narrow BAT windows use a compact progress row; very narrow windows keep the count/percentage. Older progress callers without timing metadata retain their original display.

Desktop uses **Finalizing scan** after all checks finish while it waits for a complete, validated result. Its previous snapshot stays active until that result is accepted. Late heartbeats cannot move progress backwards or turn a completed read back into a reading row. Cancellation keeps the previous completed capture. Temporary operation cleanup retries short file/folder access failures within a fixed limit and stays inside that operation folder. Successful Desktop rescans advance the scan number passed to the BAT engine; failed or cancelled attempts do not consume a completed scan number. Compact windows give the live counts their own row.
### Understand the results

Status text uses the same meanings in both themes: **READY** for an idle window, **WORKING** for an active operation, **DONE** for a successful action, **REVIEW** for information that needs explanation, and **ERROR** for an action that failed. Scan rows distinguish green **READ**, amber **CHECK**, and red **NOT READ**. Missing/default IDs remain review items; they do not automatically mean hardware failure.

Normal desktop restarts transfer the active session through an in-memory Windows named pipe restricted to the same user/elevation. They do not create a temporary snapshot file. Installing a new package uses the **Updates → Install and restart** workflow; save a snapshot first when that dialog asks, because update installation does not transfer the active session. Saved reports remain in the shared folders.

| What you see | What it means / next step |
| --- | --- |
| No scan yet | Choose **Scan this PC**. An empty table before scanning is not a clean bill of health. |
| Scan in progress | Wait or cancel. During a rescan, the last completed capture stays available until usable new results arrive. |
| Read / Check | Windows returned data. **Check** means a reported value or record needs explanation; it does not mean the query failed. |
| Not read | This part of the inventory could not be collected. Read its reason in **Review**, then retry when the provider or access issue is resolved. |
| Missing or default ID | Windows did not supply a usable value for this field. This can be normal; the app does not invent a replacement serial number. |
| No findings | No review findings were generated for the captured data. This is not a hardware health or authenticity test. |
| No changes in comparable IDs | The usable fields compared equally. Read the **not compared** information before concluding that all identifiers stayed the same. |
| No matching rows | Clear the page's search or filter to see the other captured records. |

Hardware IDs generally describe driver/model matching. Device-instance IDs identify Windows device nodes. Neither label automatically means a factory serial number. The [identifier guide](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/IDENTIFIERS.md) explains these differences.

For the engine's field definitions, warning codes and limitations, see the [main project documentation](https://github.com/justcamop555-pixel/HWID-Checker#readme) and [usage guide](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/USAGE.md).

## Keep the BAT connection working

The application reads the companion `hwid.bat` at runtime. It does not convert or rewrite the scanner into a second implementation. If the BAT is missing, incomplete or incompatible, restore the files from the same desktop package and retry.

Use **Connect BAT…** to select an existing checker when it is stored elsewhere. The EXE uses your saved connection if that file is available, then checks for an adjacent BAT. The scanning bridge loads collection/report functions from that file and runs them in a separate, hidden PowerShell process. The desktop window presents progress and results.

Use **Connect BAT…** to select the `hwid.bat` supplied with this desktop package when upgrading an older scanner. This release includes BAT **3.94**. Earlier BAT versions can still compare a JSON report by path.

**Open BAT console** checks the selected scanner with available PowerShell runtimes before opening a separate console. A source accepted by either installed runtime is kept. The standard `hwid.bat` requires its sibling launcher; a renamed BAT ignores an unused missing or invalid launcher.

If repair is needed, **Repair BAT console** explains the problem and checked location. **Not now** keeps files and the current scan unchanged. **Repair and open** restores the scanner and launcher embedded in this Desktop build under `%LOCALAPPDATA%\HWID Checker\RecoveredScanner`, verifies their bytes, connects the restored copy and opens it. It does not overwrite custom files or download a scanner. An early loader failure also requires confirmation before this fallback. An unavailable or restricted PowerShell runtime gets a runtime error instead of an ineffective file-repair prompt.

The restored connection is remembered when settings can be saved. Earlier report folders remain discoverable through the shared library; registration failures identify the old folder and offer Folder settings.

### Incomplete device identification and comparison

For present devices missing a name or model ID, both interfaces use the BAT's targeted, serialized Windows-property lookup. Recovered values identify their source. Empty or failed optional lookups retain the primary records and explain what Windows did not supply. Existing IDs and driver problem codes are kept; a recovered name does not mean a driver fault is fixed.

Comparison notes distinguish unread/absent sections from missing device matching keys and duplicate keys. Desktop retains the matching key, affected record count and previous/current source in its details and exported comparison. It also flags different computer names and reversed capture times. A result with no comparable IDs says so; it does not claim that the IDs are unchanged.

Connection checks reject empty, truncated or larger-than-8-MB BAT files before displaying a connected state. A failed connection clears stale scanner names and paths.

## Application updates

Automatic updates start enabled. Desktop checks published releases in the background and prepares a newer compatible Windows x64 package. A ready update installs after normal window closure. Open **Updates** to change this preference, check manually, or install and restart.

The updater downloads release metadata and application files from this project's GitHub releases. Scans and report content stay outside update requests. Desktop updates its installation and adjacent BAT. A separately connected BAT uses that BAT's update controls. [Update behavior and recovery](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/docs/UPDATES.md)

## Reports and local data

The **Welcome & privacy** notice appears before saved-file discovery on a first launch and can be reopened from the sidebar. Its text scrolls while the action buttons remain visible, including in compact windows. Choose whether to show it on future launches; session-preserving restarts do not repeat it.

Saving does **not** redact identifiers. Clipboard copies, snapshots and extra exports contain the full values. Keep an original JSON baseline for comparison and redact a separate copy before sharing. Hardware scanning runs locally; update checks contact GitHub without sending scan reports. OneDrive or another folder service may synchronize files saved in its folders.

Scans and exports contain identifiers such as serial numbers, UUIDs, MAC addresses, device-instance paths and the computer name. Choose an appropriate local destination and review identifying values before sharing a report or screenshot. Exports are readable TXT/JSON files.

Saving is explicit. The desktop interface uses the engine's snapshot validation and export functions, so older supported JSON captures can be selected for comparison. Existing report pairs receive new filenames rather than being overwritten.

The saved-capture library searches the shared save folder, watched folders, the BAT's report folder, its per-user fallback and adjacent installations. Both apps use the same per-user folder preferences. On Desktop, opening **Snapshots** or using **Refresh list** reloads the folders and files. The BAT has a refresh action in its comparison picker. The engine validates the selected JSON again before comparison.

Choose a shared save folder to set the starting location of the Desktop save picker and the BAT save destination. After saving to another local folder, Desktop adds it to the shared library when settings can be updated. If that update fails, the saved pair stays available and Desktop shows its location. Removing a watched folder removes it from library search. The files stay where they were saved.

Temporary bridge/request files are created under the current user's local application data directory. Compare/export operations temporarily stage the current inventory there and attempt to remove those files when the action ends, fails or is cancelled. Shared settings store folder paths in `%LOCALAPPDATA%\HWID Checker\snapshot-library.json`. Desktop settings remember the BAT connection and last save location. Report locations may be synchronized by OneDrive or another folder service configured on the PC.

Keyboard shortcuts: **Ctrl+R** scans/rescans; **Ctrl+S** saves the current snapshot. Select an ID or hardware field to read its full value and use the copy button. A new completed scan clears comparison results that referred to the previous current scan.

### Find and compare saved snapshots

- **Refreshing…** identifies background discovery. The previous list stays available while folders are read; Refresh list becomes available again when that read ends. Closing the app cancels discovery between folder/file reads. A blocked filesystem call may still take time to return.
- **Cancel comparison** stops an active comparison or row preparation. The last complete result and the current scan remain available; no partial comparison is published. Reduced-motion settings use static progress instead of an animated comparison indicator.

- Open **Snapshots** to see saved JSON captures, newest first by default. Search by PC name, date, file name or folder. Refreshing an unchanged catalog keeps the current selection, sort and scroll position.
- Select a previous capture and choose **Compare with this scan** to use the completed scan in this window. **Compare two saved…** uses the selected capture as the previous side and asks for a current saved JSON; without a selection, choose both files. A live scan is not required for two-file comparison.
- **Compare IDs** labels the previous and current sources separately. Filter **Changed values**, **Current only**, or **Previous only**, and search full identifiers, field names or device details. Selecting a row shows the complete values and exact difference.
- No search matches is different from no ID changes. Coverage notes remain available, and **Export results…** exports the complete comparison even when filters hide rows. One-sided records describe capture availability; they do not by themselves prove a physical device was added or removed.
- **Ctrl+F** focuses the search on Snapshots and Compare IDs. Restart preserves these filters along with the current capture. A new completed scan clears comparisons of the previous current scan.
## Verification

See [desktop verification](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/desktop/VERIFICATION.md) for the results of specific builds, and [test instructions](https://github.com/justcamop555-pixel/HWID-Checker/blob/main/desktop/tests/README.md) to reproduce the checks. Historical results identify their original scanner version and section count; the current scanner has 18 normal sections plus the all-known device catalog. Synthetic fixtures cover Unicode paths, cancellation, exports, identifier comparison and saved-file discovery. Live diagnostics record counts/status rather than identifiers.

The current portable build targets Windows x64. Other architectures are not packaged by this build script. The desktop runtime is bundled; Windows hardware providers and PowerShell remain system dependencies.

## Build from source

Install the **.NET 10 SDK** and **Visual Studio Build Tools with Desktop development with C++** (MSVC x64 tools and a Windows SDK) on Windows. The C compiler builds the small native startup launcher. From the repository root:

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
