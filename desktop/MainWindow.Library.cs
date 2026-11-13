using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace HwidDesktop;

public partial class MainWindow
{
    private IReadOnlyList<SnapshotEntry> _snapshotEntries = Array.Empty<SnapshotEntry>();

    private void DisconnectEngine()
    {
        _engine?.Dispose(); _engine = null;
        EngineConnectionText.Text = "BAT not connected";
        EngineConnectionText.ToolTip = null;
        EngineVersionText.Text = "Connect or restore the scanner";
        FooterText.Text = "Scanner unavailable · Open BAT console can restore a bundled copy";
        FooterText.ToolTip = null;
        UpdateButtons();
    }

    private static void ReplaceFilteredRows<T>(DataGrid grid, IReadOnlyList<T> rows)
    {
        if (ReferenceEquals(grid.ItemsSource, rows)) return;
        var sorting = grid.Items.SortDescriptions.ToArray();
        grid.ItemsSource = rows;
        if (!grid.Items.SortDescriptions.SequenceEqual(sorting))
        {
            using (grid.Items.DeferRefresh())
            {
                grid.Items.SortDescriptions.Clear();
                foreach (var sort in sorting) grid.Items.SortDescriptions.Add(sort);
            }
        }
    }

    private void OnSnapshotSearchChanged(object sender, TextChangedEventArgs e) { if (_initialized) FilterSnapshots(); }
    private void OnCompareSearchChanged(object sender, TextChangedEventArgs e) { if (_initialized) FilterComparison(); }
    private void OnCompareFilterChanged(object sender, SelectionChangedEventArgs e) { if (_initialized) FilterComparison(); }

    private void FilterSnapshots()
    {
        if (!_initialized) return;
        var selected = (SnapshotsGrid.SelectedItem as SnapshotEntry)?.Path;
        var needle = SnapshotSearch.Text.Trim();
        var rows = needle.Length == 0 ? _snapshotEntries : _snapshotEntries.Where(row => row.MatchesSearch(needle)).ToArray();
        ReplaceFilteredRows(SnapshotsGrid, rows);
        SnapshotsGrid.SelectedItem = rows.FirstOrDefault(row => row.Path.Equals(selected, StringComparison.OrdinalIgnoreCase));
        UpdateSnapshotCount();
        UpdateButtons();
    }

    private void UpdateSnapshotCount()
    {
        SetSummary(SnapshotCountText, (_snapshotCatalogRefreshing ? "Refreshing… · " : "") + $"{SnapshotsGrid.Items.Count} shown · {_snapshotEntries.Count} saved snapshots" +
            (_snapshotCatalogSkipped > 0 ? $" · {_snapshotCatalogSkipped} files/folders skipped" : ""),
            "Newest capture first by default. Preview entries are validated again before comparison. " +
            "Use Folder settings to see or change the local report locations. Existing rows remain available while refreshing. " +
            "Snapshots contain full identifiers; files in synced folders may be uploaded by that service.");
    }

    private bool HasComparisonFilter => CompareSearch.Text.Trim().Length > 0 || CompareFilter.SelectedIndex > 0;
    private void FilterComparison()
    {
        if (!_initialized) return;
        var selected = CompareGrid.SelectedItem as ChangeRow;
        var needle = CompareSearch.Text.Trim();
        var kind = CompareFilter.SelectedIndex switch { 1 => "Changed", 2 => "Current only", 3 => "Previous only", _ => "" };
        var rows = (_lastComparisonRows ?? Array.Empty<ChangeRow>()).Where(row =>
            (kind.Length == 0 || row.Kind == kind) &&
            (needle.Length == 0 || row.MatchesSearch(needle))).ToArray();
        ReplaceFilteredRows(CompareGrid, rows);
        CompareGrid.SelectedItem = rows.Contains(selected) ? selected : null;
        if (CompareGrid.SelectedItem == null) CompareDetail.Text = _lastComparisonRows == null ? "" :
            rows.Length == 0 ? _lastComparisonNotes : "Select a difference to read its complete previous/current values and exact changed characters.";
        UpdateEmptyStates();
    }

    private async void OnCompareSavedSelected(object sender, RoutedEventArgs e)
    {
        if (_busy || _engine == null) return;
        if (SnapshotsGrid.SelectedItem is not SnapshotEntry row)
        {
            OnChooseTwoFileComparison(sender, e); return;
        }
        await ChooseSecondSnapshotAsync(row.Path);
    }

    private async Task ChooseSecondSnapshotAsync(string previous)
    {
        var picker = new Microsoft.Win32.OpenFileDialog { Title = "Choose the CURRENT saved snapshot to compare with " + Path.GetFileName(previous),
            Filter = "HWID JSON snapshot (*.json)|*.json", CheckFileExists = true };
        var folder = Path.GetDirectoryName(previous);
        if (Directory.Exists(folder)) picker.InitialDirectory = folder;
        if (picker.ShowDialog(this) == true) await CompareFilesAsync(previous, picker.FileName);
    }

    private async Task<string?> ConnectRecoveredScannerAsync(string batPath, string? preferencesPath = null, string? libraryPath = null)
    {
        var settings = libraryPath == null ? ReadSharedLibrary() : SharedSnapshotLibrary.Read(libraryPath);
        var earlierDefault = DefaultReportsFolder;
        var earlierFolders = ReportFolders(settings).ToArray();
        ConnectEngine(batPath);
        if (_engine == null) throw new IOException("The restored scanner could not be connected. Use Connect BAT to choose a complete copy.");
        foreach (var folder in earlierFolders) _additionalFolders.Add(folder);
        var warnings = new List<string>();
        if (Directory.Exists(earlierDefault) && !SameFolder(earlierDefault, DefaultReportsFolder) &&
            (settings.Primary == null || !SameFolder(settings.Primary, earlierDefault)) &&
            !settings.Folders.Concat(BuiltInReportFolders()).Any(folder => SameFolder(folder, earlierDefault)) &&
            (!IsVerification || libraryPath != null || VerificationSharedSettingsPath != null))
        {
            try { await SharedSnapshotLibrary.UpdateAsync("add-folder", earlierDefault, libraryPath ?? VerificationSharedSettingsPath); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException)
            {
                warnings.Add("Earlier reports remain in " + earlierDefault + ". Add this location in Folder settings; automatic registration failed.");
            }
        }
        if (!await RememberPreferencesAsync(preferencesPath))
            warnings.Add("The restored connection could not be saved for the next app launch.");
        return warnings.Count == 0 ? null : string.Join(" ", warnings);
    }

    private async void OnOpenConsole(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SetBusy(true, "Console");
        _operationCancellation = new CancellationTokenSource();
        ShowStatus("Checking the console", "Checking scanner files and PowerShell before opening a separate console.", kind: UiStatusKind.Working);
        try
        {
            var preferred = _engine?.BatPath ?? FindEngine();
            var prepared = await EngineRecovery.PrepareAsync(preferred, EngineClient.PowerShellCandidates(), _operationCancellation.Token);
            using var process = Process.Start(EngineRecovery.StartInfo(prepared, _darkTheme))
                ?? throw new IOException("Windows did not start the console.");
            // A loader can fail before its separate console opens. Retry the bundled
            // pair once; do not loop or kill a console that has already opened.
            await Task.Delay(800, _operationCancellation.Token);
            if (process.HasExited && process.ExitCode != 0)
            {
                if (prepared.Recovered) throw new IOException("The restored console could not start. Check the PowerShell runtime and local policy.");
                prepared = await EngineRecovery.PrepareAsync(null, EngineClient.PowerShellCandidates(), _operationCancellation.Token);
                using var retry = Process.Start(EngineRecovery.StartInfo(prepared, _darkTheme))
                    ?? throw new IOException("Windows did not start the restored console.");
                await Task.Delay(800, _operationCancellation.Token);
                if (retry.HasExited && retry.ExitCode != 0) throw new IOException("The restored console could not start. Check the PowerShell runtime and local policy.");
            }
            string? warning = null;
            if (prepared.Recovered || _engine == null)
            {
                warning = await ConnectRecoveredScannerAsync(prepared.BatPath);
            }
            ShowStatus(prepared.Recovered ? "Console restored and started" : "Console started",
                (prepared.Recovered ? "Using the bundled offline scanner. Custom files and saved reports were kept. Open Snapshots for captures from both scanner locations." :
                "A separate console is starting. Its scan progress appears in that window.") +
                (warning == null ? "" : " " + warning),
                kind: warning == null ? UiStatusKind.Success : UiStatusKind.Review);
        }
        catch (OperationCanceledException) { ShowStatus("Console check cancelled", "Your current scan and saved snapshots are unchanged."); }
        catch (Exception error) { ShowError("Could not open the BAT console", error); }
        finally { SetBusy(false); _operationCancellation?.Dispose(); _operationCancellation = null; }
    }
}
