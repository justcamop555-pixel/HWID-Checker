$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17;$script:scanQueryWorker=$null
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    [pscustomobject]@{Name='Preferred fixture';PNPClass='USB';PNPDeviceID=" `0USB\00PNP`0 ";InstanceId='USB\OTHER';DeviceID='USB\LAST';Present=$true;HardwareID=@('Model-0001','MODEL-0002');CompatibleID=@('Compat-0001');ConfigManagerErrorCode=0}
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    [pscustomobject]@{Name='Parent fixture';PNPClass='USB';PNPDeviceID="`0 ";DeviceID=" `0USB\PARENT`0 ";Present=$true;ConfigManagerErrorCode=0}
    [pscustomobject]@{Name='Child fixture';PNPClass='USB';PNPDeviceID=" `0USB\CHILD0001`0 ";InstanceId='USB\IGNORED';Present=$true;ConfigManagerErrorCode=0}
}
function Get-PnpDeviceProperty {
    param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
    if(@($InstanceId).Count -ne 2 -or 'USB\PARENT' -notin $InstanceId -or 'USB\CHILD0001' -notin $InstanceId){throw 'Property lookup received unnormalized or missing instance keys'}
    foreach($id in $InstanceId){
        $padded=" `0"+([string]$id).ToLowerInvariant()+"`0 "
        [pscustomobject]@{InstanceId=$padded;KeyName='DEVPKEY_Device_IsPresent';Data=$true}
        [pscustomobject]@{InstanceId=$padded;KeyName='DEVPKEY_Device_DevNodeStatus';Data=[uint32]0}
        if($id -eq 'USB\CHILD0001'){
            [pscustomobject]@{InstanceId=$padded;KeyName='DEVPKEY_Device_HardwareIds';Data=@('Child-Model0001','Child-Model0002')}
            [pscustomobject]@{InstanceId=$padded;KeyName='DEVPKEY_Device_Parent';Data=" `0usb\parent`0 "}
        }
    }
}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
$root=Join-Path $PSScriptRoot ('test-output-instance-aliases-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $failure=$null;$keyOnly=@()
        try{$keyOnly=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{DeviceID='USB\000KEY'}}
            Get-DriverHardwareIds
        })}catch{$failure=$_}
        Assert ($null -eq $failure -and $keyOnly.Count -eq 1 -and $keyOnly[0].DeviceInstanceId -ceq 'USB\000KEY' -and $keyOnly[0].InstanceIdSource -eq 'DeviceID') ($mode+' a DeviceID-only Windows key is readable and becomes the device instance ID')
        $preferred=@(Invoke-ScanQuery {Get-DriverHardwareIds})
        Assert ($preferred.Count -eq 1 -and $preferred[0].DeviceInstanceId -ceq " `0USB\00PNP`0 " -and $preferred[0].InstanceIdSource -eq 'PNPDeviceID' -and $preferred[0].HardwareID[0] -ceq 'Model-0001') ($mode+' a usable PNPDeviceID wins while its raw padding, case and leading zeros remain unchanged')
        $instance=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Alias fixture';PNPDeviceID="`0 `0";InstanceId=" `0USB\000ALIAS`0 ";DeviceID='USB\LAST';Present=$true;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($instance.Count -eq 1 -and $instance[0].DeviceInstanceId -ceq " `0USB\000ALIAS`0 " -and $instance[0].InstanceIdSource -eq 'InstanceId') ($mode+' null-padded empty primary text does not hide a valid InstanceId alias')
        $lastAlias=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Last alias';PNPDeviceID=' ';InstanceId="`0 ";DeviceID=" `0USB\000LAST`0 ";Present=$true;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($lastAlias.Count -eq 1 -and $lastAlias[0].DeviceInstanceId -ceq " `0USB\000LAST`0 " -and $lastAlias[0].InstanceIdSource -eq 'DeviceID') ($mode+' blank preferred aliases fall back to the exact Windows DeviceID value')
        $fallback=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw [NotSupportedException]::new('Synthetic unsupported primary')}
            function Get-PnpDevice {param([switch]$PresentOnly) if(-not $PresentOnly){throw 'Present-only scope changed'};[pscustomobject]@{FriendlyName='Fallback alias';Class='USB';DeviceID=" `0USB\000FALLBACK`0 ";Present=$true;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($fallback.Count -eq 1 -and $fallback[0].DeviceInstanceId -ceq " `0USB\000FALLBACK`0 " -and $fallback[0].InstanceIdSource -eq 'DeviceID') ($mode+' present-only fallback keeps the original DeviceID source after remapping')
        $fallbackInstance=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw [NotSupportedException]::new('Synthetic unsupported primary')}
            function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{FriendlyName='Fallback instance';PNPDeviceID="`0 ";InstanceId=" `0USB\000INSTANCE`0 ";DeviceID='USB\LAST';Present=$true;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($fallbackInstance.Count -eq 1 -and $fallbackInstance[0].DeviceInstanceId -ceq " `0USB\000INSTANCE`0 " -and $fallbackInstance[0].InstanceIdSource -eq 'InstanceId') ($mode+' present-only fallback selects a valid InstanceId behind an empty primary')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Malformed primary';PNPDeviceID='USB\VALID';DeviceID=@('USB\A','USB\B');Present=$true}}
            Get-DriverHardwareIds
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-06' -and $partial.Count -eq 0) ($mode+' array-shaped DeviceID metadata cannot become a joined primary instance key')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw [NotSupportedException]::new('Synthetic unsupported primary')}
            function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Malformed fallback';PNPDeviceID='USB\VALID';DeviceID=@('USB\A','USB\B');Present=$true}}
            Get-DriverHardwareIds
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-06' -and $partial.Count -eq 0 -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' malformed fallback DeviceID keeps READ-06 and both diagnostics')
        $catalog=@(Invoke-ScanQuery {Get-ExtendedDeviceInventory})[0]
        $parent=@($catalog.Devices | Where-Object Name -eq 'Parent fixture')[0]
        $child=@($catalog.Devices | Where-Object Name -eq 'Child fixture')[0]
        Assert ($catalog.Devices.Count -eq 2 -and $parent.DeviceInstanceId -ceq " `0USB\PARENT`0 " -and $parent.InstanceIdSource -eq 'DeviceID' -and $child.DeviceInstanceId -ceq " `0USB\CHILD0001`0 " -and $child.InstanceIdSource -eq 'PNPDeviceID') ($mode+' extended records expose the selected native aliases without rewriting their text')
        Assert ($child.HardwareID.Count -eq 2 -and $child.HardwareID[0] -ceq 'Child-Model0001' -and $child.HardwareIdSource -eq 'Device properties' -and $child.Present -eq $true -and $catalog.Info.PropertyReadErrors -eq 0) ($mode+' normalized query and returned property keys enrich the correct padded device record')
        Assert ($child.ParentName -ceq 'Parent fixture' -and $child.ParentInstanceId -ceq " `0usb\parent`0 ") ($mode+' normalized parent matching resolves topology while the raw parent identifier is preserved')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Invalid extended primary';DeviceID=@('USB\A','USB\B')}}
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Invalid extended fallback';DeviceID=@('USB\A','USB\B')}}
            Get-ExtendedDeviceInventory
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-06' -and $partial.Count -eq 0 -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' extended primary and fallback reject malformed DeviceID before normalization')
        $inventory=[ordered]@{'Report info'=@{Version='3.63';Computer='TEST';Generated='2026-10-30T12:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-0001'});'PnP hardware IDs'=$preferred;'Extended device inventory'=$catalog.Devices;'Extended scan info'=$catalog.Info}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic instance aliases' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json');$savedChild=@($saved.'Extended device inventory' | Where-Object Name -eq 'Child fixture')[0]
        Assert ($saved.'PnP hardware IDs'[0].DeviceInstanceId -ceq " `0USB\00PNP`0 " -and $saved.'PnP hardware IDs'[0].InstanceIdSource -eq 'PNPDeviceID' -and $savedChild.DeviceInstanceId -ceq " `0USB\CHILD0001`0 " -and $savedChild.ParentInstanceId -ceq " `0usb\parent`0 " -and $savedChild.HardwareID[1] -ceq 'Child-Model0002') ($mode+' saved snapshots preserve exact selected IDs, source fields, parent text and arrays')
        $comparison=Compare-Inventories $inventory $saved;$nodes=Get-PnpNodeChanges $inventory.'PnP hardware IDs' $saved.'PnP hardware IDs'
        Assert ($comparison.PreviousCount -gt 0 -and $comparison.Changes.Count -eq 0 -and $nodes.Comparable -and $nodes.Added.Count -eq 0 -and $nodes.Removed.Count -eq 0) ($mode+' alias metadata and normalized lookup keys cannot manufacture snapshot or node changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks instance-alias checks passed under PowerShell $($PSVersionTable.PSVersion).")
