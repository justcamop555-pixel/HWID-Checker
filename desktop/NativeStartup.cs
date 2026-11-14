using System.Diagnostics;
using System.IO;
using System.Globalization;

namespace HwidDesktop;

internal static class NativeStartup
{
    internal static void SignalReady()
    {
        var name = Environment.GetEnvironmentVariable("HWID_DESKTOP_READY_EVENT");
        if (name == null || !System.Text.RegularExpressions.Regex.IsMatch(name, @"\ALocal\\HWID-Startup-[a-fA-F0-9-]{36}\z")) return;
        try { using var ready = EventWaitHandle.OpenExisting(name); ready.Set(); }
        catch (Exception error) when (error is WaitHandleCannotBeOpenedException or UnauthorizedAccessException or IOException) { }
    }

    // The launcher waits for this process. Updating must wait for BOTH executables
    // to exit, otherwise Windows can still have the launcher image locked.
    internal static Process? TryGetLauncher()
    {
        if (!int.TryParse(Environment.GetEnvironmentVariable("HWID_LAUNCHER_PID"), out var id) || id <= 0 || id == Environment.ProcessId ||
            !long.TryParse(Environment.GetEnvironmentVariable("HWID_LAUNCHER_START_TICKS"), NumberStyles.None, CultureInfo.InvariantCulture, out var ticks)) return null;
        Process? process = null;
        try
        {
            process = Process.GetProcessById(id);
            if (!process.HasExited && process.StartTime.ToUniversalTime().Ticks == ticks &&
                string.Equals(process.MainModule?.FileName, Path.Combine(AppContext.BaseDirectory, "HWID Checker.exe"), StringComparison.OrdinalIgnoreCase)) return process;
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { }
        process?.Dispose(); return null;
    }
}
