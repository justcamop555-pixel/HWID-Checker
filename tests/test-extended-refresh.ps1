$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17;$display=[pscustomobject]@{Mode='Synthetic extended refresh test'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Fixture node';PNPDeviceID='USB\A';PNPClass='USB';ClassGuid='NORMAL';Present=$null;ConfigManagerErrorCode=0;HardwareID=@('MODEL-A')}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) if([string]::IsNullOrWhiteSpace([string]$InstanceId)){return $null};return [uint32]0}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Fixture adapter';InterfaceGuid='NIC-1';MacAddress='001122334455';HardwareInterface=$true}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='FIXTURE-GUID'}}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    [pscustomobject]@{Name='Fixture';Caption='Fixture Windows';InstanceName='MONITOR1';DeviceID='DEVICE0';PNPDeviceID='USB\NORMAL';PNPClass='USB';ClassGuid='NORMAL';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL');ProcessorId='CPU001';UUID='SYSTEM001';SerialNumber='000123';Manufacturer='Fixture';Model='Fixture';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;TotalPhysicalMemory=8GB;Capacity=8GB;Size=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}
}
$root=Join-Path $PSScriptRoot ('test-output-extended-refresh-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$originalExtended=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        foreach($order in @('Forward','Reverse','Equal')){
            $presence=if($order -eq 'Reverse'){@('$false','$true')}elseif($order -eq 'Equal'){@('$true','$true')}else{@('$true','$false')}
            $node=if($order -eq 'Reverse'){@('[uint32]0x40000000','[uint32]0')}elseif($order -eq 'Equal'){@('[uint32]0','"0"')}else{@('[uint32]0','[uint32]0x40000000')}
            $body=@()
            foreach($value in $presence){$body+='[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_IsPresent";Data='+$value+'}'}
            foreach($value in $node){$body+='[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_DevNodeStatus";Data='+$value+'}'}
            $query=[scriptblock]::Create('function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) '+($body -join ';')+'};Get-ExtendedDeviceInventory')
            $catalog=@(Invoke-ScanQuery $query)[0];$row=$catalog.Devices[0]
            if($order -eq 'Equal'){
                Assert ($row.Present -eq $true -and -not $row.PresenceConflict -and $row.HiddenByNodeFlag -eq $false -and -not $row.NodeStatusConflict) ($mode+' repeated equal property readings remain usable')
                Assert ($row.PresenceReadings.Count -eq 1 -and $row.NodeStatusReadings.Count -eq 1 -and $row.NodeStatusReadings[0] -eq 0 -and $catalog.Info.NativeStatusRecoveries -eq 0) ($mode+' equivalent numeric/string node statuses deduplicate without a native retry')
            }else{
                Assert ($null -eq $row.Present -and $row.PresenceConflict -eq $true) ($mode+' '+$order+' contradictory property presence stays unknown and conflicted')
                Assert ($null -eq $row.HiddenByNodeFlag -and $row.NodeStatusConflict -eq $true -and $catalog.Info.NativeStatusRecoveries -eq 0) ($mode+' '+$order+' contradictory node flags are not overridden by native status')
                Assert ($row.PresenceReadings.Count -eq 2 -and $row.PresenceReadings -contains $true -and $row.PresenceReadings -contains $false -and $row.NodeStatusReadings.Count -eq 2 -and $row.NodeStatusReadings -contains [uint32]0 -and $row.NodeStatusReadings -contains [uint32]0x40000000) ($mode+' '+$order+' distinct conflicting readings remain available')
                $conflicted=$catalog
            }
        }
        $invalidStatus=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) [pscustomobject]@{InstanceId='USB\A';KeyName='DEVPKEY_Device_DevNodeStatus';Data=@([uint32]0x40000000)}}
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($invalidStatus.Devices[0].NodeStatusReadings.Count -eq 0 -and $invalidStatus.Devices[0].HiddenByNodeFlag -eq $false -and $invalidStatus.Info.NativeStatusRecoveries -eq 1) ($mode+' a singleton-array node status cannot masquerade as a typed Windows flag')
        $invalidPropertyKey=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {
                param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
                [pscustomobject]@{InstanceId=@('USB\A');KeyName='DEVPKEY_Device_IsPresent';Data=$false}
                [pscustomobject]@{InstanceId='USB\A';KeyName='DEVPKEY_Device_IsPresent';Data=$true}
                [pscustomobject]@{InstanceId='USB\A';KeyName='DEVPKEY_Device_DevNodeStatus';Data=[uint32]0x40000000}
            }
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($invalidPropertyKey.Info.InvalidPropertyRows -eq 1 -and $invalidPropertyKey.Devices[0].Present -eq $true -and -not $invalidPropertyKey.Devices[0].PresenceConflict -and $invalidPropertyKey.Devices[0].PresenceReadings.Count -eq 1 -and $invalidPropertyKey.Devices[0].HiddenByNodeFlag -eq $true) ($mode+' malformed property instance keys cannot fabricate conflicts or discard valid neighboring readings')
        foreach($case in @(@('Array key','[pscustomobject]@{Name="Malformed";PNPDeviceID=@("USB\A","USB\B")}'),@('Scalar record','"Not a device record"'),@('Empty record','[pscustomobject]@{}'))){
            $query=[scriptblock]::Create('function Get-PnpDevice {param([switch]$PresentOnly) '+$case[1]+'};function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) '+$case[1]+'};Get-ExtendedDeviceInventory')
            $failure=$null;$partial=@()
            try{$partial=@(Invoke-ScanQuery $query)}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq 'READ-06' -and $partial.Count -eq 0) ($mode+' '+$case[0]+' cannot become a successful catalog when both readers are malformed')
        }
        $blank=@(Invoke-ScanQuery {
            function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Named device without instance ID';PNPDeviceID='';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0}}
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($blank.Devices.Count -eq 1 -and [string]::IsNullOrWhiteSpace($blank.Devices[0].DeviceInstanceId) -and ((@(Get-ExtendedDeviceReview $blank.Devices[0]) -join ' ') -match 'instance')) ($mode+' a genuine blank instance ID remains readable and explicitly reviewable')
        $savedReport=[ordered]@{'Report info'=@{Version='3.60';Computer='TEST';Generated='2026-10-29T12:00:00Z'};'Extended device inventory'=$conflicted.Devices;'Extended scan info'=$conflicted.Info}
        $stem=Join-Path $root ('conflicts-'+$mode);Write-ReportPair $stem 'Synthetic conflicting property readings' ($savedReport | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'[0].PresenceConflict -eq $true -and $saved.'Extended device inventory'[0].NodeStatusConflict -eq $true -and $saved.'Extended device inventory'[0].PresenceReadings.Count -eq 2 -and $saved.'Extended device inventory'[0].NodeStatusReadings.Count -eq 2) ($mode+' conflict state and distinct readings survive saved-snapshot import')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$badCatalogs=@(
    @('Null devices','[pscustomobject]@{Devices=$null;Info=@{Captured="2026-10-29T12:30:00Z";Source="Fixture"}}'),
    @('Empty devices','[pscustomobject]@{Devices=@();Info=@{Captured="2026-10-29T12:30:00Z";Source="Fixture"}}'),
    @('Scalar devices','[pscustomobject]@{Devices=@("Not a device record");Info=@{Captured="2026-10-29T12:30:00Z";Source="Fixture"}}'),
    @('Empty device fields','[pscustomobject]@{Devices=@([pscustomobject]@{});Info=@{Captured="2026-10-29T12:30:00Z";Source="Fixture"}}'),
    @('Missing capture info','[pscustomobject]@{Devices=@([pscustomobject]@{Name="Fixture";DeviceInstanceId="USB\NEW"})}'),
    @('Array capture time','[pscustomobject]@{Devices=@([pscustomobject]@{Name="Fixture";DeviceInstanceId="USB\NEW"});Info=@{Captured=@("2026-10-29T12:30:00Z");Source="Fixture"}}'),
    @('Boolean capture time','[pscustomobject]@{Devices=@([pscustomobject]@{Name="Fixture";DeviceInstanceId="USB\NEW"});Info=@{Captured=$true;Source="Fixture"}}')
)
function Show-ExtendedDeviceReport {}
try{
    foreach($mode in @('Direct','Worker')){
        foreach($case in $badCatalogs){
            Set-Item Function:Get-ExtendedDeviceInventory -Value ([scriptblock]::Create($case[1]))
            $oldDevices=@([pscustomobject]@{Name='Previous device';DeviceInstanceId='USB\OLD';Present=$true;HardwareID=@('OLD')})
            $oldInfo=[ordered]@{Captured='2026-10-29T11:00:00Z';Source='Previous catalog';Records=1;Error='STALE-EARLIER-FAILURE'}
            $report=[ordered]@{'Report info'=[ordered]@{Version='3.60';Computer='TEST';Generated='2026-10-29T12:00:00Z';ScanNumber=3};'Extended device inventory'=$oldDevices;'Extended scan info'=$oldInfo}
            $warnings=New-Object 'System.Collections.Generic.List[string]'
            $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
            try{Start-ExtendedDeviceScan}finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
            Assert ($report['Report info'].ExtendedStatus -eq 'Unavailable' -and [object]::ReferenceEquals($oldDevices,$report['Extended device inventory']) -and [object]::ReferenceEquals($oldInfo,$report['Extended scan info'])) ($mode+' manual '+$case[0]+' rejection preserves the previous catalog and capture')
            $full=Invoke-HardwareScan 4 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
            Assert ($full.Completed -and @($full.Inventory['Scan timing'] | Where-Object Status -ne 'UNAVAILABLE').Count -eq 17 -and -not $full.Inventory.Contains('Extended device inventory') -and $full.Inventory['Report info'].ExtendedStatus -eq 'Unavailable' -and $full.Warnings.Count -eq 1) ($mode+' full rescan '+$case[0]+' rejection keeps all usable normal results without stale extended rows')
        }
        $latest=$report['Report info'].ExtendedFailureDetails
        $failure=@(Get-ReviewReadFailures $report @() | Where-Object Section -eq 'Extended device inventory')
        Assert (-not [string]::IsNullOrWhiteSpace($latest) -and $failure.Count -eq 1 -and $failure[0].Message -ceq $latest -and $failure[0].Message -ne 'STALE-EARLIER-FAILURE') ($mode+' review prefers the latest stored manual failure even without warning text')
        $stem=Join-Path $root ('failed-refresh-'+$mode);Write-ReportPair $stem 'Synthetic failed extended refresh' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        $savedFailure=@(Get-ReviewReadFailures $saved @() | Where-Object Section -eq 'Extended device inventory')
        Assert ($saved.'Report info'.ExtendedFailureDetails -ceq $latest -and $savedFailure[0].Message -ceq $latest) ($mode+' the current failure diagnostic survives save/import rather than reverting to stale capture errors')
        Set-Item Function:Get-ExtendedDeviceInventory -Value ([scriptblock]::Create('[pscustomobject]@{Devices=@([pscustomobject]@{Name="Recovered device";DeviceInstanceId="USB\RECOVERED";Present=$true;PNPClass="USB";HiddenByNodeFlag=$false;HiddenByClass=$false;ConfigManagerErrorCode=0});Info=@{Captured="2026-10-29T13:00:00Z";Source="Recovered fixture";Records=1}}'))
        $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
        try{Start-ExtendedDeviceScan}finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
        Assert ($report['Report info'].ExtendedStatus -eq 'Refreshed' -and -not $report['Report info'].ExtendedFailureDetails -and -not $report['Report info'].ExtendedFailureCode -and $warnings.Count -eq 0 -and $report['Report info'].ScanNumber -eq 3 -and $report['Report info'].Generated -ceq '2026-10-29T12:00:00Z') ($mode+' successful retry clears failure details without manufacturing a new normal capture')
        Assert (@(Get-ReviewReadFailures $report @() | Where-Object Section -eq 'Extended device inventory').Count -eq 0) ($mode+' a recovered extended refresh clears obsolete review failures')
    }
}finally{Set-Item Function:Get-ExtendedDeviceInventory -Value $originalExtended}
[Console]::WriteLine("All $script:checks extended-refresh checks passed under PowerShell $($PSVersionTable.PSVersion).")
