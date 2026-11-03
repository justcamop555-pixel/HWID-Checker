param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
Microsoft.PowerShell.Core\Get-Command Get-CimInstance | Out-Null
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function New-TestNativeFailure($Code,$Message='Synthetic localized diagnostic'){
    $exception=[Exception]::new($Message)
    $exception | Add-Member NoteProperty StatusCode 0
    $exception | Add-Member NoteProperty NativeErrorCode ([Microsoft.Management.Infrastructure.NativeErrorCode]::$Code)
    return $exception
}
foreach($case in @(@('AccessDenied','READ-01'),@('InvalidNamespace','READ-03'),@('InvalidClass','READ-03'),@('NotSupported','READ-03'),@('InvalidOperationTimeout','READ-02'),@('Failed','READ-05'),@('InvalidParameter','READ-05'))){
    $exception=New-TestNativeFailure $case[0]
    Assert ((Get-ScanFailureInfo $exception).Code -eq $case[1]) ($case[0]+' native CIM code is not masked by a zero StatusCode')
    $wrapped=[Management.Automation.ErrorRecord]::new([Exception]::new('Synthetic outer diagnostic',$exception),'Synthetic.NativeFailure',0,$null)
    $info=Get-ScanFailureInfo $wrapped
    Assert ($info.Code -eq $case[1] -and $info.Details -ceq 'Synthetic outer diagnostic') ($case[0]+' remains classified through wrappers without replacing original detail')
}
foreach($name in @('NoSuchProperty','InvalidQuery')){
    $exception=New-TestNativeFailure $name
    Assert (Test-ProjectionReadFailure ([Management.Automation.ErrorRecord]::new($exception,'Synthetic.Projection',0,$null))) ($name+' permits a bounded available-property retry without English text')
}
foreach($name in @('AccessDenied','InvalidOperationTimeout')){
    $exception=New-TestNativeFailure $name 'Invalid query mentioned in an outer diagnostic'
    Assert (-not (Test-ProjectionReadFailure ([Management.Automation.ErrorRecord]::new($exception,'Synthetic.Blocked',0,$null)))) ($name+' cannot trigger a property retry even when diagnostic text mentions an invalid query')
}
$exception=New-TestNativeFailure InvalidQuery
$exception | Add-Member NoteProperty ErrorCode 'AccessDenied'
Assert (-not (Test-ProjectionReadFailure ([Management.Automation.ErrorRecord]::new($exception,'Synthetic.MixedStatus',0,$null)))) 'A permission status in another supported field still prevents a property retry'
$exception=[Exception]::new('Synthetic unknown native code');$exception | Add-Member NoteProperty NativeErrorCode ([enum]::ToObject([Microsoft.Management.Infrastructure.NativeErrorCode],999))
Assert ((Get-ScanFailureInfo $exception).Code -eq 'READ-05') 'An unknown native code remains a generic read failure'
$exception=[Exception]::new('Synthetic malformed native status');$exception | Add-Member NoteProperty NativeErrorCode @('AccessDenied','InvalidQuery')
Assert ((Get-ScanFailureInfo $exception).Code -eq 'READ-05' -and -not (Test-ProjectionReadFailure ([Management.Automation.ErrorRecord]::new($exception,'Synthetic.Malformed',0,$null)))) 'An array of status names cannot masquerade as a scalar exception status'
$exception=[Exception]::new('Synthetic inaccessible status');$exception | Add-Member ScriptProperty NativeErrorCode {throw 'Synthetic status getter failure'}
Assert ((Get-ScanFailureInfo $exception).Code -eq 'READ-05') 'An unreadable optional status property cannot crash error classification'
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    $script:readerCalls++
    $code=$null
    if($script:nativeMode -in @('NoSuchProperty','InvalidQuery')){if($Property){$code=$script:nativeMode}}
    elseif($script:nativeMode -in @('AccessDenied','InvalidOperationTimeout','InvalidClass')){$code=$script:nativeMode}
    if($code){
        [pscustomobject]@{DeviceID='PARTIAL';ProcessorId='MUST-NOT-LEAK'}
        $exception=[Exception]::new('Synthetic localized provider diagnostic')
        $exception | Add-Member NoteProperty StatusCode 0
        $exception | Add-Member NoteProperty NativeErrorCode ([Microsoft.Management.Infrastructure.NativeErrorCode]::$code)
        throw $exception
    }
    [pscustomobject]@{DeviceID='CPU0';Name='Synthetic CPU';ProcessorId='CPU-000123';SerialNumber='000123';Namespace=$Namespace;Filter=$Filter;Timeout=$OperationTimeoutSec;Enabled=$false;Count=0}
}
function Get-PnpDevice {param([switch]$PresentOnly) if(-not $PresentOnly){throw 'Unexpected widened scope'};[pscustomobject]@{Name='Synthetic recovered device';PNPDeviceID='USB\RECOVERED';PNPClass='USB';Present=$true;HardwareID=@('MODEL');ConfigManagerErrorCode=0}}
$root=Join-Path $PSScriptRoot ('test-output-native-cim-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        foreach($code in @('NoSuchProperty','InvalidQuery')){
            $query=[scriptblock]::Create('$script:nativeMode="'+$code+'";$script:readerCalls=0;$rows=@(Get-HwidInstance Synthetic -Namespace root/test -Property ProcessorId -Filter "Present=True" -OperationTimeoutSec 37);[pscustomobject]@{Rows=$rows;Calls=$script:readerCalls}')
            $result=@(Invoke-ScanQuery $query)[0]
            Assert ($result.Calls -eq 2 -and $result.Rows.Count -eq 1 -and $result.Rows[0].ProcessorId -ceq 'CPU-000123') ($mode+' '+$code+' retries once and rejects partial primary output')
            Assert ($result.Rows[0].Namespace -ceq 'root/test' -and $result.Rows[0].Filter -ceq 'Present=True' -and $result.Rows[0].Timeout -eq 37 -and -not $result.Rows[0].Enabled -and $result.Rows[0].Count -eq 0) ($mode+' '+$code+' preserves namespace, device filter, timeout and scalar data')
            Assert ($script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryRecoveries[0].PrimaryFailure -ceq 'Synthetic localized provider diagnostic') ($mode+' '+$code+' records the compatible read and original diagnostic')
        }
        foreach($case in @(@('AccessDenied','READ-01'),@('InvalidOperationTimeout','READ-02'))){
            $query=[scriptblock]::Create('$script:nativeMode="'+$case[0]+'";$script:readerCalls=0;Get-HwidInstance Synthetic -Property ProcessorId')
            $rows=@();$failure=$null
            try{$rows=@(Invoke-ScanQuery $query)}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($rows.Count -eq 0 -and $failure.Code -eq $case[1] -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' '+$case[0]+' rejects partial data without claiming a recovery')
            $calls=@(Invoke-ScanQuery {$script:readerCalls})[0]
            Assert ($calls -eq 1) ($mode+' '+$case[0]+' makes no repeated provider call')
        }
        $fallback=@(Invoke-ScanQuery {$script:nativeMode='InvalidClass';Get-DriverHardwareIds})
        Assert ($fallback.Count -eq 1 -and $fallback[0].DeviceInstanceId -ceq 'USB\RECOVERED' -and $fallback[0].CollectionSource -match 'present-only fallback') ($mode+' native InvalidClass enables the supported present-device fallback')
        $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
        Section CPU {$script:nativeMode='AccessDenied';Get-HwidInstance Win32_Processor -Property ProcessorId | Select-Object DeviceID,ProcessorId}
        Assert ($report.CPU.FailureCode -eq 'READ-01' -and $scanTimings[0].Status -eq 'UNAVAILABLE' -and $scanTimings[0].FailureCode -eq 'READ-01' -and $warnings.Count -eq 1) ($mode+' denied sections show Access blocked rather than a generic failure')
        $unread=@(Get-ReviewReadFailures $report $warnings)
        Assert ($unread.Count -eq 1 -and $unread[0].Code -eq 'READ-01') ($mode+' warning review preserves the typed native error classification')
        $report['Report info']=@{Version='3.82';Computer='TEST';Generated='2026-11-02T12:00:00-05:00'};$report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem ((Get-PlainRecords $report.CPU) -join [Environment]::NewLine) ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.CPU.FailureCode -eq 'READ-01' -and $saved.'Scan timing'[0].FailureCode -eq 'READ-01' -and [IO.File]::ReadAllText($stem+'.txt') -match 'READ-01') ($mode+' TXT and JSON retain the corrected read code')
        $old=@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-OLD'})};$comparison=Compare-Inventories $old $saved
        Assert ($comparison.Changes.Count -eq 0 -and $comparison.SkippedSections -contains 'CPU') ($mode+' a native access denial cannot appear as an identifier removal')
        Section CPU {$script:nativeMode='NoSuchProperty';Get-HwidInstance Win32_Processor -Property ProcessorId | Select-Object DeviceID,ProcessorId}
        Assert ($report.CPU[0].ProcessorId -ceq 'CPU-000123' -and $scanTimings[-1].Status -eq 'READ' -and $scanTimings[-1].Recoveries.Count -eq 1) ($mode+' a later optional-field recovery remains readable')
        Section CPU {$script:nativeMode='Healthy';Get-HwidInstance Win32_Processor -Property ProcessorId | Select-Object DeviceID,ProcessorId}
        Assert ($scanTimings[-1].Status -eq 'READ' -and $scanTimings[-1].Recoveries.Count -eq 0 -and -not $scanTimings[-1].FailureCode) ($mode+' a later healthy query starts with fresh native error and recovery state')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks native-CIM-error checks passed under PowerShell $($PSVersionTable.PSVersion).")
