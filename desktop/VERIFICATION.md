# Desktop verification

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
