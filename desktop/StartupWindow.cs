using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace HwidDesktop;

internal sealed class StartupWindow : Window
{
    private readonly CancellationTokenSource _cancellation = new();
    private readonly CancellationToken _token;
    private readonly TextBlock _step;
    private bool _preparing;
    internal CancellationToken Cancellation => _token;
    internal bool BeginPreparation() { if (_preparing) return false; _preparing = true; return true; }

    internal StartupWindow()
    {
        SetResourceReference(StyleProperty, typeof(Window));
        _token = _cancellation.Token;
        Title = "Starting HWID Checker"; Width = Math.Min(470, SystemParameters.WorkArea.Width - 16);
        SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(new TextBlock { Text = "Starting HWID Checker", FontSize = 24, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        _step = new TextBlock { Text = "Preparing the local application…", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 14, 0, 12) };
        _step.SetResourceReference(TextBlock.ForegroundProperty, "AccentBrush"); panel.Children.Add(_step);
        var progress = new ProgressBar { Height = 4, Minimum = 0, Maximum = 100, Value = 0 };
        progress.SetResourceReference(ProgressBar.IsIndeterminateProperty, SystemParameters.ClientAreaAnimationKey);
        panel.Children.Add(progress);
        var note = new TextBlock { Text = "Slower PCs may take longer on the first launch. You can close this window to cancel. Scanning starts when you choose Scan this PC.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) };
        note.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush"); panel.Children.Add(note);
        var frame = new Border { Child = panel }; frame.SetResourceReference(BackgroundProperty, "CanvasBrush"); Content = frame;
        Closed += (_, _) => { _cancellation.Cancel(); _cancellation.Dispose(); };
    }
    internal void SetStep(string text) => _step.Text = text;
}
