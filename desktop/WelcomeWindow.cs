using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace HwidDesktop;

internal sealed class WelcomeWindow : Window
{
    internal readonly CheckBox ShowOnStartup;
    internal readonly Button ContinueButton;
    internal readonly Button LaterButton;
    internal readonly ScrollViewer NoticeScroll;
    internal readonly StackPanel Footer;

    internal bool ShowOnFutureLaunches => ShowOnStartup.IsChecked == true;

    internal WelcomeWindow(bool showOnStartup)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Title = "Welcome — HWID Checker";
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        Width = Math.Min(620, Math.Max(1, SystemParameters.WorkArea.Width - 24));
        Height = Math.Min(590, Math.Max(1, SystemParameters.WorkArea.Height - 24));
        MinWidth = Math.Min(360, Width);
        MinHeight = Math.Min(360, Height);

        var layout = new DockPanel { Margin = new Thickness(20) };
        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        var title = new TextBlock { Text = "Welcome to HWID Checker", FontSize = 25,
            FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
        header.Children.Add(title);
        var introduction = new TextBlock
        {
            Text = "View the hardware and device identifiers Windows reports, then save a snapshot or compare changes.",
            Margin = new Thickness(0, 7, 0, 0)
        };
        introduction.SetResourceReference(StyleProperty, "Muted");
        DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);

        Footer = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
        ShowOnStartup = new CheckBox { IsChecked = showOnStartup, Margin = new Thickness(0, 0, 0, 9) };
        ShowOnStartup.SetResourceReference(Control.ForegroundProperty, "TextBrush");
        ShowOnStartup.SetResourceReference(Control.BackgroundProperty, "ControlBrush");
        ShowOnStartup.SetResourceReference(Control.BorderBrushProperty, "ControlBorderBrush");
        ShowOnStartup.Content = new TextBlock { Text = "Show this message on future app launches", TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetName(ShowOnStartup, "Show this welcome on future app launches");
        Footer.Children.Add(ShowOnStartup);
        var reminder = new TextBlock { Text = "Reopen this message from Welcome & privacy in the sidebar.", FontSize = 12,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) };
        reminder.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        var actions = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        LaterButton = new Button { Content = "Not now", IsCancel = true, Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(0, 0, 8, 0) };
        LaterButton.Click += (_, _) => DialogResult = false;
        ContinueButton = new Button { Content = "Open dashboard", IsDefault = true, Padding = new Thickness(14, 8, 14, 8) };
        ContinueButton.SetResourceReference(StyleProperty, "PrimaryButton");
        ContinueButton.Click += (_, _) => DialogResult = true;
        actions.Children.Add(LaterButton); actions.Children.Add(ContinueButton); Footer.Children.Add(actions);
        DockPanel.SetDock(Footer, Dock.Bottom); layout.Children.Add(Footer);

        var notices = new StackPanel();
        introduction.Margin = new Thickness(0, 0, 4, 14);
        notices.Children.Add(introduction);
        notices.Children.Add(Notice("Read-only hardware scan", "Scanning reads Windows-reported values. It does not change your hardware identifiers.", "AccentBrush"));
        notices.Children.Add(Notice("Keep identifiers private", "Reports can include serial numbers, device IDs, MAC addresses and your PC name. Review or redact them before sharing.", "WarningBrush"));
        notices.Children.Add(Notice("Review before sharing", "Saved snapshots, exports and copied values contain full identifiers. Saving does not redact them. Keep an original JSON baseline for comparison and redact a separate copy before sharing.", "WarningBrush"));
        notices.Children.Add(Notice("Know where your files go", "Hardware scanning runs locally. Update checks contact GitHub without sending your scan reports. Files saved in OneDrive or another synced folder may be uploaded by that service.", "AccentBrush"));
        notices.Children.Add(Notice("Clipboard and saved files", "Copy actions use the Windows clipboard. Clipboard history or sync may retain that text. Reports are not encrypted by HWID Checker. A Windows account with access to their folder may read them.", "WarningBrush"));
        notices.Children.Add(Notice("Installation and removal", "All-users setup needs administrator approval; normal scans can run as a standard user. Each user keeps separate folder settings and a local default report folder. Repair and uninstall keep saved snapshots and user settings.", "AccentBrush"));
        notices.Children.Add(reminder);
        NoticeScroll = new ScrollViewer { Content = notices, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        AutomationProperties.SetName(NoticeScroll, "Read-only scan and report privacy notice");
        layout.Children.Add(NoticeScroll);
        var root = new Grid(); root.SetResourceReference(Panel.BackgroundProperty, "CanvasBrush");
        root.Children.Add(layout); Content = root;
        Loaded += (_, _) => ContinueButton.Focus();
    }

    private static Border Notice(string heading, string text, string color)
    {
        var content = new StackPanel();
        var title = new TextBlock { Text = heading, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
        title.SetResourceReference(TextBlock.ForegroundProperty, color);
        content.Children.Add(title);
        var body = new TextBlock { Text = text, Margin = new Thickness(0, 5, 0, 0) };
        body.SetResourceReference(StyleProperty, "Muted"); content.Children.Add(body);
        var frame = new Border { Child = content, Padding = new Thickness(12), Margin = new Thickness(0, 0, 4, 10) };
        frame.SetResourceReference(StyleProperty, "Card");
        return frame;
    }
}
