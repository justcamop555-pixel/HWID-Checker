using System.Diagnostics;
using System.IO;

namespace HwidDesktop;

internal enum InstallationScope { Portable, CurrentUser, AllUsers, SetupManaged }

internal static class InstallationLayout
{
    internal const string MarkerName = "HWID-SETUP.ini";
    internal const string ReleasesUrl = "https://github.com/justcamop555-pixel/HWID-Checker/releases/latest";

    internal static bool IsManaged(string directory) => File.Exists(Path.Combine(directory, MarkerName)) ||
        IsPersonalDirectory(directory) ||
        IsMachineDirectory(directory);

    private static bool IsMachineDirectory(string directory) =>
        IsUnder(directory, Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)) ||
        IsUnder(directory, Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)) ||
        IsUnder(directory, Environment.GetEnvironmentVariable("ProgramW6432"));

    private static bool IsPersonalDirectory(string directory) => IsUnder(directory,
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "HWID Checker"));

    internal static InstallationScope Scope(string directory)
    {
        // Protected/default install locations take priority over a damaged marker.
        if (IsMachineDirectory(directory)) return InstallationScope.AllUsers;
        if (IsPersonalDirectory(directory)) return InstallationScope.CurrentUser;
        var marker = Path.Combine(directory, MarkerName);
        if (!File.Exists(marker)) return InstallationScope.Portable;
        try
        {
            using var stream = File.Open(marker, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length > 4096) return InstallationScope.SetupManaged;
            using var reader = new StreamReader(stream);
            var buffer = new char[4097]; var length = reader.ReadBlock(buffer, 0, buffer.Length);
            if (length > 4096) return InstallationScope.SetupManaged;
            var section = ""; string? scope = null;
            foreach (var line in new string(buffer, 0, length).Split('\n'))
            {
                var text = line.Trim();
                if (text.StartsWith('[')) { section = text; continue; }
                if (!section.Equals("[Installation]", StringComparison.OrdinalIgnoreCase)) continue;
                var pair = text.Split('=', 2);
                if (pair.Length == 2 && pair[0].Trim().Equals("Scope", StringComparison.OrdinalIgnoreCase))
                {
                    if (scope != null) return InstallationScope.SetupManaged;
                    scope = pair[1].Trim();
                }
            }
            if (string.Equals(scope, "CurrentUser", StringComparison.OrdinalIgnoreCase)) return InstallationScope.CurrentUser;
            if (string.Equals(scope, "AllUsers", StringComparison.OrdinalIgnoreCase)) return InstallationScope.AllUsers;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        return InstallationScope.SetupManaged;
    }

    internal static string SetupGuidance(InstallationScope scope) => scope switch
    {
        InstallationScope.CurrentUser => "This copy is installed just for you. Run the new setup in Just for me mode; administrator approval is not required.",
        InstallationScope.AllUsers => "This copy is installed for all users. Run the new setup in All users mode; administrator approval is required.",
        _ => "Run the new setup using the same installation type as this copy. Administrator approval is required only for All users."
    };

    internal static ProcessStartInfo RepairStartInfo(string directory) => new(RepairSetup(directory))
    {
        UseShellExecute = true,
        Arguments = Scope(directory) switch { InstallationScope.CurrentUser => "/CURRENTUSER", InstallationScope.AllUsers => "/ALLUSERS", _ => "" }
    };

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
