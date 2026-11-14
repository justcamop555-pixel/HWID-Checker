# Desktop verification

[Desktop guide](../README.md) · [Main project](../../README.md)

## Native startup and high-DPI layouts

From the repository root, use the complete extracted 1.5.0 package:

```powershell
.\desktop\tests\test-native-launcher.ps1 -ExePath '<package>\HWID Checker.exe' -OutputDirectory '<new-test-folder>'
.\desktop\tests\test-runtime-package.ps1 -Archive '<package.zip>' -Version '1.5.0' -OutputDirectory '<new-test-folder>'
.\desktop\tests\verify-desktop.ps1 -ExePath '<package>\HWID Checker.exe' -Mode Render -Size 683x360 -LayoutStress -OutputDirectory '<new-test-folder>'
```

The launcher test uses a synthetic .NET Framework child to check argument forwarding, readiness, exit status, cancellation and missing files. The package test validates the actual ZIP and rejects a missing runtime file. Small-window renders and Library DPI math checks supplement, but do not replace, testing on physical monitors at different scaling settings. Startup timing reports for the native EXE measure the parent's memory only; do not compare that number with a single-process application's total memory.

The BAT remains the collection/report engine. Desktop checks exercise the bridge, process transport and UI without rewriting it.

| Suite | Coverage | Uses actual hardware? |
| --- | --- | --- |
| `test-desktop-bridge.ps1` | 46 checks per PowerShell runtime: complete/partial/unreadable scans, older-BAT compatibility, progress guidance, exact values and field labels, TXT/JSON pairs, comparison and malformed inputs | No; synthetic engine fixture |
| `EngineClientSmoke` | 47 checks: scoped cleanup with transient-lock retries, explicit first/rescan number transport, bounded Unicode protocol lines, immediate reported-error handling, progress diagnostics, literal arguments, result lifetime, stderr draining, cancellation and cleanup | No; synthetic bridge |
| `DesktopModelsSmoke` | 80 checks: readable metadata, exact identifiers, coverage, catalog states, snapshot discovery, staged exports, indexed ID/review search equivalence, immutable rows and new-capture isolation | No |
| `verify-desktop.ps1 -Mode Render` | Six desktop pages rendered from synthetic inventory for visual inspection | No |
| `verify-desktop.ps1 -Mode Readability` | 14 checks: regular 14-DIP body text, full hardware names/counts, useful default sections, readable capture details, original-value copying and compact/reduced-space layouts | No; synthetic fixture |
| `verify-desktop.ps1 -Mode Workflow` | 22 checks: ID filtering, hardware refresh, detail reset, RAM display, verified saves, old/new folder detection, coalesced refresh, exact ID changes, comparison invalidation and cancelled-scan restoration | Includes a cancelled read-only scan; saved captures and images use the synthetic fixture |
| `verify-desktop.ps1 -Mode Interactions` | 80 checks: semantic status labels, dark/light text contrast, restart control locking, ID labels, hardware counts/selection, copy guards, empty-state guidance, review/compare, progress, navigation, reduced motion and closing | No; synthetic fixture and progress events |
| `RestartHandoffSmoke` | 20 real-process checks: readiness, commit/abort, cancellation, bounded timeout, launch/early-exit failures, exact Unicode/zeroes, bounded frames and invalid inputs | No; in-memory synthetic state |
| `verify-desktop.ps1 -Mode Restart` | A real desktop-process replacement restores synthetic capture data, filters, theme, selected comparison and page before the original closes | No; synthetic fixture |
| `verify-desktop.ps1 -Mode Scrolling` | 31 checks: routed wheel events over Overview and all five other tables, Overview keyboard navigation, detail boundaries, text/filter input and native scrollbar dragging/range bindings | No; synthetic fixture |
| `verify-desktop.ps1 -Mode Theme` | At least 26 checks: main/Updates/Folder settings/Welcome native theme application during dark/light/dark switching, shared caption resources, native window controls and unchanged library settings | No; synthetic fixture |
| `verify-desktop.ps1 -Mode Welcome` | 28 checks: first/repeated/dismissed/restart/test startup policy, dark/light regular/compact notice layout, readable checkbox text, footer actions, keyboard focus, scrolling, Not now, preference reload and asynchronous/close-save ordering | No; synthetic fixture and isolated settings |
| `verify-desktop.ps1 -Mode LiveScan` | Full 18-section scan, catalog coverage, returned UI state and responsive timer ticks | Yes; records counts/status only |
| `test-local-sync.ps1` | Shared settings interoperability, concurrent writers, and BAT/desktop discovery of saved pairs | No |
| `UpdaterClientSmoke` | 51 checks: equal file/package versions, stale/current result handling, genuine restart states, drive-root paths, preferences, cancellation and prepared-source binding/recovery | No |

From the repository root, after building the desktop package:

```powershell
# Run once with Windows PowerShell 5.1 and once with PowerShell 7.
.\desktop\tests\test-desktop-bridge.ps1 -BatPath .\hwid.bat

dotnet run --project .\desktop\tests\EngineClientSmoke\EngineClientSmoke.csproj -c Release
dotnet run --project .\desktop\tests\RestartHandoffSmoke\RestartHandoffSmoke.csproj -c Release
dotnet run --project .\desktop\tests\DesktopModelsSmoke\DesktopModelsSmoke.csproj -c Release
dotnet run --project .\desktop\tests\UpdaterClientSmoke\UpdaterClientSmoke.csproj -c Release
.\desktop\tests\test-local-sync.ps1

# The GUI verification runner requires PowerShell 7.
$desktopExe = 'C:\path\to\HWID Checker Desktop\HWID Checker.exe'
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render -Size 640x480 -LayoutStress
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Workflow
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Workflow -TestSharedLibrary
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Interactions -Size 640x480
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Restart -Size 640x480
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Theme -Size 840x560
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Welcome -Size 640x480
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render -Size 840x560 -Theme Daylight -LayoutStress
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Readability -Size 640x480
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render -Size 840x560 -LayoutStress
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode LiveScan
```

Run live collection in a normal Windows user context with access to the hardware providers. A restricted test sandbox can block provider reads or native runtime extraction independently of app behavior. No test changes hardware identifiers or requires administrator access by default.

Restart tests also need a normal same-user Windows context: restricted test tokens can deny the named-pipe connection. The code keeps `CurrentUserOnly`; it does not weaken pipe access to make a restricted test pass. These tests do not save hardware snapshots.

`-Size` sets the window size in WPF device-independent units. `-LayoutStress` fills the rendered pages with long synthetic names, paths, warnings and identifiers, then checks the space available to tables and controls. It models reduced layout space without changing Windows display scaling.

An 840 × 560 DIP window also checks the logical space corresponding to a 1260 × 840 physical-pixel window at 150% display scaling. These renders use the current system DPI and do not replace testing on a display configured at that scaling.

`-TestSharedLibrary` adds two Desktop workflow checks for shared registration after a save and removing a watched folder. It uses a separate settings file under the test output directory.

The workflow creates uniquely named synthetic reports and removes its exact synthetic primary-folder file afterward. Other fixture output remains in its dedicated test-output directory for inspection. Test outputs and build directories are excluded by the repository ignore rules. Actual scan snapshots are not automatically exported by the live verification mode.
## Snapshot library and console recovery

Run the packaged EXE with the synthetic library UI checks (38 checks) at regular or compact sizes:

```powershell
.\desktop\tests\verify-desktop.ps1 -ExePath '.\HWID Checker.exe' -BatPath '.\hwid.bat' -Mode Library -Size 640x480 -OutputDirectory '.\test-output-library'
```

This covers PC/date/folder search, selection retention and removal, comparison without a current scan, source labels, exact ID searches/differences, all comparison categories, false empty-state prevention, full export retention, restart state and compact dark/light table space. Connection regressions cover missing/truncated/oversized files, clearing stale labels, recovery with configured shared settings, old snapshot discovery and retaining column sorts across filters. The EXE's embedded recovery files must match the selected package. Screenshots and settings fixtures are synthetic.

```powershell
dotnet run --project .\desktop\tests\EngineRecoverySmoke\EngineRecoverySmoke.csproj -c Release
```

The 24 standard recovery checks use isolated folders and parser subprocesses. A 25th check supplies both Windows PowerShell 5.1 and PowerShell 7 to ensure an earlier parser rejection cannot override a valid later runtime. They cover consent before any repair, unusable-runtime diagnostics, cancellation, deleted/corrupt companions, concurrent repairs, custom-file preservation, required versus unused launchers, renamed BAT arguments, theme/signal environment and no snapshot/settings writes. They do not interact with a terminal window or change PowerShell policy.

Library verification also checks compact repair dialogs in both themes, acceptance/decline actions, missing/duplicate device-matching explanations and comparison direction warnings. The desktop bridge regression includes three checks for preserving conflict diagnostics and rejecting guessed matches.

## Scan progress and repeated scans

```powershell
.\desktop\tests\verify-desktop.ps1 -ExePath '.\HWID Checker.exe' -BatPath '.\hwid.bat' -Mode ScanUI -Size 640x480 -OutputDirectory '.\test-output-scan-ui'
.\desktop\tests\verify-desktop.ps1 -ExePath '.\HWID Checker.exe' -BatPath '.\hwid.bat' -Mode LiveScan -RepeatScan -OutputDirectory '.\test-output-rescan'
```

ScanUI runs 22 synthetic checks for scan numbering, CHECK/read/failure counts, delayed and obsolete feedback, complete error guidance, finalization before publication, cancellation, restoring an earlier capture and readable compact counters in both themes. The repeat mode runs two actual read-only scans and checks that the second publishes scan number 2; diagnostics retain counts/status rather than hardware values. Use a normal same-user Windows context for live provider checks.

Setup verification: build `desktop/build-setup.ps1 -TestInstall` from a verified package, then run `desktop/tests/test-setup.ps1 -SetupPath <TEST.exe> -PackageDirectory <package> -OutputDirectory <new-test-folder>`. This uses a separate per-user registration, restores deliberately deleted/corrupted test companions and verifies saved/custom files survive uninstall. Production administrator/UAC behavior is not covered by this mode. Never publish the TEST executable.

Library UI checks cover Review type filtering, clearing both filters, exact long ID text and compact full-detail dialogs in both themes. UpdaterClientSmoke checks installed report defaults and blocks scheduling the portable updater against installed copies.
