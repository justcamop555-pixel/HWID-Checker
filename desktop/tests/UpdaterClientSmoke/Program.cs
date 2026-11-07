using System.Diagnostics;
using System.Text.Json;
using HwidDesktop;

var root = Path.Combine(Path.GetTempPath(), "hwid-updater-client-" + Guid.NewGuid().ToString("N"));
var install = Path.Combine(root, "App & é");
var cache = Path.Combine(root, "Preferences");
Directory.CreateDirectory(install);
File.Copy(Path.Combine(AppContext.BaseDirectory, "FakeUpdater.ps1"), Path.Combine(install, "Update-HWID.ps1"));
var checks = 0;
void Check(bool value, string description)
{
    if (!value) throw new InvalidOperationException(description);
    checks++;
    Console.WriteLine("PASS: " + description);
}

using var updater = new DesktopUpdater(install, cache);
Check(updater.AutomaticEnabled, "automatic updates default to enabled for a new local preference");
await updater.CheckAsync();
Check(updater.Status.State == "available" && !updater.IsBusy, "version checking releases its process and busy state");
await updater.DownloadAsync();
Check(updater.IsReady && updater.Status.LatestVersion == "1.4.0", "preparation exposes a newer ready package");
Check(updater.ScheduleApply(true), "the installer helper starts through the literal PowerShell argument list");
var marker = Path.Combine(install, "applied.json");
var wait = Stopwatch.StartNew();
while (!File.Exists(marker) && wait.Elapsed < TimeSpan.FromSeconds(10)) await Task.Delay(100);
using (var applied = JsonDocument.Parse(File.ReadAllText(marker)))
{
    Check(applied.RootElement.GetProperty("component").GetString() == "Package" &&
        applied.RootElement.GetProperty("relaunch").GetBoolean() &&
        applied.RootElement.GetProperty("process").GetString() == Environment.ProcessId.ToString(),
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

File.WriteAllText(Path.Combine(install, "equal.flag"), "");
await updater.DownloadAsync();
var interrupted = Path.Combine(install, ".hwid-update-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(interrupted);
File.WriteAllText(Path.Combine(interrupted, "transaction.json"), JsonSerializer.Serialize(new
{
    schema = 1, installDirectory = install, component = "Package", version = "1.3.0", state = "active"
}));
using (var repair = new DesktopUpdater(install, cache))
{
    Check(repair.IsReady && repair.Status.State == "repair", "an interrupted same-version transaction remains repairable on reopen");
    File.Delete(marker);
    Check(repair.ScheduleApply(false), "repair can be scheduled after the running application exits");
    wait.Restart();
    while (!File.Exists(marker) && wait.Elapsed < TimeSpan.FromSeconds(10)) await Task.Delay(100);
    using var request = JsonDocument.Parse(File.ReadAllText(marker));
    Check(request.RootElement.GetProperty("source").GetString() == "1.2.0",
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
Console.WriteLine(JsonSerializer.Serialize(new { checks, syntheticOnly = true }));
