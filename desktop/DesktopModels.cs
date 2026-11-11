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
    public static string SectionName(string name) => name switch
    {
        "Report info" => "Scan information", "Compatibility" => "Windows reader support",
        "System identity" => "System IDs", "System hardware" => "PC hardware",
        "CPU" => "Processor (CPU)", "BIOS" => "BIOS / firmware", "Chassis" => "Case / chassis",
        "Memory modules" => "Memory (RAM)", "Storage identifiers" => "Storage IDs",
        "Volumes" => "Volumes / drive letters", "Graphics adapters" => "Graphics (GPU)",
        "Windows Machine GUID" => "Windows installation ID", "PnP hardware IDs" => "Plug and Play devices",
        "Extended device inventory" => "Extended device list", "Extended scan info" => "Extended device scan",
        "Scan timing" => "Read results / timing", "Warnings" => "Scan warnings",
        _ => name
    };
    public static bool IsCapturedRecord(JsonElement value) =>
        value.ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null) &&
        (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Any() &&
            value.Get("Unavailable").ValueKind == JsonValueKind.Undefined);
    public static string Timestamp(string input)
    {
        if (!Regex.IsMatch(input, @"\A\d{4}-\d{2}-\d{2}(?:[Tt ].+)?\z") ||
            !DateTimeOffset.TryParse(input, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var date))
            return input;
        if (input.Length == 10) return date.ToString("MMM d, yyyy", CultureInfo.CurrentCulture);
        var hasOffset = Regex.IsMatch(input, @"(?:[Zz]|[+-]\d{2}:\d{2})\z");
        return date.ToString(hasOffset ? "MMM d, yyyy  HH:mm:ss zzz" : "MMM d, yyyy  HH:mm:ss", CultureInfo.CurrentCulture);
    }
}

public sealed record ScanRow(string Name, string Status, string Records, string Detail, string Time);
internal sealed record IdentifierRow(string Section, string Field, string Value, string Status, string Device);
internal sealed record FieldRow(string Field, string Value, string? RawValue = null);
internal sealed record ReviewRow(string Kind, string Section, string Message, string Detail);
internal sealed record ChangeRow(string Kind, string Label, string Previous, string Current, string Detail);
internal sealed record HardwareSection(string Name, int Count)
{
    public string RawName => Name;
    public string FriendlyName => J.SectionName(Name);
    public string CountText
    {
        get
        {
            var unit = Name switch
            {
                "Scan timing" => Count == 1 ? "check" : "checks",
                "Warnings" => Count == 1 ? "message" : "messages",
                "Report info" or "Compatibility" or "Extended scan info" or "Windows Machine GUID" => Count == 1 ? "entry" : "entries",
                _ => Count == 1 ? "record" : "records"
            };
            return Count + " " + unit;
        }
    }
    public string Display => FriendlyName + "  ·  " + CountText;
}
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
    public IReadOnlyList<HardwareSection> Sections { get; }
    public string Version => Data.Text("version");
    public int ReportedIds => Identifiers.Count(x => x.Status == "Reported");
    public int SectionsRead => Timing.Where(x =>
        x.Status.Trim().Equals("READ", StringComparison.OrdinalIgnoreCase) ||
        x.Status.Trim().Equals("CHECK", StringComparison.OrdinalIgnoreCase))
        .Select(x => x.Name.Trim()).Where(name => name.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).Count();
    public int DeviceCount => Inventory.Get("Extended device inventory").Rows()
        .Count(row => row.ValueKind == JsonValueKind.Object && J.IsCapturedRecord(row));

    public DesktopSnapshot(JsonElement data)
    {
        if (data.Get("inventory").ValueKind != JsonValueKind.Object) throw new InvalidDataException("The scanner returned no inventory.");
        Data = data.Clone();
        Sections = Inventory.EnumerateObject()
            .Select(section => new HardwareSection(section.Name, section.Value.Rows().Count(J.IsCapturedRecord))).ToArray();
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
        var fallback = MetadataLabel(section, field);
        if (fallback != null && (label.Length == 0 || label.Equals(field, StringComparison.OrdinalIgnoreCase) ||
            label.Equals(J.Humanize(field), StringComparison.OrdinalIgnoreCase))) return fallback;
        return label.Length > 0 ? label : fallback ?? J.Humanize(field);
    }
    public string FieldValue(string section, int recordIndex, string field, JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Array or JsonValueKind.Object) return value.Display();
        if (Regex.IsMatch(field, @"\A(?:SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|DeviceInstanceId|SMBIOSAssetTag)\z", RegexOptions.IgnoreCase) &&
            value.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) && value.Text().Length > 0)
            return value.Text();
        var records = Data.Get("fieldValues").Get(section).Rows();
        var display = recordIndex >= 0 && recordIndex < records.Length ? records[recordIndex].Text(field) : "";
        if (section == "Report info" && field == "Administrator" &&
            value.ValueKind is JsonValueKind.True or JsonValueKind.False &&
            display.Trim().ToUpperInvariant() is "" or "YES" or "NO" or "TRUE" or "FALSE")
            return value.GetBoolean() ? "Administrator" : "Standard user";
        if (!string.IsNullOrWhiteSpace(display) && display != value.Text()) return display;
        if (field is "Generated" or "SavedAt" or "ScanCompleted" or "ExtendedAttempted" or "Captured" or "InstallDate" or "LastBootUpTime" or "ReleaseDate" or "DriverDate")
        {
            var formatted = J.Timestamp(value.Text());
            if (formatted != value.Text()) return formatted;
        }
        if (section == "Report info")
        {
            if (field == "Administrator" && value.ValueKind is JsonValueKind.True or JsonValueKind.False)
                return value.GetBoolean() ? "Administrator" : "Standard user";
            var friendly = (field, value.Text()) switch
            {
                ("Display", "Desktop companion") => "Desktop dashboard",
                ("Display", "Classic console") => "BAT console",
                ("Display", "Current window") => "Existing console window",
                ("QueryMode", "Live progress") => "Live progress available",
                ("QueryMode", "Direct queries") => "Basic progress",
                ("ExtendedStatus", "Refreshed") => "Device list read",
                ("ExtendedStatus", "Unavailable") => "Device list could not be read",
                _ => null
            };
            if (friendly != null) return friendly;
        }
        if (section == "Scan timing" && field == "Section") return J.SectionName(value.Text());
        if (section == "Scan timing" && field == "Status")
            return value.Text().Trim().ToUpperInvariant() switch
            {
                "READ" => "Read", "CHECK" => "Read with items to review",
                "UNAVAILABLE" or "NOT READ" => "Not read", "READING" => "Reading",
                "WAITING" => "Waiting", "STOPPED" => "Stopped", _ => value.Display()
            };
        return value.Display();
    }
    public string RecordTitle(string section, JsonElement record, int recordIndex)
    {
        if (record.Get("Unavailable").ValueKind != JsonValueKind.Undefined) return "Read unavailable";
        var title = section switch
        {
            "Report info" => "Snapshot details", "Compatibility" => "Windows / PowerShell support",
            "Extended scan info" => "Device-list read details", "Windows Machine GUID" => "Windows installation",
            "Scan timing" => J.SectionName(record.Text("Section")),
            _ => ""
        };
        if (title.Length > 0) return title;
        if (record.ValueKind == JsonValueKind.Object)
        {
            foreach (var field in new[] { "FriendlyName", "Name", "Model", "Product", "Caption", "DeviceLocator", "BankLabel", "PartNumber", "DeviceID", "InstanceName", "DeviceInstanceId", "PNPDeviceID" })
                if (!string.IsNullOrWhiteSpace(record.Text(field))) return record.Text(field);
            return "Record " + (recordIndex + 1);
        }
        return record.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ? "Record " + (recordIndex + 1) : record.Display();
    }
    public static string SectionDescription(string section) => section switch
    {
        "Report info" => "Capture time and settings used for this snapshot.",
        "Compatibility" => "Windows, PowerShell and reader availability reported by the scanner.",
        "Scan timing" => "Read results for the normal scan sections. A read can succeed while some identifiers are missing.",
        "Extended scan info" => "Capture time, reader and query counts for the extended device list.",
        "Extended device inventory" => "Records returned by the extended Windows reader. Entries can represent physical or virtual devices.",
        "PnP hardware IDs" => "Windows device records and the identifiers Windows exposes for them.",
        "Windows Machine GUID" => "The identifier reported for this Windows installation.",
        "Warnings" => "Messages captured while reading this snapshot.",
        _ => "Hardware records reported by Windows in this snapshot."
    };
    private static string? MetadataLabel(string section, string field) => (section, field) switch
    {
        ("Report info", "Generated") => "Captured at", ("Report info", "Computer") => "PC name",
        ("Report info", "Administrator") => "Access level", ("Report info", "Version") => "Scanner version",
        ("Report info", "Display") => "Interface", ("Report info", "QueryMode") => "Progress mode",
        ("Report info", "ExtendedStatus") => "Device-list read status",
        ("Report info", "ScanSeconds") => "Scan duration (seconds)",
        ("Report info", "ScanCompleted") => "Scan finished at",
        ("Report info", "ExtendedAttempted") => "Last device-list read attempt",
        ("Report info", "CompatibleReadSections") => "Sections read with a fallback",
        ("Report info", "ProgressFallbackSections") => "Sections using basic progress",
        ("Report info", "QueryCleanupSections") => "Sections with cleanup warnings",
        ("Extended scan info", "Captured") => "Device list captured at",
        ("Extended scan info", "Source") => "Read method",
        ("Extended scan info", "Records") => "Device records",
        ("Extended scan info", "PropertyNodesRequested") => "Device nodes queried for properties",
        ("Extended scan info", "PropertyNodesReturned") => "Device nodes returning properties",
        ("Extended scan info", "PropertyNodesWithoutRows") => "Device nodes without property results",
        ("Scan timing", "Section") => "Checked section", ("Scan timing", "Status") => "Read result",
        ("Scan timing", "Results") => "Records returned", ("Scan timing", "Seconds") => "Read time (seconds)",
        ("Scan timing", "Summary") => "Read summary", ("Scan timing", "Recoveries") => "Fallback read attempts",
        _ => null
    };
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
