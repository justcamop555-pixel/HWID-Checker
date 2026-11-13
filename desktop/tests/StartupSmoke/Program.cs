using System.Text;
using HwidDesktop;

var folder = Path.Combine(Path.GetTempPath(), "HWID-startup-settings-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(folder);
var file = Path.Combine(folder, "settings.json");
var checks = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception(name); checks++; Console.WriteLine("PASS: " + name); }
try
{
    foreach (var content in new[] { "", "broken json", "[]", "null", new string(' ', 262145) })
    {
        await File.WriteAllTextAsync(file, content);
        var result = await StartupPreparation.ReadPreferencesAsync(file, CancellationToken.None);
        Check(result.EnumerateObject().Count() == 0, "invalid or oversized settings use defaults without blocking startup");
    }
    Check((await StartupPreparation.ReadPreferencesAsync(Path.Combine(folder, "missing"), CancellationToken.None)).EnumerateObject().Count() == 0,
        "missing first-launch settings use defaults");
    Check((await StartupPreparation.ReadPreferencesAsync(null, CancellationToken.None)).EnumerateObject().Count() == 0,
        "isolated startup verification needs no user preferences");
    const string json = "{\"darkTheme\":false,\"welcomeSeen\":true,\"batPath\":\"SYNTHETIC\",\"snapshotFolders\":[\"SYNTHETIC-FOLDER\"]}";
    foreach (var encoding in new Encoding[] { new UTF8Encoding(false), new UTF8Encoding(true), Encoding.Unicode })
    {
        await File.WriteAllTextAsync(file, json, encoding);
        var before = await File.ReadAllBytesAsync(file);
        var result = await StartupPreparation.ReadPreferencesAsync(file, CancellationToken.None);
        Check(!result.GetProperty("darkTheme").GetBoolean() && result.GetProperty("welcomeSeen").GetBoolean() &&
            result.GetProperty("batPath").GetString() == "SYNTHETIC" && result.GetProperty("snapshotFolders")[0].GetString() == "SYNTHETIC-FOLDER",
            "background settings preserve exact values with " + encoding.WebName + " and BOM=" + (encoding.GetPreamble().Length > 0));
        var after = await File.ReadAllBytesAsync(file);
        Check(before.SequenceEqual(after), "reading preferences never rewrites the source settings");
    }
    using var cancel = new CancellationTokenSource(); cancel.Cancel();
    try { await StartupPreparation.ReadPreferencesAsync(file, cancel.Token); Check(false, "cancellation must stop preference preparation"); }
    catch (OperationCanceledException) { Check(true, "closing before preference preparation cancels without publishing settings"); }
    using (var locked = File.Open(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        Check((await StartupPreparation.ReadPreferencesAsync(file, CancellationToken.None)).EnumerateObject().Count() == 0,
            "a locked settings file falls back without a startup crash");
    Console.WriteLine($"All {checks} startup preference checks passed. Synthetic data only.");
}
finally { if (File.Exists(file)) File.Delete(file); Directory.Delete(folder); }
