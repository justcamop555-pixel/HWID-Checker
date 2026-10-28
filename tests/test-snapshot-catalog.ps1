$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$ownedConsole=$false;$redirected=$true
$script:checks=0;$script:messages=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:messages.Add([string]$Object)}
$root=Join-Path $PSScriptRoot ('test-output-catalog-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$env:HWID_SCRIPT=Join-Path $root 'app\repo\hwid.bat'
$env:LOCALAPPDATA=Join-Path $root 'local'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $env:HWID_SCRIPT))
[IO.File]::WriteAllText((Join-Path $root 'app\hwid.bat'),'test launcher')
$locations=Get-ReportLocations
Assert ($locations.Primary -eq (Join-Path $root 'app\repo\HWID-Reports') -and $locations.Fallback -eq (Join-Path $root 'local\HWID Checker\HWID-Reports')) 'Save locations include the script folder and per-user fallback'
Assert ($locations.Search.Count -eq 3 -and $locations.Search -contains (Join-Path $root 'app\HWID-Reports')) 'Discovery includes the adjacent installation reports when a parent launcher exists'
$report=[ordered]@{'Report info'=[ordered]@{Computer='TEST';Generated='2026-10-27T12:00:00Z';Version='3.48';ScanNumber=2};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='ID0002'})}
function New-TestSnapshot($Path,$Captured,$Computer='TEST',$Id='ID0001') {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $fixture=[ordered]@{'Report info'=@{Computer=$Computer;Generated=$Captured;Version='3.48'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId=$Id})}
    [IO.File]::WriteAllText($Path,($fixture | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
}
$older=Join-Path $locations.Primary "renamed baseline ! & [1] '.json"
New-TestSnapshot $older '2026-10-26T12:00:00Z'
$same=Join-Path $locations.Primary 'HWID-current.json';New-TestSnapshot $same '2026-10-27T08:00:00-04:00' 'TEST' 'ID0002'
$newer=Join-Path $locations.Primary 'HWID-future.json';New-TestSnapshot $newer '2026-10-28T12:00:00Z'
$other=Join-Path $locations.Fallback 'HWID-other.json';New-TestSnapshot $other '2026-10-26T13:00:00Z' 'OTHER'
$adjacent=Join-Path $root 'app\HWID-Reports\HWID-parent.json';New-TestSnapshot $adjacent '2026-10-25T12:00:00Z'
$unknown=Join-Path $locations.Primary 'HWID-time-unknown.json';New-TestSnapshot $unknown 'unknown'
$missing=Join-Path $locations.Primary 'HWID-no-ids.json';New-TestSnapshot $missing '2026-10-20T12:00:00Z' 'TEST' ''
$bad=Join-Path $locations.Primary 'HWID-broken.json';[IO.File]::WriteAllText($bad,'{broken')
[IO.File]::WriteAllText((Join-Path $locations.Primary 'HWID-ignore.json.pending-test'),'pending')
[IO.File]::WriteAllText((Join-Path $locations.Primary 'HWID-ignore.txt'),'TXT')
(Get-Item -LiteralPath $older).LastWriteTimeUtc=[datetime]'2030-01-01'
$catalog=Get-SavedSnapshotCatalog (@($locations.Search)+@($locations.Primary)) $report
Assert ($catalog.Entries.Count -eq 7 -and $catalog.Skipped.Count -eq 1) 'Discovery validates JSON, skips damaged files, ignores pending/TXT files, and deduplicates paths'
Assert ($catalog.Entries[0].FullName -eq $older -and $catalog.Entries[1].FullName -eq $adjacent) 'Older same-PC captures rank ahead of current/newer/other-PC saves regardless of copied-file modification times'
Assert (@($catalog.Entries | Where-Object Relation -eq 'SAME CAPTURE TIME').Count -eq 1) 'Equivalent timestamp offsets identify the same capture time'
Assert (@($catalog.Entries | Where-Object {$_.FullName -eq $other -and -not $_.SamePc -and $_.Relation -match 'OTHER'}).Count -eq 1) 'Other-PC baselines receive a clear label'
Assert (@($catalog.Entries | Where-Object {$_.FullName -eq $unknown -and $_.Relation -eq 'TIME UNKNOWN'}).Count -eq 1) 'Unread capture dates stay explicitly unknown'
Assert ($catalog.Entries[-1].FullName -eq $missing -and $catalog.Entries[-1].UsableIds -eq 0) 'Snapshots without usable identifiers are labeled and not prioritized as baselines'
$txt=[IO.Path]::ChangeExtension($older,'.txt');[IO.File]::WriteAllText($txt,'TXT companion')
Assert ((Resolve-ComparisonReportPath $txt) -ceq $older) 'TXT comparison resolves its literal matching JSON companion'
$txtFailed=$false;try{Resolve-ComparisonReportPath (Join-Path $root 'missing.txt') | Out-Null}catch{$txtFailed=$_.Exception.Message -match 'no matching JSON'}
Assert $txtFailed 'TXT without JSON gives a specific recovery message'
$primary=Join-Path $root 'blocked';$backup=Join-Path $root 'fallback-save'
[IO.File]::WriteAllText($primary,'blocking file')
$json=$report | ConvertTo-Json -Depth 8
$saved=Write-SnapshotWithFallback $primary $backup 'HWID-fallback' 'TXT test' $json
Assert ($saved.UsedFallback -and $saved.Folder -eq $backup -and (Test-Path -LiteralPath ($saved.Stem+'.json')) -and (Test-Path -LiteralPath ($saved.Stem+'.txt'))) 'An unwritable primary folder saves a verified pair to the fallback'
Assert ((Read-SavedReport ($saved.Stem+'.json')).CPU[0].ProcessorId -ceq 'ID0002') 'Fallback JSON contains the current identifier snapshot'
Assert ([IO.File]::ReadAllText($primary) -ceq 'blocking file') 'Save fallback preserves the blocking original file'
$invalidFailed=$false;$script:writeAttempts=0
try {Write-SnapshotWithFallback (Join-Path $root 'bad-primary') (Join-Path $root 'bad-fallback') 'HWID-invalid' 'TXT' '{bad' -Writer {param($Stem,$Text,$Json) $script:writeAttempts++;Write-ReportPair $Stem $Text $Json} | Out-Null}catch{$invalidFailed=$true}
Assert ($invalidFailed -and $script:writeAttempts -eq 1) 'Invalid report data does not trigger a misleading storage fallback retry'
$bothFailed=$false;try{Write-SnapshotWithFallback $primary $primary 'HWID-both' 'TXT' $json | Out-Null}catch{$bothFailed=$true}
Assert $bothFailed 'An unavailable fallback never produces a false save success'
$script:writerCalls=0
$rolled=Write-SnapshotWithFallback (Join-Path $root 'rollback-primary') (Join-Path $root 'rollback-fallback') 'HWID-rollback' 'TXT' $json -Writer {
    param($Stem,$Text,$Json)
    $script:writerCalls++
    if($script:writerCalls -eq 1){Write-ReportPair $Stem $Text $Json -Publisher {param($From,$To) if($To.EndsWith('.json')){throw [UnauthorizedAccessException]::new('Synthetic JSON publication denied')};[IO.File]::Move($From,$To)}}else{Write-ReportPair $Stem $Text $Json}
}
Assert ($rolled.UsedFallback -and -not (Test-Path -LiteralPath (Join-Path $root 'rollback-primary\HWID-rollback.txt'))) 'Partial primary publication is rolled back before fallback succeeds'
$script:answers=New-Object 'System.Collections.Generic.Queue[string]'
function Read-CheckerLine {param($Prompt) if(-not $script:answers.Count){throw 'Unexpected comparison prompt'};$script:answers.Dequeue()}
@('6','1') | ForEach-Object {$script:answers.Enqueue($_)}
$chosen=Read-CompareReportPath
Assert ($chosen -eq $catalog.Entries[5].FullName -and $script:answers.Count -eq 0) 'Pagination exposes snapshots beyond the first five files'
$script:answers.Enqueue('8');$script:answers.Enqueue('1')
$fresh=Join-Path $locations.Primary 'HWID-fresh-old.json';New-TestSnapshot $fresh '2026-10-27T11:00:00Z'
Assert ((Read-CompareReportPath) -eq $fresh) 'Picker refresh discovers a newly saved older baseline'
$script:answers.Enqueue('9');$script:answers.Enqueue('"'+$txt+'"')
Assert ((Read-CompareReportPath) -eq $older) 'Manual path fallback accepts a quoted TXT path and selects its JSON'
$script:answers.Enqueue('0')
Assert ($null -eq (Read-CompareReportPath)) 'Comparison selection cancels without choosing a hidden baseline'
$script:messages.Clear();Save-Reports
Assert ($lastSavedReportPath -and (Test-Path -LiteralPath $lastSavedReportPath)) 'Save publishes the actual snapshot path for folder navigation'
Assert (($script:messages -join ' ') -match 'Older snapshots: 3 usable baselines') 'Saving immediately detects older usable snapshots and excludes other-PC or missing-ID files'
$savedCurrent=Read-SavedReport $lastSavedReportPath
Assert ((Get-SavedSnapshotCatalog $locations.Search $report).Entries.Count -eq 9) 'Discovery sees the newly saved snapshot without a restart'
$before=Read-SavedReport $older
$delta=Compare-Inventories $before $report
$changes=@(Get-ComparisonDetails $delta)
Assert ($changes.Count -eq 1 -and $changes[0].Previous -ceq 'ID0001' -and $changes[0].Current -ceq 'ID0002') 'An automatically detected baseline compares the exact old and current IDs'
$script:messages.Clear();Show-ComparisonResult $savedCurrent $report
Assert (($script:messages -join ' ') -match 'Same capture time:') 'Selecting a save of the active capture explains why the same scan may show no changes'
$script:messages.Clear()
Show-ComparisonResult $savedCurrent $report -Comparison ([pscustomobject]@{Changes=@();PreviousCount=1;CurrentCount=1;SkippedSections=@();SkippedFields=0;UnkeyedSections=@();AmbiguousDevices=@()})
Assert (($script:messages -join ' ') -match 'No identifier fields were skipped') 'Complete comparisons give the Not compared shortcut an explicit no-skips result'
[Console]::WriteLine("All $script:checks snapshot checks passed under PowerShell $($PSVersionTable.PSVersion).")
