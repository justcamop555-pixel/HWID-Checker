param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop';$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
foreach($name in @('$sectionGroups','$identifierPattern','$script:scanTotal')){
    $assignment=$ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $name},$false) | Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,$Message){if(-not $Condition){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Reset-UiPage {}
function Start-UiReport {param([switch]$Scanning)}
function Complete-UiReport {}
function Write-Heading {param($Title) $script:rendered.Add([pscustomobject]@{Label='Heading';Value=$Title;Color=$null})}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function Show-RescanResult {param($Previous,$Current)}
function Wait-ScanContinue {param($Destination,$KeyReader)}
$ownedConsole=$false;$redirected=$true
$display=[pscustomobject]@{Mode='Synthetic scan failure tests'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
function New-Snapshot($Number,$ReadableName,[bool]$Catalog=$false) {
    $inventory=[ordered]@{'Report info'=[ordered]@{Version='3.0';Computer='SYNTHETIC';Generated='2026-11-09T12:00:00Z';ScanNumber=$Number}}
    $timing=New-Object 'System.Collections.Generic.List[object]'
    foreach($name in @($sectionGroups.Values | ForEach-Object {$_})+@('PnP hardware IDs')){
        $inventory[$name]=@{Unavailable='Synthetic read denied';FailureCode='READ-01';FailureReason='Access denied';NextStep='Retry the scan'}
        $status='UNAVAILABLE'
        if($name -eq $ReadableName){
            $status='READ'
            $inventory[$name]=if($name -eq 'CPU'){@([pscustomobject]@{DeviceID='CPU0';ProcessorId='SYNTHETIC-CPU'})}else{@([pscustomobject]@{Caption='Synthetic inventory details'})}
        }
        $timing.Add([pscustomobject]@{Section=$name;Status=$status;Results=$(if($status -eq 'READ'){1}else{0})})
    }
    $inventory['Scan timing']=$timing.ToArray()
    $inventory['Warnings']=@()
    if($Catalog){
        $inventory['Report info']['ExtendedStatus']='Refreshed'
        $inventory['Extended device inventory']=@([pscustomobject]@{Name='Synthetic known device';DeviceInstanceId='USB\SYNTHETIC';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL')})
        $inventory['Extended scan info']=@{Captured='2026-11-09T12:00:00Z';Source='Synthetic';Records=1}
    }
    [pscustomobject]@{Completed=$true;Inventory=$inventory;Warnings=(New-Object 'System.Collections.Generic.List[string]');Identifiers=@(Get-IdentifierRows $inventory)}
}
$empty=New-Snapshot 2 $null
Assert (-not (Test-ScanHasReadableData $empty.Inventory)) 'Finished attempts alone cannot make an unreadable scan usable'
$partial=New-Snapshot 2 'CPU'
Assert (Test-ScanHasReadableData $partial.Inventory) 'One genuinely readable hardware section is a usable partial capture'
$cpuTiming=$partial.Inventory['Scan timing'] | Where-Object Section -eq 'CPU'
foreach($status in @('READ','check')){
    $cpuTiming.Status=$status
    Assert (Test-ScanHasReadableData $partial.Inventory) ($status+' is a recognized successful read state')
}
foreach($status in @('READING','WAITING','STOPPED','UNKNOWN')){
    $cpuTiming.Status=$status
    Assert (-not (Test-ScanHasReadableData $partial.Inventory)) ($status+' cannot masquerade as a finished readable section')
}
$catalog=New-Snapshot 2 $null $true
Assert (Test-ScanHasReadableData $catalog.Inventory) 'A genuinely refreshed device catalog is useful even if ordinary readers fail'
$catalog.Inventory['Extended scan info']['Error']='Synthetic catalog failure'
Assert (-not (Test-ScanHasReadableData $catalog.Inventory)) 'A catalog error cannot authorize a replacement snapshot'
$catalog.Inventory['Extended scan info'].Remove('Error')
$catalog.Inventory['Extended device inventory']=@([pscustomobject]@{})
Assert (-not (Test-ScanHasReadableData $catalog.Inventory)) 'An arbitrary catalog placeholder is not readable device data'

$realScan=(Get-Item Function:Invoke-HardwareScan).ScriptBlock
$script:nextSnapshot=$empty
function Invoke-HardwareScan {param($ScanNumber,$UseWorker,$IncludeExtended) $script:nextSnapshot}
$previous=New-Snapshot 1 'CPU'
$report=$previous.Inventory;$warnings=$previous.Warnings;$identifiers=$previous.Identifiers
$script:lastScanPrevious=@{Sentinel='previous comparison'};$script:lastScanCurrent=@{Sentinel='current comparison'}
$comparisonBefore=$script:lastScanPrevious
Start-HardwareRescan -UseWorker $false
Assert ([object]::ReferenceEquals($report,$previous.Inventory) -and [object]::ReferenceEquals($warnings,$previous.Warnings) -and [object]::ReferenceEquals($identifiers,$previous.Identifiers)) 'A wholly failed rescan preserves the previous inventory, warnings and identifiers together'
Assert ([object]::ReferenceEquals($script:lastScanPrevious,$comparisonBefore) -and @($rendered | Where-Object {$_.Value -match 'READ-07'}).Count -eq 1) 'A failed rescan preserves comparison history and gives an actionable error code'
$script:nextSnapshot=New-Snapshot 2 'CPU'
Start-HardwareRescan -UseWorker $false
Assert ($report['Report info'].ScanNumber -eq 2 -and $report.CPU[0].ProcessorId -ceq 'SYNTHETIC-CPU') 'A later partial scan can publish normally after total reader failure'
$script:nextSnapshot=New-Snapshot 3 $null $true
Start-HardwareRescan -UseWorker $false
Assert ($report['Report info'].ScanNumber -eq 3 -and $report['Extended device inventory'][0].DeviceInstanceId -ceq 'USB\SYNTHETIC') 'A catalog-only rescan publishes its genuinely read data'

function Get-Date {param($Format) $script:clockCalls++;return ([datetime]'2026-11-09T12:00:00Z').AddMinutes(10*$script:clockCalls)}
function Read-MenuChoice {param($Maximum) return '1'}
function Clear-ScanTypeAhead {}
function Start-Sleep {param($Seconds,$Milliseconds) if($Seconds -eq 3){throw 'Synthetic end of watch cycle'}}
$ownedConsole=$true;$redirected=$false
$script:clockCalls=0;$script:nextSnapshot=New-Snapshot 4 $null
$beforeWatch=$report
Start-ChangeWatch
Assert ([object]::ReferenceEquals($beforeWatch,$report)) 'Automatic watch scans also preserve the last readable snapshot after total failure'
$script:clockCalls=0;$script:nextSnapshot=New-Snapshot 4 'Windows'
$report=(New-Snapshot 3 'Windows').Inventory;$warnings=New-Object 'System.Collections.Generic.List[string]';$identifiers=@();$script:rendered.Clear()
Start-ChangeWatch
Assert (@($rendered | Where-Object {$_.Label -eq 'IDs not compared' -and $_.Color -eq $palette.Warn}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Result' -and $_.Value -match 'No changes'}).Count -eq 0) 'Watch mode explains missing comparisons instead of claiming unchanged IDs'
Remove-Item Function:Get-Date;Remove-Item Function:Start-Sleep
$ownedConsole=$false;$redirected=$true
Set-Item Function:Invoke-HardwareScan -Value $realScan
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw [UnauthorizedAccessException]::new('Synthetic provider denial')}
function Get-NetAdapter {param([switch]$IncludeHidden) throw [UnauthorizedAccessException]::new('Synthetic adapter denial')}
function Get-ItemProperty {param($LiteralPath,$Name) throw [UnauthorizedAccessException]::new('Synthetic registry denial')}
function Get-PnpDevice {param([switch]$PresentOnly) throw [UnauthorizedAccessException]::new('Synthetic PnP denial')}
function Get-ExtendedDeviceInventory {throw [UnauthorizedAccessException]::new('Synthetic catalog denial')}
foreach($worker in @($false,$true)){
    $script:rendered.Clear()
    $failed=Invoke-HardwareScan 1 -UseWorker $worker -IncludeExtended $true
    Assert ($failed.Completed -and -not (Test-ScanHasReadableData $failed.Inventory) -and $failed.Warnings.Count -eq ($scanTotal+1)) ('Worker='+$worker+' initial scans retain all failed-read diagnostics without a fatal startup error')
    Assert (@($rendered | Where-Object {$_.Label -eq 'Heading' -and $_.Value -ceq 'SCAN FINISHED / NO DATA READ'}).Count -eq 1 -and @($rendered | Where-Object {$_.Label -eq 'Next step' -and $_.Value -match '\[4\]'}).Count -eq 1) ('Worker='+$worker+' completion states no data was read and explains where to inspect failures')
    Assert ($failed.Inventory.CPU.FailureCode -ceq 'READ-01' -and $failed.Inventory.CPU.Unavailable -ceq 'Synthetic provider denial') ('Worker='+$worker+' raw provider details and established codes remain intact')
}
$sectionGroups['Synthetic extra category']=@('Synthetic optional data')
$script:deviceMenuKey=$null
function Show-MenuItem {param($Key,$Label,$Hint) if($Label -ceq 'All device IDs (PnP / drivers)'){$script:deviceMenuKey=[int]$Key}}
function Read-MenuChoice {param($Maximum) return '0'}
$script:hostMessages=New-Object 'System.Collections.Generic.List[string]'
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:hostMessages.Add([string]$Object)}
[void](Show-Categories)
Show-Help
Show-DriverHardwareIds
$deviceKey=Get-DeviceCategoryKey
Assert ($script:deviceMenuKey -eq $deviceKey -and @($rendered | Where-Object {$_.Label -ceq ('Deep IDs [3] > ['+$deviceKey+']')}).Count -eq 1 -and @($hostMessages | Where-Object {$_ -ceq ('  Reopen [3] > ['+$deviceKey+'] to retry.')}).Count -eq 1) 'Help and retry hints follow the actual device-menu key when categories change'
[Console]::WriteLine("All $script:checks readable-scan checks passed under PowerShell $($PSVersionTable.PSVersion).")
