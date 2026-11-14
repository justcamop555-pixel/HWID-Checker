# Desktop verification

## Desktop 1.5.0 and BAT 3.94 (2026-11-14)

This update changes Desktop startup and window sizing; the BAT's scanning behavior is unchanged.

- The native launcher passed 13 lifecycle checks: loading/error windows, exact Unicode and quoted arguments, parent identity, child exit status, cancellation and missing payloads. The packaged app separately verified its parent PID/start time/path binding used by updates.
- With an empty bundle-cache directory on this Windows host, the final native window appeared in 59 ms; WPF loading painted in 744 ms. The check completed in 2,365 ms including an intentional 1,000 ms preparation delay. A prior paired test measured 75 ms versus 1,475 ms for the old single-file package. The new package extracted zero runtime files; the old one extracted five files (7.8 MB). These are synthetic local measurements, not fresh-Windows or laptop benchmarks. OS caches were not flushed, and security checks were not bypassed. Parent-only memory readings are not comparable to total application memory.
- Six stressed pages passed at 683 × 360 DIPs and at 1024 × 640 in Daylight. Table assertions check reachable visible headers and rows, rather than layout height alone. IDs and Compare images were inspected. DPI conversion checks cover 100%, 125%, 150%, 200% and 250%; physical mixed-DPI monitors and the user's laptop remain untested.
- Library 86, scrolling 31, interactions 80, readability 14, welcome 50 and real-process restart 1 passed. Restart ran outside the sandbox's same-user named-pipe restriction.
- The updater validated all 408 real payload files and rejected a package with a missing runtime DLL even when its checksum list was consistent. Existing updater tests passed 104 checks on each PowerShell runtime; UpdaterClientSmoke passed 55 checks.
- The NuGet audit reported no vulnerable packages. That does not establish that the application or every bundled native component is vulnerability-free.
- The isolated TEST installer passed 23 install/repair/uninstall checks, including replacement of a deleted runtime DLL and damaged runtime configuration. Reports and custom files remained byte-identical, and the temporary uninstall registration was removed. The production all-users setup compiled with Inno Setup 7.1.1; actual administrator/UAC, HKLM and multiple-user installation were not exercised. The initial sandbox test failed at its restricted HKCU registry write and rolled back; the same test passed outside that restriction.

The 1.4.x updater does not understand the new folder layout. That upgrade requires the complete installer or a newly extracted ZIP. Historical single-file measurements below describe earlier builds.

## Local candidate — Desktop 1.4.8 and BAT 3.93 (2026-11-13)

These pre-release setup and privacy checks cover changes included in Desktop 1.5.0 / BAT 3.94.

- 866 checks per runtime passed on Windows PowerShell 5.1 and PowerShell 7: core, managed-install paths, updater, console updates, snapshot sync/catalog/storage, device identification and comparison coverage.
- Desktop model/search/export: 140 checks. Updater client: 55 checks, including per-user installed report paths and blocking portable updates for installed copies. Offline recovery: 24 checks.
- Desktop verification: Library 80, Interactions 80, Welcome 50, Readability 14, Scrolling 31, shared Workflow 24 and ScanUI 22. Real process restart passed outside the sandbox's named-pipe restriction. Six compact, stressed page renders passed and IDs/Review images were inspected.
- A separately identified, per-user TEST setup passed 11 install/repair/uninstall checks. It restored a deleted BAT and a corrupted launcher, kept the exact offline setup, and preserved synthetic reports and custom files byte-for-byte through uninstall.
- Production setup compiled with Inno Setup 7.1.1; the production script sets `PrivilegesRequired=admin`. Actual UAC interaction, HKLM registration and installation across multiple Windows accounts were not exercised. The TEST setup does not replace those checks and must not be shipped.
- The dependency audit completed against NuGet without reporting vulnerable packages. The earlier sandbox build could not access the vulnerability feed; that warning was not treated as a completed audit.

## Local candidate — Desktop 1.4.7 and BAT 3.92

The repair, identification and comparison checks below cover changes included in Desktop 1.5.0 / BAT 3.94.

- **973 checks per runtime** passed on Windows PowerShell 5.1 and PowerShell 7: 603 core, 104 updater, 49 console update, 49 desktop bridge, 18 targeted identification, 4 comparison coverage, 33 PnP refresh, 66 extended refresh and 47 hidden-device checks.
- **25 offline recovery checks** cover consent before writes, blocked/missing runtimes, cancellation, exact bundled bytes, missing/corrupt files, concurrent repair and healthy custom-scanner preservation.
- Packaged Desktop passed **71 library/dialog/comparison checks**, **80 interactions**, **22 scan UI**, **24 shared save/compare checks** and a real process restart. Compact repair prompts retained scrollable details and reachable accept/decline actions in both themes.
- Two actual read-only scans finished at scan number 2, with all 18 sections read, 178 known device records and 56 responsiveness ticks. Diagnostics stored counts/status only.
- The sandboxed build reported NU1900. A subsequent network-enabled NuGet package vulnerability check completed and reported no vulnerable packages from the configured sources.

Tested executable SHA-256: `E41BE9F6F5F05CE63AAD89922683F1573E8786EF06E9486CB421B2A98D9E4446`. The packaged documentation was updated without changing the tested EXE or BAT.

Targeted supplementary reads preserve primary device records when an optional property lookup fails. They do not infer a fault from a readable name such as "Unknown", turn a model ID into a serial number, or clear a reported driver problem. Microsoft documents [hardware-ID meaning](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/hardware-ids), [hardware-ID properties](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-hardwareids), and [device problem codes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-manager-error-messages).

## Desktop 1.4.6 and BAT 3.91

The checks below cover the changes in [Desktop 1.4.6 / BAT 3.91](https://github.com/justcamop555-pixel/HWID-Checker/releases/tag/desktop-v1.4.6). Executable hashes recorded in each follow-up identify its tested development build. The release asset has its own attached SHA-256 manifest.

### Smoothness and conflict follow-up — November 12

- ID and Review filters retain column sorting and matching selections. Hidden rows clear the corresponding copy/detail target. Unchanged immutable grid sources are reused.
- Hardware record rows and scalar search values are prepared with the snapshot. The optional value cache is capped at 1,048,576 characters and 16,384 scalar values; uncached records keep exact recursive JSON search. Nested values, leading zeros, scalar records, null slots and original record indexes remain covered. Saved-snapshot and comparison searches avoid concatenating every row for ordinary queries while retaining cross-field phrase matches.
- Automatic library polling pauses while minimized, welcoming or connecting. A timer poll cannot keep queuing another read behind an active refresh, and it does not erase an explicit pending manual refresh.
- BAT rendering retains one wrapped layout per display entry. Exact text, console width and indentation changes invalidate it. The existing native repaint/resize repair cadence is retained.

The model/search/export suite passed **140 checks**. In a synthetic 2,000-record, 50-query steady-state search benchmark, the cached hardware search took **11 ms / 176,040 allocated bytes**, versus **292 ms / 130,389,664 bytes** for the former recursive approach. These measurements exclude preparation and are not a claim about overall UI frame rate or every PC. Reproduce with `dotnet run --project .\desktop\tests\DesktopModelsSmoke -- --benchmark-hardware` from the repository root.

On each of Windows PowerShell 5.1 and PowerShell 7, **917 checks** passed: 603 core, 46 bridge, 13 display cache, 61 completion, 53 reading, 45 grouped flow, 60 native resize and 36 scrolling. Cache tests cover exact Unicode/case changes, resize round trips, indentation, controls, blank rows, legacy callers and unchanged long values. The optional synthetic wrapping benchmark has no timing threshold.

The final package passed **55 library/filter/refresh checks**, 80 interaction, 22 scan UI, 31 scrolling, 14 readability, 26 theme, 50 welcome and 24 shared save/compare checks, plus compact dark/light stress renders of all six pages. A one-core startup probe painted loading content in 718 ms in one local run. Packaged restart passed, and two real read-only scans finished at scan number 2 with 18 sections read, 178 known device records and 44 responsive timer ticks. Live diagnostics contain counts/status; saved screenshot/export fixtures remain synthetic.

The build completed with warning **NU1900** because NuGet's vulnerability service could not be reached, including on a separate restore retry. The online package vulnerability audit was **not completed**. Dependency versions were not changed by this update. Filesystem cancellation remains cooperative between Windows calls.

Tested executable SHA-256: `9CD0A1968B46A203D41B1001453A573ED6F526B03ABD3BC19576AEB21BE71574`.

### Startup responsiveness follow-up — November 12

Normal launches paint a small loading window before preferences are read or the dashboard is constructed. Preference reading is bounded to 256 KB on the open file handle and accepts existing UTF-8/UTF-16 BOM settings. Scanner path probes and BAT validation run on a worker, and a close during connection preserves the remembered BAT path. Verification and restart handoffs keep their existing direct-window flow.

The startup settings suite passed 15 checks covering missing, malformed, oversized, locked and cancelled reads, exact preferences and unchanged source bytes. The packaged app passed normal startup, a synthetic three-second preparation delay and a normal Close request during a five-second preparation delay. Closing stopped before the dashboard was created.

Three final package launches, each constrained to one CPU core with BelowNormal priority and a fresh bundle-extraction folder, painted the loading content in **1,007 / 906 / 955 ms** from process launch. These use the app's ContentRendered timestamp and the shared monotonic clock; a native window handle can appear earlier. The synthetic checks then exited in 1,665 / 1,618 / 1,682 ms. No launch-time guarantee is inferred for other hardware: OS file caches were not flushed, Windows security checks were not bypassed, and an actual low-end PC was not available.

The package still extracts five native files (about 7.8 MB) when its .NET bundle cache is empty. Microsoft documents this [single-file extraction behavior](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview). The existing compatible package format is retained. A controlled ReadyToRun variant measured slower here and was not selected; compression and compilation settings are now explicit.

Reproduce from the repository root using PowerShell 7 and an extracted desktop package:

```powershell
dotnet run --project .\desktop\tests\StartupSmoke
.\desktop\tests\test-startup.ps1 -Exe "C:\Path\To\HWID Checker.exe" -StartupFlow -OneCore
.\desktop\tests\test-startup.ps1 -Exe "C:\Path\To\HWID Checker.exe" -StartupFlow -DelayMs 3000 -OneCore
.\desktop\tests\test-startup.ps1 -Exe "C:\Path\To\HWID Checker.exe" -StartupFlow -DelayMs 5000 -CancelStartup -OneCore
```

Each measurement owns an isolated extraction folder and uses synthetic verification data without loading user preferences or scanning hardware. The timing JSON distinguishes the first window handle from rendered loading content. These tests leave the normal user's .NET extraction cache alone.

The final package also passed 50 welcome, 45 library/comparison, 80 interaction, 22 scan UI, 31 scrolling, 14 readability, 26 theme and 24 shared save/compare checks, plus all six pages in compact dark/light stress layouts. The model suite passed 82 checks.

Tested executable SHA-256: `78011BA19BD8C9832EFEC85F427ABED721A0491F7A6B725AB8B145B29F131CE5`.

### Privacy, loading and layout follow-up — November 12

- Welcome: 50 synthetic checks passed across both themes at 620×590, 500×420 and the 360×360 minimum. The notice retains a usable scroll viewport and separate visible actions. The welcome is offered before saved-file discovery; the app explains full-value exports, GitHub update requests and cloud-synced folders.
- Snapshots/comparison: 45 packaged library checks passed, including cancellation retaining the previous complete comparison, exact old/new row preparation, a separate refresh state and reduced-motion comparison progress. The model suite passed 82 checks, including cancellation before and during folder enumeration and unchanged source files after preview.
- Packaged UI: 80 interaction, 22 scan UI, 31 scrolling, 14 readability, 26 theme and 24 shared save/compare checks passed, plus compact dark/light stress renders of all six pages. These checks exercise reduced available layout space; they do not establish compatibility with every monitor DPI or graphics driver.
- BAT: on each of PowerShell 5.1 and 7, 603 core, 61 completion, 60 native-resize, 45 grouped-flow, 36 scroll and 46 bridge checks passed (851 per runtime). Completion explicitly distinguishes present and all-known device records, failed reads and omitted catalog collection.
- The packaged restart restored its synthetic session. Two real read-only scans finished at scan number 2 with all 18 sections read, 178 known device records and 41 responsive timer ticks. Live diagnostics contain counts/status, not identifier values; all saved screenshot/export fixtures are synthetic.

Catalog cancellation is cooperative between filesystem reads. An unavailable filesystem can still block inside a Windows call. Comparison preparation runs on a worker; cancellation publishes no partial replacement. Saving, exports and clipboard copies remain full-value operations without automatic redaction.

Tested executable SHA-256: `9AA58A1AC6C40110AB941E05D7EDF803BAF7AC967B8CDBBA4F5E1F5B25CFD9D5`.

| Check | Result |
| --- | --- |
| Desktop models, search and extra report exports | 80 checks passed, including exact indexed-search equivalence, immutable capture rows, new-capture isolation, older-capture coverage, catalog states and staged export failures |
| Desktop interactions | 80 checks passed, including labeled semantic states, normal-text status contrast on dark/light panels, restart input locking, truthful hardware counts, selection retention, copy guards and empty-state guidance |
| Desktop restart | 20 real-process handoff checks passed for launch failure, early exit, cancellation, timeout, commit/abort, exact values and bounded protocol messages. A separate packaged-EXE restart restored a synthetic capture, filters, theme, selected comparison and page, then waited for the original process to exit |
| Native theme matching | 26 checks passed while switching dark/light/dark across the main, Updates, Folder settings and Welcome windows. Windows accepted caption colors; native resize/title-bar controls remained in place and opening the dialogs did not change library settings |
| BAT/Desktop theme parity | 38 native checks passed on PowerShell 5.1 and 7: both palettes match Desktop colors, preferences/overrides are read safely, malformed/null/oversized settings fall back, caption colors are accepted, and current-window/redirected hosts remain unchanged |
| Desktop scrolling | 31 event-based checks passed at 640 × 480 and 840 × 560: wheel routing on all six tabs, Overview keyboard navigation, independent detail scrolling and native scrollbar dragging/bindings. Mouse-wheel movement, Home and scrollbar dragging were also observed in a visible synthetic test window |
| Readability and save/compare | 14 readability and 24 shared-library workflow checks passed |
| Layout | All six pages passed 640 × 480 and 840 × 560 stress renders, plus 1280 × 820 renders |
| BAT resize and display fallback | 60 native checks passed on each of Windows PowerShell 5.1 and PowerShell 7, including idle menu resizing with typed input/error retention, isolated progress-row painting, cursor/history preservation, host reflow, output-mode restoration and full redraw/fallback recovery |
| Existing BAT and bridge behavior | Menu/core, completion, display fallback, scrolling, native console, 104 updater, 49 console-update and 46 desktop-bridge checks passed on each runtime |
| Live desktop scan | Latest audited package: 18 sections read, 178 known device records and 49 responsive UI ticks; evidence records counts/status rather than identifier values |
| Build | The audited rebuild produced the exact executable and engine hashes used by the UI checks |

The CSV/HTML exporter stages both reports before publishing; handled failures clean up its temporary files. It does not claim a two-file transaction across a power loss or process termination. TXT/JSON snapshots retain the BAT engine's existing format and validation.

The November 11 visual/behavior audit also passed 42 engine-transport, 80 model/search/export and 51 updater-client checks. BAT coverage included 603 core checks on each runtime, plus scan recovery, readable-data publication, metadata, warning review, comparison identity, snapshot storage/discovery/sync, scan completion, scrolling and both animation suites on PowerShell 7. Native rendering was inspected at compact and wide sizes; these local checks do not establish compatibility with every display, driver or Windows configuration.

The menu uses a short idle wait with [`Console.KeyAvailable`](https://learn.microsoft.com/en-us/dotnet/api/system.console.keyavailable), allowing prompt layout to recover before calling the blocking key reader. Held Enter still follows the existing no-output path.

The startup-recovery fixture now supplies the exit-update stub used by the real menu loop; without it, the isolated fixture retried a missing command until its timeout. All 35 recovery, 14 startup-delay and 27 handoff checks passed after this test-only correction.

The subsequent restart/color update passed 603 core, 14 console-restart, 49 console-update, 53 scan-reading, 42 completion, 60 native-resize and 46 desktop-bridge checks on each PowerShell runtime. It also passed 31 scrolling, 14 readability and 24 shared save/compare checks, six compact dark stress renders, six reduced-space Daylight stress renders and six wide renders.

Restart data uses an in-memory named pipe with [`PipeOptions.CurrentUserOnly`](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.pipeoptions), bounded frames and an explicit ready/commit exchange. The receiver checks the original process start time before waiting for it to exit. No temporary snapshot is created. Restricted test tokens denied the pipe connection; the same-user Windows runs passed without weakening pipe permissions. Prepared-update installation remains a separate save-before-install workflow.

Theme matching uses documented [DWM window attributes](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute). Caption/frame color attributes are documented for Windows 11 build 22000 and later; unsupported calls leave the supported system frame in place. High-contrast mode resets Desktop frame overrides to the system defaults. The native color setter succeeded on this PC; color readback was unavailable, so the theme check records acceptance rather than claiming a pixel comparison. Windows-managed dialogs retain their system appearance.

The Desktop-only welcome/privacy notice passed 28 synthetic checks covering first launch, optional repeat launches, restart suppression, primary/Not now actions, keyboard focus, compact scrolling, dark/light contrast, and preference persistence. The notice explains read-only scanning, sensitive report contents and that saving a snapshot does not redact its identifiers. An older asynchronous settings write cannot replace a newer choice or the synchronous close-path save. Verification uses isolated preferences; normal app settings and saved snapshots are not test fixtures.

The packaged candidate also passed 80 interaction, 31 scrolling, 14 readability and 24 shared-library workflow checks, plus all six pages in compact dark/light stress layouts. A normal-user packaged restart restored its synthetic session with the welcome preferences retained; the live read-only scan read all 18 inventory sections and 178 known device records while the UI timer continued (49 ticks). BAT changes in this pass shorten the three startup-stage labels; they add no welcome dialog. All 603 core, 35 startup-recovery, 14 startup-delay and 27 startup-handoff checks passed on Windows PowerShell 5.1 and PowerShell 7.
### Snapshot library, comparison and offline recovery

The November 11 local candidate passed 29 synthetic library/compare UI checks, 19 offline recovery checks on each of Windows PowerShell 5.1 and PowerShell 7, 80 existing interaction checks, 24 shared-library workflow checks, 31 scrolling checks, 14 readability checks, 26 theme checks and 28 welcome checks. The library checks include exact comparison searches, meaningful category filters, no-match versus no-change guidance, selection state, source labels, complete export retention and usable tables at 640 × 480 in both themes. All six pages passed compact dark and reduced-space Daylight stress renders.

The packaged restart preserved the new comparison/library filters and selected change. The packaged live scan read all 18 sections and 178 known device records, with 23 responsive UI ticks. Live diagnostics record counts/status; report exports and screenshots use synthetic captures.

Offline recovery is tested with isolated files: embedded/package byte equality, deleted/corrupt managed copies, concurrent restoration, missing or syntactically invalid companions, unchanged custom files, renamed paths, runtime fallback and cancellation. Preparation parses source without executing it. Launching a console can retry an early nonzero loader exit once; these checks do not establish that every driver, provider, runtime policy or later console failure can be repaired. No scanner download or system-policy change is part of recovery.

Audited executable SHA-256: `9260F505384AC4194D00E081663F6004BFB41688E3F8F763CB5587E734DAD4E6`.
### General bug audit

A subsequent November 11 audit reproduced an incorrect fallback: a custom source valid under PowerShell 7 was replaced after the first Windows PowerShell 5.1 parser failure. Recovery now checks every installed runtime first. Renamed sources also ignore sibling loaders they do not use; standard hwid.bat still validates its required launcher.

The packaged candidate passed 38 library/connection regressions, including bounded reads of oversized/truncated BAT files, clearing stale connection labels, sorting across filters and preserving old report discovery with configured shared settings. It also passed 80 interaction, 24 shared-library workflow, 31 scrolling, 14 readability, 26 theme and 28 welcome checks, plus all six pages at 640 × 480 in both themes. Recovery passed 21 standard checks on each PowerShell runtime and a mixed-runtime parser regression. A normal-user restart restored the synthetic session; the packaged live scan read 18 sections and 178 known device records with 19 responsive UI ticks.

The BAT audit passed 1,438 synthetic checks across 23 suites on PowerShell 7.6.9, covering the core menu, snapshot sync/catalog, identity and reader-scope comparison, PnP/network fallbacks, scan completion/recovery/metadata, query failures, battery, graphics/network labels, device IDs/status, hidden records, aliases, completeness, parent relationships, scan readability, warnings and startup recovery. The BAT engine bytes and hardware query logic are unchanged in this pass. These targeted checks do not establish that every device, driver or Windows configuration is free of bugs.

Audited executable SHA-256: `E4E72803D914FADC03ED9F909F1AA996413F7D9EC2F3559098A674C92805467E`.
### Scan progress follow-up

The scan-progress update passed 22 synthetic Desktop checks for counters, delayed/obsolete feedback, full error guidance, working finalization, preserving the prior capture, cancellation, first-attempt failure and compact dark/light text space. Successful Desktop scans now send their explicit sequence number through the engine request; cancelled or failed attempts continue from the last completed capture.

The process transport passed 47 checks, including first/rescan number forwarding, cancellation/disposal, bounded protocol reading, error handling, transient file-lock cleanup and rejecting cleanup paths outside the owned operation folder. Cleanup retries are bounded and never recursively remove unexpected contents; persistent access failures can still prevent removal.

On each of Windows PowerShell 5.1 and PowerShell 7, the update passed 603 core, 56 completion, 53 scan-reading, 45 grouped-flow, 36 scrolling, 12 display-fallback, 34 recovery, 51 query-failure-state, 24 readable-data, 41 metadata, 35 reader-coverage comparison, 46 Desktop-bridge and 60 native-resize checks. These total 1,096 checks per runtime.

The packaged UI also passed 80 interactions, 38 library/connection, 24 shared save/compare, 31 scrolling, 14 readability, 26 theme and 28 welcome checks, plus all six pages in compact dark/light stress layouts. A normal-user packaged restart restored the synthetic session. Two real read-only scans ended at scan number 2 with all 18 sections read, 178 known device records and 41 responsive timer ticks. Live diagnostics retain counts/status; screenshots and export fixtures are synthetic.

The BAT progress row includes read/not-read counts when timing metadata is available. Narrow layouts use shorter text; callers without timing metadata retain the original formatter. CHECK is counted as data read and the catalog contributes one check. Collection and identifier values retain the existing providers and normalization rules.

Audited executable SHA-256: `6270F78E12ECD2302D74D1308D3FF18380B121CB5FB4978671B8E5A2978B0CDE`.
### Performance check

Local synthetic measurements on November 11, 2026:

| Workload | Previous path | Optimized path |
| --- | --- | --- |
| 32 ID searches over 20,000 synthetic fields | 27.95 ms; 81.09 MB allocated | 14.57 ms; 3.59 MB allocated |
| 32 Review searches over 2,000 synthetic findings | 5.64 ms; 12.55 MB allocated | 1.14 ms; about 1 KB allocated |
| 40 progress updates with 81 retained console entries, Windows PowerShell 5.1 | 1,266 ms | 24.7 ms |
| Same console workload, PowerShell 7 | 1,455 ms | 26.8 ms |

Search figures compare both paths in one process; console figures are sequential runs using the same synthetic workload. Results are local medians, not end-to-end hardware-scan guarantees. A normal fast-path progress update lays out one entry instead of all 81. Full redraws still run for resizing, wrapping changes and periodic repair. Search text uses memory for the active capture and is replaced with each new capture.

The performance build also passed 31 scrolling, 52 interaction, 14 readability and 24 shared save/compare checks, plus all six compact stress renders. Its live scan read 18 sections and 178 known device records while recording 22 responsive UI ticks. Windows provider queries, coverage and timeout limits were retained.

## Desktop 1.4.5 and BAT 3.90

The build uses the self-contained .NET 10 Windows x64 runtime.

| Check | Result |
| --- | --- |
| Desktop type and hardware view | 14 readability checks passed for regular 14-DIP body text, full section names/counts, hardware-first selection, readable metadata and original-value detail/copy |
| Desktop interactions and workflow | 47 interactions and 22/24 legacy/shared workflows passed; all six pages passed default, 640 × 480 and 840 × 560 stress renders |
| Desktop display models | 27 checks passed, including descriptive RAM slot titles, access-level fallbacks, accurate counts, readable timestamps and unchanged raw identifiers/JSON |
| Scanner process transport | 42 checks passed, including bounded streamed lines, Unicode/CRLF/EOF handling, prompt reported-error handling, cancellation and exact temporary-file cleanup |
| BAT and bridge | 878 numbered checks passed per runtime on Windows PowerShell 5.1 and PowerShell 7, including metadata/TXT entry points, absolute paths and existing scanner regressions |
| Classic console | Native checks passed on both runtimes: minimum 18px regular Consolas, preservation of a larger 24px font, scrolling, rescans, animations and input/cursor restoration |
| Version/update controls | 104 shared updater and 49 console-update checks passed per runtime after the version bump |
| Final packaged app | 14 readability, 47 interaction and 24 shared-workflow checks passed; a live scan read 18/18 sections, returned 178 known device records and recorded 26 responsive UI ticks |

The reduced-space layouts use the current OS DPI; they do not switch Windows display scaling. Synthetic report tests use synthetic identifiers. Native console font changes are confined to the owned checker window, and no global console settings are changed.

The published archive SHA-256 is provided in [SHA256SUMS.txt](https://github.com/justcamop555-pixel/HWID-Checker/releases/download/desktop-v1.4.5/SHA256SUMS.txt). The archive includes a second `SHA256SUMS.txt` covering the executable and companion files.

## Desktop 1.4.4 and BAT 3.89

Verified on Windows build 26300 with .NET SDK 10.0.403 and self-contained .NET 10.0.14 runtime packs.

| Check | Result |
| --- | --- |
| Desktop guidance and interactions | 47 synthetic checks passed, including compact captures before scanning, while scanning, empty/filtered Review, unchanged/one-sided/unusable comparisons and same-file selection |
| Layout and workflow | All six default and compact pages passed; 22 legacy and 24 shared save/compare workflow checks passed; the final package passed six compact pages, 47 interactions and the shared workflow |
| BAT and bridge scanning | 808 checks passed per PowerShell runtime, covering readable-data validation, failed rescan preservation, completion counts, watch comparison limits, progress details and existing hardware regressions |
| Older linked scanner | The current bridge scanned the unchanged BAT 3.88 on both runtimes, including the compatibility validation path |
| Shared updater / BAT controls | 104 updater and 49 console checks passed per runtime |
| Desktop updater | 51 checks passed, including equivalent three/four-part versions, real newer-file restart states, stale cache rejection and drive-root paths |
| Process transport / desktop model | 37 transport checks and seven model/catalog checks passed; read-failure guidance survives transport and unfinished states cannot inflate read coverage |
| Packaged live scan | All 18 sections read, 176 known device records and 22 responsive UI timer ticks; diagnostics saved counts/status rather than identifier values |
| Native BAT startup | Full scan reached its continuation and main menu with a regular font, unchanged standard-user privileges, bounded input handling and no dashboard scrolling after repeated invalid/held-Enter input |

UI renders used 96 DPI and 640 × 480 compact windows. Reports in synthetic workflows use synthetic identifiers and isolated folder settings. Update-installation tests used synthetic packages. The restricted sandbox denied a test preference-file rename; the same isolated updater-client suite passed outside that filesystem restriction.

The published archive SHA-256 is provided in [SHA256SUMS.txt](https://github.com/justcamop555-pixel/HWID-Checker/releases/download/desktop-v1.4.4/SHA256SUMS.txt). The archive includes a second `SHA256SUMS.txt` covering the executable and companion files.

## Desktop 1.4.3 and BAT 3.88

Verified on Windows build 26300 with .NET SDK 10.0.403 and the self-contained .NET 10.0.14 runtime packs.

| Check | Result |
| --- | --- |
| Packaged desktop layout | All six pages passed at default size and 640 × 480; compact tests used long synthetic names, paths, warnings and IDs |
| Desktop interactions | 21 checks passed for scalar/nested search, rapid navigation and focus, clicked-row copy guards, manual scan scrolling, selection preservation and animation cleanup |
| Closing and reduced motion | Actual fade completion, interrupted fade and disabled-animation closing passed without duplicate close completion |
| Snapshot workflow | 22 legacy and 24 shared-library workflow checks passed; the final package passed the 24-check shared workflow |
| BAT scanning/startup/motion | 764 checks passed on each of Windows PowerShell 5.1 and PowerShell 7, including native restart acknowledgement and console animation restoration |
| Additional BAT regressions | 256 checks passed per runtime for updater transactions, identifier views/labels, snapshot storage, shared folders and warning review |
| BAT update controls | 49 checks passed per runtime, including cached source-version binding, malformed cache rejection and interrupted recovery |
| Desktop bridge and transport | 34 bridge checks passed per runtime; 34 process-host checks passed |
| Desktop updater | 23 checks passed with dynamic version fixtures, including version 1.4.3 |
| Shared local library | 14 cross-app checks passed with synthetic saved reports and isolated folder settings |
| Full read-only desktop scan | All 18 sections read; 176 known device records; 22 responsive UI timer ticks; completed with 19 activity rows |

Renders used 96 DPI and reduced window sizes; these checks do not change Windows display scaling. Saved test reports contain synthetic identifiers. The live-scan diagnostic records counts/status, not identifier values. Actual public update installation was not performed.

The published archive SHA-256 is provided in [SHA256SUMS.txt](https://github.com/justcamop555-pixel/HWID-Checker/releases/download/desktop-v1.4.3/SHA256SUMS.txt). The archive also includes a per-file `SHA256SUMS.txt` with the executable and companion-file hashes.

## Desktop 1.3.0 and BAT 3.85

Verified the packaged Windows x64 application on Windows build 26300.

| Check | Result |
| --- | --- |
| Desktop layout | All six pages passed at 1260 × 850 and 640 × 480 DIPs, with long synthetic content at the compact size |
| Snapshot workflows | 24 shared-library and 22 legacy workflow checks passed, including Waiting rows and cancellation restoration |
| Live scan | All 17 sections read, 173 known device records and 19 responsive timer ticks |
| Updater | 99 synthetic checks passed on Windows PowerShell 5.1 and PowerShell 7, including complete preparation/application, rollback, split-component upgrades and journal recovery |
| Desktop update client | 15 synthetic checks passed, including preferences, literal helper arguments, cancellation and interrupted-update scheduling |
| BAT | 909 focused regression checks passed per runtime for scan behavior, update controls and local snapshot compatibility |
| Process and bridge | 34 process-host checks and 33 bridge checks per PowerShell runtime passed |
| Native console | Real scrolling, repeated scans, history, input modes and navigation passed |

Layout renders used synthetic data at 96 DPI. Update installation and recovery used isolated synthetic packages. The public release check rejected older published versions as update candidates. Live scan diagnostics recorded counts and status.

Release EXE SHA-256

```text
EA3E29D0D7F79789E8A87E00D6987A8D48BB5EBBE1CD8003569292353DC4CE39
```

## Desktop 1.2.0 and BAT 3.84

Verified the packaged Windows x64 EXE on Windows build 26300.

| Check | Result |
| --- | --- |
| Shared library | 14 cross-app checks passed, including each app discovering the other app's saved pair, concurrent folder changes and corrupt settings fallback |
| BAT regressions | 748 checks per PowerShell runtime across the console, snapshot, launcher and desktop bridge suites, including 18 shared folder checks |
| Native console | Passed the real console check for repeated scans, scrolling, content-sized history and navigation |
| Desktop workflow | 24 checks with an isolated shared library and 22 with the legacy folder behavior |
| Desktop layout | All six pages passed at 1260 × 850 and 640 × 480 DIPs |
| Live scan | All 17 sections read and the desktop stayed responsive |

The sync checks used synthetic reports and isolated folder settings. The live check recorded counts and status.

Release EXE SHA-256

```text
4BCB89C17CD8D90F087B07AE16DD5D2F21DC7E091A99407B68957BD49D615214
```

## Desktop 1.1.0

Verified the packaged Windows x64 EXE on Windows build 26300.

| Check | Result |
| --- | --- |
| Layout | All six pages passed at 1260 × 850, 900 × 600 and 640 × 480 DIPs |
| Long content | The 900 × 600 and 640 × 480 runs used synthetic long identifiers, hardware names, file paths and warnings |
| Desktop workflow | 22 checks passed, including hardware refresh, saving, comparing, cancellation and restoring the previous scan |
| Live scan | 17 of 17 sections, 160 known device records, 47 identifier fields and 11 responsive UI timer ticks |

The reduced window sizes exercise the space available to the layout at 96 DPI. The test does not switch display scaling or move the window between monitors. The live scan recorded counts and status.

Release EXE SHA-256:

```text
D00CDE1DFF84148577833A2A29EBC6B308D7D1DAAAA6A2144176CE601137015F
```

## Desktop 1.0.0

Verified locally on Windows x64, build 26300, using .NET SDK 10.0.402 and the self-contained .NET 10.0.13 runtime packs.

| Check | Result |
| --- | --- |
| Bridge integration | 33 checks passed on Windows PowerShell 5.1 and PowerShell 7 |
| Process transport | 34 synthetic checks passed |
| Desktop workflow | 21 checks passed on the packaged EXE, including folder preference reload, save/compare, view reset and cancellation |
| Desktop pages | All six pages rendered successfully from synthetic inventory |
| Compact layout | 1080 × 730 window inspected |
| Live packaged scan | 17/17 sections, 176 known device records, 47 reported ID fields and 13 responsive UI timer ticks |
| Console engine | BAT and PS1 launcher remain unchanged |
| Package | Self-contained win-x64 EXE, companion BAT/PS1, runtime notices, README, SHA-256 list and portable ZIP |

The live test recorded only counts/status. Export, comparison and screenshot fixtures used synthetic data. Provider coverage and timings vary across PCs; the runtime packs are bundled, while PowerShell and local hardware providers are still required.

The executable is built locally from the included source. No project license or code-signing certificate is assigned by these changes.

BAT SHA-256:

```text
66001B42458B87FF1918AE258827979E2D6AE8AC04A7E67795394717825354E9
```

Release EXE SHA-256:

```text
04A91C689148A7E02B96C95193514104698D3D71145031B41B602A3E1694526C
```
