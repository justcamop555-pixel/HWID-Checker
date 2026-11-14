using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace HwidDesktop;

public partial class MainWindow
{
    private void ShowSelectedValue(string title, string details, string? raw) =>
        new DetailWindow(title, details, raw) { Owner = this }.ShowDialog();

    private void OpenSelectedDetails(object? selected)
    {
        switch (selected)
        {
            case IdentifierRow id: ShowSelectedValue(id.Field, ValueExplanation.Identifier(id), id.Value); break;
            case FieldRow field: ShowSelectedValue(field.Field, field.Value +
                (field.RawValue != null && field.RawValue != field.Value ? "\n\nOriginal value\n" + field.RawValue : ""), field.RawValue ?? field.Value); break;
            case ReviewRow review: ShowSelectedValue(review.Kind, ValueExplanation.Review(review), null); break;
        }
    }
    private void OnDetailsKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || Keyboard.Modifiers != ModifierKeys.None || sender is not DataGrid grid || grid.SelectedItem == null) return;
        e.Handled = true; OpenSelectedDetails(grid.SelectedItem);
    }
    private void OnDetailsDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is DataGrid grid && e.OriginalSource is DependencyObject source &&
            ItemsControl.ContainerFromElement(grid, source) is DataGridRow row) OpenSelectedDetails(row.Item);
    }

    private void OnMaintenance(object sender, RoutedEventArgs e)
    {
        if (_busy || IsVerification) return;
        var installed = InstallationLayout.IsManaged(AppContext.BaseDirectory);
        var setup = InstallationLayout.RepairSetup(AppContext.BaseDirectory);
        var dialog = new MaintenanceWindow(installed, File.Exists(setup)) { Owner = this };
        dialog.ShowDialog();
        try
        {
            if (dialog.Action == "repair")
            {
                // The cached setup lives in the admin-owned install directory. Windows owns the UAC prompt.
                // Do not close the app until setup actually starts; a cancelled UAC prompt must be harmless.
                if (!File.Exists(setup)) throw new FileNotFoundException("The saved setup is missing. Download the setup again from Releases.");
                using var process = Process.Start(new ProcessStartInfo(setup) { UseShellExecute = true, Verb = "runas" });
                ShowStatus("Setup opened", "Save your current scan, then close this app when setup asks. Saved snapshots and settings are kept.");
            }
            else if (dialog.Action == "releases") InstallationLayout.OpenReleases();
            else if (dialog.Action == "uninstall") Process.Start(new ProcessStartInfo("ms-settings:appsfeatures") { UseShellExecute = true });
            else if (dialog.Action == "console") OnOpenConsole(sender, e);
        }
        catch (System.ComponentModel.Win32Exception error) when (error.NativeErrorCode == 1223)
        { ShowStatus("Setup cancelled", "No repair was started. Your current scan remains open."); }
        catch (Exception error) { ShowError("Could not open setup", error); }
    }
}
