using System.Buffers.Binary;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using HwidDesktop;

if (args.Contains("--restart-pipe"))
{
    var mode = args.Last();
    if (mode == "early") return 23;
    if (mode == "wait") { await Task.Delay(500); return 0; }
    try
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using var receiver = await RestartHandoff.ConnectAsync(args[1], cancellation.Token);
        if (mode == "reject") return 2;
        if (receiver.State.GetProperty("serial").GetString() != "000123 Ω ! &" ||
            receiver.State.GetProperty("zero").GetInt32() != 0) return 24;
        await receiver.ReadyAsync(cancellation.Token);
        return 0;
    }
    catch (IOException) { return mode == "abort" ? 0 : 25; }
}

var checks = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException(name);
    checks++; Console.WriteLine("PASS: " + name);
}
async Task Throws<T>(Func<Task> action, string name) where T : Exception
{
    try { await action(); } catch (T) { Check(true, name); return; }
    throw new InvalidOperationException("Expected " + typeof(T).Name + ": " + name);
}
var state = JsonSerializer.SerializeToElement(new { serial = "000123 Ω ! &", zero = 0 });
var executable = Environment.ProcessPath!;
var lastId = 0;
Process? lastStartedChild = null;
Func<ProcessStartInfo, Process?> Launcher(string mode) => start =>
{
    start.ArgumentList.Add(mode); start.CreateNoWindow = true; start.WindowStyle = ProcessWindowStyle.Hidden;
    var child = Process.Start(start); lastStartedChild = child; lastId = child?.Id ?? 0; return child;
};
bool ChildEnded()
{
    try { using var child = Process.GetProcessById(lastId); return child.WaitForExit(3000); }
    catch (ArgumentException) { return true; }
}

await Throws<FileNotFoundException>(async () => await RestartHandoff.StartAsync("missing.exe", state, default), "missing executable fails before the original window closes");
await Throws<IOException>(async () => await RestartHandoff.StartAsync(executable, state, default, launch: _ => null), "a null launcher result cannot confirm a restart");
await Throws<InvalidOperationException>(async () => await RestartHandoff.StartAsync(executable, state, default, launch: _ => throw new InvalidOperationException()), "a launch exception is reported to the original window");
await Throws<IOException>(async () => await RestartHandoff.StartAsync(executable, state, default, launch: Launcher("early")), "early replacement exit is detected without waiting for the full deadline");
await Throws<EndOfStreamException>(async () => await RestartHandoff.StartAsync(executable, state, default, launch: Launcher("reject")), "a receiver that rejects state cannot confirm readiness");
using (var cancel = new CancellationTokenSource(80))
    await Throws<OperationCanceledException>(async () => await RestartHandoff.StartAsync(executable, state, cancel.Token, launch: Launcher("wait")), "cancellation preserves the original process");
Check(ChildEnded(), "cancelled synthetic children leave no running fixture");
await Throws<TimeoutException>(async () => await RestartHandoff.StartAsync(executable, state, default, launch: Launcher("wait"), timeout: TimeSpan.FromMilliseconds(80)), "an unresponsive replacement has a bounded timeout");
Check(ChildEnded(), "timed-out synthetic children leave no running fixture");
await using (var handoff = await RestartHandoff.StartAsync(executable, state, default, launch: Launcher("abort")))
    Check(handoff.ChildId != Environment.ProcessId, "readiness belongs to a new process");
Check(ChildEnded(), "discarding a prepared handoff aborts its uncommitted receiver");
await using (var handoff = await RestartHandoff.StartAsync(executable, state, default, launch: Launcher("happy")))
{
    var child = lastStartedChild!;
    Check(!child.HasExited, "the restored replacement waits for commit");
    await handoff.CommitAsync(default);
    Check(child.WaitForExit(3000) && child.ExitCode == 0, "commit preserves exact Unicode, zeroes and leading-zero identifiers across real processes");
}
foreach (var length in new[] { -1, 0, RestartHandoff.PayloadLimit + 1 })
{
    var header = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(header, length);
    await Throws<InvalidDataException>(async () => await RestartHandoff.ReadFrameAsync(new MemoryStream(header), RestartHandoff.PayloadLimit, default), "invalid frame size is rejected before allocation: " + length);
}
await using (var stream = new MemoryStream())
{
    await RestartHandoff.WriteFrameAsync(stream, Encoding.UTF8.GetBytes(state.GetRawText()), default); stream.Position = 0;
    Check((await RestartHandoff.ReadFrameAsync(stream, 4096, default)).GetProperty("serial").GetString() == "000123 Ω ! &", "framed state retains exact text");
}
await using (var stream = new MemoryStream())
{
    await RestartHandoff.WriteFrameAsync(stream, "[]"u8.ToArray(), default); stream.Position = 0;
    await Throws<InvalidDataException>(async () => await RestartHandoff.ReadFrameAsync(stream, 4096, default), "non-object state is rejected");
}
await Throws<EndOfStreamException>(async () => await RestartHandoff.ReadFrameAsync(new MemoryStream([1, 0, 0]), 4096, default), "truncated frame headers fail without hanging");
await Throws<InvalidDataException>(async () => await RestartHandoff.ConnectAsync("arbitrary-pipe", default), "restart arguments cannot select an unrelated pipe name");
Console.WriteLine($"All {checks} restart-handoff checks passed. Synthetic identifiers only; no snapshot files created.");
return 0;
