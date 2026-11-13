using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace HwidDesktop;

internal static class ReportFiles
{
    private static readonly UTF8Encoding Utf8 = new(false);

    public static Task WriteTextAsync(string path, string text) => Task.Run(() =>
    {
        var destination = Path.GetFullPath(path);
        var pending = Stage(destination, text);
        try
        {
            if (File.Exists(destination)) File.Replace(pending, destination, null);
            else File.Move(pending, destination);
        }
        finally { RemovePending(pending); }
    });

    public static void WriteNewPair(string firstPath, string firstText, string secondPath, string secondText)
    {
        var first = Path.GetFullPath(firstPath);
        var second = Path.GetFullPath(secondPath);
        if (first.Equals(second, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Choose different files for the two exports.");
        if (!string.Equals(Path.GetDirectoryName(first), Path.GetDirectoryName(second), StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Export both reports into the same folder.");
        if (File.Exists(first) || Directory.Exists(first) || File.Exists(second) || Directory.Exists(second))
            throw new IOException("An export destination already exists. Export again to create a new report pair.");

        string? firstPending = null, secondPending = null;
        var publishedFirst = false;
        try
        {
            firstPending = Stage(first, firstText);
            secondPending = Stage(second, secondText);
            File.Move(firstPending, first);
            publishedFirst = true;
            File.Move(secondPending, second);
        }
        catch
        {
            // Roll back only the file created by this operation, preserving any
            // different contents another process may have written in the meantime.
            if (publishedFirst)
            {
                try
                {
                    if (File.Exists(first) && SHA256.HashData(File.ReadAllBytes(first))
                        .SequenceEqual(SHA256.HashData(Utf8.GetBytes(firstText))))
                        File.Delete(first);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
            throw;
        }
        finally
        {
            if (firstPending != null) RemovePending(firstPending);
            if (secondPending != null) RemovePending(secondPending);
        }
    }

    private static string Stage(string destination, string text)
    {
        var directory = Path.GetDirectoryName(destination)!;
        var path = Path.Combine(directory, ".hwid-export-" + Guid.NewGuid().ToString("N") + ".pending");
        try
        {
            using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            var bytes = Utf8.GetBytes(text);
            stream.Write(bytes);
            stream.Flush(flushToDisk: true);
            return path;
        }
        catch { RemovePending(path); throw; }
    }

    private static void RemovePending(string path)
    {
        try { File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
