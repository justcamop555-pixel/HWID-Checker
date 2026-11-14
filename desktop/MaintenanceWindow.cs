using System.Windows;
using System.Windows.Controls;

namespace HwidDesktop;

internal sealed class MaintenanceWindow : Window
{
    internal string? Action { get; private set; }
    internal MaintenanceWindow(bool installed, bool hasRepair)
    {
        SetResourceReference(StyleProperty, typeof(Window)); Title = "Setup & repair — HWID Checker";
        ShowInTaskbar = false; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Width = Math.Min(590, Math.Max(1, SystemParameters.WorkArea.Width - 24));
        Height = Math.Min(470, Math.Max(1, SystemParameters.WorkArea.Height - 24));
        MinWidth = Math.Min(360, Width); MinHeight = Math.Min(300, Height);
        var root = new DockPanel { Margin = new Thickness(18) };
        var close = new Button { Content = "Close", IsCancel = true, HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(0, 12, 0, 0) };
        close.Click += (_, _) => Close(); DockPanel.SetDock(close, Dock.Bottom); root.Children.Add(close);
        var body = new StackPanel();
        body.Children.Add(new TextBlock { Text = installed ? "Installed for all Windows users" : "Portable application",
            FontSize = 22, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = installed
            ? "Setup can reinstall the application files and shortcuts. Administrator approval is required. Your snapshots, folder choices and settings are kept."
            : "This copy runs from its current folder. The all-users setup is a separate download. It does not delete or move your portable copy or reports.",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 14) });
        Add("Check / repair BAT console", "console", true);
        Add("Repair installed application…", "repair", installed && hasRepair);
        Add("Download setup / latest release…", "releases", true);
        Add("Open Windows installed apps…", "uninstall", installed);
        body.Children.Add(new TextBlock { Text = (installed && !hasRepair ? "The cached setup is missing. Download the setup again to repair this installation.\n\n" : "") +
            "To uninstall an installed copy, select HWID Checker in Windows installed apps. Uninstall removes application files and shortcuts; it keeps saved snapshots and user settings. A portable copy has no installer registration.",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
        root.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled }); Content = root;
        void Add(string label, string action, bool enabled)
        {
            var button = new Button { Content = new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap },
                HorizontalContentAlignment = HorizontalAlignment.Left, IsEnabled = enabled,
                Margin = new Thickness(0, 0, 0, 7), Padding = new Thickness(12, 9, 12, 9) };
            button.Click += (_, _) => { Action = action; Close(); }; body.Children.Add(button);
        }
    }
}
