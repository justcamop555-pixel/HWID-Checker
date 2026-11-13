using System.Buffers.Binary;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace HwidDesktop;

// A restart transfers session data in memory. No hardware snapshot is written
// to a temporary file, and the original window owns the decision to commit.
internal sealed class RestartHandoff : IAsyncDisposable
{
    internal const int PayloadLimit = 64 * 1024 * 1024;
    private readonly NamedPipeServerStream _pipe;
    private readonly Process _child;
    private bool _committed;
    internal int ChildId => _child.Id;

    private RestartHandoff(NamedPipeServerStream pipe, Process child) => (_pipe, _child) = (pipe, child);

    internal static async Task<RestartHandoff> StartAsync(string executable, JsonElement state,
        CancellationToken cancellation, IEnumerable<string>? extraArguments = null,
        Func<ProcessStartInfo, Process?>? launch = null, TimeSpan? timeout = null)
    {
        if (!Path.IsPathFullyQualified(executable) || !File.Exists(executable))
            throw new FileNotFoundException("The desktop executable is unavailable. The current window stays open.");
        var payload = JsonSerializer.SerializeToUtf8Bytes(state);
        if (payload.Length > PayloadLimit) throw new InvalidDataException("This session is too large to transfer. Save the snapshot before restarting.");
        var name = "HWID-Restart-" + Guid.NewGuid().ToString("N");
        var pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        Process? child = null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        using var exitMonitor = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(25));
        try
        {
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(executable)! };
            start.ArgumentList.Add("--restart-pipe"); start.ArgumentList.Add(name);
            foreach (var argument in extraArguments ?? []) start.ArgumentList.Add(argument);
            cancellation.ThrowIfCancellationRequested();
            child = (launch ?? Process.Start)(start) ?? throw new IOException("Windows did not start the replacement window.");
            var connected = pipe.WaitForConnectionAsync(deadline.Token);
            var exited = child.WaitForExitAsync(exitMonitor.Token);
            if (await Task.WhenAny(connected, exited).ConfigureAwait(false) == exited)
            {
                await exited.ConfigureAwait(false);
                throw new IOException("The replacement window (" + Path.GetFileName(executable) + ") closed before it was ready (exit " + child.ExitCode + ").");
            }
            await connected.ConfigureAwait(false);
            exitMonitor.Cancel();
            try { await exited.ConfigureAwait(false); } catch (OperationCanceledException) { }
            await WriteFrameAsync(pipe, payload, deadline.Token).ConfigureAwait(false);
            var ready = await ReadFrameAsync(pipe, 4096, deadline.Token).ConfigureAwait(false);
            if (!ready.HasTrue("ready")) throw new IOException("The replacement window could not restore the current session.");
            return new RestartHandoff(pipe, child);
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        {
            await pipe.DisposeAsync(); TryClose(child); child?.Dispose();
            throw new TimeoutException("The replacement window did not become ready in time. The current window stays open.");
        }
        catch
        {
            await pipe.DisposeAsync(); TryClose(child); child?.Dispose(); throw;
        }
    }

    internal async Task CommitAsync(CancellationToken cancellation)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(TimeSpan.FromSeconds(5));
        await WriteFrameAsync(_pipe, "{\"commit\":true}"u8.ToArray(), deadline.Token).ConfigureAwait(false);
        if (!(await ReadFrameAsync(_pipe, 4096, deadline.Token).ConfigureAwait(false)).HasTrue("committed"))
            throw new IOException("The replacement window did not confirm the restart.");
        _committed = true;
    }

    internal static async Task<RestartReceiver> ConnectAsync(string name, CancellationToken cancellation)
    {
        if (!Regex.IsMatch(name, "\\AHWID-Restart-[a-f0-9]{32}\\z")) throw new InvalidDataException("Invalid restart session.");
        var pipe = new NamedPipeClientStream(".", name, PipeDirection.InOut,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly, TokenImpersonationLevel.Identification);
        try
        {
            await pipe.ConnectAsync(cancellation).ConfigureAwait(false);
            return new RestartReceiver(pipe, await ReadFrameAsync(pipe, PayloadLimit, cancellation).ConfigureAwait(false));
        }
        catch { await pipe.DisposeAsync(); throw; }
    }

    internal static async Task WriteFrameAsync(Stream stream, byte[] data, CancellationToken cancellation)
    {
        if (data.Length is < 1 or > PayloadLimit) throw new InvalidDataException("Invalid restart message size.");
        var length = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(length, data.Length);
        await stream.WriteAsync(length, cancellation).ConfigureAwait(false);
        await stream.WriteAsync(data, cancellation).ConfigureAwait(false);
        await stream.FlushAsync(cancellation).ConfigureAwait(false);
    }

    internal static async Task<JsonElement> ReadFrameAsync(Stream stream, int limit, CancellationToken cancellation)
    {
        var header = new byte[4]; await stream.ReadExactlyAsync(header, cancellation).ConfigureAwait(false);
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length < 1 || length > limit) throw new InvalidDataException("Invalid restart message size.");
        var bytes = new byte[length]; await stream.ReadExactlyAsync(bytes, cancellation).ConfigureAwait(false);
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 128 });
        if (document.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid restart message.");
        return document.RootElement.Clone();
    }

    private static void TryClose(Process? child)
    {
        try { if (child is { HasExited: false }) child.CloseMainWindow(); }
        catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { }
    }

    public async ValueTask DisposeAsync()
    {
        await _pipe.DisposeAsync();
        if (!_committed) TryClose(_child);
        _child.Dispose();
    }
}

internal sealed class RestartReceiver(NamedPipeClientStream pipe, JsonElement state) : IAsyncDisposable
{
    internal JsonElement State { get; } = state;
    internal async Task ReadyAsync(CancellationToken cancellation)
    {
        await RestartHandoff.WriteFrameAsync(pipe, "{\"ready\":true}"u8.ToArray(), cancellation);
        if (!(await RestartHandoff.ReadFrameAsync(pipe, 4096, cancellation)).HasTrue("commit"))
            throw new IOException("The original window cancelled the restart.");
        await RestartHandoff.WriteFrameAsync(pipe, "{\"committed\":true}"u8.ToArray(), cancellation);
    }
    public ValueTask DisposeAsync() => pipe.DisposeAsync();
}

internal static class RestartJson
{
    internal static bool HasTrue(this JsonElement value, string name) => value.ValueKind == JsonValueKind.Object &&
        value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.True;
}
