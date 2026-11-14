using System.Diagnostics;
using System.IO;

namespace HwidDesktop;

internal static class InstallationLayout
{
    internal const string MarkerName = "HWID-SETUP.ini";
    internal const string ReleasesUrl = "https://github.com/justcamop555-pixel/HWID-Checker/releases/latest";

    internal static bool IsManaged(string directory) => File.Exists(Path.Combine(directory, MarkerName)) ||
        IsUnder(directory, Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)) ||
        IsUnder(directory, Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)) ||
        IsUnder(directory, Environment.GetEnvironmentVariable("ProgramW6432"));

    internal static bool IsUnder(string directory, string? root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;
        var path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        var parent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        return path.Equals(parent, StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    internal static string ReportsFolder(string directory) => IsManaged(directory)
        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HWID Checker", "HWID-Reports")
        : Path.Combine(directory, "HWID-Reports");

    internal static string RepairSetup(string directory) => Path.Combine(directory, "Maintenance",
        "HWID-Checker-Setup-" + DesktopUpdater.CurrentVersion + "-win-x64.exe");

    internal static void OpenReleases() => Process.Start(new ProcessStartInfo(ReleasesUrl) { UseShellExecute = true });
}
