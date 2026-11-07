# Recent changes

[Back to the main README](../README.md)

## Desktop 1.4.1

- Fixed the desktop update dialog reporting a stale version: the app now derives its own version from the built assembly, so the sidebar, the updates dialog and the updater always agree with the installed binary.
- The updater now distinguishes "already installed on disk, restart to load it" from a failed check instead of reporting a generic version error when files are newer than the running window, and the desktop startup surface shows that state.
- Updated the packaged updater stamp and package version to 1.4.1.

## Desktop 1.4.0 and BAT 3.86

- Added a battery section to the normal scan. Absent battery hardware reports an explicit "no battery" record instead of a failed read, and the Windows section now records the Secure Boot state and TPM presence/specification when Windows exposes them. Scan totals moved from 17 to 18 sections.
- Added **[9] > [6] Watch for changes**: the console can repeat the full scan on a 5/15/30/60-minute interval, compare each cycle against the previous snapshot and list exact identifier changes; any keypress during the countdown stops watching and keeps the latest scan.
- Comparison input now accepts zero-padded selections (for example 03) in the BAT snapshot picker.
- The desktop app added searching on the Review and Hardware pages, exports of the current snapshot as CSV and standalone HTML, a text export of comparison results, and comparing two saved snapshots directly without an active scan.
- The desktop app gained a Midnight/Daylight theme toggle (persisted with the other desktop settings).
- Fixed the automatic update selector: Windows PowerShell 5.1 returns a top-level JSON release array from ConvertFrom-Json as one nested array object, which made every release unreadable whenever more than one release was published. The selector now unwraps the nested array and matches tags without relying on automatic regex state.
- Fixed the release package itself: Windows PowerShell 5.1's .NET Framework ZipFile wrote archive entry names with backslashes, which the update verifier rejects. The build script now creates every entry explicitly with forward slashes under the expected package root.
- Test suite: section/group/progress counts moved to 18 sections and eight scan groups; `test-readable-startup` again matches the actual exit menu item (its injection anchor still targeted the pre-3.85 exit case and hung the child checker); scan-scroll, scan-completion and console-update fixtures track the 1.4.0 package version.

## Desktop 1.3.0 and BAT 3.85

- Use square desktop cards, controls and table borders. Move PC identity to the start of Overview and stack it at narrow widths.
- Prepopulate scan stages with Waiting status, distinguish live records from unfinished queries, and show section timings. Rescans label the previous completed snapshot while the new scan runs.
- Recover console progress after width changes and complete the standalone extended-scan result line before its report or failure details.
- Add background detection and preparation of newer compatible GitHub release packages, checksum verification, deferred installation, backups and rollback.

## BAT 3.84 and Desktop 1.2.0

- Share a preferred save folder and watched snapshot folders between the BAT and desktop app for the current Windows user.
- Reload shared settings when browsing or saving, preserve earlier report locations, and show where snapshots were saved.
- Improve Desktop discovery of older report encodings and align the library's file size limit with the BAT importer.

## Desktop 1.1.0

- Applied a slate and teal theme with shorter headers and action buttons that wrap in narrow windows. Tables and detail panes adjust to the available space, with shorter rows in compact windows.
- Added a hardware section picker for narrow layouts. The record menu shows readable device names, and tooltips show full values and paths. Rescanning refreshes the hardware records even when the section names and counts match the previous scan.
- Snapshot refresh keeps the selected capture when its file is still in the list. Double-click a capture row to compare it with the completed current scan.

## Desktop 1.0.0 — BAT scanner 3.83

- Added a native Windows WPF EXE with overview cards, live section progress, searchable identifier tables, full hardware fields, review findings, saved snapshots and exact previous/current comparisons. The embedded bridge loads scan/report functions from the connected BAT; the BAT source and its console behavior are unchanged.
- Added verified TXT/JSON saves, older-capture discovery across primary/fallback/custom folders, coalesced library refreshes and comparison validation through the existing engine. New completed scans clear stale details and comparisons. Cancellation preserves the last completed snapshot, and closing waits for engine cleanup.
- Added a self-contained Windows x64 portable package, custom icon, literal process arguments, UTF-8 protocol handling, bounded errors and cancellation/timeouts. The original console opens through the companion Start-HWID.ps1. Desktop settings store the selected BAT path and snapshot-folder paths.
- Validation: 33 bridge checks on each of PowerShell 5.1 and 7; 34 process-host checks; 21 desktop workflow checks; six rendered UI pages; successful live desktop scans of all 17 sections plus the device catalog. The packaged EXE's live scan retained 176 known device records and 13 UI timer ticks. Live diagnostics saved counts/status only; visual/export fixtures used synthetic IDs. The BAT remains SHA256 66001B42458B87FF1918AE258827979E2D6AE8AC04A7E67795394717825354E9.

## 3.83

- Fixed repeated parent-device properties silently replacing earlier observations. Different valid parent IDs now remain unresolved regardless of arrival order, with ParentInstanceIdConflict and complete ParentInstanceIdReadings. Consistent readings resolve using normalized keys while preserving original selected text; blank/NUL-only values no longer inflate parent-link counts.
- Fixed a malformed later parent observation erasing a valid earlier reading. Valid neighboring values remain usable, invalid entries retain explicit read status, and raw arrays/objects/booleans/numbers stay available for inspection. RawParentInstanceId keeps its earlier last-value behavior for report compatibility; the new observation list preserves the entire sequence, including batch-retry readings.
- Added a separate ParentLinkConflicts count, a scan-completion notice, extended-summary details and explicit unresolved parent labels. Review explains collection disagreement while retaining Windows status and core identifiers. Each refresh starts with fresh relationship state, and topology metadata does not manufacture ID changes.
- Added 56 regression checks covering opposite reading orders, equivalent case/padding, malformed neighbors, blank values, batch-retry changes, fresh state, JSON/TXT preservation, identifier comparisons and the completion/extended/detail UI in direct/worker modes. The v3.82 baseline reproduces the silent last-parent selection.
- Validation: 2,099 checks passed on each of Windows PowerShell 5.1 and PowerShell 7. Three full standard-user BAT launches read all 17 sections and returned properties for 177/177 requested nodes. Normal 100/24-column launches reported no parent conflicts; a controlled 24-column test retained one conflicting relationship, matched no arbitrary parent name and displayed the completion notice. All retained three blank buffer rows. Live diagnostics saved counts/status rather than hardware identifiers.

Microsoft defines [DEVPKEY_Device_Parent](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-parent) as a string containing the parent instance ID and describes how disconnected devices can refer to a remembered parent or the tree root. [Get-PnpDeviceProperty](https://learn.microsoft.com/en-us/powershell/module/pnpdevice/get-pnpdeviceproperty) supplies typed observations. The checker retains unresolved readings without inferring a physical hardware change.

## 3.82

- Fixed native CIM failures being overlooked when an exception exposed a zero StatusCode alongside a meaningful NativeErrorCode. Both read classification and property-retry detection now inspect all supported named status fields through exception wrappers. Native AccessDenied, InvalidOperationTimeout and unavailable-provider statuses retain specific READ codes without relying on English messages; malformed or unreadable optional status fields cannot replace the original diagnostic.
- Fixed localized NoSuchProperty / InvalidQuery failures skipping the existing bounded compatible-property retry. Namespace, filter, timeout and reader stay unchanged, partial output from the failed attempt is rejected, and named permission/timeout statuses prevent unnecessary retries. Native InvalidClass also enables the existing present-device fallback.
- Added 56 regression checks covering native/legacy status fields, zero-status masking, wrappers, unknown/malformed values, retry scope and call counts, partial-result isolation, present-device recovery, warning review, TXT/JSON and comparison behavior in direct/worker modes. The v3.81 baseline reproduces the native access-denial misclassification.
- Confirmed the fix with real restricted CIM reads: v3.81 reported generic READ-05 despite NativeErrorCode=AccessDenied in both modes under PowerShell 7; v3.82 reports READ-01 in both modes under PowerShell 5.1 and 7, with zero records accepted and no compatible-read claim. These diagnostics contain no hardware identifiers.
- Validation: 2,043 checks passed on each of Windows PowerShell 5.1 and PowerShell 7. Full standard-user BAT launches at 100/24 columns read all 17 sections and returned properties for 177/177 requested device nodes, reached the menu after one continuation and retained three blank buffer rows (23.19s / 25.32s). Live-test diagnostics saved counts/status rather than hardware identifiers; timings depend on the environment.

Microsoft documents the named [NativeErrorCode values](https://learn.microsoft.com/en-us/dotnet/api/microsoft.management.infrastructure.nativeerrorcode?view=powershellsdk-7.6.0), including AccessDenied, NoSuchProperty, InvalidQuery and InvalidOperationTimeout. Its [CIM_Error reference](https://learn.microsoft.com/en-us/windows/win32/hyperv_v2/cim-error) defines the corresponding CIM failure meanings. The checker preserves original diagnostics and does not assume numeric codes from other error domains share these meanings.

## 3.81

- Fixed per-query cleanup exceptions discarding validated hardware results or replacing the original provider error with a generic failure. Wait-handle closure and command disposal now run independently, preserving both cleanup diagnostics when both fail. Genuine provider failures still reject partial data and retain their READ codes.
- Added separate query cleanup diagnostics to Scan timing and extended-catalog metadata, an affected-section count in Report info and a completion notice pointing to Main [5]. These diagnostics do not inflate hardware warnings or change identifier comparisons, and each query starts with fresh state.
- Fixed standalone extended-device refresh cleanup escaping after a successful read or a handled query failure. Worker state is cleared before disposal; the catalog remains usable after a cleanup-only failure, while a failed provider attempt keeps the previous capture and the true failure reason. Later healthy refreshes clear old diagnostics.
- Added 28 regression checks using real asynchronous query commands with controlled resource-release faults. Coverage includes original timeout/access/data errors, whole-attempt validation, independent release attempts, full and standalone scans, fresh state, dictionary/object metadata, saved diagnostics and stable comparisons. The v3.80 baseline reproduces the lost-result bug.
- Validation: 1,987 checks passed on each of Windows PowerShell 5.1 and PowerShell 7. Full standard-user BAT launches at 100/24 columns read all 17 sections and returned properties for 177/177 requested device nodes, reached the menu after one continuation and retained three blank buffer rows (20.09s / 19.17s). Live-test diagnostics saved counts/status rather than hardware identifiers; these timings are environment-specific.

Microsoft documents asynchronous output and provider/pipeline failures separately in [PowerShell.EndInvoke](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.powershell.endinvoke) and explains exception handling and cleanup in [about_Try_Catch_Finally](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally). The regression tests exercise the checker-specific cleanup behavior.

## 3.80

- Added an organized completion summary with SCAN COMPLETE or SCAN FINISHED / READ GAPS, explicit finished/read/not-read counts, requested catalog status, selected Windows-reported ID-field count and the main menu's review total. Enter continues to the menu or rescan comparison using the existing scroll/held-key handling. Optional missing fields do not become claims that an entire section failed.
- Fixed final-summary rendering errors discarding an otherwise finished scan. Heading/value and escaping final-progress exceptions now retain CompletionDisplayWarning under Report info, with a plain-text fallback. Query warnings, section status, identifiers and catalog data remain separate and usable.
- Fixed worker disposal errors replacing completed snapshots or masking an earlier incomplete-scan error. WorkerCleanupWarning retains the detail, the worker reference is cleared before release, and later scans start with fresh state. Completed data stays available; an actually incomplete scan still fails and keeps the previous snapshot active during rescan.
- Moved completion validation before the final progress update. An invalid snapshot cannot receive that final completion update. TXT/JSON retain completion and cleanup diagnostics without altering selected-ID comparisons.
- Validation: **1,959 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 42 new completion checks for renderer/progress/cleanup faults, partial and catalog failures, section-only mode, primary-error preservation, fresh state and saved comparisons in direct/worker modes. The v3.79 baseline reproduces the discarded-finished-snapshot bug. Full native BAT scans at 100/24 columns read all 17 sections and 170/170 property nodes (62.53s / 57.77s); the narrow console displayed the completion heading, ID count and review footer. A third native launch with a controlled summary-display exception still reached the menu with all 17 sections, refreshed catalog and recorded completion warning (54.91s). All three preserved seven groups and at most three blank buffer rows. Diagnostics saved no hardware identifiers.

Microsoft documents [finally-block execution during error handling](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally). Cleanup is isolated here so its exception cannot replace the result of hardware collection. See [reading a scan](USAGE.md#read-a-scan) for completion and warning meanings.

## 3.79

- Fixed code 12 being asserted as a confirmed device-resource conflict. It now reads Insufficient resources and contributes one device-status finding, keeping the scan marked CHECK. Guidance explains that resource shortage or conflict can be involved. Dashboard, overview and review totals use the same categories without discarding the finding.
- Added specific Windows-reported conflict labels and classification for boot configuration code 6 and shared-IRQ code 30. Duplicate nodes remain one ambiguous record group with their distinct status observations retained. Genuine conflicts and ordinary driver/disabled/disconnected findings stay visible.
- Corrected code 24 wording to retain all documented possibilities: not present, malfunctioning or incomplete drivers. Guidance checks presence, operation and drivers, and the code does not override an explicitly reported presence flag. Raw Windows codes and hardware identifiers remain unchanged in exports and imported snapshot comparisons.
- Validation: **1,917 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 43 new resource-status checks covering false-conflict reduction, true conflict controls, code 24 ambiguity, scan/review/dashboard consistency, duplicate observations, saved codes and ID stability in direct/worker modes. Existing status assertions were corrected to match the documented meanings. The v3.78 baseline reproduces the code 12 overclassification. Full native BAT scans at 100/24 columns read all 17 sections and 170/170 property nodes, displayed seven groups and retained three blank buffer rows (45.06s / 49.47s). Diagnostics saved no hardware identifiers.

Microsoft's [code 12 reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/cm-prob-normal-conflict) also describes insufficient firmware allocation, so a specific collision is not established by the code alone. The [Win32_PnPEntity definitions](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) describe codes 6, 24 and 30. This corrects the older code 12 classification recorded in this changelog. See [warnings and conflicts](USAGE.md#understand-warnings-and-conflicts).

## 3.78

- Removed an extended-review name heuristic that flagged every label beginning with Unknown, including devices reporting Windows status code zero. Readable names no longer independently imply a device problem. Actual driver errors, missing names/classes, unknown status and contradictory readings retain their separate findings.
- Fixed blank/NUL-padded or non-text name/class fields blocking usable label sources. Extended collection now selects readable PnP name, friendly name or bus description, and a readable PNPClass/Class alias. Invalid-only alternatives remain unknown instead of being stringified into fake labels. Unusable provided observations remain in labeled Raw fields; identifiers and valid source text stay intact.
- Fixed padded class names falling into the wrong device group. Group matching ignores edge whitespace/NUL padding without rewriting raw class values. Missing labels display as Unnamed device, and the extended review explains that names alone do not determine device condition.
- Validation: **1,874 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 47 new label-reading checks covering healthy-name false warnings, typed alias recovery, raw preservation, true/missing/conflicting status, class groups, rendered review and snapshot comparisons in direct/worker modes. The v3.77 baseline reproduces the name-based false warning. Full native BAT scans at 100/24 columns read all 17 sections and 175/175 property nodes, displayed seven groups and retained only three blank buffer rows (26.90s / 21.81s). Diagnostics saved no hardware identifiers.

Microsoft defines Windows condition through [ConfigManagerErrorCode](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpentity) and [device problem codes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-problemcode). The checker keeps label availability and reported status separate; code zero is a Windows reading, rather than hardware-health certification. See [hidden and remembered devices](USAGE.md#scan-hidden-and-remembered-devices).

## 3.77

- Fixed apparent network-ID additions/removals when fallback readers expose a different adapter set. Different, mixed or unrecorded reader scopes now leave one-sided interfaces not compared. Interfaces sharing a reliable interface GUID still compare usable values, including real changes; matching known readers retain one-sided ID differences.
- Added Reader coverage explanations to saved-file and rescan comparisons, with previous/current readers and the unmatched interface count. Scope uncertainty stays separate from duplicate-key conflicts. A comparison containing only unmatched interfaces now opens its explanation rather than failing or appearing completely checked. Raw identifiers and saved source labels are unchanged.
- Validation: **1,827 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 35 new coverage checks for transitions, unknown/mixed metadata, true shared-ID changes, matching-reader differences, duplicate conflicts, imported snapshots and both comparison views. The v3.76 baseline reproduces the false-difference case. Live same-session native/CIM reads returned 18/4 adapters on each runtime: the previous comparison produced 29 apparent difference entries, while the revised comparison found no differences in 11 shared fields and disclosed 14 unmatched interfaces as not compared. Serialization retained the result, and no hardware identifiers were saved by the audit. Full native BAT scans at 100/24 columns read all 17 sections and 175/175 property nodes, displayed seven groups and retained three blank buffer rows (23.11s / 22.38s).

Microsoft documents the primary reader's [IncludeHidden scope](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter) and the [legacy network-adapter provider](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkadapter). The observed provider differences are specific to this PC; the checker does not infer physical removal from differing or unknown reader coverage. See [reader coverage and comparison](GRAPHICS-NETWORK.md#reader-coverage-and-comparison).

## 3.76

- Fixed background queries dropping completed compatible-read history when a later step failed. Direct and background scans now retain the same recovery history alongside the final failure, including uncaught non-terminating errors. Original provider error identity, category and target remain available; a final terminating failure takes precedence over earlier continued errors.
- Kept incomplete data rejected: a failed query cannot return its partial records, become a successful compatible-read section or generate reliable ID removals. Full/TXT/JSON reports retain the failure and earlier recovery details. The next query starts with fresh error/recovery state.
- Fixed a trailing query comment consuming the background worker's generated closing code. Queries now have explicit line boundaries. Added complete-attempt validation so a worker ending without its result envelope becomes READ-06 instead of an empty successful read; later queries remain usable.
- Validation: **1,792 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 51 new query-state checks covering typed/mixed errors, saved diagnostics, comparison safety, trailing comments, exact scalar values, feedback failure and incomplete-worker recovery. The v3.75 baseline reproduces lost history and trailing-comment failure. Full native BAT scans at 100/24 columns read all 17 sections and 171/171 property nodes (19.91s / 23.33s). A third native scan with a controlled post-recovery CPU timeout reached the menu with 16 sections read, READ-02 and its recovery history retained, and the extended catalog refreshed (22.31s). All three displayed seven groups and retained only three blank buffer rows; diagnostics saved no hardware identifiers.

Microsoft's [PowerShell error-handling reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_error_handling) explains that explicit ErrorAction settings can override the query preference. Error-stream validation remains necessary before accepting buffered records. See [reading a scan](USAGE.md#read-a-scan) for failure and recovery meanings.

## 3.75

- Fixed malformed network identifiers blocking an otherwise usable fallback. Each native/modern/legacy attempt validates its selected scalar ID fields before acceptance. Arrays, objects and booleans in those fields reject the entire attempt; earlier rows cannot leak into recovered results. Missing IDs remain reviewable, while optional status/rate metadata and actual zero/false values stay intact.
- Successful modern and legacy network fallbacks now retain the failed-reader messages in query Recoveries. Scan rows say compatible read, the completion count includes the recovered section, and full/TXT/JSON reports retain the method and diagnostics. Legacy recovery explains both earlier attempts. A later query clears earlier recovery state.
- Validation: **1,741 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 44 new fallback checks covering malformed IDs in each reader, partial-attempt isolation, exact-value preservation, final typed failures, saved diagnostics and comparison stability. The v3.74 baseline reproduces the blocked-fallback bug. Read-only live forced modern/legacy reads returned 4/15 records with their expected recovery notes and no serialization-induced ID changes on this PC. Full native BAT scans at 100/24 columns read all 17 sections and 171/171 property nodes, preserved all seven groups and retained only three blank buffer rows (28.85s / 24.44s).

Microsoft documents [Get-NetAdapter's hidden-adapter switch](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter). Alternative providers can expose different record sets; recovery is not a complete-device or authenticity guarantee. See [reader coverage and comparison](GRAPHICS-NETWORK.md#reader-coverage-and-comparison) for the limits.

## 3.74

- Improved reading during scans: short successful results remain compact, while CHECK, PnP coverage and unread-result explanations use indented continuation lines. Detail text wraps at word boundaries without ellipses, uses the current width after a resize, and keeps Windows record totals distinct from selected identifier-field counts. NOT READ says no usable data rather than implying that no devices exist.
- Fixed fractional elapsed time being coerced to whole seconds in wide/medium progress displays. Scan-result and progress formatting now retain the displayed decimal precision.
- Removed the assumed MHz label from raw RAM `Speed`. ConfiguredClockSpeed retains its documented MHz unit, with zero shown as unknown and missing/invalid values distinguished. Unknown configured clocks use muted text. Hardware views and TXT share field interpretation, while JSON retains the exact original fields and leading-zero strings.
- Fixed TXT export omitting section context from field labels, including raw network Speed values that need bits/s. Completion-rendering failures now remain in normal/catalog progress diagnostics instead of being silently discarded; captured hardware data and comparison values remain usable.
- Validation: **1,697 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 53 new reading checks covering 24/60/80/100-column results, raw-value round trips, fractional timing and injected completion failures. The v3.73 baseline reproduces the RAM-label issue. Full native BAT scans at 100 columns on 5.1 and 24 columns on 7 read all 17 sections and 171/171 property nodes, displayed all seven groups and kept only three blank buffer rows (24.56s / 23.15s on this PC).

Microsoft's [Win32_PhysicalMemory reference](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-physicalmemory) defines ConfiguredClockSpeed in MHz, with zero meaning unknown, while the Speed property has a different documented unit. The checker leaves that raw value unconverted. See [reading a scan](USAGE.md#read-a-scan) for display and status meanings.

## 3.73

- Organized active scanning into seven numbered groups: system/firmware, CPU/memory, storage, graphics/network, Windows, present device IDs and the all-known catalog. Firmware queries now stay together before CPU/memory. Section-only diagnostics show six groups; normal query totals remain 17 and full progress remains 18 stages. Rescans reset group state and cleanup clears it.
- Fixed an empty network-reader record being counted as a device because derived rate/source labels made it appear populated. Primary, modern CIM and legacy attempts now validate record shape and actual adapter fields before labels are added. Invalid attempts can recover through the next compatible reader without leaking partial rows. All-empty attempts become READ-06, while real zero/false values remain usable. Unread sections stay outside reliable ID comparisons.
- Isolated group-heading rendering failures from hardware collection, retaining their messages as display warnings. Fixed extended-catalog heading/timer warnings being dropped: Extended scan info now preserves `ProgressWarning`, completion explains it separately, and TXT/JSON retain the detail without changing the catalog's read status or normal-section warning count.
- Validation: **1,644 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 45 new scan-flow checks in direct/worker modes. The v3.72 baseline reproduces the empty-adapter acceptance bug. Full native BAT-to-menu scans read all 17 sections and 171/171 property nodes on both runtimes, rendered all seven group headings, and retained only three blank buffer rows after written content (23.84s / 21.97s on this PC). Existing startup fixes are preserved locally.

Microsoft documents [Get-NetAdapter](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter) and [CIM instance results](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance). Reader validation checks the data actually returned; it does not certify hardware health or authenticity. See [reading a scan](USAGE.md#read-a-scan) for the group layout and status meanings.

## 3.72

- Fixed the original startup window closing before the readable child confirmed readiness. The launcher now waits for a child status signal, distinguishes normal completion from an unexplained early exit, and reports **START-03** with current-window fallback when handoff fails. This covers failures after the previous 700ms check, missing/invalid content and pre-ready fatal errors.
- A slow unconfirmed child now produces **START-04** after the initial 12-second readiness wait. The original window remains open until that child finishes; this path does not start a duplicate scan. Child startup detail is bounded/sanitized, temporary signal files are cleaned up normally, and environment state/process handles are restored or released.
- Fixed inherited `ERRORLEVEL` variables overriding real process exit codes. CMD command extensions are enabled locally so a caller disabling them cannot break the launcher's label calls and runtime gates. Genuine restricted-runtime failures still stop startup.
- Kept the 3-second preparation pause, nonzero exit reporting, existing scan recovery and current-window opt-out. No administrator elevation or automatic inventory save was added.
- Validation: **1,599 checks per runtime** on Windows PowerShell 5.1 and PowerShell 7.6.5, including 27 new startup-handoff checks with real isolated child processes. The shipped baseline reproduces the inherited-ERRORLEVEL failure; delayed-failure fixtures cover the old handoff race. Full native BAT-to-menu tests passed as a standard user with both runtimes: all 17 sections read, 171/171 requested device-property nodes returned, scan continuation preserved and no hardware identifiers written by the diagnostics (18.79s / 17.40s on this PC).

Microsoft documents [CMD command extensions](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd), [ERRORLEVEL environment-variable behavior](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/if), and [child environment inheritance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process). See [startup and recovery](USAGE.md#startup-and-recovery) for the fallback codes and troubleshooting commands.

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
