using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace HwidDesktop;

internal sealed record BridgeProgress(string Section, string Name, int Completed, int Total,
    string Status, int Records, string Message);

internal sealed class EngineException : Exception
{
    public string Code { get; }

    public EngineException(string message, string code = "ENGINE-01", Exception? inner = null)
        : base(message, inner) => Code = code;
}

/// <summary>Runs the BAT's existing scanner through the embedded PowerShell bridge.</summary>
internal sealed class EngineClient : IDisposable
{
    private const string BridgeResource = "HwidDesktop.EngineBridge";
    private const int DiagnosticLimit = 4096;
    private const int MaximumProtocolLine = 64 * 1024 * 1024;
    private static readonly UTF8Encoding Utf8 = new(false);
    private static readonly TimeSpan OperationTimeout = TimeSpan.FromMinutes(10);
    private readonly object sync = new();
    private CancellationTokenSource? activeCancellation;
    private Process? activeProcess;
    private bool busy;
    private bool disposed;

    public string BatPath { get; }

    public EngineClient(string batPath)
    {
        if (string.IsNullOrWhiteSpace(batPath))
            throw new EngineException("Choose the hwid.bat file that belongs to HWID Checker.");
        BatPath = Path.GetFullPath(batPath);
        if (!File.Exists(BatPath))
            throw new EngineException("The linked hwid.bat file could not be found. Keep it beside the desktop app or choose its location.");
    }

    public Task<JsonElement> ScanAsync(IProgress<BridgeProgress>? progress, CancellationToken ct)
        => RunAsync("Scan", null, null, progress, ct);

    public Task<JsonElement> CompareAsync(string previousPath, JsonElement currentInventory, CancellationToken ct)
    {
        RequireInventory(currentInventory);
        string path = Path.GetFullPath(previousPath);
        if (!File.Exists(path))
            throw new EngineException("The selected earlier snapshot no longer exists. Select another JSON report.", "ENGINE-02");
        return RunAsync("Compare", currentInventory.Clone(), path, null, ct);
    }

    public Task<JsonElement> ExportAsync(JsonElement inventory, string folder, CancellationToken ct)
    {
        RequireInventory(inventory);
        if (string.IsNullOrWhiteSpace(folder))
            throw new EngineException("Choose a folder for the TXT and JSON reports.", "ENGINE-02");
        return RunAsync("Export", inventory.Clone(), Path.GetFullPath(folder), null, ct);
    }

    private static void RequireInventory(JsonElement inventory)
    {
        if (inventory.ValueKind != JsonValueKind.Object)
            throw new EngineException("Complete a scan before saving or comparing a snapshot.", "ENGINE-02");
    }

    private async Task<JsonElement> RunAsync(string action, JsonElement? inventory, string? argument,
        IProgress<BridgeProgress>? progress, CancellationToken ct)
    {
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (busy)
                throw new EngineException("A scan or report action is already running.", "ENGINE-BUSY");
            busy = true;
        }

        CancellationTokenSource? cancellation = null;
        Process? process = null;
        Task<string>? stderrTask = null;
        string? operationFolder = null;
        List<string> temporaryFiles = new();
        try
        {
            cancellation = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cancellation.CancelAfter(OperationTimeout);
            lock (sync)
            {
                activeCancellation = cancellation;
                if (disposed) cancellation.Cancel();
            }
            CancellationToken token = cancellation.Token;
            token.ThrowIfCancellationRequested();
            if (!File.Exists(BatPath))
                throw new EngineException("The linked hwid.bat file is missing. Choose its location and try again.");

            string localRoot = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localRoot)) localRoot = Path.GetTempPath();
            operationFolder = Path.Combine(localRoot, "HWIDChecker", "Desktop", "Work", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(operationFolder);
            string bridgePath = Path.Combine(operationFolder, "DesktopBridge.ps1");
            temporaryFiles.Add(bridgePath);
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(BridgeResource)
                ?? throw new EngineException("The desktop engine bridge is missing from this build. Reinstall the complete desktop app."))
            using (StreamReader reader = new(resource, Utf8, detectEncodingFromByteOrderMarks: true))
            {
                string bridge = await reader.ReadToEndAsync(token).ConfigureAwait(false);
                // Windows PowerShell 5.1 needs a BOM to read non-ASCII script literals reliably.
                await File.WriteAllTextAsync(bridgePath, bridge, new UTF8Encoding(true), token).ConfigureAwait(false);
            }

            string? requestPath = null;
            if (inventory.HasValue)
            {
                string currentPath = Path.Combine(operationFolder, "current.json");
                temporaryFiles.Add(currentPath);
                await File.WriteAllTextAsync(currentPath, inventory.Value.GetRawText(), Utf8, token).ConfigureAwait(false);
                object request = action == "Compare"
                    ? new { previousPath = argument, currentPath }
                    : new { inventoryPath = currentPath, folder = argument };
                requestPath = Path.Combine(operationFolder, "request.json");
                temporaryFiles.Add(requestPath);
                await File.WriteAllTextAsync(requestPath, JsonSerializer.Serialize(request), Utf8, token).ConfigureAwait(false);
            }

            token.ThrowIfCancellationRequested();
            process = StartBridge(action, bridgePath, requestPath, operationFolder);
            lock (sync) activeProcess = process;
            using CancellationTokenRegistration registration = token.Register(() => StopOwnedProcess(process));
            stderrTask = DrainErrorAsync(process.StandardError, token);
            JsonElement? result = null;
            EngineException? reportedError = null;
            while (true)
            {
                string? line = await process.StandardOutput.ReadLineAsync(token).ConfigureAwait(false);
                if (line is null) break;
                line = line.TrimStart('\uFEFF');
                if (string.IsNullOrWhiteSpace(line)) continue;
                if (line.Length > MaximumProtocolLine)
                    throw ProtocolFailure("The engine response exceeded the supported size.");

                using JsonDocument message = ParseMessage(line);
                JsonElement root = message.RootElement;
                switch (Text(root, "type").ToLowerInvariant())
                {
                    case "progress":
                        if (result.HasValue) throw ProtocolFailure("The engine sent progress after its completed result.");
                        int total = Math.Max(1, Number(root, "total", 18));
                        BridgeProgress update = new(Text(root, "section"), Text(root, "name"),
                            Math.Clamp(Number(root, "completed"), 0, total), total,
                            Text(root, "status"), Math.Max(0, Number(root, "records")), Text(root, "message"));
                        // A closed UI or failed display callback must not discard a valid scan.
                        try { progress?.Report(update); } catch (Exception) { }
                        break;
                    case "result":
                        if (result.HasValue || !Property(root, "data", out JsonElement data)
                            || data.ValueKind != JsonValueKind.Object)
                            throw ProtocolFailure("The engine did not return one complete result object.");
                        result = data.Clone();
                        break;
                    case "error":
                        reportedError ??= new EngineException(
                            Diagnostic(Text(root, "message"), "The hardware engine could not finish this action."),
                            Diagnostic(Text(root, "code"), "ENGINE-03"));
                        break;
                    default:
                        throw ProtocolFailure("The engine returned an unsupported response.");
                }
            }
            await process.WaitForExitAsync(token).ConfigureAwait(false);
            string stderr = await stderrTask.ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (reportedError is not null) throw reportedError;
            if (process.ExitCode != 0)
                throw new EngineException(Diagnostic(stderr,
                    "The hardware engine closed before finishing. Check that PowerShell can run the linked BAT checker."), "ENGINE-04");
            if (!result.HasValue)
                throw ProtocolFailure("The hardware engine closed without a completed result. The previous snapshot remains available.");
            ValidateResult(action, result.Value);
            return result.Value;
        }
        catch (OperationCanceledException ex) when (!ct.IsCancellationRequested && !IsDisposed())
        {
            throw new EngineException("The engine exceeded the ten-minute limit. Try the scan again or open the BAT console for provider details.",
                "ENGINE-TIMEOUT", ex);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (EngineException)
        {
            throw;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Win32Exception)
        {
            throw new EngineException(Diagnostic(ex.Message, "The engine could not access its local working files."), "ENGINE-IO", ex);
        }
        finally
        {
            if (process is not null)
            {
                StopOwnedProcess(process);
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); }
                catch (Exception) { }
                if (stderrTask is not null)
                {
                    try { await stderrTask.WaitAsync(TimeSpan.FromSeconds(2)).ConfigureAwait(false); }
                    catch (Exception) { }
                }
                process.Dispose();
            }
            if (operationFolder is not null)
            {
                foreach (string file in temporaryFiles) DeleteOwnedFile(file, operationFolder);
                // Refuse recursive cleanup: unexpected contents must never be removed.
                try { Directory.Delete(operationFolder, recursive: false); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            lock (sync)
            {
                activeProcess = null;
                activeCancellation = null;
                busy = false;
            }
            cancellation?.Dispose();
        }
    }

    private Process StartBridge(string action, string bridgePath, string? requestPath, string operationFolder)
    {
        Exception? lastStartFailure = null;
        foreach (string executable in PowerShellCandidates())
        {
            ProcessStartInfo start = new(executable)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                StandardOutputEncoding = Utf8,
                StandardErrorEncoding = Utf8,
                WorkingDirectory = operationFolder
            };
            foreach (string value in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", bridgePath, "-Action", action, "-BatPath", BatPath }) start.ArgumentList.Add(value);
            if (requestPath is not null)
            {
                start.ArgumentList.Add("-RequestPath");
                start.ArgumentList.Add(requestPath);
            }
            foreach (string name in new[] { "HWID_OWN_CONSOLE", "HWID_CURRENT_WINDOW", "HWID_STARTUP_SIGNAL" })
                start.Environment.Remove(name);
            start.Environment["HWID_SCRIPT"] = BatPath;
            Process child = new() { StartInfo = start };
            try
            {
                if (!child.Start()) throw new Win32Exception("PowerShell could not be started.");
                try { child.StandardInput.Close(); } catch (IOException) { }
                return child;
            }
            catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
            {
                lastStartFailure = ex;
                child.Dispose();
            }
        }
        throw new EngineException("Windows PowerShell 5.1 or PowerShell 7 could not be started. Install or enable an approved PowerShell runtime and try again.",
            "ENGINE-RUNTIME", lastStartFailure);
    }

    private static IEnumerable<string> PowerShellCandidates()
    {
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        List<string> paths = new();
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string system = Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32";
        paths.Add(Path.Combine(windows, system, "WindowsPowerShell", "v1.0", "powershell.exe"));
        paths.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"));
        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            try { if (!string.IsNullOrWhiteSpace(directory)) paths.Add(Path.Combine(directory.Trim('"'), "pwsh.exe")); }
            catch (ArgumentException) { }
        }
        foreach (string path in paths)
            if (seen.Add(path) && File.Exists(path)) yield return path;
    }

    private static async Task<string> DrainErrorAsync(StreamReader reader, CancellationToken token)
    {
        StringBuilder text = new();
        char[] buffer = new char[2048];
        try
        {
            while (true)
            {
                int read = await reader.ReadAsync(buffer.AsMemory(), token).ConfigureAwait(false);
                if (read == 0) break;
                int keep = Math.Min(read, DiagnosticLimit - text.Length);
                if (keep > 0) text.Append(buffer, 0, keep);
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        return text.ToString();
    }

    private static JsonDocument ParseMessage(string line)
    {
        try
        {
            JsonDocument document = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 128 });
            if (document.RootElement.ValueKind == JsonValueKind.Object) return document;
            document.Dispose();
        }
        catch (JsonException) { }
        throw ProtocolFailure("The engine returned unreadable data. Open the BAT console to inspect its startup messages.");
    }

    private static bool Property(JsonElement root, string name, out JsonElement value)
    {
        if (root.ValueKind == JsonValueKind.Object)
        {
            if (root.TryGetProperty(name, out value)) return true;
            foreach (JsonProperty property in root.EnumerateObject())
                if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase)) { value = property.Value; return true; }
        }
        value = default;
        return false;
    }

    private static string Text(JsonElement root, string name)
        => Property(root, name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? "" : "";

    private static int Number(JsonElement root, string name, int fallback = 0)
    {
        if (!Property(root, name, out JsonElement value) || value.ValueKind != JsonValueKind.Number) return fallback;
        if (value.TryGetInt32(out int number)) return number;
        if (value.TryGetDouble(out double floating) && double.IsFinite(floating))
            return (int)Math.Clamp(floating, int.MinValue, int.MaxValue);
        return fallback;
    }

    private static EngineException ProtocolFailure(string message) => new(message, "ENGINE-PROTOCOL");

    private static void ValidateResult(string action, JsonElement data)
    {
        bool IsKind(string name, JsonValueKind kind)
            => Property(data, name, out JsonElement item) && item.ValueKind == kind;
        bool valid = action switch
        {
            "Scan" => IsKind("inventory", JsonValueKind.Object)
                && Property(data, "inventory", out JsonElement inventory)
                && Property(inventory, "Report info", out JsonElement info) && info.ValueKind == JsonValueKind.Object
                && IsKind("identifiers", JsonValueKind.Array) && IsKind("warnings", JsonValueKind.Array)
                && IsKind("review", JsonValueKind.Object),
            "Compare" => IsKind("changes", JsonValueKind.Array) && IsKind("previousCount", JsonValueKind.Number)
                && IsKind("currentCount", JsonValueKind.Number),
            "Export" => !string.IsNullOrWhiteSpace(Text(data, "textPath"))
                && !string.IsNullOrWhiteSpace(Text(data, "jsonPath")) && !string.IsNullOrWhiteSpace(Text(data, "folder")),
            _ => false
        };
        if (!valid) throw ProtocolFailure("The engine response is incomplete. The previous snapshot remains available; try this action again.");
    }

    private static string Diagnostic(string text, string fallback)
    {
        if (string.IsNullOrWhiteSpace(text)) return fallback;
        text = text.Replace('\0', ' ').Trim();
        return text.Length <= DiagnosticLimit ? text : text[..DiagnosticLimit] + "…";
    }

    private bool IsDisposed() { lock (sync) return disposed; }

    private static void StopOwnedProcess(Process process)
    {
        try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
        catch (InvalidOperationException) { }
        catch (Win32Exception) { }
    }

    private static void DeleteOwnedFile(string file, string operationFolder)
    {
        string expectedParent = Path.GetFullPath(operationFolder).TrimEnd(Path.DirectorySeparatorChar);
        if (!string.Equals(Path.GetDirectoryName(Path.GetFullPath(file)), expectedParent, StringComparison.OrdinalIgnoreCase)) return;
        try { File.Delete(file); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public void Dispose()
    {
        CancellationTokenSource? cancellation;
        Process? process;
        lock (sync)
        {
            if (disposed) return;
            disposed = true;
            cancellation = activeCancellation;
            process = activeProcess;
        }
        try { cancellation?.Cancel(); } catch (ObjectDisposedException) { }
        if (process is not null) StopOwnedProcess(process);
    }
}
