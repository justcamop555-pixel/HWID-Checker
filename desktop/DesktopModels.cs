using System.Globalization;
using System.IO;
using System.Text;
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
    public int SectionsRead => Timing.Count(x =>
        x.Status.Trim().Equals("READ", StringComparison.OrdinalIgnoreCase) ||
        x.Status.Trim().Equals("CHECK", StringComparison.OrdinalIgnoreCase));
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
    private const int MaximumReportBytes = 64 * 1024 * 1024;
    private static readonly JsonDocumentOptions ReportJsonOptions = new() { MaxDepth = 128 };
    private static readonly Regex SupportedVersion = new(@"^[23]\.\d+(?:\.\d+)?$", RegexOptions.CultureInvariant);
    private static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: true, throwOnInvalidBytes: true);
    private static readonly Encoding[] WideEncodings =
    [
        new UTF32Encoding(bigEndian: false, byteOrderMark: true, throwOnInvalidCharacters: true),
        new UTF32Encoding(bigEndian: true, byteOrderMark: true, throwOnInvalidCharacters: true),
        new UnicodeEncoding(bigEndian: false, byteOrderMark: true, throwOnInvalidBytes: true),
        new UnicodeEncoding(bigEndian: true, byteOrderMark: true, throwOnInvalidBytes: true)
    ];
    private static readonly HashSet<string> HardwareSections = new(StringComparer.OrdinalIgnoreCase)
    {
        "System identity", "System hardware", "Motherboard", "BIOS", "Chassis", "CPU", "Memory modules",
        "Physical disks", "Storage identifiers", "Volumes", "Disk partitions", "Graphics adapters",
        "Network adapters", "Monitors", "Battery", "Windows", "Windows Machine GUID", "PnP hardware IDs", "Extended device inventory"
    };

    public static Task<SnapshotCatalog> ReadAsync(IEnumerable<string> directories) => Task.Run(() =>
    {
        var entries = new List<SnapshotEntry>();
        var folders = new List<string>();
        var skipped = 0;
        var seenFolders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var directory in directories)
        {
            if (string.IsNullOrWhiteSpace(directory)) continue;
            try
            {
                var folder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
                if (seenFolders.Add(folder)) folders.Add(folder);
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException or IOException)
            {
                skipped++;
            }
        }

        var seenFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var folder in folders)
        {
            string[] files;
            try { files = Directory.GetFiles(folder, "*.json", SearchOption.TopDirectoryOnly); }
            catch (DirectoryNotFoundException) { continue; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                skipped++;
                continue;
            }

            foreach (var file in files)
            {
                if (!seenFiles.Add(file)) continue;
                try
                {
                    var entry = ReadEntry(file);
                    if (entry is null) skipped++;
                    else entries.Add(entry);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException
                    or DecoderFallbackException or InvalidOperationException)
                {
                    skipped++;
                }
            }
        }

        var ordered = entries.OrderByDescending(x => x.SortTime)
            .ThenBy(x => x.Path, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return new SnapshotCatalog(ordered, skipped, folders.ToArray());
    });

    private static SnapshotEntry? ReadEntry(string file)
    {
        // Match the BAT's shared-read lock and enforce the size limit on this handle.
        using var stream = File.Open(file, FileMode.Open, FileAccess.Read, FileShare.Read);
        var length = stream.Length;
        if (length <= 0 || length > MaximumReportBytes) return null;
        var bytes = GC.AllocateUninitializedArray<byte>((int)length);
        stream.ReadExactly(bytes);

        using var document = ParseReport(bytes);
        var root = document.RootElement;
        var info = root.Get("Report info");
        var version = info.Get("Version");
        if (info.ValueKind != JsonValueKind.Object || version.ValueKind != JsonValueKind.String
            || !SupportedVersion.IsMatch(version.Text())) return null;

        foreach (var field in new[] { "Computer", "Generated", "SavedAt" })
            if (info.Get(field).ValueKind is not (JsonValueKind.String or JsonValueKind.Null or JsonValueKind.Undefined))
                return null;

        // This is a catalog preview. The BAT checks all records and keys before comparison.
        if (!root.EnumerateObject().Any(section => HardwareSections.Contains(section.Name)
            && (section.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array))) return null;

        var computer = info.Text("Computer");
        var hasCaptureTime = DateTimeOffset.TryParse(info.Text("Generated"), CultureInfo.InvariantCulture,
            DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal, out var captured);
        var sortTime = hasCaptureTime ? captured.ToUniversalTime() : new DateTimeOffset(File.GetLastWriteTimeUtc(stream.SafeFileHandle));
        var size = length < 1024 * 1024 ? $"{length / 1024d:0.#} KB" : $"{length / (1024d * 1024):0.#} MB";
        return new SnapshotEntry(file, Path.GetFileName(file), string.IsNullOrWhiteSpace(computer) ? "Unknown PC" : computer,
            hasCaptureTime ? captured.ToLocalTime().ToString("MMM d, yyyy  HH:mm") : "Unknown capture time", version.Text(), size, sortTime);
    }

    private static JsonDocument ParseReport(ReadOnlyMemory<byte> bytes)
    {
        // The UTF-32 LE BOM also starts with the UTF-16 LE BOM, so test UTF-32 first.
        foreach (var encoding in WideEncodings)
        {
            var preamble = encoding.Preamble;
            if (bytes.Span.StartsWith(preamble))
                return JsonDocument.Parse(encoding.GetString(bytes.Span[preamble.Length..]), ReportJsonOptions);
        }

        if (bytes.Span.StartsWith(Utf8.Preamble)) bytes = bytes[Utf8.Preamble.Length..];
        // Validate all UTF-8 bytes without creating a second, UTF-16 copy of a large report.
        _ = Utf8.GetCharCount(bytes.Span);
        return JsonDocument.Parse(bytes, ReportJsonOptions);
    }
}
