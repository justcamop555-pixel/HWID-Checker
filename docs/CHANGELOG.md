# Recent changes

[Back to the main README](../README.md)

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
