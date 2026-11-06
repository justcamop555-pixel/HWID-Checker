param([string]$Engine=(Get-Process -Id $PID).Path,[string]$BatPath=(Join-Path $PSScriptRoot '..\..\hwid.bat'),[string]$FixtureOutput)
$ErrorActionPreference='Stop'
$bridge=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\engine\DesktopBridge.ps1'))
$BatPath=[IO.Path]::GetFullPath($BatPath)
$originalHash=(Get-FileHash -LiteralPath $BatPath).Hash
$root=Join-Path ([IO.Path]::GetTempPath()) ('HWID-Desktop-bridge-'+[guid]::NewGuid().ToString('N')+" & ! ' Ω")
[void][IO.Directory]::CreateDirectory($root)
$script:checks=0
function Assert($Condition,$Message){if(-not $Condition){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Save-Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))}
function Quote-Argument([string]$Text){return ('"'+$Text.Replace('"','\"')+'"')}
function Invoke-Bridge([string]$Operation,[string]$Source,$Request,[int]$ExpectedExit=0){
    $arguments=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$bridge,'-Action',$Operation,'-BatPath',$Source)
    if($null -ne $Request){$requestPath=Join-Path $root ([guid]::NewGuid().ToString('N')+'.request.json');Save-Json $requestPath $Request;$arguments+=@('-RequestPath',$requestPath)}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Engine;$start.Arguments=($arguments | ForEach-Object {Quote-Argument $_}) -join ' '
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false);$start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $start.EnvironmentVariables['COMPUTERNAME']='SYNTHETIC-PC'
    $process=[Diagnostics.Process]::Start($start)
    try{
        $outputTask=$process.StandardOutput.ReadToEndAsync();$errorTask=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(45000)){$process.Kill();throw 'Synthetic bridge operation exceeded its time limit.'}
        $output=$outputTask.GetAwaiter().GetResult();$errorText=$errorTask.GetAwaiter().GetResult();$exitCode=$process.ExitCode
    }finally{$process.Dispose()}
    $events=@(foreach($line in ($output -split '\r?\n')){if(-not [string]::IsNullOrWhiteSpace($line)){try{ConvertFrom-Json -InputObject $line -ErrorAction Stop}catch{throw 'The bridge wrote non-JSON text to its protocol stream.'}}})
    $results=@($events | Where-Object type -eq 'result');$errors=@($events | Where-Object type -eq 'error')
    if($exitCode -ne $ExpectedExit){throw ('Unexpected bridge exit '+$exitCode+' / '+(($errors | ForEach-Object {$_.code+': '+$_.message}) -join ' / ')+' / '+$errorText)}
    if($errorText){throw ('The bridge wrote unexpected stderr: '+$errorText)}
    return [pscustomobject]@{Events=$events;Results=$results;Errors=$errors;ExitCode=$exitCode;Data=$(if($results.Count){$results[0].data}else{$null})}
}
$fakeFunctions=@'
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    [pscustomobject]@{DeviceID='CPU0';Name='Synthetic component';Caption='Synthetic Windows';Vendor='Synthetic';Version='1';IdentifyingNumber='SYSTEM-000123';UUID='11111111-2222-3333-4444-555555555555';Manufacturer='Synthetic';Model='Synthetic';Product='Synthetic board';SerialNumber='000123';ProcessorId='CPU-000123';SocketDesignation='SOCKET0';NumberOfCores=4;NumberOfLogicalProcessors=8;MaxClockSpeed=4000;TotalPhysicalMemory=8GB;DeviceLocator='DIMM0';BankLabel='BANK0';PartNumber='RAM-0001';Capacity=8GB;Speed=3200;ConfiguredClockSpeed=0;Index=0;Number=0;DiskNumber=0;PartitionNumber=1;Size=8GB;FreeSpace=4GB;DriveType=3;VolumeName='Synthetic';VolumeSerialNumber='00AB12CD';FileSystem='NTFS';FirmwareRevision='1';PNPDeviceID='USB\SYNTHETIC';PNPClass='USB';ClassGuid='TEST';Service='Synthetic';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-0001');CompatibleID=@('CLASS-0001');UniqueId='DISK-000123';UniqueIdFormat=0;Guid='11111111-2222-3333-4444-555555555555';PartitionStyle=2;BusType=17;HealthStatus=0;DriveLetter=[char]'C';GptType='11111111-2222-3333-4444-555555555555';MbrType=0;AccessPaths=@('C:\');InstanceName='MONITOR0';Active=$true;SerialNumberID=@(48,48,49);UserFriendlyName=@(83,89,78);UserFriendlyNameLength=3;ManufacturerName=@(83,89,78);ManufacturerNameLength=3;ProductCodeID=@(49);WeekOfManufacture=1;YearOfManufacture=2026;OSArchitecture='64-bit';BuildNumber='TEST'}
}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Synthetic adapter';InterfaceDescription='Synthetic network';InterfaceGuid='11111111-2222-3333-4444-555555555555';MacAddress='001122334455';PermanentAddress='001122334455';PNPDeviceID='USB\SYNTHETIC';Status='Up';LinkSpeed=1000000000;HardwareInterface=$true}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='SYNTHETIC-MACHINE-0001'}}
function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Synthetic device';PNPDeviceID='USB\SYNTHETIC';PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-0001')}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Synthetic device';DeviceInstanceId='USB\SYNTHETIC';PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-0001')});Info=[ordered]@{Captured='2026-11-04T12:00:00-05:00';Source='Synthetic desktop tests';Records=1;PropertyNodesRequested=1;PropertyNodesReturned=1;PropertyNodesWithoutRows=0}}}
'@
$raw=[IO.File]::ReadAllText($BatPath)
$fixture=Join-Path $root "hwid & ! ' 子.bat"
[IO.File]::WriteAllText($fixture,($raw+[Environment]::NewLine+$fakeFunctions),[Text.UTF8Encoding]::new($false))
$scan=Invoke-Bridge Scan $fixture $null
Assert ($scan.Results.Count -eq 1 -and $scan.Errors.Count -eq 0) 'A synthetic full scan returns exactly one result and no protocol error'
Assert (@($scan.Events | Where-Object {$_.type -notin @('progress','result','error')}).Count -eq 0) 'Every stdout line belongs to the documented NDJSON protocol'
$progress=@($scan.Events | Where-Object type -eq 'progress')
Assert ($progress.Count -ge 37 -and $progress[0].completed -eq 0 -and $progress[-1].completed -eq 18 -and $progress[-1].total -eq 18) 'Progress covers preparation, seventeen sections and the all-known catalog'
foreach($event in $progress){foreach($key in @('section','name','completed','total','status','records','message')){if($null -eq $event.PSObject.Properties[$key]){throw ('Missing protocol progress key: '+$key)}}}
Assert ($true) 'Every progress event includes stable section, status, count and message keys'
Assert ($scan.Data.inventory.'Scan timing'.Count -eq 17 -and @($scan.Data.inventory.'Scan timing' | Where-Object Status -eq 'UNAVAILABLE').Count -eq 0) 'The desktop uses the BAT collector for all seventeen normal sections'
Assert ($scan.Data.inventory.'Report info'.ExtendedStatus -eq 'Refreshed' -and $scan.Data.inventory.'Extended device inventory'.Count -eq 1) 'The desktop full scan includes the validated extended catalog'
Assert ($scan.Data.version -eq $scan.Data.inventory.'Report info'.Version -and $scan.Data.captured -eq $scan.Data.inventory.'Report info'.Generated) 'Desktop version and capture metadata come from the actual BAT result'
Assert ($scan.Data.inventory.CPU[0].ProcessorId -ceq 'CPU-000123' -and $scan.Data.inventory.'Memory modules'[0].SerialNumber -ceq '000123' -and $scan.Data.inventory.'Report info'.Computer -ceq 'SYNTHETIC-PC') 'Synthetic scan results preserve exact identifiers without querying actual hardware IDs'
Assert ($scan.Data.fieldLabels.'Memory modules'.Speed -match 'raw' -and $scan.Data.fieldValues.'Memory modules'[0].ConfiguredClockSpeed -match 'Unknown') 'Display metadata reuses section-specific engine labels and unknown-clock formatting'
Assert ($scan.Data.inventory.'Memory modules'[0].ConfiguredClockSpeed -eq 0 -and $scan.Data.inventory.'Memory modules'[0].Speed -eq 3200) 'Display formatting leaves raw inventory values untouched'
Assert ($scan.Data.identifiers.Count -gt 0 -and $null -ne $scan.Data.review.Total -and $scan.Data.warnings.Count -eq 0) 'The desktop receives engine identifier quality and warning-review data'
if($FixtureOutput){$fixturePath=[IO.Path]::GetFullPath($FixtureOutput);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $fixturePath));Save-Json $fixturePath $scan.Data}
$inventoryPath=Join-Path $root "current & ! ' 子.json";Save-Json $inventoryPath $scan.Data.inventory
$folder=Join-Path $root "saved & ! ' 子"
$export=Invoke-Bridge Export $fixture @{inventoryPath=$inventoryPath;folder=$folder}
Assert ($export.Results.Count -eq 1 -and [IO.File]::Exists($export.Data.textPath) -and [IO.File]::Exists($export.Data.jsonPath)) 'Export creates the engine-verified TXT and JSON report pair'
Assert ([IO.Path]::GetDirectoryName($export.Data.textPath) -ceq $folder -and [IO.Path]::GetDirectoryName($export.Data.jsonPath) -ceq $folder) 'Export writes only into the explicitly requested folder'
$saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($export.Data.jsonPath))
Assert ($saved.CPU[0].ProcessorId -ceq 'CPU-000123' -and $saved.'Memory modules'[0].SerialNumber -ceq '000123' -and $saved.'Memory modules'[0].ConfiguredClockSpeed -eq 0) 'Saved JSON retains leading zeroes and raw scalar values'
Assert (-not [string]::IsNullOrWhiteSpace([string]$saved.'Report info'.SavedAt) -and $saved.'Report info'.ScanNumber -eq 1) 'Save metadata is added by the BAT report writer'
$original=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($inventoryPath))
Assert ($null -eq $original.'Report info'.SavedAt) 'Export does not mutate the active inventory file'
$text=[IO.File]::ReadAllText($export.Data.textPath)
Assert ($text -match 'HARDWARE REPORT' -and $text -match 'CPU-000123' -and $text -match 'Unknown \(Windows reports 0\)' -and $text -match 'Scan timing') 'TXT export reuses the full engine report and field formatting'
$firstHash=(Get-FileHash -LiteralPath $export.Data.jsonPath).Hash
$second=Invoke-Bridge Export $fixture @{inventoryPath=$inventoryPath;folder=$folder}
Assert ($second.Data.jsonPath -cne $export.Data.jsonPath -and (Get-FileHash -LiteralPath $export.Data.jsonPath).Hash -eq $firstHash) 'Repeated saves create distinct snapshots without overwriting the first pair'
$changed=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($inventoryPath));$changed.CPU[0].ProcessorId='CPU-000124'
$changedPath=Join-Path $root 'changed.json';Save-Json $changedPath $changed
$compare=Invoke-Bridge Compare $fixture @{previousPath=$export.Data.jsonPath;currentPath=$changedPath}
Assert ($compare.Results.Count -eq 1 -and $compare.Data.changes.Count -eq 1) 'Comparison reuses engine matching to find one changed identifier'
$change=$compare.Data.changes[0]
Assert ($change.kind -eq 'Changed' -and $change.section -eq 'CPU' -and $change.field -eq 'ProcessorId' -and $change.previous -ceq 'CPU-000123' -and $change.current -ceq 'CPU-000124') 'Comparison exposes exact old and current ID values'
Assert ($change.difference -match 'character' -and $compare.Data.previousCount -gt 0 -and $compare.Data.currentCount -gt 0) 'Comparison includes the engine character-difference explanation and comparable counts'
Assert ($null -ne $compare.Data.PSObject.Properties['skippedSections'] -and $null -ne $compare.Data.PSObject.Properties['scopeWarnings']) 'Comparison exposes unread/schema/reader-coverage context'
Assert ($compare.Data.previousComputer -ceq 'SYNTHETIC-PC' -and $compare.Data.currentComputer -ceq 'SYNTHETIC-PC' -and [string]$compare.Data.previousCaptured -eq [string]$saved.'Report info'.Generated -and [string]$compare.Data.currentCaptured -eq [string]$changed.'Report info'.Generated) 'Comparison returns prior/current computer and capture metadata from the validated reports'
$same=Invoke-Bridge Compare $fixture @{previousPath=$inventoryPath;currentPath=$inventoryPath}
Assert ($same.Data.changes.Count -eq 0) 'An unchanged snapshot does not manufacture ID changes'
$badFixture=Join-Path $root 'not-hwid.bat';[IO.File]::WriteAllText($badFixture,'@echo off',[Text.UTF8Encoding]::new($false))
$invalid=Invoke-Bridge Scan $badFixture $null 1
Assert ($invalid.Results.Count -eq 0 -and $invalid.Errors.Count -eq 1 -and $invalid.Errors[0].code -eq 'BRIDGE-01') 'An incomplete companion BAT produces one actionable bootstrap error'
$missing=Invoke-Bridge Scan (Join-Path $root 'missing.bat') $null 1
Assert ($missing.Results.Count -eq 0 -and $missing.Errors.Count -eq 1 -and $missing.Errors[0].message -match 'not found') 'A missing BAT cannot appear as a completed scan'
$malformed=Invoke-Bridge Export $fixture @('not','an','object') 1
Assert ($malformed.Results.Count -eq 0 -and $malformed.Errors.Count -eq 1 -and $malformed.Errors[0].code -eq 'BRIDGE-03') 'Array-shaped desktop requests are rejected before writing files'
$absentRequest=Invoke-Bridge Compare $fixture $null 1
Assert ($absentRequest.Results.Count -eq 0 -and $absentRequest.Errors.Count -eq 1) 'Missing comparison requests fail without a result frame'
$blockedFolder=Join-Path $root 'destination-is-a-file';[IO.File]::WriteAllText($blockedFolder,'Synthetic file',[Text.UTF8Encoding]::new($false))
$failedExport=Invoke-Bridge Export $fixture @{inventoryPath=$inventoryPath;folder=$blockedFolder} 1
Assert ($failedExport.Results.Count -eq 0 -and $failedExport.Errors.Count -eq 1 -and $failedExport.Errors[0].code -eq 'SAVE-01') 'Engine save failures become protocol errors without a false saved result'
$deniedFixture=Join-Path $root 'denied-cpu.bat'
$deniedFunctions=$fakeFunctions.Replace('    [pscustomobject]@{DeviceID=',"    if(`$ClassName -eq 'Win32_Processor'){throw [UnauthorizedAccessException]::new('Synthetic CPU denial')}`r`n    [pscustomobject]@{DeviceID=")
[IO.File]::WriteAllText($deniedFixture,($raw+[Environment]::NewLine+$deniedFunctions),[Text.UTF8Encoding]::new($false))
$partial=Invoke-Bridge Scan $deniedFixture @{scanNumber=2}
Assert ($partial.Results.Count -eq 1 -and $partial.Data.inventory.CPU.FailureCode -eq 'READ-01' -and $partial.Data.warnings.Count -eq 1) 'A partial readable scan retains the original typed CPU failure and warning'
Assert ($partial.Data.inventory.'Report info'.ScanNumber -eq 2 -and @($partial.Data.inventory.'Scan timing' | Where-Object Status -eq 'UNAVAILABLE').Count -eq 1) 'Rescan numbering and unread coverage remain explicit in the returned snapshot'
$brokenFixture=Join-Path $root 'incomplete-scan.bat'
[IO.File]::WriteAllText($brokenFixture,($raw+[Environment]::NewLine+$fakeFunctions+[Environment]::NewLine+'function Invoke-HardwareScan {param($ScanNumber,$UseWorker,$IncludeExtended) [pscustomobject]@{Completed=$false;Inventory=[ordered]@{}}}'),[Text.UTF8Encoding]::new($false))
$broken=Invoke-Bridge Scan $brokenFixture $null 1
Assert ($broken.Results.Count -eq 0 -and $broken.Errors.Count -eq 1 -and $broken.Errors[0].code -eq 'BRIDGE-02') 'An incomplete engine snapshot cannot produce a successful desktop result'
Assert ((Get-FileHash -LiteralPath $BatPath).Hash -eq $originalHash) 'The production BAT engine remains byte-for-byte unchanged'
[Console]::WriteLine("All $script:checks desktop-bridge checks passed under $Engine.")
