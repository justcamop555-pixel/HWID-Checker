param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1'
$root=Join-Path $PSScriptRoot ('test-output-animation-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$resultPath=Join-Path $root 'result.json'
$diagnostic=@'
$ErrorActionPreference='Stop';$env:HWID_NO_UPDATE='1';$env:HWID_NO_ANIMATION=$null
$script:checks=0
function Assert($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
try {
    $body=([IO.File]::ReadAllText('__SOURCE__') -split '(?m)^# POWERSHELL_START\r?$',2)[1]
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
    if($e.Count){throw ($e.Message -join '; ')}
    foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
    $null=Initialize-ReadableConsole $true $false
    $ownedConsole=$true;$redirected=$false
    $palette=@{Border='DarkGray';Heading='Cyan'}
    [Console]::SetWindowPosition(0,0);[Console]::SetWindowSize(80,20);[Console]::SetBufferSize(80,30)
    [Console]::CursorVisible=$true
    foreach($row in 16..18){[Console]::SetCursorPosition(0,$row);[Console]::Write(('Synthetic original row '+$row).PadRight(79,'.'))}
    [Console]::SetCursorPosition(7,3)
    function Read-Footer {return (ConvertTo-Json -InputObject ([HwidConsoleDisplay]::CaptureRegion(0,16,79,3)).Cells -Compress -Depth 4)}
    $original=Read-Footer
    $foreground=[Console]::ForegroundColor;$background=[Console]::BackgroundColor
    foreach($direction in @('Next','Back','Exit','Restart')){
        Show-UiTransition $direction -PendingInput {$false}
        Assert ((Read-Footer) -ceq $original) ($direction+' did not restore original footer cells and colors.')
        Assert ([Console]::CursorLeft -eq 7 -and [Console]::CursorTop -eq 3 -and [Console]::CursorVisible) ($direction+' changed cursor position or visibility.')
    }
    Assert ([Console]::ForegroundColor -eq $foreground -and [Console]::BackgroundColor -eq $background) 'Animation changed the global console output colors.'
    [Console]::CursorVisible=$false
    $script:inputPolls=0
    Show-UiTransition Next -PendingInput {$script:inputPolls++;return $script:inputPolls -ge 3}
    Assert ($script:inputPolls -eq 3 -and (Read-Footer) -ceq $original -and -not [Console]::CursorVisible) 'Pending input did not cancel and restore the running animation.'
    [Console]::CursorVisible=$true;$script:inputPolls=0
    Show-UiTransition Back -PendingInput {$script:inputPolls++;if($script:inputPolls -eq 3){throw 'Synthetic input failure'};return $false}
    Assert ((Read-Footer) -ceq $original -and [Console]::CursorVisible) 'An input callback failure leaked animation cells or hid the cursor.'
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HwidAnimationInput {
    [StructLayout(LayoutKind.Explicit, Size=20)] public struct Record {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort Key;
        [FieldOffset(14)] public ushort Character;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr input, Record[] data, uint count, out uint written);
    public static bool QueueA() {
        uint written;
        return WriteConsoleInputW(GetStdHandle(-10),new[] {new Record {Type=1,Down=1,Repeat=1,Key=65,Character=65}},1,out written) && written==1;
    }
}
"@
    Assert ([HwidAnimationInput]::QueueA()) 'Could not queue the synthetic navigation key.'
    Show-UiTransition Next
    Assert ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq [ConsoleKey]::A -and (Read-Footer) -ceq $original) 'Skipping animation consumed a key intended for the next page.'
    $script:inputPolls=0
    Show-UiTransition Next -PendingInput {
        $script:inputPolls++
        if($script:inputPolls -eq 3){
            [Console]::SetWindowSize(60,20);[Console]::SetBufferSize(60,30)
            [Console]::SetCursorPosition(0,16);[Console]::Write('SENTINEL')
        }
        return $false
    }
    $patch=[HwidConsoleDisplay]::CaptureRegion(0,16,8,1)
    $text=-join @($patch.Cells | ForEach-Object {[char]$_.Character})
    Assert ($text -ceq 'SENTINEL' -and [Console]::CursorVisible) 'Resizing restored stale animation cells over the new layout.'
    Assert ([Console]::CursorLeft -eq 8 -and [Console]::CursorTop -eq 16) 'Resizing restored an obsolete cursor location.'
    [IO.File]::WriteAllText('__RESULT__',(@{Checks=$script:checks;Runtime=$PSVersionTable.PSVersion.ToString()} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}catch{
    [IO.File]::WriteAllText('__RESULT__',(@{Error=$_.Exception.Message;Line=$_.InvocationInfo.ScriptLineNumber;Checks=$script:checks} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    exit 1
}
'@
$diagnostic=$diagnostic.Replace('__SOURCE__',([IO.Path]::GetFullPath($Source)).Replace("'","''")).Replace('__RESULT__',$resultPath.Replace("'","''"))
$scriptPath=Join-Path $root 'probe.ps1'
[IO.File]::WriteAllText($scriptPath,$diagnostic,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$arguments='-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
try{if(-not $child.WaitForExit(20000)){throw 'Native animation checks exceeded 20 seconds.'}}finally{$child.Dispose()}
if(-not [IO.File]::Exists($resultPath)){throw 'The native animation diagnostic returned no result.'}
$result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if($result.Error){throw ($result.Error+' / line '+$result.Line+' / after '+$result.Checks+' checks')}
[Console]::WriteLine("All $($result.Checks) native animation checks passed under PowerShell $($result.Runtime).")
