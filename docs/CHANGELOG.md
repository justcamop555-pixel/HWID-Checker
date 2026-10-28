# Recent changes

[Back to the main README](../README.md)

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
