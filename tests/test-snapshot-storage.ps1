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
$ownedConsole=$false;$redirected=$true;$lastSavedReportPath=$null
$script:checks=0;$script:rows=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$root=Join-Path $PSScriptRoot ('test-output-storage-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$report=[ordered]@{'Report info'=@{Computer='TEST';Generated='2026-10-28T12:00:00Z';Version='3.52'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='ID0002'})}
$fixture=[ordered]@{'Report info'=@{Computer='TEST';Generated='2026-10-27T12:00:00Z';Version='3.51'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='ID0001';Name=('CPU '+[char]0x03a9)})}
$json=$fixture | ConvertTo-Json -Depth 8
$encodings=@(
    [Text.UTF8Encoding]::new($false,$true),[Text.UTF8Encoding]::new($true,$true),
    [Text.UnicodeEncoding]::new($false,$true,$true),[Text.UnicodeEncoding]::new($true,$true,$true),
    [Text.UTF32Encoding]::new($false,$true,$true),[Text.UTF32Encoding]::new($true,$true,$true)
)
for($i=0;$i -lt $encodings.Count;$i++){
    $path=Join-Path $root ('encoding-'+$i+' ['+[char]0x03a9+'].json')
    [IO.File]::WriteAllText($path,$json,$encodings[$i])
    $saved=Read-SavedReport $path
    Assert ($saved.CPU[0].Name -ceq $fixture.CPU[0].Name -and $saved.CPU[0].ProcessorId -ceq 'ID0001') ('Encoding '+$i+' preserves literal paths and identifier text')
}
$good=Join-Path $root ('encoding-0 ['+[char]0x03a9+'].json')
$beforeDirectory=[Environment]::CurrentDirectory
Push-Location $root
try{
    [Environment]::CurrentDirectory=$env:SystemRoot
    Assert ((Read-SavedReport (Split-Path -Leaf $good)).CPU[0].ProcessorId -ceq 'ID0001') 'Relative imports resolve against PowerShell location rather than the process working directory'
}finally{Pop-Location;[Environment]::CurrentDirectory=$beforeDirectory}
function Get-ImportFailure($Path){try{Read-SavedReport $Path | Out-Null;throw 'Expected invalid import'}catch{Get-SnapshotFailureInfo $_}}
$badEncoding=Join-Path $root 'bad-encoding.json'
foreach($bom in @($false,$true)){
    $bytes=[byte[]]@(123,34,120,34,58,34,195,40,34,125)
    if($bom){$bytes=[byte[]](@(239,187,191)+$bytes)}
    [IO.File]::WriteAllBytes($badEncoding,$bytes)
    $failure=Get-ImportFailure $badEncoding
    Assert ($failure.Code -eq 'STORE-03' -and $failure.Color -eq 'Error') ('Invalid UTF-8 is rejected without replacement characters; BOM='+$bom)
    $handle=[IO.File]::Open($badEncoding,'Open','ReadWrite','None');$handle.Dispose()
    Assert $true 'A decoding exception releases the file handle'
}
$badUnicode=Join-Path $root 'bad-unicode.json'
[IO.File]::WriteAllBytes($badUnicode,[byte[]]@(255,254,123,0,34))
Assert ((Get-ImportFailure $badUnicode).Code -eq 'STORE-03') 'An incomplete UTF-16 code unit is classified as an encoding failure'
[IO.File]::WriteAllBytes($badUnicode,[byte[]]@(239,187,191,123,195))
Assert ((Get-ImportFailure $badUnicode).Code -eq 'STORE-03') 'A truncated UTF-8 character at end of file is rejected'
[IO.File]::WriteAllBytes($badUnicode,[byte[]]@(255,254,0,216))
Assert ((Get-ImportFailure $badUnicode).Code -eq 'STORE-03') 'An unpaired UTF-16 surrogate at end of file is rejected'
[IO.File]::WriteAllBytes($badUnicode,[byte[]]@(255,254,0,0,123))
Assert ((Get-ImportFailure $badUnicode).Code -eq 'STORE-03') 'An incomplete UTF-32 code unit is rejected'
$locked=Join-Path $root 'locked.json';[IO.File]::WriteAllText($locked,$json)
$lock=[IO.File]::Open($locked,'Open','ReadWrite','None')
try{
    $failure=Get-ImportFailure $locked
    Assert ($failure.Code -eq 'STORE-02' -and $failure.Color -eq 'Warn' -and $failure.Action -match 'refresh') 'A locked snapshot receives a retryable storage warning rather than damaged-JSON text'
    $catalog=Get-SavedSnapshotCatalog @($root) $report
    Assert ($catalog.Entries.Count -eq 6 -and @($catalog.Skipped | Where-Object Code -eq 'STORE-02').Count -eq 1) 'One locked file does not hide readable snapshots in the same folder'
}finally{$lock.Dispose()}
Assert (@((Get-SavedSnapshotCatalog @($root) $report).Entries | Where-Object FullName -eq $locked).Count -eq 1) 'Refreshing discovers a snapshot immediately after it is unlocked'
$large=Join-Path $root 'oversized.json';$handle=[IO.File]::Open($large,'CreateNew','Write','None')
try{$handle.SetLength(64MB+1)}finally{$handle.Dispose()}
$failure=Get-ImportFailure $large
Assert ($failure.Code -eq 'STORE-05' -and $failure.Color -eq 'Warn') 'The size limit is checked on the open handle before reading oversized input'
$handle=[IO.File]::Open($large,'Open','ReadWrite','None');$handle.Dispose()
Assert ((Get-Item -LiteralPath $large).Length -eq 64MB+1) 'Oversized imports release their handle and preserve the original file'
$broken=Join-Path $root 'broken.json';[IO.File]::WriteAllText($broken,'{broken')
Assert ((Get-ImportFailure $broken).Code -eq 'STORE-04') 'Malformed JSON is classified as damaged data'
$future=Join-Path $root 'future.json';[IO.File]::WriteAllText($future,$json.Replace('"3.51"','"9.0"'))
Assert ((Get-ImportFailure $future).Code -eq 'STORE-06') 'Unsupported report versions get a distinct status'
Assert ((Get-ImportFailure (Join-Path $root 'missing.json')).Code -eq 'STORE-02') 'A missing path is an unavailable file rather than damaged JSON'
Assert ((Get-SnapshotFailureInfo ([UnauthorizedAccessException]::new('Denied'))).Code -eq 'STORE-01') 'Permission failures have a specific recovery action'
$pair=[IO.Path]::ChangeExtension($good,'.txt');[IO.File]::WriteAllText($pair,'Readable companion')
$textOnly=Join-Path $root 'notes.TXT';[IO.File]::WriteAllText($textOnly,'Older text report')
[IO.File]::WriteAllText((Join-Path $root 'ignore.json.pending-test'),'pending')
$catalog=Get-SavedSnapshotCatalog @($root,$root) $report
Assert ($catalog.Entries.Count -eq 7 -and $catalog.TextOnly.Count -eq 1 -and $catalog.Skipped.Count -eq 5) 'Library counts JSON, pending files, TXT-only files and failures separately without duplicate paths'
Assert (@($catalog.Entries | Where-Object TextAvailable -eq $true).Count -eq 1) 'A valid JSON without TXT remains comparable; pairs are counted separately'
foreach($case in @(@('OLDER','Good'),@('SAME CAPTURE TIME','Muted'),@('NEWER','Warn'),@('TIME UNKNOWN','Warn'),@('OLDER / OTHER OR UNKNOWN PC','Warn'),@('OLDER / NO USABLE IDs','Warn'))){
    Assert ((Get-SnapshotDisplayInfo ([pscustomobject]@{Relation=$case[0]})).Color -eq $case[1]) ('Snapshot color explains '+$case[0])
}
function Get-ReportLocations {[pscustomobject]@{Primary=$root;Search=@($root)}}
function Write-PnpValue {param($Label,$Value,$Color) $script:rows.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
Show-SnapshotStorage
Assert (@($script:rows | Where-Object {$_.Label -eq 'Storage check' -and $_.Color -eq 'Red' -and $_.Value -match '5 files/folders not read / 1 TXT only'}).Count -eq 1) 'Storage summary uses red for invalid data and reports exact counts'
Assert (@($script:rows | Where-Object {$_.Label -eq 'JSON snapshots' -and $_.Color -eq 'Green' -and $_.Value -match '7 readable / 7 older'}).Count -eq 1) 'Storage summary identifies usable older baselines clearly'
Assert (@($script:rows | Where-Object {$_.Label -like 'STORE-05*' -and $_.Color -eq 'Yellow'}).Count -eq 1) 'Individual retry/context warnings remain yellow within a red overall summary'
$script:rows.Clear()
function Start-Process {param($FilePath,$ArgumentList) throw 'Synthetic Explorer failure'}
Show-SnapshotStorage -OpenFolder
Assert (@($script:rows | Where-Object Label -eq 'STORE-08 / folder not opened').Count -eq 1 -and @($script:rows | Where-Object Label -eq 'JSON snapshots').Count -eq 1) 'Explorer failure does not lose storage results'
$blocked=Join-Path $root 'protected'
function Get-ReportLocations {[pscustomobject]@{Primary=$blocked;Search=@($blocked,$root)}}
function Test-Path {param($LiteralPath,$PathType) if($LiteralPath -eq $blocked){throw [UnauthorizedAccessException]::new('Synthetic permission denial')};Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType}
$script:rows.Clear();Show-SnapshotStorage -OpenFolder
Assert (@($script:rows | Where-Object Label -eq 'Access unavailable').Count -eq 1 -and @($script:rows | Where-Object {$_.Label -like 'STORE-01*' -and $_.Color -eq 'Yellow'}).Count -eq 1) 'An inaccessible folder has an access warning while other locations remain usable'
Assert (@($script:rows | Where-Object {$_.Label -eq 'JSON snapshots' -and $_.Value -match '7 readable'}).Count -eq 1) 'A blocked primary location does not hide fallback snapshots'
[Console]::WriteLine("All $script:checks snapshot-storage checks passed under PowerShell $($PSVersionTable.PSVersion).")
