# Overview metric probe

Run against a complete built Desktop package, once per process:

```powershell
dotnet run --project .\desktop\tests\OverviewMetricsPerf -c Release -- '<package>\HWID Checker.dll' '<new-result.json>'
```

The probe loads the real WPF controls but never shows a window or starts the application event loop. Verification arguments skip user preferences; it does not connect the scanner, read hardware, enumerate saved reports or write settings. It checks initial, replaced and explicitly reapplied captures and dynamic theme resources.

The non-gating microbenchmark repeats 500 overview metric updates against a synthetic 3,000-record capture. Compare separate runs of this same probe against old and new packages. Its allocation and operation time do not measure complete application startup, hardware query speed, or total process memory.
