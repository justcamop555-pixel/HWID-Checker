using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace HwidDesktop;

internal sealed record SnapshotLibrarySettings(
    string? Primary,
    IReadOnlyList<string> Folders,
    string? Error = null,
    bool IsConfigured = false);

internal static class SharedSnapshotLibrary
{
    private const int MaxFolders = 32;
    private const int MaxSettingsBytes = 256 * 1024;
    private static readonly StringComparer FolderComparer = StringComparer.OrdinalIgnoreCase;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly Regex DeviceName = new(
        @"\A(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|(?:COM|LPT)[1-9\u00b9\u00b2\u00b3])\z",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "HWID Checker", "snapshot-library.json");

    public static SnapshotLibrarySettings Read(string? settingsPath = null)
    {
        var path = settingsPath ?? DefaultPath;
        try
        {
            return ReadCore(path);
        }
        catch (Exception ex) when (IsSettingsError(ex))
        {
            return new(null, ReadLegacyFolders(path),
                "Shared snapshot settings could not be read. The usual report folders are still available.");
        }
    }

    public static Task<SnapshotLibrarySettings> UpdateAsync(string action, string? folder, string? settingsPath = null) =>
        Task.Run(() => Update(action, folder, settingsPath ?? DefaultPath));

    private static SnapshotLibrarySettings Update(string action, string? folder, string settingsPath)
    {
        var path = Path.GetFullPath(settingsPath);
        var directory = Path.GetDirectoryName(path)!;
        var candidate = action == "reset-primary" ? null : NormalizeFolder(folder);
        Directory.CreateDirectory(directory);
        using var gate = AcquireWriteLock(Path.Combine(directory, "snapshot-library.lock"));

        SnapshotLibrarySettings current;
        try
        {
            current = ReadCore(path);
        }
        catch (Exception ex) when (IsSettingsError(ex))
        {
            throw new InvalidDataException(
                "Shared snapshot settings could not be read. Keep a copy of snapshot-library.json before repairing it.", ex);
        }

        var primary = current.Primary;
        var folders = current.Folders.ToList();
        switch (action)
        {
            case "set-primary":
                if (primary != null && !FolderComparer.Equals(primary, candidate))
                    folders.Add(primary);
                primary = candidate;
                break;
            case "add-folder":
                folders.Add(candidate!);
                break;
            case "remove-folder":
                if (FolderComparer.Equals(primary, candidate))
                    throw new InvalidOperationException("Change or reset the shared save folder before removing it.");
                folders.RemoveAll(x => FolderComparer.Equals(x, candidate));
                break;
            case "reset-primary":
                if (primary != null)
                    folders.Add(primary);
                primary = null;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(action));
        }

        var tracked = folders.Where(x => !FolderComparer.Equals(primary, x)).Distinct(FolderComparer).ToArray();
        if (tracked.Length > MaxFolders)
            throw new InvalidOperationException($"You can track up to {MaxFolders} additional folders. Remove one before adding another.");

        if (!current.IsConfigured || !FolderComparer.Equals(primary, current.Primary) ||
            !tracked.SequenceEqual(current.Folders, FolderComparer))
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new { version = 1, primary, folders = tracked });
            if (bytes.Length > MaxSettingsBytes)
                throw new InvalidDataException("Shared snapshot settings are too large.");
            WriteAtomically(path, bytes);
        }
        return new(primary, tracked, IsConfigured: true);
    }

    private static SnapshotLibrarySettings ReadCore(string path)
    {
        using var doc = ReadJson(path);
        if (doc == null)
            return new(null, ReadLegacyFolders(path));

        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("Shared snapshot settings must be a JSON object.");

        var propertyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in root.EnumerateObject())
        {
            if (!propertyNames.Add(property.Name))
                throw new InvalidDataException("Shared snapshot settings have duplicate fields.");
        }
        if (!root.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var number) || number != 1 ||
            !root.TryGetProperty("primary", out var preferred) ||
            !root.TryGetProperty("folders", out var extras) || extras.ValueKind != JsonValueKind.Array ||
            extras.GetArrayLength() > MaxFolders)
        {
            throw new InvalidDataException("Shared snapshot settings use an unsupported format.");
        }

        var primary = preferred.ValueKind == JsonValueKind.Null ? null : ReadFolder(preferred);
        var folders = extras.EnumerateArray().Select(ReadFolder)
            .Where(x => !FolderComparer.Equals(primary, x)).Distinct(FolderComparer).ToArray();
        return new(primary, folders, IsConfigured: true);
    }

    private static IReadOnlyList<string> ReadLegacyFolders(string settingsPath)
    {
        var parent = Path.GetDirectoryName(settingsPath);
        if (string.IsNullOrEmpty(parent))
            return [];

        try
        {
            using var doc = ReadJson(Path.Combine(parent, "Desktop", "settings.json"));
            if (doc == null || doc.RootElement.ValueKind != JsonValueKind.Object)
                return [];

            var root = doc.RootElement;
            var folders = new List<string>();
            var seen = new HashSet<string>(FolderComparer);
            void Add(JsonElement value)
            {
                if (value.ValueKind != JsonValueKind.String || folders.Count >= MaxFolders)
                    return;
                try
                {
                    var path = ReadFolder(value);
                    if (seen.Add(path))
                        folders.Add(path);
                }
                catch (Exception ex) when (IsSettingsError(ex)) { }
            }
            if (root.TryGetProperty("lastSaveFolder", out var last))
                Add(last);
            if (root.TryGetProperty("snapshotFolders", out var tracked) && tracked.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in tracked.EnumerateArray())
                    Add(entry);
            }
            return folders.ToArray();
        }
        catch (Exception ex) when (IsSettingsError(ex))
        {
            return [];
        }
    }

    private static string ReadFolder(JsonElement value) => NormalizeFolder(
        value.ValueKind == JsonValueKind.String ? value.GetString() : null);

    private static string NormalizeFolder(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length is < 3 or > 32767 || !char.IsAsciiLetter(value[0]) ||
            value[1] != ':' || (value[2] != '\\' && value[2] != '/') ||
            value.IndexOfAny(['<', '>', ':', '"', '|', '?', '*'], 3) >= 0 || value.Any(char.IsControl))
        {
            throw new ArgumentException("Choose an absolute folder on a Windows drive.");
        }

        foreach (var part in value[3..].Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries))
        {
            if (part is "." or "..")
                continue;
            var baseName = part.Split('.', 2)[0].TrimEnd(' ');
            if (part.EndsWith(' ') || part.EndsWith('.') || DeviceName.IsMatch(baseName))
                throw new ArgumentException("The folder contains an invalid Windows path component.");
        }
        var fullPath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(value));
        if (fullPath.Length > 32767)
            throw new ArgumentException("The folder path is too long.");
        return fullPath;
    }

    private static JsonDocument? ReadJson(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length > MaxSettingsBytes)
                throw new InvalidDataException("Snapshot folder settings are too large.");

            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1)
                throw new IOException("Snapshot folder settings changed while being read.");
            var bom = bytes.AsSpan().StartsWith(Encoding.UTF8.Preamble) ? Encoding.UTF8.Preamble.Length : 0;
            return JsonDocument.Parse(StrictUtf8.GetString(bytes.AsSpan(bom)));
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        {
            return null;
        }
    }

    private static FileStream AcquireWriteLock(string path)
    {
        var timer = Stopwatch.StartNew();
        while (true)
        {
            try
            {
                return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException ex)
            {
                if (timer.Elapsed >= TimeSpan.FromSeconds(2))
                    throw new IOException("Snapshot folder settings are busy or unavailable. Try again.", ex);
                Thread.Sleep(60);
            }
        }
    }

    private static void WriteAtomically(string path, byte[] contents)
    {
        var temporary = path + ".pending-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(contents);
                stream.Flush(flushToDisk: true);
            }
            if (File.Exists(path))
                File.Replace(temporary, path, null);
            else
                File.Move(temporary, path);
        }
        finally
        {
            try { File.Delete(temporary); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }

    private static bool IsSettingsError(Exception error) =>
        error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or ArgumentException or InvalidOperationException;
}
