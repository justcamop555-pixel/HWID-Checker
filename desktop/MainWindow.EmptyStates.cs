using System.Windows;

namespace HwidDesktop;

public partial class MainWindow
{
    private void UpdateHardwareEmptyState()
    {
        if (!_initialized) return;
        HardwareRecord.IsEnabled = _snapshot != null && HardwareRecord.Items.Count > 0;
        HardwareSectionPicker.IsEnabled = _snapshot != null && HardwareSections.Items.Count > 0;
        HardwareSearch.IsEnabled = _snapshot != null && HardwareSections.SelectedItem is HardwareSection;
        var hasFields = _snapshot != null && HardwareFields.Items.Count > 0;
        HardwareFields.Visibility = hasFields ? Visibility.Visible : Visibility.Collapsed;
        HardwareEmptyState.Visibility = hasFields ? Visibility.Collapsed : Visibility.Visible;
        HardwareDetail.Visibility = hasFields ? Visibility.Visible : Visibility.Collapsed;
        HardwareDetailRow.MinHeight = hasFields ? Dashboard.ActualHeight < 600 ? 52 : 70 : 0;
        HardwareDetailRow.Height = new GridLength(hasFields ? 0.42 : 0, GridUnitType.Star);
        if (hasFields) return;
        CopyHardwareButton.IsEnabled = false;
        var filtered = _snapshot != null && HardwareSearch.Text.Trim().Length > 0 && HardwareRecord.Items.Count == 0;
        HardwareEmptyTitle.Text = filtered ? "No records match this search" : _snapshot == null ?
            "Scan this PC to view hardware" : "No fields captured for this selection";
        HardwareEmptyText.Text = filtered ? "Search applies to the selected section. Clear it to see that section's records." :
            _snapshot == null ? "Captured components and their Windows-reported fields will appear here after the scan finishes." :
            "Windows supplied no fields for this selection. Choose another section or rescan after your devices change.";
        HardwareEmptyAction.Content = filtered ? "Clear search" : _busy && _operation == "Scan" ? "View scan progress" :
            _engine == null ? "Connect BAT…" : "Scan this PC";
        HardwareEmptyAction.Tag = filtered ? "ClearHardware" : _busy && _operation == "Scan" ? "Overview" : _engine == null ? "Connect" : "Scan";
        HardwareEmptyAction.IsEnabled = !_busy || (string?)HardwareEmptyAction.Tag is "ClearHardware" or "Overview";
    }

    private void UpdateSnapshotEmptyState()
    {
        if (!_initialized) return;
        var hasRows = SnapshotsGrid.Items.Count > 0;
        SnapshotEmptyState.Visibility = hasRows ? Visibility.Collapsed : Visibility.Visible;
        // Keep the grid visible beneath the overlay so native column layout and
        // scrolling remain initialized when a newly saved capture arrives.
        if (hasRows) return;
        if (_snapshotCatalogRefreshing && _snapshotEntries.Count == 0)
        {
            SnapshotEmptyTitle.Text = "Looking for saved snapshots";
            SnapshotEmptyText.Text = "Reading JSON captures in your shared folders. You can keep browsing the app.";
            SnapshotEmptyAction.Visibility = Visibility.Collapsed;
            return;
        }
        if (_snapshotCatalogError == null && _snapshotEntries.Count > 0 && SnapshotSearch.Text.Trim().Length > 0)
        {
            SnapshotEmptyTitle.Text = "No snapshots match your search";
            SnapshotEmptyText.Text = "Try a PC name, part of a file name or a folder. Clearing the search shows all saved snapshots.";
            SnapshotEmptyAction.Content = "Clear search"; SnapshotEmptyAction.Tag = "ClearSnapshots";
            SnapshotEmptyAction.Visibility = Visibility.Visible; SnapshotEmptyAction.IsEnabled = true;
            return;
        }
        SnapshotEmptyTitle.Text = _snapshotCatalogError != null ? "Could not read the snapshot library" :
            !_snapshotCatalogLoaded ? "Looking for saved snapshots" : "No saved snapshots found";
        SnapshotEmptyText.Text = _snapshotCatalogError ?? (!_snapshotCatalogLoaded ? "Checking the shared report folders on this PC." :
            _snapshotCatalogSkipped > 0 ? $"{_snapshotCatalogSkipped} files or folders could not be read as snapshots. Check Folder settings, or save a new capture." :
            "Save a completed scan as TXT + JSON. Captures in your shared report folders appear here for comparison.");
        var scanning = _busy && _operation == "Scan";
        SnapshotEmptyAction.Content = _snapshotCatalogError != null ? "Try again" : scanning ? "View scan progress" :
            _engine == null ? "Connect BAT…" : _snapshot == null ? "Scan this PC" : "Save snapshot";
        SnapshotEmptyAction.Tag = _snapshotCatalogError != null ? "RefreshSnapshots" : scanning ? "Overview" :
            _engine == null ? "Connect" : _snapshot == null ? "Scan" : "Save";
        SnapshotEmptyAction.Visibility = _snapshotCatalogLoaded ? Visibility.Visible : Visibility.Collapsed;
        SnapshotEmptyAction.IsEnabled = !_busy || (string?)SnapshotEmptyAction.Tag == "Overview";
    }
}
