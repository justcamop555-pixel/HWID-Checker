# Developer checks

[Back to the main README](../README.md)

Tests are optional for users. Run them from the repository root in a Windows PowerShell 5.1+ session that permits these scripts.

```powershell
.\tests\test-hwid.ps1
.\tests\test-runtime-launchers.ps1
```

| File | Checks | Reads actual hardware? |
| --- | --- | --- |
| `test-hwid.ps1` | 603 synthetic regression checks: menu, scan continuation, fallback recovery, rescan state, overview, IDs, export/import and comparisons | No |
| `test-snapshot-catalog.ps1` | 26 checks: older-file detection, renamed/damaged reports, capture ordering, pagination, TXT companion lookup and save fallback/rollback | No |
| `test-snapshot-storage.ps1` | 38 checks: strict import encodings, locked-file recovery, size limits, relative paths, storage counts, severity colors and inaccessible-folder handling | No |
| `test-id-view.ps1` | 28 checks: malformed scalar IDs, valid strings/lists/zero values, serial/MAC labels, null rows, adapter metadata and safe display | No |
| `test-review.ps1` | 24 checks: warning deduplication/recovery, stored failures, extended failures, duplicate statuses, resource conflicts and consistent review totals | No |
| `test-scan-metadata.ps1` | 41 checks: optional storage/partition/memory/monitor conversions, raw-value retention, direct/worker scan agreement and report round trips | No |
| `test-scan-recovery.ps1` | 34 checks: bounded provider-property retry, preserved filters/timeouts, partial-output isolation, error classification, full scans and saved recovery metadata in both scan modes | No |
| `test-comparison-identity.ps1` | 34 checks: case-varied schema names, exact identifier-value changes, missing fields and ambiguous system/firmware records | No |
| `test-network-scan.ps1` | 41 checks: fallback status types, ambiguous/current addresses, malformed optional metadata, raw-value preservation and snapshot comparisons in both scan modes | No |
| `test-save-scan-handling.ps1` | 22 checks: final-file verification, corruption/rollback, Unicode, scan/save timestamps, copied-array structure and progress-display failure isolation | No |
| `test-scan-content.ps1` | 27 checks: empty projected records, derived labels, zero/false values, mixed model-ID lists, raw-value retention, scan counts and review findings in both scan modes | No |
| `test-animation.ps1` | 38 checks: moving borders, direction/trails, narrow labels, bounded frames, destinations, timing and disabled-animation behavior | No |
| `test-runtime-launchers.ps1` | Eight launcher/runtime cases, including missing/old/restricted engines and the PS1 loader | No |
| `test-readable-console.ps1` | Native console layout, snapshot picker/storage navigation, comparison navigation, scan continuation, scrolling, history, input modes, overview states and animation restoration | No; opens a temporary console |
| `test-readable-startup.ps1` | Actual launcher, scan continuation, display setup, invalid input and held Enter | Yes; opens a temporary console |
| `test-live-rescan.ps1` | Initial scan, rescan and snapshot publication; optional `-LiveProgress` and `-Extended` | Yes |
| `test-live-extended.ps1` | Actual extended-device catalog and property coverage | Yes |

Live diagnostics print counts/status/timing rather than device identifiers. The console tests need an interactive Windows desktop. The startup diagnostic has a bounded wait and may time out on slower systems.

Tests may leave synthetic reports, temporary launcher cases and diagnostic scripts under `tests/`. These generated paths are ignored by Git. Do not run every diagnostic concurrently; native console tests share result filenames.

The tests locate `hwid.bat` and `Start-HWID.ps1` in the repository root. Keep the folder structure when moving the repository.
