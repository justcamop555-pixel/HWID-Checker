using System.Windows;
using System.IO;
using System.Text.Json;

namespace HwidDesktop;
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            if (WriteAutomationFailure(e.Args, args.Exception)) { args.Handled = true; Shutdown(1); return; }
            MessageBox.Show("The desktop app could not finish this action.\n\n" + args.Exception.Message,
                "HWID Checker", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
        try
        {
            var window = new MainWindow(e.Args);
            MainWindow = window;
            window.Show();
        }
        catch (Exception ex)
        {
            if (!WriteAutomationFailure(e.Args, ex)) MessageBox.Show("HWID Checker could not start.\n\n" + ex.Message, "HWID Checker", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    private static bool WriteAutomationFailure(string[] args, Exception error)
    {
        for (var i = 0; i + 1 < args.Length; i++)
            if (args[i] is "--verify" or "--scan-test")
            {
                var layoutFailure = error.Message.StartsWith("Dashboard layout:", StringComparison.Ordinal) ? error.Message : null;
                try { File.WriteAllText(args[i + 1], JsonSerializer.Serialize(new { success = false, errorType = error.GetType().FullName, layoutFailure, hardwareIdentifiersSaved = false })); } catch { }
                return true;
            }
        return false;
    }
}
