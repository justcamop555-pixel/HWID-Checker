param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function New-HealthyDevice($Name){[pscustomobject]@{Name=$Name;DeviceInstanceId='USB\LABEL-0001';PNPClass='USB';Present=$true;HiddenByNodeFlag=$false;HiddenByClass=$false;ConfigManagerErrorCode=0;ProblemCodeConflict=$false;HardwareID=@('MODEL-0001')}}
foreach($name in @('Unknown Instruments Audio','Unknown USB Device','unknown interface','Unknown','Unbekanntes Geraet','Real device')){
    $device=New-HealthyDevice $name
    Assert (@(Get-ExtendedDeviceReview $device).Count -eq 0) 'A readable name cannot independently imply a device problem when Windows reports code zero'
}
$device=New-HealthyDevice 'Unknown Instruments Audio';$device.ConfigManagerErrorCode=28
Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Driver not installed') 'An actual driver problem remains visible with the same device name'
$device.ConfigManagerErrorCode=$null
Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Device status was not supplied') 'A readable name cannot manufacture a working status when the code is missing'
$device=New-HealthyDevice ([string][char]0)
Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Device name was not supplied') 'A NUL-only name is missing readable text rather than a usable device label'
$device=New-HealthyDevice 'Device';$device.PNPClass=[string][char]0
Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Device class was not supplied') 'A NUL-only class remains visibly unread'
foreach($name in @(@('Name'),$true,123,@{Name='Device'},[pscustomobject]@{Name='Device'})){
    $device=New-HealthyDevice $name
    Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Device name was not supplied') 'Container and non-text names cannot masquerade as readable device labels'
}
foreach($case in @(@('MEDIA','AUDIO'),@('Net','NETWORK'),@('Display','GRAPHICS'),@('Monitor','MONITORS'))){
    $device=New-HealthyDevice 'Device';$device.PNPClass="`0 "+$case[0]+" `0"
    Assert ((Get-PnpGroup $device) -eq $case[1]) 'Known class groups ignore edge padding without changing raw class values'
}
function Read-LabelFixture($Primary,$Properties=''){
    $query='function Get-PnpDevice {param([switch]$PresentOnly) '+$Primary+'};function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit,$ErrorAction,$ErrorVariable) '+$Properties+'};Get-ExtendedDeviceInventory'
    return @(Invoke-ScanQuery ([scriptblock]::Create($query)))[0]
}
$root=Join-Path $PSScriptRoot ('test-output-device-labels-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $catalog=Read-LabelFixture '[pscustomobject]@{Name=[string][char]0;FriendlyName="Unknown Instruments Audio";PNPClass=[string][char]0;Class="MEDIA";ClassGuid="SYNTHETIC";InstanceId="USB\LABEL-0001";Present=$true;ConfigManagerErrorCode=0;HardwareID=@("MODEL-0001")}'
        $row=$catalog.Devices[0]
        Assert ($row.Name -ceq 'Unknown Instruments Audio' -and $row.NameSource -eq 'Friendly name' -and $row.PNPClass -ceq 'MEDIA') ($mode+' padded-blank name/class fields allow usable aliases to recover')
        Assert ($row.RawName -ceq ([string][char]0) -and $row.RawPNPClass -ceq ([string][char]0) -and $row.DeviceInstanceId -ceq 'USB\LABEL-0001') ($mode+' unusable original labels and exact identifiers are retained')
        Assert (@(Get-ExtendedDeviceReview $row).Count -eq 0 -and (Get-PnpGroup $row) -eq 'AUDIO' -and (Get-ExtendedProblemCode $row) -eq 0) ($mode+' successful label recovery does not fabricate a device warning')
        $malformed=Read-LabelFixture '[pscustomobject]@{Name=@("Bad label");FriendlyName="Recovered display";PNPClass=$true;Class="Display";ClassGuid="SYNTHETIC";InstanceId="PCI\LABEL-0002";Present=$true;ConfigManagerErrorCode=0}'
        $bad=$malformed.Devices[0]
        Assert ($bad.Name -ceq 'Recovered display' -and $bad.PNPClass -ceq 'Display' -and $bad.RawName -is [System.Collections.IList] -and $bad.RawName[0] -ceq 'Bad label' -and $bad.RawPNPClass -is [bool]) ($mode+' malformed optional labels recover through typed aliases and remain raw')
        Assert (@(Get-ExtendedDeviceReview $bad).Count -eq 0 -and (Get-PnpGroup $bad) -eq 'GRAPHICS') ($mode+' malformed label metadata cannot become a fake class or discard usable IDs')
        $bus=Read-LabelFixture '[pscustomobject]@{Name=" ";FriendlyName=$false;Class="USB";ClassGuid="SYNTHETIC";InstanceId="USB\LABEL-0003";Present=$true;ConfigManagerErrorCode=0}' '[pscustomobject]@{InstanceId="USB\LABEL-0003";KeyName="DEVPKEY_Device_BusReportedDeviceDesc";Data="Unknown Brand Device"}'
        Assert ($bus.Devices[0].Name -ceq 'Unknown Brand Device' -and $bus.Devices[0].NameSource -eq 'Bus description' -and $bus.Devices[0].RawFriendlyName -is [bool]) ($mode+' usable bus-description text remains the final sourced name fallback')
        $missing=Read-LabelFixture '[pscustomobject]@{Name=[string][char]0;FriendlyName=@("Invalid");PNPClass=[string][char]0;Class=$false;ClassGuid="SYNTHETIC";InstanceId="USB\LABEL-0004";Present=$true;ConfigManagerErrorCode=0}' '[pscustomobject]@{InstanceId="USB\LABEL-0004";KeyName="DEVPKEY_Device_BusReportedDeviceDesc";Data=@("Invalid bus label")}'
        $empty=$missing.Devices[0]
        Assert ($null -eq $empty.Name -and $empty.NameSource -eq 'Not supplied' -and $null -eq $empty.PNPClass -and $empty.RawBusDescription -is [System.Collections.IList]) ($mode+' invalid-only label sources remain unread instead of becoming joined strings')
        $reasons=@(Get-ExtendedDeviceReview $empty) -join ' '
        Assert ($reasons -match 'Device name was not supplied' -and $reasons -match 'Device class was not supplied' -and (Get-ExtendedProblemCode $empty) -eq 0) ($mode+' missing label findings stay separate from the valid Windows status code')
        $device=New-HealthyDevice 'Unknown USB Device';$device.ConfigManagerErrorCode=43
        Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'Windows stopped this device') ($mode+' removing name heuristics cannot suppress a real Windows problem code')
        $device.ProblemCodeConflict=$true
        Assert ((@(Get-ExtendedDeviceReview $device) -join ' ') -match 'readings disagreed' -and $null -eq (Get-ExtendedProblemCode $device)) ($mode+' genuine contradictory status readings remain unresolved and visible')
        $rendered.Clear();Show-PnpRecords @($row) -Extended -Full
        Assert (@($rendered | Where-Object {$_.Label -match 'Unknown Instruments Audio' -and $_.Value -match 'Working'}).Count -eq 1 -and @($rendered | Where-Object Label -eq 'DETAIL REVIEW').Count -eq 0) ($mode+' recovered readable names display with their actual working status without a false review')
        $rendered.Clear();Show-PnpRecords @($empty) -Extended
        Assert (@($rendered | Where-Object {$_.Label -match 'Unnamed device' -and $_.Value -match 'Working'}).Count -eq 1) ($mode+' a missing label displays as unnamed rather than a blank title')
        $inventory=[ordered]@{'Report info'=@{Version='3.78';Computer='TEST';Generated='2026-11-01T12:00:00-05:00'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-000123'});'Extended device inventory'=@($row,$bad,$empty);'Extended scan info'=$catalog.Info}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic device label scan' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'[0].Name -ceq 'Unknown Instruments Audio' -and $saved.'Extended device inventory'[0].RawName -ceq ([string][char]0) -and $saved.'Extended device inventory'[1].RawName[0] -ceq 'Bad label' -and $saved.'Extended device inventory'[2].RawClass -is [bool]) ($mode+' snapshots retain recovered names and original malformed text observations')
        Assert (@(Get-ExtendedDeviceReview $saved.'Extended device inventory'[0]).Count -eq 0 -and (Compare-Inventories $inventory $saved).Changes.Count -eq 0) ($mode+' saved labels cannot reintroduce the warning or alter ID comparisons')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks device-label-reading checks passed under PowerShell $($PSVersionTable.PSVersion).")
