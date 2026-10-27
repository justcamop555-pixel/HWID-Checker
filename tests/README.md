# Developer checks

[Back to the main README](../README.md)

Tests are optional for users. Run them from the repository root in a Windows PowerShell 5.1+ session that permits these scripts.

```powershell
.\tests\test-hwid.ps1
.\tests\test-runtime-launchers.ps1
```

| File | Checks | Reads actual hardware? |
| --- | --- | --- |
| `test-hwid.ps1` | 585 synthetic regression checks: menu, scanning failures and fallback recovery, rescan state, overview, IDs, export/import and comparisons | No |
| `test-runtime-launchers.ps1` | Eight launcher/runtime cases, including missing/old/restricted engines and the PS1 loader | No |
| `test-readable-console.ps1` | Native console layout, scrolling, history, input modes, overview states and animation restoration | No; opens a temporary console |
| `test-readable-startup.ps1` | Actual launcher, display setup, invalid input and held Enter | Yes; opens a temporary console |
| `test-live-rescan.ps1` | Initial scan, rescan and snapshot publication; optional `-LiveProgress` and `-Extended` | Yes |
| `test-live-extended.ps1` | Actual extended-device catalog and property coverage | Yes |

Live diagnostics print counts/status/timing rather than device identifiers. The console tests need an interactive Windows desktop. The startup diagnostic has a bounded wait and may time out on slower systems.

Tests may leave synthetic reports, temporary launcher cases and diagnostic scripts under `tests/`. These generated paths are ignored by Git. Do not run every diagnostic concurrently; native console tests share result filenames.

The tests locate `hwid.bat` and `Start-HWID.ps1` in the repository root. Keep the folder structure when moving the repository.
