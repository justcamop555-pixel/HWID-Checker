param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText($Source);$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
Assert ($null -eq (GiB @(1GB)) -and $null -eq (Format-NetworkLinkSpeed @(1000000000))) 'A singleton list cannot become a memory size or link speed'
Assert ((Get-PartitionLetterInfo @('C')).Status -eq 'Invalid value' -and (Get-StorageCodeName BusType @(17)) -match 'invalid Windows code') 'Singleton metadata containers cannot become a drive letter or storage-bus label'
Assert ((Get-MonitorTextResult (,(@(65)))).Status -eq 'Invalid text codes' -and (Get-MonitorTextResult @(65,66) @(1)).Status -eq 'Invalid length') 'Nested monitor codes and container-shaped lengths cannot manufacture decoded text'
foreach($value in @($true,[datetime]'2026-01-01',[timespan]::FromSeconds(1),[guid]::Empty,@{Value=1},[pscustomobject]@{Value=1},@(1),@(1,2))){
    Assert (-not (Get-ScanUInt64Info $value).Valid -and -not (Get-DeviceUInt32Info $value).Valid) 'Non-numeric scalar types and containers stay invalid in both unsigned readers'
}
Assert ((GiB 0) -eq 0 -and (Format-NetworkLinkSpeed 0) -ceq '0 Mbps' -and (Get-StorageCodeName HealthStatus 0) -ceq 'Healthy') 'Real zero values remain readable rather than becoming missing data'
Assert ((GiB ([uint64]::MaxValue)) -gt 0 -and (Get-ScanUInt64Info ([uint64]::MaxValue)).Valid -and -not (Get-DeviceUInt32Info ([uint64]::MaxValue)).Valid) 'Byte sizes retain their UInt64 range while status fields enforce UInt32'
Assert (-not (Get-ScanUInt64Info '-1').Valid -and -not (Get-ScanUInt64Info '18446744073709551616').Valid -and -not (Get-DeviceUInt32Info '4294967296').Valid) 'Negative and overflowing numeric metadata are rejected without exceptions'
Assert ((Get-StorageCodeName BusType '00017') -ceq 'NVMe' -and (Get-PartitionLetterInfo ([uint16]67)).Text -ceq 'C' -and (GiB '1073741824') -eq 1) 'Supported scalar strings and character codes still format correctly'
Assert ((Format-NetworkStatus ([System.Net.NetworkInformation.OperationalStatus]::Up)) -ceq 'Up' -and (Get-ScanUInt64Info ([DayOfWeek]::Monday)).Value -eq 1) 'Integral enums use their numeric values instead of localized or symbolic names'
Assert ((Format-NetworkStatus @(1)) -match 'invalid Windows network status' -and (Format-NetworkStatus @('2') -Legacy) -match 'invalid Windows network status') 'Modern and legacy network status lists remain unknown'
function Get-NetAdapter {param([switch]$IncludeHidden) throw [NotSupportedException]::new('Synthetic primary unavailable')}
function Get-CimInstance {
    param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
    switch($ClassName){
        'Win32_PnPEntity' {
            [pscustomobject]@{Name='Connected';PNPDeviceID='USB\000LIVE';Present=$true;HardwareID=@('MODEL-LIVE');ConfigManagerErrorCode=0}
            [pscustomobject]@{Name='Disconnected';PNPDeviceID='USB\000GONE';Present=$false;HardwareID=@('MODEL-GONE');ConfigManagerErrorCode=45}
        }
        'MSFT_Disk' {[pscustomobject]@{Number=0;SerialNumber='0000123';UniqueId='Case-ID';PartitionStyle=@(2);BusType=@(17);HealthStatus=@(0)}}
        'MSFT_Partition' {[pscustomobject]@{DiskNumber=0;PartitionNumber=1;Guid='PART-0001';DriveLetter=@('C');Size=@(1GB)}}
        'MSFT_NetAdapter' {[pscustomobject]@{Name='Fixture adapter';InterfaceGuid='NIC-0001';NetworkAddresses=@('001122334455');ReceiveLinkSpeed=@(1000000000);InterfaceOperationalStatus=@(1);HardwareInterface=$true}}
        'WmiMonitorID' {
            [pscustomobject]@{InstanceName='BAD';SerialNumberID=,(@(48));UserFriendlyName=@(65,66);UserFriendlyNameLength=@(1);ManufacturerName=@(65);ManufacturerNameLength=1}
            [pscustomobject]@{InstanceName='GOOD';SerialNumberID=@(48,48,49);UserFriendlyName=@(65,66);UserFriendlyNameLength=2;ManufacturerName=@(65);ManufacturerNameLength=1}
        }
        default {throw ('Unexpected fixture query: '+$ClassName)}
    }
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    [pscustomobject]@{Name='Connected';InstanceId='USB\000LIVE';Present=$true;HardwareID=@('MODEL-LIVE');Class='USB';ClassGuid='NORMAL';ConfigManagerErrorCode=0}
    [pscustomobject]@{Name='Disconnected';InstanceId='USB\000GONE';Present=$false;HardwareID=@('MODEL-GONE');Class='USB';ClassGuid='NORMAL';ConfigManagerErrorCode=45}
}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
$root=Join-Path $PSScriptRoot ('test-output-scan-scalars-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{'Report info'=@{Version='3.68';Computer='TEST';Generated='2026-10-31T12:00:00Z'}}
    $warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try {
        Section 'PnP hardware IDs' {Get-DriverHardwareIds}
        Assert ($report.'PnP hardware IDs'.Count -eq 1 -and $report.'PnP hardware IDs'[0].DeviceInstanceId -ceq 'USB\000LIVE') ($mode+' the Win32 present scan excludes explicitly disconnected rows without rewriting the live ID')
        $catalog=@(Invoke-ScanQuery {Get-ExtendedDeviceInventory})[0]
        Assert ($catalog.Devices.Count -eq 2 -and @($catalog.Devices | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count -eq 1) ($mode+' all-known scanning still preserves the remembered node')
        $fallback=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) [pscustomobject]@{Name='Stale';PNPDeviceID='USB\STALE';Present=$false;ConfigManagerErrorCode=45}}
            Get-DriverHardwareIds
        })
        Assert ($fallback.Count -eq 1 -and $fallback[0].DeviceInstanceId -ceq 'USB\000LIVE' -and $fallback[0].CollectionSource -match 'present-only fallback' -and $script:lastQueryRecoveries.Count -eq 1) ($mode+' an all-disconnected primary read tries a clean present-only fallback')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) [pscustomobject]@{Name='Stale';PNPDeviceID='USB\STALE';Present=$false}}
            function Get-PnpDevice {param([switch]$PresentOnly) return $null}
            Get-DriverHardwareIds
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-04' -and $partial.Count -eq 0 -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' no present nodes cannot become a misleading successful empty result')
        $unknown=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) [pscustomobject]@{Name='Unknown presence';PNPDeviceID='USB\UNKNOWN';Present=$null;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($unknown.Count -eq 1 -and $null -eq $unknown[0].Present) ($mode+' missing presence remains unknown instead of being coerced false')
        Section 'Storage identifiers' {Get-StorageIdentifiers}
        $disk=$report.'Storage identifiers'[0]
        Assert ($disk.SerialNumber -ceq '0000123' -and $disk.UniqueId -ceq 'Case-ID' -and $disk.BusType -match 'invalid Windows code' -and $disk.RawBusType -is [array] -and $disk.RawBusType[0] -eq 17) ($mode+' invalid scalar storage metadata stays unknown while exact IDs and raw lists are preserved')
        Section 'Disk partitions' {Get-PartitionIdentifiers}
        $partition=$report.'Disk partitions'[0]
        Assert ($partition.PartitionGuid -ceq 'PART-0001' -and $null -eq $partition.DriveLetter -and $partition.DriveLetterReadStatus -eq 'Invalid value' -and $null -eq $partition.Size_GiB -and $partition.RawDriveLetter[0] -ceq 'C' -and $partition.Size[0] -eq 1GB) ($mode+' partition metadata containers do not fabricate a mounted letter or formatted size')
        Section 'Network adapters' {Get-NetworkIdentifiers}
        $network=$report.'Network adapters'[0]
        Assert ($network.InterfaceGuid -ceq 'NIC-0001' -and $null -eq $network.MacAddress -and $network.ReportedNetworkAddress -ceq '001122334455' -and $network.Status -match 'invalid Windows network status' -and $null -eq $network.LinkSpeed -and $network.ReceiveLinkSpeed[0] -eq 1000000000) ($mode+' network fallback retains identifiers and reported addresses while malformed status/speed metadata stays unknown')
        Section 'Monitors' {Get-MonitorIdentifiers}
        $monitors=$report.Monitors
        Assert ($monitors.Count -eq 2 -and $monitors[0].SerialNumberReadStatus -eq 'Invalid text codes' -and $monitors[0].NameReadStatus -eq 'Invalid length' -and $monitors[1].SerialNumber -ceq '001') ($mode+' malformed monitor data cannot create a serial while a neighboring valid monitor remains readable')
        Assert ($warnings.Count -eq 0 -and @($scanTimings | Where-Object Status -eq 'UNAVAILABLE').Count -eq 0) ($mode+' optional metadata problems do not discard whole hardware sections')
        $report['Extended device inventory']=$catalog.Devices;$report['Extended scan info']=$catalog.Info
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic scalar/presence scan' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Storage identifiers'[0].SerialNumber -ceq '0000123' -and $saved.'Storage identifiers'[0].RawBusType -is [array] -and $saved.'Disk partitions'[0].RawDriveLetter[0] -ceq 'C' -and $saved.'Extended device inventory'.Count -eq 2) ($mode+' snapshots retain raw malformed metadata and both known-device records')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' exporting scan results does not invent identifier changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks scan-scalar checks passed under PowerShell $($PSVersionTable.PSVersion).")
