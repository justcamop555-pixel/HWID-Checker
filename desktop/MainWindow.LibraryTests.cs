using System.IO;
using System.ComponentModel;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private async Task VerifyLibraryAsync(string path)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("Library verification requires a synthetic capture.");
        var checks = new List<string>();
        void Check(bool value, string name) { if (!value) throw new InvalidOperationException("Dashboard layout: library: " + name); checks.Add(name); }
        var originalReviewFilter = ReviewFilter.SelectedIndex;
        foreach (var dpi in new[] { 96.0, 120, 144, 192, 240 })
        {
            var available = WindowBounds.AvailableDip(1920, 1040, dpi);
            Check(Math.Abs((available.Width + 16) * dpi / 96 - 1920) < 0.01 &&
                Math.Abs((available.Height + 16) * dpi / 96 - 1040) < 0.01,
                "monitor work area converts pixels to DIPs exactly once at " + dpi + " DPI");
        }
        var laptop = WindowBounds.AvailableDip(1366, 720, 192);
        Check(laptop.Width == 667 && laptop.Height == 344, "200 percent laptop work area can lower the normal 640 by 480 minimum");
        ReviewSearch.Clear(); ReviewFilter.SelectedIndex = 2;
        Check(ReviewGrid.Items.Cast<ReviewRow>().All(row => row.Kind == "ID review"), "ID review filtering excludes read failures and conflicts");
        ReviewFilter.SelectedIndex = 1;
        Check(ReviewGrid.Items.Cast<ReviewRow>().All(row => row.Kind == "Read error"), "read error filter does not label missing identifiers as failed reads");
        ReviewSearch.Text = "SYNTHETIC-NOTHING-MATCHES";
        OnEmptyStateAction(ReviewEmptyAction, new RoutedEventArgs());
        Check(ReviewFilter.SelectedIndex == 0 && ReviewSearch.Text.Length == 0 && ReviewGrid.Items.Count == _snapshot.Findings.Count,
            "clear review restores both search and kind filters");
        ReviewFilter.SelectedIndex = originalReviewFilter;
        var exactValue = "000123\n" + new string('X', 2400);
        Check(ValueExplanation.Identifier(new("CPU", "CPU identifier", exactValue, "Reported", "CPU0")).Contains(exactValue), "long selected values retain newlines and leading zeros");
        Check(ValueExplanation.Review(new("Conflict", "CPU", "Readings disagree", "Details")).Contains("does not prove spoofing"), "conflict explanations avoid declaring hardware spoofing");
        foreach (var dark in new[] { true, false })
        {
            ApplyTheme(dark);
            var detail = new DetailWindow("Synthetic long value", exactValue, exactValue) { Owner = this, Width = 340, Height = 280 };
            Exception? detailFailure = null;
            detail.Loaded += (_, _) => Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
            {
                try
                {
                    detail.UpdateLayout();
                    var root = (FrameworkElement)detail.Content;
                    var bounds = detail.CloseButton.TransformToAncestor(root).TransformBounds(new Rect(detail.CloseButton.RenderSize));
                    Check(bounds.Bottom <= root.ActualHeight + 1 && bounds.Right <= root.ActualWidth + 1, "detail close button stays visible in compact " + (dark ? "Midnight" : "Daylight"));
                    Check(detail.Details.Text == exactValue && detail.CopyButton.IsEnabled && detail.Details.ActualHeight > 20, "full value remains selectable without hiding actions");
                }
                catch (Exception error) { detailFailure = error; }
                finally { detail.Close(); }
            }));
            detail.ShowDialog(); if (detailFailure != null) throw detailFailure;
        }
        var original = _snapshot;
        using (var coverage = JsonDocument.Parse("""
        {"previousCount":0,"currentCount":0,"skippedFields":2,"skippedSections":["Memory modules"],
         "unkeyedSections":["Memory modules"],"ambiguousDevices":[{"Section":"CPU","DeviceKey":"DeviceID=CPU0","Count":2,"Sources":["Previous"]}],
         "previousComputer":"OLD-PC","currentComputer":"NEW-PC","previousCaptured":"2026-11-12T13:00:00Z","currentCaptured":"2026-11-11T13:00:00Z","changes":[]}
        """))
        {
            RenderComparison(coverage.RootElement, @"C:\Synthetic\before.json", false, @"C:\Synthetic\after.json");
            Check(_lastComparisonNotes.Contains("Missing device matching keys: Memory modules") && !_lastComparisonNotes.Contains("Unread sections:"),
                "missing device matching keys are explained without claiming that readable data was unread");
            Check(_lastComparisonNotes.Contains("Ambiguous device match: CPU / DeviceID=CPU0 / 2 records / Previous") && _comparisonHasGaps,
                "duplicate device keys retain their source, key and count in comparison details and exports");
            Check(_lastComparisonNotes.Contains("Different computer names") && _lastComparisonNotes.Contains("Previous is newer than Current"),
                "cross-computer and reversed-time comparisons explain the chosen direction");
            Check(_lastComparisonSummary == "No identifier fields could be compared.", "zero comparable fields cannot claim that IDs are unchanged");
        }
        foreach (var dark in new[] { true, false })
        {
            ApplyTheme(dark);
            foreach (var approve in new[] { false, true })
            {
                var prompt = new ConsoleRepairWindow("The scanner or launcher is missing.", @"C:\Synthetic\" + new string('a', 240) + @"\hwid.bat")
                    { Owner = this, Width = 360, Height = 300 };
                Exception? promptFailure = null;
                prompt.Loaded += (_, _) => Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
                {
                    try
                    {
                        prompt.UpdateLayout();
                        var root = (FrameworkElement)prompt.Content;
                        var box = prompt.RepairButton.TransformToAncestor(root).TransformBounds(new Rect(prompt.RepairButton.RenderSize));
                        Check(box.Bottom <= root.ActualHeight + 1 && box.Right <= root.ActualWidth + 1 && prompt.RepairButton.ActualHeight > 20,
                            "repair actions stay inside the compact " + (dark ? "Midnight" : "Daylight") + " dialog");
                        Check(prompt.DetailsScroll.ScrollableHeight > 0, "long repair details scroll separately from the buttons");
                        var button = approve ? prompt.RepairButton : prompt.CancelButton;
                        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    }
                    catch (Exception error) { promptFailure = error; prompt.Close(); }
                }));
                var accepted = prompt.ShowDialog();
                if (promptFailure != null) throw promptFailure;
                Check(accepted == approve, approve ? "only Repair and open accepts recovery" : "Not now declines recovery");
            }
        }
        _refreshAgain = false; _snapshotCatalogRefreshing = true;
        await RefreshSnapshotsAsync(automatic: true);
        Check(!_refreshAgain, "idle polling cannot queue another catalog read while a refresh is pending");
        _refreshAgain = true;
        await RefreshSnapshotsAsync(automatic: true);
        Check(_refreshAgain, "idle polling preserves an already queued manual refresh");
        _snapshotCatalogRefreshing = false; _refreshAgain = false; _welcomeOpen = true;
        await RefreshSnapshotsAsync(automatic: true);
        Check(!_refreshAgain, "idle polling does not begin discovery behind the welcome notice");
        _welcomeOpen = false; _startupConnecting = true;
        await RefreshSnapshotsAsync(automatic: true);
        Check(!_refreshAgain, "idle polling does not compete with the initial scanner connection");
        _startupConnecting = false;
        Navigate("Identifiers");
        IdSearch.Clear(); IdFilter.SelectedIndex = 0;
        var selectedId = original.Identifiers.First(row => row.Value.Length > 0);
        IdentifiersGrid.SelectedItem = selectedId;
        IdentifiersGrid.Items.SortDescriptions.Clear();
        IdentifiersGrid.Items.SortDescriptions.Add(new SortDescription(nameof(IdentifierRow.Value), ListSortDirection.Descending));
        IdSearch.Text = selectedId.Value;
        Check(IdentifiersGrid.Items.SortDescriptions.Count == 1 && IdentifiersGrid.Items.SortDescriptions[0].Direction == ListSortDirection.Descending &&
            ReferenceEquals(IdentifiersGrid.SelectedItem, selectedId), "identifier searches retain column sorting and a matching selection");
        IdSearch.Text = "SYNTHETIC-NO-MATCH-6F49";
        Check(IdentifiersGrid.SelectedItem == null && !CopyIdButton.IsEnabled, "hiding an identifier clears its copy target");
        IdSearch.Clear();
        Check(IdentifiersGrid.Items.SortDescriptions.Count == 1, "clearing ID search does not duplicate the user's sort rules");
        Navigate("Review"); ReviewSearch.Clear();
        var selectedFinding = original.Findings.First();
        ReviewGrid.SelectedItem = selectedFinding;
        ReviewGrid.Items.SortDescriptions.Clear();
        ReviewGrid.Items.SortDescriptions.Add(new SortDescription(nameof(ReviewRow.Kind), ListSortDirection.Ascending));
        ReviewSearch.Text = selectedFinding.Message;
        Check(ReviewGrid.Items.SortDescriptions.Count == 1 && ReferenceEquals(ReviewGrid.SelectedItem, selectedFinding),
            "review searches retain sorting and the selected explanation");
        ReviewSearch.Text = "SYNTHETIC-NO-FINDING-6F49";
        Check(ReviewGrid.SelectedItem == null && ReviewDetail.Text.Length == 0, "a hidden finding cannot leave a stale explanation");
        ReviewSearch.Clear();
        Check(ReviewGrid.Items.SortDescriptions.Count == 1, "clearing review search preserves one copy of the selected sort rule");
        Check(_engine != null && File.ReadAllBytes(_engine.BatPath).AsSpan().SequenceEqual(EngineRecovery.Resource("Bat")),
            "the packaged recovery BAT matches the selected build");
        Check(_engine != null && File.ReadAllBytes(Path.Combine(Path.GetDirectoryName(_engine.BatPath)!, "Start-HWID.ps1")).AsSpan().SequenceEqual(EngineRecovery.Resource("Launcher")),
            "the packaged recovery launcher matches the selected build");
        var time = DateTimeOffset.UnixEpoch;
        _snapshotEntries = new[]
        {
            new SnapshotEntry(@"C:\Synthetic\Desk\new.json", "new.json", "HOME-PC", "Nov 11, 2026 14:00", "3.91", "42 KB", time.AddDays(2)),
            new SnapshotEntry(@"C:\Synthetic\Desk\old.json", "old.json", "HOME-PC", "Nov 10, 2026 14:00", "3.90", "39 KB", time.AddDays(1)),
            new SnapshotEntry(@"C:\Synthetic\Office\work.json", "work.json", "WORK-PC", "Nov 9, 2026 14:00", "3.89", "30 KB", time)
        };
        _snapshotCatalogLoaded = true; _snapshotCatalogError = null; _snapshotCatalogSkipped = 0;
        FilterSnapshots(); Navigate("Snapshots");
        Check(SnapshotsGrid.Items.Count == 3, "the unfiltered library retains newest-first catalog order");
        SnapshotsGrid.SelectedIndex = 1;
        SnapshotSearch.Text = "home-pc";
        Check(SnapshotsGrid.Items.Count == 2 && (SnapshotsGrid.SelectedItem as SnapshotEntry)?.Name == "old.json", "PC search is case-insensitive and keeps a matching selection");
        SnapshotsGrid.Items.SortDescriptions.Add(new SortDescription(nameof(SnapshotEntry.Name), ListSortDirection.Ascending));
        SnapshotSearch.Text = "HOME";
        Check(SnapshotsGrid.Items.SortDescriptions.Count == 1 && ((SnapshotEntry)SnapshotsGrid.Items[0]).Name == "new.json",
            "snapshot search retains the user's column sorting");
        SnapshotSearch.Clear(); SnapshotSearch.Text = "HOME";
        Check(SnapshotsGrid.Items.SortDescriptions.Count == 1, "clearing and reapplying a search does not duplicate sort rules");
        SnapshotSearch.Text = "Office";
        Check(SnapshotsGrid.Items.Count == 1 && SnapshotsGrid.SelectedItem == null, "folder search hides unrelated rows and clears a hidden selection");
        Check(!CompareSelectedButton.IsEnabled, "a hidden previous selection cannot be compared accidentally");
        SnapshotSearch.Text = "Nov 10";
        Check(SnapshotsGrid.Items.Count == 1, "capture dates are searchable");
        SnapshotSearch.Text = "missing-value";
        Check(SnapshotEmptyTitle.Text == "No snapshots match your search" && (string?)SnapshotEmptyAction.Tag == "ClearSnapshots", "an empty filter is distinguished from a missing library");
        OnEmptyStateAction(SnapshotEmptyAction, new RoutedEventArgs());
        Check(SnapshotSearch.Text.Length == 0 && SnapshotsGrid.Items.Count == 3, "clear-search guidance restores all saved entries");
        Check(CompareSavedButton.IsEnabled, "two saved files can be compared from the library");
        _snapshot = null; UpdateButtons();
        Check(CompareSavedButton.IsEnabled && !CompareSelectedButton.IsEnabled, "saved-file comparison stays available before a live scan");
        _snapshot = original; UpdateButtons();
        Navigate("Snapshots"); await FocusSearch();
        Check(SnapshotSearch.IsKeyboardFocusWithin, "Ctrl+F targets the snapshot search");
        using var data = JsonDocument.Parse("""
        {"previousCount":3,"currentCount":3,"skippedFields":1,"skippedSections":["BIOS"],"scopeWarnings":[],
         "previousComputer":"HOME-PC","currentComputer":"HOME-PC","previousCaptured":"2026-11-10T14:00:00Z","currentCaptured":"2026-11-11T14:00:00Z",
         "changes":[{"kind":"Changed","section":"CPU","field":"ProcessorId","device":"CPU0","previous":"CPU-0012","current":"CPU-0099","difference":"2 characters changed at positions 7-8: 12 -> 99"},
                    {"kind":"Current only","section":"Network adapters","field":"MacAddress","device":"NIC1","previous":null,"current":"AA-BB-CC","difference":"New record"},
                    {"kind":"Previous only","section":"Storage identifiers","field":"SerialNumber","device":"Disk0","previous":"DISK-OLD","current":null,"difference":"Previous record"}]}
        """);
        RenderComparison(data.RootElement, @"C:\Synthetic\old.json", false, @"C:\Synthetic\new.json");
        Navigate("Compare");
        Check(CompareGrid.Items.Count == 3 && _lastComparisonRows!.Count == 3, "the comparison retains every difference for full export");
        Check(CompareBaselineText.Text.StartsWith("Previous:") && CompareCurrentText.Text.StartsWith("Current:"), "previous and current sources have separate readable labels");
        Check(CompareSummaryText.Text.Contains("1 current only") && CompareSummaryText.Text.Contains("1 previous only"), "counts describe direction without assuming file timestamps");
        CompareFilter.SelectedIndex = 1;
        Check(CompareGrid.Items.Count == 1 && ((ChangeRow)CompareGrid.Items[0]).Kind == "Changed", "the changed-values filter excludes one-sided records");
        CompareGrid.SelectedIndex = 0;
        Check(CompareDetail.Text.Contains("CPU-0012") && CompareDetail.Text.Contains("CPU-0099") && CompareDetail.Text.Contains("positions 7-8"), "selection shows full IDs and exact changed characters");
        CompareSearch.Text = "NO-MATCH";
        Check(CompareGrid.Items.Count == 0 && CompareEmptyTitle.Text.Contains("filters"), "a filtered-out result never claims there were no ID changes");
        Check(CompareDetail.Text.Contains("BIOS") && CompareExportButton.IsEnabled && _lastComparisonRows!.Count == 3, "coverage notes and complete export remain available with filters");
        OnEmptyStateAction(CompareEmptyAction, new RoutedEventArgs());
        Check(CompareSearch.Text.Length == 0 && CompareFilter.SelectedIndex == 0 && CompareGrid.Items.Count == 3, "clear-filters guidance restores all differences");
        CompareSearch.Text = "CPU-0099";
        Check(CompareGrid.Items.Count == 1, "exact current identifier values are searchable");
        CompareGrid.Items.SortDescriptions.Add(new SortDescription(nameof(ChangeRow.Label), ListSortDirection.Descending));
        CompareSearch.Clear();
        Check(CompareGrid.Items.SortDescriptions.Count == 1 && ((ChangeRow)CompareGrid.Items[0]).Label.StartsWith("Storage"),
            "comparison search retains the chosen result ordering");
        CompareSearch.Clear(); CompareFilter.SelectedIndex = 3;
        Check(CompareGrid.Items.Count == 1 && ((ChangeRow)CompareGrid.Items[0]).Kind == "Previous only", "previous-only records have a distinct category");
        await FocusSearch(); Check(CompareSearch.IsKeyboardFocusWithin, "Ctrl+F targets the comparison search");
        var state = CaptureRestartState();
        Check(state.Text("compareSearch") == CompareSearch.Text && state.Number("compareFilter") == 3 && state.Text("snapshotSearch") == SnapshotSearch.Text,
            "restart captures library and comparison filters");
        ApplySnapshot(original);
        Check(CompareGrid.Items.Count == 0 && CompareCurrentText.Text == "Current: not selected" && CompareSearch.Text.Length == 0 && CompareFilter.SelectedIndex == 0,
            "a new scan clears stale comparison sources and filters");
        var enginePath = _engine!.BatPath;
        var auditRoot = Path.Combine(Path.GetDirectoryName(path)!, "connection-audit"); Directory.CreateDirectory(auditRoot);
        ConnectEngine(Path.Combine(auditRoot, "missing.bat"));
        Check(_engine == null && !ScanButton.IsEnabled && EngineConnectionText.ToolTip == null && FooterText.ToolTip == null &&
            FooterText.Text.Contains("unavailable"), "a missing connection clears stale scanner labels and file paths");
        var oversized = Path.Combine(auditRoot, "oversized.bat");
        using (var file = File.Create(oversized)) file.SetLength(8 * 1024 * 1024 + 1L);
        ConnectEngine(oversized);
        Check(_engine == null && StatusDetail.Text.Contains("8 MB") && !ScanButton.IsEnabled,
            "oversized BAT files are rejected before the dashboard reads their contents");
        var incomplete = Path.Combine(auditRoot, "incomplete.bat"); await File.WriteAllTextAsync(incomplete, "@echo off");
        ConnectEngine(incomplete);
        Check(_engine == null && StatusDetail.Text.Contains("embedded scanner"), "a truncated BAT cannot be labeled connected");
        var oldSource = Path.Combine(auditRoot, "old", "hwid.bat");
        var newSource = Path.Combine(auditRoot, "restored", "hwid.bat");
        Directory.CreateDirectory(Path.GetDirectoryName(oldSource)!); Directory.CreateDirectory(Path.GetDirectoryName(newSource)!);
        File.WriteAllBytes(oldSource, EngineRecovery.Resource("Bat")); File.WriteAllBytes(newSource, EngineRecovery.Resource("Bat"));
        var oldReports = Path.Combine(Path.GetDirectoryName(oldSource)!, "HWID-Reports"); Directory.CreateDirectory(oldReports);
        var oldCapture = Path.Combine(oldReports, "older.json");
        await File.WriteAllTextAsync(oldCapture, """{"Report info":{"Version":"3.91","Computer":"SYNTHETIC","Generated":"2026-11-11T12:00:00Z"},"CPU":[{"ProcessorId":"SYNTHETIC-ID"}]}""");
        var shared = Path.Combine(auditRoot, "shared", "snapshot-library.json");
        await SharedSnapshotLibrary.UpdateAsync("reset-primary", null, shared);
        var additional = _additionalFolders.ToArray();
        ConnectEngine(oldSource);
        var warning = await ConnectRecoveredScannerAsync(newSource, Path.Combine(auditRoot, "preferences.json"), shared);
        var settings = SharedSnapshotLibrary.Read(shared);
        Check(warning == null && settings.IsConfigured && settings.Folders.Any(folder => SameFolder(folder, oldReports)),
            "recovery registers the previous default report folder in an already configured shared library");
        var catalog = await SnapshotStore.ReadAsync(ReportFolders(settings));
        Check(catalog.Entries.Any(row => row.Path == oldCapture), "old snapshots stay discoverable after a recovered scanner changes its default directory");
        _additionalFolders.Clear(); foreach (var folder in additional) _additionalFolders.Add(folder);
        ConnectEngine(enginePath);
        Check(_engine?.BatPath == enginePath && ScanButton.IsEnabled, "a healthy scanner reconnects after connection failures");
        RenderComparison(data.RootElement, @"C:\Synthetic\old.json", false, @"C:\Synthetic\new.json");
        CompareExportButton.ToolTip = "Exports the full comparison, including rows hidden by filters.";
        var directory = Path.Combine(Path.GetDirectoryName(path)!, "library-fixtures"); Directory.CreateDirectory(directory);
        foreach (var theme in new[] { true, false })
        {
            ApplyTheme(theme);
            foreach (var page in new[] { "Snapshots", "Compare" })
            {
                Navigate(page); await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); UpdateLayout();
                var grid = page == "Snapshots" ? SnapshotsGrid : CompareGrid;
                Check(grid.ActualHeight >= 80 && grid.ActualWidth >= 200, page + (theme ? " Midnight" : " Daylight") + $" retains a usable table at the requested size ({grid.ActualWidth:0} x {grid.ActualHeight:0})");
                var surface = (FrameworkElement)Content;
                var image = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
                image.Render(surface); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
                using var output = File.Create(Path.Combine(directory, page.ToLowerInvariant() + (theme ? "-midnight" : "-daylight") + ".png")); encoder.Save(output);
            }
        }
        var previousRows = _lastComparisonRows; var previousData = _comparisonResumeData;
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try { await PrepareComparisonAsync(data.RootElement, _snapshot, cancelled.Token); Check(false, "cancelled preparation must not publish"); }
            catch (OperationCanceledException)
            {
                Check(ReferenceEquals(previousRows, _lastComparisonRows) && previousData.Equals(_comparisonResumeData),
                    "cancelling comparison preparation preserves the complete previous comparison");
            }
        }
        var prepared = await PrepareComparisonAsync(data.RootElement, _snapshot, CancellationToken.None);
        Check(prepared.Rows.SequenceEqual(BuildComparisonRows(data.RootElement, _snapshot, CancellationToken.None)),
            "background comparison preparation preserves exact previous/current text and differences");
        _snapshotCatalogRefreshing = true; UpdateSnapshotCount(); UpdateSnapshotEmptyState();
        Check(SnapshotCountText.Text.StartsWith("Refreshing") && ReferenceEquals(previousRows, _lastComparisonRows),
            "snapshot refresh has its own loading state without replacing comparison results");
        _snapshotCatalogRefreshing = false; UpdateSnapshotCount();
        SetBusy(true, "Compare");
        Check(CancelButton.IsVisible && (string)CancelButton.Content == "Cancel comparison", "comparison exposes an accessible cancel action");
        UiMotion.SetEnabled(this, false);
        Check(!ScanProgress.IsIndeterminate, "reduced motion stops the comparison progress animation");
        _operationCancellation = new CancellationTokenSource();
        OnCancel(this, new RoutedEventArgs());
        Check(_operationCancellation.IsCancellationRequested && !CancelButton.IsEnabled && StatusTitle.Text == "Cancelling comparison…",
            "comparison cancellation targets the active operation and prevents duplicate requests");
        _operationCancellation.Dispose(); _operationCancellation = null; SetBusy(false);
        ClearValue(UiMotion.EnabledProperty);
        Check(!CancelButton.IsVisible && !ScanProgress.IsIndeterminate && ReferenceEquals(previousRows, _lastComparisonRows),
            "finishing cancellation resets controls without clearing the last result");
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = true, checks = checks.Count, names = checks,
            syntheticOnly = true, hardwareIdentifiersSaved = false }));
    }
}
