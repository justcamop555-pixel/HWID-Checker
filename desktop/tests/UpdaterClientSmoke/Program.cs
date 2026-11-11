using System.Diagnostics;
using System.Text.Json;
using HwidDesktop;

var root = Path.Combine(Path.GetTempPath(), "hwid-updater-client-" + Guid.NewGuid().ToString("N"));
var install = Path.Combine(root, "App & é");
var cache = Path.Combine(root, "Preferences");
Directory.CreateDirectory(install);
File.Copy(Path.Combine(AppContext.BaseDirectory, "FakeUpdater.ps1"), Path.Combine(install, "Update-HWID.ps1"));
var checks = 0;
var currentVersion = Version.Parse(DesktopUpdater.CurrentVersion);
var nextVersion = new Version(currentVersion.Major, currentVersion.Minor, currentVersion.Build + 1).ToString(3);
var previousVersion = (currentVersion.Build > 0
    ? new Version(currentVersion.Major, currentVersion.Minor, currentVersion.Build - 1)
    : currentVersion.Minor > 0
        ? new Version(currentVersion.Major, currentVersion.Minor - 1, 0)
        : new Version(currentVersion.Major - 1, 0, 0)).ToString(3);
void Check(bool value, string description)
{
    if (!value) throw new InvalidOperationException(description);
    checks++;
    Console.WriteLine("PASS: " + description);
}

using (var driveRoot = new DesktopUpdater(@"C:\", Path.Combine(root, "drive-root-cache")))
{
    var fields = typeof(DesktopUpdater);
    const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance;
    Check((string?)fields.GetField("_directory", flags)!.GetValue(driveRoot) == @"C:\" &&
        (string?)fields.GetField("_script", flags)!.GetValue(driveRoot) == @"C:\Update-HWID.ps1",
        "drive-root installs preserve an absolute directory and updater script path");
    var expectedKey = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
        System.Text.Encoding.UTF8.GetBytes("C:")))[..16].ToLowerInvariant();
    var resultPath = (string)fields.GetField("_resultPath", flags)!.GetValue(driveRoot)!;
    Check(Path.GetFileName(Path.GetDirectoryName(resultPath)) == expectedKey + "-package",
        "drive-root cache identity matches the shared updater without writing to the drive root");
}
foreach (var pair in new[]
{
    (Disk: "1.4.3.0", Running: "1.4.3", Newer: false),
    (Disk: "1.4.3", Running: "1.4.3.0", Newer: false),
    (Disk: "1.4.3.7", Running: "1.4.3", Newer: false),
    (Disk: "1.4.4.0", Running: "1.4.3", Newer: true),
    (Disk: "1.4.2.9", Running: "1.4.3", Newer: false),
    (Disk: "1.10.0.0", Running: "1.9.9", Newer: true)
})
    Check(DesktopUpdater.IsNewerPackageVersion(Version.Parse(pair.Disk), Version.Parse(pair.Running)) == pair.Newer,
        "package comparison normalizes file revision: " + pair.Disk + " / " + pair.Running);
var installedExe = Path.Combine(install, "HWID Checker.exe");
File.Copy(typeof(DesktopUpdater).Assembly.Location, installedExe);
Check(DesktopUpdater.ReadInstalledPackageVersion(installedExe) == currentVersion,
    "installed-file metadata normalizes to the same three-part running package version");
using var updater = new DesktopUpdater(install, cache);
Check(updater.AutomaticEnabled, "automatic updates default to enabled for a new local preference");
Check(updater.Status.State != "restart", "equal installed and running versions do not produce restart guidance");
await updater.CheckAsync();
Check(updater.Status.State == "available" && !updater.IsBusy, "version checking releases its process and busy state");
await updater.DownloadAsync();
Check(updater.IsReady && updater.Status.LatestVersion == nextVersion, "preparation exposes a newer ready package");
Check(updater.ScheduleApply(true), "the installer helper starts through the literal PowerShell argument list");
var marker = Path.Combine(install, "applied.json");
var wait = Stopwatch.StartNew();
while (!File.Exists(marker) && wait.Elapsed < TimeSpan.FromSeconds(10)) await Task.Delay(100);
using (var applied = JsonDocument.Parse(File.ReadAllText(marker)))
{
    Check(applied.RootElement.GetProperty("component").GetString() == "Package" &&
        applied.RootElement.GetProperty("relaunch").GetBoolean() &&
        applied.RootElement.GetProperty("process").GetString() == Environment.ProcessId.ToString() &&
        applied.RootElement.GetProperty("source").GetString() == DesktopUpdater.CurrentVersion,
        "the copied helper receives the exact component, parent and restart request");
}
updater.SetAutomatic(false);
using (var reopened = new DesktopUpdater(install, cache))
    Check(!reopened.AutomaticEnabled && reopened.IsReady, "automatic preference and prepared result survive reopening");
File.WriteAllText(Path.Combine(cache, "preferences.json"), "[1]");
using (var malformed = new DesktopUpdater(install, cache))
    Check(!malformed.AutomaticEnabled, "malformed preferences disable automatic installation without a startup exception");
File.WriteAllText(Path.Combine(cache, "preferences.json"), "{\"automaticUpdates\":false,\"AUTOMATICUPDATES\":true}");
using (var duplicate = new DesktopUpdater(install, cache))
    Check(!duplicate.AutomaticEnabled, "conflicting automatic preference fields do not enable updates");

var cachedResultPath = Directory.GetFiles(cache, "result.json", SearchOption.AllDirectories).Single();
void WriteCachedStatus(string state, string sourceVersion, string latestVersion, string message = "Synthetic cached result")
{
    File.WriteAllText(cachedResultPath, JsonSerializer.Serialize(new
    {
        state, currentVersion = sourceVersion, latestVersion,
        component = "Package", installDirectory = install, message
    }));
}
foreach (var state in new[] { "available", "updated", "error", "current", "restart" })
{
    WriteCachedStatus(state, previousVersion, DesktopUpdater.CurrentVersion, "STALE restart message");
    using var stale = new DesktopUpdater(install, cache);
    Check(stale.Status.State == "idle" && !stale.Status.Message.Contains("STALE"),
        "a result from an older running version does not retain stale " + state + " guidance");
}
WriteCachedStatus("available", DesktopUpdater.CurrentVersion, DesktopUpdater.CurrentVersion + ".0");
using (var equal = new DesktopUpdater(install, cache))
    Check(equal.Status.State == "idle" && !equal.IsReady, "an equal four-part cached release does not offer a download or installation");
WriteCachedStatus("available", DesktopUpdater.CurrentVersion, nextVersion + ".0");
using (var newer = new DesktopUpdater(install, cache))
    Check(newer.Status.State == "available" && newer.Status.LatestVersion == nextVersion,
        "a genuinely newer cached release keeps a normalized version label");

File.WriteAllText(Path.Combine(cache, "preferences.json"), "{\"automaticUpdates\":true}");
WriteCachedStatus("current", DesktopUpdater.CurrentVersion, DesktopUpdater.CurrentVersion);
using (var timed = new DesktopUpdater(install, cache))
{
    await timed.PrepareAutomaticallyAsync();
    Check(timed.Status.State == "current", "a recent current result avoids another automatic check");
    File.SetLastWriteTimeUtc(cachedResultPath, DateTime.UtcNow.AddHours(-25));
    await timed.PrepareAutomaticallyAsync();
    Check(timed.IsReady, "an expired current result allows an automatic check");
    timed.SetAutomatic(false);
}
File.WriteAllText(Path.Combine(cache, "preferences.json"), "{\"automaticUpdates\":true}");
WriteCachedStatus("error", DesktopUpdater.CurrentVersion, "", "Synthetic current-version failure");
using (var timed = new DesktopUpdater(install, cache))
{
    await timed.PrepareAutomaticallyAsync();
    Check(timed.Status.State == "error", "a recent current-version failure keeps its one-hour retry delay");
    File.SetLastWriteTimeUtc(cachedResultPath, DateTime.UtcNow.AddHours(-2));
    await timed.PrepareAutomaticallyAsync();
    Check(timed.IsReady, "an expired failure permits a new automatic check");
    timed.SetAutomatic(false);
}
foreach (var flag in new[] { "equal-available.flag", "older-available.flag" })
{
    File.WriteAllText(Path.Combine(install, flag), "");
    await updater.CheckAsync();
    Check(updater.Status.State == "current" && !updater.IsReady,
        "a fresh equal or older result does not advertise an available update: " + flag);
    File.Delete(Path.Combine(install, flag));
}
File.WriteAllText(Path.Combine(install, "busy.flag"), "");
await updater.CheckAsync();
Check(updater.Status.State == "busy", "a busy helper retains its retry guidance instead of becoming a generic error");
File.Delete(Path.Combine(install, "busy.flag"));

void WriteCachedReady(string sourceVersion)
{
    File.WriteAllText(cachedResultPath, JsonSerializer.Serialize(new
    {
        state = "ready", currentVersion = sourceVersion, latestVersion = nextVersion,
        component = "Package", installDirectory = install, stageDirectory = Path.Combine(install, "stage"),
        message = "Synthetic update prepared before an intermediate manual upgrade"
    }));
}
WriteCachedReady(previousVersion);
using (var intermediate = new DesktopUpdater(install, cache))
{
    Check(intermediate.IsReady, "a future package prepared by an older application remains ready after a manual upgrade");
    File.Delete(marker);
    Check(intermediate.ScheduleApply(false), "the previously prepared package can still be scheduled");
    wait.Restart();
    while (!File.Exists(marker) && wait.Elapsed < TimeSpan.FromSeconds(10)) await Task.Delay(100);
    using var request = JsonDocument.Parse(File.ReadAllText(marker));
    Check(request.RootElement.GetProperty("source").GetString() == previousVersion,
        "normal installation retains the prepared manifest's original source version");
}
foreach (var invalidSource in new[] { "", "invalid", currentVersion.Major + ".0", DesktopUpdater.CurrentVersion + ".0", nextVersion })
{
    WriteCachedReady(invalidSource);
    using var invalid = new DesktopUpdater(install, cache);
    Check(!invalid.IsReady && !invalid.ScheduleApply(false),
        "a missing, malformed or inapplicable prepared source cannot schedule installation: " + invalidSource);
}

File.WriteAllText(Path.Combine(install, "equal.flag"), "");
await updater.DownloadAsync();
var interrupted = Path.Combine(install, ".hwid-update-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(interrupted);
File.WriteAllText(Path.Combine(interrupted, "transaction.json"), JsonSerializer.Serialize(new
{
    schema = 1, installDirectory = install, component = "Package", version = DesktopUpdater.CurrentVersion, state = "active"
}));
using (var repair = new DesktopUpdater(install, cache))
{
    Check(repair.IsReady && repair.Status.State == "repair", "an interrupted same-version transaction remains repairable on reopen");
    File.Delete(marker);
    Check(repair.ScheduleApply(false), "repair can be scheduled after the running application exits");
    wait.Restart();
    while (!File.Exists(marker) && wait.Elapsed < TimeSpan.FromSeconds(10)) await Task.Delay(100);
    using var request = JsonDocument.Parse(File.ReadAllText(marker));
    Check(request.RootElement.GetProperty("source").GetString() == previousVersion,
        "repair keeps the prepared transaction's original version identity");
}
File.WriteAllText(Path.Combine(interrupted, "recovered.json"), "{}");
File.Delete(Path.Combine(install, "equal.flag"));
File.WriteAllText(Path.Combine(install, "older.flag"), "");
await updater.DownloadAsync();
Check(!updater.IsReady && !updater.ScheduleApply(false), "an older ready result cannot schedule a downgrade");
File.Delete(Path.Combine(install, "older.flag"));
File.WriteAllText(Path.Combine(install, "bad.flag"), "");
await updater.CheckAsync();
Check(updater.Status.State == "error" && !updater.IsBusy, "invalid helper output returns a readable error");
File.Delete(Path.Combine(install, "bad.flag"));
File.WriteAllText(Path.Combine(install, "slow.flag"), "");
var pending = updater.DownloadAsync();
await Task.Delay(450);
Check(updater.IsBusy, "preparation stays asynchronous");
updater.Cancel();
await pending;
Check(!updater.IsBusy && updater.Status.State == "idle", "cancelling stops the owned helper and restores controls");
File.Delete(Path.Combine(install, "slow.flag"));

var nextResource = Path.Combine(root, "newer-resource.exe");
var resourceSource = Path.Combine(root, "newer-resource.cs");
File.WriteAllText(resourceSource, "using System.Reflection; [assembly:AssemblyVersion(\"" + nextVersion +
    "\")] [assembly:AssemblyFileVersion(\"" + nextVersion + ".0\")] public class SyntheticVersionResource {}");
var compiler = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe");
var compilerStart = new ProcessStartInfo(compiler) { UseShellExecute = false, CreateNoWindow = true };
foreach (var argument in new[] { "/nologo", "/target:library", "/out:" + nextResource, resourceSource }) compilerStart.ArgumentList.Add(argument);
using (var compilation = Process.Start(compilerStart) ?? throw new IOException("The synthetic version resource could not be compiled."))
{
    if (!compilation.WaitForExit(10000)) { compilation.Kill(entireProcessTree: true); throw new IOException("Synthetic resource compilation timed out."); }
    Check(compilation.ExitCode == 0, "the newer-version fixture has native Windows version metadata");
}
File.Copy(nextResource, installedExe, overwrite: true);
await updater.CheckAsync();
Check(updater.Status.State == "restart" && updater.Status.LatestVersion == nextVersion && !updater.IsReady,
    "only an actually newer installed executable asks the older running app to restart");
using (var reopened = new DesktopUpdater(install, cache))
{
    Check(reopened.Status.State == "restart", "a newer installed executable takes precedence over a stale cached result");
    File.Copy(typeof(DesktopUpdater).Assembly.Location, installedExe, overwrite: true);
    await reopened.CheckAsync();
    Check(reopened.Status.State == "available", "restart guidance clears when the installed and running versions match again");
}
Console.WriteLine(JsonSerializer.Serialize(new { checks, syntheticOnly = true }));
