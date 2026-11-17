using System.IO;

namespace HwidDesktop;

internal readonly record struct SnapshotPreviewStamp(long Length, DateTime LastWriteUtc, DateTime? CreationUtc)
{
    internal static SnapshotPreviewStamp? Read(FileStream stream)
    {
        try
        {
            var modified = File.GetLastWriteTimeUtc(stream.SafeFileHandle);
            DateTime? created = null;
            try { created = File.GetCreationTimeUtc(stream.SafeFileHandle); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException) { }
            return new(stream.Length, modified, created);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException) { return null; }
    }
}

internal readonly record struct SnapshotPreviewCacheStatistics(int Entries, int Characters, long Hits, long Reads, long Parses, long BytesRead);

/// <summary>Bounded, per-window preview metadata only. Never stores report bytes,
/// identifier inventories, parse failures or comparison results.</summary>
internal sealed class SnapshotPreviewCache
{
    private sealed record Entry(string Path, SnapshotPreviewStamp Stamp, SnapshotEntry Preview, int Characters);
    private readonly object sync = new();
    private readonly Dictionary<string, Entry> entries = new(StringComparer.OrdinalIgnoreCase);
    private readonly int maximumEntries, maximumCharacters;
    private int characters;
    private long hits, reads, parses, bytesRead;

    internal SnapshotPreviewCache(int maximumEntries = 256, int maximumCharacters = 131072)
    {
        if (maximumEntries is < 1 or > 4096) throw new ArgumentOutOfRangeException(nameof(maximumEntries));
        if (maximumCharacters is < 1 or > 1048576) throw new ArgumentOutOfRangeException(nameof(maximumCharacters));
        this.maximumEntries = maximumEntries; this.maximumCharacters = maximumCharacters;
    }

    internal SnapshotPreviewCacheStatistics Statistics
    {
        get { lock (sync) return new(entries.Count, characters, hits, reads, parses, bytesRead); }
    }

    internal bool TryGet(string path, SnapshotPreviewStamp stamp, out SnapshotEntry? preview)
    {
        lock (sync)
        {
            if (entries.TryGetValue(path, out var entry))
            {
                if (entry.Stamp == stamp)
                {
                    hits++;
                    preview = entry.Preview; return true;
                }
                RemoveEntry(entry);
            }
            preview = null; return false;
        }
    }

    internal void Store(string path, SnapshotPreviewStamp stamp, SnapshotEntry preview)
    {
        // A malformed but valid JSON string could otherwise retain megabytes in
        // a single Computer field. Large previews still appear; they aren't cached.
        var size = (long)path.Length + preview.Path.Length + preview.Name.Length + preview.Computer.Length +
            preview.Captured.Length + preview.Version.Length + preview.Size.Length;
        lock (sync)
        {
            if (entries.TryGetValue(path, out var existing)) RemoveEntry(existing);
            if (size > 8192 || size > maximumCharacters) return;
            // Discovery walks the whole library. Evicting on every new file
            // would make a sequential library larger than the budget miss on
            // every refresh. Keep valid admissions; completed-scope pruning
            // releases deleted/unwatched entries for later files.
            if (entries.Count >= maximumEntries || characters + size > maximumCharacters) return;
            entries.Add(path, new Entry(path, stamp, preview, (int)size)); characters += (int)size;
        }
    }

    internal void Remove(string path)
    {
        lock (sync) if (entries.TryGetValue(path, out var entry)) RemoveEntry(entry);
    }

    internal void Retain(IReadOnlySet<string> discovered)
    {
        lock (sync)
            foreach (var path in entries.Keys.Where(path => !discovered.Contains(path)).ToArray())
                RemoveEntry(entries[path]);
    }

    internal void RecordRead(long length) { lock (sync) { reads++; bytesRead += length; } }
    internal void RecordParse() { lock (sync) parses++; }

    private void RemoveEntry(Entry entry)
    {
        entries.Remove(entry.Path); characters -= entry.Characters;
    }
}
