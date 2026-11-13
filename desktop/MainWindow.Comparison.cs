using System.Text.Json;

namespace HwidDesktop;

public partial class MainWindow
{
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
