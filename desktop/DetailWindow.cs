using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;

namespace HwidDesktop;

internal sealed class DetailWindow : Window
{
    internal readonly TextBox Details;
    internal readonly Button CopyButton;
    internal readonly Button CloseButton;

    internal DetailWindow(string title, string details, string? rawValue)
    {
        SetResourceReference(StyleProperty, typeof(Window));
        Title = title + " — HWID Checker"; ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Width = Math.Min(720, Math.Max(1, SystemParameters.WorkArea.Width - 24));
        Height = Math.Min(520, Math.Max(1, SystemParameters.WorkArea.Height - 24));
        MinWidth = Math.Min(340, Width); MinHeight = Math.Min(280, Height);
        var root = new DockPanel { Margin = new Thickness(16) };
        var heading = new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) };
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        var footer = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var notice = new TextBlock { Text = "Full values are visible here. Copied text may contain sensitive identifiers.",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) };
        notice.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush"); footer.Children.Add(notice);
        var buttons = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        CopyButton = new Button { Content = "Copy original value", IsEnabled = !string.IsNullOrEmpty(rawValue),
            Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(12, 8, 12, 8) };
        CopyButton.Click += (_, _) =>
        {
            if (string.IsNullOrEmpty(rawValue)) return;
            try { Clipboard.SetText(rawValue); notice.Text = "Original value copied. Review it before sharing; Windows clipboard history or sync may retain it."; }
            catch (Exception error) { notice.Text = "Could not copy. Select the text and try again. " + error.Message; }
        };
        CloseButton = new Button { Content = "Close", IsCancel = true, Padding = new Thickness(12, 8, 12, 8) };
        CloseButton.Click += (_, _) => Close(); buttons.Children.Add(CopyButton); buttons.Children.Add(CloseButton);
        footer.Children.Add(buttons); DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        Details = new TextBox { Text = details, IsReadOnly = true, TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        Details.SetResourceReference(StyleProperty, "DetailBox");
        AutomationProperties.SetName(Details, "Complete selected value and explanation");
        root.Children.Add(Details); Content = root;
        Loaded += (_, _) => CloseButton.Focus();
    }
}
