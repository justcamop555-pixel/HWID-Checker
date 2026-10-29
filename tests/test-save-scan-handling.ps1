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
$root=Join-Path $PSScriptRoot ('test-output-save-scan-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$report=[ordered]@{'Report info'=[ordered]@{Version='3.56';Computer='TEST';Generated='2026-10-28T12:00:00Z';ScanNumber=1};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='ID0001'});Warnings=@()}
$json=$report | ConvertTo-Json -Depth 12
$stem=Join-Path $root 'changed-text';$failed=$false
try{Write-ReportPair $stem 'TEXT-A' $json -Publisher {param($From,$To) [IO.File]::Move($From,$To);if($To.EndsWith('.txt')){[IO.File]::WriteAllText($To,'TEXT-B',[Text.UTF8Encoding]::new($false))}}}catch{$failed=$true}
Assert ($failed -and -not [IO.File]::Exists($stem+'.txt') -and -not [IO.File]::Exists($stem+'.json')) 'Same-length TXT corruption after publication is detected and rolled back'
$stem=Join-Path $root 'changed-json';$failed=$false
try{Write-ReportPair $stem 'TEXT' $json -Publisher {param($From,$To) [IO.File]::Move($From,$To);if($To.EndsWith('.json')){[IO.File]::WriteAllText($To,$json.Replace('ID0001','ID0002'),[Text.UTF8Encoding]::new($false))}}}catch{$failed=$true}
Assert ($failed -and -not [IO.File]::Exists($stem+'.txt') -and -not [IO.File]::Exists($stem+'.json')) 'Valid but changed JSON cannot be announced as the requested snapshot'
$stem=Join-Path $root 'missing-final';$failed=$false
try{Write-ReportPair $stem 'TEXT' $json -Publisher {param($From,$To)}}catch{$failed=$true}
Assert ($failed -and @(Get-ChildItem -LiteralPath $root -Filter '*.pending-*').Count -eq 0) 'A publisher that leaves no final files cannot report success or leak temporary files'
$stem=Join-Path $root 'unicode-boundary';$text=('A'*4095)+[char]0xd83d+[char]0xde00+('B'*9000)
Write-ReportPair $stem $text $json
Assert ([IO.File]::ReadAllText($stem+'.txt') -ceq $text -and (Read-SavedReport ($stem+'.json')).CPU[0].ProcessorId -ceq 'ID0001') 'Final verification preserves Unicode across chunk boundaries and complete JSON'
Assert ((Test-ReportFileContent ($stem+'.txt') $text) -and -not (Test-ReportFileContent ($stem+'.txt') ($text+'X'))) 'Content verification compares exact text and lengths'
$handle=[IO.File]::Open($stem+'.txt','Open','ReadWrite','None');$handle.Dispose()
Assert $true 'Successful verification releases its read handle'
$stem=Join-Path $root 'bad-bytes';[IO.File]::WriteAllBytes($stem+'.txt',[byte[]]@(195))
$accepted=$false;try{$accepted=Test-ReportFileContent ($stem+'.txt') 'A'}catch{}
Assert (-not $accepted) 'Invalid UTF-8 during verification is not silently accepted'
$handle=[IO.File]::Open($stem+'.txt','Open','ReadWrite','None');$handle.Dispose()
Assert $true 'Failed verification releases its read handle'
$script:scanQueryWorker=New-ScanQueryWorker;$script:pulses=0
try{
    $failure=$null;$data=@()
    try{$data=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 250;[pscustomobject]@{ProcessorId='GOOD-ID'}} {$script:pulses++;throw 'Synthetic progress display failed'})}catch{$failure=$_}
    Assert ($null -eq $failure -and $data.Count -eq 1 -and $data[0].ProcessorId -ceq 'GOOD-ID') 'A progress-display failure cannot discard successful hardware data'
    Assert ($script:pulses -eq 1 -and $script:lastQueryFeedbackFailure -match 'Synthetic progress') 'Failed progress callbacks stop repeating and retain a diagnostic'
    $next=@(Invoke-ScanQuery {[pscustomobject]@{ProcessorId='NEXT-ID'}})
    Assert ($next[0].ProcessorId -ceq 'NEXT-ID' -and -not $script:lastQueryFeedbackFailure) 'The next query clears an earlier progress-display warning'
    $failure=$null
    try{Invoke-ScanQuery {Start-Sleep -Milliseconds 250;throw [TimeoutException]::new('Provider timed out')} {throw 'Display failed again'} | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
    Assert ($failure.Code -eq 'READ-02') 'A provider failure retains its own classification after a display failure'
    $originalWaiting=(Get-Item Function:Update-ScanWaiting).ScriptBlock
    try{
        function Update-ScanWaiting {param($State,$Seconds) throw 'Synthetic waiting display failed'}
        $warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanStep=0;$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
        Section 'CPU' {Start-Sleep -Milliseconds 250;[pscustomobject]@{DeviceID='CPU0';ProcessorId='ID0001'}}
        Assert ($warnings.Count -eq 0 -and $report.CPU[0].ProcessorId -ceq 'ID0001' -and $scanTimings[0].Status -eq 'READ' -and $scanTimings[0].ProgressWarning -match 'Synthetic waiting') 'Scan timing separates progress warnings from provider-read failures'
    }finally{Set-Item Function:Update-ScanWaiting -Value $originalWaiting}
}finally{$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
$before=Copy-InventorySnapshot $report
$env:HWID_SCRIPT=Join-Path $root 'app\hwid.bat';$env:LOCALAPPDATA=Join-Path $root 'local'
Save-Reports
$saved=Read-SavedReport $lastSavedReportPath
Assert ($saved.CPU -is [array] -and $saved.CPU[0].ProcessorId -ceq 'ID0001' -and -not $saved.CPU[0].PSObject.Properties['value']) 'Copied device arrays export as hardware records rather than value/Count wrappers'
Assert ($saved.'Report info'.SavedAt -and $saved.'Report info'.Generated -ceq $before.'Report info'.Generated -and $saved.'Report info'.ScanNumber -eq 1) 'Saving records a separate save time without changing the scan time or snapshot number'
Assert (-not $report.'Report info'.Contains('SavedAt') -and $report.CPU[0].ProcessorId -ceq $before.CPU[0].ProcessorId) 'Saving does not mutate the active scan or its identifiers'
Assert ((Compare-Inventories $before $saved).Changes.Count -eq 0) 'Save-time metadata cannot become a hardware ID change'
Assert (($script:rendered -join ' ') -match 'Saved at:' -and ($script:rendered -join ' ') -match 'Scan coverage:') 'Save results explain scan time, save time and read coverage'
$firstPath=$lastSavedReportPath;Save-Reports
Assert ($lastSavedReportPath -ne $firstPath -and [IO.File]::Exists($firstPath)) 'Repeated saves create independent files while preserving the earlier snapshot'
$bad=Join-Path $root 'bad-save-time.json';$invalid=Convert-ReportJson $json
$invalid.'Report info' | Add-Member NoteProperty SavedAt ([pscustomobject]@{}) -Force
[IO.File]::WriteAllText($bad,($invalid | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$failed=$false;try{Read-SavedReport $bad | Out-Null}catch{$failed=$_.Exception.Message -match 'Invalid report metadata: SavedAt'}
Assert $failed 'Malformed optional save timestamps are rejected on import'
$originalWaiting=(Get-Item Function:Update-ScanWaiting).ScriptBlock
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -eq 'Win32_Processor'){Start-Sleep -Milliseconds 250}
    [pscustomobject]@{Name='Fixture';TotalPhysicalMemory=8GB;Caption='Windows fixture';InstanceName='MONITOR1';DiskNumber=0;PartitionNumber=1;DeviceID='CPU0';ProcessorId='CPU-1';UUID='SYSTEM-1';SerialNumber='SERIAL-1';PNPDeviceID='PCI\FIXTURE';HardwareID=@('MODEL');ConfigManagerErrorCode=0}
}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='NIC';MacAddress='001122334455';HardwareInterface=$false}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='GUID-1'}}
$display=[pscustomobject]@{Mode='Synthetic scan handling'}
try{
    function Update-ScanWaiting {param($State,$Seconds) throw 'Synthetic full-scan display failure'}
    $snapshot=Invoke-HardwareScan 2 -UseWorker $true
    Assert ($snapshot.Completed -and $snapshot.Warnings.Count -eq 0 -and $snapshot.Inventory['Scan timing'].Count -eq 17 -and $snapshot.Inventory['Report info'].ProgressFallbackSections -ge 1) 'A full scan finishes all sections after progress display failures and counts them separately'
    Assert ($snapshot.Inventory.CPU[0].ProcessorId -ceq 'CPU-1' -and @($snapshot.Inventory['Scan timing'] | Where-Object {$_.Section -eq 'CPU' -and $_.ProgressWarning -and -not $_.FailureCode}).Count -eq 1) 'Full-scan timing retains the display diagnostic without labeling the CPU read as failed'
}finally{Set-Item Function:Update-ScanWaiting -Value $originalWaiting}
[Console]::WriteLine("All $script:checks save-scan-handling checks passed under PowerShell $($PSVersionTable.PSVersion).")
