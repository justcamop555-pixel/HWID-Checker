# Using HWID Checker

[Back to the main README](../README.md)

## Read a scan

Use **[1]** for the overview. It separates normal query coverage, identifier fields, present devices and the all-known extended catalog. Startup and full rescans collect the 17 normal sections plus this catalog automatically. The overall progress bar has 18 stages and reaches 100% after the catalog attempt finishes; READ/NOT READ shows whether collection succeeded.

After the startup scan, the finished scan stays visible until you press **Enter** to continue to the main menu. After a rescan, press **Enter** to continue to the snapshot changes. You can scroll before continuing. Release Enter if it was held during scanning; the dedicated console clears scan-time keystrokes so they cannot skip this step. Redirected runs do not pause for this prompt.

In the dedicated console, you can also navigate **during** background scanning with the mouse wheel/scrollbar, Up/Down, Page Up/Down, Home and End. Scrolling back pauses following so new rows and timers preserve your chosen view. **End** resumes following the latest output. Scan history stays close to the content actually written, with a small reserve for the next line, rather than thousands of blank rows. Enter and menu numbers are ignored while collection runs; keyboard processing is bounded so holding a key cannot monopolize the scan loop. If the live worker is unavailable and direct queries are used, keyboard navigation is processed between queries; host mouse scrolling remains available.

Narrow windows retain wrapped scan text. Resizing skips stale timer coordinates; subsequent output remains readable, and the completed report can still be scrolled. Full-screen reports keep their existing history behavior; the main menu clears completed scan history when opened.

If a provider rejects requested fields, the checker retries once using the properties that provider exposes. It keeps the same device filter, namespace and reader. **Compatible read** means that retry succeeded; unsupported fields can still be missing. The finish screen counts recovered sections, and **[5] Full inventory report** includes retry diagnostics under Scan timing. These details are also saved in TXT/JSON. Access failures, timeouts and missing providers keep their normal warnings.

If live progress updates fail, the query continues and keeps its hardware results. The finish screen reports affected sections, and **[5] Scan timing** retains a separate progress-display warning. Provider-read failures still use their own READ codes.

A returned record containing only empty fields receives **READ-06**, instead of inflating readable-section coverage. Real zero/false values remain data; an identifiable component with an omitted serial remains readable and its missing ID is shown separately. In the present-device scan, malformed hardware/compatible ID-list entries are excluded from usable model IDs, retained in raw fields in **[5]**, and listed in **[4]** for review. Valid neighboring IDs and other devices are preserved.

If the normal Win32 present-device query is unsupported or returns no records, the checker tries **Get-PnpDevice -PresentOnly** when available. Successful recovery is marked **fallback reader**, with its source in **[5]** and saved reports. The normal scan keeps its present-device scope; **[9] > [4]** remains the separate scan for known hidden/disconnected records. Access/timeouts stay explicit, and an unavailable fallback never becomes an empty successful scan. Older systems without either usable reader retain the failure and recovery guidance.

Standard WMI unsupported/missing-provider HRESULTs also enable this fallback on non-English Windows. WMI operation/provider timeouts are **READ-02**; missing access/privileges are **READ-01**. Those failures do not trigger a property retry or present-device fallback. Technical messages remain in **[5]** and saved reports; an unrecognized error remains **READ-05**.

Both present-device readers exclude rows whose `Present` value is explicitly Boolean false. If the Win32 read contains only disconnected rows, the checker tries the present-only fallback rather than counting those rows as connected devices. An empty fallback remains **READ-04**. Missing presence is not converted to false; the all-known catalog still retains remembered/disconnected records separately.

Numeric display metadata must be a supported scalar. A one-item list cannot become a RAM/disk size, link speed, drive letter or storage/network status. Invalid values remain unknown while usable IDs and raw metadata stay available. Raw storage codes, drive letters and network status/speed fields preserve their list shape in JSON. Monitor text still accepts its documented numeric-code arrays, but nested code lists and list-shaped lengths are invalid. Real zero values and supported numeric strings remain usable; integral enums use their numeric values for numeric readers.

Network fallback scans distinguish operational states such as Up, Down, Dormant and Not present. Invalid status metadata stays unknown, with the raw value retained. The direct CIM fallback's address list does not identify the current address, even when it contains only one value. Current MAC therefore remains unresolved and its comparison is skipped. A single distinct candidate is shown separately as unverified; the full address list and **Current MAC read status** appear in **[5]** and saved reports. A Windows-reported permanent address stays a separate identifier.

## Browse graphics, network and monitors

Choose Main **[3] Browse hardware / devices**, then **[4] Graphics & network**. The view uses the captured snapshot; opening it does not rescan. Jump with **1** for graphics, **2** for network or **3** for monitors. Enter or **0** returns to the main menu. Main **[5]** retains the full records and source metadata.

- **Graphics:** adapter name, processor description, WMI-reported mode, driver version/date and Windows device ID. Missing, incomplete or invalid dimensions are described explicitly. A controller's reported mode is not a verified mapping to a particular monitor.
- **Network:** interfaces grouped as reported hardware/physical, reported non-hardware or type not supplied. Each entry separates state, rate kind, current-address evidence, available permanent address, interface ID and reader. A false hardware flag is not used to guess the interface's specific technology.
- **Monitors:** reported name, manufacturer, serial, Windows active flag and instance ID. Monitor records remain separate from graphics-controller records.

The modern CIM fallback labels receive and transmit rates separately; the legacy fallback calls its rate a reported bandwidth estimate. Link state/rates do not measure internet connectivity or throughput. A permanent address is Windows-reported and can change. Missing optional addresses/device IDs on a reported non-hardware interface mean **not supplied / may not apply**, rather than proof that the device cannot use them. Those absent optional fields stay outside the quick-ID totals.

Readers can expose different sets of adapters. **Get-NetAdapter -IncludeHidden** requests hidden adapters; the direct CIM compatibility reader does not carry that command's IncludeHidden option and can return fewer records. A successful read means that reader completed, not that every network interface was discovered. The all-known PnP catalog remains a separate device inventory. See the [field audit](GRAPHICS-NETWORK.md) for evidence and tested limits.

| Label | Meaning |
| --- | --- |
| Found | Windows supplied a value that is not recognized as a default |
| Missing | An expected field was not supplied |
| Default | Windows supplied a known placeholder value |
| NOT READ | A query or optional catalog could not be read |
| Not scanned | This capture has no extended catalog, for example an older present-only snapshot |
| Conflict | Sources disagree, or records cannot be matched reliably |
| Status not supplied | Windows did not return a readable device status; condition is unknown and included in review |

Found does not prove that an identifier is unique or authentic. Missing/default values are different from failed queries. **[4]** explains findings; **[5]** shows full values and sources. Extended records have their own capture time and are not added to the normal identifier-field total.

## Read the summary clearly

| Summary item | What it counts |
| --- | --- |
| Read status | Normal queries read versus not read; this is not a hardware-health guarantee |
| Identifier fields | Found, missing and default values supplied for individual fields |
| Review | All findings, including missing/default IDs; **[4]** explains them |
| Present devices | Windows records, distinct classes and records with hardware IDs; physical and virtual nodes are included |
| Extended devices | A separate catalog of known records, including hidden and remembered records |
| Uncertainty | Extended records with unread hiding flags or unknown presence; these groups can overlap |

**PREVIOUS catalog / refresh NOT READ** means the latest extended refresh failed and the older catalog was retained. The displayed extended capture time belongs to that older data. Check **[4]** for the latest failure and retry **[9] > [4]**. If the first attempt failed before a catalog existed, the summary says **NOT READ**, rather than Not scanned. A later successful refresh clears that failure status.

Repeated manual failures keep the latest diagnostic message, code, and attempt time together, even when an earlier failed full-rescan record or good catalog is retained. Successful recovery clears that failure context. An invalid extended result cannot be published as Refreshed: manual refresh keeps the prior catalog, while a PC rescan can publish its new normal data with extended NOT READ and no old catalog attached.

The summary can show all normal queries read while an optional extended refresh failed. Read status remains partial in that case. Class counts ignore casing/edge-space differences, while the full report preserves original provider text.

## Understand unreadable results

The scan's **NOT READ** label means the query did not supply usable records. **CHECK** means records were read but some fields or device records need review. The finish line counts read and not-read sections separately. When an extended catalog was requested, the same line also says **extended READ** or **extended NOT READ**. A failed extended read keeps the finish line amber even if all 17 normal queries succeeded.

| Code | Reason | Suggested action |
| --- | --- | --- |
| READ-01 | Access blocked | Run as administrator if appropriate, then rescan |
| READ-02 | Provider timed out | Retry the scan; the Windows provider may be slow or stalled |
| READ-03 | Provider unavailable | Check runtime/provider details in **[5]**; the Windows version may not expose it |
| READ-04 | No records returned | Check whether the device is expected or connected, then rescan |
| READ-05 | Other Windows read failure | Retry and inspect technical details in **[5]** or saved reports |
| READ-06 | Invalid scan data | Rescan; the provider returned unusable records rather than valid hardware data |

Main **[4]** groups conflicts, device findings, unreadable sections, and missing/default IDs separately. Use **1** for the top, **2** for devices, **3** for unreadable sections, **4** for ID fields, and **5** for conflicts. Missing instance IDs and unread device status are review findings; they do not establish that hardware is broken. Raw technical messages remain in the full report and exports.

Failure classification uses available typed errors/codes first, then known message patterns. An unfamiliar localized message without a recognized code remains READ-05. A timeout setting does not guarantee an overall scan deadline.

If a query emits an uncaught error after returning some records, that section is marked NOT READ rather than presented as a complete list. This prevents incomplete data from appearing as confirmed hardware removals during comparison. Successful fallbacks that handle their own errors remain usable. A missing serial within an otherwise valid record remains a missing-ID finding, separate from invalid scan data.

Reader attempts are checked before their partial rows can be accepted. A non-terminating property error can use the existing single compatible-property retry; a failed network or extended-device enumeration can use its compatibility readers. A recovered attempt supplies only the successful reader's records. If no reader succeeds, the section stays NOT READ with its diagnostics. Filter/namespace/timeout selection is preserved, and access/timeouts are not treated as property errors.

Device-property reads retain batches of up to 32 nodes and use **one concurrent operation**, including recovery calls. This avoids the duplicate-node output observed with parallel property queries on the development PC. Extended capture metadata shows **PropertyNodesRequested**, **PropertyNodesReturned** and **PropertyNodesWithoutRows**. These count distinct nodes returning property rows, not the number of identifiers or physical devices. Individual values can still be absent.

The extended catalog also reads Windows container/base-container IDs when available. They are optional device-grouping GUIDs, not factory serials. Conflicting GUID observations remain unresolved; malformed values stay raw for inspection. Native and property hardware/compatible-ID lists have separate sources, and disagreement is flagged without replacing the preferred native list. Review and exports retain both observations. See [ID scanning accuracy](IDENTIFIERS.md#id-scanning-accuracy-and-coverage) for definitions, the reproduced concurrency issue and limits.

Scalar ID fields and device keys are checked before scan results are counted. Arrays/objects/booleans in those fields produce READ-06 rather than an invented joined ID or a later save error. Ordinary boolean fields, numeric disk zero, dates outside ID fields, and hardware-ID arrays remain supported.

Optional scan metadata is converted separately from identifiers. Unsupported storage codes are shown explicitly; invalid sizes remain unknown while real zero stays zero. Raw storage codes, drive-letter values and byte sizes remain in the full report/JSON. A malformed partition letter is labeled unknown rather than unassigned. These optional values do not discard otherwise usable IDs.

Monitor character codes are decoded numerically, including numeric strings and null padding. Name lengths reported by Windows bound name decoding when available; the query does not require optional length fields. Invalid text codes/lengths remain unread with an explicit read-status field; the original code arrays stay available in the full report and JSON. A valid monitor record with an unread serial remains CHECK rather than a failed whole query.

Network and extended-device readers retry their fallback when the primary reader fails or returns no records, including null-only results. Extended fallback enumeration stays unfiltered so remembered records can be included. The full report records which reader succeeded; extended capture information also records why fallback was needed. If no reader succeeds, technical details retain the attempted readers' messages; the failure reason describes the final reader. Direct and live-progress scans preserve the same error categories.

Network collection tries **Get-NetAdapter**, then **MSFT_NetAdapter**, then **Win32_NetworkAdapter** as a final compatibility fallback. A successful fallback is labeled on the scan row; **[5]** shows its CollectionSource. The final reader retains available GUIDs, device IDs and current MAC addresses. It leaves permanent MAC addresses unknown, includes virtual/disabled records, and preserves unread link-speed values as raw details without inventing a formatted speed. If every network reader fails, technical details retain all three messages and classify the final failure.

## Understand warnings and conflicts

The review summary counts findings, not unique devices. A device can have an unread status and a missing instance ID, producing two findings. Repeated instance IDs belong to the Conflicts group and are not counted again as ordinary device findings.

Unread sections are detected from the current snapshot as well as warning text. Repeated warnings for one section count once; old warnings for a section that is now readable do not keep it in Not read. A failed extended refresh remains visible even when an older catalog was retained. Raw warning messages remain in the full report and saved snapshot.

All review groups show a count and an explicit result when empty. **Start with** points to conflicts, unread sections, device findings or missing/default IDs in that order. The compact dashboard uses the same totals. Device findings include instance context so identical friendly names can be distinguished. Guidance labeled **Main [5]** refers to the full report; the review page's own **5** shortcut opens Conflicts.

| Finding | What it means | Next step |
| --- | --- | --- |
| Source clash | Two unambiguously matched Windows storage records report different serials | Review both displayed values, rescan, and inspect the sources in **[5]** |
| Duplicate device key | More than one record has the same matching key | Rescan and inspect records in **[5]**; comparisons skip ambiguous keys |
| Repeated instance ID | Multiple PnP records claim the same instance ID | Rescan before comparing; this does not prove two physical devices share a factory serial |
| Resource conflict | Windows reports code 12 | Inspect the device's reported resources in Device Manager, then rescan |
| Disabled | Windows reports code 22 | Check whether disabling was intentional in Device Manager |
| Disconnected | Windows reports code 45 | Check the connection and refresh the scan |
| Unknown status | Windows supplied no readable status | Rescan and inspect device details; do not assume working or broken |

Disk sources are joined only when each has one valid record for the same disk number. Duplicate disk numbers remain separate records, preventing guessed matches from producing false serial clashes or filling the wrong device's missing serial. A source disagreement alone does not prove disk failure.

Repeated device-instance rows count as one conflict, with their distinct status readings shown together. This keeps disabled/working/unknown readings available without pretending that duplicate rows are separate devices. Shared hardware-model IDs are normal and are not treated as instance conflicts. Code 22 alone is a disabled-device finding; code 45 describes a disconnected device.

Duplicate review ignores instance-ID case and leading/trailing whitespace or NUL padding, using the same keys as node-change matching. It preserves embedded characters and original ID text. Padding-only instance IDs count as missing. Model coverage includes only nonblank string IDs, consistently in scan progress and the overview.

## Save a baseline

1. Finish the scan you want to keep.
2. Choose **[6]** to create a TXT and JSON pair.
3. Choose **[8]** to open the report folder and review saved-snapshot storage status.

TXT is for reading. JSON is for comparison. Saves use new filenames rather than overwriting previous reports. Rescanning does not save automatically.

After saving, the checker immediately reports how many older usable snapshots it found for this PC. The new save remains a capture of the active scan; saving twice does not create a new hardware scan.

The save screen distinguishes **Computer / scan** from **Saved at** and shows normal-section read coverage. `SavedAt` is added only to the exported copy; the active scan's original capture time and number stay unchanged. Saving a partial capture remains available for diagnosis. Both final files are checked against the requested contents before **SAVED** appears; a handled verification failure rolls back the new pair where possible and reports any cleanup needed.

If the normal `HWID-Reports` folder cannot be written, the checker tries `%LOCALAPPDATA%\HWID Checker\HWID-Reports`. The save screen shows the actual location and explains fallback use. Both files are verified/published as a pair; malformed report data does not trigger a storage retry. **[8]** opens the last successful save's folder in the current session.

**[8] Saved reports / storage** shows readable JSON snapshots, older usable baselines, TXT + JSON pairs, JSON-only snapshots, and files that could not be read. Its section shortcuts are **1** Summary, **2** Folders, **3** Files not read, and **4** TXT only. JSON alone can be compared. TXT alone stays readable, but needs its matching JSON for comparison. Files are preserved; this screen does not repair or delete them.

Storage messages distinguish access blocked (**STORE-01**), unavailable/in-use files (**STORE-02**), invalid encoding (**STORE-03**), damaged data (**STORE-04**), the 64 MB import limit (**STORE-05**) and unsupported versions (**STORE-06**). Each lists its path and next step. A folder-opening failure (**STORE-08**) leaves the storage results available. Close any writer or wait for sync, then reopen Main **[8]** or refresh the comparison picker to detect recovered files.

The library remains local TXT/JSON files, without a separate database. Imports read strict UTF-8, with or without a BOM, and support BOM-marked UTF-16/UTF-32 exports. Invalid byte sequences are rejected instead of silently changing identifier text.

## Find which numbers changed

1. Keep a saved JSON baseline from **[6]**.
2. After changing hardware or connecting devices, choose **[9] > [1]** to refresh the current scan.
3. Choose **[7]** and select a detected **OLDER** snapshot, or paste a report path.
4. Read the previous/current values and the indicated character differences.

Pasted paths can use matching single or double quotes. Brackets, apostrophes and ampersands are treated as literal filename characters. The checker does not execute pasted text or expand shell commands.

The picker searches the launcher's report folder, the per-user fallback folder, and the adjacent installation's report folder when a parent `hwid.bat` exists. Renamed JSON snapshots are included. Files that cannot be read or validated are omitted with a count; Main **[8]** explains each failure. A manual path also exposes an individual file's error.

Five snapshots appear per page: **1–5** select a file, **6** opens the next page, **7** returns to the previous page, **8** refreshes detection, **9** accepts a path, and **0** or blank goes back. Older captures from the same computer appear first. Capture timestamps determine age, so copying a file does not make an old capture current. A **SAME CAPTURE TIME** label is a timestamp match, not proof that all IDs match. Newer, other-PC, unknown-time and no-usable-ID snapshots are labeled separately.

Colors reinforce these labels: **green** marks older usable baselines from this PC; **gray** marks the same capture time; **yellow** asks you to check context or retry; **red** marks invalid file data in the storage screen. Color never replaces the written status.

Choosing a TXT report automatically uses the JSON with the same filename stem. TXT without its JSON companion cannot be used for comparison. Results provide **1 Summary / 2 ID changes / 3 Not compared** shortcuts, full OLD/NEW values and exact character differences. Same-time and newer-than-current baselines receive a time-order explanation.

Comparison also identifies added/removed records. Missing or duplicate matching keys can prevent a reliable match; the checker explains skipped comparisons rather than guessing. A changed device-instance ID can reflect a different port or Windows device record.

Capitalization of recognized JSON section/field names does not count as an ID change. Actual identifier values remain case-sensitive and keep leading zeros. If a system or firmware section contains multiple records without a reliable device key, its comparison is skipped and Main **[4]** shows the ambiguity; a single record remains comparable. Raw saved files are preserved.

For two consecutive scans in the same session, **[9] > [3]** reopens the last rescan comparison. Save with **[6]** if you need a snapshot after closing.

## Scan hidden and remembered devices

Startup and full rescans collect the all-known catalog automatically. Choose **[9] > [4]** to refresh it separately and browse its groups. Windows may expose hidden flags, disabled devices, disconnected records, unknown presence and additional device properties. The extended view provides numbered shortcuts for these groups.

Hidden and remembered are different properties, and their groups can overlap. A remembered record does not prove that hardware is still connected. Unknown presence or unread visibility stays unknown. Full PC rescans request this catalog even when the previous capture did not include one.

Optional device properties are read in batches of up to 32 nodes. A generic terminating batch failure receives one bounded per-device recovery pass, retaining earlier successful rows and continuing later batches. Access, timeout and unavailable-provider failures do not start per-device retry loops; a retry pass stops if one of those failures occurs. Non-terminating optional errors retain usable rows. **[5]** and saved reports include `PropertyBatches`, `PropertyRetryDevices` and the reader-error count. These are read attempts, not extra devices. Missing properties stay unknown; an unavailable catalog leaves normal scan results usable with an explicit warning.

Contradictory device-property readings keep presence or node visibility unknown and appear in detail review. The full report and JSON retain distinct `PresenceReadings` and `NodeStatusReadings`; repeated equal readings do not create a conflict. Native status fallback is used for missing valid readings, and does not replace an already conflicting set with one chosen value.

Extended view filters overlap: **2** includes disconnected records, **3** includes all records with a Windows hiding flag/class, **4** includes known-present disabled records, **5** includes all known-present records, and **6** includes unknown presence. One device can appear in several views; do not add these counts to estimate unique devices.

Problem-code arrays/objects/booleans are unread metadata rather than numeric status. A usable native code remains available when an optional reading is invalid. Disagreeing valid codes remain unknown, with `ProblemCodeReadings`, `ProblemCodeConflict`, read status and raw observations in **[5]**/JSON. Invalid optional parent data leaves topology unresolved while preserving the device's core identifiers; `ParentReadStatus` and `RawParentInstanceId` explain it.

Normal and extended device scans select the first usable `PNPDeviceID`, `InstanceId`, or Windows `DeviceID` key. `InstanceIdSource` records the field used. Original ID text stays in the report; normalized keys are used to look up properties and parent names. A blank or NUL-only alias cannot replace a valid alternative.

Extended hardware/compatible ID lists keep valid text, order, invalid raw observations, and read-status findings. Usable PnP-record lists stay preferred. If they are absent, collected property lists supply the usable values. `HardwareIDPropertyReadings` and `CompatibleIDPropertyReadings` retain original observations; different lists are flagged, and their combined inspection values do not establish a Windows driver-priority order. **[5]** and saved JSON keep these full details.

## Navigation

- Main menu: type **0–9**, then Enter. Empty Enter is ignored.
- Reports in the checker's readable console: scroll with the wheel, arrows, Page Up/Down or Home/End. Use any numbered shortcuts printed on that page.
- Report pages: Enter returns to the menu. Where the footer offers **0**, that also returns.
- Navigation animations can be disabled by setting `HWID_NO_ANIMATION=1` before launching.
- Next/Back use directional trails with a moving border; Exit closes toward the center. Back is quickest. Typing during a transition skips the remaining motion and leaves the key available for the next input step. Narrow windows keep the action label visible.

## Compatibility and common problems

The checker requires Windows and PowerShell 5.1 or newer in FullLanguage mode. Current validation covers Windows PowerShell 5.1 and PowerShell 7.6.5 on a Windows PC; it does not establish support for every historical Windows build.

| Problem | What to do |
| --- | --- |
| COMPAT-01 / no suitable PowerShell | Use an installed PowerShell 5.1+ runtime approved for your Windows version. The checker does not install one. |
| COMPAT-02 / restricted execution | Ask your administrator about approved execution. The checker does not change persistent policy. |
| COMPAT-03 from the PS1 launcher | Read the accompanying message. Keep `Start-HWID.ps1` and `hwid.bat` together. |
| START-01 | Checker content could not be loaded or parsed. Missing/blank content is rejected; download a complete copy if needed. |
| START-02 | CMD received a nonzero runtime exit code. Read the earlier error; the exit code is preserved. |
| UI-01 | A menu action failed. The current scan is retained; press Enter to return to the menu and save normally if needed. |
| CRASH-01 | An uncaught application error stopped the checker. Note the phase/detail shown, then reopen and retry. |
| CMD is unavailable | Use `Start-HWID.ps1` in an approved PowerShell session. Normal script policies still apply. |
| A section is unavailable | Open **[4]**. A provider may be absent, blocked, or unable to expose data. Other sections remain usable. |
| Access denied | If appropriate, run as administrator and rescan. Permissions cannot supply values missing from firmware. |
| A value is shortened | Open **[5]** or save with **[6]** for full values. |
| Nothing changes in a saved report | Saved files are snapshots. Rescan and choose **[6]** to create a new pair. |
| A JSON report cannot be compared | Use the JSON exported by a supported checker version, not TXT. Keep the original error message for troubleshooting. |

If both CMD and a suitable PowerShell runtime are unavailable, this script-based checker cannot run. Windows-specific hardware providers may limit coverage even when the runtime is supported.

## Startup and recovery

The BAT launcher displays **[1/3] Preparing startup**, holds that screen with a **3-second native CMD countdown**, then begins **[2/3] Checking for compatible PowerShell**. **[3/3] Starting checker** appears only after a suitable runtime is found. The reading pause occurs before the first PowerShell probe; ordinary keys, including held Enter, do not skip it. It is a readability pause, not a hardware-scan percentage.

The countdown uses `%SystemRoot%\System32\timeout.exe` with `/nobreak`, avoiding a similarly named command on PATH. If the timer is absent, blocked, fails or cannot use redirected input, an informational line explains that the countdown is unavailable and startup continues. Timer failure does not replace runtime/checker exit codes or bypass compatibility restrictions. No network-based delay or extra package is used. The PowerShell-only launcher keeps its preparation message; the readable-window handoff loads the embedded PowerShell body without repeating the CMD countdown. All three loaders still reject missing/blank embedded content before invoking it.

Unexpected menu-action errors use **UI-01**. The current inventory and warnings remain in memory; live worker/timer/navigation state is cleared, and Enter returns to the main menu. Recovery does not rescan or save automatically. Use **[6]** to save the retained capture when needed.

Uncaught application failures use **CRASH-01**, showing the phase and up to 320 characters of error detail. The checker attempts to dispose its query worker, stop its progress clock and restore cursor visibility before exiting with code 1. The dedicated window offers Enter to close on interactive input. Startup/parse failures before the application can run use **START-01** or **COMPAT-03**; CMD preserves nonzero exit codes and keeps its failure message visible.

No automatic crash log or snapshot is written by these handlers. Saved reports are left available. Forced process termination, native runtime failure or Windows shutdown can bypass PowerShell handlers, so an unsaved scan cannot always be recovered.
