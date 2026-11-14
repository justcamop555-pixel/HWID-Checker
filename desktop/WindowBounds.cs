using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace HwidDesktop;

internal static class WindowBounds
{
    public static readonly DependencyProperty EnabledProperty = DependencyProperty.RegisterAttached("Enabled", typeof(bool),
        typeof(WindowBounds), new PropertyMetadata(false, Changed));
    public static bool GetEnabled(DependencyObject target) => (bool)target.GetValue(EnabledProperty);
    public static void SetEnabled(DependencyObject target, bool value) => target.SetValue(EnabledProperty, value);
    private static void Changed(DependencyObject target, DependencyPropertyChangedEventArgs args)
    { if (target is Window window && args.NewValue is true) _ = new Subscription(window); }

    internal static Size AvailableDip(double widthPx, double heightPx, double dpi) => new(
        Math.Max(1, widthPx * 96 / Math.Max(96, dpi) - 16),
        Math.Max(1, heightPx * 96 / Math.Max(96, dpi) - 16));

    [StructLayout(LayoutKind.Sequential)] private struct RECT { internal int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MONITORINFO { internal int Size; internal RECT Monitor, Work; internal uint Flags; }
    [DllImport("user32.dll")] private static extern nint MonitorFromWindow(nint hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(nint monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint hwnd, nint after, int x, int y, int width, int height, uint flags);

    private sealed class Subscription
    {
        private readonly Window window;
        private HwndSource? source;
        private bool loaded, queued, fitting, closed;
        private double minWidth, minHeight;
        internal Subscription(Window window)
        {
            this.window = window;
            window.Loaded += Loaded; window.Closed += Closed; window.StateChanged += Changed;
        }
        private void Loaded(object sender, RoutedEventArgs args)
        {
            if (loaded || !ReferenceEquals(args.OriginalSource, window)) return;
            loaded = true; minWidth = window.MinWidth; minHeight = window.MinHeight;
            source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
            source?.AddHook(Hook); Fit();
        }
        private void Changed(object? sender, EventArgs args) => Queue();
        private nint Hook(nint hwnd, int message, nint w, nint l, ref bool handled)
        {
            // Let WPF process the suggested DPI rectangle first. Do not fight
            // interactive resizing or snap a window back midway through a drag.
            if (message is 0x02E0 or 0x007E or 0x001A or 0x0232) Queue();
            return 0;
        }
        private void Queue()
        {
            if (!loaded || queued || closed || window.Dispatcher.HasShutdownStarted) return;
            queued = true; window.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => { queued = false; Fit(); }));
        }
        private void Fit()
        {
            if (closed || fitting || !window.IsVisible || window.WindowState == WindowState.Minimized) return;
            fitting = true;
            try
            {
                var hwnd = new WindowInteropHelper(window).Handle;
                var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
                if (hwnd == 0 || !GetMonitorInfo(MonitorFromWindow(hwnd, 2), ref info) || !GetWindowRect(hwnd, out var rect)) return;
                var dpi = GetDpiForWindow(hwnd); if (dpi == 0) dpi = 96;
                var available = AvailableDip(info.Work.Right - info.Work.Left, info.Work.Bottom - info.Work.Top, dpi);
                window.MinWidth = Math.Min(minWidth, available.Width); window.MinHeight = Math.Min(minHeight, available.Height);
                if (window.WindowState != WindowState.Normal) return;
                var inset = Math.Max(1, (int)Math.Round(8 * dpi / 96.0));
                var width = Math.Min(rect.Right - rect.Left, Math.Max(1, info.Work.Right - info.Work.Left - 2 * inset));
                var height = Math.Min(rect.Bottom - rect.Top, Math.Max(1, info.Work.Bottom - info.Work.Top - 2 * inset));
                var left = Math.Clamp(rect.Left, info.Work.Left + inset, Math.Max(info.Work.Left + inset, info.Work.Right - inset - width));
                var top = Math.Clamp(rect.Top, info.Work.Top + inset, Math.Max(info.Work.Top + inset, info.Work.Bottom - inset - height));
                if (width != rect.Right - rect.Left || height != rect.Bottom - rect.Top || left != rect.Left || top != rect.Top)
                {
                    if (window.SizeToContent != SizeToContent.Manual) window.SizeToContent = SizeToContent.Manual;
                    SetWindowPos(hwnd, 0, left, top, width, height, 0x0014);
                }
            }
            catch (EntryPointNotFoundException) { /* Older Windows retains WPF's own DPI behavior. */ }
            finally { fitting = false; }
        }
        private void Closed(object? sender, EventArgs args)
        {
            closed = true; source?.RemoveHook(Hook); source = null;
            window.Loaded -= Loaded; window.Closed -= Closed; window.StateChanged -= Changed;
        }
    }
}
