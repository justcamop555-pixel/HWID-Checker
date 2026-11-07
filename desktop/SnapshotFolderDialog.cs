using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using Microsoft.Win32;

namespace HwidDesktop;

internal sealed class SnapshotFolderDialog : Window
{
    private readonly string _defaultFolder;
    private readonly string? _settingsPath;
    private SnapshotLibrarySettings _settings;
    private readonly TextBlock _preferred = new();
    private readonly TextBlock _message = new();
    private readonly ListBox _folders = new();
    private readonly Button _choose = new() { Content = "Choose save folder…" };
    private readonly Button _reset = new() { Content = "Use default folder" };
    private readonly Button _add = new() { Content = "Watch a folder…" };
    private readonly Button _remove = new() { Content = "Stop watching selected" };
    private readonly Button _close = new() { Content = "Close", IsCancel = true };
    private bool _saving;

    internal SnapshotFolderDialog(SnapshotLibrarySettings settings, string defaultFolder, string? settingsPath)
    {
        _settings = settings;
        _defaultFolder = defaultFolder;
        _settingsPath = settingsPath;
        Title = "Snapshot folder settings";
        SetResourceReference(StyleProperty, typeof(Window));
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        Width = Math.Clamp(SystemParameters.WorkArea.Width - 16, 1, 540);
        Height = Math.Clamp(SystemParameters.WorkArea.Height - 16, 1, 440);
        MinWidth = Math.Min(405, Width);
        MinHeight = Math.Min(330, Height);

        var layout = new DockPanel { Margin = new Thickness(16) };
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = "Shared save folder", FontSize = 18, FontWeight = FontWeights.SemiBold });
        _preferred.SetResourceReference(StyleProperty, "TrimmedText");
        _preferred.Margin = new Thickness(0, 3, 0, 6);
        header.Children.Add(_preferred);
        header.Children.Add(ButtonRow(_choose, _reset));
        header.Children.Add(new TextBlock
        {
            Text = "Watched folders", FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 12, 0, 2)
        });
        var hint = new TextBlock
        {
            Text = "Both apps look here for earlier JSON snapshots. Built-in report folders are searched automatically.",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6)
        };
        hint.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        header.Children.Add(hint);
        DockPanel.SetDock(header, Dock.Top);
        layout.Children.Add(header);

        var footer = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        var buttons = ButtonRow(_add, _remove, _close);
        footer.Children.Add(buttons);
        _message.Margin = new Thickness(0, 2, 0, 0);
        _message.SetResourceReference(StyleProperty, "TrimmedText");
        footer.Children.Add(_message);
        DockPanel.SetDock(footer, Dock.Bottom);
        layout.Children.Add(footer);

        AutomationProperties.SetName(_folders, "Shared watched folders");
        var listPanel = new Border { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(0), Child = _folders };
        listPanel.SetResourceReference(Border.BackgroundProperty, "PanelBrush");
        listPanel.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
        layout.Children.Add(listPanel);
        Content = layout;

        _choose.Click += async (_, _) => await PickFolderAsync("set-primary", "Choose the shared save folder");
        _reset.Click += async (_, _) => await ChangeAsync("reset-primary", null);
        _add.Click += async (_, _) => await PickFolderAsync("add-folder", "Choose a folder of saved snapshots");
        _remove.Click += async (_, _) =>
        {
            if (SelectedFolder is { } folder) await ChangeAsync("remove-folder", folder);
        };
        _folders.SelectionChanged += (_, _) => UpdateButtons();
        Reload();
    }

    private string? SelectedFolder => (_folders.SelectedItem as ListBoxItem)?.Tag as string;

    private static WrapPanel ButtonRow(params Button[] buttons)
    {
        var row = new WrapPanel();
        foreach (var button in buttons)
        {
            button.Padding = new Thickness(9, 6, 9, 6);
            button.Margin = new Thickness(0, 0, 6, 4);
            row.Children.Add(button);
        }
        return row;
    }

    private void Reload()
    {
        var selected = SelectedFolder;
        _preferred.Text = _settings.Primary ?? "Default · " + _defaultFolder;
        _folders.Items.Clear();
        foreach (var folder in _settings.Folders)
        {
            var text = new TextBlock { Text = folder };
            text.SetResourceReference(StyleProperty, "TrimmedText");
            var item = new ListBoxItem { Content = text, Tag = folder };
            AutomationProperties.SetName(item, folder);
            _folders.Items.Add(item);
            if (folder.Equals(selected, StringComparison.OrdinalIgnoreCase)) _folders.SelectedItem = item;
        }
        ShowMessage(_settings.Error ?? (_settings.Folders.Count == 0 ? "No extra folders are watched." : ""), _settings.Error != null);
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        var enabled = !_saving && _settings.Error == null;
        _choose.IsEnabled = enabled;
        _reset.IsEnabled = enabled && _settings.Primary != null;
        _add.IsEnabled = enabled;
        _remove.IsEnabled = enabled && SelectedFolder is { } folder && !folder.Equals(_settings.Primary, StringComparison.OrdinalIgnoreCase);
        _folders.IsEnabled = !_saving;
        _close.IsEnabled = !_saving;
    }

    private void ShowMessage(string message, bool warning = false)
    {
        _message.Text = message.ReplaceLineEndings(" ");
        _message.ToolTip = message;
        _message.SetResourceReference(TextBlock.ForegroundProperty, warning ? "WarningBrush" : "MutedBrush");
    }

    private async Task PickFolderAsync(string action, string title)
    {
        var picker = new OpenFolderDialog { Title = title };
        if (_settings.Primary is { } primary && System.IO.Directory.Exists(primary)) picker.InitialDirectory = primary;
        else if (System.IO.Directory.Exists(_defaultFolder)) picker.InitialDirectory = _defaultFolder;
        if (picker.ShowDialog(this) == true) await ChangeAsync(action, picker.FolderName);
    }

    private async Task ChangeAsync(string action, string? folder)
    {
        if (_saving) return;
        _saving = true;
        UpdateButtons();
        ShowMessage("Updating shared folders…");
        try
        {
            _settings = await SharedSnapshotLibrary.UpdateAsync(action, folder, _settingsPath);
            Reload();
            if (_settings.Error == null) ShowMessage("Shared folders updated.");
        }
        catch (Exception ex) { ShowMessage("Could not update shared folders. " + ex.Message, true); }
        finally
        {
            _saving = false;
            UpdateButtons();
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (_saving) e.Cancel = true;
        base.OnClosing(e);
    }
}
