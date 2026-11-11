# Using HWID Checker

[Back to the main README](../README.md)

Application updates are available from Desktop **Updates** or BAT **[9] → [5]**. Automatic updates start enabled and prepare compatible newer packages in the background. [Update behavior and recovery](UPDATES.md)

## Read a scan

Use **[1]** for the overview. It separates normal query coverage, identifier fields, present devices and the all-known extended catalog. Startup and full rescans collect the 18 normal sections plus this catalog automatically. The overall progress bar has 19 stages and reaches 100% after the catalog attempt finishes; READ/NOT READ shows whether collection succeeded.

The scan display groups related queries together:

| Group | Contents |
| --- | --- |
| 1. System & firmware | System identity/hardware, motherboard, BIOS and chassis |
| 2. CPU & memory | CPU and memory modules |
| 3. Storage | Physical disks, storage identifiers, volumes and partitions |
| 4. Graphics & network | Graphics adapters, monitors and network adapters |
| 5. Power | Optional battery identity, charge, voltage and Windows-reported status |
| 6. Windows | Operating-system details, available Secure Boot/TPM information and Machine GUID |
| 7. Present device IDs | Present PnP nodes and their reported ID lists |
| 8. All-known device catalog | Windows-known nodes, including hidden/disconnected records |

Group numbers organize the display; they do not replace the 18 query counters or 19-stage overall progress. Section-only diagnostic scans show seven groups. Firmware queries stay together before CPU/memory. Every new scan resets group numbering, and the scrollbar continues to track written content rather than empty reserved rows.

Battery hardware is optional. A desktop PC can correctly report no battery. Device IDs identify the Windows battery record and should not be read as a manufacturer serial number. The checker does not manufacture a missing-serial warning for fields its battery provider does not support.

Short successful results stay compact. **CHECK**, PnP coverage and unread-result details use indented continuation lines, keeping record/time status separate from longer explanations. Result details wrap at word boundaries in narrow windows; they are not shortened with ellipses. The formatter uses the current width after resizing, while completed query metadata keeps its full summary. Progress displays retain fractional elapsed seconds.

**Records** are rows returned by Windows, while **IDs** count selected identifier fields. A record can contain several IDs. **NOT READ / no usable data** explains a missing result without claiming that no physical devices exist; the reason, READ code and Main **[4]** reference follow below it.

After the startup scan, the finished scan stays visible until you press **Enter** to continue to the main menu. After a rescan, press **Enter** to continue to the snapshot changes. You can scroll before continuing. Release Enter if it was held during scanning; the dedicated console clears scan-time keystrokes so they cannot skip this step. Redirected runs do not pause for this prompt.

The finish screen shows **SCAN COMPLETE** when all requested sections and the requested catalog were read, or **SCAN FINISHED / READ GAPS** when an attempt returned no usable data. **Finished** separates attempted/read/not-read counts and catalog status. **Selected IDs** counts Windows-reported identifier fields, and **Review** matches the main menu's findings with a Main **[4]** pointer after Enter. Reaching 100% means all requested attempts finished; it does not guarantee every optional field or serial was supplied.

Final summary/progress exceptions cannot discard a finished snapshot. **[5] > Report info > Scan completion display warning** retains the detail in the full report and TXT/JSON. Worker disposal errors use **Scan cleanup warning** and leave the finished data usable; a cleanup error cannot replace an earlier incomplete-scan error. These diagnostics stay separate from Windows hardware-read warnings. Each new scan starts with fresh completion/cleanup state. An incomplete snapshot fails validation before its final progress update and is not published as a completed rescan.

Individual query cleanup follows the same rule. Closing the wait handle and disposing the query command are attempted separately, so one cleanup failure cannot skip the other release. Fully validated results stay readable; an actual provider timeout, access denial or invalid result keeps its original READ code. Cleanup alone does not create a hardware-read warning or an ID change.

The finish screen shows **Query cleanup** when applicable. **[5] > Scan timing > Query cleanup warning** holds normal-section details, **Report info > Sections with query cleanup warnings** counts those sections, and **Extended scan info > Query cleanup warning** holds full-scan catalog details. For a standalone catalog refresh using **[9] > [4]**, **Report info > Extended query cleanup warning / Extended worker cleanup warning** describes the latest attempt. A failed refresh keeps the prior catalog and its original capture time while marking the latest attempt unavailable. A later healthy attempt clears old cleanup diagnostics. These details are included in TXT/JSON; resource release is best effort when the runtime itself reports a cleanup failure.

In the dedicated console, you can also navigate **during** background scanning with the mouse wheel/scrollbar, Up/Down, Page Up/Down, Home and End. Scrolling back pauses following so new rows and timers preserve your chosen view. **End** resumes following the latest output. Scan history stays close to the content actually written, with a small reserve for the next line, rather than thousands of blank rows. Enter and menu numbers are ignored while collection runs; keyboard processing is bounded so holding a key cannot monopolize the scan loop. If the live worker is unavailable and direct queries are used, keyboard navigation is processed between queries; host mouse scrolling remains available.

Narrow windows retain wrapped scan text. Resizing skips stale timer coordinates; subsequent output remains readable, and the completed report can still be scrolled. Full-screen reports keep their existing history behavior; the main menu clears completed scan history when opened.

If a provider rejects requested fields, the checker retries once using the properties that provider exposes. It keeps the same device filter, namespace and reader. **Compatible read** means that retry succeeded; unsupported fields can still be missing. The finish screen counts recovered sections, and **[5] Full inventory report** includes retry diagnostics under Scan timing. These details are also saved in TXT/JSON. Access failures, timeouts and missing providers keep their normal warnings.

Error handling reads the exception's named **NativeErrorCode**, **StatusCode** and **ErrorCode** values, including inner exceptions. A zero StatusCode no longer hides a native CIM error. Native **AccessDenied** becomes **READ-01 / Access blocked**, **InvalidOperationTimeout** becomes **READ-02 / Provider timed out**, and **InvalidClass / InvalidNamespace / NotSupported** retain **READ-03 / Provider unavailable**. The present-device reader can use its existing fallback when the primary class is unavailable. Unknown codes keep the generic failure and original detail; numeric codes from different APIs are not guessed to have the same meaning.

Native **NoSuchProperty / InvalidQuery** also enable the single available-property retry without depending on English error text. Named access/timeout errors prevent that retry, including when an outer message mentions an invalid query. Partial output from a failed attempt is rejected before any fallback is selected. Review, saved reports and comparisons retain the corrected READ code; unread IDs do not become removed hardware.

If live progress updates fail, the query continues and keeps its hardware results. The finish screen reports affected sections, and **[5] Scan timing** retains a separate progress-display warning. Provider-read failures still use their own READ codes.

Group-heading failures follow the same rule. Catalog heading/timer failures are retained under **Extended scan info / ProgressWarning**, shown as **Catalog display** at completion and included in TXT/JSON. They do not turn a successfully read catalog into a failed query or inflate the normal-section display-warning count.

Completed-result rendering errors are also retained: normal rows use **Scan timing / ProgressWarning**, and catalog rows use **Extended scan info / ProgressWarning**. A plain-text fallback is attempted without replacing the captured hardware data. Collection failures retain their own read reason and code.

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

The scan's **NOT READ** label means the query did not supply usable records. **CHECK** means records were read but some fields or device records need review. The finish screen separates completed checks, readable hardware areas and the Windows-known device-list status. A failed device-list read remains explicit even if all 18 normal queries succeeded.

Finished checks and readable data are separate counts. A scan can reach **19/19 checks finished** while some hardware areas remain unread. If a rescan cannot read any inventory, the last usable capture stays active; its warnings still belong to that earlier capture. Retry the rescan, or restart the checker for fresh startup diagnostics. A first scan with no readable data keeps its diagnostic details. Watch mode does not report unchanged IDs when no identifier fields can be compared.

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

Direct and background queries retain completed compatible-read attempts when a later step fails. **[5] > Scan timing > Recoveries** and TXT/JSON reports show that earlier history alongside the final FailureCode. Recovery history does not make an incomplete section readable or add it to the compatible-read success total. The final terminating error takes priority over earlier non-terminating errors; original provider error identities/categories remain available. Each new query clears earlier query state. A background worker that ends without a complete attempt result produces READ-06 rather than a successful empty result.

Reader attempts are checked before their partial rows can be accepted. A non-terminating property error can use the existing single compatible-property retry; a failed network or extended-device enumeration can use its compatibility readers. A recovered attempt supplies only the successful reader's records. If no reader succeeds, the section stays NOT READ with its diagnostics. Filter/namespace/timeout selection is preserved, and access/timeouts are not treated as property errors.

Device-property reads retain batches of up to 32 nodes and use **one concurrent operation**, including recovery calls. This avoids the duplicate-node output observed with parallel property queries on the development PC. Extended capture metadata shows **PropertyNodesRequested**, **PropertyNodesReturned** and **PropertyNodesWithoutRows**. These count distinct nodes returning property rows, not the number of identifiers or physical devices. Individual values can still be absent.

The extended catalog also reads Windows container/base-container IDs when available. They are optional device-grouping GUIDs, not factory serials. Conflicting GUID observations remain unresolved; malformed values stay raw for inspection. Native and property hardware/compatible-ID lists have separate sources, and disagreement is flagged without replacing the preferred native list. Review and exports retain both observations. See [ID scanning accuracy](IDENTIFIERS.md#id-scanning-accuracy-and-coverage) for definitions, the reproduced concurrency issue and limits.

Scalar ID fields and device keys are checked before scan results are counted. Arrays/objects/booleans in those fields produce READ-06 rather than an invented joined ID or a later save error. Ordinary boolean fields, numeric disk zero, dates outside ID fields, and hardware-ID arrays remain supported.

Optional scan metadata is converted separately from identifiers. Unsupported storage codes are shown explicitly; invalid sizes remain unknown while real zero stays zero. Raw storage codes, drive-letter values and byte sizes remain in the full report/JSON. A malformed partition letter is labeled unknown rather than unassigned. These optional values do not discard otherwise usable IDs.

For RAM, **Speed** is labeled **Windows-reported raw** rather than assumed to be MHz. **ConfiguredClockSpeed** has the documented MHz label, but a reported zero means **Unknown**, not a measured zero-frequency clock. Missing and invalid configured values remain distinguishable; unknown values use muted text. Hardware views and TXT share these interpretations, while JSON preserves the original fields, including zero and leading-zero strings. Raw network `Speed` fields in TXT use bits/s rather than inheriting a memory-speed label. See Microsoft's [Win32_PhysicalMemory definitions](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-physicalmemory).

Monitor character codes are decoded numerically, including numeric strings and null padding. Name lengths reported by Windows bound name decoding when available; the query does not require optional length fields. Invalid text codes/lengths remain unread with an explicit read-status field; the original code arrays stay available in the full report and JSON. A valid monitor record with an unread serial remains CHECK rather than a failed whole query.

Network and extended-device readers retry their fallback when the primary reader fails or returns no records, including null-only results. Extended fallback enumeration stays unfiltered so remembered records can be included. The full report records which reader succeeded; extended capture information also records why fallback was needed. If no reader succeeds, technical details retain the attempted readers' messages; the failure reason describes the final reader. Direct and live-progress scans preserve the same error categories.

Network reader attempts are also checked for scalar/list-shaped records, empty adapter fields, and malformed scalar identifiers before derived labels are added. A list/object/boolean in a selected interface GUID, MAC/permanent address or PnP device ID rejects that reader attempt and allows the next reader to run. Validation applies to fields used by that reader. An invalid attempt cannot leak partial rows or fabricate a device. If every reader returns invalid records, the section becomes READ-06 with zero accepted results. Missing IDs remain reviewable device data; optional status/rate metadata is kept separately, including actual zero/false values. Source and rate-kind labels alone cannot make an empty record readable, and an unread network section is skipped during comparison rather than treated as confirmed device removal.

Network collection tries **Get-NetAdapter**, then **MSFT_NetAdapter**, then **Win32_NetworkAdapter** as a final compatibility fallback. A successful fallback adds **compatible read** to the scan result and contributes to the finished scan's compatible-read section count. **[5]** shows each record's CollectionSource and the network query's Recoveries: the chosen method and earlier reader errors. TXT and JSON exports retain these diagnostics. The final reader retains available GUIDs, device IDs and current MAC addresses. It leaves permanent MAC addresses unknown, includes virtual/disabled records, and preserves unread link-speed values as raw details without inventing a formatted speed. If every network reader fails, technical details retain all three messages and classify the final failure.

## Understand warnings and conflicts

The review summary counts findings, not unique devices. A device can have an unread status and a missing instance ID, producing two findings. Repeated instance IDs belong to the Conflicts group and are not counted again as ordinary device findings.

Unread sections are detected from the current snapshot as well as warning text. Repeated warnings for one section count once; old warnings for a section that is now readable do not keep it in Not read. A failed extended refresh remains visible even when an older catalog was retained. Raw warning messages remain in the full report and saved snapshot.

All review groups show a count and an explicit result when empty. **Start with** points to conflicts, unread sections, device findings or missing/default IDs in that order. The compact dashboard uses the same totals. Device findings include instance context so identical friendly names can be distinguished. Guidance labeled **Main [5]** refers to the full report; the review page's own **5** shortcut opens Conflicts.

| Finding | What it means | Next step |
| --- | --- | --- |
| Source clash | Two unambiguously matched Windows storage records report different serials | Review both displayed values, rescan, and inspect the sources in **[5]** |
| Duplicate device key | More than one record has the same matching key | Rescan and inspect records in **[5]**; comparisons skip ambiguous keys |
| Repeated instance ID | Multiple PnP records claim the same instance ID | Rescan before comparing; this does not prove two physical devices share a factory serial |
| Resource conflict | Windows reports a boot configuration conflict (code 6) or an IRQ resource already in use (code 30) | Inspect the reported resource assignment in Device Manager, then rescan |
| Insufficient resources | Windows reports code 12; a shortage or conflict may be involved | Check resource allocation in Device Manager; the finding stays visible under Device status & records |
| Ambiguous presence/driver status | Windows reports code 24: not present, malfunctioning, or incomplete drivers | Check presence, operation and drivers in Device Manager; this code alone does not determine presence |
| Disabled | Windows reports code 22 | Check whether disabling was intentional in Device Manager |
| Disconnected | Windows reports code 45 | Check the connection and refresh the scan |
| Unknown status | Windows supplied no readable status | Rescan and inspect device details; do not assume working or broken |

Disk sources are joined only when each has one valid record for the same disk number. Duplicate disk numbers remain separate records, preventing guessed matches from producing false serial clashes or filling the wrong device's missing serial. A source disagreement alone does not prove disk failure.

Repeated device-instance rows count as one conflict, with their distinct status readings shown together. This keeps disabled/working/unknown readings available without pretending that duplicate rows are separate devices. Shared hardware-model IDs are normal and are not treated as instance conflicts. Code 22 alone is a disabled-device finding; code 45 describes a disconnected device.

Code 12 contributes one device finding to the review total and keeps the scan marked CHECK. Codes 6 and 30 contribute reported conflict findings. The dashboard, summary, review page and device views use the same interpretation. Windows can report code 12 when firmware has not allocated enough resources, so the checker does not assert a collision from that code alone. See Microsoft's [code 12 explanation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-normal-conflict) and [Windows status-code definitions](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity). Raw codes remain unchanged in TXT/JSON and older snapshots are interpreted using these current labels.

Duplicate review ignores instance-ID case and leading/trailing whitespace or NUL padding, using the same keys as node-change matching. It preserves embedded characters and original ID text. Padding-only instance IDs count as missing. Model coverage includes only nonblank string IDs, consistently in scan progress and the overview.

## Save a baseline

1. Finish the scan you want to keep.
2. Choose **[6]** to create a TXT and JSON pair.
3. Choose **[8]**, then **[1]** to review storage or **[2]** to open the report folder.

TXT is for reading. JSON is for comparison. Saves use new filenames rather than overwriting previous reports. Rescanning does not save automatically.

After saving, the checker immediately reports how many older usable snapshots it found for this PC. The new save remains a capture of the active scan; saving twice does not create a new hardware scan.

The save screen distinguishes **Computer / scan** from **Saved at** and shows normal-section read coverage. `SavedAt` is added only to the exported copy; the active scan's original capture time and number stay unchanged. Saving a partial capture remains available for diagnosis. Both final files are checked against the requested contents before **SAVED** appears; a handled verification failure rolls back the new pair where possible and reports any cleanup needed.

The BAT saves to your shared save folder if configured, or to the normal `HWID-Reports` folder. If it cannot write there, it tries `%LOCALAPPDATA%\HWID Checker\HWID-Reports`. The save screen shows the actual location and explains fallback use. Both files are verified as a pair. **[8] → [2]** opens the last successful save's folder when it is available.

**[8] → [1]** shows readable JSON snapshots, older usable baselines, TXT + JSON pairs, JSON-only snapshots, and files that could not be read. Its section shortcuts are **1** Summary, **2** Folders, **3** Files not read, and **4** TXT only. JSON alone can be compared. TXT alone stays readable and needs its matching JSON for comparison.

### Share snapshot folders on this PC

Use **Snapshots → Folder settings…** in Desktop 1.3.0 or **[8]** in BAT 3.85.

| BAT storage option | Purpose |
| --- | --- |
| **[3]** | Choose the shared save folder. The BAT saves there and Desktop starts its save picker there. |
| **[4]** | Add another folder to both snapshot libraries. |
| **[5]** | Stop watching an added folder. Existing reports stay in the folder. |
| **[6]** | Use the normal save folder again. The old shared folder remains in the library. |

Both apps use folder preferences from `%LOCALAPPDATA%\HWID Checker\snapshot-library.json` for the current Windows user. The preference file holds folder paths. Saving is explicit and both libraries point to the original files. Older versions can still open a saved JSON directly.

Storage messages distinguish access blocked (**STORE-01**), unavailable/in-use files (**STORE-02**), invalid encoding (**STORE-03**), damaged data (**STORE-04**), the 64 MB import limit (**STORE-05**) and unsupported versions (**STORE-06**). Each lists its path and next step. A folder-opening failure (**STORE-08**) leaves the storage results available. Close any writer or wait for sync, then reopen Main **[8]** or refresh the comparison picker to detect recovered files.

The library remains local TXT/JSON files, without a separate database. Imports read strict UTF-8, with or without a BOM, and support BOM-marked UTF-16/UTF-32 exports. Invalid byte sequences are rejected instead of silently changing identifier text.

## Find which numbers changed

1. Keep a saved JSON baseline from **[6]**.
2. After changing hardware or connecting devices, choose **[9] > [1]** to refresh the current scan.
3. Choose **[7]** and select a detected **OLDER** snapshot, or paste a report path.
4. Read the previous/current values and the indicated character differences.

Pasted paths can use matching single or double quotes. Brackets, apostrophes and ampersands are treated as literal filename characters. The checker does not execute pasted text or expand shell commands.

The picker searches the shared library, the launcher's report folder, the per-user fallback folder, and the adjacent installation's report folder when a parent `hwid.bat` exists. **[8]** in the picker reloads both folders and files. Renamed JSON snapshots are included. **Main [8] → [1]** explains which files could not be read. A manual path also exposes an individual file's error.

Five snapshots appear per page: **1–5** select a file, **6** opens the next page, **7** returns to the previous page, **8** refreshes detection, **9** accepts a path, and **0** or blank goes back. Older captures from the same computer appear first. Capture timestamps determine age, so copying a file does not make an old capture current. A **SAME CAPTURE TIME** label is a timestamp match, not proof that all IDs match. Newer, other-PC, unknown-time and no-usable-ID snapshots are labeled separately.

Colors reinforce these labels: **green** marks older usable baselines from this PC; **gray** marks the same capture time; **yellow** asks you to check context or retry; **red** marks invalid file data in the storage screen. Color never replaces the written status.

Choosing a TXT report automatically uses the JSON with the same filename stem. TXT without its JSON companion cannot be used for comparison. Results provide **1 Summary / 2 ID changes / 3 Not compared** shortcuts, full OLD/NEW values and exact character differences. Same-time and newer-than-current baselines receive a time-order explanation.

Comparison also identifies added/removed records. Missing or duplicate matching keys can prevent a reliable match; the checker explains skipped comparisons rather than guessing. A changed device-instance ID can reflect a different port or Windows device record.

**Network reader coverage:** fallback readers can expose a different adapter set. When the readers differ, are mixed, or are not recorded in an older snapshot, interfaces present in only one report are marked **not compared** instead of becoming added/removed IDs. Both the saved-file comparison and rescan summary show **Reader coverage**, the two readers and the number of unmatched interfaces. Interfaces matched by their interface GUID still compare usable IDs, including real changes. When both captures identify the same known reader, one-sided ID records remain comparable. A provider transition with all interfaces matched adds no coverage warning. Raw snapshots remain unchanged; a coverage finding is not a hardware conflict or proof of hardware removal.

Capitalization of recognized JSON section/field names does not count as an ID change. Actual identifier values remain case-sensitive and keep leading zeros. If a system or firmware section contains multiple records without a reliable device key, its comparison is skipped and Main **[4]** shows the ambiguity; a single record remains comparable. Raw saved files are preserved.

For two consecutive scans in the same session, **[9] > [3]** reopens the last rescan comparison. Save with **[6]** if you need a snapshot after closing.

## Scan hidden and remembered devices

Startup and full rescans collect the all-known catalog automatically. Choose **[9] > [4]** to refresh it separately and browse its groups. Windows may expose hidden flags, disabled devices, disconnected records, unknown presence and additional device properties. The extended view provides numbered shortcuts for these groups.

Hidden and remembered are different properties, and their groups can overlap. A remembered record does not prove that hardware is still connected. Unknown presence or unread visibility stays unknown. Full PC rescans request this catalog even when the previous capture did not include one.

Optional device properties are read in batches of up to 32 nodes. A generic terminating batch failure receives one bounded per-device recovery pass, retaining earlier successful rows and continuing later batches. Access, timeout and unavailable-provider failures do not start per-device retry loops; a retry pass stops if one of those failures occurs. Non-terminating optional errors retain usable rows. **[5]** and saved reports include `PropertyBatches`, `PropertyRetryDevices` and the reader-error count. These are read attempts, not extra devices. Missing properties stay unknown; an unavailable catalog leaves normal scan results usable with an explicit warning.

Contradictory device-property readings keep presence or node visibility unknown and appear in detail review. The full report and JSON retain distinct `PresenceReadings` and `NodeStatusReadings`; repeated equal readings do not create a conflict. Native status fallback is used for missing valid readings, and does not replace an already conflicting set with one chosen value.

Extended view filters overlap: **2** includes disconnected records, **3** includes all records with a Windows hiding flag/class, **4** includes known-present disabled records, **5** includes all known-present records, and **6** includes unknown presence. One device can appear in several views; do not add these counts to estimate unique devices.

Problem-code arrays/objects/booleans are unread metadata rather than numeric status. A usable native code remains available when an optional reading is invalid. Disagreeing valid codes remain unknown, with `ProblemCodeReadings`, `ProblemCodeConflict`, read status and raw observations in **[5]**/JSON. Parent metadata is checked separately, preserving the device's core identifiers and any consistent valid reading.

For parent links, equivalent repeated values resolve using a key that ignores case and surrounding whitespace/NUL padding, while the chosen original text is preserved. Different valid parent IDs set **ParentInstanceIdConflict**, leave **ParentInstanceId / ParentName** unresolved and retain every observation in **ParentInstanceIdReadings**. **Parent links** counts usable parent IDs; **ParentLinkConflicts** counts unresolved relationships separately. Empty/NUL-only values do not create a link or a conflict.

Malformed arrays, objects, booleans and numeric parent values are excluded from matching. A valid neighboring reading remains usable and **ParentReadStatus** explains ignored invalid entries. If none is valid, the parent stays unresolved. **RawParentInstanceId** keeps the last raw property value for compatibility with earlier reports; **ParentInstanceIdReadings** holds the complete sequence, including malformed values and observations collected before a batch retry. TXT/JSON preserve these details.

The finished scan shows **Device relationships** when parent readings disagree. The extended summary shows **Parent conflicts**, its detailed rows label unresolved links, and **[7] Unknown & review** inside that view explains the disagreement. Windows device-status codes remain separately available; parent metadata alone does not change identifier comparisons. Each scan builds fresh relationship state.

Normal and extended device scans select the first usable `PNPDeviceID`, `InstanceId`, or Windows `DeviceID` key. `InstanceIdSource` records the field used. Original ID text stays in the report; normalized keys are used to look up properties and parent names. A blank or NUL-only alias cannot replace a valid alternative.

Extended device names use readable text from **PnP name**, then **Friendly name**, then **Bus description**. Classes use readable **PNPClass**, then the **Class** alias. NUL-only/blank text and non-text containers cannot block usable alternatives or become joined labels. If all alternatives are unread, the name/class remains unknown and detail review explains the missing text. Unusable provided values remain in **Raw PnP name**, **Raw friendly name**, **Raw bus description**, **Raw PnP class** or **Raw class alias** in the full report/JSON. NameSource identifies the selected name source.

Names beginning with **Unknown**, or their localized equivalents, do not independently determine device condition. Windows status codes, missing data and contradictory readings still receive their own findings. A readable label does not manufacture a working status when the code is missing. Class grouping ignores edge whitespace/NUL padding while preserving original values; names and hardware identifiers are not rewritten into guessed manufacturer data.

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

The BAT enables CMD command extensions within its local environment and clears an inherited variable named `ERRORLEVEL`. This makes its label calls and runtime checks work with command extensions disabled by the caller, and prevents a shadow variable from replacing real process exit codes. Actual blocked-runtime checks still stop startup.

The original window now waits for the readable child to confirm readiness before starting hardware collection. **START-03** means the new window failed, exited without confirmation or could not be created; the checker explains the failure and continues in the original window. Missing/invalid content and pre-ready fatal errors can send their bounded detail back to the launcher. A normal completed child is distinguished from an unexplained early zero exit.

After 12 seconds without confirmation, **START-04** explains that the readable window is still starting. The original window stays open until that child finishes, so this condition does not start a duplicate scan. A failed child then falls back to the original window. A small temporary file carries startup state and up to 320 characters of error detail, and the launcher attempts to remove it during cleanup. Parent environment state and process handles are restored/released; no hardware inventory is written to the signal.

To keep everything in the current console while troubleshooting, launch from the extracted repository folder:

```powershell
.\hwid.bat --current-window
```

To keep a CMD prompt open after the checker exits, use `cmd.exe /d /k hwid.bat --current-window` from that same folder. The `/d` option skips Command Processor AutoRun commands for that new CMD session. Existing runtime and organization policies still apply.

Unexpected menu-action errors use **UI-01**. The current inventory and warnings remain in memory; live worker/timer/navigation state is cleared, and Enter returns to the main menu. Recovery does not rescan or save automatically. Use **[6]** to save the retained capture when needed.

Uncaught application failures use **CRASH-01**, showing the phase and up to 320 characters of error detail. The checker attempts to dispose its query worker, stop its progress clock and restore cursor visibility before exiting with code 1. After a successful handoff, the dedicated window offers Enter to close on interactive input. A pre-ready failure is reported back to the original launcher for fallback instead. Startup/parse failures before the application can run use **START-01** or **COMPAT-03**; CMD preserves nonzero exit codes and keeps its failure message visible.

These handlers do not save an inventory snapshot or permanent crash log. The temporary handoff signal described above is separate from saved reports. Forced process termination, native runtime failure or Windows shutdown can bypass PowerShell handlers and normal signal cleanup, so an unsaved scan cannot always be recovered.
