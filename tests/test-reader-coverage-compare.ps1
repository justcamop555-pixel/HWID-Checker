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
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Reset-UiPage {}
function Start-UiReport {param([switch]$Scanning)}
function Add-ReportBookmark {param($Key)}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function New-Nic($Key,$Mac,$Reader){[pscustomobject]@{Name=('Synthetic '+$Key);InterfaceGuid=$Key;MacAddress=$Mac;CollectionSource=$Reader}}
function New-Snapshot($Nics){[ordered]@{'Report info'=@{Version='3.77';Computer='TEST';Generated='2026-11-01T12:00:00-05:00'};'Network adapters'=@($Nics);CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-000123'})}}
$native='Get-NetAdapter';$modern='MSFT_NetAdapter CIM fallback';$legacy='Win32_NetworkAdapter fallback'
$previous=New-Snapshot @((New-Nic NIC-SHARED '00-11-22-33-44-55' $native),(New-Nic NIC-OLD '00-11-22-33-44-66' $native))
$current=New-Snapshot @((New-Nic NIC-SHARED '001122334455' $modern),(New-Nic NIC-NEW '001122334477' $modern))
$comparison=Compare-Inventories $previous $current
Assert ($comparison.Changes.Count -eq 0 -and $comparison.SkippedFields -eq 4) 'Different network-reader coverage cannot manufacture ID additions or removals'
Assert ($comparison.PreviousCount -eq 3 -and $comparison.CurrentCount -eq 3 -and $comparison.ScopeWarnings.Count -eq 1 -and $comparison.ScopeWarnings[0].SkippedDevices -eq 2) 'Only shared interfaces remain comparable and skipped devices are counted separately'
Assert ($comparison.ScopeWarnings[0].PreviousReader -eq 'Get-NetAdapter' -and $comparison.ScopeWarnings[0].CurrentReader -eq 'MSFT_NetAdapter') 'Coverage diagnostics name the previous and current reader'
Assert ($comparison.SkippedSections -notcontains 'Network adapters' -and $comparison.AmbiguousDevices.Count -eq 0) 'Reader differences do not turn shared interfaces into unread sections or hardware conflicts'
$current['Network adapters'][0].MacAddress='001122334499'
$comparison=Compare-Inventories $previous $current;$details=@(Get-ComparisonDetails $comparison)
Assert ($details.Count -eq 1 -and $details[0].Kind -eq 'Changed' -and $details[0].Field -eq 'MacAddress' -and $details[0].Device -match 'NIC-SHARED') 'A real ID change on a shared interface survives a reader transition'
Assert ($details[0].Previous -ceq '001122334455' -and $details[0].Current -ceq '001122334499') 'Comparable changes keep their canonical OLD and NEW values'
foreach($sources in @(@($native,$modern),@($modern,$native),@($native,$legacy),@($legacy,$modern),@($null,$native),@($native,$null),@($null,$null),@('Custom reader',$native),@($native,'Custom reader'))){
    $old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $sources[0]),(New-Nic PREVIOUS AABBCCDDEE22 $sources[0]))
    $new=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $sources[1]),(New-Nic CURRENT AABBCCDDEE33 $sources[1]))
    $result=Compare-Inventories $old $new
    Assert ($result.Changes.Count -eq 0 -and $result.ScopeWarnings.Count -eq 1 -and $result.ScopeWarnings[0].SkippedDevices -eq 2) 'Different or unrecorded reader scopes skip one-sided interfaces in both directions'
}
foreach($reader in @($native,$modern,$legacy)){
    $old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $reader),(New-Nic PREVIOUS AABBCCDDEE22 $reader))
    $new=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $reader),(New-Nic CURRENT AABBCCDDEE33 $reader))
    $result=Compare-Inventories $old $new;$details=@(Get-ComparisonDetails $result)
    Assert ($result.Changes.Count -eq 4 -and $result.ScopeWarnings.Count -eq 0 -and $result.SkippedFields -eq 0) 'Matching known readers retain genuine one-sided ID differences'
    Assert (@($details | Where-Object Kind -eq 'Previous only').Count -eq 2 -and @($details | Where-Object Kind -eq 'Current only').Count -eq 2) 'Same-reader changes still identify both previous-only and current-only values'
}
$old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 ' get-netadapter '),(New-Nic PREVIOUS AABBCCDDEE22 $native))
$new=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $native))
$result=Compare-Inventories $old $new
Assert ($result.Changes.Count -eq 2 -and $result.ScopeWarnings.Count -eq 0) 'Reader-label case and surrounding whitespace do not manufacture a scope transition'
$old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $native),(New-Nic PREVIOUS AABBCCDDEE22 $modern))
$new=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $native),(New-Nic CURRENT AABBCCDDEE33 $modern))
$result=Compare-Inventories $old $new
Assert ($result.Changes.Count -eq 0 -and $result.ScopeWarnings.Count -eq 1) 'A mixed-reader capture does not establish reliable one-sided device coverage'
$old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $native))
$new=New-Snapshot @((New-Nic SHARED AABBCCDDEE99 $modern))
$result=Compare-Inventories $old $new
Assert ($result.Changes.Count -eq 2 -and $result.ScopeWarnings.Count -eq 0) 'A reader transition alone adds no warning when every interface is matched'
$old=New-Snapshot @((New-Nic SHARED AABBCCDDEE11 $native),(New-Nic PREVIOUS AABBCCDDEE22 $native))
$new=New-Snapshot @((New-Nic SHARED $null $modern))
$result=Compare-Inventories $old $new
Assert ($result.Changes.Count -eq 0 -and $result.SkippedFields -eq 3 -and $result.ScopeWarnings[0].SkippedDevices -eq 1) 'Missing matched IDs and uncertain device coverage stay distinct without false removals'
$new.CPU[0].ProcessorId='CPU-CHANGED'
$result=Compare-Inventories $old $new;$details=@(Get-ComparisonDetails $result)
Assert ($details.Count -eq 1 -and $details[0].Section -eq 'CPU' -and $details[0].Kind -eq 'Changed') 'Network coverage handling cannot suppress genuine changes in other hardware'
$new['Network adapters']=@((New-Nic SHARED AABBCCDDEE11 $modern),(New-Nic SHARED AABBCCDDEE99 $modern))
$result=Compare-Inventories $old $new
Assert ($result.AmbiguousDevices.Count -eq 1 -and @(Get-InventoryConflicts $new).Count -eq 1) 'True duplicate interface-key conflicts remain visible'
$new['Network adapters']=@([pscustomobject]@{InterfaceGuid=$null;MacAddress='AABBCCDDEE11';CollectionSource=$modern})
$result=Compare-Inventories $old $new
Assert ($result.UnkeyedSections -contains 'Network adapters' -and $result.ScopeWarnings.Count -eq 0) 'Missing interface keys retain their original unmatchable-section diagnosis'
$root=Join-Path $PSScriptRoot ('test-output-reader-coverage-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$beforeOld=$previous | ConvertTo-Json -Depth 12 -Compress;$beforeNew=$current | ConvertTo-Json -Depth 12 -Compress
foreach($side in @('previous','current')){$value=if($side -eq 'previous'){$previous}else{$current};Write-ReportPair (Join-Path $root $side) 'Synthetic reader coverage' ($value | ConvertTo-Json -Depth 12)}
$savedOld=Read-SavedReport (Join-Path $root 'previous.json');$savedNew=Read-SavedReport (Join-Path $root 'current.json')
$savedComparison=Compare-Inventories $savedOld $savedNew
Assert ($savedComparison.Changes.Count -eq 2 -and $savedComparison.ScopeWarnings[0].SkippedDevices -eq 2) 'Imported snapshots preserve reader-aware comparison and real shared-ID changes'
Assert (($previous | ConvertTo-Json -Depth 12 -Compress) -ceq $beforeOld -and ($current | ConvertTo-Json -Depth 12 -Compress) -ceq $beforeNew) 'Comparison does not rewrite raw IDs, source labels or snapshots'
Assert ($savedOld.'Network adapters'[0].MacAddress -ceq '00-11-22-33-44-55' -and $savedOld.'Network adapters'[0].CollectionSource -ceq $native) 'Saved snapshots preserve the original address and source text'
Show-ComparisonResult $previous $current $savedComparison 'Synthetic baseline'
Assert (@($rendered | Where-Object {$_.Label -eq 'Reader coverage' -and $_.Value -match '2.*Get-NetAdapter.*MSFT_NetAdapter'}).Count -eq 1) 'Saved-comparison UI explains which unmatched records were not compared and why'
$rendered.Clear();Show-RescanResult $previous $current
Assert (@($rendered | Where-Object {$_.Label -eq 'Reader coverage' -and $_.Value -match '2.*Get-NetAdapter.*MSFT_NetAdapter'}).Count -eq 1) 'Rescan comparison shows the same coverage explanation'
$onlyOld=[ordered]@{'Report info'=$previous['Report info'];'Network adapters'=@((New-Nic OLDONLY AABBCCDDEE11 $native))}
$onlyNew=[ordered]@{'Report info'=$current['Report info'];'Network adapters'=@((New-Nic NEWONLY AABBCCDDEE22 $modern))}
$result=Compare-Inventories $onlyOld $onlyNew;$rendered.Clear();$failure=$null
try{Show-ComparisonResult $onlyOld $onlyNew $result 'Synthetic baseline'}catch{$failure=$_}
Assert ($null -eq $failure -and $result.PreviousCount -eq 0 -and $result.CurrentCount -eq 0 -and @($rendered | Where-Object Label -eq 'Reader coverage').Count -eq 1) 'A comparison with only unmatched reader scopes opens its explanation instead of failing'
Assert (@($rendered | Where-Object {$_.Label -eq 'RESULT' -and $_.Color -eq $palette.Warn}).Count -eq 1) 'No comparable IDs due to coverage cannot appear as a complete clean comparison'
[Console]::WriteLine("All $script:checks reader-coverage-compare checks passed under PowerShell $($PSVersionTable.PSVersion).")
