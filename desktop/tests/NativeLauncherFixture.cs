using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

// Synthetic child for testing the native launcher without starting WPF or a scan.
internal static class NativeLauncherFixture
{
    private static int Main(string[] args)
    {
        var output = args[0];
        File.WriteAllLines(Path.Combine(output, "arguments.txt"), args);
        File.WriteAllText(Path.Combine(output, "child.pid"), Process.GetCurrentProcess().Id.ToString());
        var parent = Process.GetProcessById(int.Parse(Environment.GetEnvironmentVariable("HWID_LAUNCHER_PID")));
        if (parent.StartTime.ToUniversalTime().Ticks.ToString() != Environment.GetEnvironmentVariable("HWID_LAUNCHER_START_TICKS"))
            return 91;
        if (args[1] == "slow") Thread.Sleep(30000);
        using (var ready = EventWaitHandle.OpenExisting(Environment.GetEnvironmentVariable("HWID_DESKTOP_READY_EVENT")))
            ready.Set();
        Thread.Sleep(450);
        File.WriteAllText(Path.Combine(output, "completed.txt"), "Synthetic child completed.");
        return 17;
    }
}
