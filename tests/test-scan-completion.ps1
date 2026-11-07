param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18;$display=[pscustomobject]@{Mode='Synthetic completion scan'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[object]';$script:progress=New-Object 'System.Collections.Generic.List[int]'
$script:failLabel=$null;$script:failHeading=$false;$script:failFinalProgress=$false
$script:realFactory=(Get-Item Function:New-ScanQueryWorker).ScriptBlock;$script:realSection=(Get-Item Function:Section).ScriptBlock
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Write-PnpValue {param($Label,$Value,$Color) if($Label -eq $script:failLabel){throw 'Synthetic completion value failure'};$script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function Write-Heading {param($Title) if($script:failHeading -and $Title -in @('SCAN COMPLETE','SCAN FINISHED / READ GAPS')){throw 'Synthetic completion heading failure'};$script:rendered.Add([pscustomobject]@{Label='Heading';Value=$Title;Color=$palette.Heading})}
function Update-ScanProgress {param([int]$Completed=$script:scanStep) $script:progress.Add($Completed);if($script:failFinalProgress -and $Completed -eq 19){throw 'Synthetic final progress failure'}}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Synthetic adapter';InterfaceGuid='NIC-0001';MacAddress='001122334455';HardwareInterface=$true}}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Synthetic component';Caption='Synthetic Windows';DeviceID='CPU0';PNPDeviceID='USB\SYNTHETIC';InstanceName='MONITOR0';PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL');SerialNumber='000123';UUID='SYSTEM-0001';ProcessorId='CPU-0001';IdentifyingNumber='SYSTEM-0001';Manufacturer='Synthetic';Model='Synthetic';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;DeviceLocator='DIMM0';BankLabel='BANK0';Size=8GB;Capacity=8GB;TotalPhysicalMemory=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='WINDOWS-0001'}}
function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Synthetic device';DeviceInstanceId='USB\SYNTHETIC';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0});Info=@{Captured='2026-11-01T12:00:00-05:00';Source='Synthetic';Records=1}}}
$script:normalCim=(Get-Item Function:Get-CimInstance).ScriptBlock;$script:normalExtended=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock
$root=Join-Path $PSScriptRoot ('test-output-scan-completion-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $useWorker=$mode -eq 'Worker';$script:rendered.Clear();$script:progress.Clear();$script:failLabel='Finished'
    $snapshot=$null;$failure=$null
    try{$snapshot=Invoke-HardwareScan 1 -UseWorker $useWorker -IncludeExtended $true}catch{$failure=$_}
    Assert ($null -eq $failure -and $snapshot.Completed -and $snapshot.Inventory['Scan timing'].Count -eq 18) ($mode+' completion display failure cannot discard a finished snapshot')
    Assert ($snapshot.Inventory['Report info'].CompletionDisplayWarning -match 'completion value failure' -and $snapshot.Warnings.Count -eq 0) ($mode+' completion feedback is retained separately from hardware-read warnings')
    Assert ($snapshot.Inventory.CPU[0].ProcessorId -ceq 'CPU-0001' -and $snapshot.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') ($mode+' completion failure keeps IDs and the all-known catalog')
    Assert ($null -eq $script:scanQueryWorker -and $null -eq $script:scanProgressClock -and $null -eq $script:scanGroupState -and $null -eq $script:scanViewState) ($mode+' scan state is released after completion failure')
    $script:failLabel=$null;$script:rendered.Clear();$script:progress.Clear();$normal=Invoke-HardwareScan 2 -UseWorker $useWorker -IncludeExtended $true
    Assert ($normal.Completed -and -not $normal.Inventory['Report info'].Contains('CompletionDisplayWarning')) ($mode+' the next scan does not inherit old completion warnings')
    Assert (@($rendered | Where-Object {$_.Label -eq 'Heading' -and $_.Value -eq 'SCAN COMPLETE'}).Count -eq 1) ($mode+' a complete read has a clear completion heading')
    Assert (@($rendered | Where-Object {$_.Label -eq 'Finished' -and $_.Value -match '18/18 finished / 18 read / 0 not read / extended READ' -and $_.Color -eq $palette.Good}).Count -eq 1) ($mode+' completion distinguishes finished attempts from read coverage')
    $found=@($normal.Identifiers | Where-Object Quality -eq 'Reported').Count
    Assert (@($rendered | Where-Object {$_.Label -eq 'Selected IDs' -and $_.Value -match ('^'+$found+' ')}).Count -eq 1) ($mode+' completion counts reported selected fields without promising unique hardware IDs')
    $review=Get-ReviewSummary $normal.Inventory $normal.Identifiers $normal.Warnings
    Assert (@($rendered | Where-Object {$_.Label -eq 'Review' -and $_.Value -match ('^'+$review.Total+' findings')}).Count -eq 1 -and $script:progress[-1] -eq 19) ($mode+' the completion review agrees with the main menu and reaches the final stage')
    $script:failHeading=$true;$headingFailure=Invoke-HardwareScan 3 -UseWorker $useWorker -IncludeExtended $true;$script:failHeading=$false
    Assert ($headingFailure.Completed -and $headingFailure.Inventory['Report info'].CompletionDisplayWarning -match 'completion heading') ($mode+' heading failure cannot discard completed hardware reads')
    $script:failFinalProgress=$true;$progressFailure=Invoke-HardwareScan 4 -UseWorker $useWorker -IncludeExtended $true;$script:failFinalProgress=$false
    Assert ($progressFailure.Completed -and $progressFailure.Inventory['Report info'].CompletionDisplayWarning -match 'final progress') ($mode+' final progress failure stays visible without invalidating the snapshot')
    $script:failLabel='Finished';$script:failFinalProgress=$true;$both=Invoke-HardwareScan 5 -UseWorker $useWorker -IncludeExtended $true;$script:failLabel=$null;$script:failFinalProgress=$false
    Assert ($both.Inventory['Report info'].CompletionDisplayWarning -match 'final progress.*completion value') ($mode+' multiple completion feedback failures retain both explanations')
    $parameters='param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)'
    $cpuFailure=$script:normalCim.ToString().Replace($parameters,($parameters+' if($ClassName -eq "Win32_Processor"){throw [TimeoutException]::new("Synthetic CPU timeout")}'))
    Set-Item Function:Get-CimInstance -Value ([scriptblock]::Create($cpuFailure))
    $script:rendered.Clear();$partial=Invoke-HardwareScan 6 -UseWorker $useWorker -IncludeExtended $true
    Assert ($partial.Completed -and $partial.Inventory.CPU.FailureCode -eq 'READ-02' -and $partial.Warnings.Count -eq 1) ($mode+' a finished partial read retains its real typed failure')
    Assert (@($rendered | Where-Object {$_.Label -eq 'Heading' -and $_.Value -eq 'SCAN FINISHED / READ GAPS'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Finished' -and $_.Value -match '17 read / 1 not read' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' unread data cannot be labeled as a fully read scan')
    Set-Item Function:Get-CimInstance -Value $script:normalCim
    Set-Item Function:Get-ExtendedDeviceInventory -Value {throw [TimeoutException]::new('Synthetic catalog timeout')}
    $script:rendered.Clear();$catalogFailure=Invoke-HardwareScan 7 -UseWorker $useWorker -IncludeExtended $true
    Assert ($catalogFailure.Completed -and $catalogFailure.Inventory['Report info'].ExtendedStatus -eq 'Unavailable' -and @($rendered | Where-Object {$_.Label -eq 'Finished' -and $_.Value -match 'extended NOT READ' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' an unavailable catalog remains separate from the 17 completed sections')
    Set-Item Function:Get-ExtendedDeviceInventory -Value $script:normalExtended
    $script:rendered.Clear();$short=Invoke-HardwareScan 8 -UseWorker $useWorker -IncludeExtended $false
    Assert ($short.Completed -and -not $short.Inventory.Contains('Extended scan info') -and @($rendered | Where-Object {$_.Label -eq 'Finished' -and $_.Value -match 'extended'}).Count -eq 0) ($mode+' section-only completion makes no catalog claim')
    $stem=Join-Path $root $mode;Write-ReportPair $stem ((Get-PlainRecords $both.Inventory['Report info']) -join [Environment]::NewLine) ($both.Inventory | ConvertTo-Json -Depth 12)
    $saved=Read-SavedReport ($stem+'.json')
    Assert ($saved.'Report info'.CompletionDisplayWarning -match 'final progress.*completion value' -and [IO.File]::ReadAllText($stem+'.txt') -match 'completion value failure') ($mode+' TXT and JSON retain completion diagnostics')
    Assert ((Compare-Inventories $both.Inventory $saved).Changes.Count -eq 0 -and $saved.CPU[0].ProcessorId -ceq 'CPU-0001') ($mode+' completion diagnostics cannot manufacture changed IDs')
}
function New-ScanQueryWorker {
    $actual=& $script:realFactory
    $proxy=[pscustomobject]@{Runspace=$actual.Runspace;Actual=$actual}
    $proxy | Add-Member ScriptMethod Dispose {$this.Actual.Dispose();throw 'Synthetic worker cleanup failure'}
    return $proxy
}
$cleanup=Invoke-HardwareScan 9 -UseWorker $true -IncludeExtended $true
Assert ($cleanup.Completed -and $cleanup.Inventory['Report info'].WorkerCleanupWarning -match 'worker cleanup failure' -and $cleanup.Inventory.CPU[0].ProcessorId -ceq 'CPU-0001') 'A worker cleanup exception cannot replace a successfully completed snapshot'
Assert ($null -eq $script:scanQueryWorker -and $null -eq $script:scanProgressClock -and $null -eq $script:scanGroupState) 'Failed worker disposal still clears reusable scan state'
function Section {param($Name,$Query) & $script:realSection $Name $Query;if($Name -eq 'PnP hardware IDs'){$script:scanStep=0}}
$script:progress.Clear();$failure=$null
try{Invoke-HardwareScan 10 -UseWorker $true -IncludeExtended $true | Out-Null}catch{$failure=$_}
Assert ($failure.Exception.Message -match 'did not finish every section' -and $failure.Exception.Message -notmatch 'worker cleanup failure') 'A cleanup exception cannot mask the original incomplete-scan failure'
Assert ($script:progress -notcontains 19) 'An incomplete snapshot cannot receive the final 100-percent completion update'
Set-Item Function:Section -Value $script:realSection;Set-Item Function:New-ScanQueryWorker -Value $script:realFactory
$fresh=Invoke-HardwareScan 11 -UseWorker $true -IncludeExtended $true
Assert ($fresh.Completed -and -not $fresh.Inventory['Report info'].Contains('WorkerCleanupWarning') -and $fresh.Warnings.Count -eq 0) 'A later scan starts with fresh completion and cleanup state'
$cleanup.Inventory['Report info'].Version='3.80'
$stem=Join-Path $root 'cleanup';Write-ReportPair $stem 'Synthetic cleanup warning' ($cleanup.Inventory | ConvertTo-Json -Depth 12)
$saved=Read-SavedReport ($stem+'.json')
Assert ($saved.'Report info'.WorkerCleanupWarning -match 'worker cleanup failure' -and (Compare-Inventories $cleanup.Inventory $saved).Changes.Count -eq 0) 'Saved cleanup diagnostics retain usable IDs without affecting comparisons'
[Console]::WriteLine("All $script:checks scan-completion checks passed under PowerShell $($PSVersionTable.PSVersion).")
