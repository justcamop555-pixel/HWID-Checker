using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace HwidDesktop;

internal sealed record UpdateStatus(
    string State,
    string Message,
    string LatestVersion = "",
    string ReleaseUrl = "",
    string StageDirectory = "",
    string BatVersion = "",
    string SourceVersion = "");

internal sealed class DesktopUpdater : IDisposable
{
    // Package releases use major.minor.patch. File metadata can add a revision.
    internal static readonly string CurrentVersion =
        NormalizePackageVersion(Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(1, 0, 0)).ToString(3);

    internal static Version NormalizePackageVersion(Version value) =>
        new(value.Major, value.Minor, Math.Max(0, value.Build));

    internal static bool IsNewerPackageVersion(Version candidate, Version current) =>
        NormalizePackageVersion(candidate) > NormalizePackageVersion(current);

    internal static Version? ReadInstalledPackageVersion(string executablePath)
    {
        var fullPath = Path.GetFullPath(executablePath);
        if (!File.Exists(fullPath)) return null;
        var nativePath = fullPath.StartsWith(@"\\?\", StringComparison.Ordinal) ? fullPath :
            fullPath.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + fullPath[2..] : @"\\?\" + fullPath;
        var info = FileVersionInfo.GetVersionInfo(nativePath);
        return string.IsNullOrWhiteSpace(info.FileVersion) ? null :
            new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart);
    }
    private readonly string _directory;
    private readonly string _script;
    private readonly string _resultPath;
    private readonly string _preferences;
    private CancellationTokenSource? _cancellation;
    private bool _disposed;

    public event EventHandler? Changed;
    public UpdateStatus Status { get; private set; } = new("idle", "Updates have not been checked yet.");
    public bool IsBusy => _cancellation != null;
    public bool AutomaticEnabled { get; private set; }
    public bool IsReady => CanApply(Status);

    private static bool CanApply(UpdateStatus status)
    {
        var current = Version.Parse(CurrentVersion);
        return status.State is "ready" or "repair" && status.StageDirectory.Length > 0 &&
            TryPackageVersion(status.SourceVersion, out var source) &&
            TryPackageVersion(status.LatestVersion, out var next) &&
            source < next && source <= current &&
            (next > current || status.State == "repair" && next == current);
    }

    private static bool TryPackageVersion(string value, out Version version)
    {
        if (Version.TryParse(value, out var parsed) && parsed.Build >= 0 && parsed.Revision == -1 &&
            parsed.ToString(3) == value)
        {
            version = parsed;
            return true;
        }
        version = new Version(0, 0, 0);
        return false;
    }

    public DesktopUpdater(string directory, string? updatesRoot = null)
    {
        _directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        _script = Path.Combine(_directory, "Update-HWID.ps1");
        var root = updatesRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HWID Checker", "Updates");
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(_directory.TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant())))[..16].ToLowerInvariant();
        _resultPath = Path.Combine(root, key + "-package", "result.json");
        _preferences = Path.Combine(root, "preferences.json");
        AutomaticEnabled = ReadAutomaticPreference();
        ReadCachedStatus();
        RefreshInstalledVersion();
    }

    public async Task PrepareAutomaticallyAsync()
    {
        if (!AutomaticEnabled || _disposed) return;
        if (Status.State == "repair" || RefreshInstalledVersion()) return;
        if (File.Exists(_resultPath))
        {
            var age = DateTime.UtcNow - File.GetLastWriteTimeUtc(_resultPath);
            var interval = Status.State == "error" ? TimeSpan.FromHours(1) : TimeSpan.FromDays(1);
            if (age >= TimeSpan.Zero && age < interval && Status.State is "current" or "ready" or "error")
                return;
        }
        await RunAsync("Prepare");
    }

    public Task CheckAsync() => RunAsync("Check");
    public Task DownloadAsync() => RunAsync("Prepare");
    public void RefreshAutomaticPreference() => AutomaticEnabled = ReadAutomaticPreference();

    public void SetAutomatic(bool enabled)
    {
        var folder = Path.GetDirectoryName(_preferences)!;
        Directory.CreateDirectory(folder);
        var temporary = _preferences + ".pending-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllBytes(temporary, JsonSerializer.SerializeToUtf8Bytes(new { automaticUpdates = enabled }));
            if (File.Exists(_preferences)) File.Replace(temporary, _preferences, null);
            else File.Move(temporary, _preferences);
            AutomaticEnabled = enabled;
            Notify();
        }
        finally
        {
            try { File.Delete(temporary); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }

    private bool ReadAutomaticPreference()
    {
        try
        {
            using var stream = new FileStream(_preferences, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length > 256 * 1024) return false;
            using var reader = new StreamReader(stream, new UTF8Encoding(false, true), true);
            using var json = JsonDocument.Parse(reader.ReadToEnd());
            var root = json.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                root.EnumerateObject().Count(property => property.Name.Equals("automaticUpdates", StringComparison.OrdinalIgnoreCase)) != 1)
                return false;
            return root.TryGetProperty("automaticUpdates", out var enabled) && enabled.ValueKind == JsonValueKind.True;
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return true; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { return false; }
    }

    private void ReadCachedStatus()
    {
        try
        {
            if (!File.Exists(_resultPath) || new FileInfo(_resultPath).Length > 64 * 1024) return;
            using var document = JsonDocument.Parse(File.ReadAllText(_resultPath));
            var result = document.RootElement;
            if (!result.Text("installDirectory").Equals(_directory, StringComparison.OrdinalIgnoreCase) ||
                !result.Text("component").Equals("Package", StringComparison.OrdinalIgnoreCase)) return;
            Status = NormalizeStatus(ParseResult(result), cached: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { }
    }

    private async Task RunAsync(string mode)
    {
        if (_disposed || IsBusy) return;
        if (Status.State == "repair") return;
        if (RefreshInstalledVersion()) { Notify(); return; }
        if (!File.Exists(_script))
        {
            Status = new("error", "The updater is missing. Restore Update-HWID.ps1 from the complete package.");
            Notify();
            return;
        }
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        _cancellation = cancellation;
        Status = new("checking", mode == "Prepare" ? "Checking and preparing a newer package…" : "Checking published versions…");
        Notify();
        Process? process = null;
        try
        {
            var start = CreateStart(_script, mode);
            Directory.CreateDirectory(Path.GetDirectoryName(_resultPath)!);
            AddArguments(start, "-ResultPath", _resultPath);
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            start.StandardOutputEncoding = Encoding.UTF8;
            start.StandardErrorEncoding = Encoding.UTF8;
            process = Process.Start(start) ?? throw new IOException("The updater process could not start.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            try { await process.WaitForExitAsync(cancellation.Token); }
            catch (OperationCanceledException)
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync();
                await Task.WhenAll(stdout, stderr);
                throw;
            }
            var text = await stdout;
            await stderr;
            if (text.Length > 64 * 1024) throw new InvalidDataException("The updater returned too much output.");
            using var document = JsonDocument.Parse(text);
            if (!document.RootElement.Text("installDirectory").Equals(_directory, StringComparison.OrdinalIgnoreCase) ||
                !document.RootElement.Text("component").Equals("Package", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The updater returned a result for another application folder.");
            Status = NormalizeStatus(ParseResult(document.RootElement), cached: false);
            if (process.ExitCode != 0 && Status.State is not ("error" or "busy"))
                Status = new("error", "The update action did not finish. Try again from this window.");
            RefreshInstalledVersion();
        }
        catch (OperationCanceledException) { Status = new("idle", "Update preparation stopped. You can try again later."); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Status = new("error", "Could not check or prepare the update. " + error.Message);
        }
        finally
        {
            process?.Dispose();
            _cancellation = null;
            Notify();
        }
    }

    private static UpdateStatus ParseResult(JsonElement result) => new(
        result.Text("state"), result.Text("message"), result.Text("latestVersion"),
        result.Text("releaseUrl"), result.Text("stageDirectory"), result.Text("batVersion"), result.Text("currentVersion"));

    private static UpdateStatus RunningStatus() =>
        new("idle", "Desktop " + CurrentVersion + " is running. Choose Check now to look for newer releases.",
            CurrentVersion, SourceVersion: CurrentVersion);

    private UpdateStatus NormalizeStatus(UpdateStatus status, bool cached)
    {
        var current = Version.Parse(CurrentVersion);
        if (status.State == "ready")
        {
            if (!TryPackageVersion(status.LatestVersion, out var next)) return RunningStatus();
            if (next == current && HasInterruptedTransaction(status.LatestVersion))
                status = status with { State = "repair", Message = "An interrupted update is ready to finish after the app closes." };
            return CanApply(status) ? status : RunningStatus();
        }
        if (!TryPackageVersion(status.SourceVersion, out var source) || source != current)
            return RunningStatus();
        if (status.State is "available" or "current" or "updated" or "restart")
        {
            if (!Version.TryParse(status.LatestVersion, out var next) || next.Build < 0)
                return RunningStatus();
            var normalized = NormalizePackageVersion(next);
            if (status.State == "available" && normalized > current)
                return status with { LatestVersion = normalized.ToString(3) };
            if (status.State == "current" && normalized <= current)
                return status with { LatestVersion = normalized.ToString(3) };
            if (!cached && normalized <= current)
                return new("current", "Desktop " + CurrentVersion + " is running. This result contains no newer package.",
                    CurrentVersion, SourceVersion: CurrentVersion);
            return RunningStatus();
        }
        return status.State is "error" or "busy" ? status : RunningStatus();
    }

    private bool RefreshInstalledVersion()
    {
        try
        {
            var installed = ReadInstalledPackageVersion(Path.Combine(_directory, "HWID Checker.exe"));
            if (installed == null || !IsNewerPackageVersion(installed, Version.Parse(CurrentVersion)))
            {
                if (Status.State == "restart") Status = RunningStatus();
                return false;
            }
            if (HasInterruptedTransaction(installed.ToString(3)) && IsReady) return false;
            Status = new("restart", "Desktop " + installed.ToString(3) +
                " is installed, and this window is running Desktop " + CurrentVersion +
                ". Close and reopen the app to use the installed version.",
                installed.ToString(3), SourceVersion: CurrentVersion);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException) { return false; }
    }

    private bool HasInterruptedTransaction(string version)
    {
        try
        {
            foreach (var folder in Directory.EnumerateDirectories(_directory, ".hwid-update-*").Take(256))
            {
                if (!System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(folder), @"\A\.hwid-update-[a-f0-9]{32}\z") ||
                    (File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0 ||
                    File.Exists(Path.Combine(folder, "completed.json")) || File.Exists(Path.Combine(folder, "recovered.json"))) continue;
                var journal = Path.Combine(folder, "transaction.json");
                if (!File.Exists(journal) || new FileInfo(journal).Length > 256 * 1024) continue;
                using var json = JsonDocument.Parse(File.ReadAllText(journal));
                var transaction = json.RootElement;
                if (transaction.Number("schema") == 1 && transaction.Text("state") == "active" &&
                    transaction.Text("component") == "Package" && transaction.Text("version") == version &&
                    transaction.Text("installDirectory").Equals(_directory, StringComparison.OrdinalIgnoreCase)) return true;
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { }
        return false;
    }

    private ProcessStartInfo CreateStart(string script, string mode, string? sourceVersion = null)
    {
        var runtime = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(runtime)) runtime = "pwsh.exe";
        var start = new ProcessStartInfo(runtime)
        {
            UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = _directory
        };
        AddArguments(start, "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
            "-Mode", mode, "-InstallDirectory", _directory, "-CurrentVersion", sourceVersion ?? CurrentVersion, "-Component", "Package");
        return start;
    }

    public bool ScheduleApply(bool relaunch)
    {
        if (!IsReady || IsBusy || !File.Exists(_script)) return false;
        var helperFolder = Path.Combine(Path.GetDirectoryName(_resultPath)!, "helper-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(helperFolder);
        var helper = Path.Combine(helperFolder, "Update-HWID.ps1");
        File.Copy(_script, helper);
        var start = CreateStart(helper, "Apply", Status.SourceVersion);
        using var current = Process.GetCurrentProcess();
        AddArguments(start, "-StageDirectory", Status.StageDirectory,
            "-WaitProcessId", current.Id.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "-WaitProcessStartTicks", current.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "-ResultPath", _resultPath);
        if (relaunch) start.ArgumentList.Add("-Relaunch");
        using var launched = Process.Start(start) ?? throw new IOException("The update installer could not start.");
        return true;
    }

    private static void AddArguments(ProcessStartInfo start, params string[] values)
    {
        foreach (var value in values) start.ArgumentList.Add(value);
    }

    private void Notify() => Changed?.Invoke(this, EventArgs.Empty);
    public void Cancel() => _cancellation?.Cancel();
    public void Dispose()
    {
        _disposed = true;
        Cancel();
    }
}
