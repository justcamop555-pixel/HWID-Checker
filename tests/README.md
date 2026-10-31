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
| `test-network-scan.ps1` | 41 checks: fallback status types, unverified reported-address lists, malformed optional metadata, raw-value preservation and snapshot comparisons in both scan modes | No |
| `test-graphics-network.ps1` | 50 checks: organized graphics/network/monitor sections, address evidence, optional fields, directional rates, source labels, raw-value retention, comparisons, snapshots and native scrolling at 80/24 columns | No; opens a hidden temporary console |
| `test-save-scan-handling.ps1` | 22 checks: final-file verification, corruption/rollback, Unicode, scan/save timestamps, copied-array structure and progress-display failure isolation | No |
| `test-scan-content.ps1` | 27 checks: empty projected records, derived labels, zero/false values, mixed model-ID lists, raw-value retention, scan counts and review findings in both scan modes | No |
| `test-animation.ps1` | 38 checks: moving borders, direction/trails, narrow labels, bounded frames, destinations, timing and disabled-animation behavior | No |
| `test-pnp-fallback.ps1` | 29 checks: present-only fallback, alias mapping, preserved IDs/source, empty/missing readers, partial errors, access/timeouts and localized typed failures in both scan modes | No |
| `test-reader-attempts.ps1` | 34 checks: non-terminating partial-error recovery, CIM/legacy-WMI property retries, network/extended fallbacks, final failures, scope/metadata preservation and saved comparison consistency in both scan modes | No |
| `test-extended-refresh.ps1` | 66 checks: contradictory/equal property readings, malformed keys and catalogs, manual/full refresh publication, latest failure details, recovery clearing and snapshot round trips in both scan modes | No |
| `test-pnp-refresh.ps1` | 33 checks: raw key validation in both present-device readers, manual refresh failure/recovery, strict status values and saved identifier consistency | No |
| `test-hidden-devices.ps1` | 47 checks: scalar/conflicting problem codes, optional parent isolation, Class aliases, overlapping device views, rendered counts and saved raw metadata | No |
| `test-instance-aliases.ps1` | 28 checks: Windows DeviceID fallback, blank/NUL aliases, exact ID/source preservation, normalized property/parent matching, malformed keys and saved snapshots | No |
| `test-device-id-lists.ps1` | 34 checks: normal/extended ID-list parity, exact values, malformed raw retention, repeated/different list observations, primary preference, review and snapshot round trips | No |
| `test-id-completeness.ps1` | 68 checks: cross-source ID disagreements, exact text/zeros/order, compatible-ID source labels, optional container/base-container GUIDs, raw malformed observations, snapshot round trips, serialized property calls and distinct-node coverage across 65 nodes in direct/worker modes | No |
| `test-scan-diagnostics.ps1` | 60 checks: localized WMI HRESULTs/legacy error codes, present-only recovery, access/timeout retry suppression, final-reader diagnostics, padded duplicates, model coverage and saved snapshots | No |
| `test-device-coverage.ps1` | 36 checks: all-known startup/rescan coverage, progress stages, failed-batch isolation, bounded retries, error containment, raw-ID preservation and snapshot metadata in both scan modes | No |
| `test-scan-scroll.ps1` | 33 native checks: bounded scan history, viewport-preserving timer/output writes, injected keys during a worker query, follow/pause controls, held Enter, resizing, narrow full scans and cleanup | No; opens a hidden temporary console |
| `test-runtime-launchers.ps1` | Eight launcher/runtime cases, including missing/old/restricted engines and the PS1 loader | No |
| `test-startup-recovery.ps1` | 35 checks: CMD preparation order, empty/missing/broken bodies, exit-code preservation, both PS loaders, cleanup failures, bounded diagnostics, fatal traps and actual menu-action recovery on 5.1/7 | No |
| `test-scan-scalars.ps1` | 41 checks: present-only consistency, disconnected/unknown presence, scalar/container validation, numeric ranges/enums, nested monitor data, raw-shape preservation and saved comparisons in direct/worker modes | No |
| `test-startup-delay.ps1` | 14 checks: native CMD pause before runtime probes with Enter queued, redirected input, missing/failed timer, empty/shadowed PATH, compatibility gates and exit codes | No; opens a hidden temporary console |
| `test-readable-console.ps1` | Native console layout, snapshot picker/storage navigation, comparison navigation, scan continuation, scrolling, history, input modes, overview states and animation restoration | No; opens a temporary console |
| `test-readable-startup.ps1` | Actual launcher, scan continuation, display setup, invalid input and held Enter | Yes; opens a temporary console |
| `test-live-rescan.ps1` | Initial scan, rescan and snapshot publication; `-LiveProgress` tests worker queries, `-Extended` includes the all-known catalog in the initial scan as well as the rescan | Yes |
| `test-live-extended.ps1` | Actual extended-device catalog and property coverage | Yes |

Live diagnostics print counts/status/timing rather than device identifiers. The console tests need an interactive Windows desktop. The startup diagnostic has a bounded wait and may time out on slower systems.

Tests may leave synthetic reports, temporary launcher cases and diagnostic scripts under `tests/`. These generated paths are ignored by Git. Do not run every diagnostic concurrently; native console tests share result filenames.

The tests locate `hwid.bat` and `Start-HWID.ps1` in the repository root. Keep the folder structure when moving the repository.
