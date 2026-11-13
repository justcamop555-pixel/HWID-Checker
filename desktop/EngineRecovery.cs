using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace HwidDesktop;

internal sealed record PreparedConsole(string BatPath, string Launcher, string Runtime, bool Recovered);

/// <summary>Uses the embedded, build-matched scanner when a companion is missing or invalid.
/// Custom files are never overwritten; restored files live in a separate user-owned folder.</summary>
internal static class EngineRecovery
{
    private const int MaximumSourceBytes = 8 * 1024 * 1024;
    private const string Probe = """
        $ErrorActionPreference='Stop'
        if($PSVersionTable.PSVersion -lt [version]'5.1' -or $ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){exit 20}
        try {
          $reader=[IO.StreamReader]::new($env:HWID_PROBE_BAT)
          try {
            if($reader.BaseStream.Length -le 0 -or $reader.BaseStream.Length -gt 8388608){exit 21}
            $raw=$reader.ReadToEnd()
          } finally {$reader.Dispose()}
          $parts=$raw -split '(?m)^# POWERSHELL_START\r?$',2
          if($parts.Count -ne 2 -or $parts[1] -notmatch 'function\s+Get-CheckerTheme\b'){exit 21}
          $t=$null;$e=$null
          $null=[Management.Automation.Language.Parser]::ParseInput($parts[1],[ref]$t,[ref]$e)
          if($e.Count){exit 21}
          if($env:HWID_PROBE_LOADER){
            $null=[Management.Automation.Language.Parser]::ParseFile($env:HWID_PROBE_LOADER,[ref]$t,[ref]$e)
            if($e.Count){exit 21}
          }
          exit 0
        } catch {exit 21}
        """;

    internal static byte[] Resource(string name)
    {
        using var input = typeof(EngineRecovery).Assembly.GetManifestResourceStream("HwidDesktop.Recovery." + name)
            ?? throw new IOException("This desktop build has no bundled scanner. Reinstall the complete desktop package.");
        using var output = new MemoryStream(); input.CopyTo(output);
        if (output.Length == 0 || output.Length > MaximumSourceBytes) throw new IOException("The bundled scanner is incomplete.");
        return output.ToArray();
    }

    internal static string Restore(string? recoveryRoot = null)
    {
        var bat = Resource("Bat"); var launcher = Resource("Launcher");
        var fingerprint = Convert.ToHexString(SHA256.HashData(bat.Concat(launcher).ToArray()));
        var root = recoveryRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "HWID Checker", "RecoveredScanner");
        var folder = Path.Combine(Path.GetFullPath(root), fingerprint);
        Directory.CreateDirectory(folder);
        Publish(Path.Combine(folder, "hwid.bat"), bat);
        Publish(Path.Combine(folder, "Start-HWID.ps1"), launcher);
        return Path.Combine(folder, "hwid.bat");
    }

    private static void Publish(string path, byte[] bytes)
    {
        if (Matches(path, bytes)) return;
        var temporary = path + ".pending-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllBytes(temporary, bytes);
            if (!Matches(temporary, bytes)) throw new IOException("Restored scanner verification failed.");
            File.Move(temporary, path, true);
            if (!Matches(path, bytes)) throw new IOException("The restored scanner changed before it could be used.");
        }
        finally { try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    private static bool Matches(string path, byte[] expected)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return stream.Length == expected.Length && SHA256.HashData(stream).AsSpan().SequenceEqual(SHA256.HashData(expected));
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    internal static string ReadScannerText(string path)
    {
        using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 or > MaximumSourceBytes)
            throw new IOException("The scanner is empty or exceeds the supported 8 MB size. Use a complete HWID Checker BAT.");
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        var text = reader.ReadToEnd();
        var markers = Regex.Matches(text, @"(?m)^# POWERSHELL_START\r?$");
        if (markers.Count != 1 || string.IsNullOrWhiteSpace(text[(markers[0].Index + markers[0].Length)..]))
            throw new InvalidDataException("The BAT does not contain a complete embedded scanner. Use Open BAT console to restore the bundled copy, or choose a complete BAT.");
        return text;
    }

    private static bool NeedsLauncher(string path) => Path.GetFileName(path).Equals("hwid.bat", StringComparison.OrdinalIgnoreCase);
    private static bool HasCompanions(string? path) => path != null && File.Exists(path)
        && new FileInfo(path).Length is > 0 and <= MaximumSourceBytes
        && (!NeedsLauncher(path) ||
            (File.Exists(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "Start-HWID.ps1"))
            && new FileInfo(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "Start-HWID.ps1")).Length is > 0 and <= MaximumSourceBytes));

    internal static async Task<PreparedConsole> PrepareAsync(string? preferred, IEnumerable<string> runtimes,
        CancellationToken token, string? recoveryRoot = null)
    {
        token.ThrowIfCancellationRequested();
        string? source = null;
        try { if (HasCompanions(preferred)) source = Path.GetFullPath(preferred!); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException) { }
        var candidates = runtimes.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (candidates.Length == 0) throw new IOException("PowerShell is unavailable. Install or enable an approved Windows PowerShell 5.1 or PowerShell 7 runtime.");
        foreach (var recovered in source == null ? new[] { true } : new[] { false, true })
        {
            if (recovered) source = await Task.Run(() => Restore(recoveryRoot), token);
            var launcher = Path.Combine(Path.GetDirectoryName(source!)!, "Start-HWID.ps1");
            foreach (var runtime in candidates)
            {
                token.ThrowIfCancellationRequested();
                var result = await ProbeAsync(runtime, source!, launcher, token);
                if (result == 0) return new(source!, launcher, runtime, recovered);
                // Syntax can be runtime-specific. Try every installed runtime
                // before deciding the selected source needs the bundled fallback.
            }
        }
        throw new IOException("The console could not pass its startup check. Check that an approved PowerShell runtime can run. No security settings were changed; custom scanner files were kept.");
    }

    private static async Task<int> ProbeAsync(string runtime, string bat, string launcher, CancellationToken token)
    {
        var start = new ProcessStartInfo(runtime) { UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var arg in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(Probe)) }) start.ArgumentList.Add(arg);
        start.Environment["HWID_PROBE_BAT"] = bat;
        start.Environment["HWID_PROBE_LOADER"] = NeedsLauncher(bat) ? launcher : "";
        using var process = new Process { StartInfo = start };
        try
        {
            if (!process.Start()) return 20;
            var stdout = process.StandardOutput.ReadToEndAsync(token);
            var stderr = process.StandardError.ReadToEndAsync(token);
            await process.WaitForExitAsync(token).WaitAsync(TimeSpan.FromSeconds(8), token);
            await Task.WhenAll(stdout, stderr);
            return process.ExitCode;
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or TimeoutException or InvalidOperationException) { return 20; }
        finally { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } }
    }

    internal static ProcessStartInfo StartInfo(PreparedConsole prepared, bool dark)
    {
        var start = new ProcessStartInfo(prepared.Runtime) { UseShellExecute = false, CreateNoWindow = false,
            WorkingDirectory = Path.GetDirectoryName(prepared.BatPath)! };
        foreach (var arg in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass" })
            start.ArgumentList.Add(arg);
        if (Path.GetFileName(prepared.BatPath).Equals("hwid.bat", StringComparison.OrdinalIgnoreCase))
        {
            start.ArgumentList.Add("-File"); start.ArgumentList.Add(prepared.Launcher);
        }
        else
        {
            // The standard loader resolves a sibling named hwid.bat. A renamed
            // custom scanner must be addressed explicitly without shell quoting.
            const string launch = """
                $ErrorActionPreference='Stop'
                try {
                  $env:HWID_SCRIPT=$env:HWID_DESKTOP_SOURCE
                  $parts=[IO.File]::ReadAllText($env:HWID_SCRIPT) -split '(?m)^# POWERSHELL_START\r?$',2
                  if($parts.Count -ne 2){throw 'The scanner is incomplete.'}
                  & ([scriptblock]::Create($parts[1]))
                } catch {Write-Error $_;exit 1}
                """;
            start.ArgumentList.Add("-EncodedCommand");
            start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(launch)));
            start.Environment["HWID_DESKTOP_SOURCE"] = prepared.BatPath;
        }
        start.Environment["HWID_THEME"] = dark ? "Midnight" : "Daylight";
        foreach (var name in new[] { "HWID_OWN_CONSOLE", "HWID_CURRENT_WINDOW", "HWID_STARTUP_SIGNAL", "HWID_RESTART_SIGNAL" })
            start.Environment.Remove(name);
        return start;
    }
}
