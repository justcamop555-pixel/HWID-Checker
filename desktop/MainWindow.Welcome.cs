using System.Windows;

namespace HwidDesktop;

public partial class MainWindow
{
    private bool _welcomeSeen, _showWelcomeOnStartup, _welcomeOpen;
    private long _preferencesRevision;

    private static bool ShouldShowWelcome(bool verification, bool restoring, bool seen, bool everyLaunch) =>
        !verification && !restoring && (!seen || everyLaunch);

    private async void OnOpenWelcome(object sender, RoutedEventArgs e) => await ShowWelcomeAsync();

    private async Task ShowWelcomeAsync(string? preferencesPath = null)
    {
        if (_busy || _closing || _closeRequested || _welcomeOpen) return;
        _welcomeOpen = true; UpdateButtons();
        try
        {
            var welcome = new WelcomeWindow(_showWelcomeOnStartup) { Owner = this };
            if (welcome.ShowDialog() != true) return;
            _welcomeSeen = true;
            _showWelcomeOnStartup = welcome.ShowOnFutureLaunches;
            if (!await RememberPreferencesAsync(preferencesPath))
                ShowStatus("Welcome preference could not be saved", "The app is ready to use. This notice may appear again when you next open it.", true);
        }
        catch (Exception error) { ShowError("Welcome message could not open", error); }
        finally { _welcomeOpen = false; UpdateButtons(); }
    }
}
