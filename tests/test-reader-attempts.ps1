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
function Get-NetAdapter {
    param([switch]$IncludeHidden)
    [pscustomobject]@{Name='Incomplete primary';InterfaceGuid='PARTIAL';MacAddress='FFFFFFFFFFFF'}
    Write-Error 'Primary adapter enumeration incomplete' -Category ReadError -ErrorAction Continue
}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    switch($ClassName){
        'PartialProjection' {
            if($Property){
                [pscustomobject]@{SerialNumber='PARTIAL';DeviceID='CPU0'}
                Write-Error -Exception ([Runtime.InteropServices.COMException]::new('Localized invalid property',[Convert]::ToInt32('80041031',16))) -ErrorAction Continue
                return
            }
            [pscustomobject]@{SerialNumber='0000123';DeviceID='CPU0';ProcessorId='0000123';Namespace=$Namespace;Filter=$Filter;Timeout=$OperationTimeoutSec;Enabled=$false;Count=0}
        }
        'Healthy' {[pscustomobject]@{SerialNumber='0000123';DeviceID='CPU0'}}
        'MSFT_NetAdapter' {[pscustomobject]@{Name='Recovered adapter';InterfaceGuid='NIC-1';NetworkAddresses=@('001122334455');InterfaceOperationalStatus=1;HardwareInterface=$true}}
        'Win32_PnPEntity' {
            if($Filter){throw 'Extended fallback must stay unfiltered'}
            [pscustomobject]@{Name='Present fixture';PNPDeviceID='USB\PRESENT';Present=$true;HardwareID=@('MODEL-LIVE');ConfigManagerErrorCode=0}
            [pscustomobject]@{Name='Remembered fixture';PNPDeviceID='USB\REMEMBERED';Present=$false;HardwareID=@('MODEL-OLD');ConfigManagerErrorCode=45}
        }
        default {throw ('Unexpected provider query: '+$ClassName)}
    }
}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    [pscustomobject]@{Name='Incomplete primary';PNPDeviceID='USB\PARTIAL';Present=$true}
    Write-Error 'Primary device enumeration incomplete' -Category ReadError -ErrorAction Continue
}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return $null}
$root=Join-Path $PSScriptRoot ('test-output-reader-attempts-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        $failure=$null;$rows=@()
        try{$rows=@(Invoke-ScanQuery {Get-HwidInstance PartialProjection -Property SerialNumber,Optional -Namespace 'root/test' -Filter 'Present=True' -OperationTimeoutSec 30})}catch{$failure=$_}
        Assert ($null -eq $failure -and $rows.Count -eq 1 -and $rows[0].SerialNumber -ceq '0000123') ($mode+' an uncaught non-terminating property error recovers without leaking incomplete rows')
        Assert ($rows[0].Namespace -ceq 'root/test' -and $rows[0].Filter -ceq 'Present=True' -and $rows[0].Timeout -eq 30 -and $rows[0].Enabled -eq $false -and $rows[0].Count -eq 0) ($mode+' recovered attempts preserve device selection, timeout, exact IDs and false/zero metadata')
        Assert ($script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryRecoveries[0].PrimaryFailure -match 'Localized') ($mode+' handled reader errors become recovery diagnostics rather than an escaped query error')
        Section 'CPU' {Get-HwidInstance PartialProjection -Property ProcessorId | Select-Object DeviceID,ProcessorId}
        Assert ($warnings.Count -eq 0 -and $report.CPU[0].ProcessorId -ceq '0000123' -and $scanTimings[-1].Recoveries.Count -eq 1) ($mode+' the recovered section is readable with preserved scan timing')
        Section 'Network adapters' {Get-NetworkIdentifiers}
        Assert ($warnings.Count -eq 0 -and $report.'Network adapters'.Count -eq 1 -and $report.'Network adapters'[0].InterfaceGuid -ceq 'NIC-1') ($mode+' partial network enumeration triggers a clean compatibility fallback')
        Assert ($report.'Network adapters'[0].CollectionSource -eq 'MSFT_NetAdapter CIM fallback' -and $report.'Network adapters'[0].MacAddress -ceq '001122334455') ($mode+' network fallback retains its actual reader and current address')
        $catalog=@(Invoke-ScanQuery {Get-ExtendedDeviceInventory})[0]
        Assert ($catalog.Devices.Count -eq 2 -and @($catalog.Devices | Where-Object DeviceInstanceId -eq 'USB\PARTIAL').Count -eq 0) ($mode+' partial extended enumeration discards its rows before falling back')
        Assert (@($catalog.Devices | Where-Object {$_.Present -eq $true}).Count -eq 1 -and @($catalog.Devices | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count -eq 1) ($mode+' extended fallback preserves present and remembered records')
        Assert ($catalog.Info.Source -match 'unfiltered fallback' -and $catalog.Info.FallbackReason -match 'enumeration incomplete') ($mode+' extended recovery retains the primary error and selected source')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {
                param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
                [pscustomobject]@{Name='Incomplete fallback';InterfaceGuid='PARTIAL'}
                if($ClassName -eq 'MSFT_NetAdapter'){Write-Error 'Invalid class in modern fallback' -ErrorAction Continue}
                else{Write-Error -Exception ([TimeoutException]::new('Localized final timeout')) -ErrorAction Continue}
            }
            Get-NetworkIdentifiers
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-02' -and $partial.Count -eq 0 -and $failure.Details -match 'Primary:.*CIM fallback:.*Fallback:') ($mode+' all failed network attempts retain diagnostics and classify the final timeout')
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {
            function Get-CimInstance {
                param($ClassName,$Property)
                [pscustomobject]@{SerialNumber='PARTIAL'}
                if($Property){Write-Error 'Invalid property in primary' -ErrorAction Continue}
                else{Write-Error -Exception ([UnauthorizedAccessException]::new('Localized final denial')) -ErrorAction Continue}
            }
            Get-HwidInstance Fixture -Property SerialNumber
        })}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $partial.Count -eq 0 -and $failure.Details -match 'Requested fields failed:.*Compatible read failed:') ($mode+' a partial failed property retry cannot become successful records')
        $failure=$null
        try{Invoke-ScanQuery {
            function Get-CimInstance {param($ClassName,$Property) [pscustomobject]@{SerialNumber='PARTIAL'};Write-Error -Exception ([TimeoutException]::new('Localized timeout')) -ErrorAction Continue}
            Get-HwidInstance Fixture -Property SerialNumber
        } | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-02' -and $failure.Details -notmatch 'Compatible read failed') ($mode+' a non-terminating timeout is not retried as an invalid-property failure')
        $legacy=@(Invoke-ScanQuery {
            function Get-Command {param($Name,$ErrorAction) if($Name -eq 'Get-CimInstance'){return $null};Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue}
            function Get-WmiObject {
                param($Class,$Namespace,$Property,$Filter)
                if($Property){[pscustomobject]@{SerialNumber='PARTIAL'};Write-Error 'Invalid property in legacy reader' -ErrorAction Continue;return}
                [pscustomobject]@{SerialNumber='0000042';Namespace=$Namespace;Filter=$Filter}
            }
            Get-HwidInstance LegacyFixture -Property SerialNumber,Optional -Namespace 'root/legacy' -Filter 'Present=True'
        })
        Assert ($legacy.Count -eq 1 -and $legacy[0].SerialNumber -ceq '0000042') ($mode+' legacy WMI also discards partial errors before a successful property retry')
        Assert ($legacy[0].Namespace -ceq 'root/legacy' -and $legacy[0].Filter -ceq 'Present=True' -and $script:lastQueryRecoveries.Count -eq 1) ($mode+' legacy WMI recovery preserves selection and exposes one recovery note')
        $healthy=@(Invoke-ScanQuery {Get-HwidInstance Healthy -Property SerialNumber})
        Assert ($healthy.Count -eq 1 -and $healthy[0].SerialNumber -ceq '0000123' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' a later successful query does not inherit old reader errors or recovery notes')
        $report['Report info']=@{Version='3.60';Computer='TEST';Generated='2026-10-29T12:00:00Z'}
        $report['Scan timing']=@($scanTimings.ToArray());$report['Extended device inventory']=$catalog.Devices;$report['Extended scan info']=$catalog.Info
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic reader recovery' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.CPU[0].ProcessorId -ceq '0000123' -and $saved.'Scan timing'[0].Recoveries[0].PrimaryFailure -match 'Localized' -and $saved.'Extended scan info'.FallbackReason -match 'enumeration incomplete') ($mode+' saved reports retain recovered IDs and reader diagnostics')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' exporting recovered records does not invent identifier differences')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks reader-attempt checks passed under PowerShell $($PSVersionTable.PSVersion).")
