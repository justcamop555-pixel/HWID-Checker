using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace HwidDesktop;

// An existence-only mutex marks this install directory while Desktop runs.
// It does not enforce a single app instance or interfere with restart handoff.
internal static class SetupSession
{
    internal static string MutexName(string directory)
    {
        var path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        // Fold ASCII consistently with Inno Setup, independent of Windows language.
        var folded = new string(path.Select(c => c is >= 'a' and <= 'z' ? (char)(c - 32) : c).ToArray());
        return @"Local\HWID-Desktop-" + Convert.ToHexString(SHA256.HashData(Encoding.Unicode.GetBytes(folded))).ToLowerInvariant();
    }

    internal static Mutex? Hold(string directory)
    {
        try { return new Mutex(false, MutexName(directory)); }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or WaitHandleCannotBeOpenedException) { return null; }
    }
}
