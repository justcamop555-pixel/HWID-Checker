param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18;$display=[pscustomobject]@{Mode='Synthetic grouped scan'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$script:lines=New-Object 'System.Collections.Generic.List[string]'
function Write-PnpLine {param($Text,$Color) if($script:failGroup -and $Text -match '^  \[\d/\d\]' -and $Text.Contains($script:failGroup)){throw 'Synthetic group display failure'};$script:lines.Add([string]$Text)}
function Start-ScanLine {param($Prefix) [pscustomobject]@{Prefix=$Prefix}}
function Complete-ScanLine {param($State,$Name,$Text,$Color)}
function Update-ScanWaiting {param($State,$Seconds) if($script:failCatalogPulse -and $State.Prefix -match '\[EXTRA\]'){throw 'Synthetic catalog pulse failure'}}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Synthetic network';InterfaceGuid='SYNTHETIC-NIC';MacAddress='001122334455';HardwareInterface=$true}}
function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) [pscustomobject]@{Name='Synthetic component';Caption='Synthetic Windows';DeviceID='CPU0';PNPDeviceID='USB\PRESENT';InstanceName='MONITOR0';PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL');SerialNumber='000123';UUID='SYSTEM-001';ProcessorId='CPU-001';IdentifyingNumber='SYSTEM-001';Manufacturer='Synthetic';Model='Synthetic';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;DeviceLocator='DIMM0';BankLabel='BANK0';Size=8GB;Capacity=8GB;TotalPhysicalMemory=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='SYNTHETIC-WINDOWS'}}
function Get-PnpDevice {param([switch]$PresentOnly) Start-Sleep -Milliseconds 350;[pscustomobject]@{Name='Synthetic device';InstanceId='USB\PRESENT';Class='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL')}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ThrottleLimit,$ErrorAction,$ErrorVariable) [pscustomobject]@{InstanceId='USB\PRESENT';KeyName='DEVPKEY_Device_IsPresent';Data=$true}}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function Read-NetworkFixture($Primary,$Modern,$Legacy='[pscustomobject]@{Name="Recovered legacy";GUID="LEGACY-NIC";MACAddress="001122334455";PhysicalAdapter=$true}'){
    $query='function Get-NetAdapter {param([switch]$IncludeHidden) '+$Primary+'};function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) if($ClassName -eq "MSFT_NetAdapter"){'+$Modern+';return};'+$Legacy+'};Get-NetworkIdentifiers'
    return @(Invoke-ScanQuery ([scriptblock]::Create($query)))
}
$root=Join-Path $PSScriptRoot ('test-output-scan-flow-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $script:scanGroupState=$null
    try {
        $recovered=@(Read-NetworkFixture '[pscustomobject]@{Name=$null;InterfaceGuid=$null;HardwareInterface=$null}' '[pscustomobject]@{Name="Recovered CIM";InterfaceGuid="CIM-NIC";NetworkAddresses=@("001122334455")}')
        Assert ($recovered.Count -eq 1 -and $recovered[0].Name -ceq 'Recovered CIM' -and $recovered[0].CollectionSource -eq 'MSFT_NetAdapter CIM fallback') ($mode+' an empty primary record cannot manufacture a device or prevent fallback')
        Assert ($null -eq $recovered[0].MacAddress -and $recovered[0].ReportedNetworkAddress -ceq '001122334455') ($mode+' fallback still preserves address uncertainty and exact reported text')
        $legacy=@(Read-NetworkFixture '[pscustomobject]@{}' '[pscustomobject]@{Name=" ";InterfaceGuid=$null}')
        Assert ($legacy.Count -eq 1 -and $legacy[0].CollectionSource -eq 'Win32_NetworkAdapter fallback') ($mode+' an empty modern fallback continues to the compatible legacy reader')
        $mixed=@(Read-NetworkFixture '[pscustomobject]@{Name="Partial native";InterfaceGuid="FIRST"};[pscustomobject]@{}' '[pscustomobject]@{Name="Complete recovered attempt";InterfaceGuid="CIM-NIC"}')
        Assert ($mixed.Count -eq 1 -and $mixed[0].Name -ceq 'Complete recovered attempt') ($mode+' a mixed valid/empty reader attempt cannot leak phantom or partial rows')
        foreach($scalar in @('"not an adapter"','$true','123')){
            $fixed=@(Read-NetworkFixture $scalar '[pscustomobject]@{Name="Recovered malformed attempt";InterfaceGuid="CIM-NIC"}')
            Assert ($fixed.Count -eq 1 -and $fixed[0].Name -eq 'Recovered malformed attempt') ($mode+' a scalar response is rejected before adapter labels are added')
        }
        $zero=@(Read-NetworkFixture '[pscustomobject]@{HardwareInterface=$false;ReceiveLinkSpeed=0}' 'throw "Must not use fallback"')
        Assert ($zero.Count -eq 1 -and $zero[0].HardwareInterface -eq $false -and $zero[0].ReceiveLinkSpeed -eq 0 -and $zero[0].CollectionSource -eq 'Get-NetAdapter') ($mode+' real false/zero metadata remains usable rather than being treated as empty')
        $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
        Section 'Network adapters' {function Get-NetAdapter {[pscustomobject]@{}};function Get-CimInstance {param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec) [pscustomobject]@{}};Get-NetworkIdentifiers}
        Assert ($report['Network adapters'].FailureCode -eq 'READ-06' -and $scanTimings[-1].Results -eq 0) ($mode+' no usable reader is NOT READ with zero devices instead of a fabricated CHECK record')
        $old=[ordered]@{'Network adapters'=@([pscustomobject]@{Name='Previous';InterfaceGuid='NIC';MacAddress='AABBCCDDEEFF'})}
        $comparison=Compare-Inventories $old $report
        Assert ($comparison.Changes.Count -eq 0 -and $comparison.SkippedSections -contains 'Network adapters') ($mode+' unread empty-adapter results cannot become false identifier removals')
        Section 'Network adapters' {[pscustomobject]@{Name=$null;InterfaceGuid=$null;LinkSpeedKind='Receive link rate';CollectionSource='Synthetic reader'}}
        Assert ($report['Network adapters'].FailureCode -eq 'READ-06') ($mode+' derived rate/source labels alone are not actual adapter data')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    $script:lines.Clear();$script:failGroup=$null;$script:failCatalogPulse=$false
    $scan=Invoke-HardwareScan 1 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
    $groupLines=@($lines | Where-Object {$_ -match '^  \[\d/8\]'})
    Assert ($groupLines.Count -eq 8 -and ($groupLines -join '|') -match '(?s)SYSTEM & FIRMWARE.*CPU & MEMORY.*STORAGE.*GRAPHICS & NETWORK.*POWER.*WINDOWS.*PRESENT DEVICE IDS.*ALL-KNOWN DEVICE CATALOG') ($mode+' full scanning presents eight ordered groups without duplicate headings')
    Assert (($scan.Inventory['Scan timing'][0..6].Section -join '|') -ceq 'System identity|System hardware|Motherboard|BIOS|Chassis|CPU|Memory modules') ($mode+' firmware queries stay together before CPU/memory queries')
    Assert ($scan.Completed -and $scan.Inventory['Scan timing'].Count -eq 18 -and $scanStep -eq 18 -and $scan.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') ($mode+' group headings do not change query totals or extended completion')
    Assert ($null -eq $script:scanGroupState) ($mode+' group state is cleared after scan completion')
    $script:lines.Clear();$again=Invoke-HardwareScan 2 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
    Assert (@($lines | Where-Object {$_ -match '^  \[1/8\] SYSTEM'}).Count -eq 1 -and @($lines | Where-Object {$_ -match '^  \[8/8\] ALL-KNOWN'}).Count -eq 1) ($mode+' subsequent scans restart group numbering and include the last catalog group')
    Assert ((Compare-Inventories $scan.Inventory $again.Inventory).Changes.Count -eq 0) ($mode+' reorganizing scan order does not manufacture identifier changes')
    $script:lines.Clear();$short=Invoke-HardwareScan 3 -UseWorker ($mode -eq 'Worker') -IncludeExtended $false
    Assert (@($lines | Where-Object {$_ -match '^  \[\d/7\]'}).Count -eq 7 -and -not $short.Inventory.Contains('Extended scan info')) ($mode+' section-only scans show seven groups without a catalog claim')
    $script:failGroup='STORAGE';$damaged=Invoke-HardwareScan 4 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
    Assert ($damaged.Completed -and $damaged.Inventory['Report info'].ProgressFallbackSections -eq 1 -and $damaged.Inventory['Scan timing'][7].ProgressWarning -match 'group display') ($mode+' group rendering failures stay separate from valid hardware-query results')
    $script:failGroup='ALL-KNOWN DEVICE CATALOG';$catalogDisplay=Invoke-HardwareScan 5 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
    Assert ($catalogDisplay.Inventory['Report info'].ExtendedStatus -eq 'Refreshed' -and $catalogDisplay.Inventory['Extended scan info'].ProgressWarning -match 'group display' -and $catalogDisplay.Inventory['Report info'].ProgressFallbackSections -eq 0) ($mode+' catalog display failures are retained separately from normal section warnings')
    $script:failGroup=$null
    if($mode -eq 'Worker'){
        $script:failCatalogPulse=$true;$catalogDisplay=Invoke-HardwareScan 6 -UseWorker $true -IncludeExtended $true
        Assert ($catalogDisplay.Inventory['Report info'].ExtendedStatus -eq 'Refreshed' -and $catalogDisplay.Inventory['Extended scan info'].ProgressWarning -match 'catalog pulse') 'Worker catalog timer failures remain visible without discarding the catalog'
        $script:failCatalogPulse=$false
    }
    $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic organized scan' ($catalogDisplay.Inventory | ConvertTo-Json -Depth 12)
    $saved=Read-SavedReport ($stem+'.json')
    Assert ($saved.'Extended scan info'.ProgressWarning -match 'display|pulse' -and $saved.'Memory modules'[0].SerialNumber -ceq '000123') ($mode+' saved reports retain catalog feedback diagnostics and exact serials')
    Assert ((Compare-Inventories $catalogDisplay.Inventory $saved).Changes.Count -eq 0) ($mode+' grouped scan snapshots still compare without false changes')
}
[Console]::WriteLine("All $checks scan-flow checks passed under PowerShell $($PSVersionTable.PSVersion).")
