using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private async Task VerifyScanUiAsync(string path)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("Scan UI verification requires a synthetic capture.");
        var checks = new List<string>();
        void Check(bool value, string name) { if (!value) throw new InvalidOperationException("Dashboard layout: scan: " + name); checks.Add(name); }
        var original = _snapshot;
        bool UsesBrush(System.Windows.Controls.TextBlock label, string key) =>
            label.Foreground is SolidColorBrush actual && FindResource(key) is SolidColorBrush expected && actual.Color == expected.Color;
        DesktopSnapshot MetricCapture(string? status, bool includeCatalog = false, int records = 0, bool findings = false)
        {
            var data = JsonNode.Parse("""{"version":"3.96","inventory":{"Report info":{},"CPU":[{"Name":"Synthetic CPU"}]},"identifiers":[],"review":{}}""")!;
            var inventory = data["inventory"]!.AsObject();
            if (status != null) inventory["Report info"]!["ExtendedStatus"] = status;
            if (includeCatalog)
            {
                var rows = new JsonArray();
                for (var index = 0; index < records; index++) rows.Add(new JsonObject { ["DeviceInstanceId"] = "SYNTHETIC\\000" + index });
                inventory["Extended device inventory"] = rows;
            }
            if (findings) data["review"]!["DeviceIssues"] = new JsonArray(new JsonObject { ["Message"] = "Synthetic status needs review" });
            using var parsed = JsonDocument.Parse(data.ToJsonString());
            return new DesktopSnapshot(parsed.RootElement);
        }
        Navigate("Overview");
        _snapshot = null; UpdateButtons();
        Check(IdsCount.Text == "Not scanned" && SectionsCount.Text == "Not scanned" && DevicesCount.Text == "Not scanned" &&
            ReviewCount.Text == "Not checked", "before a scan, metrics explain that results have not been collected");
        Check(ReviewMetricDetail.Text == "No results yet" && IdsMetricDetail.Text.Contains("Start a scan"),
            "initial metric guidance gives a next action without implying missing IDs or conflicts");
        foreach (var dark in new[] { true, false })
        {
            ApplyTheme(dark); await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); UpdateLayout();
            Check(new[] { IdsCount, SectionsCount, ReviewCount, DevicesCount }.All(label => UsesBrush(label, "MutedBrush")),
                (dark ? "Midnight" : "Daylight") + " has no warning or successful-result colors before a scan");
            foreach (var label in new[] { IdsCount, SectionsCount, ReviewCount, DevicesCount })
            {
                var text = new FormattedText(label.Text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                    new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch), label.FontSize,
                    label.Foreground, VisualTreeHelper.GetDpi(label).PixelsPerDip);
                var available = ((FrameworkElement)label.Parent).ActualWidth;
                Check(text.WidthIncludingTrailingWhitespace <= available,
                    (dark ? "Midnight" : "Daylight") + " pre-scan " + label.Name + " fits its card");
            }
            OverviewPage.ScrollToTop();
            var surface = (FrameworkElement)Content;
            var frame = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            frame.Render(surface); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(frame));
            using var output = File.Create(Path.Combine(Path.GetDirectoryName(path)!, dark ? "before-scan-midnight.png" : "before-scan-daylight.png")); encoder.Save(output);
        }
        ApplySnapshot(MetricCapture("Refreshed", true));
        Check(ReviewCount.Text == "0" && UsesBrush(ReviewCount, "MutedBrush") && ReviewMetricDetail.Text == "No review items reported",
            "a completed capture with zero findings does not show a warning or claim hardware health");
        Check(DevicesCount.Text == "0", "a confirmed successful empty catalog retains its genuine zero count");
        ApplySnapshot(MetricCapture("Unavailable"));
        Check(DevicesCount.Text == "Not read", "a failed catalog read cannot masquerade as zero devices");
        ApplySnapshot(MetricCapture(null));
        Check(DevicesCount.Text == "Not included", "a capture without the catalog does not claim zero devices");
        ApplySnapshot(MetricCapture(null, true));
        Check(DevicesCount.Text == "Unknown", "an empty catalog without a read status does not claim verified zero devices");
        ApplySnapshot(MetricCapture(null, true, 1));
        Check(DevicesCount.Text == "1" && DevicesMetricDetail.Text == "Read status not recorded",
            "legacy saved records keep their count without inventing successful coverage");
        ApplySnapshot(MetricCapture("Refreshed", true, 1, true));
        Check(ReviewCount.Text == "1" && UsesBrush(ReviewCount, "WarningBrush") && ReviewMetricDetail.Text == "Open Review for details",
            "warning color is reserved for actual captured findings");
        var partialCatalog = JsonNode.Parse(MetricCapture("Refreshed", true, 1).Data.GetRawText())!;
        partialCatalog["inventory"]!["Extended scan info"] = new JsonObject { ["PropertyNodesRequested"] = 1,
            ["PropertyNodesReturned"] = 0, ["PropertyNodesWithoutRows"] = 1, ["PropertyBlockingErrors"] = 1 };
        using (var partialData = JsonDocument.Parse(partialCatalog.ToJsonString())) ApplySnapshot(new DesktopSnapshot(partialData.RootElement));
        Check(DevicesCount.Text == "1" && DevicesMetricDetail.Text == "Records read; review identification" &&
            UsesBrush(DevicesCount, "WarningBrush") && CatalogText.Text.Contains("identification needs review"),
            "readable catalog records retain their count while incomplete identification is explained separately");
        ReviewFilter.SelectedIndex = 5; FilterReview();
        Check(ReviewGrid.Items.Count == 1 && ((ReviewRow)ReviewGrid.Items[0]).Kind == "Scan coverage",
            "the scan-coverage filter explains optional lookup gaps without labeling them as a device fault");
        ReviewFilter.SelectedIndex = 4; FilterReview();
        Check(ReviewGrid.Items.Count == 0, "identification coverage is excluded from hardware device-status findings");
        ReviewFilter.SelectedIndex = 0;
        ApplySnapshot(MetricCapture("Refreshed", true, 1));
        Check(ReviewCount.Text == "0" && UsesBrush(DevicesCount, "TextBrush") && DevicesMetricDetail.Text == "Windows-known device records",
            "a healthy replacement capture clears prior coverage findings and colors");
        ApplySnapshot(MetricCapture("Refreshed", true, 1, true));
        SetBusy(true, "Scan");
        Check(ReviewCount.Text == "1" && MetricsGrid.Visibility == Visibility.Collapsed,
            "a rescan hides retained metrics instead of publishing partial or empty results");
        RestoreScanActivity(); SetBusy(false);
        Check(ReviewCount.Text == "1" && DevicesCount.Text == "1" && MetricsGrid.Visibility == Visibility.Visible,
            "an unsuccessful rescan keeps the last accepted metric counts");
        _snapshot = null; RestoreScanActivity(); UpdateButtons();
        Check(ReviewCount.Text == "Not checked" && DevicesCount.Text == "Not scanned" && UsesBrush(ReviewCount, "MutedBrush"),
            "a first attempt without an accepted snapshot retains neutral unscanned metrics");
        ApplySnapshot(original);
        DesktopSnapshot Numbered(int number)
        {
            var data = JsonNode.Parse(original.Data.GetRawText())!;
            data["inventory"]!["Report info"]!["ScanNumber"] = number;
            using var parsed = JsonDocument.Parse(data.ToJsonString());
            return new DesktopSnapshot(parsed.RootElement);
        }
        Check(NextScanNumber(null) == 1 && NextScanNumber(Numbered(0)) == 1, "a fresh scan starts at number one");
        Check(NextScanNumber(Numbered(5)) == 6, "a successful rescan advances the saved scan number");
        Check(NextScanNumber(Numbered(-1)) == 1 && NextScanNumber(Numbered(int.MaxValue)) == 1,
            "invalid or exhausted imported numbering cannot crash a new scan");
        Navigate("Overview"); SetBusy(true, "Scan");
        _operationCancellation = new CancellationTokenSource();
        var generation = ++_scanGeneration;
        _scanTotalStages = 19; _scanCompletedStages = 0; _scanClock.Restart();
        ScanRows.Clear();
        foreach (var name in ScanSectionNames) ScanRows.Add(new(name, "WAITING", "Pending", "Synthetic waiting", ""));
        ApplyScanProgress(new("CPU", "CPU", 0, 19, "READING", 0, "Synthetic provider read", 0.2), generation);
        Check(ScanRows.Single(row => row.Name == "CPU").Records == "Pending" && ScanElapsedText.Text.Contains("0 read"),
            "an unfinished query does not claim zero returned records or a successful read");
        Check(CancelButton.Visibility == Visibility.Visible && !SaveButton.IsEnabled && ReferenceEquals(_snapshot, original),
            "scan cancellation remains available while the previous snapshot is protected from publication");
        ApplyScanProgress(new("CPU", "CPU", 1, 19, "READ", 1, "Synthetic IDs received", 0.3), generation);
        ApplyScanProgress(new("BIOS", "BIOS", 2, 19, "CHECK", 1, "Synthetic default serial", 0.1), generation);
        Check(ScanElapsedText.Text.Contains("2 read") && ScanElapsedText.Text.Contains("0 not read"),
            "CHECK counts as data read rather than a provider failure");
        ApplyScanProgress(new("Motherboard", "Motherboard", 3, 19, "UNAVAILABLE", 0, "Synthetic denied", 0.1, "READ-01", "Review the Windows reader"), generation);
        Check(ScanElapsedText.Text.Contains("2 read") && ScanElapsedText.Text.Contains("1 not read"),
            "failed reads are counted separately from finished checks");
        Check(StatusDetail.Text.Contains("READ-01") && StatusDetail.Text.Contains("Review the Windows reader"),
            "the active status retains the failure code and actionable next step");
        var percent = ScanProgress.Value;
        ApplyScanProgress(new("CPU", "CPU", 0, 19, "READING", 0, "Synthetic delayed heartbeat"), generation);
        Check(ScanRows.Single(row => row.Name == "CPU").Status == "READ" && ScanProgress.Value >= percent,
            "a delayed heartbeat cannot regress progress or replace an accepted read");
        var title = StatusTitle.Text;
        ApplyScanProgress(new("Preparing", "Preparing", 0, 19, "READING", 0, "Synthetic delayed preparation"), generation);
        Check(StatusTitle.Text == title, "late preparation feedback cannot replace the active scan phase");
        var before = ScanRows.ToArray();
        ApplyScanProgress(new("CPU", "CPU", 4, 19, "NOT READ", 0, "Obsolete generation"), generation - 1);
        Check(ScanRows.SequenceEqual(before), "obsolete scan generations cannot change the current activity table");
        for (var index = 0; index < ScanRows.Count; index++)
            if (ScanRows[index].Name != "Motherboard") ScanRows[index] = ScanRows[index] with { Status = "READ", Records = "1", Detail = "Synthetic data read" };
        ApplyScanProgress(new("Extended device inventory", "Extended device inventory", 19, 19, "READ", 1, "Synthetic catalog received"), generation);
        Check(StatusTitle.Text == "Finalizing scan" && Title.Contains("finalizing") && StatusBadge.Text == "WORKING",
            "100 percent attempted checks remain a working finalization phase");
        Check(ReferenceEquals(_snapshot, original) && !SaveButton.IsEnabled,
            "the completed progress stream cannot publish or export an unvalidated replacement");
        Check(ScanElapsedText.Text.Contains("18 read") && ScanElapsedText.Text.Contains("1 not read"),
            "the finished-check counts include the catalog without hiding an earlier read failure");
        var directory = Path.Combine(Path.GetDirectoryName(path)!, "scan-fixtures"); Directory.CreateDirectory(directory);
        foreach (var dark in new[] { true, false })
        {
            ApplyTheme(dark); await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); UpdateLayout();
            var label = new FormattedText(ScanElapsedText.Text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                new Typeface(ScanElapsedText.FontFamily, ScanElapsedText.FontStyle, ScanElapsedText.FontWeight, ScanElapsedText.FontStretch),
                ScanElapsedText.FontSize, ScanElapsedText.Foreground, VisualTreeHelper.GetDpi(ScanElapsedText).PixelsPerDip);
            Check(label.WidthIncludingTrailingWhitespace <= ScanElapsedText.ActualWidth,
                (dark ? "Midnight" : "Daylight") + " shows the complete read/failure counts and elapsed time without truncation");
            if (ScanGrid.Columns[1].GetCellContent(ScanRows.First(row => row.Name == "Motherboard")) is System.Windows.Controls.TextBlock failure)
            {
                var text = new FormattedText(failure.Text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                    new Typeface(failure.FontFamily, failure.FontStyle, failure.FontWeight, failure.FontStretch), failure.FontSize,
                    failure.Foreground, VisualTreeHelper.GetDpi(failure).PixelsPerDip);
                Check(text.WidthIncludingTrailingWhitespace <= failure.ActualWidth,
                    $"Full failed-read label fits the status cell ({text.WidthIncludingTrailingWhitespace:0.0} required / {failure.ActualWidth:0.0} available)");
            }
            var surface = (FrameworkElement)Content;
            var frame = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            frame.Render(surface); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(frame));
            using var output = File.Create(Path.Combine(directory, dark ? "finalizing-midnight.png" : "finalizing-daylight.png")); encoder.Save(output);
        }
        OnCancel(CancelButton, new RoutedEventArgs());
        before = ScanRows.ToArray();
        ApplyScanProgress(new("CPU", "CPU", 19, 19, "NOT READ", 0, "Late after cancellation"), generation);
        Check(_operationCancellation.IsCancellationRequested && !CancelButton.IsEnabled && ScanRows.SequenceEqual(before),
            "cancellation disables repeated requests and rejects pending progress");
        RestoreScanActivity();
        Check(ReferenceEquals(_snapshot, original) && ScanRows.SequenceEqual(original.Timing.Concat(new[] { original.CatalogRow })),
            "cancelling a rescan restores all activity rows from the previous completed capture");
        Check(NextScanNumber(_snapshot) == NextScanNumber(original), "a failed or cancelled attempt does not consume a successful scan number");
        _operationCancellation.Dispose(); _operationCancellation = null;
        SetBusy(false); _scanClock.Stop(); ++_scanGeneration;
        Check(ReviewCount.Text == original.Findings.Count.ToString("N0"), "cancelling a rescan keeps the accepted review count");
        _snapshot = null; ScanRows.Clear(); ScanRows.Add(new("CPU", "READING", "Pending", "Synthetic first attempt", ""));
        RestoreScanActivity();
        UpdateButtons();
        Check(ScanRows[0].Status == "Stopped" && ScanProgress.Value == 0, "an aborted first scan cannot present a completed snapshot");
        Check(ReviewCount.Text == "Not checked" && UsesBrush(ReviewCount, "MutedBrush"), "an aborted first scan cannot leave stale findings in the overview");
        ApplySnapshot(original); Title = "HWID Checker - Desktop";
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = true, checks = checks.Count, names = checks,
            syntheticOnly = true, hardwareIdentifiersSaved = false }));
    }
}
