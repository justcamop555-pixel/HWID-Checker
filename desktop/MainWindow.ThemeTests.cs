using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private async Task VerifyNativeThemeAsync(string path)
    {
        if (!IsVerification) throw new InvalidOperationException("Theme checks require verification mode.");
        var checks = new List<string>();
        void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException("Dashboard layout: native theme: " + message);
            checks.Add(message);
        }
        async Task Settle()
        {
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            UpdateLayout();
            await Task.Delay(80);
        }
        var folder = Path.Combine(Path.GetDirectoryName(path)!, "theme-dialogs");
        Directory.CreateDirectory(folder);
        using var updater = new DesktopUpdater(AppContext.BaseDirectory, Path.Combine(folder, "updates"));
        var updates = new UpdateWindow(updater, EngineVersionText.Text, () => false, () => { }) { Owner = this };
        var library = new SnapshotFolderDialog(new SnapshotLibrarySettings(null, []), folder, Path.Combine(folder, "settings.json")) { Owner = this };
        var welcome = new WelcomeWindow(false) { Owner = this };
        try
        {
            updates.Show(); library.Show(); welcome.Show();
            foreach (var dark in new[] { true, false, true })
            {
                ApplyTheme(dark); await Settle();
                var expectedCaption = NativeWindowTheme.ColorRef(((SolidColorBrush)Application.Current.Resources["SidebarBrush"]).Color);
                var expectedText = NativeWindowTheme.ColorRef(((SolidColorBrush)Application.Current.Resources["TextBrush"]).Color);
                foreach (var window in new Window[] { this, updates, library, welcome })
                {
                    Check(NativeWindowTheme.GetCaptionBrush(window) is SolidColorBrush captionBrush && NativeWindowTheme.ColorRef(captionBrush.Color) == expectedCaption,
                        window.GetType().Name + " follows the " + (dark ? "dark" : "light") + " caption resource");
                    var supported = NativeWindowTheme.Read(window, 35, out var caption) && NativeWindowTheme.Read(window, 36, out _);
                    if (supported && !SystemParameters.HighContrast)
                    {
                        Check(caption == expectedCaption, window.GetType().Name + " native caption matches the selected theme");
                        Check(NativeWindowTheme.Read(window, 36, out var text) && text == expectedText,
                            window.GetType().Name + " native caption text matches the selected theme");
                    }
                    else Check(NativeWindowTheme.Apply(window) || !OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000) || SystemParameters.HighContrast,
                        window.GetType().Name + " accepts caption colors or retains the older/system frame");
                }
            }
            Check(ResizeMode == ResizeMode.CanResize && WindowStyle == WindowStyle.SingleBorderWindow,
                "main window retains native resize and title-bar controls");
            Check(!File.Exists(Path.Combine(folder, "settings.json")), "opening themed dialogs does not change library settings");
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = true, checks = checks.Count, names = checks,
                nativeCaptionApplied = NativeWindowTheme.Apply(this), nativeColorReadbackAvailable = NativeWindowTheme.Read(this, 35, out _),
                highContrast = SystemParameters.HighContrast, syntheticOnly = true }));
        }
        finally { welcome.Close(); library.Close(); updates.Close(); ApplyTheme(_darkTheme); }
    }
}
