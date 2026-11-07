# Desktop verification

[Desktop guide](../README.md) · [Main project](../../README.md)

The BAT remains the collection/report engine. Desktop checks exercise the bridge, process transport and UI without rewriting it.

| Suite | Coverage | Uses actual hardware? |
| --- | --- | --- |
| `test-desktop-bridge.ps1` | 33 checks per PowerShell runtime: complete/partial scans, progress, exact values and field labels, TXT/JSON pairs, old/current comparison, metadata and malformed inputs | No; synthetic engine fixture |
| `EngineClientSmoke` | 34 checks: UTF-8/Unicode paths, literal arguments, result lifetime, stderr draining, protocol/error validation, cancellation, overlap/disposal and temporary-file cleanup | No; synthetic bridge |
| `verify-desktop.ps1 -Mode Render` | Six desktop pages rendered from synthetic inventory for visual inspection | No |
| `verify-desktop.ps1 -Mode Workflow` | 22 checks: ID filtering, hardware refresh, detail reset, RAM display, verified saves, old/new folder detection, coalesced refresh, exact ID changes, comparison invalidation and cancelled-scan restoration | Includes a cancelled read-only scan; saved captures and images use the synthetic fixture |
| `verify-desktop.ps1 -Mode LiveScan` | Full 17-section scan, catalog coverage, returned UI state and responsive timer ticks | Yes; records counts/status only |
| `test-local-sync.ps1` | Shared settings interoperability, concurrent writers, and BAT/desktop discovery of saved pairs | No |
| `UpdaterClientSmoke` | Desktop updater preferences, literal helper arguments, cancellation, downgrade prevention and interrupted-update scheduling | No |

From the repository root, after building the desktop package:

```powershell
# Run once with Windows PowerShell 5.1 and once with PowerShell 7.
.\desktop\tests\test-desktop-bridge.ps1 -BatPath .\hwid.bat

dotnet run --project .\desktop\tests\EngineClientSmoke\EngineClientSmoke.csproj -c Release
dotnet run --project .\desktop\tests\UpdaterClientSmoke\UpdaterClientSmoke.csproj -c Release
.\desktop\tests\test-local-sync.ps1

# The GUI verification runner requires PowerShell 7.
$desktopExe = 'C:\path\to\HWID Checker Desktop\HWID Checker.exe'
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Render -Size 640x480 -LayoutStress
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Workflow
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode Workflow -TestSharedLibrary
.\desktop\tests\verify-desktop.ps1 -ExePath $desktopExe -Mode LiveScan
```

Run live collection in a normal Windows user context with access to the hardware providers. A restricted test sandbox can block provider reads or native runtime extraction independently of app behavior. No test changes hardware identifiers or requires administrator access by default.

`-Size` sets the window size in WPF device-independent units. `-LayoutStress` fills the rendered pages with long synthetic names, paths, warnings and identifiers, then checks the space available to tables and controls. It models reduced layout space without changing Windows display scaling.

`-TestSharedLibrary` adds two Desktop workflow checks for shared registration after a save and removing a watched folder. It uses a separate settings file under the test output directory.

The workflow creates uniquely named synthetic reports and removes its exact synthetic primary-folder file afterward. Other fixture output remains in its dedicated test-output directory for inspection. Test outputs and build directories are excluded by the repository ignore rules. Actual scan snapshots are not automatically exported by the live verification mode.
