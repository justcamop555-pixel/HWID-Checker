# Desktop verification

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
