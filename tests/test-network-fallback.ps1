param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-NetworkFixtureQuery($Primary,$Modern,$Legacy='throw "Unexpected legacy read"'){
    return [scriptblock]::Create(('function Get-NetAdapter {param([switch]$IncludeHidden) '+$Primary+'};function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) if($ClassName -eq "MSFT_NetAdapter"){'+$Modern+';return};'+$Legacy+'};Get-NetworkIdentifiers'))
}
$root=Join-Path $PSScriptRoot ('test-output-network-fallback-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try {
        $query=Get-NetworkFixtureQuery '[pscustomobject]@{Name="Malformed native";InterfaceGuid=@("BAD-GUID")}' '[pscustomobject]@{Name="Recovered adapter";InterfaceGuid="NIC-0001";NetworkAddresses=@("00-11-22-33-44-55");HardwareInterface=$false;ReceiveLinkSpeed=0}'
        Section 'Network adapters' $query
        $rows=$report['Network adapters']
        Assert ((Test-SectionReadable $rows) -and $rows[0].InterfaceGuid -ceq 'NIC-0001' -and $rows[0].CollectionSource -eq 'MSFT_NetAdapter CIM fallback') ($mode+' a malformed primary identifier cannot block a usable network fallback')
        Assert ($rows[0].HardwareInterface -eq $false -and $rows[0].ReceiveLinkSpeed -eq 0 -and $rows[0].ReportedNetworkAddress -ceq '00-11-22-33-44-55' -and $null -eq $rows[0].MacAddress) ($mode+' recovery preserves exact values and leaves an unverified current address unresolved')
        Assert ($warnings.Count -eq 0 -and $scanTimings[-1].Results -eq 1 -and $scanTimings[-1].Summary -match 'compatible read') ($mode+' recovered scanning reports the real result count and a compatible read')
        Assert ($scanTimings[-1].Recoveries.Count -eq 1 -and $scanTimings[-1].Recoveries[0].Class -eq 'Get-NetAdapter' -and $scanTimings[-1].Recoveries[0].Method -eq 'MSFT_NetAdapter CIM fallback' -and $scanTimings[-1].Recoveries[0].PrimaryFailure -match 'InterfaceGuid') ($mode+' successful fallback retains its failed reader and precise field diagnostic')
        foreach($field in @('InterfaceGuid','MacAddress','PermanentAddress','PNPDeviceID')){
            $native='[pscustomobject]@{Name="Partial native";InterfaceGuid="PARTIAL"};[pscustomobject]@{Name="Bad native";'+$field+'=@("BAD")}'
            $fixed=@(Invoke-ScanQuery (Get-NetworkFixtureQuery $native '[pscustomobject]@{Name="Complete CIM";InterfaceGuid="COMPLETE"}'))
            Assert ($fixed.Count -eq 1 -and $fixed[0].InterfaceGuid -ceq 'COMPLETE') ($mode+' invalid primary '+$field+' discards the complete attempt before fallback')
            $modern='[pscustomobject]@{Name="Partial modern";InterfaceGuid="PARTIAL"};[pscustomobject]@{Name="Bad modern";'+$field+'=$true}'
            # MacAddress is not part of the modern CIM projection; an unused extra field must not reject it.
            if($field -eq 'MacAddress'){
                $fixed=@(Invoke-ScanQuery (Get-NetworkFixtureQuery 'throw "Native unavailable"' $modern))
                Assert ($fixed.Count -eq 2 -and $fixed[1].CollectionSource -eq 'MSFT_NetAdapter CIM fallback' -and $null -eq $fixed[1].MacAddress) ($mode+' unused modern fields do not reject otherwise usable records')
            }else{
                $fixed=@(Invoke-ScanQuery (Get-NetworkFixtureQuery 'throw "Native unavailable"' $modern '[pscustomobject]@{Name="Complete legacy";GUID="LEGACY-0001";MACAddress="001122334455";PhysicalAdapter=$false;Speed=0}'))
                Assert ($fixed.Count -eq 1 -and $fixed[0].InterfaceGuid -ceq 'LEGACY-0001' -and $fixed[0].CollectionSource -eq 'Win32_NetworkAdapter fallback') ($mode+' invalid modern '+$field+' allows the complete legacy reader to recover')
            }
        }
        $legacyQuery=Get-NetworkFixtureQuery 'throw [NotSupportedException]::new("Synthetic primary unavailable")' '[pscustomobject]@{Name="Bad modern";InterfaceGuid=@("BAD")}' '[pscustomobject]@{Name="Recovered legacy";GUID="LEGACY-0001";MACAddress="00-11-22-33-44-55";PhysicalAdapter=$false;Speed=0}'
        Section 'Network adapters' $legacyQuery
        Assert ($report['Network adapters'][0].MacAddress -ceq '00-11-22-33-44-55' -and $report['Network adapters'][0].HardwareInterface -eq $false -and $report['Network adapters'][0].RawLinkSpeedBps -eq 0) ($mode+' legacy fallback preserves the actual reported ID and zero/false metadata')
        Assert ($scanTimings[-1].Recoveries.Count -eq 1 -and $scanTimings[-1].Recoveries[0].Method -eq 'Win32_NetworkAdapter fallback' -and $scanTimings[-1].Recoveries[0].PrimaryFailure -match 'Primary:.*Synthetic primary unavailable.*CIM fallback:.*InterfaceGuid') ($mode+' legacy recovery explains both earlier attempts')
        foreach($field in @('GUID','MACAddress','PNPDeviceID')){
            $invalid='[pscustomobject]@{Name="Partial legacy";GUID="PARTIAL"};[pscustomobject]@{Name="Bad legacy";'+$field+'=@{Value="BAD"}}'
            $failure=$null;$partial=@()
            try{$partial=@(Invoke-ScanQuery (Get-NetworkFixtureQuery 'throw "Native unavailable"' 'throw "Modern unavailable"' $invalid))}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($partial.Count -eq 0 -and $failure.Code -eq 'READ-06' -and $failure.Details -match [regex]::Escape($field)) ($mode+' invalid legacy '+$field+' remains unreadable without leaking partial rows')
        }
        $failure=$null
        try{Invoke-ScanQuery (Get-NetworkFixtureQuery '[pscustomobject]@{InterfaceGuid=@("BAD")}' '[pscustomobject]@{InterfaceGuid=$true}' 'throw [UnauthorizedAccessException]::new("Synthetic final denial")') | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($failure.Code -eq 'READ-01' -and $failure.Details -match 'Primary:.*CIM fallback:.*Fallback:.*Synthetic final denial') ($mode+' all-failed scanning retains the final typed failure and every attempt diagnostic')
        $report['Report info']=@{Version='3.75';Computer='TEST';Generated='2026-10-31T12:00:00Z'}
        $report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic fallback snapshot' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Scan timing'[0].Recoveries[0].PrimaryFailure -match 'InterfaceGuid' -and $saved.'Scan timing'[1].Recoveries[0].PrimaryFailure -match 'CIM fallback') ($mode+' saved snapshots retain recovery details for both fallback routes')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' recovery diagnostics do not change identifier comparison results')
        $native=@(Invoke-ScanQuery (Get-NetworkFixtureQuery '[pscustomobject]@{Name="Native";InterfaceGuid="000123";MacAddress="00-11-22-33-44-55";LinkSpeed=@(1);Status=$true}' 'throw "Unexpected modern read"'))
        Assert ($native.Count -eq 1 -and $native[0].InterfaceGuid -ceq '000123' -and $native[0].LinkSpeed[0] -eq 1 -and $native[0].Status -eq $true -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' optional metadata and exact scalar IDs remain intact; the next query clears old recoveries')
        $native=@(Invoke-ScanQuery (Get-NetworkFixtureQuery '[pscustomobject]@{Name="No IDs";InterfaceGuid=$null;MacAddress=" ";HardwareInterface=$false}' 'throw "Unexpected modern read"'))
        Assert ($native.Count -eq 1 -and $native[0].CollectionSource -eq 'Get-NetAdapter' -and $null -eq $native[0].InterfaceGuid) ($mode+' missing identifiers remain a readable device for review rather than a forced fallback')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks network-fallback checks passed under PowerShell $($PSVersionTable.PSVersion).")
