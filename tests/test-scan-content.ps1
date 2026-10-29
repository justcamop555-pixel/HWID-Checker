$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0;$script:scanQueryWorker=$null
Section 'CPU' {[pscustomobject]@{Name=$null;ProcessorId=$null;DeviceID=$null}}
Assert ($report.CPU.FailureCode -eq 'READ-06' -and $scanTimings[0].Status -eq 'UNAVAILABLE') 'An all-empty projected hardware record is not counted as readable data'
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    [pscustomobject]@{Name='Mixed model data';PNPDeviceID='PCI\ONE';PNPClass='System';HardwareID=@('MODEL-A',$true,123,' ');CompatibleID=@('COMPAT-A',$false);ConfigManagerErrorCode=0;Present=$true}
    [pscustomobject]@{Name='Only invalid models';PNPDeviceID='PCI\TWO';PNPClass='System';HardwareID=@($false,123);CompatibleID=@();ConfigManagerErrorCode=0;Present=$true}
    [pscustomobject]@{Name='Single model';PNPDeviceID='PCI\THREE';PNPClass='System';HardwareID='MODEL-C';CompatibleID=$null;ConfigManagerErrorCode=0;Present=$true}
}
$root=Join-Path $PSScriptRoot ('test-output-content-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        foreach($fixture in @('Nulls','Whitespace','EmptyLists','OnlyReadLabels')){
            $query=switch($fixture){
                'Nulls' {[scriptblock]{[pscustomobject]@{Name=$null;SerialNumber=$null}}}
                'Whitespace' {[scriptblock]{[pscustomobject]@{Name=" `t`0 ";SerialNumber=' '}}}
                'EmptyLists' {[scriptblock]{[pscustomobject]@{HardwareID=@();Values=@($null,' ')}}}
                'OnlyReadLabels' {[scriptblock]{[pscustomobject]@{Name=$null;SerialNumber=$null;SerialNumberReadStatus='Not supplied';NameReadStatus='Not supplied';CollectionSource='CIM'}}}
            }
            Section 'CPU' $query
            Assert ($report.CPU.FailureCode -eq 'READ-06' -and $scanTimings[-1].Results -eq 0 -and -not (Test-SectionReadable $report.CPU)) ($mode+' '+$fixture+' is explicitly unreadable rather than a successful empty record')
        }
        Section 'CPU' {[pscustomobject]@{Name='Real device';ProcessorId=$null;DeviceID='CPU0'}}
        Assert ((Test-SectionReadable $report.CPU) -and $scanTimings[-1].Status -eq 'CHECK') ($mode+' a real device with an omitted identifier remains readable and reviewable')
        Section 'Valid metadata' {[pscustomobject]@{Enabled=$false;Size=0;Values=@()}}
        Assert ($report.'Valid metadata'[0].Enabled -eq $false -and $report.'Valid metadata'[0].Size -eq 0 -and $scanTimings[-1].Status -eq 'READ') ($mode+' actual zero and false values remain meaningful data')
        Section 'PnP hardware IDs' {Get-DriverHardwareIds}
        $devices=$report.'PnP hardware IDs'
        Assert ($devices.Count -eq 3 -and $devices[0].HardwareID.Count -eq 1 -and $devices[0].HardwareID[0] -ceq 'MODEL-A' -and $devices[0].CompatibleID[0] -ceq 'COMPAT-A') ($mode+' valid model and compatible IDs survive malformed neighboring entries')
        Assert ($devices[0].RawHardwareID.Count -eq 4 -and $devices[0].RawHardwareID[1] -eq $true -and $devices[0].HardwareIDReadStatus -match 'Invalid entries') ($mode+' malformed model data is preserved raw with an explicit read status')
        Assert ($devices[1].HardwareID.Count -eq 0 -and $devices[1].RawHardwareID.Count -eq 2 -and $devices[2].HardwareID[0] -ceq 'MODEL-C') ($mode+' invalid-only lists do not become models while singleton string IDs remain supported')
        $info=Get-SectionIdentifierInfo 'PnP hardware IDs' $devices
        Assert ($info.Text -match '3 instance IDs; 2 with model IDs' -and $info.Tag -eq 'CHECK') ($mode+' scan counts include only valid model lists and flag repaired entries for review')
        $review=Get-ReviewSummary $report @() @()
        Assert ($review.DeviceCount -eq 2 -and @($review.DeviceIssues | Where-Object Kind -eq 'InvalidIdList').Count -eq 2) ($mode+' repaired lists have explicit findings in main warning review')
        $report['Report info']=@{Version='3.57';Computer='TEST';Generated='2026-10-29T12:00:00Z'}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic content report' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'PnP hardware IDs'[0].RawHardwareID[1] -eq $true -and $saved.'PnP hardware IDs'[0].HardwareID[0] -ceq 'MODEL-A') ($mode+' saved snapshots retain exact valid IDs and raw malformed entries')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$legacyInfo=Get-SectionIdentifierInfo 'PnP hardware IDs' @([pscustomobject]@{DeviceInstanceId='PCI\LEGACY';HardwareID=@($true,123);ConfigManagerErrorCode=0})
Assert ($legacyInfo.Text -match '0 with model IDs') 'Older/custom reports cannot inflate model-ID counts with non-string list values'
Assert ((Get-DeviceReviewAction ([pscustomobject]@{Kind='InvalidIdList'})) -match 'Main \[5\]') 'Malformed model-list findings point to raw report data rather than an unrelated device status code'
[Console]::WriteLine("All $script:checks scan-content checks passed under PowerShell $($PSVersionTable.PSVersion).")
