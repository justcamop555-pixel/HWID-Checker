param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$checks=0
function Assert($value,$message){if(-not $value){throw ('FAILED: '+$message)};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
function Invoke-PresentFixture([string]$Case){
    $query=[scriptblock]::Create(@'
$script:primaryCalls=0;$script:fallbackCalls=0;$script:primaryFilter=$null;$script:primaryTimeout=0;$script:presentOnly=$false
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    $script:primaryCalls++;$script:primaryFilter=$Filter;$script:primaryTimeout=$OperationTimeoutSec
    if($ClassName -ne 'Win32_PnPEntity'){throw 'Unexpected hardware reader'}
    switch('FIXTURE_CASE'){
        'Access' {throw [UnauthorizedAccessException]::new('Localized primary denial')}
        'Timeout' {throw [TimeoutException]::new('Localized primary wait failure')}
        'Healthy' {
            [pscustomobject]@{Name='Healthy primary';PNPClass='PCI';PNPDeviceID='PCI\PRIMARY-000123';HardwareID=@('PRIMARY-MODEL-0000');Present=$true;ConfigManagerErrorCode=0}
            return
        }
    }
    [pscustomobject]@{Name='Partial primary';PNPClass='PCI';PNPDeviceID='PCI\DO-NOT-MIX';HardwareID=@('PRIMARY-PARTIAL');Present=$true;ConfigManagerErrorCode=0}
    [pscustomobject]@{Name='Malformed primary';PNPDeviceID=@('INVALID','PRIMARY-KEY');Present=$true}
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    $script:fallbackCalls++;$script:presentOnly=[bool]$PresentOnly
    if(-not $PresentOnly){throw 'Fallback widened the present-device scope'}
    if('FIXTURE_CASE' -eq 'FallbackDenied'){throw [UnauthorizedAccessException]::new('Localized final denial')}
    [pscustomobject]@{FriendlyName='Recovered OEM device';Class='USB';InstanceId='USB\VID_0001&PID_0002\0000123';HardwareID=@('MODEL-0001','MODEL-0000');CompatibleID=@('COMPAT-0000');Present=$true;ConfigManagerErrorCode=28}
    [pscustomobject]@{FriendlyName='Remembered device';Class='USB';InstanceId='USB\DO-NOT-INCLUDE';HardwareID=@('OLD-MODEL');Present=$false;ConfigManagerErrorCode=45}
    if('FIXTURE_CASE' -eq 'BothMalformed'){
        [pscustomobject]@{Name='Malformed fallback';InstanceId=@('INVALID','FALLBACK-KEY');Present=$true}
    }
}
$rows=@();$failure=$null
try{$rows=@(Get-DriverHardwareIds)}catch{$failure=$_}
[pscustomobject]@{Rows=$rows;Failure=$failure;PrimaryCalls=$script:primaryCalls;FallbackCalls=$script:fallbackCalls;PrimaryFilter=$script:primaryFilter;PrimaryTimeout=$script:primaryTimeout;PresentOnly=$script:presentOnly}
'@.Replace('FIXTURE_CASE',$Case))
    return @(Invoke-ScanQuery $query)[0]
}
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $result=Invoke-PresentFixture 'Malformed'
        Assert ($null -eq $result.Failure -and $result.Rows.Count -eq 1) ($mode+' malformed primary PnP records recover through a fully validated alternative reader')
        Assert ($result.PrimaryCalls -eq 1 -and $result.FallbackCalls -eq 1 -and $result.PrimaryFilter -ceq 'Present = True' -and $result.PrimaryTimeout -eq 20 -and $result.PresentOnly) ($mode+' recovery remains bounded and preserves present-only scope and primary timeout')
        $row=$result.Rows[0]
        Assert ($row.DeviceInstanceId -ceq 'USB\VID_0001&PID_0002\0000123' -and $row.HardwareID[0] -ceq 'MODEL-0001' -and $row.HardwareID[1] -ceq 'MODEL-0000' -and $row.CompatibleID[0] -ceq 'COMPAT-0000') ($mode+' recovered instance and model identifiers retain exact text, order and leading zeros')
        Assert ($row.Name -ceq 'Recovered OEM device' -and $row.PNPClass -ceq 'USB' -and $row.InstanceIdSource -ceq 'InstanceId' -and $row.CollectionSource -ceq 'Get-PnpDevice present-only fallback') ($mode+' recovered labels and original instance alias retain their source')
        Assert ($row.Present -eq $true -and @($result.Rows|Where-Object DeviceInstanceId -match 'DO-NOT').Count -eq 0) ($mode+' disconnected fallback records and incomplete primary rows cannot leak into the accepted inventory')
        Assert ($script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryRecoveries[0].PrimaryFailure -match 'invalid device key: PNPDeviceID' -and $script:lastQueryRecoveries[0].Method -ceq 'Get-PnpDevice present-only fallback') ($mode+' a successful recovery retains the malformed-primary diagnostic')
        Assert (@(Get-PnpIssues $result.Rows|Where-Object {$_.Kind -eq 'Status' -and $_.Code -eq 28}).Count -eq 1) ($mode+' recovered identification cannot erase a real Windows driver-status finding')

        $invalid=Invoke-PresentFixture 'BothMalformed'
        $failure=Get-ScanFailureInfo $invalid.Failure
        Assert ($failure.Code -ceq 'READ-06' -and $invalid.Rows.Count -eq 0 -and $invalid.PrimaryCalls -eq 1 -and $invalid.FallbackCalls -eq 1) ($mode+' malformed alternative records remain invalid data rather than a successful partial inventory')
        Assert ($failure.Details -match 'Primary:.*invalid device key: PNPDeviceID.*Fallback:.*invalid device key: InstanceId') ($mode+' failed validation in both readers retains both original diagnostics')

        $denied=Invoke-PresentFixture 'FallbackDenied'
        $failure=Get-ScanFailureInfo $denied.Failure
        Assert ($failure.Code -ceq 'READ-01' -and $denied.Rows.Count -eq 0 -and $denied.FallbackCalls -eq 1 -and $failure.Details -match 'Primary:.*invalid device key: PNPDeviceID.*Fallback:.*Localized final denial') ($mode+' a typed final-reader failure keeps its real code and both reader messages')
        foreach($case in @(@('Access','READ-01'),@('Timeout','READ-02'))){
            $blocked=Invoke-PresentFixture $case[0]
            $failure=Get-ScanFailureInfo $blocked.Failure
            Assert ($failure.Code -ceq $case[1] -and $blocked.FallbackCalls -eq 0 -and $blocked.PrimaryCalls -eq 1 -and $blocked.Rows.Count -eq 0) ($mode+' '+$case[0]+' is not retried as a malformed-data recovery')
        }
        $healthy=Invoke-PresentFixture 'Healthy'
        Assert ($null -eq $healthy.Failure -and $healthy.Rows.Count -eq 1 -and $healthy.Rows[0].DeviceInstanceId -ceq 'PCI\PRIMARY-000123' -and $healthy.FallbackCalls -eq 0 -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' a later healthy primary is accepted without extra calls or stale recovery details')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine(('All {0} present-device recovery checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
