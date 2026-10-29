$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17;$display=[pscustomobject]@{Mode='Synthetic metadata test'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -eq 'WmiMonitorID' -and ($Property -contains 'ManufacturerNameLength' -or $Property -contains 'UserFriendlyNameLength')){throw 'Invalid query: optional projected monitor length field'}
    switch($ClassName) {
        'MSFT_Disk' {[pscustomobject]@{Number=0;SerialNumber='00001';UniqueId='DISK-ID';PartitionStyle='bad style';BusType=65535;HealthStatus=0};return}
        'MSFT_Partition' {
            [pscustomobject]@{DiskNumber=0;PartitionNumber=1;DriveLetter='C:';Guid='PART-1';AccessPaths=@('PATH1');Size='bad size'}
            [pscustomobject]@{DiskNumber=0;PartitionNumber=2;DriveLetter=0;Guid='PART-2';Size=0}
            [pscustomobject]@{DiskNumber=0;PartitionNumber=3;DriveLetter=[uint16]68;Guid='PART-3';Size=1GB}
            return
        }
        'WmiMonitorID' {
            [pscustomobject]@{InstanceName='MONITOR-GOOD';Active=$true;ManufacturerName=@(65,66,67);ManufacturerNameLength=3;UserFriendlyName=@(65,66,90);UserFriendlyNameLength=2;ProductCodeID=@(65,0,66);SerialNumberID=@('48','48','49')}
            [pscustomobject]@{InstanceName='MONITOR-BAD';Active=$true;ManufacturerName=@(65);ManufacturerNameLength=1;UserFriendlyName=@(65,66);UserFriendlyNameLength=-1;SerialNumberID=@(49,'bad code',50)}
            return
        }
    }
    [pscustomobject]@{Name='Fixture';Caption='Windows fixture';DeviceID='CPU0';DeviceLocator='A1';SerialNumber='SERIAL-1';UUID='SYSTEM-1';ProcessorId='CPU-1';TotalPhysicalMemory='bad memory';Capacity=$false;Size=-1024;FreeSpace=0;DriveType=3;FileSystem='NTFS';VolumeSerialNumber='VOL-1';PNPDeviceID='PCI\NODE';HardwareID=@('MODEL');ConfigManagerErrorCode=0}
}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='NIC';MacAddress='001122334455';HardwareInterface=$false;InterfaceGuid='NIC-1'}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='MACHINE-1'}}
Assert ((Get-StorageCodeName 'BusType' 65535) -eq 'Windows code 65535') 'Unknown valid uint16 storage codes remain explicit'
Assert ((Get-StorageCodeName 'HealthStatus' 0) -eq 'Healthy' -and (Get-StorageCodeName 'PartitionStyle' 2) -eq 'GPT') 'Zero and other recognized storage codes retain their real meanings'
foreach($bad in @('bad',-1,[uint32]::MaxValue,$false)) {Assert ((Get-StorageCodeName 'PartitionStyle' $bad) -eq 'Unknown (invalid Windows code)') 'Malformed storage codes never throw or become a guessed partition style'}
Assert ($null -eq (GiB -1) -and $null -eq (GiB 'bad size') -and $null -eq (GiB $false) -and $null -eq (GiB '1.5')) 'Negative, malformed, boolean and fractional byte sizes remain unknown'
Assert ((GiB 0) -eq 0 -and (GiB '1073741824') -eq 1 -and $null -ne (GiB ([uint64]::MaxValue))) 'Capacity conversion accepts real zero, numeric strings and the uint64 range'
Assert ((Get-PartitionLetterInfo ([uint16]67)).Text -eq 'C' -and (Get-PartitionLetterInfo 'd').Text -eq 'D') 'Partition letters handle char codes and text consistently'
Assert ((Get-PartitionLetterInfo ([char]0)).Status -eq 'Not assigned' -and (Get-PartitionLetterInfo $null).Status -eq 'Not assigned') 'Unassigned partition letters remain distinct from invalid values'
Assert ((Get-PartitionLetterInfo 'C:').Status -eq 'Invalid value' -and (Get-PartitionLetterInfo $false).Status -eq 'Invalid value') 'Malformed partition metadata is not described as a normal unassigned letter'
Assert ((Convert-MonitorText @('65','66','67')) -ceq 'ABC' -and (Convert-MonitorText @('65')) -ceq 'A') 'Numeric-string monitor codes decode numerically, including a singleton'
Assert ((Convert-MonitorText @(48,48,49,0,0)) -ceq '001' -and (Convert-MonitorText @(65,0,66)) -ceq 'AB') 'Monitor text preserves leading zeros and supported null padding'
Assert ((Get-MonitorTextResult @(65,66,90) 2).Text -ceq 'AB' -and (Get-MonitorTextResult @(65) 2).Status -eq 'Invalid length') 'Monitor name lengths bound decoding without guessing out-of-range text'
foreach($codes in @(@(65,65536,66),@(65,$false,66),@(65,'bad',66),@(65,-1,66))) {Assert ((Get-MonitorTextResult $codes).Status -eq 'Invalid text codes' -and (Convert-MonitorText $codes) -ceq '') 'Invalid monitor codes cannot produce a partially joined identifier'}
$report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanStep=0;$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
$root=Join-Path $PSScriptRoot ('test-output-metadata-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')) {
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try {
        Section 'Storage identifiers' {Get-StorageIdentifiers}
        $disk=$report.'Storage identifiers'[0]
        Assert ($disk.SerialNumber -ceq '00001' -and $disk.PartitionStyle -eq 'Unknown (invalid Windows code)' -and $disk.RawPartitionStyle -ceq 'bad style' -and $disk.BusType -eq 'Windows code 65535' -and $disk.HealthStatus -eq 'Healthy') ($mode+' disk IDs survive malformed optional codes with raw values retained')
        Section 'Disk partitions' {Get-PartitionIdentifiers}
        $parts=$report.'Disk partitions'
        Assert ($parts.Count -eq 3 -and $parts[0].PartitionGuid -ceq 'PART-1' -and $parts[0].DriveLetterReadStatus -eq 'Invalid value' -and $parts[0].RawDriveLetter -ceq 'C:' -and $null -eq $parts[0].Size_GiB -and $parts[0].Size -ceq 'bad size') ($mode+' malformed optional partition values do not discard partition IDs')
        Assert ($parts[1].DriveLetterReadStatus -eq 'Not assigned' -and $parts[1].Size_GiB -eq 0 -and $parts[2].DriveLetter -eq 'D' -and $parts[2].Size_GiB -eq 1) ($mode+' partition zero/unassigned/valid letter values remain distinct')
        $script:rendered.Clear();Show-Records @($parts[0]) 'Disk partitions'
        Assert (($script:rendered -join ' ') -match 'Unknown / invalid provider value' -and ($script:rendered -join ' ') -notmatch 'None assigned') ($mode+' invalid drive letters are explained without a false unassigned claim')
        Section 'Monitors' {Get-MonitorIdentifiers}
        $monitors=$report.Monitors
        Assert ($monitors.Count -eq 2 -and $monitors[0].SerialNumber -ceq '001' -and $monitors[0].Name -ceq 'AB' -and $monitors[0].UserFriendlyName[2] -eq 90) ($mode+' monitor IDs and bounded names survive optional-property query incompatibility with original arrays preserved')
        Assert ($monitors[1].SerialNumber -ceq '' -and $monitors[1].SerialNumberReadStatus -eq 'Invalid text codes' -and $monitors[1].SerialNumberID[1] -ceq 'bad code' -and $monitors[1].NameReadStatus -eq 'Invalid length') ($mode+' unread monitor text is explicit while the rest of the monitor remains available')
        Assert ($script:scanTimings[-1].Status -eq 'CHECK' -and $warnings.Count -eq 0) ($mode+' missing decoded serials are review findings rather than failed whole queries')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    $snapshot=Invoke-HardwareScan 1 -UseWorker ($mode -eq 'Worker')
    Assert ($snapshot.Completed -and $snapshot.Inventory.'Scan timing'.Count -eq 17 -and $snapshot.Warnings.Count -eq 0) ($mode+' the full scan captures all sections despite unread optional metadata')
    Assert ($null -eq $snapshot.Inventory.'System hardware'[0].TotalRAM_GiB -and $snapshot.Inventory.'System hardware'[0].TotalPhysicalMemory -ceq 'bad memory' -and $snapshot.Inventory.'Memory modules'[0].Capacity -eq $false -and $null -eq $snapshot.Inventory.'Memory modules'[0].Capacity_GiB) ($mode+' unread memory sizes are preserved raw instead of becoming zero')
    Assert ($snapshot.Inventory.'Physical disks'[0].Size -eq -1024 -and $null -eq $snapshot.Inventory.'Physical disks'[0].Size_GiB -and $snapshot.Inventory.Volumes[0].Free_GiB -eq 0) ($mode+' negative disk sizes stay unknown while real zero free space stays zero')
    $path=Join-Path $root ($mode+'.json');[IO.File]::WriteAllText($path,($snapshot.Inventory | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
    $saved=Read-SavedReport $path
    Assert ($saved.Monitors[0].SerialNumber -ceq '001' -and $saved.Monitors[1].SerialNumberID[1] -ceq 'bad code' -and $saved.'Disk partitions'[0].PartitionGuid -ceq 'PART-1') ($mode+' normalized and raw metadata survive report export/import with IDs intact')
}
Assert ((Get-FieldLabel 'RawLinkSpeedBps') -match 'bits/s' -and (Get-FieldLabel 'ReceiveLinkSpeed') -match 'bits/s') 'Raw network speed labels use bits/s rather than memory MHz'
[Console]::WriteLine("All $script:checks scan-metadata checks passed under PowerShell $($PSVersionTable.PSVersion).")
