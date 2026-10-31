$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17;$display=[pscustomobject]@{Mode='Synthetic device coverage test'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if($PresentOnly){throw 'All-known catalog must not request present-only records'}
    foreach($index in 0..39){[pscustomobject]@{Name=('Fixture '+$index);InstanceId=('USB\D{0:000}' -f $index);Class='USB';ClassGuid='NORMAL';Present=($index%2 -eq 0);ConfigManagerErrorCode=0;HardwareID=@()}}
}
function Get-PnpDeviceProperty {
    param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
    if($InstanceId -contains 'USB\D010'){
        if($InstanceId.Count -gt 1){[pscustomobject]@{InstanceId=$InstanceId[0];KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-000000')}}
        throw 'Device disappeared during property enumeration'
    }
    foreach($id in $InstanceId){
        $index=[int]$id.Substring($id.Length-3)
        [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@(('MODEL-{0:000000}' -f $index))}
        [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_IsPresent';Data=($index%2 -eq 0)}
        [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_DevNodeStatus';Data=$(if($index -eq 4){[uint32]0x40000000}else{[uint32]0})}
    }
}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return $null}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Fixture network';InterfaceGuid='NIC-1';MacAddress='001122334455'}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='FIXTURE-GUID'}}
function Get-CimInstance {
    param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
    [pscustomobject]@{Name='Fixture';Caption='Fixture Windows';InstanceName='MONITOR1';DeviceID='DEVICE0';PNPDeviceID='USB\PRESENT';PNPClass='USB';ClassGuid='NORMAL';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('PRESENT-MODEL');ProcessorId='CPU001';UUID='SYSTEM001';SerialNumber='000123';Manufacturer='Fixture';Model='Fixture';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;TotalPhysicalMemory=8GB;Capacity=8GB;Size=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}
}
$root=Join-Path $PSScriptRoot ('test-output-device-coverage-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $catalog=@(Invoke-ScanQuery {Get-ExtendedDeviceInventory})[0]
        Assert ($catalog.Devices.Count -eq 40 -and @($catalog.Devices | Where-Object {$_.Present -eq $true}).Count -eq 20 -and @($catalog.Devices | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count -eq 20) ($mode+' collection retains all known present and remembered nodes')
        Assert ($catalog.Info.PropertyBatches -eq 2 -and $catalog.Info.PropertyRetryDevices -eq 32) ($mode+' a generic batch failure receives one bounded per-device recovery pass')
        Assert (@($catalog.Devices | Where-Object {$_.HardwareID.Count -eq 1}).Count -eq 39 -and $catalog.Info.HardwareIdRecoveries -eq 39) ($mode+' one disappearing node cannot prevent model-ID recovery for its neighbors or later batches')
        Assert ($catalog.Devices[0].HardwareID[0] -ceq 'MODEL-000000' -and -not $catalog.Devices[0].HardwareIDPropertyConflict -and $catalog.Devices[39].HardwareID[0] -ceq 'MODEL-000039') ($mode+' successful rows survive retries without changing zeroes or inventing list conflicts')
        Assert ($catalog.Devices[10].DeviceInstanceId -ceq 'USB\D010' -and $catalog.Devices[10].HardwareID.Count -eq 0 -and $null -eq $catalog.Devices[10].HiddenByNodeFlag -and $catalog.Info.PropertyReadErrors -gt 0) ($mode+' an unread property set remains unknown without dropping the device record')
        Assert ($catalog.Devices[4].HiddenByNodeFlag -eq $true -and $catalog.Devices[5].Present -eq $false -and $catalog.Devices[5].DevNodeStatus -eq 0) ($mode+' hidden flags, false presence and zero node status remain intact')
        $healthy=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('RECOVERED-0001')}}}
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($healthy.Info.PropertyBatches -eq 2 -and $healthy.Info.PropertyRetryDevices -eq 0 -and $healthy.Info.PropertyReadErrors -eq 0 -and $healthy.Info.HardwareIdRecoveries -eq 40) ($mode+' a subsequent healthy read does not inherit failed-batch metadata')
        foreach($hex in @('80041062','80041088','8004100C')){
            $query=[scriptblock]::Create('function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) throw [Runtime.InteropServices.COMException]::new("Localized diagnostic",[Convert]::ToInt32("'+$hex+'",16))};Get-ExtendedDeviceInventory')
            $blocked=@(Invoke-ScanQuery $query)[0]
            Assert ($blocked.Devices.Count -eq 40 -and $blocked.Info.PropertyBatches -eq 2 -and $blocked.Info.PropertyRetryDevices -eq 0 -and $blocked.Info.PropertyReadErrors -gt 0) ($mode+' '+$hex+' does not expand into per-device retries or remove known nodes')
        }
        $stopped=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {
                param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
                if($InstanceId.Count -gt 1){throw 'Generic initial failure'}
                throw [UnauthorizedAccessException]::new('Localized per-device denial')
            }
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($stopped.Info.PropertyRetryDevices -eq 2 -and $stopped.Devices.Count -eq 40) ($mode+' each retry pass stops immediately when the individual reader becomes access-blocked')
        $continued=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {
                param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
                foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-AVAILABLE')}}
                Write-Error 'Optional property unavailable' -ErrorAction Continue
            }
            Get-ExtendedDeviceInventory
        })[0]
        Assert ($continued.Info.HardwareIdRecoveries -eq 40 -and $continued.Info.PropertyRetryDevices -eq 0 -and $continued.Info.PropertyReadErrors -gt 0) ($mode+' non-terminating optional errors preserve usable rows without triggering batch retries')
        $inventory=[ordered]@{'Report info'=@{Version='3.65';Computer='TEST';Generated='2026-10-31T12:00:00Z'};'Extended device inventory'=$catalog.Devices;'Extended scan info'=$catalog.Info}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic device coverage' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'.Count -eq 40 -and $saved.'Extended scan info'.PropertyRetryDevices -eq 32 -and $saved.'Extended device inventory'[39].HardwareID[0] -ceq 'MODEL-000039') ($mode+' snapshots preserve known-node coverage, recovered IDs and property-read diagnostics')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$script:progress=New-Object 'System.Collections.Generic.List[object]'
function Update-ScanProgress([int]$Completed=$script:scanStep){$script:progress.Add([pscustomobject]@{Completed=$Completed;Total=$script:scanProgressTotal})}
$full=Invoke-HardwareScan 1 -UseWorker $false -IncludeExtended $true
Assert ($full.Completed -and $full.Inventory['Scan timing'].Count -eq 17 -and $full.Inventory['Extended device inventory'].Count -eq 40 -and $full.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') 'Full scan collects normal hardware and all known-device records in one completed snapshot'
Assert ($progress[-1].Completed -eq 18 -and $progress[-1].Total -eq 18 -and @($progress | Where-Object {$_.Completed -eq 17 -and $_.Total -eq 18}).Count -gt 0) 'Progress reserves its final stage for the all-known device catalog'
Assert ((Get-ScanProgressText 17 18 5) -match '94%' -and (Get-ScanProgressText 18 18 5) -match '100%') 'Normal queries finishing cannot display 100 percent while device enrichment is still running'
Assert ($null -eq $script:scanProgressTotal -and $null -eq $script:scanQueryWorker) 'Full scan releases its progress and worker state'
$report=$full.Inventory;$warnings=$full.Warnings;$identifiers=$full.Identifiers
$report.Remove('Extended scan info');$report.Remove('Extended device inventory');$report['Report info'].Remove('ExtendedStatus')
Start-HardwareRescan -UseWorker $false
Assert ($report['Report info'].ScanNumber -eq 2 -and $report['Extended device inventory'].Count -eq 40 -and $lastScanPrevious['Report info'].ScanNumber -eq 1 -and -not $lastScanPrevious.Contains('Extended scan info')) 'Rescanning an older present-only capture automatically adds all-known records and preserves the baseline'
Assert ($report['PnP hardware IDs'].Count -eq 1 -and @($report['Extended device inventory'] | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count -eq 20) 'Remembered nodes remain separate from the normal present-device list'
$scanFunction=(Get-Item Function:Invoke-HardwareScan).ScriptBlock
function Invoke-HardwareScan {param([bool]$IncludeExtended) $script:startupExtended=$IncludeExtended;[pscustomobject]@{}}
$startup=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$initialScan'},$false) | Select-Object -First 1
. ([scriptblock]::Create($startup.Extent.Text))
Assert ($script:startupExtended -eq $true) 'The actual application startup requests the all-known device catalog'
Set-Item Function:Invoke-HardwareScan -Value $scanFunction
$originalExtended=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock
function Get-ExtendedDeviceInventory {throw [TimeoutException]::new('Synthetic all-known read timeout')}
$partial=Invoke-HardwareScan 3 -UseWorker $false -IncludeExtended $true
Assert ($partial.Completed -and $partial.Inventory['Report info'].ExtendedStatus -eq 'Unavailable' -and -not $partial.Inventory.Contains('Extended device inventory') -and $partial.Inventory['Scan timing'].Count -eq 17 -and $partial.Warnings.Count -eq 1) 'An unavailable catalog preserves normal results and explicit failure instead of attaching stale device rows'
Assert ($progress[-1].Completed -eq 18 -and $null -eq $script:scanProgressTotal) 'A failed final stage finishes progress and clears scan state'
Set-Item Function:Get-ExtendedDeviceInventory -Value $originalExtended
$basic=Invoke-HardwareScan 4 -UseWorker $false -IncludeExtended $false
Assert ($basic.Completed -and -not $basic.Inventory.Contains('Extended scan info') -and $progress[-1].Total -eq 17 -and $progress[-1].Completed -eq 17) 'Internal present-only scans retain their seventeen-stage behavior'
[Console]::WriteLine("All $script:checks device-coverage checks passed under PowerShell $($PSVersionTable.PSVersion).")
