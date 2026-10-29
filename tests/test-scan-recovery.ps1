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
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    switch($ClassName){
        'Access' {throw [UnauthorizedAccessException]::new('Access denied; invalid query context')}
        'Timeout' {throw [TimeoutException]::new('Invalid query timed out')}
        'MissingClass' {throw [Runtime.InteropServices.COMException]::new('Localized missing class',[Convert]::ToInt32('80041010',16))}
        'RetryFails' {if(-not $Property){throw [UnauthorizedAccessException]::new('Localized denied')}}
        'BadFilter' {throw [Runtime.InteropServices.COMException]::new('Localized invalid query',[Convert]::ToInt32('80041017',16))}
        'Empty' {return}
        'Healthy' {break}
        default {
            if($Property){
                [pscustomobject]@{SerialNumber='PARTIAL-MUST-NOT-LEAK'}
                throw [Runtime.InteropServices.COMException]::new('Localized projected property failure',[Convert]::ToInt32('80041017',16))
            }
        }
    }
    if($ClassName -eq 'RetryFails'){throw [Runtime.InteropServices.COMException]::new('Localized projected property failure',[Convert]::ToInt32('80041017',16))}
    foreach($id in @('00001','00002')){[pscustomobject]@{Name='Fixture';Caption='Windows fixture';InstanceName='MONITOR1';DiskNumber=0;PartitionNumber=1;TotalPhysicalMemory=8GB;SerialNumber=$id;DeviceID=$id;Namespace=$Namespace;Filter=$Filter;Timeout=$OperationTimeoutSec;Properties=$Property;Enabled=$false;Paths=@('P1','P2')}}
}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Fixture NIC';MacAddress='001122334455';HardwareInterface=$false}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='FIXTURE-GUID'}}
$display=[pscustomobject]@{Mode='Synthetic recovery test'}
$root=Join-Path $PSScriptRoot ('test-output-recovery-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        $rows=@(Invoke-ScanQuery {Get-HwidInstance Recover -Namespace 'root/test' -Property SerialNumber,OptionalMissing -Filter 'Present=True' -OperationTimeoutSec 30})
        Assert ($rows.Count -eq 2 -and $rows[0].SerialNumber -ceq '00001' -and $rows[1].SerialNumber -ceq '00002') ($mode+' retry recovers all exact serials and discards partial primary output')
        Assert ($rows[0].Namespace -ceq 'root/test' -and $rows[0].Filter -ceq 'Present=True' -and $rows[0].Timeout -eq 30 -and -not $rows[0].Properties) ($mode+' retry preserves namespace, filter and timeout while removing only the property projection')
        Assert ($rows[0].Enabled -eq $false -and $rows[0].Paths.Count -eq 2) ($mode+' recovered data preserves false values and arrays')
        Assert ($script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryRecoveries[0].Class -eq 'Recover' -and $script:lastQueryRecoveries[0].PrimaryFailure -match 'Localized') ($mode+' recovery details reach the main thread without becoming hardware records')
        Section 'CPU' {Get-HwidInstance Recover -Property SerialNumber,OptionalMissing | Select-Object DeviceID,SerialNumber,@{n='ProcessorId';e={$_.SerialNumber}}}
        Assert ($warnings.Count -eq 0 -and $report.CPU.Count -eq 2 -and $scanTimings[-1].Summary -match 'compatible read' -and $scanTimings[-1].Recoveries.Count -eq 1) ($mode+' successful recovery is labeled in scan timing without a failed-section warning')
        $healthy=@(Invoke-ScanQuery {Get-HwidInstance Healthy -Property SerialNumber})
        Assert ($healthy.Count -eq 2 -and $healthy[0].Properties -contains 'SerialNumber' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' healthy queries retain their requested fields and clear prior recovery notes')
        $failed=$false;$partial=@()
        try{$partial=@(Invoke-ScanQuery {Get-HwidInstance BadFilter -Property SerialNumber -Filter 'bad'})}catch{$failed=$true}
        Assert ($failed -and $partial.Count -eq 0 -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' an invalid filter still fails rather than widening the device scope')
        Section 'Motherboard' {Get-HwidInstance RetryFails -Property SerialNumber}
        Assert ($report.Motherboard.FailureCode -eq 'READ-01' -and $report.Motherboard.Unavailable -match 'Requested fields failed:.*Compatible read failed:') ($mode+' a failed retry keeps both diagnostics and classifies the final access failure')
        foreach($case in @(@('Access','READ-01'),@('Timeout','READ-02'),@('MissingClass','READ-03'))){
            $failure=$null
            try{Invoke-ScanQuery ([scriptblock]::Create('Get-HwidInstance '+$case[0]+' -Property SerialNumber')) | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq $case[1] -and $failure.Details -notmatch 'Compatible read failed' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' '+$case[0]+' is not retried as a projection failure')
        }
        $empty=@(Invoke-ScanQuery {Get-HwidInstance Empty -Property SerialNumber})
        Assert ($empty.Count -eq 0 -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' no matching devices remain empty without fabricated fallback records')
        Section 'CPU' {Get-HwidInstance Healthy -Property SerialNumber}
        Assert ($scanTimings[-1].Recoveries.Count -eq 0 -and $scanTimings[-1].Summary -notmatch 'compatible read') ($mode+' the next section does not inherit old recovery status')
        if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
        $snapshot=Invoke-HardwareScan 2 -UseWorker ($mode -eq 'Worker')
        Assert ($snapshot.Completed -and $snapshot.Inventory['Report info'].CompatibleReadSections -eq 14 -and $snapshot.Inventory['Scan timing'].Count -eq 17 -and $snapshot.Warnings.Count -eq 0) ($mode+' full scans count recovered sections without losing any of seventeen query results')
        $export=$snapshot.Inventory | ConvertTo-Json -Depth 12
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic report' $export
        $import=Read-SavedReport ($stem+'.json')
        Assert ($import.'Report info'.CompatibleReadSections -eq 14 -and $import.'Scan timing'[0].Recoveries[0].Class -eq 'Win32_ComputerSystemProduct' -and $import.'Scan timing'[0].Recoveries[0].PrimaryFailure -match 'Localized') ($mode+' recovery metadata survives snapshot export and import')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$script:calls=0
function Get-CimInstance {
    param($ClassName,$Property,$Filter,$Namespace,$OperationTimeoutSec)
    $script:calls++
    throw [Runtime.InteropServices.COMException]::new('Localized invalid query',[Convert]::ToInt32('80041017',16))
}
try{Get-HwidInstance Test -Property SerialNumber | Out-Null}catch{}
Assert ($script:calls -eq 2) 'Persistent projection failure has exactly one retry'
$script:calls=0;try{Get-HwidInstance Test | Out-Null}catch{}
Assert ($script:calls -eq 1) 'Queries already reading all properties are not retried'
function Get-WmiObject {
    param($Class,$Namespace,$Property,$Filter)
    $script:calls++
    if($Property){throw [Runtime.InteropServices.COMException]::new('Localized invalid property',[Convert]::ToInt32('80041031',16))}
    [pscustomobject]@{SerialNumber='WMI-0001';Class=$Class;Namespace=$Namespace;Filter=$Filter}
}
function Get-Command {param($Name,$ErrorAction) if($Name -eq 'Get-CimInstance'){return $null};Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue}
$script:calls=0;$script:hwidQueryRecoveries=New-Object 'System.Collections.Generic.List[object]'
$legacy=Get-HwidInstance Legacy -Namespace 'root/test' -Property SerialNumber -Filter 'Present=True'
Assert ($script:calls -eq 2 -and $legacy.SerialNumber -ceq 'WMI-0001' -and $legacy.Filter -ceq 'Present=True' -and $script:hwidQueryRecoveries.Count -eq 1) 'Legacy WMI gets the same bounded property retry with its device selection preserved'
Remove-Item Function:Get-Command
$script:hwidQueryRecoveries=$null
function Get-CimInstance {param($ClassName,$Property) throw 'Access denied while diagnosing invalid query'}
$failed=$false;try{Get-HwidInstance Test -Property SerialNumber | Out-Null}catch{$failed=$_.Exception.Message -notmatch 'Compatible read failed'}
Assert $failed 'Text-only access diagnostics do not trigger an extra read even when they mention query errors'
[Console]::WriteLine("All $script:checks scan-recovery checks passed under PowerShell $($PSVersionTable.PSVersion).")
