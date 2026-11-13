using System.Windows;
using System.IO;
using System.Text.Json;
using System.Diagnostics;
using System.Windows.Threading;

namespace HwidDesktop;
public partial class App : Application
{
    private readonly Stopwatch _startupClock = Stopwatch.StartNew();
    private readonly long _startupEpoch = Stopwatch.GetTimestamp();
    private readonly Dictionary<string, long> _startupPhases = [];
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            if (WriteAutomationFailure(e.Args, args.Exception)) { args.Handled = true; Shutdown(1); return; }
            MessageBox.Show("The desktop app could not finish this action.\n\n" + args.Exception.Message,
                "HWID Checker", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
        try
        {
            // Keep automation/restart handoffs unchanged. A normal cold launch
            // paints a small window before reading settings or building the dashboard.
            if (UseStartupWindow(e.Args))
            {
                var loading = new StartupWindow(); MainWindow = loading;
                loading.ContentRendered += async (_, _) =>
                {
                    if (!loading.BeginPreparation()) return;
                    _startupPhases["loadingRenderedMs"] = _startupClock.ElapsedMilliseconds;
                    await PrepareDashboardAsync(loading, e.Args);
                };
                loading.Show(); return;
            }
            var window = new MainWindow(e.Args);
            MainWindow = window;
            window.Show();
        }
        catch (Exception ex)
        {
            if (!WriteAutomationFailure(e.Args, ex)) MessageBox.Show("HWID Checker could not start.\n\n" + ex.Message, "HWID Checker", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    private static bool UseStartupWindow(string[] args) => args.Any(x => x.Split('=', 2)[0] == "--startup-test") ||
        !HwidDesktop.MainWindow.IsVerificationLaunch(args) && !args.Any(x => x.Split('=', 2)[0] == "--restart-pipe");

    private static string? Value(string[] args, string name)
    {
        var inline = args.FirstOrDefault(value => value.StartsWith(name + "=", StringComparison.Ordinal));
        if (inline != null) return inline[(name.Length + 1)..];
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    private async Task PrepareDashboardAsync(StartupWindow loading, string[] args)
    {
        try
        {
            await Dispatcher.Yield(DispatcherPriority.Background);
            loading.SetStep("Reading local settings…");
            var test = Value(args, "--startup-test") != null;
            if (test && int.TryParse(Value(args, "--startup-delay-ms"), out var delay) && delay is > 0 and <= 5000)
                await Task.Delay(delay, loading.Cancellation);
            var path = test ? Value(args, "--startup-settings") : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HWID Checker", "Desktop", "settings.json");
            var preferences = await StartupPreparation.ReadPreferencesAsync(path, loading.Cancellation);
            if (loading.Cancellation.IsCancellationRequested) return;
            _startupPhases["preferencesReadMs"] = _startupClock.ElapsedMilliseconds;
            loading.SetStep("Opening your dashboard…");
            await Dispatcher.Yield(DispatcherPriority.Background);
            if (loading.Cancellation.IsCancellationRequested) return;
            var window = new MainWindow(args, preferences);
            _startupPhases["dashboardBuiltMs"] = _startupClock.ElapsedMilliseconds;
            window.ContentRendered += (_, _) => _startupPhases.TryAdd("dashboardRenderedMs", _startupClock.ElapsedMilliseconds);
            MainWindow = window;
            window.Show(); loading.Close();
        }
        catch (OperationCanceledException) when (loading.Cancellation.IsCancellationRequested) { }
        catch (Exception error)
        {
            if (!WriteAutomationFailure(args, error)) MessageBox.Show("HWID Checker could not start.\n\n" + error.Message,
                "HWID Checker", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    internal Task WriteStartupResultAsync(string path, bool scannerConnected)
    {
        _startupPhases["scannerReadyMs"] = _startupClock.ElapsedMilliseconds;
        return File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = scannerConnected,
            phases = _startupPhases, measurementStartedTimestamp = _startupEpoch, measurementFrequency = Stopwatch.Frequency,
            hardwareIdentifiersSaved = false, startupLoadingShown = _startupPhases.ContainsKey("loadingRenderedMs") }));
    }
    private static bool WriteAutomationFailure(string[] args, Exception error)
    {
        for (var i = 0; i + 1 < args.Length; i++)
            if (args[i] is "--verify" or "--scan-test" or "--restart-result" or "--startup-test")
            {
                var layoutFailure = error.Message.StartsWith("Dashboard layout:", StringComparison.Ordinal) ? error.Message : null;
                try { File.WriteAllText(args[i + 1], JsonSerializer.Serialize(new { success = false, errorType = error.GetType().FullName, layoutFailure, hardwareIdentifiersSaved = false })); } catch { }
                return true;
            }
        return false;
    }
}
