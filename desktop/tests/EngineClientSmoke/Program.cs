using System.Diagnostics;
using System.Text;
using System.Text.Json;
using HwidDesktop;

string root = Path.Combine(Path.GetTempPath(), "HWIDDesktop-host-test-" + Guid.NewGuid().ToString("N"), "space ! & é ' 中文");
Directory.CreateDirectory(root);
string bat = Path.Combine(root, "hwid.bat");
string marker = Path.Combine(root, "last-operation.txt");
List<string> files = new() { bat, marker };
int checks = 0;
void Assert(bool condition, string message)
{
    if (!condition) throw new Exception("FAILED: " + message);
    checks++;
    Console.WriteLine("PASS: " + message);
}
void Mode(string value) => File.WriteAllText(bat, value, new UTF8Encoding(false));
void Cleaned()
{
    string operation = File.ReadAllText(marker);
    Assert(!Directory.Exists(operation), "Only this completed operation's temporary folder is removed");
}
async Task ExpectEngine(string code, Func<Task> action)
{
    try { await action(); throw new Exception("Expected " + code); }
    catch (EngineException ex) { Assert(ex.Code == code, "Failure preserves " + code); }
    Cleaned();
}

try
{
    using (var bytes = new MemoryStream(Encoding.UTF8.GetBytes("é\r\n\r中文\nlast")))
    using (var reader = new StreamReader(bytes, Encoding.UTF8))
    {
        var protocol = new EngineProtocolReader(reader, 32);
        var lines = new List<string?>();
        for (int index = 0; index < 5; index++) lines.Add(await protocol.ReadLineAsync(CancellationToken.None));
        Assert(lines.SequenceEqual(new string?[] { "é", "", "中文", "last", null }), "Bounded protocol reading preserves Unicode, CR/LF and the last line without a terminator");
    }
    using (var bytes = new MemoryStream(Encoding.UTF8.GetBytes("1234\r\nnext")))
    using (var reader = new StreamReader(bytes, Encoding.UTF8))
    {
        var protocol = new EngineProtocolReader(reader, 4);
        Assert(await protocol.ReadLineAsync(CancellationToken.None) == "1234" && await protocol.ReadLineAsync(CancellationToken.None) == "next", "The exact line-size boundary remains valid across consecutive messages");
    }
    using (var bytes = new RepeatingInputStream())
    using (var reader = new StreamReader(bytes, Encoding.UTF8))
    {
        var protocol = new EngineProtocolReader(reader, 128);
        try { await protocol.ReadLineAsync(CancellationToken.None); throw new Exception("Expected oversized protocol failure"); }
        catch (EngineException ex) { Assert(ex.Code == "ENGINE-PROTOCOL" && bytes.BytesRead <= 32768, "An oversized unterminated response is rejected before consuming the rest of the stream"); }
    }
    Mode("normal");
    using EngineClient client = new(bat);
    List<BridgeProgress> updates = new();
    JsonElement scan = await client.ScanAsync(new InlineProgress(updates.Add), CancellationToken.None);
    Assert(scan.GetProperty("inventory").GetProperty("CPU")[0].GetProperty("Name").GetString() == "Synthetic é 中文", "Unicode data survives the Windows PowerShell UTF8 pipe");
    Assert(updates.Count == 1 && updates[0].Name == "Synthetic é 中文" && updates[0].Completed == 1, "Progress arrives with Unicode and stage counts");
    Assert(updates[0].FailureCode == "" && updates[0].NextStep == "", "Older bridge progress without guidance remains compatible");
    Assert(scan.GetProperty("version").GetString() == "3.83", "Result data remains valid after its JSON document closes");
    Cleaned();
    Mode("read-guidance");
    updates.Clear();
    await client.ScanAsync(new InlineProgress(updates.Add), CancellationToken.None);
    Assert(updates.Count == 1 && updates[0].Status == "NOT READ" && updates[0].FailureCode == "READ-01" &&
        updates[0].NextStep == "Synthetic retry guidance é 中文", "Read-failure codes and next steps reach the UI without losing Unicode text");
    Cleaned();
    Mode("normal");
    JsonElement stillValid = await client.ScanAsync(new InlineProgress(_ => throw new InvalidOperationException("Synthetic closed view")), CancellationToken.None);
    Assert(stillValid.GetProperty("version").GetString() == "3.83", "A failed progress callback cannot discard the snapshot");
    Cleaned();

    Mode("stderr");
    Stopwatch clock = Stopwatch.StartNew();
    JsonElement noisy = await client.ScanAsync(null, CancellationToken.None);
    Assert(noisy.GetProperty("version").GetString() == "3.83" && clock.Elapsed < TimeSpan.FromSeconds(10), "Large stderr is drained without blocking a successful result");
    Cleaned();
    Mode("error");
    try { await client.ScanAsync(null, CancellationToken.None); throw new Exception("Expected synthetic failure"); }
    catch (EngineException ex) { Assert(ex.Code == "READ-02" && ex.Message.Contains("é 中文"), "Reported error retains its code and Unicode detail"); }
    Cleaned();
    Mode("error-hang");
    clock.Restart();
    try { await client.ScanAsync(null, CancellationToken.None); throw new Exception("Expected immediate failure"); }
    catch (EngineException ex) { Assert(ex.Code == "READ-02" && ex.Message.Contains("é 中文") && clock.Elapsed < TimeSpan.FromSeconds(8), "A reported scan error ends the owned process promptly even when its shutdown hangs"); }
    Cleaned();
    foreach ((string mode, string code) in new[] { ("bad-json", "ENGINE-PROTOCOL"), ("duplicate", "ENGINE-PROTOCOL"), ("no-result", "ENGINE-PROTOCOL"), ("incomplete", "ENGINE-PROTOCOL"), ("bad-exit", "ENGINE-04") })
    {
        Mode(mode);
        await ExpectEngine(code, async () => { await client.ScanAsync(null, CancellationToken.None); });
    }

    Mode("slow");
    using CancellationTokenSource cancellation = new();
    TaskCompletionSource started = new(TaskCreationOptions.RunContinuationsAsynchronously);
    Task<JsonElement> pending = client.ScanAsync(new InlineProgress(_ => started.TrySetResult()), cancellation.Token);
    await started.Task.WaitAsync(TimeSpan.FromSeconds(10));
    try { await client.ScanAsync(null, CancellationToken.None); throw new Exception("Expected busy failure"); }
    catch (EngineException ex) { Assert(ex.Code == "ENGINE-BUSY", "Overlapping operations are rejected without starting another process"); }
    clock.Restart();
    cancellation.Cancel();
    try { await pending; throw new Exception("Expected cancellation"); }
    catch (OperationCanceledException) { Assert(clock.Elapsed < TimeSpan.FromSeconds(6), "Cancellation promptly ends the owned PowerShell operation"); }
    Cleaned();
    Mode("normal");
    JsonElement afterCancel = await client.ScanAsync(null, CancellationToken.None);
    Assert(afterCancel.GetProperty("version").GetString() == "3.83", "A fresh operation works after cancellation");
    Cleaned();

    string previous = Path.Combine(root, "old ! & é ' 中文.json");
    files.Add(previous);
    JsonElement inventory = scan.GetProperty("inventory");
    File.WriteAllText(previous, inventory.GetRawText(), new UTF8Encoding(false));
    JsonElement comparison = await client.CompareAsync(previous, inventory, CancellationToken.None);
    Assert(comparison.GetProperty("previousPath").GetString() == previous && comparison.GetProperty("processor").GetString() == "SYNTHETIC-ONLY-000123", "Compare paths with spaces, Unicode and shell punctuation are passed literally");
    Cleaned();
    Task<JsonElement> detachedComparison;
    using (JsonDocument temporaryDocument = JsonDocument.Parse(inventory.GetRawText()))
        detachedComparison = client.CompareAsync(previous, temporaryDocument.RootElement, CancellationToken.None);
    JsonElement detached = await detachedComparison;
    Assert(detached.GetProperty("currentCount").GetInt32() == 1, "Compare owns a stable copy when the caller disposes its JSON document");
    Cleaned();
    string reports = Path.Combine(root, "reports ! & é ' 中文");
    JsonElement export = await client.ExportAsync(inventory, reports, CancellationToken.None);
    string text = export.GetProperty("textPath").GetString()!;
    string json = export.GetProperty("jsonPath").GetString()!;
    files.Add(text); files.Add(json);
    Assert(File.Exists(text) && File.Exists(json) && JsonDocument.Parse(File.ReadAllText(json)).RootElement.GetProperty("CPU")[0].GetProperty("ProcessorId").GetString() == "SYNTHETIC-ONLY-000123", "Export forwards a complete snapshot to the selected literal folder");
    Cleaned();

    Mode("slow");
    EngineClient closing = new(bat);
    TaskCompletionSource closingStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
    Task<JsonElement> closingTask = closing.ScanAsync(new InlineProgress(_ => closingStarted.TrySetResult()), CancellationToken.None);
    await closingStarted.Task.WaitAsync(TimeSpan.FromSeconds(10));
    closing.Dispose();
    try { await closingTask; throw new Exception("Expected disposal cancellation"); }
    catch (OperationCanceledException) { Assert(true, "Disposal cancels the active owned process"); }
    Cleaned();
    try { await closing.ScanAsync(null, CancellationToken.None); throw new Exception("Expected disposed failure"); }
    catch (ObjectDisposedException) { Assert(true, "A disposed host cannot start another process"); }
    Console.WriteLine($"All {checks} engine-client smoke checks passed. Synthetic identifiers only.");
}
finally
{
    foreach (string file in files) { try { File.Delete(file); } catch (IOException) { } }
    foreach (string directory in new[] { Path.Combine(root, "reports ! & é ' 中文"), root, Path.GetDirectoryName(root)! })
    { try { Directory.Delete(directory, recursive: false); } catch (IOException) { } }
}

sealed class InlineProgress(Action<BridgeProgress> handler) : IProgress<BridgeProgress>
{
    public void Report(BridgeProgress value) => handler(value);
}

sealed class RepeatingInputStream : Stream
{
    public long BytesRead { get; private set; }
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => 1_000_000;
    public override long Position { get => BytesRead; set => throw new NotSupportedException(); }
    public override int Read(byte[] buffer, int offset, int count)
    {
        int read = (int)Math.Min(count, Length - BytesRead);
        Array.Fill(buffer, (byte)'A', offset, read);
        BytesRead += read;
        return read;
    }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
