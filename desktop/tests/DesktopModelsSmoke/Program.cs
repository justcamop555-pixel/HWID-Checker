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
var stamp = "2026-11-11T14:05:06.1234567+02:00";
var exactId = "000123 \0";
var data = JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object?>
    {
        ["Report info"] = new { Generated = stamp, Administrator = false, Version = "3.89", Display = "Desktop companion", QueryMode = "Live progress", ExtendedStatus = "Refreshed" },
        ["System hardware"] = new[] { new { Manufacturer = "SYNTHETIC", Model = "Readable PC" } },
        ["CPU"] = new[] { new { ProcessorId = exactId, SerialNumber = stamp, Name = "Synthetic CPU" } },
        ["Graphics adapters"] = new { Unavailable = "Synthetic provider denial" },
        ["Extended device inventory"] = new object[] { new { }, new { Unavailable = "Synthetic provider denial" }, new { Name = "Synthetic device" } },
        ["Scan timing"] = new[]
        {
            new { Section = "CPU", Status = "READ", Results = 1 },
            new { Section = " cpu ", Status = "CHECK", Results = 1 },
            new { Section = "", Status = "READ", Results = 1 }
        },
        ["Warnings"] = new[] { "Synthetic warning" }
    },
    identifiers = new[] { new { Section = "CPU", Field = "ProcessorId", Value = exactId, Quality = "Reported", Device = "CPU0" } },
    fieldLabels = new Dictionary<string, object>
    {
        ["Report info"] = new { Generated = "Generated", Administrator = "Administrator", Computer = "Custom PC label" }
    },
    fieldValues = new Dictionary<string, object>
    {
        ["CPU"] = new[] { new { ProcessorId = "decorated identifier", SerialNumber = "decorated timestamp-like identifier" } }
    }
});
var model = new DesktopSnapshot(data);
var originalData = data.GetRawText();
Check(model.Sections.First().Name == "Report info" && model.Sections.First().RawName == "Report info" &&
    model.Sections.First().FriendlyName == "Scan information" && model.Sections.First().CountText == "1 entry",
    "Friendly section names and explicit count units preserve the original lookup key and order");
Check(model.Sections.Single(section => section.Name == "Graphics adapters").Count == 0 &&
    model.Sections.Single(section => section.Name == "Warnings").CountText == "1 message",
    "Unread placeholders do not count as captured hardware and warning counts describe messages");
Check(model.Sections.Single(section => section.Name == "Scan timing").CountText == "3 checks",
    "Read timing counts describe checks rather than devices");
Check(model.SectionsRead == 1, "Repeated successful timing rows and blank section names cannot inflate read coverage");
Check(model.DeviceCount == 1, "Empty and unreadable catalog placeholders cannot inflate the known device count");
Check(model.Label("Report info", "Generated") == "Captured at" && model.Label("Report info", "Administrator") == "Access level",
    "Legacy raw metadata labels fall back to plain language");
Check(model.Label("Report info", "Computer") == "Custom PC label", "An explicit engine display label is preserved");
var reportInfo = model.Info;
var time = model.FieldValue("Report info", 0, "Generated", reportInfo.Get("Generated"));
Check(time != stamp && time.EndsWith("14:05:06 +02:00", StringComparison.Ordinal),
    "Capture timestamps become readable while retaining the reported clock time and offset");
Check(J.Timestamp("unknown") == "unknown" && J.Timestamp("2026-99-99T12:00:00Z") == "2026-99-99T12:00:00Z",
    "Unrecognized or invalid dates remain literal");
Check(model.FieldValue("Report info", 0, "Administrator", reportInfo.Get("Administrator")) == "Standard user",
    "The access-level field explains a false administrator flag");
foreach (var administrator in new[] { false, true })
{
    using var legacyJson = JsonDocument.Parse(JsonSerializer.Serialize(new
    {
        inventory = new Dictionary<string, object> { ["Report info"] = new { Administrator = administrator } },
        fieldValues = new Dictionary<string, object> { ["Report info"] = new[] { new { Administrator = administrator ? "Yes" : "No" } } }
    }));
    var legacy = new DesktopSnapshot(legacyJson.RootElement);
    var raw = legacy.Info.Get("Administrator");
    Check(legacy.FieldValue("Report info", 0, "Administrator", raw) == (administrator ? "Administrator" : "Standard user") &&
        raw.GetBoolean() == administrator,
        "Legacy Yes/No access formatting is replaced by the role while the original boolean remains available");
}
Check(model.FieldValue("Report info", 0, "QueryMode", reportInfo.Get("QueryMode")) == "Live progress available" &&
    model.FieldValue("Report info", 0, "ExtendedStatus", reportInfo.Get("ExtendedStatus")) == "Device list read",
    "Scan metadata describes progress and device-list status without implying hardware health");
var cpu = model.Inventory.Get("CPU").Rows()[0];
Check(model.FieldValue("CPU", 0, "ProcessorId", cpu.Get("ProcessorId")) == exactId &&
    model.FieldValue("CPU", 0, "SerialNumber", cpu.Get("SerialNumber")) == stamp &&
    model.Identifiers[0].Value == exactId,
    "Identifiers keep leading zeroes, whitespace and control padding even when display metadata or date-like text exists");
Check(model.RecordTitle("Report info", reportInfo, 0) == "Snapshot details" &&
    model.RecordTitle("CPU", cpu, 0) == "Synthetic CPU" &&
    model.RecordTitle("Graphics adapters", model.Inventory.Get("Graphics adapters"), 0) == "Read unavailable",
    "Record titles identify metadata, named hardware and read failures clearly");
Check(model.RecordTitle("Other", JsonSerializer.SerializeToElement(false), 0) == "False" &&
    model.RecordTitle("Other", JsonSerializer.SerializeToElement(42), 1) == "42",
    "Scalar records retain descriptive titles that remain searchable");
Check(model.RecordTitle("Memory modules", JsonSerializer.SerializeToElement(new { DeviceLocator = "DIMM_A1", BankLabel = "BANK 0", PartNumber = "SYNTHETIC-RAM" }), 0) == "DIMM_A1" &&
    model.RecordTitle("Memory modules", JsonSerializer.SerializeToElement(new { BankLabel = "BANK 1", PartNumber = "SYNTHETIC-RAM" }), 1) == "BANK 1" &&
    model.RecordTitle("Memory modules", JsonSerializer.SerializeToElement(new { PartNumber = "SYNTHETIC-RAM" }), 2) == "SYNTHETIC-RAM",
    "Memory records retain their slot label with bank and part-number fallbacks");
var formatted = new FieldRow("Captured at", time, stamp);
Check(formatted.RawValue == stamp && new FieldRow("Value", "Original").RawValue == null,
    "Formatted field rows can retain an exact original value without changing older callers");
Check(model.Data.GetRawText() == originalData && model.Inventory.Get("CPU").Rows()[0].Text("ProcessorId") == exactId,
    "Display helpers leave raw JSON and identifier matching keys unchanged");
Check(!DesktopSnapshot.SectionDescription("Extended device inventory").Contains("every", StringComparison.OrdinalIgnoreCase),
    "Device scope text describes returned Windows records without claiming complete PC coverage");
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
