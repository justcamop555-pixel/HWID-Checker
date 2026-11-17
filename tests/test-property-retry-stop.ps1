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
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        foreach($kind in @('access','timeout','provider')){
            $query=[scriptblock]::Create(@'
$script:attempts=New-Object 'System.Collections.Generic.List[string]'
function Get-PnpDeviceProperty {
    [CmdletBinding()]param([string[]]$InstanceId,[string[]]$KeyName,[int]$ThrottleLimit)
    $script:attempts.Add(($InstanceId -join ','))
    if($InstanceId.Count -gt 1){
        if($InstanceId[0] -eq 'USB\NODE0'){throw 'A node disappeared during this batch.'}
        foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('Later-0000')}}
        return
    }
    if($InstanceId[0] -eq 'USB\NODE0'){
        [pscustomobject]@{InstanceId=$InstanceId[0];KeyName='DEVPKEY_Device_HardwareIds';Data=@('Exact-000123')}
        return
    }
    $exception=switch('KIND'){
        'access' {[UnauthorizedAccessException]::new('Synthetic localized denial')}
        'timeout' {[TimeoutException]::new('Synthetic localized wait failure')}
        'provider' {[NotSupportedException]::new('Synthetic localized provider failure')}
    }
    $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new($exception,'Synthetic.ReadFailure',[Management.Automation.ErrorCategory]::NotSpecified,$InstanceId[0]))
}
$ids=@(0..39|ForEach-Object {'USB\NODE'+$_})
$read=Read-DevicePropertyBatches $ids @('DEVPKEY_Device_HardwareIds')
[pscustomobject]@{Read=$read;Attempts=@($script:attempts.ToArray())}
'@.Replace('KIND',$kind))
            $result=@(Invoke-ScanQuery $query)[0]
            Assert ($result.Read.RetriedDevices -eq 2 -and $result.Attempts.Count -eq 4) ($mode+' '+$kind+' non-terminating failures stop the per-device recovery loop')
            Assert ($result.Read.Rows.Count -eq 9 -and $result.Read.Rows[0].Data[0] -ceq 'Exact-000123') ($mode+' '+$kind+' retains accepted IDs and reads the later independent batch')
            Assert ($result.Read.Errors.Count -gt 0 -and $result.Read.NodesRequested -eq 40 -and $result.Read.NodesWithoutRows -eq 31) ($mode+' '+$kind+' keeps failure diagnostics and accurate missing-property coverage')
        }
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine(('All {0} property retry stop checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
