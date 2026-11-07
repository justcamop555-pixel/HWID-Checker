param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    $definition=$fn.Extent.Text
    if($fn.Name -eq 'Invoke-ScanQuery'){$definition=$definition.Replace('[PowerShell]::Create()','New-TestQueryCommand')}
    . ([scriptblock]::Create($definition))
}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18;$display=[pscustomobject]@{Mode='Synthetic query cleanup'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:closeFailure=$true;$script:disposeFailure=$true;$script:disposed=0;$script:closed=0
$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function New-TestQueryCommand {
    $proxy=[pscustomobject]@{Inner=[PowerShell]::Create();Runspace=$null;Streams=$null}
    $proxy.Streams=$proxy.Inner.Streams
    $proxy | Add-Member ScriptMethod AddScript {param($Code) $this.Inner.AddScript($Code)}
    $proxy | Add-Member ScriptMethod BeginInvoke {
        $this.Inner.Runspace=$this.Runspace
        $pending=[pscustomobject]@{Inner=$this.Inner.BeginInvoke();AsyncWaitHandle=$null}
        $handle=[pscustomobject]@{Inner=$pending.Inner.AsyncWaitHandle}
        $handle | Add-Member ScriptMethod WaitOne {param($Milliseconds) $this.Inner.WaitOne($Milliseconds)}
        $handle | Add-Member ScriptMethod Close {$this.Inner.Close();$script:closed++;if($script:closeFailure){throw 'Synthetic wait handle cleanup failure'}}
        $pending.AsyncWaitHandle=$handle
        $pending | Add-Member ScriptProperty IsCompleted {$this.Inner.IsCompleted}
        return $pending
    }
    # Keep the native result collection intact; a ScriptMethod otherwise unwraps
    # a single envelope differently under Windows PowerShell 5.1.
    $proxy | Add-Member ScriptMethod EndInvoke {param($Pending) return ,$this.Inner.EndInvoke($Pending.Inner)}
    $proxy | Add-Member ScriptMethod Dispose {$this.Inner.Dispose();$script:disposed++;if($script:disposeFailure){throw 'Synthetic query command cleanup failure'}}
    return $proxy
}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Synthetic';Caption='Synthetic Windows';DeviceID='CPU0';PNPDeviceID='USB\SYNTHETIC';InstanceName='MONITOR0';PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL');SerialNumber='000123';UUID='SYSTEM-0001';ProcessorId='CPU-0001';IdentifyingNumber='SYSTEM-0001';Manufacturer='Synthetic';Model='Synthetic';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;Size=8GB;Capacity=8GB;TotalPhysicalMemory=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Synthetic adapter';InterfaceGuid='NIC-0001';MacAddress='001122334455';HardwareInterface=$true}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='WINDOWS-0001'}}
function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Synthetic device';DeviceInstanceId='USB\SYNTHETIC';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0});Info=@{Captured='2026-11-02T12:00:00-05:00';Source='Synthetic';Records=1}}}
$root=Join-Path $PSScriptRoot ('test-output-query-cleanup-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$script:scanQueryWorker=New-ScanQueryWorker
try{
    $rows=@();$failure=$null
    try{$rows=@(Invoke-ScanQuery {[pscustomobject]@{ProcessorId='CPU-0001'}})}catch{$failure=$_}
    Assert ($null -eq $failure -and $rows.Count -eq 1 -and $rows[0].ProcessorId -ceq 'CPU-0001') 'Query cleanup cannot discard a fully validated result'
    Assert ($script:closed -eq 1 -and $script:disposed -eq 1) 'Command disposal still runs when closing its wait handle fails'
    Assert ($script:lastQueryCleanupFailure -match 'wait handle cleanup failure' -and $script:lastQueryCleanupFailure -match 'query command cleanup failure') 'Both cleanup diagnostics survive separately from provider errors'
    foreach($case in @(@('Timeout','throw [TimeoutException]::new("Synthetic provider timeout")','READ-02'),@('Denied','throw [UnauthorizedAccessException]::new("Synthetic provider denial")','READ-01'),@('Invalid','throw [IO.InvalidDataException]::new("Synthetic provider invalid data")','READ-06'))){
        $partial=@();$failure=$null
        try{$partial=@(Invoke-ScanQuery ([scriptblock]::Create('[pscustomobject]@{ProcessorId="PARTIAL"};'+$case[1])))}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($partial.Count -eq 0 -and $failure.Code -eq $case[2] -and $failure.Details -match 'Synthetic provider') ($case[0]+' original provider failure wins over simultaneous cleanup failures')
    }
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    Section CPU {[pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-0001'}}
    Assert ($report.CPU[0].ProcessorId -ceq 'CPU-0001' -and $scanTimings[0].Status -eq 'READ' -and $warnings.Count -eq 0) 'A successful section remains readable when only query cleanup fails'
    Assert ($scanTimings[0].QueryCleanupWarning -match 'wait handle cleanup failure' -and -not $scanTimings[0].ProgressWarning) 'Timing records distinguish query cleanup from hardware and display problems'
    Section CPU {throw [TimeoutException]::new('Synthetic section timeout')}
    Assert ($scanTimings[1].FailureCode -eq 'READ-02' -and $scanTimings[1].QueryCleanupWarning -match 'query command cleanup failure' -and $warnings.Count -eq 1) 'Unread sections retain the true provider code and independent cleanup detail'
    $script:closeFailure=$false;$script:disposeFailure=$false
    $healthy=@(Invoke-ScanQuery {[pscustomobject]@{ProcessorId='CPU-FRESH'}})
    Assert ($healthy[0].ProcessorId -ceq 'CPU-FRESH' -and -not $script:lastQueryCleanupFailure) 'The next query clears stale cleanup warnings'
}finally{$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
$script:closeFailure=$true;$script:disposeFailure=$true
$snapshot=Invoke-HardwareScan 1 -UseWorker $true -IncludeExtended $true
Assert ($snapshot.Completed -and @($snapshot.Inventory['Scan timing'] | Where-Object Status -ne 'UNAVAILABLE').Count -eq 18 -and $snapshot.Warnings.Count -eq 0) 'Full scans keep all eighteen valid reads despite command cleanup failures'
Assert ($snapshot.Inventory['Report info'].QueryCleanupSections -eq 18 -and @($snapshot.Inventory['Scan timing'] | Where-Object QueryCleanupWarning).Count -eq 18) 'Full scan metadata counts exactly the affected normal sections'
Assert ($snapshot.Inventory['Extended scan info'].QueryCleanupWarning -match 'query command cleanup failure' -and $snapshot.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') 'Extended catalog retains valid data and its separate query cleanup diagnostic'
Assert (@($rendered | Where-Object {$_.Label -eq 'Query cleanup' -and $_.Color -eq $palette.Warn}).Count -eq 1) 'Completion directs users to report details for query cleanup problems'
$stem=Join-Path $root 'cleanup';Write-ReportPair $stem ((Get-PlainRecords $snapshot.Inventory['Scan timing']) -join [Environment]::NewLine) ($snapshot.Inventory | ConvertTo-Json -Depth 12)
$saved=Read-SavedReport ($stem+'.json')
Assert ($saved.'Report info'.QueryCleanupSections -eq 18 -and $saved.'Scan timing'[0].QueryCleanupWarning -match 'wait handle cleanup failure') 'JSON export and import preserve query cleanup details'
Assert ([IO.File]::ReadAllText($stem+'.txt') -match 'query command cleanup failure') 'TXT reports preserve query cleanup details'
$comparison=Compare-Inventories $saved $snapshot.Inventory
Assert ($comparison.Changes.Count -eq 0 -and $comparison.PreviousCount -gt 0 -and $comparison.PreviousCount -eq $comparison.CurrentCount) 'Cleanup diagnostics cannot invent identifier changes'
$script:closeFailure=$false;$script:disposeFailure=$false
$fresh=Invoke-HardwareScan 2 -UseWorker $true -IncludeExtended $true
Assert ($fresh.Inventory['Report info'].QueryCleanupSections -eq 0 -and -not $fresh.Inventory['Extended scan info'].Contains('QueryCleanupWarning')) 'Fresh scans do not inherit earlier cleanup diagnostics'
$script:lastQueryCleanupFailure='Stale';$direct=@(Invoke-ScanQuery {[pscustomobject]@{ProcessorId='DIRECT'}})
Assert ($direct[0].ProcessorId -ceq 'DIRECT' -and -not $script:lastQueryCleanupFailure) 'Direct queries clear worker cleanup state'
$script:realFactory=(Get-Item Function:New-ScanQueryWorker).ScriptBlock
$script:catalogShows=0
function Reset-UiPage {}
function Start-UiReport {param([switch]$Scanning)}
function Start-ScanLine {param($Prefix) return $null}
function Write-Heading {param($Title)}
function Show-ExtendedDeviceReport {$script:catalogShows++}
function New-ScanQueryWorker {
    $actual=& $script:realFactory
    $proxy=[pscustomobject]@{Runspace=$actual.Runspace;Actual=$actual}
    $proxy | Add-Member ScriptMethod Dispose {$this.Actual.Dispose();throw 'Synthetic extended worker cleanup failure'}
    return $proxy
}
$ownedConsole=$true;$redirected=$false
$report=Copy-InventorySnapshot $fresh.Inventory;$warnings=New-Object 'System.Collections.Generic.List[string]'
$script:closeFailure=$true;$script:disposeFailure=$true
$failure=$null
try{Start-ExtendedDeviceScan}catch{$failure=$_}
Assert ($null -eq $failure -and $report['Report info'].ExtendedStatus -eq 'Refreshed' -and $script:catalogShows -eq 1) 'Standalone extended scan still presents its successful catalog after cleanup failures'
Assert ($report['Report info'].ExtendedQueryCleanupWarning -match 'query command cleanup failure' -and $report['Report info'].ExtendedWorkerCleanupWarning -match 'extended worker cleanup failure') 'Standalone extended scans retain query and session cleanup diagnostics separately'
Assert ($null -eq $script:scanQueryWorker -and $warnings.Count -eq 0 -and $report['Extended device inventory'][0].DeviceInstanceId -ceq 'USB\SYNTHETIC') 'Standalone cleanup clears worker state without converting valid hardware into warnings'
$oldCapture=$report['Extended scan info'].Captured
function Get-ExtendedDeviceInventory {throw [UnauthorizedAccessException]::new('Synthetic extended access denial')}
$failure=$null;try{Start-ExtendedDeviceScan}catch{$failure=$_}
Assert ($null -eq $failure -and $report['Report info'].ExtendedFailureCode -eq 'READ-01' -and $report['Report info'].ExtendedFailureDetails -match 'Synthetic extended access denial') 'Standalone query and session cleanup failures cannot hide the original catalog denial'
Assert ($report['Extended scan info'].Captured -eq $oldCapture -and $script:catalogShows -eq 1 -and $report['Report info'].ExtendedStatus -eq 'Unavailable') 'Failed standalone refresh keeps the earlier catalog and marks the attempt unavailable'
Assert ($null -eq $script:scanQueryWorker -and $report['Report info'].ExtendedQueryCleanupWarning -and $report['Report info'].ExtendedWorkerCleanupWarning) 'Failed standalone refresh still clears its worker and keeps both cleanup diagnostics'
function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Fresh device';DeviceInstanceId='USB\FRESH';Present=$true});Info=[pscustomobject]@{Captured='2026-11-02T12:01:00-05:00';Source='Synthetic';Records=1}}}
$ownedConsole=$false;$redirected=$true;$script:closeFailure=$false;$script:disposeFailure=$false
Start-ExtendedDeviceScan
Assert (-not $report['Report info'].Contains('ExtendedQueryCleanupWarning') -and -not $report['Report info'].Contains('ExtendedWorkerCleanupWarning') -and $report['Report info'].ExtendedStatus -eq 'Refreshed') 'A later direct catalog refresh clears stale standalone cleanup diagnostics'
Assert ($report['Extended device inventory'][0].DeviceInstanceId -ceq 'USB\FRESH' -and $warnings.Count -eq 0) 'A later healthy catalog replaces old data and removes the prior read warning'
$script:closeFailure=$true;$script:disposeFailure=$true
$objectMetadata=Invoke-HardwareScan 3 -UseWorker $true -IncludeExtended $true
Assert ($objectMetadata.Inventory['Extended scan info'].QueryCleanupWarning -match 'query command cleanup failure' -and $objectMetadata.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') 'Cleanup metadata supports both dictionary and object catalog info'
[Console]::WriteLine("All $script:checks query-cleanup checks passed under PowerShell $($PSVersionTable.PSVersion).")
