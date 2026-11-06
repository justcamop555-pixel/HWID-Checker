using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace HwidDesktop;

internal static class J
{
    public static JsonElement Get(this JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object) return default;
        if (value.TryGetProperty(name, out var direct)) return direct;
        foreach (var property in value.EnumerateObject())
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase)) return property.Value;
        return default;
    }
    public static string Text(this JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => value.GetString() ?? "",
        JsonValueKind.Number => value.GetRawText(),
        JsonValueKind.True => "True", JsonValueKind.False => "False",
        JsonValueKind.Null or JsonValueKind.Undefined => "",
        _ => value.GetRawText()
    };
    public static string Text(this JsonElement value, string name) => value.Get(name).Text();
    public static int Number(this JsonElement value, string name) => int.TryParse(value.Get(name).Text(), out var number) ? number : 0;
    public static bool Flag(this JsonElement value, string name) => value.Get(name).ValueKind == JsonValueKind.True;
    public static JsonElement[] Rows(this JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Array => value.EnumerateArray().ToArray(),
        JsonValueKind.Null or JsonValueKind.Undefined => [], _ => [value]
    };
    public static string Display(this JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Array) return string.Join(Environment.NewLine, value.EnumerateArray().Select(Display));
        if (value.ValueKind == JsonValueKind.Object) return JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true });
        var text = value.Text();
        return string.IsNullOrWhiteSpace(text) ? "(not supplied)" : text.Replace("\0", "");
    }
    public static string Humanize(string name) => name switch
    {
        "ProcessorId" => "CPU identifier", "UUID" => "System UUID", "MachineGuid" => "Windows installation ID",
        "PNPDeviceID" => "Windows device ID", "DeviceInstanceId" => "Device instance ID",
        _ => Regex.Replace(name.Replace('_', ' '), "(?<=[a-z0-9])(?=[A-Z])", " ")
    };
    public static string Date(string input) => DateTimeOffset.TryParse(input, CultureInfo.InvariantCulture,
        DateTimeStyles.AllowWhiteSpaces, out var date) ? date.ToLocalTime().ToString("MMM d, yyyy  HH:mm") : input;
}

public sealed record ScanRow(string Name, string Status, string Records, string Detail, string Time);
internal sealed record IdentifierRow(string Section, string Field, string Value, string Status, string Device);
internal sealed record FieldRow(string Field, string Value);
internal sealed record ReviewRow(string Kind, string Section, string Message, string Detail);
internal sealed record ChangeRow(string Kind, string Label, string Previous, string Current, string Detail);
internal sealed record HardwareSection(string Name, int Count) { public string Display => Name + "  ·  " + Count; }
internal sealed record HardwareRecord(string Title, JsonElement Data, int Index);
internal sealed record SnapshotEntry(string Path, string Name, string Computer, string Captured, string Version, string Size, DateTimeOffset SortTime);
internal sealed record SnapshotCatalog(IReadOnlyList<SnapshotEntry> Entries, int Skipped, string[] Folders);

internal sealed class DesktopSnapshot
{
    public JsonElement Data { get; }
    public JsonElement Inventory => Data.Get("inventory");
    public JsonElement Info => Inventory.Get("Report info");
    public List<IdentifierRow> Identifiers { get; } = [];
    public List<ReviewRow> Findings { get; } = [];
    public List<ScanRow> Timing { get; } = [];
    public string Version => Data.Text("version");
    public int ReportedIds => Identifiers.Count(x => x.Status == "Reported");
    public int SectionsRead => Timing.Count(x => x.Status != "NOT READ");
    public int DeviceCount => Inventory.Get("Extended device inventory").Rows().Length;

    public DesktopSnapshot(JsonElement data)
    {
        if (data.Get("inventory").ValueKind != JsonValueKind.Object) throw new InvalidDataException("The scanner returned no inventory.");
        Data = data.Clone();
        foreach (var row in Data.Get("identifiers").Rows())
        {
            var section = row.Text("Section"); var rawField = row.Text("Field");
            var quality = row.Text("Quality");
            Identifiers.Add(new(section, Label(section, rawField), row.Text("Value"), quality == "Placeholder" ? "Default" : quality, row.Text("Device")));
        }
        foreach (var row in Inventory.Get("Scan timing").Rows())
        {
            var status = row.Text("Status");
            Timing.Add(new(row.Text("Section"), status == "UNAVAILABLE" ? "NOT READ" : status,
                row.Text("Results"), row.Text("Summary"), row.Text("Seconds") + " s"));
        }
        var review = Data.Get("review");
        foreach (var row in review.Get("UnreadDetails").Rows())
            Findings.Add(new("Read error", row.Text("Section"), row.Text("Reason") + " · " + row.Text("Code"),
                row.Text("Message") + "\n\nNext step: " + row.Text("Action")));
        foreach (var row in review.Get("IdIssues").Rows())
        {
            var section = row.Text("Section"); var field = Label(section, row.Text("Field"));
            Findings.Add(new("ID review", section, field + " · " + (row.Text("Quality") == "Placeholder" ? "default value" : "not supplied"),
                "Device: " + row.Text("Device") + "\nField: " + field + "\nValue: " + row.Get("Value").Display() +
                "\n\nA missing or generic identifier can be normal for this component. The full inventory retains the Windows-reported value."));
        }
        foreach (var key in new[] { "DeviceIssues", "PnpConflicts", "DiskClashes", "RecordConflicts" })
            foreach (var row in review.Get(key).Rows())
            {
                var message = row.Text("Message");
                if (string.IsNullOrEmpty(message)) message = key switch { "DiskClashes" => "Storage identifier readings disagree", "RecordConflicts" => "Duplicate device keys need review", _ => "Device detail needs review" };
                var source = row.Text("Section");
                if (source.Length == 0) source = row.Text("Device");
                if (source.Length == 0) source = key == "DiskClashes" ? "Storage" : "Device records";
                Findings.Add(new(key is "PnpConflicts" or "DiskClashes" or "RecordConflicts" ? "Conflict" : "Device status", source, message, row.Display()));
            }
        foreach (var row in Inventory.Get("Extended device inventory").Rows().Where(x => x.Flag("ParentInstanceIdConflict")))
            Findings.Add(new("Parent link", row.Text("Name"), "Parent-device readings disagree", "Instance: " + row.Text("DeviceInstanceId") +
                "\n\nObserved parents:\n" + row.Get("ParentInstanceIdReadings").Display() + "\n\nThe relationship is unresolved. Core device identifiers remain available."));
    }
    public string Label(string section, string field)
    {
        var label = Data.Get("fieldLabels").Get(section).Text(field);
        return label.Length > 0 ? label : J.Humanize(field);
    }
    public string FieldValue(string section, int recordIndex, string field, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Array or JsonValueKind.Object) return value.Display();
        var records = Data.Get("fieldValues").Get(section).Rows();
        var display = recordIndex < records.Length ? records[recordIndex].Text(field) : "";
        return string.IsNullOrWhiteSpace(display) ? value.Display() : display;
    }
    public string First(string section, string field) => Inventory.Get(section).Rows().FirstOrDefault().Text(field);
}

internal static class SnapshotStore
{
    public static Task<SnapshotCatalog> ReadAsync(IEnumerable<string> directories) => Task.Run(() =>
    {
        var entries = new List<SnapshotEntry>(); var skipped = 0;
        var folders = directories.Where(x => !string.IsNullOrWhiteSpace(x)).Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var folder in folders)
        {
            if (!Directory.Exists(folder)) continue;
            string[] files;
            try { files = Directory.GetFiles(folder, "*.json", SearchOption.TopDirectoryOnly); }
            catch (IOException) { skipped++; continue; } catch (UnauthorizedAccessException) { skipped++; continue; }
            foreach (var file in files)
            {
                if (!seen.Add(file)) continue;
                try
                {
                    var info = new FileInfo(file);
                    if (info.Length > 25 * 1024 * 1024) { skipped++; continue; }
                    using var doc = JsonDocument.Parse(File.ReadAllText(file), new JsonDocumentOptions { MaxDepth = 64 });
                    var report = doc.RootElement.Get("Report info");
                    if (report.ValueKind != JsonValueKind.Object || string.IsNullOrWhiteSpace(report.Text("Computer")) || !DateTimeOffset.TryParse(report.Text("Generated"), CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var time)) { skipped++; continue; }
                    entries.Add(new(file, info.Name, report.Text("Computer"), J.Date(report.Text("Generated")), report.Text("Version"),
                        info.Length < 1024 * 1024 ? $"{info.Length / 1024d:0.#} KB" : $"{info.Length / (1024d * 1024):0.#} MB", time));
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { skipped++; }
            }
        }
        return new SnapshotCatalog(entries.OrderByDescending(x => x.SortTime).ToArray(), skipped, folders);
    });
}
