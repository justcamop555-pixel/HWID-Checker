using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace HwidDesktop;

internal sealed class ConsoleRepairWindow : Window
{
    internal readonly Button RepairButton;
    internal readonly Button CancelButton;
    internal readonly ScrollViewer DetailsScroll;

    internal ConsoleRepairWindow(string reason, string? sourcePath)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Title = "Repair BAT console — HWID Checker";
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        Width = Math.Min(590, SystemParameters.WorkArea.Width - 24);
        Height = Math.Min(430, SystemParameters.WorkArea.Height - 24);
        MinWidth = Math.Min(360, Width); MinHeight = Math.Min(300, Height);
        var layout = new DockPanel { Margin = new Thickness(20) };
        var actions = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        CancelButton = new Button { Content = "Not now", IsCancel = true, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(14, 8, 14, 8) };
        RepairButton = new Button { Content = "Repair and open", Padding = new Thickness(14, 8, 14, 8) };
        RepairButton.SetResourceReference(StyleProperty, "PrimaryButton");
        CancelButton.Click += (_, _) => DialogResult = false;
        RepairButton.Click += (_, _) => DialogResult = true;
        actions.Children.Add(CancelButton); actions.Children.Add(RepairButton);
        DockPanel.SetDock(actions, Dock.Bottom); layout.Children.Add(actions);
        var details = new StackPanel();
        void Add(string text, bool heading = false)
        {
            var label = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) };
            if (heading) { label.FontSize = 23; label.FontWeight = FontWeights.SemiBold; }
            else label.SetResourceReference(StyleProperty, "Muted");
            details.Children.Add(label);
        }
        Add("Repair the BAT console?", true);
        Add(reason);
        if (!string.IsNullOrWhiteSpace(sourcePath)) Add("Checked file: " + sourcePath);
        Add("Repair and open restores the scanner bundled with this Desktop app to its local recovery folder, connects it, and opens the BAT console.");
        Add("Your existing files, current scan and saved snapshots are kept. No download is needed. You can also choose Not now and connect another BAT.");
        DetailsScroll = new ScrollViewer { Content = details, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        AutomationProperties.SetName(DetailsScroll, "BAT repair details");
        layout.Children.Add(DetailsScroll); Content = layout;
        Loaded += (_, _) => CancelButton.Focus();
    }
}
