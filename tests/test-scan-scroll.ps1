param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$folder=Join-Path $PSScriptRoot ('test-output-scan-scroll-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
$resultPath=Join-Path $folder 'result.json'
$diagnostic=@'
$ErrorActionPreference='Stop'
$checks=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:checks++}
try {
    $raw=[IO.File]::ReadAllText('__SOURCE__');$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors.Message -join '; ')}
    foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
    $null=Initialize-ReadableConsole $true $false
    $ownedConsole=$true;$redirected=$false;$scanTotal=17
    $palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
    Reset-UiPage
    [Console]::SetWindowSize(60,12);[Console]::SetBufferSize(60,12)
    Start-UiReport -Scanning
    Assert ([Console]::BufferHeight -eq 12) 'Scanning reserved thousands of empty scrollbar rows.'
    Assert ($null -ne $script:scanViewState -and $script:scanViewState.FollowLatest) 'Scan navigation state did not start in follow mode.'
    foreach($index in 0..79){Write-PnpLine ('Row '+$index) $palette.Muted}
    Assert ([Console]::BufferHeight -eq [Console]::CursorTop+3) 'Active history did not shrink to written content plus a small reserve.'
    Assert ([Console]::WindowTop -eq [Console]::BufferHeight-[Console]::WindowHeight) 'Following live output did not remain at the tail.'
    $script:keys=New-Object 'System.Collections.Generic.Queue[object]'
    function Send-Nav($Name){$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]0,[ConsoleKey]::$Name,$false,$false,$false)));Read-ScanNavigation -AvailableReader {$script:keys.Count -gt 0} -KeyReader {$script:keys.Dequeue()}}
    Send-Nav 'Home'
    Assert ([Console]::WindowTop -eq 0 -and -not $script:scanViewState.FollowLatest) 'Home did not pause automatic following.'
    Write-PnpLine 'Arrived while reading the first rows' $palette.Text
    Assert ([Console]::WindowTop -eq 0) 'A new output line pulled the reader away from the chosen viewport.'
    $script:scanProgressClock=[Diagnostics.Stopwatch]::StartNew();$script:scanProgressTotal=18
    $script:scanProgressState=[pscustomobject]@{Top=0;Width=60}
    $line=Start-ScanLine 'Slow fixture: '
    $cursorTop=[Console]::CursorTop;$cursorLeft=[Console]::CursorLeft
    Update-ScanProgress 10;Update-ScanWaiting $line 6
    Assert ([Console]::WindowTop -eq 0) 'Timer/status painting moved the scrolled viewport.'
    Assert ([Console]::CursorTop -eq $cursorTop -and [Console]::CursorLeft -eq $cursorLeft) 'Timer/status painting moved the output cursor.'
    $patch=[HwidConsoleDisplay]::CaptureRegion($line.Left,$line.Top,40,1)
    $painted=-join @($patch.Cells | ForEach-Object {[char]$_.Character})
    Assert ($painted -match 'WAITING' -and $line.LastLength -gt 12) 'Waiting status was not painted in its buffer row.'
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class HwidScanTestInput {
    [StructLayout(LayoutKind.Explicit, Size=20)] public struct InputRecord {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort Key;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr input, InputRecord[] records, uint length, out uint written);
    public static bool Send(ConsoleKey key) {
        uint written;
        return WriteConsoleInputW(GetStdHandle(-10),new[] { new InputRecord { Type=1, Down=1, Repeat=1, Key=(ushort)key } },1,out written) && written==1;
    }
}
"@
    Send-Nav 'End'
    Assert ([HwidScanTestInput]::Send([ConsoleKey]::Home)) 'Could not enqueue a native scan navigation key.'
    $script:scanQueryWorker=New-ScanQueryWorker
    $script:pulses=0
    $rows=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 650;[pscustomobject]@{SerialNumber='SYNTHETIC'}} {
        $script:pulses++;Update-ScanProgress 10;Update-ScanWaiting $line 7
        $expected=if($script:pulses -eq 2){1}else{0}
        if([Console]::WindowTop -ne $expected){throw 'Worker did not handle scan navigation before repainting'}
        if($script:pulses -eq 1){$null=[HwidScanTestInput]::Send([ConsoleKey]::DownArrow)}
        if($script:pulses -eq 2){$null=[HwidScanTestInput]::Send([ConsoleKey]::UpArrow)}
    })
    Assert ($script:pulses -ge 3 -and $rows.Count -eq 1 -and -not $script:lastQueryFeedbackFailure) 'Scrolling-safe repaint or actual keyboard input interfered with a worker query.'
    Complete-ScanLine $line 'Fixture' '[READ] Synthetic complete' $palette.Good
    Assert ([Console]::WindowTop -eq 0 -and [Console]::CursorTop -eq $cursorTop+1) 'Completing a scan row moved the reader or appended multiple rows.'
    Send-Nav 'PageDown';Assert ([Console]::WindowTop -eq 11) 'PageDown was not handled during scanning.'
    Send-Nav 'UpArrow';Assert ([Console]::WindowTop -eq 10) 'Up was not handled during scanning.'
    Send-Nav 'DownArrow';Assert ([Console]::WindowTop -eq 11) 'Down was not handled during scanning.'
    Send-Nav 'PageUp';Assert ([Console]::WindowTop -eq 0) 'PageUp was not handled during scanning.'
    Send-Nav 'End';Assert ($script:scanViewState.FollowLatest -and [Console]::WindowTop -eq [Console]::BufferHeight-12) 'End did not resume following the scan.'
    Write-PnpLine 'Follow resumed' $palette.Text
    Assert ([Console]::WindowTop -eq [Console]::BufferHeight-12) 'Output did not follow after End.'
    [Console]::SetWindowPosition(0,2)
    Write-PnpLine 'Mouse-style viewport change' $palette.Text
    Assert ([Console]::WindowTop -eq 2 -and -not $script:scanViewState.FollowLatest) 'A scrollbar/mouse-style viewport change was not preserved.'
    for($index=0;$index -lt 70;$index++){$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))}
    Read-ScanNavigation -AvailableReader {$script:keys.Count -gt 0} -KeyReader {$script:keys.Dequeue()}
    Assert ($script:keys.Count -eq 38) 'Held Enter was not bounded to 32 reads per pulse.'
    Assert ([Console]::WindowTop -eq 2) 'Ignored scan-time keys changed the view.'
    $script:keys.Clear()
    Send-Nav 'Home'
    [Console]::SetWindowSize(20,12);[Console]::SetBufferSize(20,[Console]::BufferHeight)
    Send-Nav 'Home'
    $before=[Console]::CursorTop;Update-ScanProgress 11;Update-ScanWaiting $line 8
    Assert ([Console]::CursorTop -eq $before -and [Console]::WindowTop -eq 0) 'Resizing made a stale timer position move the view/cursor.'
    Write-PnpLine ('Wrapped '+('x'*160)) $palette.Text
    Assert ([Console]::BufferHeight -eq [Console]::CursorTop+3 -and [Console]::WindowTop -eq 0) 'Wrapped narrow output lost its bounded history or viewport.'
    $first=[HwidConsoleDisplay]::CaptureRegion(0,0,20,[Console]::BufferHeight)
    Assert ($null -ne $first -and (-join @($first.Cells | ForEach-Object {[char]$_.Character})) -match 'Row 5') 'Earlier buffer rows were lost after narrow output.'
    $script:scanViewState=$null
    $script:keys.Enqueue((New-Object ConsoleKeyInfo([char]0,[ConsoleKey]::Home,$false,$false,$false)))
    Read-ScanNavigation -AvailableReader {$script:keys.Count -gt 0} -KeyReader {$script:keys.Dequeue()}
    Assert ($script:keys.Count -eq 1) 'Scan navigation consumed keys outside an active scan.'
    Reset-UiPage
    Assert ([Console]::BufferHeight -eq 12 -and [Console]::WindowTop -eq 0) 'The menu inherited scan history.'
    $script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null
    $script:scanProgressClock.Stop();$script:scanProgressClock=$null
    $groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
    . ([scriptblock]::Create($groups.Extent.Text))
    $identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
    $display=[pscustomobject]@{Mode='Synthetic native full scan'}
    function Get-CimInstance {
        param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
        if([Console]::CursorVisible){throw 'Typing cursor was visible during collection'}
        [pscustomobject]@{Name='Fixture';Caption='Fixture Windows';InstanceName='MONITOR1';DeviceID='DEVICE0';PNPDeviceID='USB\PRESENT';PNPClass='USB';ClassGuid='NORMAL';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('PRESENT-MODEL');ProcessorId='CPU001';UUID='SYSTEM001';SerialNumber='000123';Manufacturer='Fixture';Model='Fixture';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;TotalPhysicalMemory=8GB;Capacity=8GB;Size=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}
    }
    function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Fixture NIC';InterfaceGuid='NIC1';MacAddress='001122334455'}}
    function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='SYNTHETIC-GUID'}}
    function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Known fixture';InstanceId='USB\KNOWN';Class='USB';ClassGuid='NORMAL';Present=$false;ConfigManagerErrorCode=45}}
    function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
    function Get-ClassHiddenState {param($ClassGuid) return $false}
    function Get-NativeNodeStatus {param($InstanceId) return $null}
    $snapshot=Invoke-HardwareScan 1 -UseWorker $true -IncludeExtended $true
    Assert ($snapshot.Completed -and $snapshot.Warnings.Count -eq 0 -and $snapshot.Inventory['Scan timing'].Count -eq 17) 'The narrow native scan lost results or encountered a display failure.'
    Assert ($snapshot.Inventory['Extended device inventory'].Count -eq 1 -and $snapshot.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') 'The narrow native scan lost the all-known device catalog.'
    Assert ([Console]::BufferHeight -eq [Console]::CursorTop+3 -and [Console]::BufferHeight -lt 512) 'The full scan retained an oversized or truncated scrollbar buffer.'
    $screen=[HwidConsoleDisplay]::CaptureRegion(0,0,20,[Console]::BufferHeight)
    Assert ((-join @($screen.Cells | ForEach-Object {[char]$_.Character})) -match 'PC SCAN') 'The first scan heading was lost when narrow output wrapped.'
    Assert ($null -eq $script:scanViewState -and $null -eq $script:scanQueryWorker -and $null -eq $script:scanProgressClock) 'The full scan left navigation or worker state active.'
    Wait-ScanContinue 'menu' -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    Assert ([Console]::BufferHeight -eq (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))) 'The continuation footer left thousands of blank rows.'
    $heading=(Get-Item Function:Write-Heading).ScriptBlock;$cursorBefore=[Console]::CursorVisible;$failed=$false
    function Write-Heading {param($Title) throw 'Synthetic early scan-render failure'}
    try{Invoke-HardwareScan 2 | Out-Null}catch{$failed=$true}finally{Set-Item Function:Write-Heading -Value $heading}
    Assert ($failed -and $null -eq $script:scanViewState -and [Console]::CursorVisible -eq $cursorBefore) 'An early render failure left scan navigation active or changed cursor visibility.'
    @{Checks=$checks;Runtime=$PSVersionTable.PSVersion.ToString();HistoryBounded=$true;ViewportPreserved=$true;NavigationWorks=$true;ReadOnly=$true} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
}catch{@{Error=$_.Exception.Message;Line=$_.InvocationInfo.ScriptLineNumber;Checks=$checks} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8;exit 1}
'@
$diagnostic=$diagnostic.Replace('__SOURCE__',([IO.Path]::GetFullPath($Source)).Replace("'","''")).Replace('__RESULT__',$resultPath.Replace("'","''"))
$scriptPath=Join-Path $folder 'probe.ps1';[IO.File]::WriteAllText($scriptPath,$diagnostic,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$arguments='-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
if(-not $process.WaitForExit(30000)){throw 'Native scan-scroll checks exceeded 30 seconds.'}
if(-not (Test-Path -LiteralPath $resultPath)){throw 'Native scan-scroll checks did not return a result.'}
$result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if($result.Error){throw ($result.Error+' / line '+$result.Line+' / after '+$result.Checks+' checks')}
$result | ConvertTo-Json
Write-Output ("All $($result.Checks) scan-scroll checks passed under PowerShell $($result.Runtime).")
