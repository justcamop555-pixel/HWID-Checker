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
function Get-CimInstance {
    param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
    throw [Runtime.InteropServices.COMException]::new('Localized unsupported present query',[Convert]::ToInt32('80041017',16))
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if(-not $PresentOnly){throw 'Device scope was widened'}
    [pscustomobject]@{FriendlyName='Fallback device';Class='USB';InstanceId='USB\LIVE';HardwareID=@('MODEL-0001');CompatibleID=@('COMPAT-0001');ConfigManagerErrorCode=0}
    [pscustomobject]@{FriendlyName='Disconnected';Class='USB';InstanceId='USB\OLD';Present=$false;HardwareID=@('OLD-MODEL');ConfigManagerErrorCode=45}
}
$script:scanQueryWorker=$null;$failure=$null;$rows=@()
try{$rows=@(Get-DriverHardwareIds)}catch{$failure=$_}
Assert ($null -eq $failure -and $rows.Count -eq 1 -and $rows[0].DeviceInstanceId -ceq 'USB\LIVE') 'An unsupported Win32 present query recovers through a present-only reader'
$root=Join-Path $PSScriptRoot ('test-output-pnp-fallback-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        Section 'PnP hardware IDs' {Get-DriverHardwareIds}
        $rows=$report.'PnP hardware IDs'
        Assert ($warnings.Count -eq 0 -and $rows.Count -eq 1 -and $rows[0].Present -eq $true) ($mode+' successful fallback retains present scope and excludes explicit disconnected rows')
        Assert ($rows[0].Name -ceq 'Fallback device' -and $rows[0].PNPClass -ceq 'USB' -and $rows[0].HardwareID[0] -ceq 'MODEL-0001' -and $rows[0].CompatibleID[0] -ceq 'COMPAT-0001') ($mode+' fallback maps device aliases without changing identifier text')
        Assert ($rows[0].CollectionSource -match 'present-only fallback' -and $scanTimings[-1].Recoveries.Count -eq 1 -and $scanTimings[-1].Summary -match 'fallback reader') ($mode+' scan output and timing identify the reader used and preserve the original failure')
        $report['Report info']=@{Version='3.59';Computer='TEST';Generated='2026-10-29T12:00:00Z'}
        $report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic fallback snapshot' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'PnP hardware IDs'[0].DeviceInstanceId -ceq 'USB\LIVE' -and $saved.'Scan timing'[0].Recoveries[0].PrimaryFailure -match 'Localized') ($mode+' saved snapshots retain fallback source and diagnostics')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) throw [UnauthorizedAccessException]::new('Localized access failure')}
            function Get-PnpDevice {throw 'Fallback must not run for access failures'}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $failure.Details -notmatch 'Fallback must not run') ($mode+' access failures remain explicit without an extra reader attempt')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) throw [TimeoutException]::new('Localized timeout')}
            function Get-PnpDevice {throw 'Fallback must not run for timeouts'}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-02' -and $failure.Details -notmatch 'Fallback must not run') ($mode+' timeouts remain bounded to the failed reader')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) throw 'Invalid class in primary'}
            function Get-PnpDevice {param([switch]$PresentOnly) throw [UnauthorizedAccessException]::new('Localized fallback denied')}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' a failed fallback keeps both diagnostics and classifies the final failure')
        $empty=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) return $null}
            function Get-PnpDevice {param([switch]$PresentOnly) if(-not $PresentOnly){throw 'Scope widened'};[pscustomobject]@{InstanceId='USB\RECOVERED';FriendlyName='Recovered';Present=$true;ConfigManagerErrorCode=0}}
            Get-DriverHardwareIds
        })
        Assert ($empty.Count -eq 1 -and $empty[0].DeviceInstanceId -eq 'USB\RECOVERED') ($mode+' an empty primary reader can recover real present records')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) return $null}
            function Get-PnpDevice {param([switch]$PresentOnly) return $null}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-04') ($mode+' two empty readers remain no records rather than a fabricated successful scan')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) throw 'Invalid class in primary'}
            function Get-Command {param($Name,$ErrorAction) if($Name -eq 'Get-PnpDevice'){return $null};Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-03' -and $failure.Details -match 'Primary:.*Fallback:') ($mode+' a missing fallback command preserves provider-unavailable guidance and both diagnostics')
        $healthy=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) if($Filter -ne 'Present = True'){throw 'Scope changed'};[pscustomobject]@{Name='Healthy primary';PNPDeviceID='PCI\PRIMARY';HardwareID=@('MODEL');ConfigManagerErrorCode=0}}
            function Get-PnpDevice {throw 'Healthy primary must not trigger fallback'}
            Get-DriverHardwareIds
        })
        Assert ($healthy.Count -eq 1 -and $healthy[0].DeviceInstanceId -ceq 'PCI\PRIMARY' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' healthy primary results do not invoke fallback or inherit old recovery notes')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) Write-Error 'Localized primary failure' -Category PermissionDenied -ErrorAction Continue}
            function Get-PnpDevice {throw 'Fallback must not run after an uncaught access error'}
            Get-DriverHardwareIds
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $failure.Details -notmatch 'Fallback must not run') ($mode+' an uncaught non-terminating access error does not trigger a second reader')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property,$Filter) throw 'Invalid class'}
            function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{InstanceId='USB\PARTIAL'};Write-Error 'Localized fallback error' -Category PermissionDenied -ErrorAction Continue}
            Get-DriverHardwareIds
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $partial.Count -eq 0) ($mode+' fallback rows emitted before an uncaught error cannot become a successful inventory')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
Assert ((Get-ScanFailureInfo ([NotSupportedException]::new('Localized unsupported reader'))).Code -eq 'READ-03') 'Typed unsupported-reader failures are classified without English message matching'
Assert ((Get-ScanFailureInfo ([Management.Automation.CommandNotFoundException]::new('Localized missing reader'))).Code -eq 'READ-03') 'Typed missing-command failures are provider unavailable on localized Windows'
[Console]::WriteLine("All $script:checks PnP-fallback checks passed under PowerShell $($PSVersionTable.PSVersion).")
