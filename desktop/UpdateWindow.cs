using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace HwidDesktop;

internal sealed class UpdateWindow : Window
{
    private readonly DesktopUpdater _updater;
    private readonly Func<bool> _canInstall;
    private readonly Action _install;
    private readonly TextBlock _message = new() { TextWrapping = TextWrapping.Wrap };
    private readonly CheckBox _automatic = new() { Content = "Download new versions automatically and install when I close the app", IsThreeState = false };
    private readonly Button _check = new() { Content = "Check now" };
    private readonly Button _download = new() { Content = "Download update" };
    private readonly Button _restart = new() { Content = "Install and restart" };
    private readonly Button _cancel = new() { Content = "Stop" };

    internal UpdateWindow(DesktopUpdater updater, string scannerVersion, Func<bool> canInstall, Action install)
    {
        _updater = updater;
        _canInstall = canInstall;
        _install = install;
        SetResourceReference(StyleProperty, typeof(Window));
        Title = "HWID Checker updates";
        Width = Math.Min(560, Math.Max(1, SystemParameters.WorkArea.Width - 16));
        Height = Math.Min(365, Math.Max(1, SystemParameters.WorkArea.Height - 16));
        MinWidth = Math.Min(390, Width);
        MinHeight = Math.Min(300, Height);
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var layout = new DockPanel { Margin = new Thickness(18) };
        var heading = new StackPanel();
        heading.Children.Add(new TextBlock { Text = "Application updates", FontSize = 22, FontWeight = FontWeights.SemiBold });
        var versions = new TextBlock
        {
            Text = $"Running Desktop {DesktopUpdater.CurrentVersion}  ·  {scannerVersion}",
            Margin = new Thickness(0, 7, 0, 14), TextWrapping = TextWrapping.Wrap
        };
        versions.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        heading.Children.Add(versions);
        _automatic.Content = new TextBlock
        {
            Text = "Download new versions automatically and install when I close the app",
            TextWrapping = TextWrapping.Wrap
        };
        _automatic.IsChecked = updater.AutomaticEnabled;
        _automatic.SetResourceReference(ForegroundProperty, "TextBrush");
        _automatic.Margin = new Thickness(0, 0, 0, 14);
        heading.Children.Add(_automatic);
        DockPanel.SetDock(heading, Dock.Top);
        layout.Children.Add(heading);

        var buttons = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        foreach (var button in new[] { _check, _download, _restart, _cancel })
        {
            button.Padding = new Thickness(10, 7, 10, 7);
            button.Margin = new Thickness(0, 0, 7, 6);
            buttons.Children.Add(button);
        }
        var releases = new Button { Content = "Release notes", Padding = new Thickness(10, 7, 10, 7), Margin = new Thickness(0, 0, 7, 6) };
        releases.Click += (_, _) =>
        {
            try { Process.Start(new ProcessStartInfo("https://github.com/justcamop555-pixel/HWID-Checker/releases") { UseShellExecute = true }); }
            catch (Exception error) { _message.Text = "Could not open release notes. " + error.Message; }
        };
        buttons.Children.Add(releases);
        var close = new Button { Content = "Close", IsCancel = true, Padding = new Thickness(10, 7, 10, 7), Margin = new Thickness(0, 0, 0, 6) };
        buttons.Children.Add(close);
        DockPanel.SetDock(buttons, Dock.Bottom);
        layout.Children.Add(buttons);
        var status = new Border { Padding = new Thickness(12), Child = new ScrollViewer { Content = _message, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } };
        status.SetResourceReference(Border.BackgroundProperty, "PanelBrush");
        status.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
        status.BorderThickness = new Thickness(1);
        layout.Children.Add(status);
        Content = layout;

        _check.Click += async (_, _) => await updater.CheckAsync();
        _download.Click += async (_, _) => await updater.DownloadAsync();
        _cancel.Click += (_, _) => updater.Cancel();
        _restart.Click += (_, _) =>
        {
            if (!_canInstall()) { _message.Text = "Finish the active scan or report action before installing."; return; }
            _install();
        };
        _automatic.Click += async (_, _) =>
        {
            try
            {
                updater.SetAutomatic(_automatic.IsChecked == true);
                if (!updater.AutomaticEnabled) updater.Cancel();
                else await updater.PrepareAutomaticallyAsync();
                Refresh();
            }
            catch (Exception error) { _message.Text = "Could not save the update preference. " + error.Message; }
        };
        updater.Changed += OnUpdaterChanged;
        Closed += (_, _) => updater.Changed -= OnUpdaterChanged;
        Refresh();
    }

    private void OnUpdaterChanged(object? sender, EventArgs args) => Dispatcher.Invoke(Refresh);

    private void Refresh()
    {
        var status = _updater.Status;
        _message.Text = status.Message +
            (status.LatestVersion.Length > 0 && status.State is "available" or "ready" or "repair"
                ? "\n\nUpdate package " + status.LatestVersion : "") +
            (status.BatVersion.Length > 0 ? " · BAT " + status.BatVersion : "") +
            (_updater.IsReady ? "\n\nThe verified package is ready. " +
                (_updater.AutomaticEnabled ? "It will install after the app closes." : "Choose Install and restart to apply it.") : "");
        _message.SetResourceReference(TextBlock.ForegroundProperty, status.State == "error" ? "WarningBrush" : "TextBrush");
        _check.IsEnabled = !_updater.IsBusy && status.State is not ("repair" or "restart");
        _download.Visibility = status.State == "available" ? Visibility.Visible : Visibility.Collapsed;
        _download.IsEnabled = !_updater.IsBusy;
        _restart.Visibility = _updater.IsReady ? Visibility.Visible : Visibility.Collapsed;
        _restart.IsEnabled = !_updater.IsBusy;
        _cancel.Visibility = _updater.IsBusy ? Visibility.Visible : Visibility.Collapsed;
    }
}
