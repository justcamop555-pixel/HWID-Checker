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
        ["Extended device inventory"] = new object[] { new { }, new { Unavailable = "Synthetic provider denial" }, new { Name = "Synthetic device", DeviceInstanceId = "SYNTHETIC\\000123" } },
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
    using var cancelledCatalog = new CancellationTokenSource();
    cancelledCatalog.Cancel();
    try { await SnapshotStore.ReadAsync(new[] { root }, cancelledCatalog.Token); Check(false, "A cancelled catalog must not publish a partial list"); }
    catch (OperationCanceledException) { Check(true, "A cancelled catalog stops without publishing a partial list"); }
    using var midCatalog = new CancellationTokenSource();
    IEnumerable<string> FoldersCancelledDuringEnumeration()
    {
        yield return root;
        midCatalog.Cancel();
        yield return root;
    }
    try { await SnapshotStore.ReadAsync(FoldersCancelledDuringEnumeration(), midCatalog.Token); Check(false, "Cancellation must be observed during folder enumeration"); }
    catch (OperationCanceledException) { Check(true, "Cancellation during folder enumeration stops the catalog before file reads"); }
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
var older = Snapshot("READ", "CHECK", "NOT READ");
Check(older.SectionsChecked == 3 && older.SectionsRead == 2 && !older.AllSectionsRead && older.CoverageText == "2 of 3 sections read",
    "Coverage uses the recorded section count rather than assuming the newest scanner schema");
Check(Snapshot().SectionsChecked == 0 && !Snapshot().AllSectionsRead && Snapshot().CoverageText.Contains("not recorded"),
    "Missing timing does not become zero of eighteen failed sections");
Check(Snapshot("READ", "CHECK").AllSectionsRead && Snapshot("READ").CatalogRow.Status == "NOT SCANNED",
    "An older capture without a device catalog is distinguished from a failed catalog read");
Check(model.SectionsChecked == 1 && model.CatalogRow.Status == "READ" && model.CatalogRow.Records == "1",
    "Duplicate timing rows cannot inflate the checked count and catalog counts exclude placeholders");
foreach (var conflictingStatus in new[] { "NOT READ", "UNAVAILABLE", "WAITING", "READING", "UNKNOWN", "" })
{
    var mixed = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
    {
        inventory = new Dictionary<string, object>
        {
            ["Scan timing"] = new[] { new { Section = "CPU", Status = "READ" }, new { Section = " cpu ", Status = conflictingStatus },
                new { Section = "BIOS", Status = "CHECK" } }
        }
    }));
    Check(mixed.SectionsChecked == 2 && mixed.SectionsRead == 1 && !mixed.AllSectionsRead,
        "A contradictory or unfinished duplicate cannot hide behind an earlier successful section read: " + conflictingStatus);
}
Check(model.SectionsRead == 1 && model.AllSectionsRead,
    "Consistent successful duplicates remain one readable section in older captures");
DesktopSnapshot CatalogMetadata(object? metadata, bool include = true)
{
    var inventory = new Dictionary<string, object?>
    {
        ["Report info"] = new { ExtendedStatus = "Refreshed" },
        ["Extended device inventory"] = new[] { new { DeviceInstanceId = "SYNTHETIC\\000123" } }
    };
    if (include) inventory["Extended scan info"] = metadata;
    return new DesktopSnapshot(JsonSerializer.SerializeToElement(new { inventory }));
}
foreach (var metadata in new object[] { new { Error = "Synthetic failed refresh" }, new { Unavailable = "Synthetic unavailable" },
    new { Error = true }, new { Unavailable = true } })
    Check(CatalogMetadata(metadata).CatalogRow.Status == "NOT READ",
        "Explicit catalog failure takes precedence over a contradictory Refreshed header");
foreach (var metadata in new object?[] { null, new { }, new { Error = false, Unavailable = false },
    new { Error = " \t ", Unavailable = "" } })
    Check(CatalogMetadata(metadata).CatalogRow.Status == "READ",
        "Null, empty or non-failure catalog metadata does not invent a failed refresh");
Check(CatalogMetadata(null, include: false).CatalogRow.Status == "READ",
    "An older Refreshed capture can omit extended metadata without manufacturing a failure");
foreach (var metadata in new object[] { "Malformed metadata", 42, new[] { "Malformed list" }, new { Error = new[] { "Malformed error" } } })
{
    var malformedCatalog = CatalogMetadata(metadata);
    Check(malformedCatalog.CatalogRow.Status == "UNKNOWN" && malformedCatalog.DeviceCount == 1 &&
        malformedCatalog.Inventory.Get("Extended device inventory").Rows()[0].Text("DeviceInstanceId") == "SYNTHETIC\\000123",
        "Malformed catalog metadata stays unknown without discarding captured identifiers");
}
foreach (var status in new[] { "Unavailable", "unavailable", " Unavailable " })
{
    var failed = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
    {
        inventory = new Dictionary<string, object>
        {
            ["Report info"] = new { ExtendedStatus = status },
            ["Extended device inventory"] = new[] { new { Name = "Saved device" } }
        }
    }));
    Check(failed.CatalogRow.Status == "NOT READ" && failed.CatalogRow.Records == "Not read",
        "A failed catalog refresh does not present retained records as newly read");
}
var unverified = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object> { ["Extended device inventory"] = new[] { new { Name = "Legacy device" } } }
}));
Check(unverified.CatalogRow.Status == "UNKNOWN" && unverified.DeviceCount == 1,
    "Catalog records without original read metadata are available without a fabricated success or failure");

var exports = Path.Combine(Path.GetTempPath(), "HWID-export-checks-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(exports);
var previousFile = Path.Combine(exports, "comparison.txt");
var csv = Path.Combine(exports, "report.csv");
var html = Path.Combine(exports, "report.html");
try
{
    await ReportFiles.WriteTextAsync(previousFile, "Previous comparison");
    using (var locked = new FileStream(previousFile, FileMode.Open, FileAccess.Read, FileShare.None))
    {
        var rejected = false;
        try { await ReportFiles.WriteTextAsync(previousFile, "Replacement comparison"); }
        catch (IOException) { rejected = true; }
        Check(rejected, "A locked comparison file rejects replacement");
    }
    Check(await File.ReadAllTextAsync(previousFile) == "Previous comparison" && Directory.GetFiles(exports, "*.pending").Length == 0,
        "A failed comparison export preserves the existing report and cleans its temporary file");
    await ReportFiles.WriteTextAsync(previousFile, "New comparison · 000123\r\n");
    Check(await File.ReadAllTextAsync(previousFile) == "New comparison · 000123\r\n",
        "A successful comparison replacement retains exact Unicode and identifier text");
    Directory.CreateDirectory(html);
    var pairRejected = false;
    try { ReportFiles.WriteNewPair(csv, "000123", html, "<html>000123</html>"); }
    catch (IOException) { pairRejected = true; }
    Check(pairRejected && !File.Exists(csv) && Directory.Exists(html),
        "A blocked HTML destination does not leave a partial CSV export or replace the blocker");
    Directory.Delete(html);
    ReportFiles.WriteNewPair(csv, "\"Value\"\r\n\"000123\"\r\n", html, "<html>000123 · 合成</html>");
    Check(await File.ReadAllTextAsync(csv) == "\"Value\"\r\n\"000123\"\r\n" && (await File.ReadAllTextAsync(html)).Contains("合成"),
        "CSV and HTML are both published with the original text");
    pairRejected = false;
    try { ReportFiles.WriteNewPair(csv, "Overwrite", html, "Overwrite"); }
    catch (IOException) { pairRejected = true; }
    Check(pairRejected && (await File.ReadAllTextAsync(csv)).Contains("000123") && Directory.GetFiles(exports, "*.pending").Length == 0,
        "Pair collisions preserve existing exports and leave no pending files");
}
finally
{
    foreach (var item in Directory.GetFiles(exports)) File.Delete(item);
    if (Directory.Exists(html)) Directory.Delete(html);
    Directory.Delete(exports);
}
var searchable = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object> { ["Report info"] = new { Computer = "SYNTHETIC" } },
    identifiers = new[]
    {
        new { Section="Memory modules", Field="SerialNumber", Value="000123", Quality="Reported", Device="DIMM_A1 Ω" },
        new { Section="Network adapters", Field="MacAddress", Value="00-01-02-03-04-05", Quality="Placeholder", Device="NIC0" },
        new { Section="CPU", Field="ProcessorId", Value="", Quality="Missing", Device="CPU0" }
    },
    review = new { UnreadDetails = new[] { new { Section="CPU", Reason="Read denied", Code="TEST", Message="Synthetic Ω error", Action="Retry" } } }
}));
foreach (var query in new[] { "", "000123", "dimm", "reported", "Default", "Missing", "Ω", "000123 DIMM_A1", "not-present" })
{
    foreach (var filter in new[] { 0, 1, 2 })
    {
        var expected = searchable.Identifiers.Where(row =>
            (filter != 1 || row.Status == "Reported") && (filter != 2 || row.Status is "Missing" or "Default") &&
            (query.Length == 0 || string.Join(" ", row.Section, row.Field, row.Value, row.Device, row.Status).Contains(query, StringComparison.OrdinalIgnoreCase)));
        Check(searchable.FindIdentifiers(query, filter).SequenceEqual(expected),
            "Indexed ID search retains exact field/device/status matching for query " + query + " / filter " + filter);
    }
    Check(searchable.FindReview(query).SequenceEqual(searchable.Findings.Where(row =>
        query.Length == 0 || string.Join(" ", row.Kind, row.Section, row.Message, row.Detail).Contains(query, StringComparison.OrdinalIgnoreCase))),
        "Indexed review search retains the original matching semantics for " + query);
}
Check(ReferenceEquals(searchable.FindIdentifiers(""), searchable.Identifiers) && ReferenceEquals(searchable.FindReview(""), searchable.Findings),
    "Clearing a search reuses the immutable snapshot rows without rebuilding a full list");
Check(((IList<IdentifierRow>)searchable.Identifiers).IsReadOnly && ((IList<ReviewRow>)searchable.Findings).IsReadOnly,
    "Published snapshot row collections cannot invalidate the search index");
var replacementSearch = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object>(),
    identifiers = new[] { new { Section="CPU", Field="ProcessorId", Value="NEW-SYNTHETIC-ID", Quality="Reported", Device="CPU0" } }
}));
Check(replacementSearch.FindIdentifiers("000123").Count == 0 && replacementSearch.FindIdentifiers("NEW-SYNTHETIC-ID").Count == 1 &&
    searchable.FindIdentifiers("000123").Count == 1, "New scans replace their search data without changing the earlier capture");
var hardwareSearch = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object>
    {
        ["PnP hardware IDs"] = new object?[] { null, new { Name="WiFi Synthetic", InstanceId="PCI\\SYNTHETIC-001", Nested=new { Values=new object?[] { "001234", true, 54321, null } } },
            new { FriendlyName="Storage Synthetic", HiddenValue="EXACT-HIDDEN-0099" }, "Scalar record" },
        ["CPU"] = new[] { new { Name="Synthetic CPU", SerialNumber="000001" } }
    }
}));
bool ValueContains(JsonElement value, string needle) => value.ValueKind switch
{
    JsonValueKind.Object => value.EnumerateObject().Any(field => ValueContains(field.Value, needle)),
    JsonValueKind.Array => value.EnumerateArray().Any(item => ValueContains(item, needle)),
    _ => value.Text().Contains(needle, StringComparison.OrdinalIgnoreCase)
};
foreach (var section in new[] { "PnP hardware IDs", "CPU", "Missing section" })
foreach (var query in new[] { "", "wifi", "001234", "true", "54321", "hidden-0099", "scalar", "not-present", "000001" })
{
    var expected = hardwareSearch.Inventory.Get(section).Rows().Select((value,index)=>(value,index))
        .Where(entry => entry.value.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) &&
            (query.Length == 0 || hardwareSearch.RecordTitle(section, entry.value, entry.index).Contains(query, StringComparison.OrdinalIgnoreCase) || ValueContains(entry.value, query)))
        .Select(entry=>entry.index);
    Check(hardwareSearch.FindHardwareRecords(section, query).Select(row=>row.Index).SequenceEqual(expected),
        "Hardware index preserves recursive value, title and original record-index search: " + section + " / " + query);
}
Check(ReferenceEquals(hardwareSearch.FindHardwareRecords("PnP hardware IDs", ""), hardwareSearch.FindHardwareRecords("PnP hardware IDs", "")) &&
    ((IList<HardwareRecord>)hardwareSearch.FindHardwareRecords("PnP hardware IDs", "")).IsReadOnly,
    "Clearing hardware search reuses immutable record rows");
var overflowSearch = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object>
    {
        ["Extended device inventory"] = new[] { new { Name="Synthetic large record", Blob=new string('x',1_048_580)+"EXACT-TAIL-0098" } },
        ["PnP hardware IDs"] = new[] { new { Name="Synthetic many values", Values=Enumerable.Range(0,20_000).Select(i=>"leaf-"+i).ToArray() } }
    }
}));
Check(overflowSearch.CachedHardwareCharacters <= 1_048_576 && overflowSearch.FindHardwareRecords("Extended device inventory", "EXACT-TAIL-0098").Count == 1 &&
    overflowSearch.FindHardwareRecords("PnP hardware IDs", "leaf-19999").Count == 1,
    "Hardware values beyond the bounded cache remain searchable without truncating large fields or late array values");
Check(hardwareSearch.FindHardwareRecords("PnP hardware IDs", "leaf-19999").Count == 0 &&
    hardwareSearch.FindHardwareRecords("PnP hardware IDs", "EXACT-HIDDEN-0099").Count == 1,
    "Hardware search data stays isolated between captures");
var searchChange = new ChangeRow("Changed", "CPU / Serial number", "000001", "000009", "Device: synthetic CPU\nExact change: 1 -> 9");
var searchCapture = new SnapshotEntry(@"C:\Synthetic folder\snapshot.json", "snapshot.json", "HOME-PC", "Nov 12, 2026", "3.91", "1 KB", DateTimeOffset.UnixEpoch);
foreach(var query in new[] { "", "cpu", "000001", "000009", "synthetic", "number 000001", "000001 000009", "Changed CPU", "missing", "snapshot.json HOME-PC", "HOME-PC Nov", "Nov 12", "folder", "3.91" })
{
    Check(searchChange.MatchesSearch(query) == string.Join(" ", searchChange.Kind, searchChange.Label, searchChange.Previous, searchChange.Current, searchChange.Detail).Contains(query,StringComparison.OrdinalIgnoreCase),
        "Comparison search preserves exact values and cross-field phrase matches: " + query);
    Check(searchCapture.MatchesSearch(query) == string.Join(" ", searchCapture.Name, searchCapture.Computer, searchCapture.Captured, searchCapture.Path, searchCapture.Version).Contains(query,StringComparison.OrdinalIgnoreCase),
        "Snapshot search preserves path/date/version and cross-field phrase matches: " + query);
}
using (var overrides = JsonDocument.Parse("""{"inventory":{"CPU":[{"Name":"raw"}]},"fieldValues":{"CPU":[{"Name":"first"},{"Name":"second"}]}}"""))
{
    var display = new DesktopSnapshot(overrides.RootElement);
    var raw = display.Inventory.Get("CPU")[0].Get("Name");
    Check(display.FieldValue("CPU", 1, "Name", raw) == "second", "display values retain the original array record index");
    Check(display.FieldValue("CPU", -1, "Name", raw) == "raw" && display.FieldValue("CPU", 2, "Name", raw) == "raw",
        "out-of-range display indexes fall back to the exact raw value");
}
using (var scalarOverrides = JsonDocument.Parse("""{"inventory":{"CPU":[{"Name":"raw"}]},"fieldValues":{"CPU":{"Name":"single"}}}"""))
{
    var display = new DesktopSnapshot(scalarOverrides.RootElement);
    var raw = display.Inventory.Get("CPU")[0].Get("Name");
    Check(display.FieldValue("CPU", 0, "Name", raw) == "single" && display.FieldValue("CPU", 1, "Name", raw) == "raw",
        "single-record display values preserve the prior scalar-object behavior");
}
using (var availability = JsonDocument.Parse("""{"inventory":{"Report info":{"Version":"3.97"},"Monitors":[{"RecordKind":"Collection status","IdentificationRecords":0,"IdentificationStatus":"No identification records reported","Scope":"Physical display count undetermined"}],"Windows":[{"Caption":"Synthetic Windows","SecureBoot":null,"SecureBootReadStatus":"Access blocked","SecureBootReadCode":"READ-01","TPM":null,"TPMReadStatus":"Not reported"}]},"identifiers":[],"review":{}}"""))
{
    var available = new DesktopSnapshot(availability.RootElement);
    var status = available.FindHardwareRecords("Monitors", "").Single();
    Check(available.RecordTitle("Monitors", status.Data, status.Index) == "Monitor identification status - 0 identification records",
        "a zero-identification status is a readable collection result rather than an invented physical monitor");
    Check(available.Identifiers.Count == 0 && available.Findings.Count == 0 && status.Data.Number("IdentificationRecords") == 0,
        "monitor availability metadata does not invent serials, missing-ID findings or physical display counts");
    Check(available.Label("Windows", "SecureBootReadStatus") == "Secure Boot read status" &&
        available.Label("Windows", "TPMReadCode") == "TPM read code" && available.Inventory.Get("Windows").Rows()[0].Get("SecureBoot").ValueKind == JsonValueKind.Null,
        "optional firmware diagnostics keep readable labels and an unknown value instead of a false disabled state");
}
DesktopSnapshot CoverageCapture(string? key = null, bool suppliedReview = false)
{
    var info = new Dictionary<string, object> { ["PropertyNodesRequested"] = 1, ["PropertyNodesReturned"] = 1,
        ["PropertyNodesWithoutRows"] = 0, ["PropertyReadErrors"] = 3 };
    if (key != null) info[key] = 1;
    return new DesktopSnapshot(JsonSerializer.SerializeToElement(new
    {
        inventory = new Dictionary<string, object>
        {
            ["Report info"] = new { ExtendedStatus = "Refreshed" }, ["Extended scan info"] = info,
            ["Extended device inventory"] = new[] { new { DeviceInstanceId = "SYNTHETIC\\000123", HardwareID = new[] { "MODEL-000123" } } }
        },
        identifiers = new[] { new { Section = "CPU", Field = "ProcessorId", Value = "000123", Quality = "Reported" } },
        review = new { CoverageIssues = suppliedReview ? new[] { new { Section = "Extended device inventory", Message = "Additional identification incomplete", Details = "Synthetic property coverage", Action = "Inspect metadata" } } : [] }
    }));
}
foreach (var key in new[] { "PropertyNodesWithoutRows", "PropertyBlockingErrors", "MissingInstanceIds", "InvalidPropertyRows", "IdSourceConflicts", "IdPropertyConflicts", "ContainerIdConflicts" })
{
    var coverage = CoverageCapture(key);
    Check(coverage.CatalogRow.Status == "CHECK" && coverage.CatalogRow.Records == "1" &&
        coverage.Findings.Count(row => row.Kind == "Scan coverage") == 1 && coverage.Identifiers[0].Value == "000123",
        key + " keeps readable records/exact IDs while exposing identification coverage instead of plain success");
}
Check(CoverageCapture().CatalogRow.Status == "READ" && CoverageCapture().Findings.Count == 0,
    "generic optional-property errors alone do not invent a fault when every node returned properties");
Check(CoverageCapture("PropertyNodesWithoutRows", true).Findings.Count(row => row.Kind == "Scan coverage") == 1,
    "engine-supplied catalog coverage is not duplicated by legacy metadata fallback");
Check(CoverageCapture().Identifiers[0].Value == CoverageCapture("PropertyNodesWithoutRows").Identifiers[0].Value,
    "healthy replacement coverage clears the qualifier without rewriting accepted identifiers");
foreach (var alias in new[] { "DeviceInstanceId", "PNPDeviceID", "InstanceId", "DeviceID" })
{
    var legacy = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
    {
        inventory = new Dictionary<string, object> { ["Report info"] = new { ExtendedStatus = "Refreshed" },
            ["Extended device inventory"] = new[] { new Dictionary<string, object> { ["Name"] = "Legacy node", [alias] = "SYNTHETIC\\000123" } } }
    }));
    Check(legacy.CatalogRow.Status == "READ", "legacy " + alias + " counts as a supplied instance key without new coverage counters");
}
var noInstance = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
{
    inventory = new Dictionary<string, object> { ["Report info"] = new { ExtendedStatus = "Refreshed" },
        ["Extended device inventory"] = new[] { new { Name = "Legacy named node", DeviceInstanceId = " \0 " } } }
}));
Check(noInstance.DeviceCount == 1 && noInstance.CatalogRow.Status == "CHECK" && noInstance.Findings.Single().Kind == "Scan coverage",
    "legacy named records without usable instance keys remain available but cannot imply full identification");
Console.WriteLine($"All {checks} desktop model, search and export checks passed. Synthetic identifiers only.");
if (args.Contains("--benchmark-fields"))
{
    var report = JsonSerializer.SerializeToElement(new
    {
        inventory = new { CPU = new[] { new { Name = "raw" } } },
        fieldValues = new { CPU = Enumerable.Range(0, 3000).Select(i => new { Name = "display-" + i }).ToArray() }
    });
    var display = new DesktopSnapshot(report);
    var raw = report.Get("inventory").Get("CPU")[0].Get("Name");
    string Legacy(int index) => report.Get("fieldValues").Get("CPU").Rows()[index].Text("Name");
    _ = display.FieldValue("CPU", 2999, "Name", raw); _ = Legacy(2999);
    var allocated = GC.GetAllocatedBytesForCurrentThread();
    var clock = System.Diagnostics.Stopwatch.StartNew();
    var length = 0;
    for (var i = 0; i < 1000; i++) length += display.FieldValue("CPU", 2999, "Name", raw).Length;
    var directBytes = GC.GetAllocatedBytesForCurrentThread() - allocated;
    var directMs = clock.Elapsed.TotalMilliseconds;
    allocated = GC.GetAllocatedBytesForCurrentThread(); clock.Restart();
    var legacyLength = 0;
    for (var i = 0; i < 1000; i++) legacyLength += Legacy(2999).Length;
    var legacyBytes = GC.GetAllocatedBytesForCurrentThread() - allocated;
    var legacyMs = clock.Elapsed.TotalMilliseconds;
    if (length != legacyLength) throw new Exception("The field benchmark changed display values.");
    Console.WriteLine(JsonSerializer.Serialize(new { scenario = "3000 display records / 1000 field lookups", directBytes, legacyBytes, directMs, legacyMs,
        exactOutputMatched = true, syntheticOnly = true }));
}
if (args.Contains("--benchmark-hardware"))
{
    var large = new DesktopSnapshot(JsonSerializer.SerializeToElement(new
    {
        inventory = new Dictionary<string, object>
        {
            ["PnP hardware IDs"] = Enumerable.Range(0,2_000).Select(i=>new { Name="Synthetic device "+i, DeviceID="PCI\\SYNTHETIC-"+i,
                Properties=new { SerialNumber="SERIAL-"+i.ToString("D8"), Values=new[] {"Driver value "+i,"Exact value "+i} } }).ToArray()
        }
    }));
    var queries = new[] { "SERIAL-00001999", "pci", "missing-device", "Exact value 103", "device 51" };
    foreach (var query in queries) { _ = large.FindHardwareRecords("PnP hardware IDs", query); }
    long indexedTotal=0, recursiveTotal=0;
    var bytes=GC.GetAllocatedBytesForCurrentThread();var watch=System.Diagnostics.Stopwatch.StartNew();
    for(var pass=0;pass<10;pass++) foreach(var query in queries) indexedTotal+=large.FindHardwareRecords("PnP hardware IDs",query).Count;
    var indexedMs=watch.ElapsedMilliseconds;var indexedBytes=GC.GetAllocatedBytesForCurrentThread()-bytes;
    bytes=GC.GetAllocatedBytesForCurrentThread();watch.Restart();
    for(var pass=0;pass<10;pass++) foreach(var query in queries)
        recursiveTotal+=large.Inventory.Get("PnP hardware IDs").Rows().Select((value,index)=>(value,index)).Count(entry=>
            large.RecordTitle("PnP hardware IDs",entry.value,entry.index).Contains(query,StringComparison.OrdinalIgnoreCase)||ValueContains(entry.value,query));
    var recursiveMs=watch.ElapsedMilliseconds;var recursiveBytes=GC.GetAllocatedBytesForCurrentThread()-bytes;
    if(indexedTotal!=recursiveTotal)throw new Exception("The hardware benchmark found different search results.");
    Console.WriteLine($"Synthetic hardware benchmark: 2000 records / 50 searches / indexed {indexedMs}ms and {indexedBytes} bytes / recursive {recursiveMs}ms and {recursiveBytes} bytes. No timing threshold enforced.");
}
