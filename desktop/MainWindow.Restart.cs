using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private bool _restartReceiving, _restartChildAborted;
    private CancellationTokenSource? _restartRestoreCancellation;
    private JsonElement? _comparisonResumeData;
    private string _comparisonResumePrevious = "";
    private string? _comparisonResumeCurrent;
    private bool _comparisonResumeLive;
    private string? _restartSelectedSnapshotPath;

    private JsonElement CaptureRestartState() => JsonSerializer.SerializeToElement(new
    {
        version = 1, parentId = Environment.ProcessId,
        parentStartTicks = RestartParentStartTicks(),
        engine = _engine?.BatPath, snapshot = _snapshot?.Data, page = _page, dark = _darkTheme,
        welcomeSeen = _welcomeSeen, showWelcomeOnStartup = _showWelcomeOnStartup,
        width = WindowState == WindowState.Normal ? ActualWidth : RestoreBounds.Width,
        height = WindowState == WindowState.Normal ? ActualHeight : RestoreBounds.Height,
        maximized = WindowState == WindowState.Maximized,
        idSearch = IdSearch.Text, idFilter = IdFilter.SelectedIndex, idSelection = IdentifiersGrid.SelectedIndex,
        reviewSearch = ReviewSearch.Text, reviewKind = ReviewFilter.SelectedIndex, reviewSelection = ReviewGrid.SelectedIndex, hardwareSearch = HardwareSearch.Text,
        hardwareSection = (HardwareSections.SelectedItem as HardwareSection)?.Name,
        hardwareRecord = (HardwareRecord.SelectedItem as HardwareRecord)?.Index ?? -1,
        hardwareField = HardwareFields.SelectedIndex, comparisonSelection = CompareGrid.SelectedIndex,
        snapshotPath = (SnapshotsGrid.SelectedItem as SnapshotEntry)?.Path, scrollOffset = PageScrollViewer()?.VerticalOffset ?? 0,
        snapshotSearch = SnapshotSearch.Text, compareSearch = CompareSearch.Text, compareFilter = CompareFilter.SelectedIndex,
        lastSaveFolder = _lastSaveFolder, additionalFolders = _additionalFolders.ToArray(),
        comparison = _comparisonResumeData, previousPath = _comparisonResumePrevious,
        currentPath = _comparisonResumeCurrent, liveComparison = _comparisonResumeLive
    });

    private static long RestartParentStartTicks()
    {
        using var process = Process.GetCurrentProcess();
        return process.StartTime.ToUniversalTime().Ticks;
    }

    private async Task<bool> RestartDesktopAsync(string? verificationResult = null)
    {
        if (_busy || _closing || _closeRequested) return false;
        if (!IsVerification && _updater?.IsReady == true)
        {
            ShowStatus("An update is ready", "Open Updates to install it. Save this scan first if you need to keep it.", true);
            OnOpenUpdates(this, new RoutedEventArgs());
            return false;
        }
        var state = CaptureRestartState();
        SetBusy(true, "Restart");
        _operationCancellation = new CancellationTokenSource();
        ShowStatus("Restarting the desktop", "Opening a replacement window and keeping your current scan and view.", kind: UiStatusKind.Working);
        try
        {
            var executable = Environment.ProcessPath ?? throw new IOException("The desktop executable could not be located.");
            var extra = verificationResult == null ? Array.Empty<string>() : new[] { "--restart-result", verificationResult };
            await using var handoff = await RestartHandoff.StartAsync(executable, state, _operationCancellation.Token, extra);
            await handoff.CommitAsync(_operationCancellation.Token);
            _restarting = true;
            SetBusy(false);
            Close();
            return true;
        }
        catch (OperationCanceledException)
        {
            ShowStatus("Restart cancelled", "Your current window and captured results remain available.", true);
            return false;
        }
        catch (Exception error)
        {
            ShowError("Restart could not finish · current window kept", error);
            return false;
        }
        finally
        {
            if (_busy && _operation == "Restart") SetBusy(false);
            _operationCancellation?.Dispose(); _operationCancellation = null;
        }
    }

    private async Task<bool> RestoreDesktopRestartAsync()
    {
        _restartRestoreCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(35));
        var token = _restartRestoreCancellation.Token;
        IsEnabled = false;
        ShowStatus("Restoring your session", "Waiting for the original window to confirm the restart.", kind: UiStatusKind.Working);
        try
        {
            await using var receiver = await RestartHandoff.ConnectAsync(Argument("--restart-pipe")!, token);
            var state = receiver.State;
            if (state.Number("version") != 1 || state.Number("parentId") is not (> 0) || state.Number("parentId") == Environment.ProcessId)
                throw new InvalidDataException("The restart session is invalid.");
            using var parent = Process.GetProcessById(state.Number("parentId"));
            if (!state.Get("parentStartTicks").TryGetInt64(out var ticks) || parent.StartTime.ToUniversalTime().Ticks != ticks)
                throw new InvalidDataException("The original restart process is no longer available.");
            _darkTheme = state.Flag("dark"); ApplyTheme(_darkTheme);
            if (state.Get("welcomeSeen").ValueKind is JsonValueKind.True or JsonValueKind.False) _welcomeSeen = state.Flag("welcomeSeen");
            if (state.Get("showWelcomeOnStartup").ValueKind is JsonValueKind.True or JsonValueKind.False) _showWelcomeOnStartup = state.Flag("showWelcomeOnStartup");
            if (state.Text("engine") is { Length: > 0 } engine)
            {
                ConnectEngine(engine);
                if (_engine == null) throw new IOException("The connected BAT could not be restored.");
            }
            if (state.Get("snapshot").ValueKind == JsonValueKind.Object) ApplySnapshot(new DesktopSnapshot(state.Get("snapshot")));
            _lastSaveFolder = state.Text("lastSaveFolder");
            foreach (var folder in state.Get("additionalFolders").Rows().Select(row => row.Text()))
                if (Path.IsPathFullyQualified(folder)) _additionalFolders.Add(folder);
            IdSearch.Text = state.Text("idSearch"); IdFilter.SelectedIndex = Math.Clamp(state.Number("idFilter"), 0, 2);
            var selection = state.Number("idSelection");
            IdentifiersGrid.SelectedIndex = selection >= 0 && selection < IdentifiersGrid.Items.Count ? selection : -1;
            ReviewSearch.Text = state.Text("reviewSearch");
            ReviewFilter.SelectedIndex = Math.Clamp(state.Number("reviewKind"), 0, 4);
            ReviewGrid.SelectedIndex = state.Number("reviewSelection") is var reviewIndex && reviewIndex >= 0 && reviewIndex < ReviewGrid.Items.Count ? reviewIndex : -1;
            HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().FirstOrDefault(section => section.Name == state.Text("hardwareSection")) ?? HardwareSections.SelectedItem;
            HardwareSearch.Text = state.Text("hardwareSearch");
            HardwareRecord.SelectedItem = HardwareRecord.Items.Cast<HardwareRecord>().FirstOrDefault(record => record.Index == state.Number("hardwareRecord")) ?? HardwareRecord.SelectedItem;
            HardwareFields.SelectedIndex = state.Number("hardwareField") is var fieldIndex && fieldIndex >= 0 && fieldIndex < HardwareFields.Items.Count ? fieldIndex : -1;
            if (state.Get("comparison").ValueKind == JsonValueKind.Object)
                RenderComparison(state.Get("comparison"), state.Text("previousPath"), state.Flag("liveComparison"), state.Text("currentPath"));
            SnapshotSearch.Text = state.Text("snapshotSearch");
            CompareSearch.Text = state.Text("compareSearch"); CompareFilter.SelectedIndex = Math.Clamp(state.Number("compareFilter"), 0, 3);
            CompareGrid.SelectedIndex = state.Number("comparisonSelection") is var changeIndex && changeIndex >= 0 && changeIndex < CompareGrid.Items.Count ? changeIndex : -1;
            _restartSelectedSnapshotPath = state.Text("snapshotPath");
            if (state.Get("width").TryGetDouble(out var width) && double.IsFinite(width)) Width = Math.Clamp(width, MinWidth, Math.Max(MinWidth, SystemParameters.WorkArea.Width - 16));
            if (state.Get("height").TryGetDouble(out var height) && double.IsFinite(height)) Height = Math.Clamp(height, MinHeight, Math.Max(MinHeight, SystemParameters.WorkArea.Height - 16));
            if (state.Flag("maximized")) WindowState = WindowState.Maximized;
            Navigate(state.Text("page")); UpdateButtons(); FitLayout();
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            if (state.Get("scrollOffset").TryGetDouble(out var offset) && double.IsFinite(offset)) PageScrollViewer()?.ScrollToVerticalOffset(Math.Max(0, offset));
            await receiver.ReadyAsync(token);
            await parent.WaitForExitAsync(token);
            _restartReceiving = false;
            IsEnabled = true;
            ShowStatus("Restart complete", _snapshot == null ? "The desktop is ready. Choose Scan this PC to begin." :
                "Your current scan, filters and comparison results have been restored.", kind: UiStatusKind.Success);
            if (Argument("--restart-result") is { } result)
            {
                if (JsonSerializer.Serialize(_snapshot?.Data) != JsonSerializer.Serialize(state.Get("snapshot")) ||
                    _page != state.Text("page") || IdSearch.Text != state.Text("idSearch") ||
                    HardwareSearch.Text != state.Text("hardwareSearch") ||
                    SnapshotSearch.Text != state.Text("snapshotSearch") || CompareSearch.Text != state.Text("compareSearch") ||
                    CompareFilter.SelectedIndex != state.Number("compareFilter") ||
                    IdFilter.SelectedIndex != state.Number("idFilter") || _darkTheme != state.Flag("dark") ||
                    _welcomeSeen != state.Flag("welcomeSeen") || _showWelcomeOnStartup != state.Flag("showWelcomeOnStartup") ||
                    CompareGrid.SelectedIndex != state.Number("comparisonSelection") ||
                    JsonSerializer.Serialize(_comparisonResumeData) != JsonSerializer.Serialize(state.Get("comparison")))
                    throw new InvalidDataException("Restart verification: restored session values differ.");
                await WriteTestResultAsync(result, true);
                Close();
                return false;
            }
            return true;
        }
        catch (Exception error)
        {
            if (Argument("--restart-result") is { } failure)
                await File.WriteAllTextAsync(failure, JsonSerializer.Serialize(new { success = false, errorType = error.GetType().FullName,
                    layoutFailure = "Dashboard layout: restart restore: " + error.Message, hardwareIdentifiersSaved = false }));
            _restartChildAborted = true;
            Close();
            return false;
        }
        finally { _restartRestoreCancellation.Dispose(); _restartRestoreCancellation = null; }
    }

    private async Task VerifyRestartAsync(string path)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("Restart verification requires a synthetic capture.");
        HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().First(section => section.Name == "CPU");
        HardwareSearch.Text = "CPU";
        IdSearch.Text = "CPU"; IdFilter.SelectedIndex = 1;
        IdSearch.Focus();
        using var comparison = JsonDocument.Parse("""{"changes":[{"kind":"Changed","section":"CPU","field":"ProcessorId","device":"CPU0","previous":"OLD-000123","current":"NEW-000124","difference":"last digit changed"}],"previousCount":1,"currentCount":1}""");
        RenderComparison(comparison.RootElement, Path.Combine(Path.GetDirectoryName(path)!, "synthetic-old.json"), true);
        CompareSearch.Text = "CPU"; CompareFilter.SelectedIndex = 1; SnapshotSearch.Text = "synthetic";
        CompareGrid.SelectedIndex = 0;
        _darkTheme = false; ApplyTheme(false);
        _welcomeSeen = true; _showWelcomeOnStartup = true;
        Navigate("Compare");
        if (!await RestartDesktopAsync(path))
        {
            var detail = File.Exists(path) ? await File.ReadAllTextAsync(path) : StatusDetail.Text;
            throw new InvalidOperationException("Dashboard layout: restart verification: " + StatusTitle.Text + ": " + detail);
        }
    }
}
