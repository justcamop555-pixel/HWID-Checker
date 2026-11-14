using System.Windows;

namespace HwidDesktop;

public partial class MainWindow
{
    private bool _startupConnecting;

    private async Task ConnectEngineAtStartupAsync()
    {
        _startupConnecting = true; UpdateButtons();
        try
        {
            // A remembered BAT can be on a sleeping disk, OneDrive or an
            // unavailable network share. Never probe or read it on the dispatcher.
            var prepared = await Task.Run(() =>
            {
                var path = FindEngine();
                if (string.IsNullOrWhiteSpace(path)) return ((EngineClient?)null, "");
                var text = EngineRecovery.ReadScannerText(path);
                return ((EngineClient?)new EngineClient(path), text);
            });
            if (_closing || _closeRequested) { prepared.Item1?.Dispose(); return; }
            if (prepared.Item1 == null)
            {
                DisconnectEngine();
                ShowStatus("Scanner needs repair", "Use Open BAT console to check and restore the bundled scanner, or Setup & repair to reinstall the application files. Existing snapshots remain available.", true);
            }
            else AttachPreparedEngine(prepared.Item1, prepared.Item2);
        }
        catch (Exception error)
        {
            if (!_closing && !_closeRequested) { DisconnectEngine(); ShowError("Could not connect the BAT", error); }
        }
        finally { _startupConnecting = false; if (!_closing && !_closeRequested) UpdateButtons(); }
    }
}
