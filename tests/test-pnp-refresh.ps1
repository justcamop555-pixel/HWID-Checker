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
    [pscustomobject]@{Name='Fixture device';PNPClass='USB';PNPDeviceID='USB\000A';InstanceId='USB\ALIAS';ClassGuid='{36fc9e60-c465-11cf-8056-444553540000}';Present=$true;HardwareID=@('MODEl-0001','MODEL-0002');CompatibleID=@('COMPAT-0001');ConfigManagerErrorCode=0}
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if(-not $PresentOnly){throw 'Unexpected device scope'}
    [pscustomobject]@{FriendlyName='Fallback fixture';Class='USB';PNPDeviceID='USB\000A';InstanceId='USB\ALIAS';ClassGuid='{36fc9e60-c465-11cf-8056-444553540000}';Present=$true;HardwareID=@('MODEl-0001','MODEL-0002');CompatibleID=@('COMPAT-0001');ConfigManagerErrorCode=0}
}
$primaryTemplate=@'
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    $record=[pscustomobject]@{Name='Malformed fixture';PNPClass='USB';PNPDeviceID='USB\000A';InstanceId='USB\ALIAS';ClassGuid='{36fc9e60-c465-11cf-8056-444553540000}';Present=$true;HardwareID=@('MODEL');ConfigManagerErrorCode=0}
    $record.__FIELD__=@('BAD-A','BAD-B')
    $record
}
Get-DriverHardwareIds
'@
$fallbackTemplate=@'
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw [NotSupportedException]::new('Synthetic unsupported primary')}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if(-not $PresentOnly){throw 'Unexpected device scope'}
    $record=[pscustomobject]@{FriendlyName='Malformed fallback';Class='USB';PNPDeviceID='USB\000A';InstanceId='USB\ALIAS';ClassGuid='{36fc9e60-c465-11cf-8056-444553540000}';Present=$true;HardwareID=@('MODEL');ConfigManagerErrorCode=0}
    $record.__FIELD__=@('BAD-A','BAD-B')
    $record
}
Get-DriverHardwareIds
'@
$root=Join-Path $PSScriptRoot ('test-output-pnp-refresh-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        foreach($field in @('PNPDeviceID','InstanceId','ClassGuid')){
            $failure=$null;$rows=@()
            try{$rows=@(Invoke-ScanQuery ([scriptblock]::Create($primaryTemplate.Replace('__FIELD__',$field))))}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq 'READ-06' -and $rows.Count -eq 0) ($mode+' primary '+$field+' arrays cannot become readable or joined device keys')
        }
        foreach($field in @('PNPDeviceID','InstanceId','ClassGuid')){
            $failure=$null;$rows=@()
            try{$rows=@(Invoke-ScanQuery ([scriptblock]::Create($fallbackTemplate.Replace('__FIELD__',$field))))}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq 'READ-06' -and $rows.Count -eq 0 -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' fallback '+$field+' arrays stay invalid before alias mapping')
        }
        $valid=@(Invoke-ScanQuery {Get-DriverHardwareIds})
        Assert ($valid.Count -eq 1 -and $valid[0].DeviceInstanceId -ceq 'USB\000A' -and $valid[0].HardwareID.Count -eq 2 -and $valid[0].HardwareID[0] -ceq 'MODEl-0001' -and $valid[0].CompatibleID[0] -ceq 'COMPAT-0001') ($mode+' a clean read after failures preserves exact IDs and model lists')
        $statusRows=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Unread status';PNPDeviceID='USB\STATUS';Present=$true;HardwareID=@('MODEL');ConfigManagerErrorCode=@(0)}}
            Get-DriverHardwareIds
        })
        $status=Get-PnpStatus $statusRows[0].ConfigManagerErrorCode
        Assert ($statusRows.Count -eq 1 -and $status.Quality -eq 'Unknown' -and $null -eq $status.Code -and @((Get-PnpIssues $statusRows) | Where-Object Kind -eq 'UnknownStatus').Count -eq 1) ($mode+' an array-shaped status remains unread without discarding the valid device')
        $inventory=[ordered]@{'Report info'=@{Version='3.62';Computer='TEST';Generated='2026-10-30T12:00:00Z'};'PnP hardware IDs'=$valid}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic PnP refresh snapshot' ($inventory | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'PnP hardware IDs'[0].DeviceInstanceId -ceq 'USB\000A' -and $saved.'PnP hardware IDs'[0].HardwareID.Count -eq 2 -and $saved.'PnP hardware IDs'[0].HardwareID[0] -ceq 'MODEl-0001' -and $saved.'PnP hardware IDs'[0].CompatibleID[0] -ceq 'COMPAT-0001') ($mode+' saved/imported PnP rows retain exact keys and complete ID arrays')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$originalCim=(Get-Item Function:Get-CimInstance).ScriptBlock
$report=[ordered]@{'Report info'=[ordered]@{ScanNumber=1};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-UNCHANGED'});'PnP hardware IDs'=@([pscustomobject]@{Name='Earlier device';DeviceInstanceId='USB\OLD';HardwareID=@('OLD-MODEL');ConfigManagerErrorCode=0})}
$warnings=New-Object 'System.Collections.Generic.List[string]'
try{
    function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Malformed refresh';PNPDeviceID=@('USB\A','USB\B');HardwareID=@('MODEL');ConfigManagerErrorCode=0}}
    Show-DriverHardwareIds
    Assert (-not (Test-SectionReadable $report['PnP hardware IDs']) -and $report['PnP hardware IDs'].FailureCode -eq 'READ-06' -and $warnings.Count -eq 1) 'Opening the present-device view cannot clear a malformed-key failure or publish joined IDs'
    Show-DriverHardwareIds
    Assert ($warnings.Count -eq 1 -and $report.Warnings.Count -eq 1 -and $report['PnP hardware IDs'].FailureCode -eq 'READ-06') 'Repeated invalid refreshes retain one current warning and NOT READ data'
    Set-Item Function:Get-CimInstance -Value $originalCim
    Show-DriverHardwareIds
    Assert ((Test-SectionReadable $report['PnP hardware IDs']) -and $warnings.Count -eq 0 -and $report.Warnings.Count -eq 0 -and $report['PnP hardware IDs'][0].DeviceInstanceId -ceq 'USB\000A') 'A later valid refresh clears the failed read once and publishes the new exact device key'
    Assert ($report.CPU[0].ProcessorId -ceq 'CPU-UNCHANGED' -and $report['Report info'].ScanNumber -eq 1) 'A present-device refresh leaves the other hardware and scan number intact'
}finally{Set-Item Function:Get-CimInstance -Value $originalCim}
foreach($bad in @(@(0),@(22),@{Code=0},[pscustomobject]@{Code=22},$true,$false,[datetime]::UtcNow,[datetimeoffset]::UtcNow)){
    $status=Get-PnpStatus $bad
    Assert ($status.Quality -eq 'Unknown' -and $null -eq $status.Code -and $status.Text -notmatch 'Working|Disabled') 'Malformed status types cannot assert a working or disabled device'
}
Assert ((Get-PnpStatus 0).Quality -eq 'OK' -and (Get-PnpStatus '00').Code -eq 0 -and (Get-PnpStatus '00').Text -match 'Working') 'Numeric and numeric-string zero remain genuine working status'
Assert ((Get-PnpStatus 22).Code -eq 22 -and (Get-PnpStatus '022').Code -eq 22 -and (Get-PnpStatus '022').Text -match 'Disabled') 'Numeric and padded numeric-string disabled status remain readable'
Assert ((Get-PnpStatus '28').Code -eq 28 -and (Get-PnpStatus '28').Text -match 'Driver not installed') 'A valid reported driver problem remains a review finding'
[Console]::WriteLine("All $script:checks PnP-refresh checks passed under PowerShell $($PSVersionTable.PSVersion).")
