param([switch]$LiveProgress,[switch]$Extended)
$ErrorActionPreference='Stop'
# Read-only hardware smoke test. Print counts/timing only; never identifiers.
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$groups=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$ownedConsole=$false;$redirected=$true
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$display=[pscustomobject]@{Mode='Read-only diagnostic'}
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$script:scanTotal=17
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$initial=Invoke-HardwareScan 1 -UseWorker $LiveProgress.IsPresent
$script:report=$initial.Inventory;$script:warnings=$initial.Warnings;$script:identifiers=$initial.Identifiers
if($Extended) {
    $catalog=Get-ExtendedDeviceInventory
    $report['Extended device inventory']=$catalog.Devices
    $report['Extended scan info']=$catalog.Info
}
$firstRead=(@(Get-ScanCoverage $report) | Measure-Object Read -Sum).Sum
$firstSeconds=$report['Report info'].ScanSeconds
Start-HardwareRescan -UseWorker $LiveProgress.IsPresent
if($report['Report info'].ScanNumber -ne 2 -or $lastScanPrevious['Report info'].ScanNumber -ne 1){throw 'Live rescan did not publish its snapshot and preserve the baseline.'}
if($report['Scan timing'].Count -ne 17 -or $scanStep -ne 17){throw 'Live rescan counters or timing did not reset.'}
if($LiveProgress -and ($initial.Inventory['Report info'].QueryMode -ne 'Live progress' -or $report['Report info'].QueryMode -ne 'Live progress')){throw 'The live-progress diagnostic unexpectedly used direct queries.'}
if($Extended -and ($report['Report info'].ExtendedStatus -ne 'Refreshed' -or -not $report['Extended device inventory'].Count)){throw 'Rescan did not refresh the requested extended catalog.'}
[pscustomobject]@{
    InitialSectionsRead=$firstRead;RescanSectionsRead=(@(Get-ScanCoverage $report) | Measure-Object Read -Sum).Sum
    TotalSections=17;InitialSeconds=$firstSeconds;RescanSeconds=$report['Report info'].ScanSeconds
    RescanWarnings=$warnings.Count;SnapshotNumber=$report['Report info'].ScanNumber
    PreviousSnapshotKept=($lastScanPrevious['Report info'].ScanNumber -eq 1)
    RescanTimingRecords=$report['Scan timing'].Count
    QueryMode=$report['Report info'].QueryMode
    ExtendedStatus=$report['Report info'].ExtendedStatus
    ExtendedRecords=@($report['Extended device inventory'] | Where-Object {$null -ne $_}).Count
    CurrentDeviceNodes=@($report['PnP hardware IDs'] | Where-Object DeviceInstanceId).Count
} | ConvertTo-Json
