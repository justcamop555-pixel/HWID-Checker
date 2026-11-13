using System.IO;
using System.Text.Json;
using System.Text;

namespace HwidDesktop;

internal static class StartupPreparation
{
    // Run even the open/metadata checks off the dispatcher. Reading settings
    // must not prevent the loading window from painting or responding to Close.
    internal static Task<JsonElement> ReadPreferencesAsync(string? path, CancellationToken cancellationToken) => Task.Run(() =>
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            if (path != null)
            {
                using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                var length = stream.Length;
                if (length is > 0 and <= 262144)
                {
                    // Bound the bytes on this open handle even if another process
                    // grows the file after the length check. Keep BOM compatibility.
                    var bytes = new byte[(int)length];
                    stream.ReadExactly(bytes);
                    using var reader = new StreamReader(new MemoryStream(bytes), Encoding.UTF8, true);
                    using var document = JsonDocument.Parse(reader.ReadToEnd(), new JsonDocumentOptions { MaxDepth = 64 });
                    cancellationToken.ThrowIfCancellationRequested();
                    if (document.RootElement.ValueKind == JsonValueKind.Object) return document.RootElement.Clone();
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException or NotSupportedException) { }
        cancellationToken.ThrowIfCancellationRequested();
        return JsonSerializer.SerializeToElement(new { });
    }, cancellationToken);
}
