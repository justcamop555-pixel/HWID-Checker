using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

internal static class Program
{
    private const BindingFlags Members = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length is < 1 or > 2)
        {
            Console.Error.WriteLine("Usage: OverviewMetricsPerf <packaged HWID Checker.dll> [result.json]");
            return 2;
        }
        Window? window = null;
        try
        {
            var assemblyPath = Path.GetFullPath(args[0]);
            var folder = Path.GetDirectoryName(assemblyPath)!;
            AssemblyLoadContext.Default.Resolving += (_, name) =>
            {
                if (name.Name == null || Path.GetFileName(name.Name) != name.Name) return null;
                var path = Path.Combine(folder, name.Name + ".dll");
                return File.Exists(path) ? AssemblyLoadContext.Default.LoadFromAssemblyPath(path) : null;
            };
            var assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(assemblyPath);
            var app = (Application)Activator.CreateInstance(assembly.GetType("HwidDesktop.App", true)!)!;
            app.GetType().GetMethod("InitializeComponent", Members)!.Invoke(app, null);
            var windowType = assembly.GetType("HwidDesktop.MainWindow", true)!;
            // Verification arguments skip user preferences. Never Show or Run:
            // Loaded/OnStartup cannot connect a scanner or enumerate reports.
            window = (Window)Activator.CreateInstance(windowType, [new[] { "--fixture", "synthetic-placeholder" }, null])!;
            ((DispatcherTimer)windowType.GetField("_timer", Members)!.GetValue(window)!).Stop();
            var refresh = windowType.GetMethod("UpdateOverviewMetrics", Members)!.CreateDelegate<Action>(window);
            var apply = windowType.GetMethod("ApplySnapshot", Members)!;
            var snapshotField = windowType.GetField("_snapshot", Members)!;
            var snapshotType = assembly.GetType("HwidDesktop.DesktopSnapshot", true)!;
            var applyTheme = windowType.GetMethod("ApplyTheme", Members)!.CreateDelegate<Action<bool>>(window);
            var checks = 0;
            TextBlock Label(string name) => (TextBlock)window.FindName(name);
            void Check(bool condition, string name)
            {
                if (!condition) throw new InvalidOperationException(name);
                checks++; Console.WriteLine("PASS: " + name);
            }
            bool UsesBrush(string name, string resource) => Label(name).Foreground is SolidColorBrush actual &&
                window.FindResource(resource) is SolidColorBrush expected && actual.Color == expected.Color;
            object Capture(int count)
            {
                using var document = JsonDocument.Parse(JsonSerializer.Serialize(new
                {
                    version = "3.96",
                    inventory = new Dictionary<string, object>
                    {
                        ["Report info"] = new { ExtendedStatus = "Refreshed", Computer = "SYNTHETIC" },
                        ["CPU"] = new[] { new { Name = "Synthetic CPU" } },
                        ["Extended device inventory"] = Enumerable.Range(0, count)
                            .Select(index => new { DeviceInstanceId = "SYNTHETIC\\000" + index, Name = "Synthetic device" }).ToArray()
                    },
                    identifiers = Array.Empty<object>(), review = new { }
                }));
                return Activator.CreateInstance(snapshotType, [document.RootElement])!;
            }

            Check(Label("ReviewCount").Text == "Not checked" && Label("DevicesCount").Text == "Not scanned",
                "initial overview contains no invented findings or device counts");
            Check(UsesBrush("ReviewCount", "MutedBrush"), "initial review is neutral");
            const int records = 3000, iterations = 500;
            var capture = Capture(records);
            apply.Invoke(window, [capture]);
            for (var pass = 0; pass < 5; pass++) refresh();
            var watch = new Stopwatch();
            var beforeBytes = GC.GetAllocatedBytesForCurrentThread();
            watch.Start();
            for (var pass = 0; pass < iterations; pass++) refresh();
            watch.Stop();
            var allocated = GC.GetAllocatedBytesForCurrentThread() - beforeBytes;
            Check(Label("DevicesCount").Text == records.ToString("N0", CultureInfo.CurrentCulture) && Label("ReviewCount").Text == "0",
                "repeated unchanged refreshes retain exact captured metrics");
            foreach (var dark in new[] { false, true })
            {
                applyTheme(dark); refresh();
                Check(UsesBrush("ReviewCount", "MutedBrush"),
                    (dark ? "Midnight" : "Daylight") + " dynamic neutral brush follows theme changes");
            }
            var replacement = Capture(7);
            apply.Invoke(window, [replacement]);
            refresh();
            Check(Label("DevicesCount").Text == "7", "accepting a different capture replaces the old count");
            // Explicitly reapplying an accepted object must still refresh its
            // publicly mutable timing list; reference reuse cannot mask this.
            var timing = (IList)snapshotType.GetProperty("Timing")!.GetValue(replacement)!;
            timing.Add(Activator.CreateInstance(assembly.GetType("HwidDesktop.ScanRow", true)!,
                ["CPU", "READ", "1", "Synthetic read", "0.1 s"]));
            apply.Invoke(window, [replacement]);
            Check(Label("SectionsCount").Text == "1 / 1", "explicit reapplication refreshes timing even when the snapshot reference is reused");
            snapshotField.SetValue(window, null); refresh();
            Check(Label("ReviewCount").Text == "Not checked" && UsesBrush("ReviewCount", "MutedBrush"),
                "returning to no accepted capture clears old findings");
            Check(!window.IsVisible, "the probe never opens a desktop window");
            var result = new
            {
                success = true, checks, syntheticOnly = true, actualHardwareRead = false,
                userSettingsRead = false, applicationVersion = assembly.GetName().Version?.ToString(),
                benchmark = new { records, iterations, elapsedMilliseconds = watch.Elapsed.TotalMilliseconds,
                    allocatedBytes = allocated, timingThresholdEnforced = false, measuredOperation = "unchanged overview metric refresh" }
            };
            var json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
            if (args.Length == 2) File.WriteAllText(Path.GetFullPath(args[1]), json);
            Console.WriteLine(json);
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.ToString());
            return 1;
        }
        finally
        {
            if (window != null)
            {
                var timer = (DispatcherTimer?)window.GetType().GetField("_timer", Members)?.GetValue(window);
                timer?.Stop();
                window.Close();
            }
        }
    }
}
