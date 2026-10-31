param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Fixture';InstanceId='USB\NODE001';Class='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@(' Model-0001 ','MODEL-0002');CompatibleID=@(' COMPAT-0001 ')}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function Read-Fixture([string]$Properties,[string]$Devices=''){
    $code='function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit,$ErrorAction,$ErrorVariable) '+$Properties+'};'
    if($Devices){$code+='function Get-PnpDevice {param([switch]$PresentOnly) '+$Devices+'};'}
    $code+='Get-ExtendedDeviceInventory'
    return @(Invoke-ScanQuery ([scriptblock]::Create($code)))[0]
}
$root=Join-Path $PSScriptRoot ('test-output-id-completeness-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try {
        $different=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_HardwareIds";Data=@("OTHER-0001")};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("OTHER-COMPAT")}'
        $row=$different.Devices[0]
        Assert ($row.HardwareIDSourceConflict -eq $true -and $row.CompatibleIDSourceConflict -eq $true) ($mode+' disagreements between native and property ID lists are explicit')
        Assert (($row.HardwareID -join '|') -ceq ' Model-0001 |MODEL-0002' -and $row.HardwareIDPropertyReadings[0][0] -ceq 'OTHER-0001') ($mode+' both exact observations survive without replacing preferred native IDs')
        Assert ($row.HardwareIdSource -ceq 'PnP record' -and $row.CompatibleIdSource -ceq 'PnP record') ($mode+' hardware and compatible lists have separate source labels')
        Assert ((@(Get-ExtendedDeviceReview $row) -join ' ') -match 'PnP record.*disagree') ($mode+' cross-source disagreement is visible in device review')
        Assert ($different.Info.IdSourceConflicts -eq 1 -and -not $row.HardwareIDPropertyConflict) ($mode+' one cross-source conflict is distinct from repeated-property disagreements')
        $same=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_HardwareIds";Data=@(" Model-0001 ","MODEL-0002")};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_CompatibleIds";Data=@(" COMPAT-0001 ")}'
        Assert (-not $same.Devices[0].HardwareIDSourceConflict -and -not $same.Devices[0].CompatibleIDSourceConflict -and $same.Info.IdSourceConflicts -eq 0) ($mode+' equal opaque ID lists create no source conflict')
        foreach($list in @('@("Model-0001","MODEL-0002")','@(" Model-0001 ","model-0002")','@("MODEL-0002"," Model-0001 ")')){
            $changed=Read-Fixture ('[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_HardwareIds";Data='+$list+'}')
            Assert ($changed.Devices[0].HardwareIDSourceConflict -eq $true) ($mode+' differing ID padding/case/order remains a text disagreement')
        }
        $invalidList=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_HardwareIds";Data=@("OTHER",$true)}'
        Assert (-not $invalidList.Devices[0].HardwareIDSourceConflict -and $invalidList.Devices[0].HardwareIDReadStatus -match '^Invalid') ($mode+' a malformed partial list is reported invalid rather than a definite source mismatch')
        $recovered=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_HardwareIds";Data=@(" PROP-00001 ")};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_CompatibleIds";Data=@(" PROP-COMPAT ")}' '[pscustomobject]@{Name="Fixture";InstanceId="USB\NODE001";Class="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@();CompatibleID=@()}'
        Assert ($recovered.Devices[0].HardwareID[0] -ceq ' PROP-00001 ' -and $recovered.Devices[0].CompatibleID[0] -ceq ' PROP-COMPAT ') ($mode+' missing native IDs recover exact property strings and leading zeros')
        Assert ($recovered.Devices[0].HardwareIdSource -eq 'Device properties' -and $recovered.Devices[0].CompatibleIdSource -eq 'Device properties' -and $recovered.Info.CompatibleIdRecoveries -eq 1) ($mode+' recovered compatible IDs now carry their own source/count')
        $guid=Read-Fixture 'if($KeyName -notcontains "DEVPKEY_Device_ContainerId" -or $KeyName -notcontains "DEVPKEY_Device_BaseContainerId"){throw "Missing container property request"};[pscustomobject]@{InstanceId=" usb\node001 ";KeyName="DEVPKEY_Device_ContainerId";Data=" {aBcDeF12-1234-5678-90aB-0123456789aB} "};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data="ABCDEF12-1234-5678-90AB-0123456789AB"};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_BaseContainerId";Data=[guid]"11111111-2222-3333-4444-555555555555"}'
        $row=$guid.Devices[0]
        Assert ($row.ContainerId -ceq ' {aBcDeF12-1234-5678-90aB-0123456789aB} ' -and $row.ContainerIdReadings.Count -eq 2) ($mode+' equivalent container GUID formats preserve the first exact reported string and both observations')
        Assert (-not $row.ContainerIdConflict -and $row.ContainerIdReadStatus -eq 'Device properties') ($mode+' casing/braces/padding do not create a false GUID conflict')
        Assert ($row.BaseContainerId -ceq '11111111-2222-3333-4444-555555555555' -and $guid.Info.ContainerIdsRead -eq 1 -and $guid.Info.BaseContainerIdsRead -eq 1) ($mode+' native GUID objects become readable IDs with coverage counts')
        $mixed=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data=@("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data=$true};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data="11111111-2222-3333-4444-555555555555"}'
        $row=$mixed.Devices[0]
        Assert ($row.ContainerId -ceq '11111111-2222-3333-4444-555555555555' -and $row.ContainerIdReadStatus -match '^Invalid' -and -not $row.ContainerIdConflict) ($mode+' singleton containers and booleans cannot manufacture container GUIDs or conflicts')
        Assert ($row.ContainerIdReadings.Count -eq 3 -and $row.ContainerIdReadings[0] -is [array] -and $row.ContainerIdReadings[1] -is [bool]) ($mode+' invalid container observations preserve list and Boolean shape')
        Assert ((@(Get-ExtendedDeviceReview $row) -join ' ') -match 'container-ID.*invalid') ($mode+' invalid optional GUIDs remain a specific review finding')
        $conflict=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data="11111111-2222-3333-4444-555555555555"};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_BaseContainerId";Data="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"};[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_BaseContainerId";Data=[guid]::Empty}'
        Assert ($null -eq $conflict.Devices[0].ContainerId -and $conflict.Devices[0].ContainerIdConflict -and $conflict.Devices[0].ContainerIdReadings.Count -eq 2) ($mode+' conflicting GUID observations remain unresolved rather than last-reader-wins')
        Assert ($null -eq $conflict.Devices[0].BaseContainerId -and $conflict.Devices[0].BaseContainerIdConflict -and (@(Get-ExtendedDeviceReview $conflict.Devices[0]) -join ' ') -match 'container-ID.*disagreed') ($mode+' assigned versus empty GUID observations are also explicit conflicts')
        $empty=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data=[guid]::Empty}'
        Assert ($null -eq $empty.Devices[0].ContainerId -and $empty.Devices[0].ContainerIdReadStatus -match '^Empty GUID' -and -not $empty.Devices[0].ContainerIdConflict) ($mode+' an empty GUID is unassigned rather than a found identifier')
        $missing=Read-Fixture ''
        Assert ($null -eq $missing.Devices[0].ContainerId -and $missing.Devices[0].ContainerIdReadStatus -eq 'Not supplied (optional)' -and (@(Get-ExtendedDeviceReview $missing.Devices[0]) -join ' ') -notmatch 'container-ID') ($mode+' absent optional container IDs do not manufacture warnings')
        $unrelated=Read-Fixture '[pscustomobject]@{InstanceId="USB\OTHER";KeyName="DEVPKEY_Device_ContainerId";Data="11111111-2222-3333-4444-555555555555"}'
        Assert ($null -eq $unrelated.Devices[0].ContainerId -and $unrelated.Devices.Count -eq 1) ($mode+' unrequested device observations cannot attach IDs to a different node')
        $failed=Read-Fixture '[pscustomobject]@{InstanceId="USB\NODE001";KeyName="DEVPKEY_Device_ContainerId";Data="11111111-2222-3333-4444-555555555555"};throw [UnauthorizedAccessException]::new("Synthetic property access denied")'
        Assert ($failed.Devices.Count -eq 1 -and $failed.Devices[0].HardwareID[0] -ceq ' Model-0001 ' -and $failed.Devices[0].ContainerId -ceq '11111111-2222-3333-4444-555555555555' -and $failed.Info.PropertyReadErrors -gt 0) ($mode+' an optional read failure preserves already collected exact identifiers and diagnostics')
        $inventory=[ordered]@{'Report info'=@{Version='3.71';Computer='TEST';Generated='2026-10-31T12:00:00Z'};'Extended device inventory'=@($guid.Devices[0],$different.Devices[0],$mixed.Devices[0],$conflict.Devices[0]);'Extended scan info'=$guid.Info;'Memory modules'=@([pscustomobject]@{DeviceLocator='DIMM0';SerialNumber=' 0000123 '})}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic ID completeness' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'[0].ContainerId -ceq ' {aBcDeF12-1234-5678-90aB-0123456789aB} ' -and $saved.'Extended device inventory'[2].ContainerIdReadings[0] -is [array] -and $saved.'Extended device inventory'[2].ContainerIdReadings[1] -is [bool]) ($mode+' exact GUID text and malformed observation shapes survive snapshot export/import')
        Assert ($saved.'Extended device inventory'[1].HardwareIDSourceConflict -and $saved.'Extended device inventory'[3].ContainerIdConflict -and $saved.'Memory modules'[0].SerialNumber -ceq ' 0000123 ') ($mode+' source conflicts and exact component serials survive snapshot export/import')
        Assert ((Compare-Inventories $inventory $saved).Changes.Count -eq 0) ($mode+' new grouping metadata does not create component-serial comparison changes')
        Assert-ExtendedDeviceCatalog ([pscustomobject]@{Devices=$saved.'Extended device inventory';Info=$saved.'Extended scan info'})
        Assert ($true) ($mode+' optional invalid observations do not invalidate otherwise usable device catalogs')
        $many=Read-Fixture 'if($InstanceId.Count -gt 32){throw "Unbounded batch"};foreach($id in $InstanceId){$index=[int]$id.Substring($id.Length-3);$reportedId=if($ThrottleLimit -eq 1){$id}else{$InstanceId[-1]};[pscustomobject]@{InstanceId=$reportedId;KeyName="DEVPKEY_Device_ContainerId";Data=("00000000-0000-0000-0000-{0:000000000000}" -f $index)};[pscustomobject]@{InstanceId=$reportedId;KeyName="DEVPKEY_Device_BaseContainerId";Data=("11111111-0000-0000-0000-{0:000000000000}" -f $index)}}' 'foreach($index in 1..65){[pscustomobject]@{Name="Fixture";InstanceId=("USB\NODE{0:000}" -f $index);Class="USB";ClassGuid="TEST";Present=$true;ConfigManagerErrorCode=0;HardwareID=@("MODEL")}}'
        Assert ($many.Devices.Count -eq 65 -and $many.Info.ContainerIdsRead -eq 65 -and $many.Info.BaseContainerIdsRead -eq 65) ($mode+' serialized property calls avoid duplicate-node output silently omitting other IDs')
        Assert (@($many.Devices | Where-Object {$index=[int]$_.DeviceInstanceId.Substring($_.DeviceInstanceId.Length-3);$_.ContainerId -cne ("00000000-0000-0000-0000-{0:000000000000}" -f $index)}).Count -eq 0) ($mode+' every returned grouping ID stays attached to its exact requested node')
        Assert ($many.Info.PropertyBatches -eq 3 -and $many.Info.PropertyNodesRequested -eq 65 -and $many.Info.PropertyNodesReturned -eq 65 -and $many.Info.PropertyNodesWithoutRows -eq 0 -and $many.Info.PropertyReadConcurrency -eq 1) ($mode+' coverage counts distinct requested nodes across bounded batches rather than row totals')
        $noRows=Read-Fixture ''
        Assert ($noRows.Devices.Count -eq 1 -and $noRows.Info.PropertyNodesRequested -eq 1 -and $noRows.Info.PropertyNodesReturned -eq 0 -and $noRows.Info.PropertyNodesWithoutRows -eq 1 -and $noRows.Devices[0].HardwareID[0] -ceq ' Model-0001 ') ($mode+' missing property rows stay explicit while native IDs remain usable')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value})}
function Write-Heading {param($Text)}
Show-PnpRecords @($guid.Devices[0],$different.Devices[0]) -Full -Extended
Assert (@($rendered | Where-Object {$_.Label -eq 'Windows container ID (device grouping)'}).Count -eq 1) 'The extended view labels a container ID as Windows device grouping'
Assert (@($rendered | Where-Object {$_.Label -eq 'Compatible IDs read from'}).Count -eq 2 -and (@($rendered.Value) -join ' ') -match 'PnP record.*disagree') 'The extended view shows separate sources and explains ID-list disagreement'
$script:rendered.Clear();Show-PnpRecords @([pscustomobject]@{Name='Old snapshot';DeviceInstanceId='USB\OLD';PNPClass='USB';HardwareID=@('MODEL');ConfigManagerErrorCode=0}) -Full -Extended
Assert (@($rendered | Where-Object {$_.Label -match 'container ID'}).Count -eq 0) 'Old snapshots do not acquire invented container readings'
Assert ((Get-FieldLabel ContainerId) -match 'grouping' -and (Get-FieldLabel ContainerId) -notmatch 'serial') 'Grouping ID labels do not claim a factory hardware serial'
[Console]::WriteLine("All $script:checks ID-completeness checks passed under PowerShell $($PSVersionTable.PSVersion).")
