# Recent changes

[Back to the main README](../README.md)

## 3.71

- Fixed silent device-property coverage loss reproduced with concurrent Windows queries. Normal and recovery calls now use `Get-PnpDeviceProperty -ThrottleLimit 1`, retaining batches of up to 32 nodes and existing bounded recovery. A development-PC probe returned 169 container rows for only 158 distinct nodes at default concurrency, versus all 169 at limit one. This is a measured local issue, not a universal Windows compatibility claim.
- Added distinct-node property coverage to extended metadata and its summary. Returned row totals cannot inflate node coverage; individual fields may still be absent. Serial property collection can take longer (2.51s versus 1.40s in that probe).
- Added optional Windows container/base-container IDs with source read status and original observations. Equivalent GUID formats preserve the first original text; conflicting values stay unresolved, empty GUIDs remain unassigned, and malformed values stay available without discarding valid device records. These are Windows grouping IDs, outside normal component-ID totals and serial comparisons.
- Fixed native/property hardware-ID and compatible-ID disagreements remaining unflagged. Both exact observations are retained, native lists stay preferred, and device review explains the disagreement. Compatible-ID lists now have their own source and recovery counts. Leading zeros, case, padding and order remain available in saved data.
- Validation: **1,572 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 68 new ID-completeness checks in direct/worker modes. The previous build fails the source-conflict fixture. Live audits on both runtimes matched 169 nodes, 252 exact native lists and 338 independently read grouping GUIDs with zero mismatches. A full live scan/rescan read all 17 sections, refreshed both extended catalogs and preserved the previous snapshot (32.10s / 30.79s on this PC).

See [ID scanning accuracy and coverage](IDENTIFIERS.md#id-scanning-accuracy-and-coverage) for field definitions, source evidence and limits. No scan can recover identifiers that Windows or the device does not expose.

## 3.70

- Reorganized **Main [3] > [4] Graphics & network** into compact graphics, network and monitor sections with three jump shortcuts. Network interfaces are grouped by reported hardware flags; raw records remain available in Main [5] and saved reports.
- Fixed the modern CIM fallback promoting a single reported network address into a confirmed current MAC. It now preserves the candidate/list separately, states that current address is unidentified, and skips unreliable current-address comparisons. Explicit primary/legacy MAC fields remain usable.
- Replaced the fallback's generic speed claim with receive/transmit rate labels, retained raw directional values, and labeled legacy bandwidth as an estimate. Permanent addresses are labeled Windows-reported; absent optional IDs on non-hardware interfaces no longer claim “not used.”
- Graphics modes are labeled WMI-reported and require valid positive width/height values. Missing, incomplete and invalid dimensions remain explicit. The hardware viewer also gives raw network Speed fields the correct bits/s context instead of the memory MHz label.
- Added a [field audit](GRAPHICS-NETWORK.md) comparing previous claims with Windows definitions, including the direct CIM fallback's potentially smaller adapter set. No GPU-to-monitor mapping or internet-performance guarantee is inferred.
- Validation: **1,504 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5. Fifty new checks include direct/worker readers, snapshots/comparisons and native 80/24-column navigation. Both live audits matched 16 primary adapter records with zero differences; the forced CIM fallback returned 4 records with correctly unresolved current addresses and directional rates. A full live scan/rescan read all 17 sections, refreshed both extended catalogs and retained the previous snapshot (29.06s / 27.56s on this PC).

## 3.69

- Added the requested 3-second reading pause in CMD preparation before any PowerShell probe starts. The Windows timer displays its countdown with `/nobreak`, so ordinary/held Enter input cannot rush the screen. The dedicated PowerShell window does not repeat this BAT-only pause.
- Handle missing, blocked or failed timer execution and redirected input as optional presentation failures. Startup shows one informational line and continues; runtime restrictions, body validation and checker exit codes retain their existing behavior. The timer is resolved by its absolute Windows path, so PATH shadowing cannot replace it.
- Validation: 1,454 checks on each of Windows PowerShell 5.1 and PowerShell 7.6.5. Fourteen new checks cover real attached-console timing with Enter queued, headless input, missing/failed timers, empty/shadowed PATH, blocked/missing runtimes and exit-code preservation. The earlier version fails the preparation-pause regression fixture. Existing local v3.68 scanning fixes are retained.

Microsoft documents the native [`timeout /t` and `/nobreak` options](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/timeout). The countdown is a bounded reading pause rather than a dependency on an installed PowerShell runtime.

## 3.68

- Fixed the normal Win32 present-device reader accepting rows explicitly marked `Present=false`. It now applies the same exclusion as the present-only fallback; an all-disconnected primary result can recover through that fallback. Unknown presence stays unknown, and the all-known catalog continues to retain disconnected records.
- Fixed singleton containers being string-coerced into apparent RAM/disk sizes, link speeds, drive letters, storage codes or network status. Shared scalar validation rejects lists/objects/booleans/date-like values while preserving zero, numeric strings and supported integer ranges. Integral enums use their underlying numeric value in numeric readers.
- Fixed nested monitor-code containers and list-shaped text lengths manufacturing decoded values. Invalid fields retain their raw observations without discarding valid neighboring monitor records or identifiers.
- Fixed calculated raw metadata fields losing singleton-list shape. Storage codes, partition drive letters and fallback network status/speed observations preserve their original scalar/list structure through collection and saved JSON. Scan arrays are copied without serialization decorations so PowerShell 5.1 does not export singleton arrays as `value`/`Count` wrapper objects.
- Validation: 1,440 checks on each of Windows PowerShell 5.1 and PowerShell 7.6.5, including 41 new scalar/presence checks in direct and worker modes. Baseline fixtures reproduce the old false-present and numeric-container behavior; snapshot round trips preserve raw data and exact identifiers. Read-only live tests cover scanning, rescanning and present-only fallback.

Microsoft documents [memory capacity as a UInt64 scalar](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-physicalmemory), [monitor IDs as UInt16 arrays with scalar lengths](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorid), and [PnP presence as a Boolean property](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity). Coverage still depends on available Windows providers and access.

## 3.67

- Added visible CMD preparation stages before the checker starts: preparing, checking compatible PowerShell and launching. The PS1 loader also displays preparation. Progress reflects actual steps and adds no fixed delay.
- Fixed missing/blank embedded checker content sometimes being accepted as a successful launch. All three loaders validate the marker/body before invocation; BAT failures retain their exit codes and show a START-02 summary. Existing runtime/version/language-mode restrictions remain in place.
- Added application failure handling with bounded, control-character-safe diagnostics and phase context. Uncaught PowerShell errors use CRASH-01, clean up worker/timer/navigation state and exit nonzero; interactive dedicated windows keep the message available until Enter.
- Added recovery around menu actions. UI-01 retains the active inventory and warnings, clears transient operation state and returns to the main menu after Enter. It does not trigger an automatic rescan, export or crash-log write. A failure of the menu itself stops visibly rather than retrying indefinitely.
- Updated the startup diagnostic to replace the application's fatal trap with its test reporter, avoiding duplicate trap definitions.
- Validation: 1,399 checks on each of Windows PowerShell 5.1 and PowerShell 7.6.5, including 35 new recovery checks and the eight existing runtime-launcher checks. Fixtures cover real CMD/PS loader execution, corrupted content, preserved exit codes, cleanup failures, retained snapshots, fatal phases and the actual main-menu loop. The previous version exits 0 for a blank body; the updated loader exits 1 with an incomplete-file message. A read-only live scan/rescan verifies normal collection.

## 3.66

- Fixed the active scan reserving 4,096 mostly blank buffer rows, which made the scrollbar extend far beyond scan content. Normal and separate extended scans now maintain history around the actual written rows, including wrapped output in narrow windows. Menus still clear their report history.
- Fixed live progress/waiting redraws moving the console cursor and pulling the viewport away while browsing. Status text now paints directly into its buffer cells; newly completed rows preserve a reader's chosen view. Scrolling back pauses following; End resumes following new results.
- Added Up/Down, Page Up/Down, Home and End handling during worker queries and between scan rows. Input processing is limited to 32 keys per pass; Enter/menu keys remain ignored during collection. The scan screen explains its navigation controls.
- Kept scan rendering optional for collection: redirected diagnostics avoid console-only geometry reads, resize mismatches skip stale timer coordinates, and early render failures clear navigation state and restore cursor visibility.
- Validation: 1,323 synthetic checks and 33 native-console checks on each of Windows PowerShell 5.1 and PowerShell 7.6.5. Native checks cover injected keyboard input during a live worker query, mouse-style viewport movement, held Enter, narrow full scans, wrapped history, resize handling and cleanup. A read-only live scan/rescan verifies hardware coverage and catalog refresh.

Microsoft documents that [cursor positioning outside the visible window moves the window origin](https://learn.microsoft.com/en-us/windows/console/setconsolecursorposition). The live status painter avoids that cursor movement, while buffer sizing follows the [console window/buffer constraints](https://learn.microsoft.com/en-us/windows/console/setconsolescreenbuffersize).

## 3.65

- Startup and full PC rescans now include the all-known device catalog automatically, including Windows-exposed hidden/disconnected records. The normal present-device list remains separate so remembered nodes do not become false arrivals or active-device counts. Older present-only captures also gain the catalog on their next rescan.
- Fixed the overall progress bar reaching 100% before extended collection finished. Full scans use 18 stages: 17 normal sections plus the device catalog. Completion still reports unread sections/catalogs explicitly, and the scan continuation prompt remains available afterward.
- Fixed one terminating device-property query preventing detail reads for unrelated devices. Property reads now use batches of up to 32 nodes, preserve partial successful rows and continue later batches. Generic terminating batch failures receive one bounded per-device recovery pass; access/timeouts/provider failures avoid that retry expansion.
- Contained non-terminating optional property errors in both scan modes so valid rows stay usable. Full reports/JSON retain property-batch/retry/error counts, and failed property values remain unknown. Successful later reads clear prior recovery diagnostics.
- Validation: 1,323 synthetic checks on Windows PowerShell 5.1 and PowerShell 7.6.5, including 36 new coverage checks. Read-only live verification covers initial scans, rescans, extended catalogs and present-device fallback.

Microsoft documents [Get-PnpDevice without `-PresentOnly`](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdevice) as returning all known PnP devices, present or not. Coverage remains limited to records Windows exposes; a catalog entry does not prove a physical device is connected.

## 3.64

- Fixed standard WMI unsupported/missing-provider errors being reported as generic failures. Their HRESULTs now enable the existing present-only fallback even when Windows returns localized error messages. The successful reader and original failure remain in scan diagnostics.
- Recognize WMI operation/provider timeouts and missing privileges, including legacy `ErrorCode` names. Access/timeouts cannot trigger an invalid-property retry or present-device fallback; the failure guidance describes the actual category. Unknown/reserved errors remain generic failures.
- Fixed padded duplicate device IDs sometimes producing a duplicate conflict plus a separate status finding for the same node. Review now uses the same normalized, ordinal case-insensitive keys as node-change matching. Distinct statuses remain together, and original ID text stays unchanged.
- Scan rows, overview model coverage and extended review now agree that whitespace/NUL-only identifiers are missing and non-string model entries are unusable. Raw inventory rows remain available for inspection.
- Validation: 1,287 synthetic checks on Windows PowerShell 5.1 and PowerShell 7.6.5, including 60 new scan-diagnostic checks for localized HRESULTs, fallback scope, retry suppression, exact raw values, duplicate review and saved snapshots. Read-only live checks cover scanning, rescanning, extended collection and present-device fallback.

Error classification follows Microsoft's [WMI error constants](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wmi-error-constants). No device configuration changes are made by these recovery paths.

## 3.63

- Recovered valid device-instance identifiers from PNPDeviceID, InstanceId, or the Windows DeviceID key, in that order. Blank/whitespace/NUL-only aliases no longer hide a usable alternative. Both Win32 queries explicitly request DeviceID, and raw validation covers the added key.
- Preserved the selected identifier's original text and its InstanceIdSource. Property queries, native lookup, and parent-name matching use normalized lookup keys without rewriting the stored ID.
- Applied the same hardware/compatible-list validation to normal and extended collection. NUL-only/blank strings do not count as usable model IDs; malformed entries retain their raw values and review details while neighboring valid IDs survive.
- Retained all optional model-list observations rather than overwriting earlier lists. Usable primary lists stay preferred; when they are absent, valid property observations are combined in first-observation order with exact deduplication. Differing readings are flagged for inspection, and original sequences remain available in full reports/JSON.
- Validation: 1,227 checks on Windows PowerShell 5.1 and PowerShell 7.6.5, including 62 new instance-alias/ID-list checks; a real 17-section scan/rescan, live extended catalogs on both runtimes, and present-only fallback agreement in direct/worker collection. Separate v3.62 copies reproduce the omitted DeviceID and NUL-only model-ID failures.

Microsoft documents [DeviceID as a device key](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) and [hardware IDs as an ordered driver-matching list](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/hardware-ids). A combined list of differing observations is an inspection view, not an authoritative Windows driver-priority list.

## 3.62

- Fixed the present-device view accepting malformed raw instance/class keys that the startup scan rejected. Both present-device reader paths now share record validation before mapping or publication; invalid refreshes remain NOT READ / READ-06.
- Stopped arrays, objects, booleans and dates from becoming Working/Disabled problem codes through string coercion. Valid numeric/string/enum status codes, including zero, remain usable.
- Preserved distinct optional problem-code readings and flagged disagreements with each other or native status. Conflicting status stays unknown; invalid optional readings cannot hide a valid native driver finding. Raw observations and read-status details remain in full reports/JSON.
- Isolated malformed optional parent metadata instead of discarding the core device catalog. The parent remains unresolved, its raw value is retained, and extended review explains the missing topology. Extended enumeration also maps the Class alias when PNPClass is absent.
- Made extended view groups independent filters. Hidden remembered devices appear under Hidden and Disconnected; hidden disabled devices appear under Hidden, Disabled and Present. Counts are explicitly non-additive.
- Validation: 1,165 checks on Windows PowerShell 5.1 and PowerShell 7.6.5, including 80 new PnP-refresh/hidden-device checks; a real 17-section scan/rescan, extended reads on both runtimes, and native console navigation/scrolling checks. Separate v3.61 baseline copies reproduce the malformed-key/status failures before these fixes.

Microsoft describes [hidden devices](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/viewing-hidden-devices) as including node/class hiding flags and non-present records. The checker keeps those properties separate while allowing the corresponding views to overlap.

## 3.61

- Fixed repeated extended-refresh failures showing an older technical message alongside the latest failure code. Manual retries now retain their latest failure details separately from an older catalog and clear those details on successful recovery.
- Validated extended enumeration and catalog results before publication. Scalar/empty device records, non-scalar instance keys, and missing capture metadata cannot be marked Refreshed. A malformed primary enumeration can use its compatibility reader; failed manual refreshes retain the previous catalog, while failed PC-rescan refreshes keep new normal results without attaching an old catalog.
- Kept contradictory presence and node-status property readings unknown rather than choosing whichever arrived last. Distinct readings are retained in PresenceReadings/NodeStatusReadings, with conflict labels in extended review; matching duplicate readings remain usable.
- Rejected arrays, booleans and objects as node-status numbers. Unknown flags remain separate from a definite hidden/present state, and native fallback does not override conflicting property readings.
- Ignored malformed optional property keys without allowing them to match a real device; InvalidPropertyRows records the count. Missing instance IDs in otherwise readable extended nodes now appear explicitly in detail review.
- Validation: 1,085 checks on Windows PowerShell 5.1 and PowerShell 7.6.5, including 66 extended-refresh regressions; a real 17-section scan/rescan with zero rescan query warnings; and live extended-device catalogs on both runtimes. The new suite reproduces a contradictory-presence failure against v3.60 before the fix.

Windows exposes [device presence](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) and [node status flags](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-devnodestatus) as separate properties. A collection-time disagreement remains a review finding rather than a confirmed hardware change.

## 3.60

- Fixed compatible reads being skipped when a CIM/WMI reader emits records followed by an uncaught non-terminating property error. Each attempt now buffers and validates its error stream before returning records or selecting a retry.
- Fixed partial network and extended-device enumeration preventing their compatibility fallbacks from recovering. Failed primary rows are discarded; recovered results retain the selected reader and original diagnostic where recorded.
- Shared attempt validation with the present-only PnP fallback. Direct and live-progress collection use the same helper, while extended fallback keeps its unfiltered scope for remembered records.
- Preserved query filters, namespaces, timeout settings, the single property retry, exact identifiers and false/zero metadata. Access/timeouts are not reclassified as property errors; failed attempts retain typed final failures and cannot publish incomplete rows.
- Added 34 regressions covering partial-error recovery, failed retries, legacy WMI, network/extended fallback, clean subsequent queries, snapshot round trips, and comparisons in both collection modes.
- Validation: 1,019 checks on Windows PowerShell 5.1 and PowerShell 7.6.5; real network/extended fallback recovery in both collection modes on both runtimes; and a read-only 17-section scan/rescan with extended refresh and no rescan query warnings.

PowerShell can continue after a [non-terminating error](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters). The checker now validates each reader attempt using [separate success/error streams](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection) before accepting its data.

## 3.59

- Added a present-device fallback for unsupported Win32 PnP queries/providers or empty results. It uses `Get-PnpDevice -PresentOnly`, maps available instance/name/class aliases, and keeps model/compatible IDs separate. It does not widen the normal scan into disconnected records.
- Left access and timeout failures with their original guidance, without invoking the new reader. Failed fallback attempts retain both diagnostics and classify the final failure. Two empty readers remain READ-04; missing/unsupported readers remain READ-03.
- Retained fallback source on device records and the original failure in scan timing/saved reports. Compatible-read completion wording now covers recovered readers as well as property queries.
- Fixed localized typed `CommandNotFoundException` and `NotSupportedException` being classified as generic read failures.
- Buffered both present-device readers' error streams so uncaught partial errors cannot trigger an inappropriate retry or publish incomplete rows as success.
- Validation: 985 synthetic checks under Windows PowerShell 5.1 and PowerShell 7.6.5, real present-only fallback agreement in both collection modes, native console checks and a read-only 17-section scan/rescan with extended refresh.

Microsoft documents the [Win32 PnP Present property](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) as unsupported on some older Windows versions. The fallback follows [Get-PnpDevice -PresentOnly](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdevice), when that command is available.

## 3.58

- Added directional moving borders and clearer two-stage arrow trails to Next/Back. Exit closes both the track and border toward the center before Goodbye. Existing console colors and the three-row animation area are preserved.
- Shortened navigation timing: Back 160 ms, Next 200 ms and Exit 260 ms. Queued keyboard input skips the remaining motion without reading or discarding that input.
- Kept action labels visible in narrow windows and honored explicit Back destinations. Frame geometry remains bounded and destination controls are sanitized.
- Retained original text, per-cell colors, cursor visibility, viewport and input modes after completed or skipped animations. Shared/redirected consoles and `HWID_NO_ANIMATION=1` continue to skip motion.
- Validation: 603 existing regressions and 38 animation checks on Windows PowerShell 5.1 and PowerShell 7, plus native console checks covering completed/input-skipped transitions, exact cell restoration, bounded history and preserved queued input.

## 3.57

- Stopped counting records containing only null, blank/null-padded strings or empty lists as readable hardware. These receive READ-06; genuine zero/false metadata and devices with a name/key but omitted serials remain readable.
- Validated the present-device scan's hardware/compatible ID lists. Valid strings are retained, malformed entries stay in separate raw fields, and affected nodes get explicit scan/review messages without discarding the remaining device inventory.
- Fixed model-list counts accepting non-string values in older/custom records. Counts now reflect nodes with usable model strings, independently of device-instance IDs.
- Preserved singleton string lists and exact valid ID text across direct collection, live-progress collection and saved snapshot round trips.
- Validation: 918 synthetic checks under Windows PowerShell 5.1 and PowerShell 7.6.5, including 27 new scan-content checks, plus native console and read-only scan/rescan checks. Existing full-scan fixtures now populate the requested OS/monitor/partition fields so they continue to represent successful provider reads under the stricter validation.

Microsoft documents [Win32_PnPEntity HardwareID and CompatibleID](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) as string arrays. Empty model-ID lists can be normal and do not by themselves create a warning.

## 3.56

- Added final TXT/JSON content verification before announcing a successful save. Both files are compared with the requested content in bounded chunks; missing, changed or unreadable files fail the save and trigger existing rollback/cleanup handling. Existing report files are never overwritten.
- Saved a separate `SavedAt` timestamp on a copy of the active report. The scan capture time, scan number and live identifiers remain unchanged, so repeated saves do not become new scans or manufacture comparison differences.
- Fixed copied arrays exporting as value/Count wrapper objects on Windows PowerShell 5.1 by allocating plain object arrays. Device records keep the same JSON structure across both supported runtimes.
- Organized save results around verified files, scan/save time, readable normal-section coverage and the actual destination. Partial captures can still be saved for diagnosis, with coverage shown explicitly.
- Prevented live progress callback failures from discarding valid hardware results. A failed callback is disabled for the rest of that query, its diagnostic stays separate in scan timing, and the next query starts with clean feedback state. Provider errors keep their own classification.
- Validation: 891 synthetic checks under Windows PowerShell 5.1 and PowerShell 7.6.5, including 22 save/scan-handling regressions, plus native console and read-only scan/rescan checks.

## 3.55

- Fixed network fallback status labels for numeric strings, including padded values. Booleans, negative/fractional values and out-of-range codes remain explicitly invalid rather than becoming Up/Down. Modern operational states and legacy connection states use their own mappings.
- Stopped treating the first of multiple distinct reported network addresses as the current MAC. An explicit current address wins; a single distinct list address can be used; an unresolved multiple-address list remains missing for comparison, with the full list and reason retained.
- Ignored non-string address-list entries when selecting a MAC while preserving the original list. Equivalent hex addresses with different separators/case do not create false ambiguity. Existing permanent MAC values remain separate.
- Preserved the raw modern interface status code in full reports and snapshots. Both direct and live-progress readers use the same helpers.
- Validation: 869 synthetic checks on Windows PowerShell 5.1 and PowerShell 7.6.5, native console checks, real network fallback agreement between both scan modes, and a read-only 17-section scan/rescan with a refreshed extended catalog.

Network property types and status meanings follow Microsoft's [MSFT_NetAdapter](https://learn.microsoft.com/en-us/windows/win32/fwp/wmi/netadaptercimprov/msft-netadapter) and [Win32_NetworkAdapter](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter) references. When fallback data does not identify a current address, the checker treats multiple distinct values as unresolved.

## 3.54

- Fixed false identifier changes when imported JSON uses different capitalization for recognized section or field names. Comparison rows now use stable schema names; raw imported data and identifier values retain their original spelling, letter case and leading zeros.
- Fixed arbitrary pairing of multiple system/firmware records without matching device keys. These sections are now disclosed under Not compared, with a scan-data conflict in warning review. Single-record firmware comparisons remain available.
- Kept actual identifier-value comparisons case-sensitive. Missing/default fields with case-varied names are skipped on both sides rather than shown as removed IDs.
- Validation: 828 synthetic checks on each supported PowerShell runtime, including 34 new comparison-identity regressions, plus native console and read-only scan/rescan checks.

Schema-name handling follows PowerShell's [JSON conversion behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json). Duplicate JSON names are still rejected before import.

## 3.53

- Recovered scan sections when a Windows provider rejects a requested property: retry once using available properties, while keeping the same reader, namespace, device filter and CIM timeout. Unsupported fields remain missing; IDs are never guessed.
- Buffered each reader attempt so records emitted before a failure cannot leak into a successful retry or duplicate devices. Access failures, timeouts and missing classes keep their existing failure handling.
- Marked successful recovery as `compatible read` in scan lines and retained the original diagnostic, class and method in scan timing, full inventory and saved reports. The finished scan reports how many sections recovered.
- Kept direct and live-progress scans consistent: recovery notes travel separately from hardware records and reset before each query. Failed retries retain both messages and use the final error for classification.
- Validation: 794 synthetic checks on Windows PowerShell 5.1 and PowerShell 7.6.5, native console checks, and an actual read-only live-progress scan/rescan reading all 17 sections with zero query warnings and a refreshed extended catalog.

Retry classification follows Microsoft's [WMI error constants](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wmi-error-constants); property selection follows [Get-CimInstance](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance).

## 3.52

- Added Main [8] storage status with readable snapshots, older usable baselines, TXT/JSON pairs, JSON-only and TXT-only files, and per-file recovery advice. Folder opening remains available; failures do not hide the summary.
- Distinguished locked/unavailable files, access failures, invalid encoding, damaged JSON, oversized imports and unsupported versions with stable STORE codes. Other readable snapshots remain available and refresh picks up recovered files.
- Prevented lossy UTF-8 decoding from silently changing imported identifiers. Strict UTF-8 and BOM-marked UTF-16/UTF-32 imports preserve legacy exports; one read handle checks the size limit and excludes active writers, with disposal on failure.
- Fixed .NET Framework text-reader behavior that could drop incomplete trailing characters. Whole-buffer strict decoding rejects truncated UTF-8/UTF-16/UTF-32 consistently on both supported PowerShell runtimes.
- Fixed relative imports resolving against the process directory rather than the PowerShell location.
- Applied the existing palette by meaning: green older baselines, gray same-capture labels, yellow retry/context warnings and red invalid-data failures. Save results use matching status colors and point to storage details.
- Validation: the existing 722 synthetic checks plus 38 storage checks under Windows PowerShell 5.1 and PowerShell 7, and native console storage navigation/scrolling checks. Existing user reports are preserved.

## 3.51

- Hardened optional scan conversions so invalid metadata does not throw during property projection or discard usable identifiers. Storage codes use validated uint16 values; valid unknown codes remain explicit and malformed codes remain unknown.
- Distinguished invalid partition drive-letter values from unassigned letters. Character codes and text letters are supported, with original values retained for inspection.
- Fixed monitor numeric-string code comparisons dropping characters. Decoding validates codes, preserves leading zeros/null padding, honors reported name lengths and exposes invalid-code/length status alongside original arrays.
- Fixed a live-tested monitor provider compatibility failure: optional length fields are no longer required in the query projection. The reader uses the properties the provider exposes and applies length metadata when available.
- Prevented negative, boolean, fractional or malformed byte sizes from becoming plausible capacities. Real zero and supported uint64 byte values remain usable; raw memory/disk/volume/partition sizes are retained.
- Corrected raw network speed labels to bits/s rather than memory-speed MHz.
- Validation: 603 existing regressions, 26 snapshot checks, 28 ID-view checks, 24 review checks and 41 scan-metadata checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native console checks and an actual read-only scan/rescan.

Field types follow Microsoft's [disk](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-disk), [partition](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-partition), and [monitor](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorid) references.

## 3.50

- Fixed unread sections disappearing from review when warning text was absent. Current unavailable/empty section data and extended failure metadata now drive the read-failure model, while warning text remains a fallback for older/custom queries.
- Collapsed repeated warnings per section and stopped stale warnings from keeping a refreshed, readable section in Not read. Stored localized failure codes/advice and raw diagnostics are retained.
- Fixed duplicate PnP rows inflating ordinary device findings. Repeated instance IDs count once as a conflict with their distinct status readings preserved. Shared model IDs remain normal.
- Classified Windows code 12 as a resource conflict. Disabled/disconnected states retain their separate meanings and advice.
- Unified compact/dashboard/review totals. Review now provides a suggested starting group, explicit empty-group results, device instance context, and clear Main [5] links that do not conflict with the page shortcut.
- Validation: 603 existing regressions, 26 snapshot checks, 28 ID-view checks and 24 review checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native navigation/layout checks.

Status meanings follow [Microsoft's Device Manager error reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-manager-error-messages); findings alone do not establish hardware failure.

## 3.49

- Organized ID numbers/serials into five groups with section shortcuts, snapshot context and explicit unread-section names. Added chassis serials and distinct current/permanent MAC rows without inventing fields in older schemas.
- Fixed null rows creating phantom missing quick-view IDs and ambiguous labels when multiple system/board records are present. Separate records keep repeated values and leading zeros.
- Fixed malformed scalar IDs/device keys being counted as found and then failing report export. Scan and import validation now share the scalar-value check; failed scan fields produce READ-06. Valid empty/wrapped strings remain missing fields, and ordinary booleans, zero indices, dates and ID arrays remain supported in their proper fields.
- Removed terminal control characters from displayed table text and wrapped values while preserving the raw report values. Narrow windows retain the stacked view and content-sized scrolling history.
- Fixed malformed adapter-type metadata suppressing missing IDs. Only a real boolean false marks an adapter as virtual for the not-applicable exemption.
- Validation: 603 existing regressions, 26 snapshot checks and 28 ID-view checks under Windows PowerShell 5.1 and PowerShell 7.6.5, native section/narrow-view navigation checks, and an actual read-only scan/rescan.

Identifier scopes follow Microsoft's [processor](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor), [monitor](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorid) and [storage identification](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/device-unique-identifiers--duids--for-storage-devices) references.

## 3.48

- Added saved-snapshot discovery after saving and when opening comparison. It checks the normal, per-user fallback and adjacent installation report folders, includes renamed JSON files, and skips damaged/unsupported reports with a visible count.
- Added a paged baseline picker with refresh and manual-path fallback. Older usable captures from this PC rank first; same-time, newer, other-PC, unknown-time and no-usable-ID captures are distinguished using capture metadata rather than file modification time.
- Added TXT-to-matching-JSON lookup. Comparison results retain exact OLD/NEW IDs and character differences, with section shortcuts and warnings for same-time or newer baselines.
- Added verified-pair saves in the user's local app-data report folder when the normal location has a filesystem/access failure. Invalid data does not trigger a fallback retry; failed partial publication is cleaned up before retrying. Folder navigation follows the last successful save.
- Validation: the 603 existing regression checks plus 26 snapshot discovery/save/comparison checks under Windows PowerShell 5.1 and PowerShell 7.6.5, and native comparison/picker navigation checks.

The fallback uses the per-user storage purpose documented by [Microsoft's LocalApplicationData reference](https://learn.microsoft.com/en-us/dotnet/api/system.environment.specialfolder).

## 3.47

- Added Enter to continue after the startup scan and PC rescans. Finished scan rows remain available for scrolling before opening the menu or snapshot changes; redirected diagnostics continue without an interactive pause.
- Added held-Enter release handling and bounded draining of scan-time keystrokes in the dedicated console. Continue prompts do not accept unrelated keys or zero as navigation commands.
- Added Win32_NetworkAdapter as a final network fallback when Get-NetAdapter and MSFT_NetAdapter are unavailable or empty. Virtual/disabled records, zero/false values and available interface/device IDs are retained; a missing permanent MAC remains unknown.
- Labeled network fallback use on the scan row. Full reports retain the selected CollectionSource, and failed reads keep all three diagnostics while classifying the final failure.
- Fixed link-speed conversion errors from malformed optional provider values. Unread speeds remain unknown and their raw values are retained; adapter identity is preserved.
- Validation: 603 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5, native console continuation/navigation checks, actual launcher continuation/held-Enter checks, and a read-only hardware scan/rescan.

The final compatibility reader uses fields documented in [Microsoft's Win32_NetworkAdapter reference](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter). Modern readers remain first choice.

## 3.46

- Fixed empty extended-device enumeration skipping its fallback reader. Empty and null-only results now retry the unfiltered CIM/WMI reader; recovered catalogs record the fallback reason.
- Fixed null-only network output being accepted as a blank adapter instead of triggering fallback or a no-records failure.
- Preserved typed exceptions and PowerShell error categories when both network or extended readers fail. Technical details keep both messages while classification describes the final reader, so an earlier access error cannot hide a later provider failure.
- Fixed live-progress query invocation wrapping errors and losing categories. The original error record now reaches the scan checker, consistently with direct queries.
- Added extended READ / NOT READ to the scan finish line. An optional extended failure keeps that line amber even when all 17 normal sections were read.
- Validation: 585 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native console checks and an actual read-only scan/rescan with extended collection.

The extended scan uses the all-known-device scope described in [Microsoft's Get-PnpDevice documentation](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdevice), including non-present records that Windows exposes.

## 3.45

- Clarified summary read status and added explicit unread normal-query counts. Read completion is distinct from identifier/device findings.
- Fixed the summary Review line appearing clear when only missing/default IDs needed review. Its total now matches the review page and keeps the warning color when findings exist.
- Renamed device totals as records and hardware-ID coverage, avoiding an implied count of unique physical devices. Class totals ignore casing and surrounding spaces without changing raw data.
- Added unknown-presence counts alongside unread visibility flags for extended catalogs.
- Fixed failed manual extended refreshes leaving the old catalog apparently current. Summary labels retained data PREVIOUS, keeps its capture time, and makes the latest failure available in review. A first failed attempt is NOT READ rather than Not scanned.
- Successful extended recovery clears stale failure warnings/metadata. Repeated failures keep one current warning, and a PC rescan retries a previously requested extended scan even when its first attempt produced no catalog.
- Validation: 560 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native overview, review and full-report navigation checks.

The class-count fix avoids the default case-sensitive behavior of [Select-Object -Unique](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/select-object?view=powershell-5.1), and works on both supported PowerShell engine families.

## 3.44

- Fixed partial query output being accepted after an uncaught non-terminating error. Direct and live-progress query modes now reject those incomplete results and preserve the failure category.
- Added READ-06 for unusable scan data. Scalar/list output and records with no fields no longer count as successfully read hardware.
- Fixed empty unavailable-marker messages being mistaken for readable records; those markers now receive a clear diagnostic fallback.
- Preserved valid missing-ID records, false/zero/empty-list field values, and successful fallbacks that handle their own primary errors. Failed query state does not leak into the next query.
- Validation: 542 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5. A read-only actual scan and rescan each read 17/17 sections without rescan warnings, and the extended catalog refreshed successfully.

PowerShell commands can explicitly override the error preference; see [Microsoft's common-parameter documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters). The checker distinguishes an error that escapes a query from an error deliberately handled by a successful fallback.

## 3.43

- Added conflicts to the review summary, with separate totals for conflicts, unreadable sections, device findings, missing IDs and default IDs. The dashboard and overview use the same classification.
- Added a dedicated Conflicts section and shortcut 5. Duplicate instance IDs appear there once rather than also inflating device findings. Counts describe findings, not unique devices.
- Confirmed disk serial clashes show the actual values separately under Physical disks and Storage identifiers, with next steps.
- Fixed ambiguous disk matching: joins require one valid disk number in each source. Duplicate/malformed numbers cannot create false serial clashes or fill multiple missing serials from one alternate record. Null rows are ignored and the full unsigned Windows disk-number range is supported.
- Added context-specific device advice, instance-ID labels for unnamed devices, and an explicit disconnected status. Placeholder text is sanitized before display.
- Validation: 521 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native console checks for conflict/unread/ID shortcuts and full-report navigation.

Windows code 22 means [the device is disabled](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-disabled); this alone does not establish hardware failure. [Storage identification guidance](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/device-unique-identifiers--duids--for-storage-devices) also describes limits of relying on a single storage identifier.

## 3.42

- Corrected unavailable-marker results that could appear as successful scan rows. Failed reads now report zero captured records consistently.
- Added READ-01 through READ-05 failure reasons and next steps. Typed exceptions, PowerShell error categories, and standard WMI HRESULTs improve classification on non-English Windows. Unknown errors remain explicitly unknown.
- Preserved raw diagnostic text, reason codes and suggested actions in failed-section metadata and scan timing exports. Normal scans, refreshed PnP views and extended scan failures use the same classifications.
- Flagged missing device instance IDs for review and included them in PnP scan missing counts. Missing model IDs alone are not treated as proof of a problem.
- Reorganized review into device findings, sections not read, and missing/default identifier fields. Added section shortcuts and top-of-page navigation while preserving full-report bookmarks.
- Validation: 501 synthetic regression checks under Windows PowerShell 5.1 and PowerShell 7.6.5, plus native console checks for review shortcuts, scrolling, scan rows, cursor restoration and full-report navigation.
- A read-only actual-hardware scan and rescan each read all 17 sections, with zero rescan query warnings and the previous snapshot retained.

Provider timeouts are reported rather than treated as missing IDs. The timeout is an API operation setting, not a guaranteed overall scan deadline; see [Get-CimInstance](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance) and [Windows PnP properties](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity).

## 3.41

- Fixed device browsing so USB input devices, cameras, audio and Bluetooth devices appear under their function. Unclassified USB nodes still appear under USB.
- Added unread/malformed Windows device status to review counts with an explicit unknown-condition explanation. Null provider rows are ignored.
- Accepted matching single or double quotes around pasted comparison paths. Apostrophes and other literal path characters are preserved; unmatched quotes, empty quoted paths and control characters get specific errors.
- Validation: 484 regression checks pass under Windows PowerShell 5.1 and PowerShell 7.6.5, plus eight launcher checks and native console diagnostics.

Grouping follows Microsoft's distinction between [device setup classes and interface classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/comparison-of-setup-classes-and-interface-classes) and its [system-defined setup classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors).

## 3.40

- Reorganized scan overview into results, query coverage and next actions.
- Separated identifier counts, present devices and extended-device groups.
- Kept unknown counts distinct from zero, with separate extended capture times.
- Verified normal, extended and failed summaries in the standard console, plus narrow-window scrolling.

## 3.39

- Added runtime/version checks and clearer compatibility errors.
- Added the alternative `Start-HWID.ps1` launcher.
- Improved handling of missing optional Windows commands and providers.

## 3.38

- Improved Next, Back and Exit animations.
- Preserved report text, colors, scrollback and queued keyboard input during transitions.

## Earlier improvements

Added hidden/remembered device details, rescanning, device-arrival/removal review, clearer saved-report comparisons and safer TXT/JSON export handling.

Older versions already committed to this repository are available through Git history. Loose local backups are not release files and are excluded from Git.
