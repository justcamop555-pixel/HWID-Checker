# Desktop verification

[Desktop guide](../README.md) · [Main project](../../README.md)

The BAT remains the collection/report engine. Desktop checks exercise the bridge, process transport and UI without rewriting it.

| Suite | Coverage | Uses actual hardware? |
| --- | --- | --- |
| `test-desktop-bridge.ps1` | 41 checks per PowerShell runtime: complete/partial/unreadable scans, older-BAT compatibility, progress guidance, exact values and field labels, TXT/JSON pairs, comparison and malformed inputs | No; synthetic engine fixture |
| `EngineClientSmoke` | 42 checks: bounded Unicode protocol lines, immediate reported-error handling, progress diagnostics, literal arguments, result lifetime, stderr draining, cancellation and cleanup | No; synthetic bridge |
| `DesktopModelsSmoke` | 27 checks: readable metadata/section names, legacy display fallbacks, accurate captured/read counts, RAM slot names, original values and exact identifiers, and saved capture discovery | No |
| `verify-desktop.ps1 -Mode Render` | Six desktop pages rendered from synthetic inventory for visual inspection | No |
| `verify-desktop.ps1 -Mode Readability` | 14 checks: regular 14-DIP body text, full hardware names/counts, useful default sections, readable capture details, original-value copying and compact/reduced-space layouts | No; synthetic fixture |
| `verify-desktop.ps1 -Mode Workflow` | 22 checks: ID filtering, hardware refresh, detail reset, RAM display, verified saves, old/new folder detection, coalesced refresh, exact ID changes, comparison invalidation and cancelled-scan restoration | Includes a cancelled read-only scan; saved captures and images use the synthetic fixture |
| `verify-desktop.ps1 -Mode Interactions` | 47 checks: empty-state guidance and compact screenshots, unchanged/unusable/one-sided/self-comparison results, stale/cancelled progress and actionable diagnostics, scalar/nested search, navigation, copy guards, scrolling, selection, reduced motion and closing | No; synthetic fixture and progress events |
| `verify-desktop.ps1 -Mode Readability` | 14 checks: default type, hardware-first selection, full section names/counts, friendly metadata, exact original values, catalog-only fallback and compact/reduced-space hardware screenshots | No; synthetic fixture |
| `verify-desktop.ps1 -Mode LiveScan` | Full 18-section scan, catalog coverage, returned UI state and responsive timer ticks | Yes; records counts/status only |
| `test-local-sync.ps1` | Shared settings interoperability, concurrent writers, and BAT/desktop discovery of saved pairs | No |
| `UpdaterClientSmoke` | 51 checks: equal file/package versions, stale/current result handling, genuine restart states, drive-root paths, preferences, cancellation and prepared-source binding/recovery | No |

From the repository root, after building the desktop package:

```powershell
# Run once with Windows PowerShell 5.1 and once with PowerShell 7.
.\desktop\tests\test-desktop-bridge.ps1 -BatPath .\hwid.bat

dotnet run --project .\desktop\tests\EngineClientSmoke\EngineClientSmoke.csproj -c Release
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
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Readability -Size 640x480
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render -Size 840x560 -LayoutStress
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode LiveScan
```

Run live collection in a normal Windows user context with access to the hardware providers. A restricted test sandbox can block provider reads or native runtime extraction independently of app behavior. No test changes hardware identifiers or requires administrator access by default.

`-Size` sets the window size in WPF device-independent units. `-LayoutStress` fills the rendered pages with long synthetic names, paths, warnings and identifiers, then checks the space available to tables and controls. It models reduced layout space without changing Windows display scaling.

An 840 × 560 DIP window also checks the logical space corresponding to a 1260 × 840 physical-pixel window at 150% display scaling. These renders use the current system DPI and do not replace testing on a display configured at that scaling.

`-TestSharedLibrary` adds two Desktop workflow checks for shared registration after a save and removing a watched folder. It uses a separate settings file under the test output directory.

The workflow creates uniquely named synthetic reports and removes its exact synthetic primary-folder file afterward. Other fixture output remains in its dedicated test-output directory for inspection. Test outputs and build directories are excluded by the repository ignore rules. Actual scan snapshots are not automatically exported by the live verification mode.
