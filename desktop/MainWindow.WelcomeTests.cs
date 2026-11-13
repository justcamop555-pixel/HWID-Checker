using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private async Task VerifyWelcomeAsync(string path)
    {
        if (!IsVerification) throw new InvalidOperationException("Welcome verification requires a fixture.");
        var checks = new List<string>();
        void Check(bool condition, string text)
        {
            if (!condition) throw new InvalidOperationException("Dashboard layout: welcome: " + text);
            checks.Add(text);
        }
        var originalSeen = _welcomeSeen; var originalRepeat = _showWelcomeOnStartup;
        var directory = Path.Combine(Path.GetDirectoryName(path)!, "welcome-fixtures");
        Directory.CreateDirectory(directory);
        Check(ShouldShowWelcome(false, false, false, false), "first cold launch offers the welcome notice");
        Check(!ShouldShowWelcome(false, false, true, false), "acknowledged one-time notices stay dismissed");
        Check(ShouldShowWelcome(false, false, true, true), "repeat preference offers the notice on a later cold launch");
        Check(!ShouldShowWelcome(false, true, false, true), "session-preserving restart does not repeat the notice");
        Check(!ShouldShowWelcome(true, false, false, true), "automated scans and fixtures do not open startup notices");
        try
        {
            foreach (var dark in new[] { true, false })
            foreach (var size in new[] { (Width: 620d, Height: 590d), (Width: 500d, Height: 420d), (Width: 360d, Height: 360d) })
            {
                var compact = size.Width < 620;
                ApplyTheme(dark);
                _welcomeSeen = false; _showWelcomeOnStartup = false;
                var name = (dark ? "midnight" : "daylight") + $"-{size.Width:0}x{size.Height:0}";
                var settings = Path.Combine(directory, name + ".json");
                _ = Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
                {
                    var dialog = Application.Current.Windows.OfType<WelcomeWindow>().Single();
                    dialog.Width = size.Width; dialog.Height = size.Height;
                    dialog.UpdateLayout();
                    var content = (FrameworkElement)dialog.Content;
                    var footer = dialog.Footer.TransformToAncestor(content).TransformBounds(new Rect(dialog.Footer.RenderSize));
                    Check(footer.Top >= 0 && footer.Bottom <= content.ActualHeight + 1 && dialog.ContinueButton.IsVisible && dialog.LaterButton.IsVisible,
                        name + " keeps both actions in the visible footer");
                    var notice = dialog.NoticeScroll.TransformToAncestor(content).TransformBounds(new Rect(dialog.NoticeScroll.RenderSize));
                    Check(dialog.NoticeScroll.ViewportHeight >= 55 && notice.Bottom <= footer.Top + 1 && notice.Top >= 0,
                        name + " keeps a usable scrollable privacy notice above the fixed actions");
                    var firstAction = dialog.LaterButton.TransformToAncestor(content).TransformBounds(new Rect(dialog.LaterButton.RenderSize));
                    var primaryAction = dialog.ContinueButton.TransformToAncestor(content).TransformBounds(new Rect(dialog.ContinueButton.RenderSize));
                    Check(firstAction.Left >= 0 && primaryAction.Right <= content.ActualWidth + 1 && !firstAction.IntersectsWith(primaryAction),
                        name + " keeps keyboard actions separate and inside the window");
                    Check(dialog.FontSize == 14 && dialog.ContinueButton.IsDefault && dialog.LaterButton.IsCancel && Keyboard.FocusedElement == dialog.ContinueButton,
                        name + " retains readable body text, keyboard focus, Enter and Escape actions");
                    Check(dialog.ShowOnStartup.Foreground is SolidColorBrush label && label.Color == ((SolidColorBrush)Application.Current.Resources["TextBrush"]).Color,
                        name + " preference label follows the readable theme text color");
                    if (compact)
                    {
                        dialog.NoticeScroll.ScrollToBottom(); dialog.UpdateLayout();
                        Check(dialog.NoticeScroll.VerticalOffset > 0 && dialog.NoticeScroll.HorizontalScrollBarVisibility == ScrollBarVisibility.Disabled,
                            name + " scrolls the complete notice without horizontal clipping");
                    }
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(content.ActualWidth), (int)Math.Ceiling(content.ActualHeight), 96, 96, PixelFormats.Pbgra32);
                    bitmap.Render(content);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using (var stream = File.Create(Path.Combine(directory, name + ".png"))) encoder.Save(stream);
                    dialog.ShowOnStartup.IsChecked = compact;
                    dialog.ContinueButton.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
                }));
                await ShowWelcomeAsync(settings);
                using var saved = JsonDocument.Parse(await File.ReadAllTextAsync(settings));
                Check(_welcomeSeen && !_welcomeOpen && WelcomeButton.IsEnabled && saved.RootElement.Flag("welcomeSeen") &&
                    saved.RootElement.Flag("showWelcomeOnStartup") == compact && saved.RootElement.Flag("darkTheme") == _darkTheme,
                    name + " saves the chosen welcome preference while preserving the theme");
            }
            _welcomeSeen = false; _showWelcomeOnStartup = false;
            var laterSettings = Path.Combine(directory, "not-now.json");
            _ = Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
                Application.Current.Windows.OfType<WelcomeWindow>().Single().LaterButton.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent))));
            await ShowWelcomeAsync(laterSettings);
            Check(!_welcomeSeen && !_welcomeOpen && !File.Exists(laterSettings), "Not now leaves the first-launch notice available without writing preferences");

            var concurrentSettings = Path.Combine(directory, "concurrent.json");
            _welcomeSeen = false; _showWelcomeOnStartup = true;
            var older = RememberPreferencesAsync(concurrentSettings);
            _welcomeSeen = true; _showWelcomeOnStartup = false;
            var newer = RememberPreferencesAsync(concurrentSettings);
            await Task.WhenAll(older, newer);
            using (var saved = JsonDocument.Parse(await File.ReadAllTextAsync(concurrentSettings)))
                Check(saved.RootElement.Flag("welcomeSeen") && !saved.RootElement.Flag("showWelcomeOnStartup"),
                    "an older asynchronous save cannot overwrite the newest welcome choice");
            var pending = RememberPreferencesAsync(concurrentSettings);
            _showWelcomeOnStartup = true;
            Check(RememberPreferencesNow(concurrentSettings), "close-path preferences save completes synchronously");
            await pending;
            using (var saved = JsonDocument.Parse(await File.ReadAllTextAsync(concurrentSettings)))
                Check(saved.RootElement.Flag("showWelcomeOnStartup"), "a pending asynchronous save cannot overwrite close-path preferences");
            _welcomeSeen = false; _showWelcomeOnStartup = false;
            LoadPreferences(concurrentSettings);
            Check(_welcomeSeen && _showWelcomeOnStartup, "welcome preferences survive loading a saved settings file");
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = true, checks = checks.Count, names = checks,
                syntheticOnly = true, hardwareIdentifiersSaved = false }));
        }
        finally { _welcomeSeen = originalSeen; _showWelcomeOnStartup = originalRepeat; ApplyTheme(_darkTheme); }
    }
}
