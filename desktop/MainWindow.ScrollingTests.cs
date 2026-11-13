using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace HwidDesktop;

public partial class MainWindow
{
    private async Task VerifyScrollingAsync(string path)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("A synthetic snapshot is required.");
        var checks = new List<string>();
        void Check(bool value, string message)
        {
            if (!value) throw new InvalidOperationException("Dashboard layout: scrolling: " + message);
            checks.Add(message);
        }
        async Task Settle()
        {
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            UpdateLayout();
            await Task.Delay(100);
        }
        static T? Descendant<T>(DependencyObject root) where T : DependencyObject
        {
            for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            {
                var child = VisualTreeHelper.GetChild(root, index);
                if (child is T match) return match;
                if (Descendant<T>(child) is { } nested) return nested;
            }
            return null;
        }
        static void Wheel(UIElement source, int delta)
        {
            var preview = new MouseWheelEventArgs(Mouse.PrimaryDevice, Environment.TickCount, delta)
                { RoutedEvent = Mouse.PreviewMouseWheelEvent };
            source.RaiseEvent(preview);
            if (!preview.Handled)
                source.RaiseEvent(new MouseWheelEventArgs(Mouse.PrimaryDevice, Environment.TickCount, delta)
                    { RoutedEvent = Mouse.MouseWheelEvent });
        }
        void Press(UIElement source, Key key)
        {
            var keyboardSource = PresentationSource.FromVisual(this)!;
            var preview = new KeyEventArgs(Keyboard.PrimaryDevice, keyboardSource, Environment.TickCount, key)
                { RoutedEvent = Keyboard.PreviewKeyDownEvent };
            source.RaiseEvent(preview);
            if (!preview.Handled)
                source.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice, keyboardSource, Environment.TickCount, key)
                    { RoutedEvent = Keyboard.KeyDownEvent });
        }

        var original = _snapshot;
        UiMotion.SetEnabled(this, false);
        Navigate("Overview");
        await Settle();
        Check(OverviewPage.ScrollableHeight > 100, "the overview fixture has scrollable content");
        OverviewPage.ScrollToVerticalOffset(Math.Min(300, OverviewPage.ScrollableHeight / 2));
        await Settle();
        var scanContent = Descendant<ScrollContentPresenter>(ScanGrid)!;
        var previous = OverviewPage.VerticalOffset;
        Wheel(scanContent, -120);
        await Settle();
        Check(OverviewPage.VerticalOffset > previous, "wheel down over the activity table scrolls Overview");
        previous = OverviewPage.VerticalOffset;
        Wheel(scanContent, 120);
        await Settle();
        Check(OverviewPage.VerticalOffset < previous, "wheel up over the activity table scrolls Overview");
        foreach (var key in new[] { Key.Down, Key.PageDown, Key.End, Key.Up, Key.PageUp, Key.Home })
        {
            OverviewPage.ScrollToVerticalOffset(Math.Min(300, OverviewPage.ScrollableHeight / 2));
            await Settle();
            previous = OverviewPage.VerticalOffset;
            Press(ScanGrid, key);
            await Settle();
            Check(key is Key.Up or Key.PageUp or Key.Home ? OverviewPage.VerticalOffset < previous : OverviewPage.VerticalOffset > previous,
                key + " over the activity table scrolls Overview");
        }

        foreach (var page in new[] { "Identifiers", "Hardware", "Review", "Snapshots", "Compare" })
        {
            Navigate(page);
            var table = page switch
            {
                "Identifiers" => IdentifiersGrid, "Hardware" => HardwareFields, "Review" => ReviewGrid,
                "Snapshots" => SnapshotsGrid, _ => CompareGrid
            };
            table.ItemsSource = page switch
            {
                "Identifiers" => Enumerable.Range(0, 160).Select(i => new IdentifierRow("CPU", "Serial", "SYNTHETIC-" + i, "Reported", "CPU" + i)).ToArray(),
                "Hardware" => Enumerable.Range(0, 160).Select(i => new FieldRow("Field " + i, "SYNTHETIC-" + i)).ToArray(),
                "Review" => Enumerable.Range(0, 160).Select(i => new ReviewRow("Review", "CPU", "Synthetic " + i, "Details " + i)).ToArray(),
                "Snapshots" => Enumerable.Range(0, 160).Select(i => new SnapshotEntry("synthetic-" + i, "synthetic-" + i, "SYNTHETIC", "2026-11-11", "3.91", "1 KB", DateTimeOffset.UnixEpoch)).ToArray(),
                _ => Enumerable.Range(0, 160).Select(i => new ChangeRow("Changed", "CPU " + i, "0001", "0002", "Synthetic change")).ToArray()
            };
            if (page == "Review") ReviewEmptyState.Visibility = Visibility.Collapsed;
            if (page == "Compare") { CompareEmptyState.Visibility = Visibility.Collapsed; CompareGrid.Visibility = Visibility.Visible; }
            await Settle();
            var viewer = Descendant<ScrollViewer>(table)!;
            viewer.ScrollToTop();
            await Settle();
            Check(viewer.ScrollableHeight > 1, page + " has a bounded scrollable table");
            var content = Descendant<ScrollContentPresenter>(table)!;
            Wheel(content, -120);
            await Settle();
            Check(viewer.VerticalOffset > 0, page + " handles wheel down over its rows");
            previous = viewer.VerticalOffset;
            Wheel(content, 120);
            await Settle();
            Check(viewer.VerticalOffset < previous, page + " handles wheel up over its rows");
        }

        Navigate("Review");
        await Settle();
        var reviewViewer = Descendant<ScrollViewer>(ReviewGrid)!;
        reviewViewer.ScrollToVerticalOffset(10);
        ReviewDetail.Text = string.Join("\n", Enumerable.Range(0, 100).Select(i => "Synthetic detail line " + i));
        await Settle();
        var detailViewer = Descendant<ScrollViewer>(ReviewDetail)!;
        detailViewer.ScrollToTop();
        await Settle();
        previous = reviewViewer.VerticalOffset;
        Wheel(Descendant<ScrollContentPresenter>(ReviewDetail)!, -120);
        await Settle();
        Check(detailViewer.VerticalOffset > 0 && reviewViewer.VerticalOffset == previous, "detail scrolling stays inside the detail pane");
        detailViewer.ScrollToTop();
        await Settle();
        Wheel(Descendant<ScrollContentPresenter>(ReviewDetail)!, 120);
        await Settle();
        Check(detailViewer.VerticalOffset == 0 && reviewViewer.VerticalOffset == previous, "a detail boundary does not scroll a sibling table");
        Navigate("Identifiers");
        await Settle();
        var idViewer = Descendant<ScrollViewer>(IdentifiersGrid)!;
        idViewer.ScrollToVerticalOffset(10);
        await Settle();
        previous = idViewer.VerticalOffset;
        IdSearch.Focus();
        Press(IdSearch, Key.Up);
        await Settle();
        Check(idViewer.VerticalOffset == previous, "text editing keys do not scroll a sibling table");
        IdFilter.Focus();
        Wheel(IdFilter, -120);
        await Settle();
        Check(idViewer.VerticalOffset == previous, "filter wheel input does not move a sibling table");

        ApplySnapshot(original);
        Navigate("Overview");
        await Settle();
        var overviewBar = OverviewPage.Template.FindName("PART_VerticalScrollBar", OverviewPage) as ScrollBar
            ?? throw new InvalidOperationException("Dashboard layout: scrolling: Overview has no vertical scrollbar");
        Check(overviewBar.Orientation == Orientation.Vertical, "Overview retains a native vertical scrollbar");
        OverviewPage.ScrollToTop();
        await Settle();
        var track = Descendant<Track>(overviewBar)
            ?? throw new InvalidOperationException("Dashboard layout: scrolling: Overview has no scrollbar track");
        track.Thumb.RaiseEvent(new DragStartedEventArgs(0, 0) { RoutedEvent = Thumb.DragStartedEvent });
        track.Thumb.RaiseEvent(new DragDeltaEventArgs(0, 25) { RoutedEvent = Thumb.DragDeltaEvent });
        track.Thumb.RaiseEvent(new DragCompletedEventArgs(0, 25, false) { RoutedEvent = Thumb.DragCompletedEvent });
        await Settle();
        Check(OverviewPage.VerticalOffset > 0, "scrollbar thumb tracking moves Overview");
        Check(track != null && track.IsDirectionReversed && track.Maximum == overviewBar.Maximum && track.ViewportSize == overviewBar.ViewportSize,
            "the scrollbar track retains range, direction and viewport bindings");
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { success = true, syntheticOnly = true, checks = checks.Count, names = checks }));
        await WriteTestResultAsync(Argument("--verify") ?? path + ".summary.json", true);
    }
}
