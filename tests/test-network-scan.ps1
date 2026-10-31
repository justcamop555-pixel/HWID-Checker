$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-NetAdapter {throw 'Synthetic primary adapter reader unavailable'}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -eq 'MSFT_NetAdapter'){
        [pscustomobject]@{Name='Padded code';InterfaceGuid='NIC-1';NetworkAddresses=@('001122334455');InterfaceOperationalStatus='01';ReceiveLinkSpeed=1000000000;HardwareInterface=$true}
        [pscustomobject]@{Name='Two addresses';InterfaceGuid='NIC-2';NetworkAddresses=@('001122334455','AABBCCDDEEFF');InterfaceOperationalStatus='02';HardwareInterface=$true}
        [pscustomobject]@{Name='Repeated formatting';InterfaceGuid='NIC-3';NetworkAddresses=@('00-11-22-33-44-55','001122334455');InterfaceOperationalStatus=5;HardwareInterface=$true}
        [pscustomobject]@{Name='Invalid metadata';InterfaceGuid='NIC-4';NetworkAddresses=@($true,123,'AABBCCDDEEFF');InterfaceOperationalStatus=$true;PermanentAddress='FFEEDDCCBBAA';HardwareInterface=$true}
        return
    }
    throw 'Unexpected real-provider query'
}
$script:scanQueryWorker=$null
$rows=@(Get-NetworkIdentifiers)
Assert ($rows[0].Status -eq 'Up') 'Numeric-string operational status is interpreted numerically rather than compared as text'
$root=Join-Path $PSScriptRoot ('test-output-network-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        Section 'Network adapters' {Get-NetworkIdentifiers}
        $rows=$report.'Network adapters'
        Assert ($rows.Count -eq 4 -and $warnings.Count -eq 0) ($mode+' malformed optional network metadata does not discard valid adapter IDs')
        Assert ($rows[0].Status -eq 'Up' -and $rows[1].Status -eq 'Down' -and $rows[2].Status -eq 'Dormant') ($mode+' numeric strings and documented operational states have clear labels')
        Assert ($rows[3].Status -match 'invalid' -and $rows[3].RawInterfaceOperationalStatus -eq $true) ($mode+' boolean status cannot masquerade as Up and its raw value is preserved')
        Assert ($null -eq $rows[1].MacAddress -and $rows[1].MacAddressReadStatus -match 'Multiple' -and $rows[1].NetworkAddresses.Count -eq 2) ($mode+' multiple distinct reported addresses remain available without guessing a current MAC')
        Assert ($null -eq $rows[2].MacAddress -and $rows[2].ReportedNetworkAddress -ceq '00-11-22-33-44-55' -and $rows[2].NetworkAddresses.Count -eq 2) ($mode+' repeated formatting keeps one reported candidate without confirming a current MAC')
        Assert ($null -eq $rows[3].MacAddress -and $rows[3].ReportedNetworkAddress -ceq 'AABBCCDDEEFF' -and $rows[3].PermanentAddress -ceq 'FFEEDDCCBBAA' -and $rows[3].NetworkAddresses[0] -eq $true) ($mode+' malformed address-list entries cannot become current MAC IDs or hide valid reported addresses')
        Assert ((Get-SectionIdentifierInfo 'Network adapters' $rows).Tag -eq 'CHECK') ($mode+' unresolved current addresses remain visible in scan review counts')
        $old=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-2';MacAddress='001122334455'})}
        $comparison=Compare-Inventories $old $report
        Assert ($comparison.SkippedFields -gt 0 -and @($comparison.Changes | Where-Object InputObject -match 'NIC-2').Count -eq 0) ($mode+' ambiguous current MAC data is skipped rather than reported as an ID change')
        $report['Report info']=@{Version='3.55';Computer='TEST';Generated='2026-10-29T12:00:00Z'}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic network snapshot' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($null -eq $saved.'Network adapters'[1].MacAddress -and $saved.'Network adapters'[1].NetworkAddresses.Count -eq 2 -and $saved.'Network adapters'[3].RawInterfaceOperationalStatus -eq $true) ($mode+' snapshots preserve ambiguity and original status/address data')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' saving and importing the same network scan cannot invent identifier changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
foreach($case in @(@('01','Up'),@('02','Down'),@(3,'Testing'),@(4,'Unknown'),@(5,'Dormant'),@(6,'Not present'),@(7,'Lower layer down'),@(99,'Windows status 99'))){
    Assert ((Format-NetworkStatus $case[0]) -eq $case[1]) ('Operational status '+$case[0]+' retains its documented or explicit unknown meaning')
}
foreach($bad in @($false,$true,-1,'bad',[uint64]::MaxValue,'1.5')){Assert ((Format-NetworkStatus $bad) -match 'invalid') 'Malformed operational status stays unknown instead of becoming Up or Down'}
Assert ($null -eq (Format-NetworkStatus $null)) 'An absent operational status stays absent'
Assert ((Format-NetworkStatus '02' -Legacy) -eq 'Up' -and (Format-NetworkStatus 0 -Legacy) -eq 'Down' -and (Format-NetworkStatus 7 -Legacy) -eq 'Down') 'Legacy connection codes have numeric interpretation and retain Up/Down semantics'
Assert ((Format-NetworkStatus 65536 -Legacy) -match 'invalid' -and (Format-NetworkStatus 65535 -Legacy) -eq 'Windows network status 65535') 'Legacy status enforces its uint16 range without discarding valid unknown codes'
$explicit=Get-NetworkAddressInfo @('001122334455','AABBCCDDEEFF') '112233445566'
Assert ($explicit.Value -ceq '112233445566' -and $explicit.Status -eq 'Explicit current address') 'An explicit current address takes priority over an unordered address list'
$empty=Get-NetworkAddressInfo @($true,123,' ')
Assert ($null -eq $empty.Value -and $empty.Status -eq 'No usable address supplied') 'A list with no usable address does not manufacture a scalar ID'
$forward=Get-NetworkAddressInfo @('001122334455','AABBCCDDEEFF')
$reverse=Get-NetworkAddressInfo @('AABBCCDDEEFF','001122334455')
Assert ($null -eq $forward.Value -and $null -eq $reverse.Value -and $forward.Status -eq $reverse.Status) 'Reordering multiple addresses cannot manufacture a changed current MAC'
[Console]::WriteLine("All $script:checks network-scan checks passed under PowerShell $($PSVersionTable.PSVersion).")
