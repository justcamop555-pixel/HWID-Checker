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
$cases=@(
    @('8004100C','READ-03'),@('80041011','READ-03'),@('80041012','READ-03'),@('80041085','READ-03'),
    @('80041069','READ-02'),@('80041088','READ-02'),@('80041062','READ-01'),@('80043001','READ-05')
)
foreach($case in $cases){
    $exception=[Runtime.InteropServices.COMException]::new('Localized diagnostic',[Convert]::ToInt32($case[0],16))
    Assert ((Get-ScanFailureInfo $exception).Code -eq $case[1]) ($case[0]+' is classified from its HRESULT without English error text')
    $wrapped=[System.Management.Automation.ErrorRecord]::new([Exception]::new('Outer diagnostic',$exception),'Fixture',0,$null)
    Assert ((Get-ScanFailureInfo $wrapped).Code -eq $case[1] -and (Get-ScanFailureInfo $wrapped).Details -ceq 'Outer diagnostic') ($case[0]+' remains classified through an error wrapper without replacing its diagnostic')
    Assert ((Get-ScanFailureInfo ('Localized diagnostic 0x'+$case[0])).Code -eq $case[1]) ($case[0]+' is recognized in text-only stored diagnostics')
}
foreach($case in @(@('Timedout','READ-02'),@('Timeout','READ-02'),@('PrivilegeNotHeld','READ-01'),@('AccessDenied','READ-01'),@('ProviderNotFound','READ-03'),@('InvalidProviderRegistration','READ-03'),@('ProviderLoadFailure','READ-03'),@('NotSupported','READ-03'))){
    $exception=[Exception]::new('Localized legacy diagnostic')
    $exception | Add-Member -NotePropertyName ErrorCode -NotePropertyValue $case[0]
    Assert ((Get-ScanFailureInfo $exception).Code -eq $case[1]) ($case[0]+' legacy ErrorCode remains usable when StatusCode is absent')
}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -eq 'Healthy'){return [pscustomobject]@{DeviceID='CPU0';ProcessorId='0000123'}}
    throw [Runtime.InteropServices.COMException]::new('Localized provider diagnostic',[Convert]::ToInt32('8004100C',16))
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if(-not $PresentOnly){throw 'Present-device fallback widened its scope'}
    [pscustomobject]@{FriendlyName='Recovered';Class='USB';InstanceId='USB\RECOVERED';HardwareID=@('MODEL-0001');ConfigManagerErrorCode=0}
    [pscustomobject]@{FriendlyName='Remembered';InstanceId='USB\OLD';Present=$false;ConfigManagerErrorCode=45}
}
$root=Join-Path $PSScriptRoot ('test-output-scan-diagnostics-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        Section 'PnP hardware IDs' {Get-DriverHardwareIds}
        $rows=$report.'PnP hardware IDs'
        Assert ($warnings.Count -eq 0 -and $rows.Count -eq 1 -and $rows[0].DeviceInstanceId -ceq 'USB\RECOVERED') ($mode+' unsupported HRESULT recovers usable rows without including disconnected devices')
        Assert ($rows[0].CollectionSource -match 'present-only fallback' -and $scanTimings[0].Recoveries.Count -eq 1 -and $scanTimings[0].Recoveries[0].PrimaryFailure -match 'Localized') ($mode+' successful fallback retains its source and original failure')
        $protected=@(Invoke-ScanQuery {
            foreach($hex in @('80041069','80041088','80041062')){
                $script:diagnosticCalls=0;$script:diagnosticCode=$hex
                function Get-CimInstance {
                    param($ClassName,$Property)
                    $script:diagnosticCalls++
                    throw [Runtime.InteropServices.COMException]::new('Invalid query in outer diagnostic',[Convert]::ToInt32($script:diagnosticCode,16))
                }
                function Get-PnpDevice {throw 'Unexpected fallback after timeout/access failure'}
                $failure=$null
                try{Get-DriverHardwareIds | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
                [pscustomobject]@{Hex=$hex;Code=$failure.Code;Calls=$script:diagnosticCalls;Details=$failure.Details}
            }
        })
        foreach($result in $protected){
            $expected=if($result.Hex -eq '80041062'){'READ-01'}else{'READ-02'}
            Assert ($result.Code -eq $expected -and $result.Calls -eq 1 -and $result.Details -notmatch 'Fallback:') ($mode+' '+$result.Hex+' cannot trigger a property retry or present-device fallback')
        }
        $final=@(Invoke-ScanQuery {
            function Get-PnpDevice {param([switch]$PresentOnly) throw [Runtime.InteropServices.COMException]::new('Localized final diagnostic',[Convert]::ToInt32('80041088',16))}
            try{Get-DriverHardwareIds | Out-Null}catch{Get-ScanFailureInfo $_}
        })[0]
        Assert ($final.Code -eq 'READ-02' -and $final.Details -match 'Primary:.*Fallback:') ($mode+' final fallback timeout determines the failure while both messages remain available')
        $healthy=@(Invoke-ScanQuery {Get-HwidInstance Healthy -Property ProcessorId})
        Assert ($healthy.Count -eq 1 -and $healthy[0].ProcessorId -ceq '0000123' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' later successful reads clear old recovery notes')
        $report['Report info']=@{Version='3.64';Computer='TEST';Generated='2026-10-30T12:00:00Z'}
        $report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic scan diagnostics' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'PnP hardware IDs'[0].DeviceInstanceId -ceq 'USB\RECOVERED' -and $saved.'Scan timing'[0].Recoveries[0].PrimaryFailure -match 'Localized') ($mode+' saved snapshots retain recovered IDs and scan diagnostics')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' diagnostic export/import does not create ID changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$devices=@(
    [pscustomobject]@{Name='First';DeviceInstanceId=" USB\PAD`0 ";ConfigManagerErrorCode=0;HardwareID=@("`0",42)},
    [pscustomobject]@{Name='Second';DeviceInstanceId='usb\pad';ConfigManagerErrorCode=22;HardwareID=@('MODEL-0001')},
    [pscustomobject]@{Name='No instance';DeviceInstanceId=" `0 ";ConfigManagerErrorCode=0;HardwareID=@("`0",[pscustomobject]@{Name='Invalid model'})},
    [pscustomobject]@{Name='Different instance';DeviceInstanceId='USB\PAD2';ConfigManagerErrorCode=22;HardwareID=@('MODEL-0001')}
)
$issues=@(Get-PnpIssues $devices)
Assert (@($issues | Where-Object Kind -eq 'Duplicate').Count -eq 1 -and @($issues | Where-Object Kind -eq 'Status').Count -eq 1) 'Padded duplicates aggregate their statuses once without hiding a separate disabled node'
Assert (@($issues | Where-Object Kind -eq 'MissingInstance').Count -eq 1) 'Whitespace/NUL-only instance IDs are missing rather than reliable keys'
$duplicate=@($issues | Where-Object Kind -eq 'Duplicate')[0]
Assert ($duplicate.Statuses.Count -eq 2 -and $duplicate.InstanceId -ceq " USB\PAD`0 ") 'Duplicate findings preserve all distinct status observations and the original first ID'
Assert ($devices[0].DeviceInstanceId -ceq " USB\PAD`0 " -and $devices[1].ConfigManagerErrorCode -eq 22) 'Review grouping never rewrites source device rows'
$inventory=[ordered]@{'Report info'=@{};'PnP hardware IDs'=$devices}
$summary=Get-OverviewSummary $inventory @() @()
Assert ($summary.Conflicts -eq 1 -and $summary.DeviceIssues -eq 2) 'Overview totals count one duplicate conflict plus missing-ID and separate disabled findings'
Assert ($summary.Models -eq 2 -and $summary.Nodes -eq 4) 'Overview model coverage excludes invalid/NUL-only lists while retaining the raw row count'
$section=Get-SectionIdentifierInfo 'PnP hardware IDs' $devices
Assert ($section.Found -eq 3 -and $section.Missing -eq 1 -and $section.Text -match '2 with model IDs') 'Scan progress and overview agree on valid model coverage and missing instance IDs'
Assert (@(Get-ExtendedDeviceReview $devices[2]) -contains 'Device instance ID was not supplied') 'Extended review uses the same missing-instance rule'
$distinct=@([pscustomobject]@{Name='Embedded NUL';DeviceInstanceId="USB\A`0B";ConfigManagerErrorCode=0},[pscustomobject]@{Name='No embedded NUL';DeviceInstanceId='USB\AB';ConfigManagerErrorCode=0})
Assert (@(Get-PnpIssues $distinct | Where-Object Kind -eq 'Duplicate').Count -eq 0) 'Ordinal instance grouping does not merge different IDs through culture collation'
Assert (@(Get-PnpIssues @([pscustomobject]@{Name='One';DeviceInstanceId='USB\1';HardwareID=@('SHARED');ConfigManagerErrorCode=0},[pscustomobject]@{Name='Two';DeviceInstanceId='USB\2';HardwareID=@('SHARED');ConfigManagerErrorCode=0})).Count -eq 0) 'Shared model IDs remain valid for different instances'
[Console]::WriteLine("All $script:checks scan-diagnostic checks passed under PowerShell $($PSVersionTable.PSVersion).")
