param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText($Source);$header=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[0]
$root=Join-Path $PSScriptRoot ("test-output-preparation ! & ' "+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Run-Headless($Path,$PathOverride) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe';$start.Arguments='/d /c ""'+$Path+'""'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    if($null -ne $PathOverride){$start.EnvironmentVariables['PATH']=$PathOverride}
    $clock=[Diagnostics.Stopwatch]::StartNew();$child=[Diagnostics.Process]::Start($start);$child.StandardInput.Close()
    $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(15000)){$child.Kill();throw 'Headless preparation fixture exceeded 15 seconds.'}
    $clock.Stop();$result=[pscustomobject]@{Code=$child.ExitCode;Output=($stdout.Result+$stderr.Result);Seconds=$clock.Elapsed.TotalSeconds};$child.Dispose();return $result
}
function Make-Fixture($Name,$Header,$Body) {
    $folder=Join-Path $root $Name;[void][IO.Directory]::CreateDirectory($folder);$path=Join-Path $folder 'hwid.bat'
    [IO.File]::WriteAllText($path,($Header+[Environment]::NewLine+'# POWERSHELL_START'+[Environment]::NewLine+$Body),[Text.UTF8Encoding]::new($false));return $path
}
$normal=Make-Fixture 'normal' $header 'Write-Output "PREPARATION_OK"'
$result=Run-Headless $normal $null
Assert ($result.Code -eq 0 -and $result.Output -match 'PREPARATION_OK') 'The preparation helper preserves successful startup from a shell-punctuation path'
Assert ($result.Output -match '(?s)\[1/3\].*3-second reading pause.*\[2/3\].*\[3/3\].*PREPARATION_OK') 'Preparation describes the reading pause before any PowerShell checks'
Assert ($result.Output -match 'Countdown unavailable.*continuing startup' -and $result.Seconds -lt 12) 'Closed/redirected input skips an unavailable native countdown without blocking startup'
Assert ($result.Output -notmatch 'Input redirection is not supported|not recognized|cannot find') 'Native timer errors do not spill into the launcher screen'
$missingHeader=$header.Replace('%SystemRoot%\System32\timeout.exe','%SystemRoot%\System32\hwid-nonexistent-test-timer.exe')
$missing=Make-Fixture 'missing-timer' $missingHeader 'Write-Output "PREPARATION_OK"'
$result=Run-Headless $missing $null
Assert ($result.Code -eq 0 -and $result.Output -match 'Countdown unavailable' -and $result.Output -match 'PREPARATION_OK') 'A missing timer remains an optional presentation failure'
$timerLine=@($header -split '\r?\n' | Where-Object {$_ -like '"%SystemRoot%\System32\timeout.exe" *'})[0]
Assert (-not [string]::IsNullOrWhiteSpace($timerLine)) 'The countdown uses the Windows timer by absolute path'
$failedHeader=$header.Replace($timerLine,'"%SystemRoot%\System32\cmd.exe" /d /c exit 7')
$failed=Make-Fixture 'failed-timer' $failedHeader 'exit 23'
$result=Run-Headless $failed $null
Assert ($result.Code -eq 23 -and $result.Output -match 'Countdown unavailable' -and $result.Output -match 'START-02.*23') 'Timer failures do not replace the actual checker exit code'
$shadow=Join-Path $root 'shadow';[void][IO.Directory]::CreateDirectory($shadow)
[IO.File]::WriteAllText((Join-Path $shadow 'timeout.cmd'),"@echo SHADOW_TIMER_USED`r`n@exit /b 0`r`n",[Text.Encoding]::ASCII)
$result=Run-Headless $normal $shadow
Assert ($result.Code -eq 0 -and $result.Output -notmatch 'SHADOW_TIMER_USED' -and $result.Output -match 'PREPARATION_OK') 'A timeout command on PATH cannot shadow the Windows timer'
$result=Run-Headless $normal ''
Assert ($result.Code -eq 0 -and $result.Output -match 'PREPARATION_OK') 'Preparation and standard runtime discovery work with an empty PATH'
$noRuntimeHeader=$header -replace '(?m)^(call :hwid_try_engine |for %%P in ).*\r?$','rem Test: no runtime candidates'
$noRuntime=Make-Fixture 'missing-runtime' $noRuntimeHeader 'THIS MUST NEVER PARSE @('
$result=Run-Headless $noRuntime $null
Assert ($result.Code -eq 10 -and $result.Output -match 'COMPAT-01' -and $result.Output -notmatch '\[3/3\]|ParserError') 'Missing runtimes still stop before the starting stage or body parsing'
$probeLine=@($header -split '\r?\n' | Where-Object {$_ -like '"%~1" *'})[0]
$blocked=Make-Fixture 'blocked-runtime' ($header.Replace($probeLine,'"%~1" -NoLogo -NoProfile -Command "exit 13" >nul 2>nul')) 'THIS MUST NEVER PARSE @('
$result=Run-Headless $blocked $null
Assert ($result.Code -eq 13 -and $result.Output -match 'COMPAT-02' -and $result.Output -notmatch '\[3/3\]|ParserError') 'The reading pause does not bypass restricted runtime checks'
$markerLine='echo   [2/3] Checking for compatible PowerShell...'
$nativeHeader=$header.Replace($markerLine,('> "%HWID_PREP_PROBE%" echo READY'+[Environment]::NewLine+$markerLine))
$native=Make-Fixture 'native' $nativeHeader '[IO.File]::WriteAllText($env:HWID_PREP_BODY,"OK")'
$diagnostic=@'
$ErrorActionPreference='Stop'
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HwidPreparationTestKeys {
    [StructLayout(LayoutKind.Explicit, Size=20)] public struct Input {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort Key;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr input, Input[] records, uint length, out uint written);
    public static bool QueueEnter() { uint written; return WriteConsoleInputW(GetStdHandle(-10),new[] {new Input {Type=1,Down=1,Repeat=20,Key=13}},1,out written) && written==1; }
}
"@
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe';$start.Arguments='/d /c ""__BATCH__""';$start.UseShellExecute=$false;$start.CreateNoWindow=$false
    $start.EnvironmentVariables['HWID_PREP_PROBE']='__PROBE__';$start.EnvironmentVariables['HWID_PREP_BODY']='__BODY__'
    $queued=[HwidPreparationTestKeys]::QueueEnter()
    $clock=[Diagnostics.Stopwatch]::StartNew();$child=[Diagnostics.Process]::Start($start)
    while(-not (Test-Path -LiteralPath '__PROBE__')){if($clock.Elapsed.TotalSeconds -gt 10){$child.Kill();throw 'Native countdown did not finish.'};Start-Sleep -Milliseconds 20}
    $seconds=$clock.Elapsed.TotalSeconds
    if(-not $child.WaitForExit(15000)){$child.Kill();throw 'Native fixture did not finish launching.'}
    @{SecondsBeforeProbe=$seconds;EnterQueued=$queued;ExitCode=$child.ExitCode;BodyExecuted=(Test-Path -LiteralPath '__BODY__')} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
    $child.Dispose()
}catch{@{Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8;exit 1}
'@
$probe=Join-Path $root 'probe.txt';$bodyMarker=Join-Path $root 'body.txt';$nativeResult=Join-Path $root 'native-result.json'
$diagnostic=$diagnostic.Replace('__BATCH__',$native.Replace("'","''")).Replace('__PROBE__',$probe.Replace("'","''")).Replace('__BODY__',$bodyMarker.Replace("'","''")).Replace('__RESULT__',$nativeResult.Replace("'","''"))
$scriptPath=Join-Path $root 'native-probe.ps1';[IO.File]::WriteAllText($scriptPath,$diagnostic,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$arguments='-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
if(-not $child.WaitForExit(30000)){throw 'Native preparation checks exceeded 30 seconds.'}
$nativeResult=Get-Content -LiteralPath $nativeResult -Raw | ConvertFrom-Json
if($nativeResult.Error){throw $nativeResult.Error}
Assert ($nativeResult.EnterQueued) 'The native test queued held Enter before startup'
Assert ($nativeResult.SecondsBeforeProbe -ge 2 -and $nativeResult.SecondsBeforeProbe -lt 10) 'An attached CMD window keeps preparation readable before the first PowerShell probe despite queued Enter'
Assert ($nativeResult.ExitCode -eq 0 -and $nativeResult.BodyExecuted) 'Native countdown completion proceeds to the checker successfully'
[Console]::WriteLine(('Measured preparation before runtime probes: {0:0.00}s.' -f $nativeResult.SecondsBeforeProbe))
[Console]::WriteLine("All $checks startup-delay checks passed under PowerShell $($PSVersionTable.PSVersion).")
