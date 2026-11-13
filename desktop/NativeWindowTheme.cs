using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace HwidDesktop;

// Keep the real Windows title bar and its native resize/snap/accessibility
// behavior. Unsupported DWM attributes simply leave the system frame intact.
internal static class NativeWindowTheme
{
    public static readonly DependencyProperty CaptionBrushProperty = DependencyProperty.RegisterAttached(
        "CaptionBrush", typeof(Brush), typeof(NativeWindowTheme), new PropertyMetadata(null, Changed));
    public static readonly DependencyProperty TextBrushProperty = DependencyProperty.RegisterAttached(
        "TextBrush", typeof(Brush), typeof(NativeWindowTheme), new PropertyMetadata(null, Changed));
    public static readonly DependencyProperty BorderBrushProperty = DependencyProperty.RegisterAttached(
        "BorderBrush", typeof(Brush), typeof(NativeWindowTheme), new PropertyMetadata(null, Changed));
    private static readonly DependencyProperty SubscriptionProperty = DependencyProperty.RegisterAttached(
        "Subscription", typeof(Subscription), typeof(NativeWindowTheme));

    public static void SetCaptionBrush(DependencyObject target, Brush value) => target.SetValue(CaptionBrushProperty, value);
    public static Brush? GetCaptionBrush(DependencyObject target) => (Brush?)target.GetValue(CaptionBrushProperty);
    public static void SetTextBrush(DependencyObject target, Brush value) => target.SetValue(TextBrushProperty, value);
    public static Brush? GetTextBrush(DependencyObject target) => (Brush?)target.GetValue(TextBrushProperty);
    public static void SetBorderBrush(DependencyObject target, Brush value) => target.SetValue(BorderBrushProperty, value);
    public static Brush? GetBorderBrush(DependencyObject target) => (Brush?)target.GetValue(BorderBrushProperty);

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(nint window, int attribute, ref uint value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(nint window, int attribute, out uint value, int size);

    private static void Changed(DependencyObject target, DependencyPropertyChangedEventArgs args)
    {
        if (target is not Window window) return;
        if (window.GetValue(SubscriptionProperty) == null)
            window.SetValue(SubscriptionProperty, new Subscription(window));
        Apply(window);
    }

    internal static uint ColorRef(Color color) => (uint)(color.R | color.G << 8 | color.B << 16);

    internal static bool Apply(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == 0) return false;
        var background = (GetCaptionBrush(window) as SolidColorBrush)?.Color;
        var foreground = (GetTextBrush(window) as SolidColorBrush)?.Color;
        var border = (GetBorderBrush(window) as SolidColorBrush)?.Color;
        var highContrast = SystemParameters.HighContrast;
        uint dark = !highContrast && background is { } color && (0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B) < 128 ? 1u : 0u;
        var caption = !highContrast && background is { } bg ? ColorRef(bg) : uint.MaxValue;
        var text = !highContrast && foreground is { } fg ? ColorRef(fg) : uint.MaxValue;
        var frame = !highContrast && border is { } edge ? ColorRef(edge) : uint.MaxValue;
        try
        {
            DwmSetWindowAttribute(handle, 20, ref dark, 4);
            var captionResult = DwmSetWindowAttribute(handle, 35, ref caption, 4);
            var textResult = DwmSetWindowAttribute(handle, 36, ref text, 4);
            DwmSetWindowAttribute(handle, 34, ref frame, 4);
            return captionResult == 0 && textResult == 0;
        }
        catch (DllNotFoundException) { return false; }
        catch (EntryPointNotFoundException) { return false; }
    }

    internal static bool Read(Window window, int attribute, out uint value)
    {
        value = 0;
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == 0) return false;
        try { return DwmGetWindowAttribute(handle, attribute, out value, 4) == 0; }
        catch (DllNotFoundException) { return false; }
        catch (EntryPointNotFoundException) { return false; }
    }

    private sealed class Subscription
    {
        private readonly Window _window;
        internal Subscription(Window window)
        {
            _window = window;
            window.SourceInitialized += Ready;
            window.Activated += Ready;
            window.Deactivated += Ready;
            window.Closed += Closed;
            SystemParameters.StaticPropertyChanged += SystemChanged;
        }
        private void Ready(object? sender, EventArgs args) => Apply(_window);
        private void SystemChanged(object? sender, PropertyChangedEventArgs args)
        {
            if (args.PropertyName == nameof(SystemParameters.HighContrast) && !_window.Dispatcher.HasShutdownStarted)
                _window.Dispatcher.BeginInvoke(new Action(() => Apply(_window)));
        }
        private void Closed(object? sender, EventArgs args)
        {
            SystemParameters.StaticPropertyChanged -= SystemChanged;
            _window.SourceInitialized -= Ready;
            _window.Activated -= Ready;
            _window.Deactivated -= Ready;
            _window.Closed -= Closed;
        }
    }
}
