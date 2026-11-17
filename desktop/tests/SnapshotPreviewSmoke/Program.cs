using System.Diagnostics;
using System.Text;
using System.Text.Json;
using HwidDesktop;

int checks = 0;
void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
    checks++; Console.WriteLine("PASS: " + message);
}
var output = Path.GetFullPath(args.Length > 0 ? args[0] : Path.Combine(Path.GetTempPath(), "HWID-preview-checks-" + Guid.NewGuid().ToString("N")));
if (Directory.Exists(output) || File.Exists(output)) throw new InvalidOperationException("Choose a new verification directory.");
Directory.CreateDirectory(output);
var root = Path.Combine(output, "synthetic-files"); Directory.CreateDirectory(root);
string Report(string computer, string padding = "") => JsonSerializer.Serialize(new Dictionary<string, object>
{
    ["Report info"] = new { Version = "3.96", Computer = computer, Generated = "2026-11-15T12:34:56+02:00" },
    ["CPU"] = new[] { new { ProcessorId = "SYNTHETIC-000123", Name = padding } }
});
void Write(string file, string computer, string padding = "") => File.WriteAllText(file, Report(computer, padding), new UTF8Encoding(false));
SnapshotPreviewStamp Stamp(string file) { using var stream = File.OpenRead(file); return SnapshotPreviewStamp.Read(stream) ?? throw new InvalidOperationException("File stamps are unavailable on this verification filesystem."); }
void RestoreStamp(string file, SnapshotPreviewStamp stamp)
{
    if (stamp.CreationUtc is { } created) File.SetCreationTimeUtc(file, created);
    File.SetLastWriteTimeUtc(file, stamp.LastWriteUtc);
}
object? benchmark = null;
try
{
    var folder = Path.Combine(root, "Unicode Ω folder"); Directory.CreateDirectory(folder);
    var file = Path.Combine(folder, "HWID-leading-000123.json");
    Write(file, "SYNTHETIC-000123 Ω");
    var originalBytes = File.ReadAllBytes(file);
    var cache = new SnapshotPreviewCache();
    var first = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache);
    var firstStats = cache.Statistics;
    var entry = first.Entries.Single();
    Check(first.Skipped == 0 && entry.Path == file && entry.Name == Path.GetFileName(file) && entry.Computer == "SYNTHETIC-000123 Ω" && entry.Version == "3.96",
        "fresh previews preserve exact path, Unicode computer name, leading zeroes and scanner version");
    Check(entry.SortTime == DateTimeOffset.Parse("2026-11-15T10:34:56Z") && entry.Captured.Length > 0 && entry.Size.EndsWith(" KB", StringComparison.Ordinal),
        "cached metadata retains capture time, ordering and display size");
    Check(firstStats.Reads == 1 && firstStats.Parses == 1 && firstStats.Entries == 1,
        "explicit discovery fully reads and validates a file before caching only its preview");
    var second = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(second.Entries.SequenceEqual(first.Entries) && cache.Statistics.Reads == firstStats.Reads && cache.Statistics.Parses == firstStats.Parses && cache.Statistics.Hits == 1,
        "an unchanged automatic refresh reuses identical previews without reading or parsing report bytes");
    Check(originalBytes.SequenceEqual(File.ReadAllBytes(file)), "preview discovery leaves the synthetic report bytes unchanged");

    var sameStamp = Stamp(file);
    Write(file, "SYNTHETIC-000124 Ω"); RestoreStamp(file, sameStamp);
    Check(Stamp(file) == sameStamp, "same-size manual-refresh fixture retains the original opened-handle metadata");
    var beforeManual = cache.Statistics;
    var manual = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache);
    Check(manual.Entries.Single().Computer == "SYNTHETIC-000124 Ω" && cache.Statistics.Reads == beforeManual.Reads + 1 && cache.Statistics.Parses == beforeManual.Parses + 1,
        "manual refresh validates fresh content even when size and timestamps were preserved");
    var afterManual = cache.Statistics;
    var autoAfterManual = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(autoAfterManual.Entries.Single().Computer == "SYNTHETIC-000124 Ω" && cache.Statistics.Parses == afterManual.Parses,
        "a successful manual refresh replaces the advisory preview reused afterward");

    Write(file, "SYNTHETIC-LONGER-PC-NAME");
    var beforeLength = cache.Statistics;
    var lengthChanged = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(lengthChanged.Entries.Single().Computer == "SYNTHETIC-LONGER-PC-NAME" && cache.Statistics.Parses == beforeLength.Parses + 1,
        "a changed file length invalidates the prior preview");
    var modifiedStamp = Stamp(file);
    Write(file, "SYNTHETIC-LONGER-PC-MARK");
    File.SetLastWriteTimeUtc(file, modifiedStamp.LastWriteUtc.AddMinutes(1));
    var beforeModified = cache.Statistics;
    var modified = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(modified.Entries.Single().Computer == "SYNTHETIC-LONGER-PC-MARK" && cache.Statistics.Parses == beforeModified.Parses + 1,
        "same-length content with a changed last-write time is validated again");

    var replacementStamp = Stamp(file);
    var replacement = Path.Combine(folder, "replacement.tmp"); Write(replacement, "SYNTHETIC-LONGER-PC-NEXT");
    File.Move(replacement, file, true);
    File.SetLastWriteTimeUtc(file, replacementStamp.LastWriteUtc);
    if (replacementStamp.CreationUtc is { } creation)
    {
        File.SetCreationTimeUtc(file, creation.AddHours(1));
        Check(Stamp(file).CreationUtc != replacementStamp.CreationUtc, "replacement fixture exposes its distinct creation metadata on the same opened handle");
    }
    var beforeReplace = cache.Statistics;
    var replaced = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(replaced.Entries.Single().Computer == "SYNTHETIC-LONGER-PC-NEXT" && cache.Statistics.Parses == beforeReplace.Parses + 1,
        "a replacement file with preserved length and modification time invalidates the old preview");

    using (var locked = new FileStream(file, FileMode.Open, FileAccess.Write, FileShare.None))
    {
        var blocked = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
        Check(blocked.Entries.Count == 0 && blocked.Skipped == 1 && cache.Statistics.Entries == 0,
            "cached metadata cannot bypass current read access or a conflicting file lock");
    }
    var unlocked = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(unlocked.Entries.Count == 1 && cache.Statistics.Entries == 1, "a previously locked report is retried after access recovers");

    var invalidStamp = Stamp(file); var invalidBytes = Enumerable.Repeat((byte)' ', (int)invalidStamp.Length).ToArray(); invalidBytes[0] = (byte)'{';
    File.WriteAllBytes(file, invalidBytes); RestoreStamp(file, invalidStamp);
    var invalidManual = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache);
    Check(invalidManual.Entries.Count == 0 && invalidManual.Skipped == 1 && cache.Statistics.Entries == 0,
        "explicit refresh rejects malformed content even when cached file metadata still matches");
    var beforeInvalid = cache.Statistics;
    var invalidAgain = await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true);
    Check(invalidAgain.Skipped == 1 && cache.Statistics.Reads == beforeInvalid.Reads + 1 && cache.Statistics.Parses == beforeInvalid.Parses + 1,
        "parse failures are not cached and remain eligible for recovery");
    Write(file, "SYNTHETIC-RECOVERED");
    Check((await SnapshotStore.ReadAsync(new[] { folder }, cache: cache, reuseCachedPreviews: true)).Entries.Single().Computer == "SYNTHETIC-RECOVERED",
        "a repaired file replaces its earlier invalid state");

    var alternate = Path.Combine(root, "Other scope"); Directory.CreateDirectory(alternate);
    var alternateFile = Path.Combine(alternate, "other.json"); Write(alternateFile, "SYNTHETIC-OTHER");
    Check((await SnapshotStore.ReadAsync(new[] { folder, alternate }, cache: cache)).Entries.Count == 2 && cache.Statistics.Entries == 2,
        "separate watched folders retain independent previews");
    var scoped = await SnapshotStore.ReadAsync(new[] { alternate }, cache: cache, reuseCachedPreviews: true);
    Check(scoped.Entries.Count == 1 && scoped.Entries[0].Path == alternateFile && cache.Statistics.Entries == 1,
        "a changed folder scope cannot retain or publish entries from an unwatched location");
    File.Delete(alternateFile);
    var deleted = await SnapshotStore.ReadAsync(new[] { alternate }, cache: cache, reuseCachedPreviews: true);
    Check(deleted.Entries.Count == 0 && cache.Statistics.Entries == 0, "deleted reports are removed from the cache after discovery");
    Write(alternateFile, "SYNTHETIC-OTHER");
    await SnapshotStore.ReadAsync(new[] { alternate }, cache: cache);
    Directory.Delete(alternate, true);
    Check((await SnapshotStore.ReadAsync(new[] { alternate }, cache: cache, reuseCachedPreviews: true)).Entries.Count == 0 && cache.Statistics.Entries == 0,
        "a removed watched folder does not keep stale previews");

    await SnapshotStore.ReadAsync(new[] { folder }, cache: cache);
    var beforeCancel = cache.Statistics;
    using (var cancelled = new CancellationTokenSource())
    {
        cancelled.Cancel();
        try { await SnapshotStore.ReadAsync(new[] { folder }, cancelled.Token, cache, true); throw new InvalidOperationException("Cancelled discovery must not return results."); }
        catch (OperationCanceledException) { Check(cache.Statistics == beforeCancel, "an already cancelled discovery does not read, parse, hit or prune the cache"); }
    }
    using (var cancelled = new CancellationTokenSource())
    {
        IEnumerable<string> InterruptedFolders() { yield return root; cancelled.Cancel(); yield return folder; }
        try { await SnapshotStore.ReadAsync(InterruptedFolders(), cancelled.Token, cache, true); throw new InvalidOperationException("Interrupted discovery must not return results."); }
        catch (OperationCanceledException) { Check(cache.Statistics == beforeCancel, "cancellation during folder discovery cannot prune a valid previous cache scope"); }
    }

    var boundedFolder = Path.Combine(root, "Bounded"); Directory.CreateDirectory(boundedFolder);
    for (var index = 0; index < 5; index++) Write(Path.Combine(boundedFolder, index + ".json"), "SYNTHETIC-" + index);
    var bounded = new SnapshotPreviewCache(maximumEntries: 2, maximumCharacters: 1024);
    var boundedCatalog = await SnapshotStore.ReadAsync(new[] { boundedFolder }, cache: bounded);
    Check(boundedCatalog.Entries.Count == 5 && bounded.Statistics.Entries <= 2 && bounded.Statistics.Characters <= 1024,
        "entry and metadata-character budgets bound memory without removing valid catalog rows");
    var beforeOverCapacity = bounded.Statistics;
    var overCapacity = await SnapshotStore.ReadAsync(new[] { boundedFolder }, cache: bounded, reuseCachedPreviews: true);
    Check(overCapacity.Entries.SequenceEqual(boundedCatalog.Entries) && beforeOverCapacity.Entries > 0 &&
        bounded.Statistics.Hits - beforeOverCapacity.Hits == beforeOverCapacity.Entries &&
        bounded.Statistics.Parses - beforeOverCapacity.Parses == 5 - beforeOverCapacity.Entries,
        "a library larger than the cache budget still reuses retained previews instead of sequentially evicting every hit");
    var veryLongComputer = new string('X', 10000);
    Write(Path.Combine(boundedFolder, "large-name.json"), veryLongComputer);
    var largeMetadata = await SnapshotStore.ReadAsync(new[] { boundedFolder }, cache: bounded, reuseCachedPreviews: true);
    Check(largeMetadata.Entries.Any(row => row.Computer == veryLongComputer) && bounded.Statistics.Entries <= 2 && bounded.Statistics.Characters <= 1024,
        "oversized preview strings stay accurate in results without entering the bounded cache");

    var benchmarkFolder = Path.Combine(root, "Benchmark"); Directory.CreateDirectory(benchmarkFolder);
    for (var index = 0; index < 12; index++) Write(Path.Combine(benchmarkFolder, index + ".json"), "SYNTHETIC-BENCH-" + index, new string('X', 200000));
    async Task<object> Measure(bool reuse)
    {
        var trial = new SnapshotPreviewCache();
        await SnapshotStore.ReadAsync(new[] { benchmarkFolder }, cache: trial);
        var before = trial.Statistics; var allocated = GC.GetTotalAllocatedBytes(false); var clock = Stopwatch.StartNew();
        for (var round = 0; round < 6; round++) await SnapshotStore.ReadAsync(new[] { benchmarkFolder }, cache: trial, reuseCachedPreviews: reuse);
        clock.Stop(); var after = trial.Statistics;
        return new { milliseconds = clock.Elapsed.TotalMilliseconds, allocatedBytes = GC.GetTotalAllocatedBytes(false) - allocated,
            reportReads = after.Reads - before.Reads, jsonParses = after.Parses - before.Parses,
            reportBytesRead = after.BytesRead - before.BytesRead, reusedPreviews = after.Hits - before.Hits };
    }
    benchmark = new { syntheticFiles = 12, rounds = 6, approximateBytesPerFile = 200000,
        fullValidation = await Measure(false), unchangedAutomaticRefresh = await Measure(true), timingIsNonGating = true };
    Console.WriteLine("NON-GATING SYNTHETIC BENCHMARK: " + JsonSerializer.Serialize(benchmark));
}
finally
{
    var safeRoot = Path.GetFullPath(root);
    if (!safeRoot.StartsWith(output.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("Synthetic cleanup escaped its verification directory.");
    if (Directory.Exists(safeRoot)) Directory.Delete(safeRoot, true);
}
var result = new { success = true, checks, syntheticOnly = true, hardwareIdentifiersSaved = false, benchmark };
await File.WriteAllTextAsync(Path.Combine(output, "result.json"), JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"All {checks} snapshot-preview checks passed. Synthetic data only.");
