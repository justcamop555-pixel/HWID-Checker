param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText($Source);$body=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$definition=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($definition.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$single=Get-NetworkAddressInfo @('001122334455')
Assert ($null -eq $single.Value -and $single.ReportedAddress -ceq '001122334455' -and $single.Status -match 'current address not identified') 'One reported address is not promoted into a confirmed current MAC'
$duplicate=Get-NetworkAddressInfo @('00-11-22-33-44-55','001122334455')
Assert ($null -eq $duplicate.Value -and $duplicate.ReportedAddress -ceq '00-11-22-33-44-55') 'Equivalent address formatting keeps the original candidate without a current-address claim'
$opaque=Get-NetworkAddressInfo @('provider-opaque-address')
Assert ($null -eq $opaque.Value -and $opaque.ReportedAddress -ceq 'provider-opaque-address') 'Opaque reported addresses are retained without being labeled current MACs'
Assert ((Get-FieldLabel 'Speed' 'Network adapters') -match 'bits/s' -and (Get-FieldLabel 'Speed' 'Network adapters') -notmatch 'MHz') 'A network Speed field cannot inherit the memory clock label'
Assert ((Get-FieldLabel 'PermanentAddress') -match 'Windows-reported' -and (Get-FieldLabel 'CurrentHorizontalResolution') -match 'WMI.*pixels') 'Permanent-address and display-dimension labels identify their actual source/units'
foreach($case in @(@(1920,1080,'Reported'),@(0,0,'Missing'),@($null,$null,'Missing'),@(1920,$null,'Incomplete'),@(0,1080,'Incomplete'),@(@(1920),1080,'Invalid'),@($true,1080,'Invalid'),@(-1,1080,'Invalid'))){
    Assert ((Get-GraphicsModeInfo $case[0] $case[1]).Status -eq $case[2]) ('WMI mode metadata is classified as '+$case[2]+' without an invented monitor mapping')
}
Assert ((Get-GraphicsModeInfo 1920 1080).Text -ceq '1920 x 1080 pixels' -and (Get-GraphicsModeInfo 0 0).Text -notmatch '0 x 0') 'Only a complete positive WMI mode becomes a pixel-size label'
Assert ((Get-NetworkGroup ([pscustomobject]@{HardwareInterface=$false})) -match 'non-hardware' -and (Get-NetworkGroup ([pscustomobject]@{HardwareInterface='false'})) -ceq 'Type not supplied') 'Non-hardware and unread type flags remain distinct'
Assert ((Get-FieldQuality MacAddress $null ([pscustomobject]@{HardwareInterface=$false})) -eq 'Optional' -and (Get-FieldQuality MacAddress $null ([pscustomobject]@{HardwareInterface=$true})) -eq 'Missing') 'Missing optional addresses no longer mean proven not-applicable'
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Primary';InterfaceGuid='NIC-PRIMARY';MacAddress='00-11-22-33-44-55';PermanentAddress='00-11-22-33-44-66';Status='Up';LinkSpeed='1 Gbps';TransmitLinkSpeed=1000000000;HardwareInterface=$true}}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -eq 'MSFT_NetAdapter'){[pscustomobject]@{Name='CIM adapter';InterfaceGuid='NIC-CIM';NetworkAddresses=@('AABBCCDDEEFF');PermanentAddress='112233445566';InterfaceOperationalStatus=1;ReceiveLinkSpeed=1000000000;TransmitLinkSpeed=100000000;HardwareInterface=$true};return}
    if($ClassName -eq 'Win32_NetworkAdapter'){[pscustomobject]@{Name='Legacy adapter';GUID='NIC-LEGACY';MACAddress='001122334455';NetConnectionStatus=2;Speed=1000000000;PhysicalAdapter=$true};return}
    throw ('Unexpected provider: '+$ClassName)
}
$root=Join-Path $PSScriptRoot ('test-output-graphics-network-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try {
        $primary=@(Invoke-ScanQuery {Get-NetworkIdentifiers})[0]
        Assert ($primary.MacAddress -ceq '00-11-22-33-44-55' -and $primary.PermanentAddress -ceq '00-11-22-33-44-66' -and $primary.MacAddressReadStatus -match 'Get-NetAdapter') ($mode+' explicit primary current/permanent addresses remain separate and exact')
        Assert ($primary.LinkSpeed -ceq '1 Gbps' -and $primary.TransmitLinkRate -ceq '1000 Mbps' -and $primary.LinkSpeedKind -match 'reported') ($mode+' primary rate retains its reported form and separately labels transmit rate')
        $cim=@(Invoke-ScanQuery {function Get-NetAdapter {param([switch]$IncludeHidden) throw 'Synthetic primary unavailable'};Get-NetworkIdentifiers})[0]
        Assert ($null -eq $cim.MacAddress -and $cim.ReportedNetworkAddress -ceq 'AABBCCDDEEFF' -and $cim.PermanentAddress -ceq '112233445566') ($mode+' CIM fallback preserves reported/permanent addresses without inventing a current MAC')
        Assert ($cim.LinkSpeedKind -ceq 'Receive link rate' -and $cim.LinkSpeed -ceq '1000 Mbps' -and $cim.TransmitLinkRate -ceq '100 Mbps' -and $cim.ReceiveLinkSpeed -eq 1000000000 -and $cim.TransmitLinkSpeed -eq 100000000) ($mode+' asymmetric receive/transmit rates keep their direction and raw bit values')
        $legacy=@(Invoke-ScanQuery {
            function Get-NetAdapter {param([switch]$IncludeHidden) throw 'Synthetic primary unavailable'}
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) if($ClassName -eq 'MSFT_NetAdapter'){throw 'Invalid class'};[pscustomobject]@{Name='Legacy';GUID='NIC-LEGACY';MACAddress='001122334455';Speed=1000000000;NetConnectionStatus=2;PhysicalAdapter=$true}}
            Get-NetworkIdentifiers
        })[0]
        Assert ($legacy.MacAddress -ceq '001122334455' -and $null -eq $legacy.PermanentAddress -and $legacy.LinkSpeedKind -ceq 'Reported bandwidth estimate') ($mode+' legacy current address remains usable while its speed is an estimate and permanent address stays unknown')
        $old=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-CIM';MacAddress='FFEEDDCCBBAA'})}
        $current=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-CIM';MacAddress=$cim.MacAddress;ReportedNetworkAddress=$cim.ReportedNetworkAddress})}
        $comparison=Compare-Inventories $old $current
        Assert ($comparison.SkippedFields -gt 0 -and $comparison.Changes.Count -eq 0) ($mode+' an unverified list candidate cannot create a current-MAC change')
        $inventory=[ordered]@{'Report info'=@{Version='3.70';Computer='TEST';Generated='2026-10-31T12:00:00Z'};'Network adapters'=@($primary,$cim,$legacy)}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic graphics/network evidence' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($null -eq $saved.'Network adapters'[1].MacAddress -and $saved.'Network adapters'[1].ReportedNetworkAddress -ceq 'AABBCCDDEEFF' -and $saved.'Network adapters'[1].TransmitLinkSpeed -eq 100000000) ($mode+' saved reports retain address uncertainty and directional speed data')
        Assert ((Compare-Inventories $inventory $saved).Changes.Count -eq 0) ($mode+' exporting the same network scan does not create identifier changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$script:rendered=New-Object 'System.Collections.Generic.List[object]';$script:jumps=New-Object 'System.Collections.Generic.List[string]'
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=[string]$Label;Value=[string]$Value})}
function Add-ReportBookmark {param($Key) $script:jumps.Add([string]$Key)}
$report=[ordered]@{
    'Graphics adapters'=@([pscustomobject]@{Name='GPU fixture';VideoProcessor='Processor fixture';PNPDeviceID='PCI\GPU';DriverVersion='1.2.3';CurrentHorizontalResolution=1920;CurrentVerticalResolution=1080},[pscustomobject]@{Name='No mode';PNPDeviceID='PCI\OTHER';CurrentHorizontalResolution=0;CurrentVerticalResolution=0})
    'Network adapters'=@($cim,[pscustomobject]@{Name='Non-hardware';HardwareInterface=$false;Status='Down';InterfaceGuid='NIC-SOFT';MacAddress=$null;PermanentAddress=$null},[pscustomobject]@{Name='Unread type';HardwareInterface='false';InterfaceGuid='NIC-UNKNOWN';MacAddress='ABC'})
    Monitors=@([pscustomobject]@{Name='Monitor fixture';SerialNumber='0001';Active=$false;Manufacturer='Fixture';InstanceName='DISPLAY\FIXTURE'})
}
$before=$report | ConvertTo-Json -Depth 12
$viewFixture=$report
Show-GraphicsNetworkSummary
Assert (($jumps -join ',') -ceq '1,2,3') 'The category has separate graphics, network and monitor shortcuts'
Assert (@($rendered | Where-Object {$_.Label -eq 'Mode (WMI-reported)' -and $_.Value -eq '1920 x 1080 pixels'}).Count -eq 1 -and @($rendered | Where-Object {$_.Value -match '0 x 0'}).Count -eq 0) 'Graphics cards label WMI mode correctly and omit false zero-resolution claims'
Assert (@($rendered | Where-Object {$_.Label -eq 'Reported hardware / physical interfaces'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Reported non-hardware interfaces'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Type not supplied'}).Count -eq 1) 'Network cards group reported hardware/non-hardware/unknown types without guessing virtual status'
Assert (($rendered.Value -join ' ') -match 'Internet speed/connectivity is not tested' -and ($rendered.Value -join ' ') -match 'firmware/software can change') 'The category explains link-rate and permanent-address limits'
Assert (@($rendered | Where-Object {$_.Label -eq 'Receive link rate' -and $_.Value -eq '1000 Mbps'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Transmit link rate' -and $_.Value -eq '100 Mbps'}).Count -eq 1) 'Directional rates appear as distinct fields in the network view'
Assert (($rendered.Value -join ' ') -notmatch 'Not used by this device' -and ($rendered.Value -join ' ') -match 'may not apply') 'Missing non-hardware addresses are described as unsupplied rather than proven unused'
Assert (($report | ConvertTo-Json -Depth 12) -ceq $before) 'Rendering the organized view does not modify scan values'
$script:rendered.Clear();$script:jumps.Clear()
function Read-MenuChoice {param($Maximum) return '4'}
Assert ((Show-Categories) -eq $true -and ($jumps -join ',') -ceq '1,2,3') 'The real hardware-category route opens the organized graphics/network view'
$script:rendered.Clear()
Show-Records @([pscustomobject]@{Speed=1000000000}) 'Network adapters'
Assert (@($rendered | Where-Object {$_.Label -match 'bandwidth.*bits/s'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -match 'MHz'}).Count -eq 0) 'Raw network Speed is labeled in bits per second rather than memory MHz'
$script:rendered.Clear();$report=[ordered]@{'Graphics adapters'=@{Unavailable='GPU failed'};'Network adapters'=@{Unavailable='NIC failed'};Monitors=@{Unavailable='Monitor failed'}}
Show-GraphicsNetworkSummary
Assert (@($rendered | Where-Object Label -eq 'Not read').Count -eq 3) 'Unread sections stay explicit instead of appearing as zero devices'
$viewPath=Join-Path $root 'view.json';[IO.File]::WriteAllText($viewPath,($viewFixture | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$resultPath=Join-Path $root 'native.json'
$native=@'
$ErrorActionPreference='Stop'
try {
    $raw=[IO.File]::ReadAllText('__SOURCE__');$body=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
    foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
    $null=Initialize-ReadableConsole $true $false
    $ownedConsole=$true;$redirected=$false
    $palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
    $identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
    $json=Get-Content -LiteralPath '__VIEW__' -Raw | ConvertFrom-Json
    $report=[ordered]@{'Graphics adapters'=$json.'Graphics adapters';'Network adapters'=$json.'Network adapters';Monitors=$json.Monitors}
    $results=@(foreach($width in @(80,24)){
        Reset-UiPage;[Console]::SetWindowSize($width,20);[Console]::SetBufferSize($width,20)
        Show-GraphicsNetworkSummary;Complete-UiReport
        Move-UiReportView 'Home';$homeTop=[Console]::WindowTop
        Move-UiReportView 'End';$endTop=[Console]::WindowTop
        [pscustomobject]@{Width=$width;Bookmarks=$script:reportBookmarks.Count;HistoryTrimmed=([Console]::BufferHeight -eq (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop)));NavigationBounded=($homeTop -eq 0 -and $endTop -eq [Console]::BufferHeight-[Console]::WindowHeight);CursorFits=([Console]::CursorLeft -lt $width -and [Console]::CursorTop -lt [Console]::BufferHeight)}
    })
    $results | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8
}catch{@{Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT__' -Encoding UTF8;exit 1}
'@
$native=$native.Replace('__SOURCE__',([IO.Path]::GetFullPath($Source)).Replace("'","''")).Replace('__VIEW__',$viewPath.Replace("'","''")).Replace('__RESULT__',$resultPath.Replace("'","''"))
$probePath=Join-Path $root 'native.ps1';[IO.File]::WriteAllText($probePath,$native,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$arguments='-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$probePath+'"'
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
if(-not $process.WaitForExit(30000)){throw 'Native graphics/network checks exceeded 30 seconds.'}
$nativeResult=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if($nativeResult -isnot [array] -and $nativeResult.Error){throw $nativeResult.Error}
foreach($case in $nativeResult){
    Assert ($case.Bookmarks -eq 3) ($case.Width.ToString()+'-column category retains three navigation shortcuts')
    Assert ($case.HistoryTrimmed) ($case.Width.ToString()+'-column category history includes only rendered content')
    Assert ($case.NavigationBounded) ($case.Width.ToString()+'-column category scrolls to both valid ends')
    Assert ($case.CursorFits) ($case.Width.ToString()+'-column category retains wrapped values within its buffer')
}
[Console]::WriteLine("All $checks graphics-network checks passed under PowerShell $($PSVersionTable.PSVersion).")
