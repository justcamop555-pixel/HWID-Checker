$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat')) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$checks=0
function Assert($value,$name){if(-not $value){throw ('FAILED: '+$name)};$script:checks++;[Console]::WriteLine('PASS: '+$name)}
function Get-CimInstance {
 param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
 [pscustomobject]@{Name=$null;PNPDeviceID='USB\NEEDS-ID';PNPClass='USB';Present=$true;HardwareID=@();CompatibleID=@();ConfigManagerErrorCode=28}
 [pscustomobject]@{Name='Healthy device';PNPDeviceID='USB\HEALTHY';PNPClass='USB';Present=$true;HardwareID=@('Exact-0000');CompatibleID=@();ConfigManagerErrorCode=0}
}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ThrottleLimit)
 if(@($InstanceId).Count -ne 1 -or $InstanceId[0] -cne 'USB\NEEDS-ID' -or $ThrottleLimit -ne 1){throw 'Unexpected identification scope'}
 [pscustomobject]@{InstanceId='usb\needs-id';KeyName='DEVPKEY_Device_HardwareIds';Data=@('USB\VID_0001&PID_0002', 'Exact-0001')}
 [pscustomobject]@{InstanceId='USB\NEEDS-ID';KeyName='DEVPKEY_Device_CompatibleIds';Data=@('USB\Class_01')}
 [pscustomobject]@{InstanceId='USB\NEEDS-ID';KeyName='DEVPKEY_Device_FriendlyName';Data='Recovered device name'}
 [pscustomobject]@{InstanceId='USB\UNREQUESTED';KeyName='DEVPKEY_Device_HardwareIds';Data=@('DO-NOT-ATTACH')}
}
foreach($mode in @('Direct','Worker')){
 $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
 try{
  $rows=@(Invoke-ScanQuery {Get-DriverHardwareIds})
  $row=@($rows|Where-Object DeviceInstanceId -ceq 'USB\NEEDS-ID')[0]
  $good=@($rows|Where-Object DeviceInstanceId -ceq 'USB\HEALTHY')[0]
  Assert ($rows.Count -eq 2 -and $row.Name -ceq 'Recovered device name') ($mode+' preserves all present nodes and recovers a missing readable name')
  Assert ($row.HardwareID.Count -eq 2 -and $row.HardwareID[0] -ceq 'USB\VID_0001&PID_0002' -and $row.HardwareID[1] -ceq 'Exact-0001') ($mode+' fills missing model IDs with exact property values')
  Assert ($row.CompatibleID[0] -ceq 'USB\Class_01' -and $row.HardwareIDSource -ceq 'Device properties') ($mode+' labels the recovered identifier source')
  Assert ($good.Name -ceq 'Healthy device' -and $good.HardwareID[0] -ceq 'Exact-0000' -and $null -eq $good.IdentificationReadStatus) ($mode+' does not requery or alter complete device identification')
  Assert ($row.ConfigManagerErrorCode -eq 28 -and @((Get-PnpIssues $rows)|Where-Object {$_.Kind -eq 'Status' -and $_.Code -eq 28}).Count -eq 1) ($mode+' recovered names and IDs cannot erase a reported driver problem')
  $failed=@(Invoke-ScanQuery {
   function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit) throw [UnauthorizedAccessException]::new('Synthetic optional-property denial')}
   Get-DriverHardwareIds
  })
  $failedRow=@($failed|Where-Object DeviceInstanceId -ceq 'USB\NEEDS-ID')[0]
  Assert ($failed.Count -eq 2 -and $failedRow.HardwareID.Count -eq 0 -and $failedRow.IdentificationReadStatus -like '*incomplete*' -and $failedRow.IdentificationReadErrors.Count -gt 0) ($mode+' optional property failures keep the primary device records and explain the limitation')
  $mixed=@(Invoke-ScanQuery {
   function Get-PnpDeviceProperty {
    param($InstanceId,$KeyName,$ThrottleLimit)
    [pscustomobject]@{InstanceId='USB\NEEDS-ID';KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-A',42)}
    [pscustomobject]@{InstanceId='USB\NEEDS-ID';KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-B')}
    [pscustomobject]@{InstanceId='USB\NEEDS-ID';KeyName='DEVPKEY_Device_FriendlyName';Data=@('not','scalar')}
   }
   Get-DriverHardwareIds
  })
  $mixedRow=@($mixed|Where-Object DeviceInstanceId -ceq 'USB\NEEDS-ID')[0]
  Assert ($mixedRow.HardwareID.Count -eq 2 -and $mixedRow.HardwareIDReadStatus -like 'Invalid*' -and $mixedRow.HardwareIDPropertyConflict -eq $true) ($mode+' malformed or conflicting readings remain explicit beside usable strings')
  Assert ($null -eq $mixedRow.Name -and @((Get-PnpIssues $mixed)|Where-Object Kind -eq 'IdSourceConflict').Count -eq 1) ($mode+' arrays cannot become a readable device name and conflicts reach Review')
  $plain=@(Invoke-ScanQuery {
   function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit)}
   Get-DriverHardwareIds
  })
  $plainRow=@($plain|Where-Object DeviceInstanceId -ceq 'USB\NEEDS-ID')[0]
  Assert ($plainRow.IdentificationReadStatus -ceq 'No additional identification supplied by Windows' -and $plainRow.HardwareID.Count -eq 0) ($mode+' an empty optional lookup does not invent identifiers')
 }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $checks device-identification checks passed.")
