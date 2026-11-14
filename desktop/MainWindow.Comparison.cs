using System.Text.Json;

namespace HwidDesktop;

public partial class MainWindow
{
    private static List<string> ComparisonNotes(JsonElement result, bool sameFile)
    {
        var notes = new List<string>
        {
            $"Identifier fields available for comparison · {result.Number("previousCount")} in the previous capture, {result.Number("currentCount")} in the current capture.",
            $"Not compared · {result.Number("skippedFields")} fields."
        };
        if (sameFile) notes.Add("Both sides were read from the same JSON file path.");
        var skipped = result.Get("skippedSections").Rows().Select(x => x.Text()).ToArray();
        if (skipped.Length > 0) notes.Add("Sections not compared: " + string.Join(", ", skipped) + ". Data may be unread, absent, or lack reliable matching keys.");
        var unkeyed = result.Get("unkeyedSections").Rows().Select(x => x.Text()).ToArray();
        if (unkeyed.Length > 0) notes.Add("Missing device matching keys: " + string.Join(", ", unkeyed) + ". No device match was guessed.");
        foreach (var conflict in result.Get("ambiguousDevices").Rows())
        {
            var key = conflict.Text("DeviceKey");
            notes.Add("Ambiguous device match: " + conflict.Text("Section") + " / " + (key.Length > 0 ? key : "no reliable device key")
                + " / " + conflict.Number("Count") + " records / " + string.Join(" + ", conflict.Get("Sources").Rows().Select(x => x.Text()))
                + ". These IDs were not compared.");
        }
        foreach (var scope in result.Get("scopeWarnings").Rows())
            notes.Add("Reader coverage differs: " + scope.Text("PreviousReader") + " → " + scope.Text("CurrentReader") + "; " + scope.Number("SkippedDevices") + " unmatched device records not compared.");
        var previousComputer = result.Text("previousComputer"); var currentComputer = result.Text("currentComputer");
        if (previousComputer.Length > 0 && currentComputer.Length > 0 && !previousComputer.Equals(currentComputer, StringComparison.OrdinalIgnoreCase))
            notes.Add("Different computer names: verify that these are the captures you intended to compare.");
        if (DateTimeOffset.TryParse(result.Text("previousCaptured"), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var before)
            && DateTimeOffset.TryParse(result.Text("currentCaptured"), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var after))
        {
            if (before == after) notes.Add("Same capture time: this may be another save of the same scan.");
            else if (before > after) notes.Add("Time order: Previous is newer than Current. Labels follow your chosen files; values were not swapped.");
        }
        return notes;
    }

    private sealed record PreparedComparison(JsonElement Data, ChangeRow[] Rows);

    // Build complete rows before replacing the visible comparison. Cancelling a
    // worker or this preparation leaves the last finished result intact.
    private static Task<PreparedComparison> PrepareComparisonAsync(JsonElement result, DesktopSnapshot? snapshot, CancellationToken cancellationToken) =>
        Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            var data = result.Clone();
            var rows = BuildComparisonRows(data, snapshot, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            return new PreparedComparison(data, rows);
        }, cancellationToken);

    private static ChangeRow[] BuildComparisonRows(JsonElement result, DesktopSnapshot? snapshot, CancellationToken cancellationToken)
    {
        var rows = new List<ChangeRow>();
        foreach (var row in result.Get("changes").Rows())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var previous = row.Get("previous").Display();
            var current = row.Get("current").Display();
            rows.Add(new ChangeRow(row.Text("kind"), row.Text("section") + " / " + CompareLabel(result, row.Text("section"), row.Text("field"), snapshot),
                previous, current, "Device: " + row.Text("device") + "\nOLD: " + previous + "\nNEW: " + current + "\n\n" + row.Text("difference")));
        }
        return rows.ToArray();
    }
}
