using System.Text.Json;
using HwidDesktop;

int checks = 0;
void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
    checks++;
    Console.WriteLine("PASS: " + message);
}
DesktopSnapshot Snapshot(params string[] statuses)
{
    using var json = JsonDocument.Parse(JsonSerializer.Serialize(new
    {
        inventory = new Dictionary<string, object>
        {
            ["Report info"] = new { Version = "3.88" },
            ["Scan timing"] = statuses.Select((status, index) => new { Section = "Synthetic " + index, Status = status, Results = 0 })
        }
    }));
    return new DesktopSnapshot(json.RootElement);
}
Check(Snapshot("READ", "CHECK", "UNAVAILABLE").SectionsRead == 2,
    "A successful read needing ID review counts as read; unavailable data does not");
Check(Snapshot("WAITING", "READING", "Stopped", "", "UNKNOWN", "NOT READ").SectionsRead == 0,
    "Unfinished, stopped and unknown timing states cannot be counted as successful reads");
Check(Snapshot("read", "check", " READ ").SectionsRead == 3,
    "Read coverage tolerates case and padding without treating unknown states as success");
Check(Snapshot().SectionsRead == 0, "An inventory without completed timing rows does not claim read coverage");
var root = Path.Combine(Path.GetTempPath(), "HWID-model-checks-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var file = Path.Combine(root, "battery-only.json");
try
{
    var report = new Dictionary<string, object>
    {
        ["Report info"] = new { Computer = "SYNTHETIC-PC", Version = "3.88", Generated = "2026-11-09T12:00:00Z" },
        ["Battery"] = new[] { new { DeviceID = "BATTERY-00000017", PNPDeviceID = "ACPI\\SYNTHETIC-00017" } }
    };
    await File.WriteAllTextAsync(file, JsonSerializer.Serialize(report));
    var original = await File.ReadAllBytesAsync(file);
    var catalog = await SnapshotStore.ReadAsync(new[] { root });
    Check(catalog.Entries.Count == 1 && catalog.Entries[0].Path == file,
        "A supported battery-only capture is discoverable in the saved snapshot library");
    var afterPreview = await File.ReadAllBytesAsync(file);
    Check(original.SequenceEqual(afterPreview),
        "Catalog preview leaves the saved capture and its exact identifier text unchanged");
    await File.WriteAllTextAsync(file, "{\"Report info\":{\"Version\":\"3.88\"},\"Unknown section\":[]}");
    var invalid = await SnapshotStore.ReadAsync(new[] { root });
    Check(invalid.Entries.Count == 0 && invalid.Skipped == 1,
        "Recognizing battery captures does not admit files with no supported inventory section");
}
finally
{
    if (File.Exists(file)) File.Delete(file);
    Directory.Delete(root);
}
Console.WriteLine($"All {checks} desktop model checks passed. Synthetic identifiers only.");
