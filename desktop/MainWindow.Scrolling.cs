using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Media3D;

namespace HwidDesktop;

public partial class MainWindow
{
    private static IEnumerable<DependencyObject> ScrollAncestors(DependencyObject? source)
    {
        for (var current = source; current != null;)
        {
            yield return current;
            current = current switch
            {
                Visual or Visual3D => VisualTreeHelper.GetParent(current),
                FrameworkContentElement content => content.Parent,
                _ => LogicalTreeHelper.GetParent(current)
            };
        }
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer viewer) return viewer;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            if (FindScrollViewer(VisualTreeHelper.GetChild(root, index)) is { } child) return child;
        return null;
    }

    private ScrollViewer? PageScrollViewer() => _page switch
    {
        "Overview" => OverviewPage,
        "Identifiers" => FindScrollViewer(IdentifiersGrid),
        "Hardware" => FindScrollViewer(HardwareFields),
        "Review" => FindScrollViewer(ReviewGrid),
        "Snapshots" => FindScrollViewer(SnapshotsGrid),
        "Compare" => FindScrollViewer(CompareGrid),
        _ => null
    };

    private static bool CanScroll(ScrollViewer viewer, bool up) =>
        viewer.IsVisible && viewer.IsEnabled && viewer.VerticalScrollBarVisibility != ScrollBarVisibility.Disabled &&
        (up ? viewer.VerticalOffset > 0.001 : viewer.ScrollableHeight - viewer.VerticalOffset > 0.001);

    private void OnPageMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled || e.Delta == 0 || Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
        var ancestors = ScrollAncestors(e.OriginalSource as DependencyObject).ToArray();
        // Drop-downs retain their native item selection and popup scrolling.
        if (ancestors.Any(item => item is ComboBox)) return;
        var viewers = ancestors.OfType<ScrollViewer>().ToArray();
        var target = viewers.FirstOrDefault(viewer => CanScroll(viewer, e.Delta > 0));
        // Allow wheel scrolling over a page's table border/header, without moving
        // a sibling table when a detail pane has reached its own boundary.
        if (target == null && viewers.Length == 0 && ancestors.Contains(PageHost) &&
            !ancestors.Any(item => item is TextBoxBase or PasswordBox))
            target = PageScrollViewer();
        if (target == null || !CanScroll(target, e.Delta > 0)) return;

        // Delegate to WPF's normal wheel handler: it knows physical versus logical
        // scrolling, virtualized rows and the user's configured wheel settings.
        var forwarded = new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta)
            { RoutedEvent = Mouse.MouseWheelEvent };
        target.RaiseEvent(forwarded);
        e.Handled = forwarded.Handled;
    }

    private void OnPageScrollKey(object sender, KeyEventArgs e)
    {
        if (e.Handled || Keyboard.Modifiers.HasFlag(ModifierKeys.Alt) ||
            Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) return;
        var key = e.Key;
        if (key is not (Key.Up or Key.Down or Key.PageUp or Key.PageDown or Key.Home or Key.End)) return;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && key is not (Key.Home or Key.End)) return;
        var ancestors = ScrollAncestors(e.OriginalSource as DependencyObject).ToArray();
        if (ancestors.Any(item => item is TextBoxBase or PasswordBox or ComboBox or ScrollBar)) return;
        if ((key is Key.Up or Key.Down) && ancestors.Any(item => item is ButtonBase)) return;
        // Other lists and grids keep selection/cell navigation. The activity table
        // is fully expanded inside Overview, so its scroll keys belong to the page.
        if (ancestors.Any(item => item is DataGrid grid && grid != ScanGrid || item is ListBox)) return;
        var up = key is Key.Up or Key.PageUp or Key.Home;
        var viewers = ancestors.OfType<ScrollViewer>().ToArray();
        var target = viewers.FirstOrDefault(viewer => CanScroll(viewer, up));
        if (target == null && viewers.Length == 0) target = PageScrollViewer();
        if (target == null || !CanScroll(target, up)) return;
        switch (key)
        {
            case Key.Up: target.LineUp(); break;
            case Key.Down: target.LineDown(); break;
            case Key.PageUp: target.PageUp(); break;
            case Key.PageDown: target.PageDown(); break;
            case Key.Home: target.ScrollToTop(); break;
            case Key.End: target.ScrollToBottom(); break;
        }
        e.Handled = true;
    }
}
