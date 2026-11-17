using System.Windows.Controls;

namespace HwidDesktop;

public partial class MainWindow
{
    private DesktopSnapshot? _overviewMetricsSnapshot;
    private bool _overviewMetricsRendered;

    private void UpdateOverviewMetrics()
    {
        // Library searches and selection changes update buttons frequently.
        // The accepted capture has not changed; keep its existing dynamic
        // resource bindings instead of recounting devices and invalidating text.
        if (_overviewMetricsRendered && ReferenceEquals(_overviewMetricsSnapshot, _snapshot)) return;
        void Metric(TextBlock value, TextBlock detail, string text, string description, string brush, string? explanation = null)
        {
            SetSummary(value, text, explanation ?? description);
            value.SetResourceReference(TextBlock.ForegroundProperty, brush);
            SetSummary(detail, description, explanation);
        }

        // Metrics always describe the last accepted capture, never partial progress.
        // No scan and no findings are different states; neither is a warning.
        if (_snapshot == null)
        {
            Metric(IdsCount, IdsMetricDetail, "Not scanned", "Start a scan to collect IDs", "MutedBrush");
            Metric(SectionsCount, SectionsMetricDetail, "Not scanned", "Read status after scanning", "MutedBrush");
            Metric(ReviewCount, ReviewMetricDetail, "Not checked", "No results yet", "MutedBrush");
            Metric(DevicesCount, DevicesMetricDetail, "Not scanned", "Counts appear after scanning", "MutedBrush");
            _overviewMetricsSnapshot = null; _overviewMetricsRendered = true;
            return;
        }

        var snapshot = _snapshot;
        Metric(IdsCount, IdsMetricDetail, snapshot.ReportedIds.ToString("N0"), "Reported by Windows", "AccentBrush",
            "Identifier fields supplied in this capture. This count can include repeated values; it is not a count of unique devices.");
        Metric(SectionsCount, SectionsMetricDetail,
            snapshot.SectionsChecked > 0 ? snapshot.SectionsRead + " / " + snapshot.SectionsChecked : "Unknown",
            "Hardware and system", snapshot.SectionsChecked > 0 ? "TextBrush" : "MutedBrush", snapshot.CoverageText);
        var findings = snapshot.Findings.Count;
        Metric(ReviewCount, ReviewMetricDetail, findings.ToString("N0"),
            findings > 0 ? "Open Review for details" : "No review items reported",
            findings > 0 ? "WarningBrush" : "MutedBrush",
            "Review items can include unavailable or generic IDs. They are not proof of a hardware fault.");

        var catalog = snapshot.CatalogRow;
        var devices = catalog.Status switch
        {
            "READ" or "CHECK" => snapshot.DeviceCount.ToString("N0"),
            "NOT READ" => "Not read",
            "NOT SCANNED" => "Not included",
            _ => snapshot.DeviceCount > 0 ? snapshot.DeviceCount.ToString("N0") : "Unknown"
        };
        Metric(DevicesCount, DevicesMetricDetail, devices,
            catalog.Status == "READ" ? "Windows-known device records" :
            catalog.Status == "CHECK" ? "Records read; review identification" :
            catalog.Status == "UNKNOWN" ? "Read status not recorded" :
            catalog.Status == "NOT READ" ? "Open Review for read details" : "Not captured in this snapshot",
            catalog.Status == "READ" ? "TextBrush" : catalog.Status is "NOT READ" or "CHECK" ? "WarningBrush" : "MutedBrush",
            catalog.Detail);
        _overviewMetricsSnapshot = snapshot; _overviewMetricsRendered = true;
    }
}
