param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$folder=Join-Path $PSScriptRoot ('test-output-scan-resize-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
$resultPath=Join-Path $folder 'result.json'
$diagnostic=@'
$ErrorActionPreference='Stop'
$checks=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try{
    $raw=[IO.File]::ReadAllText('__SOURCE__');$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
    $null=Initialize-ReadableConsole $true $false
    $ownedConsole=$true;$redirected=$false;$scanTotal=18
    $palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
    function Resize-Fixture([int]$Width,[int]$Height){
        $height=[math]::Min($Height,[Console]::LargestWindowHeight)
        [Console]::SetWindowPosition(0,0)
        [Console]::SetBufferSize([math]::Max($Width,[Console]::BufferWidth),[math]::Max($height,[Console]::BufferHeight))
        [Console]::SetWindowSize($Width,$height)
        [Console]::SetBufferSize($Width,[Console]::BufferHeight)
    }
    function Read-Screen {
        $patch=[HwidConsoleDisplay]::CaptureRegion(0,0,[Console]::BufferWidth,[Console]::BufferHeight)
        if($null -eq $patch){throw 'Could not capture console screen.'}
        return ((-join @($patch.Cells|ForEach-Object {[char]$_.Character})) -replace '\s','')
    }
    Reset-UiPage;Resize-Fixture 100 24;Start-UiReport -Scanning
    Write-Heading 'SYNTHETIC SCAN'
    $script:scanProgressClock=[Diagnostics.Stopwatch]::StartNew();$script:scanProgressTotal=19
    $script:scanProgressState=[pscustomobject]@{Top=[Console]::CursorTop;Width=[Console]::WindowWidth}
    Write-PnpLine ('  '+(Get-ScanProgressText 0 19 0 97)) $palette.Heading
    foreach($index in 0..35){Write-PnpLine ("  Device $index / Serial: 0000-$index-END") $palette.Text}
    $line=Start-ScanLine '  [19/19] Extended device inventory '
    Update-ScanWaiting $line 12.5
    foreach($size in @(@(34,12),@(100,36),@(20,10),@(78,18),@(100,24))){
        Resize-Fixture $size[0] $size[1]
        Read-ScanNavigation
        Update-ScanProgress 18
        Update-ScanWaiting $line 13
        Assert (-not $script:scanDisplayState.Dirty) 'A supported size did not finish repainting.'
        $screen=Read-Screen
        Assert ($screen.Contains('0000-0-END') -and $screen.Contains('0000-35-END')) 'A resize lost earlier or later serial numbers.'
        Assert ([Console]::BufferWidth -eq [Console]::WindowWidth -and [Console]::BufferHeight -eq [Console]::CursorTop+3) 'A resize retained horizontal overflow or excessive blank history.'
    }
    Complete-ScanLine $line 'Catalog' '[READ] 178 known nodes' $palette.Good
    $screen=Read-Screen
    Assert ($screen.Contains('[READ]178knownnodes') -and -not $screen.Contains('WAITING') -and -not $screen.Contains('READING...')) 'A shorter completion left stale pending/waiting characters.'
    Move-UiReportView 'Home'
    Read-ScanNavigation
    Resize-Fixture 42 16;Read-ScanNavigation
    Assert ([Console]::WindowTop -eq 0 -and -not $script:scanDisplayState.FollowLatest) 'Resizing pulled a reader away from the first rows.'
    Resize-Fixture 100 24;Read-ScanNavigation
    Move-UiReportView 'End';Read-ScanNavigation
    Assert ($script:scanDisplayState.FollowLatest) 'End did not restore automatic following after resize.'
    $script:scanQueryWorker=New-ScanQueryWorker
    $script:pulses=0
    $line=Start-ScanLine '  Synthetic responsive query '
    $rows=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 750;[pscustomobject]@{SerialNumber='UNCHANGED-SYNTHETIC-001'}} {
        $script:pulses++
        $width=if($script:pulses%2){30}else{100}
        Resize-Fixture $width 18
        Update-ScanProgress 18
        Update-ScanWaiting $line 15
    })
    Assert ($script:pulses -ge 3 -and $rows.Count -eq 1 -and $rows[0].SerialNumber -ceq 'UNCHANGED-SYNTHETIC-001') 'Resizing changed, duplicated or interrupted a query result.'
    Assert (-not $script:lastQueryFeedbackFailure) 'Supported resizing was recorded as a query/display error.'
    Complete-ScanLine $line 'Fixture' '[READ] One result' $palette.Good
    $script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null
    Update-ScanProgress 19
    Write-Heading 'SCAN COMPLETE'
    Write-PnpValue 'Finished' '19/19 checks finished / 18/18 areas read / 0 not read / device list read / 17.1s' $palette.Good
    Write-PnpValue 'Selected IDs' '65 identifier fields filled by Windows' $palette.Good
    Write-PnpValue 'Review' '4 items to review. Choose [4] from the main menu for explanations.' $palette.Warn
    $script:scanViewState=$null
    $script:scanProgressClock.Stop();$script:scanProgressClock=$null;$script:scanProgressState=$null
    $script:step=0
    Wait-ScanContinue 'main menu' -KeyReader {
        $script:step++
        if($script:step -eq 1){Resize-Fixture 26 12}
        elseif($script:step -eq 2){
            Assert ($script:scanDisplayState.Width -eq 26) 'The finished screen did not detect a resize.'
            Assert ((Read-Screen).Contains('SelectedIDs:65identifierfieldsfilledbyWindows')) 'The finished screen lost the identifier count.'
            Resize-Fixture 100 36
        }else{
            $screen=Read-Screen
            Assert ($screen.Contains('Finished:19/19checksfinished/18/18areasread/0notread/devicelistread/17.1s')) 'The finished summary was overwritten or truncated.'
            Assert ($screen.Contains('Review:4itemstoreview.Choose[4]fromthemainmenuforexplanations.')) 'Review text was overwritten or mixed with another row.'
            Assert ($screen.Contains('Continue:PressEnterformainmenu.ReleaseEnterfirstifheldduringscanning.')) 'The continuation prompt was lost after resize.'
            Assert ([Console]::BufferHeight -eq (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))) 'The finished screen left an excessive scrollbar.'
            return (New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false))
        }
        return (New-Object ConsoleKeyInfo([char]'x',[ConsoleKey]::X,$false,$false,$false))
    }
    Assert ($script:step -eq 3) 'Resize/navigation keys incorrectly dismissed the finished scan.'
    # Returning to the same dimensions between polls must also repair host reflow.
    Resize-Fixture 100 24;Update-ScanDisplay
    Resize-Fixture 20 10;Resize-Fixture 100 24
    Start-Sleep -Milliseconds 450
    Update-ScanDisplay
    Assert ((Read-Screen).Contains('Continue:PressEnterformainmenu.ReleaseEnterfirstifheldduringscanning.')) 'A between-poll resize round trip damaged the continuation prompt.'
    Add-Type -TypeDefinition @"
using System;
using System.Threading;
using System.Runtime.InteropServices;
public static class HwidResizeIdleProbe {
    [StructLayout(LayoutKind.Explicit, Size=20)] public struct InputRecord {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort Key;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr output, out uint mode);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr output, uint mode);
    public static uint OutputMode() { uint mode; if(!GetConsoleMode(GetStdHandle(-11),out mode)) throw new Exception("Cannot read output mode."); return mode; }
    public static bool SetOutputMode(uint mode) { return SetConsoleMode(GetStdHandle(-11),mode); }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern bool WriteConsoleInputW(IntPtr input, InputRecord[] records, uint length, out uint written);
    public static string Error;
    public static bool InputSent;
    public static Thread Begin() {
        var thread = new Thread(() => {
            try {
                Thread.Sleep(180);
                Console.SetWindowPosition(0,0);
                Console.SetWindowSize(40,16);
                Console.SetBufferSize(40,Console.BufferHeight);
                Thread.Sleep(800);
            } catch(Exception e) { Error=e.Message; }
            finally {
                uint written;
                InputSent=WriteConsoleInputW(GetStdHandle(-10),new[] { new InputRecord { Type=1, Down=1, Repeat=1, Key=13 } },1,out written) && written==1;
            }
        });
        thread.IsBackground=true;thread.Start();return thread;
    }
}
"@
    $thread=[HwidResizeIdleProbe]::Begin()
    Wait-ScanContinue 'main menu'
    [void]$thread.Join(3000)
    Assert (-not [HwidResizeIdleProbe]::Error -and [HwidResizeIdleProbe]::InputSent) 'The idle-resize fixture failed.'
    Assert ($script:scanDisplayState.Width -eq 40 -and -not $script:scanDisplayState.Dirty) 'Idle resize required keyboard input before repainting.'
    Assert ((Read-Screen).Contains('SelectedIDs:65identifierfieldsfilledbyWindows')) 'Idle resize lost the final scan result.'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    foreach($index in 1..24){Resize-Fixture $(if($index%2){24}else{100}) $(if($index%2){12}else{30});Update-ScanDisplay}
    $watch.Stop()
    Assert ($watch.Elapsed.TotalSeconds -lt 10) 'Repeated resizing monopolized the UI loop.'
    Assert ((Read-Screen).Contains('0000-0-END') -and (Read-Screen).Contains('0000-35-END')) 'Repeated resizing destroyed retained scan history.'
    # Inspect the host's immediate reflow, before the next application repaint.
    # Painting cells does not clear stale soft-wrap metadata left by a resize.
    Reset-UiPage;Resize-Fixture 100 24;Start-UiReport -Scanning
    foreach($index in 0..20){Write-PnpLine ('  MARKER:'+('{0:00}' -f $index)+' '+('X'*100)) $palette.Text}
    Resize-Fixture 30 12;Update-ScanDisplay
    Resize-Fixture 100 24
    $patch=[HwidConsoleDisplay]::CaptureRegion(0,0,[Console]::BufferWidth,[Console]::BufferHeight)
    $markers=0;$displaced=0
    for($row=0;$row -lt $patch.Height;$row++){
        $rowText=-join @($patch.Cells[($row*$patch.Width)..(($row+1)*$patch.Width-1)]|ForEach-Object {[char]$_.Character})
        foreach($marker in [regex]::Matches($rowText,'MARKER:\d\d')){
            $markers++
            if($marker.Index -ne 2){$displaced++}
        }
    }
    Assert ($markers -eq 21) 'Host reflow lost a labeled scan row before the next repaint.'
    Assert ($displaced -eq 0) 'Stale soft-wrap metadata shifted scan rows diagonally during resize.'
    $frameLines=New-Object 'System.Collections.Generic.List[string]'
    $frameColors=New-Object 'System.Collections.Generic.List[uint16]'
    for($row=0;$row -lt $patch.Height;$row++){
        $frameLines.Add((-join @($patch.Cells[($row*$patch.Width)..(($row+1)*$patch.Width-1)]|ForEach-Object {[char]$_.Character})))
        $frameColors.Add($patch.Cells[$row*$patch.Width].Attributes)
    }
    $originalMode=[HwidResizeIdleProbe]::OutputMode()
    try{
        foreach($testMode in @(($originalMode -bor 13),($originalMode -band (-bnot 5)))){
            Assert ([HwidResizeIdleProbe]::SetOutputMode([uint32]$testMode)) 'The output-mode fixture could not set a valid mode.'
            $cursorRow=[Console]::CursorTop;$cursorColumn=[Console]::CursorLeft;$viewTop=[Console]::WindowTop
            Assert ([HwidConsoleDisplay]::PaintScanFrame($patch,$frameLines.ToArray(),$frameColors.ToArray())) 'Hard-line frame painting failed with a supported output mode.'
            Assert ([HwidResizeIdleProbe]::OutputMode() -eq $testMode) 'Hard-line frame painting changed the inherited output mode.'
            Assert ([Console]::CursorTop -eq $cursorRow -and [Console]::CursorLeft -eq $cursorColumn -and [Console]::WindowTop -eq $viewTop) 'Hard-line frame painting changed the output cursor or viewport.'
        }
    }finally{[void][HwidResizeIdleProbe]::SetOutputMode($originalMode)}
    Reset-UiPage;Resize-Fixture 100 24;Start-UiReport -Scanning
    Write-PnpLine '  Earlier serial: SYNTHETIC-PRIOR-001' $palette.Text
    $pending=Start-ScanLine '  Synthetic provider '
    $nativePainter=(Get-Item Function:Invoke-ScanFramePaint).ScriptBlock
    $script:failedPaints=0
    function Invoke-ScanFramePaint {param($Patch,$Lines,$Colors) $script:failedPaints++;return $false}
    $script:scanQueryWorker=New-ScanQueryWorker
    try{
        $result=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 1450;[pscustomobject]@{SerialNumber='SYNTHETIC-RECOVERED-001'}} {Update-ScanDisplay -Force})
        Assert ($result.Count -eq 1 -and $result[0].SerialNumber -ceq 'SYNTHETIC-RECOVERED-001') 'A persistent native drawing failure lost the query result.'
        Assert ($null -eq $script:scanDisplayState -and $script:scanDisplayWarning -match 'text output') 'A stable native drawing failure never switched to readable text.'
        Assert ($script:failedPaints -gt 1 -and $script:failedPaints -lt 40 -and -not $script:lastQueryFeedbackFailure) 'Native display fallback retried without a bound or contaminated query status.'
        $beforeRow=[Console]::CursorTop;$beforeColumn=[Console]::CursorLeft
        Update-ScanWaiting $pending 99
        Assert ([Console]::CursorTop -eq $beforeRow -and [Console]::CursorLeft -eq $beforeColumn) 'Fallback timer updates used obsolete frame coordinates.'
        Complete-ScanLine $pending 'Synthetic provider' '[READ] one result after text fallback' $palette.Good
        $text=Read-Screen
        Assert ($text.Contains('SYNTHETIC-PRIOR-001') -and $text.Contains('[READ]oneresultaftertextfallback')) 'Text fallback lost earlier scan text or its completion line.'
        Write-PnpLine '  More scan output after fallback' $palette.Text
        Assert ((Read-Screen).Contains('Morescanoutputafterfallback')) 'The legacy text path did not accept later scan output.'
    }finally{
        Set-Item Function:Invoke-ScanFramePaint -Value $nativePainter
        $script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null
    }
    Reset-UiPage;Resize-Fixture 100 24;Start-UiReport -Scanning
    Write-PnpLine '  Stable serial: SYNTHETIC-UNCHANGED-0001' $palette.Text
    $pending=Start-ScanLine '  Synthetic partial update '
    $before=[HwidConsoleDisplay]::CaptureRegion(0,0,100,1)
    $cursorRow=[Console]::CursorTop;$cursorColumn=[Console]::CursorLeft;$viewTop=[Console]::WindowTop
    $wrapFunction=(Get-Item Function:Get-ScanDisplayLines).ScriptBlock
    $script:layoutCalls=0
    $script:performanceWrap=$wrapFunction
    function Get-ScanDisplayLines {param($Entry,$Width) $script:layoutCalls++; & $script:performanceWrap $Entry $Width}
    $script:scanDisplayState.RefreshClock=[pscustomobject]@{ElapsedMilliseconds=0}
    $script:scanDisplayState.RefreshClock | Add-Member ScriptMethod Restart {}
    try{
        Set-ScanDisplayEntry $pending.Entry '  Synthetic partial update: 000123' $palette.Good
        Assert ($script:layoutCalls -eq 1 -and -not $script:scanDisplayState.Dirty) 'A same-size progress update rebuilt unchanged transcript lines.'
        $after=[HwidConsoleDisplay]::CaptureRegion(0,0,100,1)
        Assert ((-join @($before.Cells|ForEach-Object Character)) -ceq (-join @($after.Cells|ForEach-Object Character))) 'A partial status update changed an unrelated scan row.'
        Assert ([Console]::CursorTop -eq $cursorRow -and [Console]::CursorLeft -eq $cursorColumn -and [Console]::WindowTop -eq $viewTop) 'A partial update moved the output cursor or reader viewport.'
    }finally{Set-Item Function:Get-ScanDisplayLines -Value $wrapFunction}
    Resize-Fixture 30 12;Update-ScanDisplay
    Assert ((Read-Screen).Contains('Syntheticpartialupdate:000123')) 'A resize did not rebuild the latest authoritative partial-update text.'
    $pending.Entry.Pending=$false
    Set-ScanDisplayEntry $pending.Entry '  Synthetic partial update: DONE' $palette.Good
    Assert ([Console]::CursorTop -eq $pending.Entry.Row+$pending.Entry.Rows) 'A partial completion did not advance to the next output row.'
    Assert ([Console]::BufferHeight -eq (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))) 'Partial completion retained excess scrollbar rows.'
    Reset-UiPage
    Assert ($null -eq $script:scanDisplayState -and [Console]::BufferHeight -eq [Console]::WindowHeight) 'Returning to the menu retained the scan transcript or scrollbar.'
    # Menu input must recover while no key is pressed, retaining typed text and
    # validation feedback. The fake availability reader resizes before yielding.
    Resize-Fixture 100 24
    $area=New-MenuInputArea;$area.Maximum=6;$area.Error='[INPUT-02] Choose 0-6.'
    $null=Write-MenuInputArea $area '123'
    $script:menuPolls=0
    $key=Read-MenuKey $area '123' -AvailableReader {
        $script:menuPolls++
        if($script:menuPolls -eq 1){Resize-Fixture 34 12;return $false}
        $screen=Read-Screen
        Assert ($screen.Contains('[0-6]:123') -and $screen.Contains('[INPUT-02]Choose0-6.')) 'Idle menu resizing lost input or validation feedback before any key arrived.'
        return $true
    } -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    Assert ($key.Key -eq [ConsoleKey]::Enter -and $script:menuPolls -eq 2 -and $area.Enabled) 'The resize-aware menu reader did not return the first available key.'
    $script:menuPolls=0
    $null=Read-MenuKey $area '123' -AvailableReader {
        $script:menuPolls++
        if($script:menuPolls -eq 1){Resize-Fixture 100 24;return $false}
        Assert ((Read-Screen).Contains('Select[0-6]:123')) 'Widening the idle menu did not restore its bounded prompt.'
        return $true
    } -KeyReader {New-Object ConsoleKeyInfo([char]'4',[ConsoleKey]::D4,$false,$false,$false)}
    Assert ([Console]::CursorTop -lt [Console]::WindowTop+[Console]::WindowHeight -and $area.Error -eq '[INPUT-02] Choose 0-6.') 'Idle menu recovery moved the caret outside the viewport or cleared the error.'
    [IO.File]::WriteAllText('__RESULT__',(@{Checks=$checks;Runtime=$PSVersionTable.PSVersion.ToString();ResizeStormSeconds=$watch.Elapsed.TotalSeconds;RealHardwareRead=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}catch{
    [IO.File]::WriteAllText('__RESULT__',(@{Error=$_.Exception.Message;Line=$_.InvocationInfo.ScriptLineNumber;Checks=$checks}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    exit 1
}
'@
$diagnostic=$diagnostic.Replace('__SOURCE__',([IO.Path]::GetFullPath($Source)).Replace("'","''")).Replace('__RESULT__',$resultPath.Replace("'","''"))
$scriptPath=Join-Path $folder 'probe.ps1'
[IO.File]::WriteAllText($scriptPath,$diagnostic,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$arguments='-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
try{if(-not $process.WaitForExit(45000)){throw 'Native scan-resize checks exceeded 45 seconds.'}}finally{$process.Dispose()}
if(-not [IO.File]::Exists($resultPath)){throw 'Native scan-resize checks did not return a result.'}
$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
if($result.Error){throw ($result.Error+' / line '+$result.Line+' / after '+$result.Checks+' checks')}
$result|ConvertTo-Json
Write-Output ("All $($result.Checks) scan-resize checks passed under PowerShell $($result.Runtime).")
