using HwidDesktop;
using System.Security.Cryptography;

var root = Path.Combine(Path.GetTempPath(), "hwid-recovery-check-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var checks = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); checks++; Console.WriteLine("PASS: " + name); }
var runtime = args.Length > 0 ? args[0] : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
var recovery = Path.Combine(root, "Recovery");
var gatedFolder = Path.Combine(root, "ConsentRequired");
var deleted = Path.Combine(root, "deleted.bat");
var requested = false;
try { await EngineRecovery.PrepareAsync(deleted, new[] { runtime }, CancellationToken.None, gatedFolder); }
catch (ConsoleRepairRequiredException error) { requested = error.SourcePath == deleted; }
Check(requested && !Directory.Exists(gatedFolder), "missing BAT requests consent before creating or changing recovery files");
var missingOnly = false;
try { await EngineRecovery.PrepareAsync(deleted, new[] { Path.Combine(root, "missing-runtime.exe") }, CancellationToken.None, gatedFolder); }
catch (ConsoleRepairRequiredException) { throw new Exception("runtime failure must not suggest file repair"); }
catch (IOException error) { missingOnly = error.Message.Contains("PowerShell"); }
Check(missingOnly && !Directory.Exists(gatedFolder), "an unusable runtime does not prompt for an ineffective file repair");
using (var stop = new CancellationTokenSource())
{
    stop.Cancel();
    try { await EngineRecovery.PrepareAsync(deleted, new[] { runtime }, stop.Token, gatedFolder, allowRepair: true); }
    catch (OperationCanceledException) { }
    Check(!Directory.Exists(gatedFolder), "cancellation after consent still prevents publication");
}
var restored = EngineRecovery.Restore(recovery);
Check(File.ReadAllBytes(restored).AsSpan().SequenceEqual(EngineRecovery.Resource("Bat")), "offline BAT recovery matches the embedded build");
var launcher = Path.Combine(Path.GetDirectoryName(restored)!, "Start-HWID.ps1");
Check(File.ReadAllBytes(launcher).AsSpan().SequenceEqual(EngineRecovery.Resource("Launcher")), "offline launcher recovery matches the embedded build");
var stamp = File.GetLastWriteTimeUtc(restored);
Check(EngineRecovery.Restore(recovery) == restored && File.GetLastWriteTimeUtc(restored) == stamp, "a healthy restored scanner is reused without rewriting");
File.Delete(restored);
Check(File.Exists(EngineRecovery.Restore(recovery)), "a deleted restored BAT is recreated");
await File.WriteAllTextAsync(restored, "incomplete");
await File.WriteAllTextAsync(launcher, "bad loader");
EngineRecovery.Restore(recovery);
Check(File.ReadAllBytes(restored).AsSpan().SequenceEqual(EngineRecovery.Resource("Bat")), "corrupted managed BAT content is repaired");
Check(File.ReadAllBytes(launcher).AsSpan().SequenceEqual(EngineRecovery.Resource("Launcher")), "corrupted managed launcher content is repaired");
await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => Task.Run(() => EngineRecovery.Restore(recovery))));
Check(!Directory.EnumerateFiles(Path.GetDirectoryName(restored)!, "*.pending-*").Any(), "concurrent repairs leave no pending files");
var custom = Path.Combine(root, "Custom ! & ' path"); Directory.CreateDirectory(custom);
var customBat = Path.Combine(custom, "custom checker.bat"); var customLoader = Path.Combine(custom, "Start-HWID.ps1");
File.WriteAllBytes(customBat, EngineRecovery.Resource("Bat")); File.WriteAllBytes(customLoader, EngineRecovery.Resource("Launcher"));
var prepared = await EngineRecovery.PrepareAsync(customBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(!prepared.Recovered && prepared.BatPath == customBat, "an existing valid custom scanner remains selected");
var customStart = EngineRecovery.StartInfo(prepared, true);
Check(customStart.ArgumentList.Contains("-EncodedCommand") && customStart.Environment["HWID_DESKTOP_SOURCE"] == customBat,
    "a renamed custom BAT is launched by its own path rather than a missing hwid.bat sibling");
File.Delete(customLoader);
prepared = await EngineRecovery.PrepareAsync(customBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(!prepared.Recovered && prepared.BatPath == customBat, "a renamed valid BAT does not require an unused sibling launcher");
var standardBat = Path.Combine(custom, "hwid.bat"); File.WriteAllBytes(standardBat, EngineRecovery.Resource("Bat"));
prepared = await EngineRecovery.PrepareAsync(standardBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(prepared.Recovered && File.Exists(standardBat), "a standard BAT with a missing required loader falls back without overwriting it");
File.WriteAllBytes(customLoader, EngineRecovery.Resource("Launcher"));
var broken = "@echo off\r\n# POWERSHELL_START\r\nfunction Get-CheckerTheme { 'x' }\r\nfunction broken {";
await File.WriteAllTextAsync(customBat, broken);
prepared = await EngineRecovery.PrepareAsync(customBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(prepared.Recovered && await File.ReadAllTextAsync(customBat) == broken, "a parser failure selects the bundled pair and preserves damaged custom content");
File.WriteAllBytes(customBat, EngineRecovery.Resource("Bat"));
await File.WriteAllTextAsync(customLoader, "function broken {");
prepared = await EngineRecovery.PrepareAsync(customBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(!prepared.Recovered && await File.ReadAllTextAsync(customLoader) == "function broken {", "an unused invalid loader cannot reject a renamed scanner");
prepared = await EngineRecovery.PrepareAsync(standardBat, new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(prepared.Recovered && await File.ReadAllTextAsync(customLoader) == "function broken {", "a required invalid loader falls back without executing or replacing it");
prepared = await EngineRecovery.PrepareAsync(Path.Combine(root, "deleted.bat"), new[] { runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(prepared.Recovered, "a missing linked BAT is recovered after explicit permission");
prepared = await EngineRecovery.PrepareAsync(null, new[] { Path.Combine(root, "missing-runtime.exe"), runtime }, CancellationToken.None, recovery, allowRepair: true);
Check(prepared.Runtime == runtime, "a missing preferred runtime falls through to a usable installed runtime");
var missingRuntime = false;
try { await EngineRecovery.PrepareAsync(null, Array.Empty<string>(), CancellationToken.None, Path.Combine(root, "NoRuntime")); }
catch (IOException error) { missingRuntime = error.Message.Contains("PowerShell"); }
Check(missingRuntime && !Directory.Exists(Path.Combine(root, "NoRuntime")), "no-runtime failure gives an actionable error without creating a repair folder");
using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
var cancelled = false;
try { await EngineRecovery.PrepareAsync(null, new[] { runtime }, cancellation.Token, recovery); } catch (OperationCanceledException) { cancelled = true; }
Check(cancelled, "cancelled preparation stops before publishing another repair");
var start = EngineRecovery.StartInfo(prepared, false);
var originalLauncher = prepared.Launcher;
if (args.Length > 1)
{
    File.WriteAllBytes(customLoader, EngineRecovery.Resource("Launcher"));
    await File.WriteAllTextAsync(customBat, System.Text.Encoding.UTF8.GetString(EngineRecovery.Resource("Bat")) + "\r\n$null = $null ?? 'PowerShell 7 syntax'");
    prepared = await EngineRecovery.PrepareAsync(customBat, new[] { runtime, args[1] }, CancellationToken.None, recovery, allowRepair: true);
    Check(!prepared.Recovered && prepared.Runtime == args[1], "a valid PowerShell 7 scanner survives an earlier PowerShell 5.1 parser rejection");
}
Check(start.UseShellExecute == false && start.ArgumentList.Last() == originalLauncher && start.Environment["HWID_THEME"] == "Daylight", "launch uses structured arguments and the selected theme");
Check(new[] { "HWID_OWN_CONSOLE", "HWID_CURRENT_WINDOW", "HWID_STARTUP_SIGNAL", "HWID_RESTART_SIGNAL" }.All(name => !start.Environment.ContainsKey(name)),
    "startup and restart signal variables do not leak into a new console");
Check(!Directory.EnumerateFiles(root, "*.json", SearchOption.AllDirectories).Any(), "recovery does not write a hardware snapshot or settings");
Console.WriteLine($"All {checks} offline recovery checks passed. Synthetic files: {root}");
