namespace HwidDesktop;

public partial class MainWindow
{
    private static int NextScanNumber(DesktopSnapshot? snapshot)
    {
        var previous = snapshot?.Info.Number("ScanNumber") ?? 0;
        return previous is >= 0 and < int.MaxValue ? previous + 1 : 1;
    }

    private void UpdateScanActivityText()
    {
        var read = ScanRows.Count(row => row.Status is "READ" or "CHECK");
        var notRead = ScanRows.Count(row => row.Status is "NOT READ" or "UNAVAILABLE");
        SetSummary(ScanElapsedText, $"{_scanCompletedStages}/{_scanTotalStages} finished · {read} read · {notRead} not read · {_scanClock.Elapsed:mm\\:ss}",
            "Finished counts attempted checks, including the device catalog. READ and CHECK received data; NOT READ is a failed check. A scan is published after its complete result is validated.");
    }
}
