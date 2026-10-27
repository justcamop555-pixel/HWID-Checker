$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\hwid.bat'
$raw = [IO.File]::ReadAllText($source)
$code = ($raw -split '(?m)^# POWERSHELL_START\r?$', 2)[1]
$interactiveTestCode=$code.Replace('Read-CheckerLine ', 'Read-Host ')
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join '; ') }
foreach ($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
. ([scriptblock]::Create($code.Substring(0, $code.IndexOf('function Write-Heading'))))
$identifierPattern = '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$script:checks = 0
function Assert($Condition, $Description) {
    if (-not $Condition) { throw "FAILED: $Description" }
    $script:checks++
    [Console]::WriteLine("PASS: $Description")
}
$script:rendered = New-Object 'System.Collections.Generic.List[object]'
function Write-Host { param([Parameter(ValueFromPipeline=$true)]$Object, $ForegroundColor, [switch]$NoNewline) process { $script:rendered.Add([pscustomobject]@{Text=[string]$Object;Color=[string]$ForegroundColor}) } }
Assert ((Get-Quality '') -eq 'Missing') 'Blank identifier is missing'
Assert ((Get-Quality '00:00:00:00:00:00') -eq 'Placeholder') 'Zero MAC is a placeholder'
Assert ((Get-Quality '{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}') -eq 'Placeholder') 'Braced all-F UUID is a placeholder'
Assert ((Get-Quality 'ABC123') -eq 'Reported') 'Ordinary serial is reported'
$sample = [ordered]@{
    'Report info' = [ordered]@{ Version='3.2'; Computer='TEST'; Generated='test' }
    'Memory modules' = @(
        [pscustomobject]@{DeviceLocator='Slot A'; BankLabel='Bank 0'; SerialNumber='111'},
        [pscustomobject]@{DeviceLocator='Slot B'; BankLabel='Bank 1'; SerialNumber='222'}
    )
    Warnings = @()
}
$rows = @(Get-IdentifierRows $sample)
Assert ($rows.Count -eq 2 -and $rows[0].Device -match 'Slot A') 'Identifiers retain device location'
$imported = $sample | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$before = @(Get-ComparisonKeys $rows | Sort-Object)
$after = @(Get-ComparisonKeys @(Get-IdentifierRows $imported) | Sort-Object)
Assert (@(Compare-Object $before $after).Count -eq 0) 'JSON round trip has no false differences'
$imported.'Memory modules'[0].SerialNumber = '222'
$imported.'Memory modules'[1].SerialNumber = '111'
$after = @(Get-ComparisonKeys @(Get-IdentifierRows $imported) | Sort-Object)
Assert (@(Compare-Object $before $after).Count -eq 4) 'Swapped device serials are detected'
$after = @(Get-ComparisonKeys @($rows[1], $rows[0]) | Sort-Object)
Assert (@(Compare-Object $before $after).Count -eq 0) 'Enumeration order does not change comparison'
$duplicate = @($before[0], $before[0], $before[1])
Assert (@(Compare-Object $before $duplicate).Count -eq 1) 'Duplicate identifier counts are preserved'
$upper = @(Get-ComparisonKeys @([pscustomobject]@{Section='CPU';Device='CPU0';Field='ProcessorId';Value='ABC'}))
$lower = @(Get-ComparisonKeys @([pscustomobject]@{Section='CPU';Device='CPU0';Field='ProcessorId';Value='abc'}))
Assert (@(Compare-Object $upper $lower -CaseSensitive).Count -eq 2) 'Case-only identifier changes are detected'
Assert ((Format-ComparisonKey $upper[0]) -eq '[CPU] CPU identifier (CPU0): ABC') 'Comparison keys display readable device labels'
$testFolder = Join-Path $PSScriptRoot ('test-output-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testFolder | Out-Null
$env:HWID_SCRIPT = Join-Path $testFolder 'hwid.bat'
$report = $sample
Save-Reports
$exportFolder = Join-Path $testFolder 'HWID-Reports'
$jsonFiles = @(Get-ChildItem -LiteralPath $exportFolder -Filter '*.json')
Assert ($jsonFiles.Count -eq 1) 'JSON report saved'
$saved = Read-SavedReport $jsonFiles[0].FullName
Assert ($saved.'Memory modules'.Count -eq 2) 'Saved report loads with devices intact'
$saved.'Report info'.Version = '2.0'
$legacyPath = Join-Path $testFolder 'legacy-v2.json'
$saved | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyPath -Encoding UTF8
Assert (@(Get-IdentifierRows (Read-SavedReport $legacyPath)).Count -eq 2) 'Version 2 reports remain compatible'
$textFile = @(Get-ChildItem -LiteralPath $exportFolder -Filter '*.txt')[0]
Assert (-not ([IO.File]::ReadAllText($textFile.FullName).Contains([string][char]27))) 'Plain text export has no ANSI colors'
Assert ([IO.File]::ReadAllText($textFile.FullName).Contains('CPU & MEMORY')) 'Text export uses hardware category headings'
Show-Records @([pscustomobject]@{SerialNumber='ABC123';UUID='';ProcessorId='To be filled by O.E.M.'})
Assert (@($script:rendered | Where-Object { $_.Text.EndsWith('ABC123 [Found]') -and $_.Color -eq $palette.Good }).Count -gt 0) 'Reported identifiers use the success color'
Assert (@($script:rendered | Where-Object { $_.Text.EndsWith('(not provided) [Not supplied]') -and $_.Color -eq $palette.Warn }).Count -gt 0) 'Missing identifiers use warning color and text label'
$utf8Path = Join-Path $testFolder 'unicode.json'
$sample['Report info'].Computer = 'PC-' + [char]0x00E9
$utf8 = $sample | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($utf8Path, $utf8, (New-Object Text.UTF8Encoding($false)))
Assert ((Read-SavedReport $utf8Path).'Report info'.Computer -eq $sample['Report info'].Computer) 'UTF-8 without BOM imports correctly'
$badPath = Join-Path $testFolder 'invalid.json'
[IO.File]::WriteAllText($badPath, '{"Report info":{"Version":"99.0"}}')
$rejected = $false
try { Read-SavedReport $badPath | Out-Null } catch { $rejected = $true }
Assert $rejected 'Unsupported report is rejected'
# Exercise the entire script without reading or exporting real device identifiers.
function Get-CimInstance { param($ClassName,$Filter,$OperationTimeoutSec) if($ClassName -eq 'MSFT_Disk'){throw 'Simulated access denied'}; if($ClassName -eq 'MSFT_Partition'){return [pscustomobject]@{DiskNumber=0;PartitionNumber=1;Guid='PARTITION-TEST';AccessPaths=@('VOLUME-TEST');Size=1GB}}; [pscustomobject]@{SerialNumber='MOCK'; DeviceID='MOCK'; UUID='MOCK'; TotalPhysicalMemory=8GB} }
function Get-Disk { throw 'Simulated access denied' }
function Get-Partition { [pscustomobject]@{DiskNumber=0;PartitionNumber=1;Guid='PARTITION-TEST';AccessPaths=@('VOLUME-TEST');Size=1GB} }
function Get-NetAdapter { param([switch]$IncludeHidden) [pscustomobject]@{Name='MOCK'; MacAddress='00:00:00:00:00:00'; InterfaceGuid='MOCK'} }
function Get-ItemProperty { param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='MOCK'} }
function Start-Process { param($FilePath,$ArgumentList) throw 'Simulated Explorer failure' }
$script:answers = New-Object 'System.Collections.Generic.Queue[string]'
@(' 1 ', '2', '', '3', '1', '3', '2', '3', '3', '3', '4', '3', '5', '3', '0', '3', 'invalid', '0', '4', '5', '6', '7', $badPath, '7', '', '8', '9', '2', '0') | ForEach-Object { $script:answers.Enqueue($_) }
function Read-Host { param($Prompt) if (-not $script:answers.Count) { throw 'Unexpected prompt / possible menu loop' }; $script:answers.Dequeue() }
. ([scriptblock]::Create($interactiveTestCode))
Assert ($script:answers.Count -eq 0) 'Menu survives invalid report, cancel, unavailable query, and Explorer failure'
Assert ($warnings.Count -eq 1) 'Failed query is isolated to its section'
Assert ($report.Contains('PnP hardware IDs') -and (Test-SectionReadable $report['PnP hardware IDs'])) 'All present PnP IDs are scanned automatically at startup'
Assert ($report.Contains('Disk partitions') -and $report['Disk partitions'][0].PartitionGuid -eq 'PARTITION-TEST') 'Partition GUIDs are included in the startup inventory'
Assert ($report.Contains('Monitors')) 'Monitor identification is included in the startup inventory'
Assert ($report['Scan timing'].Count -eq 17 -and @($report['Scan timing'] | Where-Object {$_.Seconds -lt 0}).Count -eq 0) 'Startup retains per-section timing for all seventeen queries'
Assert ($report['Report info'].ScanSeconds -ge 0 -and $report['Report info'].ScanCompleted) 'Report metadata records scan completion and total elapsed time'


Assert (@($script:rendered | Where-Object Text -match '\[17/17\]').Count -eq 1) 'Progress displays all seventeen scan sections'
Assert (@($script:rendered | Where-Object Text -match 'SCAN OVERVIEW').Count -ge 2) 'Overview displays after scan and from the menu'
Assert (@($script:rendered | Where-Object Text -match 'HELP & COLOR KEY').Count -eq 1) 'Help and color key are accessible'
Assert (@($sectionGroups.Values | ForEach-Object { $_ }).Count -eq 16) 'Category organization covers sixteen categorized hardware sections'
Assert ($null -eq (GiB $null)) 'Unreadable capacity stays missing instead of becoming zero'
Assert ((GiB 0) -eq 0) 'A real zero capacity stays zero'
Assert ((Get-FieldQuality 'Guid' '00000000-0000-0000-0000-000000000000' ([pscustomobject]@{PartitionStyle='MBR'})) -eq 'Not applicable') 'MBR disk does not need a GPT disk ID'
Assert ((Get-FieldQuality 'Guid' '' ([pscustomobject]@{PartitionStyle='GPT'})) -eq 'Missing') 'Missing GPT disk ID still gets flagged'
Assert ((Get-FieldQuality 'Guid' '' ([pscustomobject]@{PartitionStyle=2})) -eq 'Missing') 'Legacy numeric GPT disk format remains supported'
$mbr = [ordered]@{'Storage identifiers'=@([pscustomobject]@{Number=0;PartitionStyle='MBR';Guid='00000000-0000-0000-0000-000000000000';SerialNumber='REAL123'})}
Assert (@(Get-IdentifierRows $mbr).Count -eq 1) 'Inapplicable GPT IDs do not inflate review counts'
Assert ((Get-FieldLabel 'ConfiguredClockSpeed') -eq 'Configured speed (MHz)') 'Memory speed label includes its unit'
Assert ((Format-FieldValue $false) -eq 'No') 'Boolean values use plain language'
Assert ((Format-FieldValue @(1,2,3,4,5,6)) -eq '1, 2, 3, 4, 5, 6') 'Long arrays are not truncated in text reports'
$malformedPath = Join-Path $testFolder 'malformed-section.json'
[IO.File]::WriteAllText($malformedPath, '{"Report info":{"Version":"3.4"},"CPU":"not a device object"}')
$rejected = $false
try { Read-SavedReport $malformedPath | Out-Null } catch { $rejected = $true }
Assert $rejected 'Malformed hardware sections are rejected'
Section 'Date test' { [pscustomobject]@{ReleaseDate=[datetime]'2026-10-24T12:00:00'} }
Assert ($report['Date test'][0].ReleaseDate -is [string] -and $report['Date test'][0].ReleaseDate -match '^2026-10-24T12:00:00') 'Dates are normalized before JSON export'
$currentReportPath = (Get-ChildItem -LiteralPath $exportFolder -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$script:answers.Enqueue('7')
$script:answers.Enqueue($currentReportPath)
$script:answers.Enqueue('0')
. ([scriptblock]::Create($interactiveTestCode))
Assert (@($script:rendered | Where-Object { $_.Text -match 'No differences found in available data' -and $_.Color -eq $palette.Warn }).Count -gt 0) 'Identical incomplete reports show a caution instead of an all-clear'
$good = [ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='REAL123'});Motherboard=@([pscustomobject]@{SerialNumber='BOARD123'})}
$denied = [ordered]@{CPU=@{Unavailable='Access denied'};Motherboard=@([pscustomobject]@{SerialNumber='BOARD123'})}
$result = Compare-Inventories $good $denied
Assert ($result.Changes.Count -eq 0 -and 'CPU' -in $result.SkippedSections) 'Unreadable section does not appear as removed hardware'
$blank = [ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId=''});Motherboard=@([pscustomobject]@{SerialNumber='BOARD123'})}
$result = Compare-Inventories $good $blank
Assert ($result.Changes.Count -eq 0 -and $result.SkippedFields -eq 1) 'Unreadable field does not appear as an ID change'
$changed = [ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CHANGED'});Motherboard=@([pscustomobject]@{SerialNumber='BOARD123'})}
Assert ((Compare-Inventories $good $changed).Changes.Count -eq 2) 'Real identifier changes remain detected'
$twoDevices = [ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='REAL123'},[pscustomobject]@{DeviceID='CPU1';ProcessorId='SECOND'})}
$oneDevice = [ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='REAL123'})}
Assert ((Compare-Inventories $twoDevices $oneDevice).Changes.Count -eq 1) 'Removed device in a readable section remains detected'
Assert (Test-SectionReadable $twoDevices.CPU) 'Multiple device records do not falsely mark a section unavailable'
Assert (-not (Test-SectionReadable @(@{Unavailable='Denied'}))) 'Unavailable marker is recognized'
Assert ((Get-CanonicalIdentifier 'MacAddress' 'aa:bb:cc:dd:ee:12') -eq (Get-CanonicalIdentifier 'MacAddress' 'AA-BB-CC-DD-EE-12')) 'MAC separator and case changes do not create false differences'
Assert ((Get-CanonicalIdentifier 'UUID' '{AB123456-1234-5678-ABCD-123456789012}') -eq (Get-CanonicalIdentifier 'UUID' 'ab12345612345678abcd123456789012')) 'Equivalent GUID formats compare equally'
Assert ((Get-CanonicalIdentifier 'SerialNumber' 'abc') -cne (Get-CanonicalIdentifier 'SerialNumber' 'ABC')) 'Serial number case is preserved'
Assert ((Get-FieldQuality 'PermanentAddress' '' ([pscustomobject]@{HardwareInterface=$false})) -eq 'Not applicable') 'Virtual adapter without permanent MAC is not a missing-ID warning'
Assert ((Get-FieldQuality 'PermanentAddress' '' ([pscustomobject]@{HardwareInterface=$true})) -eq 'Missing') 'Missing physical adapter MAC remains visible'
$script:answers.Enqueue('')
$script:answers.Enqueue('0')
. ([scriptblock]::Create($interactiveTestCode))
Assert ($script:answers.Count -eq 0) 'Blank main-menu input retries and explicit zero exits'
$quickFixture = [ordered]@{
    'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='DRIVE123';PNPDeviceID='LONG DEVICE PATH'})
    'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='DRIVE123';UniqueId='LONG STORAGE ID'})
    'Memory modules'=@([pscustomobject]@{DeviceLocator='A1';SerialNumber='RAM123'},[pscustomobject]@{DeviceLocator='B1';SerialNumber='RAM456'})
}
$quickRows = @(Get-QuickIds $quickFixture)
Assert (@($quickRows | Where-Object Label -eq 'Disk 0').Count -eq 1) 'Quick view shows a disk serial only once'
Assert (@($quickRows | Where-Object Value -match 'LONG').Count -eq 0) 'Quick view omits verbose device paths'
Assert (@($quickRows | Where-Object Label -like 'RAM *').Count -eq 2) 'Quick view keeps separate memory slots'
$quickFixture['Physical disks'] = @{Unavailable='Denied'}
Assert (@(Get-QuickIds $quickFixture | Where-Object Value -eq 'DRIVE123').Count -eq 1) 'Quick view uses fallback disk serials when needed'
Assert ((Limit-TableText '12345678901234567890' 10) -eq '1234567...') 'Long table values are visibly shortened'
Assert ((Limit-TableText 'ABC123' 36) -eq 'ABC123') 'Short identifiers are shown completely'
$report = $quickFixture
$script:rendered.Clear()
Show-QuickIds
Assert (@($script:rendered | Where-Object Text -match '^OK\*?$').Count -eq 3) 'Quick view uses short OK status labels'
Assert (@($script:rendered | Where-Object Text -match 'All details / full IDs').Count -eq 1) 'Quick view links to complete identifiers'
$diskFixture = [ordered]@{
    'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber=''})
    'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='ALT123'})
}
$diskRows = @(Get-QuickDisks $diskFixture)
Assert ($diskRows.Count -eq 1 -and $diskRows[0].Value -eq 'ALT123' -and $diskRows[0].Note -eq 'Alternate source') 'Per-disk fallback fills missing serial without adding a duplicate'
Assert ($diskFixture['Physical disks'][0].SerialNumber -eq '') 'Quick fallback leaves original report values untouched'
$diskFixture['Physical disks'][0].SerialNumber = 'PRIMARY123'
$diskRows = @(Get-QuickDisks $diskFixture)
Assert ($diskRows.Count -eq 1 -and $diskRows[0].Quality -eq 'Conflict' -and $diskRows[0].Value -eq 'PRIMARY123 / ALT123') 'Conflicting serial sources are identified explicitly'
$diskFixture['Storage identifiers'] += [pscustomobject]@{Number=1;SerialNumber='EXTRA456'}
Assert (@(Get-QuickDisks $diskFixture).Count -eq 2) 'Disks present only in alternate provider remain visible'
foreach ($width in @(32,40,48,60,80,120)) {
    $layout = Get-QuickLayout $width
    Assert ($layout.LabelWidth + $layout.ValueWidth + 13 -lt $width) "Table columns fit width $width"
}
Assert ((Limit-TableText 'ABCDE' 2) -eq '..') 'Tiny truncation widths do not throw'
$report=$diskFixture
$identifiers=@(Get-IdentifierRows $report)
$warnings=New-Object 'System.Collections.Generic.List[string]'
$script:rendered.Clear()
Show-Attention
Assert (@($script:rendered | Where-Object Text -match '\[SOURCE CLASH\]').Count -eq 1) 'Review screen includes source conflicts'
Assert (Test-ReadableLaunchNeeded $false $false '') 'Interactive launch requests the dedicated display'
Assert (-not (Test-ReadableLaunchNeeded $true $false '')) 'Redirected input/output stays in its current process'
Assert (-not (Test-ReadableLaunchNeeded $false $true '')) 'Owned console guard prevents relaunch loops'
Assert (-not (Test-ReadableLaunchNeeded $false $false '--current-window')) 'Current-window opt-out is honored'
$launchPlan=Get-ReadableLaunchPlan 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$loader=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($launchPlan.EncodedLoader))
$loaderTokens=$null; $loaderErrors=$null
[System.Management.Automation.Language.Parser]::ParseInput($loader,[ref]$loaderTokens,[ref]$loaderErrors) | Out-Null
Assert ($loaderErrors.Count -eq 0 -and $loader.Contains("HWID_OWN_CONSOLE = '1'")) 'Encoded loader parses correctly and sets the loop guard'
Assert ($loader.Contains('$env:HWID_SCRIPT') -and $launchPlan.Arguments.StartsWith('-ForceNoHandoff -- "')) 'Launcher carries script paths through environment and avoids Terminal handoff'
Assert (-not ($loader -match 'Verb\s+RunAs' -or $launchPlan.Arguments -match 'Verb\s+RunAs')) 'Readable mode does not request elevation'
Assert (-not (Initialize-ReadableConsole $true $true).FontApplied) 'Redirected execution does not change display settings'
Assert (-not (Start-ReadableConsole $source $false $false '')) 'Host startup failure falls back to the existing window'
$entries=@(Get-MenuEntries)
Assert ($entries.Count -eq 5 -and @($entries | Where-Object Count -ne 4).Count -eq 0) 'Control deck has five complete two-column menu rows'
$keys=@($entries | ForEach-Object { $_[0]; $_[2] } | Sort-Object)
Assert (($keys -join '') -eq '0123456789') 'All ten menu keys appear exactly once'
$script:rendered.Clear()
Show-ControlDeck
Assert (@($script:rendered | Where-Object Text -match 'MAIN MENU / HWID CHECKER').Count -eq 1) 'Control deck includes a framed page title'
Assert (@($script:rendered | Where-Object Text -match 'HWID CHECKER  /').Count -eq 1) 'New dashboard includes the system console header'
Assert (@($script:rendered | Where-Object Color -eq $palette.Error).Count -eq 0) 'Informational dashboard is not colored as an error'
$priorOwned=$ownedConsole; $priorRedirected=$redirected
$ownedConsole=$true; $redirected=$false
Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
Assert ($script:answers.Count -eq 0) 'Owned-console result pages wait for Enter before clearing'
$redirected=$true
Wait-UiPage
Assert ($script:answers.Count -eq 0) 'Redirected execution does not add result-page prompts'
$ownedConsole=$priorOwned; $redirected=$priorRedirected
foreach($digit in @('0','1','2','3','4','5','6','7','8','9')) {
    Assert ((Read-MenuChoice -Reader { $digit }) -ceq $digit) "Main menu accepts digit $digit"
}
$script:menuInputs=New-Object 'System.Collections.Generic.Queue[string]'
@('fgsdv235','10','-1','1.5','',' ',([string][char]0xFF11),'1x',' 7 ') | ForEach-Object {$script:menuInputs.Enqueue($_)}
$script:rendered.Clear()
$selected=Read-MenuChoice -Reader { $script:menuInputs.Dequeue() }
Assert ($selected -eq '7' -and $script:menuInputs.Count -eq 0) 'Invalid menu input retries immediately until one digit is entered'
Assert (@($script:rendered | Where-Object { $_.Text -match '\[INPUT-01\]' -and $_.Color -eq $palette.Error }).Count -eq 1) 'Repeated invalid input shows one custom error instead of flooding output'
Assert (@($script:rendered | Where-Object Text -match 'Enter = control deck').Count -eq 0) 'Invalid menu input never asks for an extra return confirmation'
Assert (@($script:rendered | Where-Object Text -match 'fgsdv235').Count -eq 0) 'Custom input error does not repeat arbitrary input'
$script:rendered.Clear()
Assert ($null -eq (Read-MenuChoice -Reader { return $null })) 'End of input exits cleanly'
Assert ($script:rendered.Count -eq 0) 'End of input does not trigger an endless error loop'
$script:keys=New-Object 'System.Collections.Generic.Queue[System.ConsoleKeyInfo]'
for($repeat=0;$repeat -lt 2000;$repeat++) {$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))}
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]'2',[ConsoleKey]::D2,$false,$false,$false)))
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
$script:rendered.Clear()
$timer=[Diagnostics.Stopwatch]::StartNew()
$typed=Read-MenuKeyboard -KeyReader {$script:keys.Dequeue()}
$timer.Stop()
Assert ($typed -eq '2' -and $script:keys.Count -eq 0) 'Two thousand held-Enter events are ignored and the next digit still works'
Assert ($script:rendered.Count -eq 3) 'Held Enter produces zero redraws and zero repeated prompt output'
[Console]::WriteLine("Held-Enter simulation: 2000 events in $($timer.ElapsedMilliseconds) ms; $($script:rendered.Count) total output calls.")
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]'1',[ConsoleKey]::D1,$false,$false,$false)))
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]8,[ConsoleKey]::Backspace,$false,$false,$false)))
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]'9',[ConsoleKey]::D9,$false,$false,$false)))
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
Assert ((Read-MenuKeyboard -KeyReader {$script:keys.Dequeue()}) -eq '9') 'Backspace editing still works in the menu keyboard reader'
for($repeat=0;$repeat -lt 100;$repeat++){$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]' ',[ConsoleKey]::Spacebar,$false,$false,$false)))}
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]'3',[ConsoleKey]::D3,$false,$false,$false)))
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
Assert ((Read-MenuKeyboard -KeyReader {$script:keys.Dequeue()}) -eq '3') 'Leading whitespace repeats cannot fill and lock the input buffer'
foreach($character in ('1'+(' '*31)+'x').ToCharArray()){$script:keys.Enqueue((New-Object ConsoleKeyInfo($character,[ConsoleKey]::A,$false,$false,$false)))}
$script:keys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
Assert ((Read-MenuKeyboard -KeyReader {$script:keys.Dequeue()}) -eq '[input too long]') 'Input overflow is rejected instead of truncating into a valid menu digit'
foreach($width in @(32,48,80,100)) {
    $layout=Get-MenuInputLayout $width 20 10 1000
    Assert ($layout.Top -eq 28 -and $layout.PromptRow -eq 29 -and $layout.Width -eq $width-1) "Input area fits resized viewport width $width"
    $lines=Get-MenuInputLines $layout.Width ('X'*32) '[INPUT-01] Invalid option. Type one digit: 0-9.'
    Assert ($lines.Status.Length -eq $layout.Width -and $lines.Prompt.Length -eq $layout.Width -and $lines.Cursor -lt $layout.Width) "Input rows never wrap at width $width"
}
Assert (-not (Get-MenuInputLayout 7 1 0 20).Enabled) 'Unsupported tiny viewports disable cursor positioning safely'
$lines=Get-MenuInputLines 31 ([string][char]0xFF11) ''
Assert ($lines.Prompt.Contains('?') -and $lines.Prompt -notmatch ([string][char]0xFF11)) 'Wide Unicode lookalikes cannot shift the fixed input columns'
Assert ((Get-ReportHistoryRows 34 10) -eq 34) 'Short pages have no excess scrollbar history'
Assert ((Get-ReportHistoryRows 34 150) -eq 153) 'Long reports keep only actual text and prompt space'
Assert ((Get-ReportScrollTop 'PageDown' 0 34 153) -eq 33) 'PageDown advances by a visible page'
Assert ((Get-ReportScrollTop 'PageUp' 10 34 153) -eq 0) 'PageUp clamps to report start'
Assert ((Get-ReportScrollTop 'End' 0 34 153) -eq 119) 'End reaches last report viewport'
Assert ((Get-ReportScrollTop 'DownArrow' 119 34 153) -eq 119) 'Scrolling cannot go beyond report content'
Assert ((Get-ReportScrollTop 'UpArrow' 0 34 34) -eq 0) 'Dashboard without history stays at its only viewport'
$script:driverFixture=@(
    [pscustomobject]@{Name='Test USB';Manufacturer='Test';PNPClass='USB';PNPDeviceID='USB\TEST\DEVICE';HardwareID=@('USB\MODEL_A','USB\MODEL_B');CompatibleID=@('USB\CLASS_00');ConfigManagerErrorCode=0},
    [pscustomobject]@{Name='Test GPU';Manufacturer='Test';PNPClass='Display';PNPDeviceID='PCI\GPU\DEVICE';HardwareID=@('PCI\GPU_MODEL');CompatibleID=@();ConfigManagerErrorCode=0}
)
$script:pnpReadCalls=0
function Get-CimInstance { param($ClassName,$Filter,$OperationTimeoutSec) $script:pnpReadCalls++; $script:lastPnpFilter=$Filter; $script:driverFixture }
$details=@(Get-DriverHardwareIds)
Assert ($script:lastPnpFilter -eq 'Present = True') 'Full PnP query includes all present device classes'
Assert ($details.Count -eq 2 -and $details[0].PNPClass -eq 'Display') 'Deep hardware details are sorted and grouped by device class'
Assert ($details[1].DeviceInstanceId -eq 'USB\TEST\DEVICE' -and $details[1].HardwareID.Count -eq 2) 'Hardware IDs remain separate from the device instance ID'
$report=[ordered]@{'Report info'=[ordered]@{Version='3.14';Computer='TEST';Generated='test'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='REAL123'});Warnings=@()}
$warnings=New-Object 'System.Collections.Generic.List[string]'
$baseKeys=@(Get-ComparisonKeys @(Get-IdentifierRows $report))
$script:pnpReadCalls=0
Show-DriverHardwareIds
Show-DriverHardwareIds
Assert ($script:pnpReadCalls -eq 2) 'Deep IDs refresh on each visit to reflect changed devices'
Assert (@(Compare-Object $baseKeys @(Get-ComparisonKeys @(Get-IdentifierRows $report))).Count -eq 0) 'Driver IDs do not alter the machine-identifier comparison'
Save-Reports
$latestJson=Get-ChildItem -LiteralPath $exportFolder -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$savedDeep=Read-SavedReport $latestJson.FullName
Assert ($savedDeep.'PnP hardware IDs'.Count -eq 2 -and $savedDeep.'PnP hardware IDs'[1].HardwareID.Count -eq 2) 'Saved reports retain complete optional hardware-ID arrays'
$script:driverFixture=@($script:driverFixture[0])
Show-DriverHardwareIds
Assert ($report['PnP hardware IDs'].Count -eq 1) 'Refreshing deep IDs removes devices that are no longer returned'
$report.Remove('PnP hardware IDs')
function Get-CimInstance { param($ClassName,$Filter,$OperationTimeoutSec) throw 'Simulated PnP access denied' }
Show-DriverHardwareIds
Assert ($report['PnP hardware IDs'].Unavailable -and $report['Warnings'].Count -eq 1) 'Unavailable deep IDs produce a readable warning without stopping the checker'
foreach($direction in @('Next','Back','Exit')) {
    $first=Get-UiTransitionFrame $direction 0 80
    $last=Get-UiTransitionFrame $direction 7 80
    Assert ($first -ne $last) ("$direction transition has distinct start and end frames")
    Assert ((Get-UiTransitionFrame $direction 4 12).Length -le 12) ("$direction transition fits narrow windows")
}
Assert ((Get-UiTransitionFrame 'Next' 0 80) -match '\[>>') 'Next sweep starts on the left'
Assert ((Get-UiTransitionFrame 'Back' 0 80) -match '<<\]') 'Back sweep starts on the right'
$renderedBefore=$script:rendered.Count
$ownedConsole=$false; $redirected=$false
Show-UiTransition 'Next'
Assert ($script:rendered.Count -eq $renderedBefore) 'External console skips animation output'
$ownedConsole=$true; $redirected=$true
Show-UiTransition 'Exit'
Assert ($script:rendered.Count -eq $renderedBefore) 'Redirected output skips animation output'
$ownedConsole=$false; $redirected=$true
$script:answers.Enqueue('0')
Assert (-not (Show-Categories)) 'Category Back returns directly without a report pause'
$script:answers.Enqueue('invalid');$script:answers.Enqueue('1')
Assert (Show-Categories) 'Invalid category keeps the picker open until a valid selection'
$script:answers.Enqueue('');$script:answers.Enqueue('0')
Assert (-not (Show-Categories)) 'Empty category input is ignored until explicit Back'
$script:answers.Enqueue('')
$redirected=$false
Wait-UiPage
Assert ($script:answers.Count -eq 0) 'Current-window pages pause so their output can be read'
$redirected=$true
Show-DriverHardwareIds
Assert ($warnings.Count -eq 1) 'Repeated deep-ID failures keep one current warning'
function Get-CimInstance { param($ClassName,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Recovered';PNPDeviceID='USB\RECOVERED';HardwareID=@('USB\MODEL');PNPClass='USB'} }
Show-DriverHardwareIds
Assert ((Test-SectionReadable $report['PnP hardware IDs']) -and $report['PnP hardware IDs'][0].Name -eq 'Recovered') 'Failed deep-ID query is retried and can recover'
Assert ($warnings.Count -eq 0 -and $report['Warnings'].Count -eq 0) 'Recovery removes stale deep-ID warnings from screen and export'
Assert ((Get-PnpStatus $null).Quality -eq 'Unknown') 'Missing device status is not incorrectly reported as working'
Assert ((Get-PnpStatus '').Quality -eq 'Unknown') 'Empty device status remains unknown'
Assert ((Get-PnpStatus 0).Text -eq 'Working (code 0)') 'Working device status has a readable label'
Assert ((Get-PnpStatus 22).Text -eq 'Disabled (code 22)') 'Disabled devices are identified without claiming an ID conflict'
Assert ((Get-PnpStatus 28).Text -eq 'Driver not installed (code 28)') 'Missing driver has a readable explanation'
Assert ((Get-PnpStatus 12).Text -match 'Resource conflict') 'Actual Windows resource conflicts are identified'
Assert ((Get-PnpStatus 999).Text -eq 'Device issue (code 999)') 'Unmapped status codes retain their numeric value'
$usbKeyboard=[pscustomobject]@{Name='Keyboard';PNPClass='HIDClass';DeviceInstanceId='USB\VID_TEST\KEYBOARD';HardwareID=@('USB\MODEL','USB\GENERAL');CompatibleID=@('USB\CLASS');ConfigManagerErrorCode=0}
Assert ((Get-PnpGroup $usbKeyboard) -eq 'INPUT') 'USB input devices are grouped by function rather than their transport'
foreach($entry in @(@('Camera','CAMERAS'),@('MEDIA','AUDIO'),@('Bluetooth','BLUETOOTH'),@('Keyboard','INPUT'),@('Mouse','INPUT'))) {
    Assert ((Get-PnpGroup ([pscustomobject]@{PNPClass=$entry[0];DeviceInstanceId='USB\VID_TEST\DEVICE'})) -eq $entry[1]) ('USB function grouping retains '+$entry[0])
}
Assert ((Get-PnpGroup ([pscustomobject]@{PNPClass=$null;DeviceInstanceId='USB\VID_TEST\DEVICE'})) -eq 'USB') 'Unclassified USB nodes remain visible in USB fallback'
Assert ((Get-PnpGroup ([pscustomobject]@{PNPClass=$null;DeviceInstanceId='USBSTOR\DISK'})) -eq 'OTHER DEVICES') 'USB bus fallback requires the complete enumerator name'
$unknownDevice=[pscustomobject]@{Name='Unknown device';PNPClass=$null;DeviceInstanceId='PCI\UNKNOWN';ConfigManagerErrorCode=28}
Assert ((Get-PnpGroup $unknownDevice) -eq 'OTHER DEVICES') 'Unclassified problem devices remain visible'
$anotherKeyboard=[pscustomobject]@{Name='Keyboard 2';PNPClass='HIDClass';DeviceInstanceId='USB\VID_TEST\KEYBOARD2';HardwareID=@('USB\MODEL');ConfigManagerErrorCode=0}
Assert (@(Get-PnpIssues @($usbKeyboard,$anotherKeyboard)).Count -eq 0) 'Shared hardware-model IDs are not treated as conflicts'
$duplicateKeyboard=[pscustomobject]@{Name='Duplicate entry';PNPClass='HIDClass';DeviceInstanceId='usb\vid_test\keyboard';ConfigManagerErrorCode=0}
Assert (@(Get-PnpIssues @($usbKeyboard,$duplicateKeyboard) | Where-Object Kind -eq 'Duplicate').Count -eq 1) 'Duplicate instance IDs are detected without case-sensitive false negatives'
Assert (@(Get-PnpIssues @($unknownDevice)).Count -eq 1) 'Nonzero device status appears in review issues'
$script:rendered.Clear()
Show-PnpRecords @($usbKeyboard,$unknownDevice)
Assert (@($script:rendered | Where-Object Text -match 'INPUT / 1 device').Count -eq 1) 'Compact deep view has function category headings and counts'
Assert (@($script:rendered | Where-Object Text -match 'USB\\GENERAL|Compatible ID').Count -eq 0) 'Compact deep view hides extra hardware and compatibility lists'
$script:rendered.Clear()
Show-PnpRecords @($usbKeyboard) -Full
$fullLines=@($script:rendered | ForEach-Object Text)
Assert (@($fullLines | Where-Object {$_ -like '*Hardware ID 1*USB\MODEL*'}).Count -eq 1) 'Full view renders the first driver-match ID'
Assert (@($fullLines | Where-Object {$_ -like '*Hardware ID 2*USB\GENERAL*'}).Count -eq 1) 'Full view preserves additional IDs in the provider order'
Assert (@($fullLines | Where-Object {$_ -like '*Compatible ID 1*USB\CLASS*'}).Count -eq 1) 'Full view lists compatible IDs separately'
$nameless=[pscustomobject]@{Name=$null;PNPClass='USB';DeviceInstanceId=$null;HardwareID=@();CompatibleID=@();ConfigManagerErrorCode=$null}
Assert (@(Get-PnpIssues @($nameless) | Where-Object Kind -eq 'UnknownStatus').Count -eq 1) 'Unread status is a review item rather than a false all-clear'
Assert (@(Get-PnpIssues @($null,$usbKeyboard)).Count -eq 0) 'Null provider rows do not create unknown-device review items'
Assert (@(Get-PnpIssues @([pscustomobject]@{Name='Bad code';ConfigManagerErrorCode='invalid'}) | Where-Object Kind -eq 'UnknownStatus').Count -eq 1) 'Malformed provider status is shown as unknown rather than working'
$script:rendered.Clear()
Show-PnpRecords @($nameless) -Full
Assert (@($script:rendered | Where-Object Text -match 'Unnamed device').Count -eq 1) 'Incomplete devices render without an empty heading'
Assert (@($script:rendered | Where-Object Text -match 'none reported; can be normal').Count -eq 1) 'Missing compatible IDs do not imply a broken device'
$report['PnP hardware IDs']=@($unknownDevice)
$warnings.Clear();$identifiers=@();$script:rendered.Clear()
Show-Attention
Assert (@($script:rendered | Where-Object Text -match 'DEVICE REVIEW').Count -eq 1 -and @($script:rendered | Where-Object Text -match 'No missing identifiers').Count -eq 0) 'Device issues appear in review without a misleading all-clear'
$script:rendered.Clear()
Show-ControlDeck
Assert (@($script:rendered | Where-Object Text -match '\[REVIEW\]  1 items').Count -eq 1) 'Dashboard review count includes deep device issues'
foreach($compactWidth in @(20,32,40,60)) {
    $script:rendered.Clear()
    Show-CompactDeck $compactWidth
    $menuLines=@($script:rendered | Where-Object Text -match '\[[0-9]\]')
    Assert ($menuLines.Count -eq 10) ("Compact dashboard retains all menu choices at width $compactWidth")
    Assert (@($script:rendered | Where-Object {$_.Text.Length -ge $compactWidth}).Count -eq 0) ("Compact dashboard avoids line wrap at width $compactWidth")
}
foreach($direction in @('Next','Back','Exit')) {
    Assert ((Get-UiTransitionFrame $direction -10 80) -eq (Get-UiTransitionFrame $direction 0 80)) ("$direction animation clamps negative frame indexes")
    Assert ((Get-UiTransitionFrame $direction 100 80) -eq (Get-UiTransitionFrame $direction 17 80)) ("$direction animation clamps excess frame indexes")
}
Assert ((Get-UiTransitionFrame 'Next' 17 80) -match '>>\]') 'Forward sweep finishes at the right edge'
Assert ((Get-UiTransitionFrame 'Back' 17 80) -match '\[<<') 'Back sweep finishes at the left edge'
Assert ((Get-UiTransitionFrame 'Exit' 17 80) -notmatch '=') 'Exit bar fully closes on its final frame'
Assert ((Get-UiTransitionFrame 'Exit' 17 80) -match 'Goodbye') 'Exit animation ends with its own closing label'
Assert ((Get-UiTransitionDuration 'Back') -lt (Get-UiTransitionDuration 'Next') -and (Get-UiTransitionDuration 'Next') -lt (Get-UiTransitionDuration 'Exit')) 'Back is quicker than Next and Exit uses a slightly longer closing sequence'
foreach($animationWidth in @(0,8,16,40,80,100)) {
    foreach($direction in @('Next','Back','Exit')) {
        $frames=@(0..17 | ForEach-Object {Get-UiTransitionFrame $direction $_ $animationWidth 'Quick IDs'})
        Assert (@($frames | Where-Object {$_.Length -gt $animationWidth}).Count -eq 0) ("All $direction frames fit width $animationWidth")
    }
}
Assert ((Get-UiTransitionFrame 'Next' 8 40).Length -lt (Get-UiTransitionFrame 'Next' 8 100).Length) 'Motion track adapts to the available console width'
$script:rendered.Clear()
Write-PnpValue ("Device`nname") ("ID`r`nVALUE") $palette.Text
Assert (@($script:rendered | Where-Object {$_.Text -match '[\r\n\t]'}).Count -eq 0) 'Device names and values cannot inject console lines'
$script:rendered.Clear()
Show-Overview
Assert (@($script:rendered | Where-Object Text -match 'Review: .*findings / \d+ device / \d+ conflicts').Count -eq 1) 'Summary shows review totals and device findings as well as the dashboard'
$script:rendered.Clear()
Show-Help
Assert (@($script:rendered | Where-Object Text -match 'UNDERSTAND YOUR IDs|REPORTS & REVIEW').Count -eq 2) 'Help separates controls, identifiers, and report guidance'
foreach($digit in @('0','1','2','3','4','5','6')) {
    Assert ((Read-MenuChoice -Maximum 6 -Reader {$digit}) -eq $digit) ("Category input accepts $digit")
}
$script:categoryInputs=New-Object 'System.Collections.Generic.Queue[string]'
@('','7','9',([string][char]0xFF16),'6') | ForEach-Object {$script:categoryInputs.Enqueue($_)}
$script:rendered.Clear()
Assert ((Read-MenuChoice -Maximum 6 -Reader {$script:categoryInputs.Dequeue()}) -eq '6') 'Category input ignores blank and rejects out-of-range and Unicode digits'
Assert (@($script:rendered | Where-Object Text -match '\[INPUT-02\]').Count -eq 1) 'Category fallback reports one bounded-range error without flooding'
$categoryLines=Get-MenuInputLines 40 '6' '' 6
Assert ($categoryLines.Prompt.Contains('[0-6]') -and -not $categoryLines.Prompt.Contains('[0-9]')) 'Fixed category prompt shows the correct numeric range'
Assert ((Get-UiTransitionFrame 'Next' 5 90 'Quick IDs').Contains('NEXT / Quick IDs')) 'Next animation identifies the destination page'
Assert ((Get-MenuDestination '2') -eq 'ID numbers / serials' -and (Get-MenuDestination '6') -eq 'Save snapshot (TXT + JSON)') 'Animation destinations match dashboard menu labels'
Assert ((Convert-MonitorText @(65,66,67,0,0)) -eq 'ABC') 'Monitor text decodes EDID character arrays without trailing nulls'
Assert ((Convert-MonitorText $null) -eq '') 'Unavailable monitor text does not invent an identifier'
foreach($entry in @(@('Processor','SYSTEM & FIRMWARE'),@('Monitor','MONITORS'),@('AudioEndpoint','AUDIO'),@('Bluetooth','BLUETOOTH'),@('Camera','CAMERAS'),@('Keyboard','INPUT'),@('SCSIAdapter','STORAGE'),@('UnlistedClass','OTHER DEVICES'))) {
    $group=Get-PnpGroup ([pscustomobject]@{PNPClass=$entry[0];DeviceInstanceId='TEST\NODE'})
    Assert ($group -eq $entry[1] -and $group -in (Get-PnpGroups)) ("All-device grouping includes "+$entry[0])
}
$monitorFixture=[ordered]@{Monitors=@([pscustomobject]@{InstanceName='DISPLAY\A';SerialNumber='MON-A'},[pscustomobject]@{InstanceName='DISPLAY\B';SerialNumber='MON-B'})}
Assert (@(Get-QuickIds $monitorFixture).Count -eq 2 -and (Get-QuickIds $monitorFixture)[1].Label -eq 'Monitor 2') 'Quick IDs distinguish serials for multiple monitors'
$monitorOther=[ordered]@{Monitors=@([pscustomobject]@{InstanceName='DISPLAY\A';SerialNumber='MON-C'},[pscustomobject]@{InstanceName='DISPLAY\B';SerialNumber='MON-B'})}
Assert ((Compare-Inventories $monitorFixture $monitorOther).Changes.Count -eq 2) 'Monitor serial changes are compared by monitor instance'
$coverageFixture=[ordered]@{}
foreach($sectionName in @($sectionGroups.Values | ForEach-Object {$_})) {$coverageFixture[$sectionName]=@([pscustomobject]@{Name='Fixture'})}
$coverageFixture['PnP hardware IDs']=@($usbKeyboard,$unknownDevice)
$coverageRows=@(Get-ScanCoverage $coverageFixture)
Assert ($coverageRows.Count -eq 6 -and ($coverageRows | Measure-Object Total -Sum).Sum -eq 17) 'Coverage table accounts for all seventeen queries including PnP'
Assert (@($coverageRows | Where-Object Status -ne 'OK').Count -eq 0) 'Fully readable coverage reports OK for every area'
$coverageFixture.Remove('CPU');$coverageFixture['PnP hardware IDs']=@{Unavailable='Blocked'}
$coverageRows=@(Get-ScanCoverage $coverageFixture)
Assert (@($coverageRows | Where-Object {$_.Area -eq 'CPU & memory' -and $_.Status -eq 'PARTIAL'}).Count -eq 1) 'Missing CPU query produces a partial area instead of an all-clear'
Assert ($coverageRows[-1].Status -eq 'NOT READ' -and $coverageRows[-1].Read -eq 0) 'Unavailable all-device query is shown explicitly in coverage'
Assert ((Format-ScanTime '2026-10-25T10:38:04.4334337-04:00') -eq '2026-10-25 10:38:04 -04:00') 'Overview timestamp removes fractional seconds while retaining timezone'
Assert ((Format-ScanTime 'invalid time') -eq 'invalid time') 'Unreadable timestamps do not crash the overview'
Assert ((Format-ScanTime $null) -eq '(not provided)') 'Missing timestamps retain an explicit missing label'
$report['PnP hardware IDs']=@($usbKeyboard,$unknownDevice)
$script:rendered.Clear(); Show-Overview
Assert (@($script:rendered | Where-Object Text -match '(?m)^  RESULTS$|^  COVERAGE / QUERIES$|^  NEXT$').Count -eq 3) 'Overview separates results, coverage, and next actions'
Assert (@($script:rendered | Where-Object Text -match '2 records / 1 classes / 1 with hardware IDs').Count -eq 1) 'Device records and hardware-ID coverage counts use distinct units'
Assert (@($script:rendered | Where-Object Text -match 'not unique PC counts').Count -eq 1) 'Overview explains that identifier fields are not unique computer counts'
$overviewFixture=[ordered]@{'Report info'=[ordered]@{Generated='NORMAL-TIME'}}
foreach($sectionName in @($sectionGroups.Values | ForEach-Object {$_})) {$overviewFixture[$sectionName]=@([pscustomobject]@{Name='Fixture'})}
$overviewFixture['PnP hardware IDs']=@($null,$usbKeyboard,$unknownDevice)
$overviewIds=@([pscustomobject]@{Quality='Reported'},[pscustomobject]@{Quality='Missing'},[pscustomobject]@{Quality='Placeholder'})
$overviewSummary=Get-OverviewSummary $overviewFixture $overviewIds @('Query warning',$null)
Assert ($overviewSummary.Complete -and $overviewSummary.Read -eq 17 -and $overviewSummary.Total -eq 17) 'Overview completion measures query coverage independently of identifier quality'
Assert ($overviewSummary.Found -eq 1 -and $overviewSummary.Missing -eq 1 -and $overviewSummary.Default -eq 1 -and $overviewSummary.QueryWarnings -eq 1) 'Overview separates identifier fields from nonnull query warnings'
Assert ($overviewSummary.Nodes -eq 2 -and $overviewSummary.Classes -eq 1 -and $overviewSummary.Models -eq 1) 'Overview excludes null device rows from coverage counts'
Assert ($overviewSummary.ExtendedState -eq 'NOT SCANNED' -and $null -eq $overviewSummary.Known) 'An unrequested extended scan is distinct from a zero-device scan'
$overviewFixture['Extended scan info']=[ordered]@{Captured='EXTENDED-TIME'}
$overviewFixture['Extended device inventory']=@(
    $null,
    [pscustomobject]@{HiddenByNodeFlag=$true;HiddenByClass=$true;Present=$false},
    [pscustomobject]@{HiddenByNodeFlag=$null;HiddenByClass=$null;Present=$null},
    [pscustomobject]@{HiddenByNodeFlag=$false;HiddenByClass=$false;Present=$true}
)
$overviewSummary=Get-OverviewSummary $overviewFixture $overviewIds @()
Assert ($overviewSummary.ExtendedState -eq 'READ' -and $overviewSummary.Known -eq 3 -and $overviewSummary.Hidden -eq 1) 'Extended overview counts a node hidden by two flags only once'
Assert ($overviewSummary.VisibilityUnread -eq 1 -and $overviewSummary.Remembered -eq 1) 'Unknown visibility counts per device and unknown presence does not mean remembered'
Assert ($overviewSummary.ExtendedCaptured -eq 'EXTENDED-TIME' -and $overviewFixture['Report info'].Generated -eq 'NORMAL-TIME') 'Normal and extended captures keep their own timestamps'
$overviewFixture['Extended scan info']['Error']='Provider unavailable'
$overviewSummary=Get-OverviewSummary $overviewFixture $overviewIds @()
Assert (-not $overviewSummary.Complete -and $overviewSummary.Read -eq 17 -and $overviewSummary.ExtendedState -eq 'NOT READ' -and $null -eq $overviewSummary.Known) 'A failed extended attempt prevents a false complete result and hides stale counts'
$overviewFixture['PnP hardware IDs']=@{Unavailable='Access denied'}
$overviewSummary=Get-OverviewSummary $overviewFixture $overviewIds @()
Assert (-not $overviewSummary.DeviceReadable -and $null -eq $overviewSummary.Nodes -and $null -eq $overviewSummary.Classes -and $null -eq $overviewSummary.Models) 'Unread present-device counts stay unknown rather than becoming zero'
Assert ($overviewSummary.Read -eq 16 -and -not $overviewSummary.Complete) 'Unread PnP coverage contributes to a partial scan result'
Assert ((Normalize-IdentifierText (" `0Ab C`0 ")) -ceq 'Ab C') 'Identifier evaluation removes edge null padding and preserves internal spaces/case'
Assert ((Get-Quality ("`0`0 ")) -eq 'Missing') 'Null-only provider values do not count as identifiers'
Assert ((Get-Quality 'Not Provided') -eq 'Missing') 'Explicit unavailable firmware text is not counted as a found identifier'
$paddedDisk=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber="SERIAL`0 "});'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='SERIAL'})}
Assert ((Get-QuickDisks $paddedDisk)[0].Quality -eq 'Reported') 'Padding differences between disk providers do not create a serial clash'
Assert ($paddedDisk['Physical disks'][0].SerialNumber.Contains([string][char]0)) 'Evaluation preserves the original raw provider value in inventory'
Assert ((Get-CanonicalIdentifier 'SerialNumber' "SERIAL`0 ") -ceq 'SERIAL') 'Saved-report comparison uses the same edge-padding normalization'
$emptyOptical=[pscustomobject]@{DeviceID='D:';DriveType=5;FileSystem=$null;Size_GiB=$null;VolumeSerialNumber=$null}
Assert ((Get-FieldQuality 'VolumeSerialNumber' '' $emptyOptical) -eq 'Not applicable') 'Empty optical drive does not produce a false missing-volume-ID warning'
Assert (@(Get-QuickIds ([ordered]@{Volumes=@($emptyOptical)})).Count -eq 0) 'Quick IDs omit optical-drive serials when no filesystem/media is reported'
$loadedDrive=[pscustomobject]@{DriveType=2;FileSystem='NTFS';Size_GiB=16;VolumeSerialNumber=''}
Assert ((Get-FieldQuality 'VolumeSerialNumber' '' $loadedDrive) -eq 'Missing') 'Mounted removable filesystem with an unreadable serial still requires review'
Assert ((Get-FieldQuality 'MacAddress' '' ([pscustomobject]@{HardwareInterface=$false})) -eq 'Not applicable') 'Virtual interface without an assigned MAC is not treated as physical-ID loss'
Assert ((Get-FieldQuality 'MacAddress' '' ([pscustomobject]@{HardwareInterface=$true})) -eq 'Missing') 'Physical interface with no MAC remains a review item'
$oldNetwork=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-1';MacAddress='AA-BB-CC-DD-EE-12'})}
$newNetwork=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-1';MacAddress='AA-BB-CC-DD-EE-12';PNPDeviceID='PCI\NEW_FIELD'})}
$schemaComparison=Compare-Inventories $oldNetwork $newNetwork
Assert ($schemaComparison.Changes.Count -eq 0 -and $schemaComparison.SkippedFields -eq 1) 'Newly collected network fields do not falsely report hardware changes against older reports'
$savedNetFunction=(Get-Item Function:Get-NetAdapter).ScriptBlock
$savedCimFunction=(Get-Item Function:Get-CimInstance).ScriptBlock
try {
    function Get-NetAdapter {param([switch]$IncludeHidden) throw 'Simulated missing NetAdapter module'}
    $script:fallbackCalls=0
    function Get-CimInstance {param($Namespace,$ClassName,$OperationTimeoutSec) $script:fallbackCalls++; [pscustomobject]@{Name='Fallback NIC';InterfaceGuid='NIC-1';MacAddress='AABBCCDDEE12';PermanentAddress=$null;PNPDeviceID='PCI\NIC';HardwareInterface=$true;InterfaceOperationalStatus=1;ReceiveLinkSpeed=1000000000} }
    $fallback=@(Get-NetworkIdentifiers)
    Assert ($fallback.Count -eq 1 -and $fallback[0].CollectionSource -eq 'MSFT_NetAdapter CIM fallback') 'Network identifiers use modern CIM when the NetAdapter command fails'
    Assert ($fallback[0].PNPDeviceID -eq 'PCI\NIC' -and $fallback[0].InterfaceGuid -eq 'NIC-1') 'Network fallback retains both device and interface identifiers'
    Assert ($null -eq $fallback[0].PermanentAddress) 'Fallback never substitutes a current MAC for a missing permanent MAC'
    Assert ($fallback[0].Status -eq 'Up' -and $fallback[0].LinkSpeed -eq '1000 Mbps') 'Fallback formats status and bit-rate units clearly'
    function Get-NetAdapter {param([switch]$IncludeHidden) return}
    Assert (@(Get-NetworkIdentifiers).Count -eq 1 -and $script:fallbackCalls -eq 2) 'Empty primary adapter results also trigger fallback'
    function Get-CimInstance {param($Namespace,$ClassName,$OperationTimeoutSec) throw 'Simulated CIM denial'}
    $networkFailed=$false
    try {Get-NetworkIdentifiers | Out-Null}catch{$networkFailed=$_.Exception.Message -match 'Primary:.*Fallback:'}
    Assert $networkFailed 'Failure of both network providers returns a clear isolated error'
} finally {
    Set-Item -Path Function:Get-NetAdapter -Value $savedNetFunction
    Set-Item -Path Function:Get-CimInstance -Value $savedCimFunction
}
$pairFolder=Join-Path $testFolder 'pair-tests'
New-Item -ItemType Directory -Path $pairFolder | Out-Null
$pairJson=$sample | ConvertTo-Json -Depth 8
$pairStem=Join-Path $pairFolder 'HWID-pair-success'
Write-ReportPair $pairStem ('Readable '+[char]0x00E9) $pairJson
Assert ((Test-Path -LiteralPath ($pairStem+'.txt')) -and (Test-Path -LiteralPath ($pairStem+'.json'))) 'Successful staged save publishes both report files'
Assert ((Read-SavedReport ($pairStem+'.json')).'Memory modules'.Count -eq 2) 'Published JSON is readable with complete device data'
Assert ([IO.File]::ReadAllText($pairStem+'.txt') -eq ('Readable '+[char]0x00E9)) 'Staged TXT save preserves Unicode'
$failedStem=Join-Path $pairFolder 'HWID-pair-failure'
$publishFailed=$false
try {Write-ReportPair $failedStem 'text' $pairJson -Publisher {param($from,$to) if($to.EndsWith('.json')){throw 'Simulated second-file failure'};[IO.File]::Move($from,$to)}}catch{$publishFailed=$true}
Assert ($publishFailed -and -not (Test-Path -LiteralPath ($failedStem+'.txt')) -and -not (Test-Path -LiteralPath ($failedStem+'.json'))) 'Second-file failure rolls back the first file instead of leaving a partial pair'
Assert (@(Get-ChildItem -LiteralPath $pairFolder -Filter '*.pending-*').Count -eq 0) 'Handled save failures remove staged files'
$collisionStem=Join-Path $pairFolder 'HWID-existing'
[IO.File]::WriteAllText($collisionStem+'.txt','KEEP')
$collisionFailed=$false
try {Write-ReportPair $collisionStem 'replacement' $pairJson}catch{$collisionFailed=$true}
Assert ($collisionFailed -and [IO.File]::ReadAllText($collisionStem+'.txt') -eq 'KEEP') 'Report publishing never overwrites an existing report file'
$invalidStem=Join-Path $pairFolder 'HWID-invalid'
$invalidSave=$false
try {Write-ReportPair $invalidStem 'text' '{broken'}catch{$invalidSave=$true}
Assert ($invalidSave -and -not (Test-Path -LiteralPath ($invalidStem+'.txt')) -and -not (Test-Path -LiteralPath ($invalidStem+'.json'))) 'Invalid JSON is rejected before publishing either report'
$invalidIdentifierPath=Join-Path $pairFolder 'bad-identifier.json'
[IO.File]::WriteAllText($invalidIdentifierPath,'{"Report info":{"Version":"3.23"},"CPU":[{"ProcessorId":["A","B"]}]}')
$identifierRejected=$false
try {Read-SavedReport $invalidIdentifierPath | Out-Null}catch{$identifierRejected=$_.Exception.Message -match 'Invalid identifier'}
Assert $identifierRejected 'Array-valued scalar identifiers cannot create misleading comparison strings'
$missingReport=$false
try {Read-SavedReport (Join-Path $pairFolder 'absent.json') | Out-Null}catch{$missingReport=$_.Exception.Message -match 'not found'}
Assert $missingReport 'Missing report files produce a clear import error'
$recentFixture=@([pscustomobject]@{FullName="C:\Reports\a ! & [test] ' e.json"},[pscustomobject]@{FullName='C:\Reports\b.json'})
Assert ((Resolve-CompareInput '1' $recentFixture) -eq $recentFixture[0].FullName) 'Recent-report selection preserves literal special characters in paths'
Assert ((Resolve-CompareInput '"C:\Reports\custom file.json"' @()) -eq 'C:\Reports\custom file.json') 'Quoted pasted report paths are accepted'
Assert ((Resolve-CompareInput "'C:\Reports\custom file.json'" @()) -eq 'C:\Reports\custom file.json') 'Single-quoted report paths from PowerShell are accepted'
Assert ((Resolve-CompareInput '"C:\Reports\O''Brien [baseline] & scan!.json"' @()) -eq 'C:\Reports\O''Brien [baseline] & scan!.json') 'Pasted paths preserve apostrophes brackets and command-like characters literally'
foreach($badPathInput in @('"C:\Reports\scan.json','C:\Reports\scan.json"','""',("C:\Reports\scan"+[char]0+'.json'),("C:\Reports\one.json"+[char]10+'two.json'))) {
    $badPathRejected=$false
    try {Resolve-CompareInput $badPathInput @() | Out-Null}catch{$badPathRejected=$true}
    Assert $badPathRejected 'Malformed empty quoted or multiline report paths get a specific input error'
}
Assert ($null -eq (Resolve-CompareInput '0' $recentFixture) -and $null -eq (Resolve-CompareInput '' $recentFixture)) 'Zero and blank cancel report selection'
$badRecent=$false
try {Resolve-CompareInput '9' $recentFixture | Out-Null}catch{$badRecent=$true}
Assert $badRecent 'Unlisted recent-report numbers cannot select an unrelated path'
$recentFolder=Join-Path $pairFolder 'recent'
New-Item -ItemType Directory -Path $recentFolder | Out-Null
foreach($index in 1..6){$file=Join-Path $recentFolder ("HWID-$index.json");[IO.File]::WriteAllText($file,$pairJson);(Get-Item -LiteralPath $file).LastWriteTimeUtc=([datetime]'2026-01-01').AddDays($index)}
[IO.File]::WriteAllText((Join-Path $recentFolder 'HWID-staged.json.pending-test'),'pending')
[IO.File]::WriteAllText((Join-Path $recentFolder 'HWID-not-json.txt'),'text')
$recent=@(Get-RecentReports $recentFolder)
Assert ($recent.Count -eq 5 -and $recent[0].Name -eq 'HWID-6.json' -and $recent[-1].Name -eq 'HWID-2.json') 'Recent picker lists only five completed JSON files in modification order'
$comparisonOld=[ordered]@{'Report info'=@{Computer='TEST';Generated='2026-01-01T00:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='BEFORE'})}
$comparisonNew=[ordered]@{'Report info'=@{Computer='TEST';Generated='2026-01-02T00:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='AFTER'})}
$pairedChanges=@(Get-ComparisonDetails (Compare-Inventories $comparisonOld $comparisonNew))
Assert ($pairedChanges.Count -eq 1 -and $pairedChanges[0].Kind -eq 'Changed' -and $pairedChanges[0].Previous -eq 'BEFORE' -and $pairedChanges[0].Current -eq 'AFTER') 'One changed identifier is organized as a single previous/current pair'
$deviceRemoved=[ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU1';ProcessorId='OTHER'})}
$unpairedChanges=@(Get-ComparisonDetails (Compare-Inventories $comparisonOld $deviceRemoved))
Assert ($unpairedChanges.Count -eq 2 -and @($unpairedChanges | Where-Object Kind -eq 'Changed').Count -eq 0) 'Different device slots are not falsely paired as a single changed identifier'
$script:rendered.Clear()
Show-ComparisonResult ($comparisonOld | ConvertTo-Json -Depth 8 | ConvertFrom-Json) $comparisonNew
Assert (@($script:rendered | Where-Object Text -match '1 changed / 0 current only / 0 previous only').Count -eq 1) 'Comparison summary counts changed fields rather than two raw difference rows'
Assert (@($script:rendered | Where-Object Text -match 'OLD ID / saved: BEFORE|NEW ID / now: AFTER').Count -eq 2) 'Comparison displays previous and current values together'
Assert (@($script:rendered | Where-Object Text -match 'NOT COMPARED').Count -eq 1) 'Partial comparisons disclose skipped data in a separate section'
$plainArray=@(Get-PlainRecords @([pscustomobject]@{HardwareID=@('FIRST-ID','SECOND-ID');CompatibleID=@()}))
Assert (($plainArray -join "`n").Contains('[1] FIRST-ID') -and ($plainArray -join "`n").Contains('[2] SECOND-ID')) 'TXT export puts long identifier arrays on separate numbered lines in provider order'
Assert (($plainArray -join "`n").Contains('(none reported)')) 'TXT export distinguishes empty arrays from truncated data'
$malformedInfoPath=Join-Path $pairFolder 'bad-metadata.json'
[IO.File]::WriteAllText($malformedInfoPath,'{"Report info":{"Version":["3.23"],"Computer":{"Name":"wrong"}},"CPU":[{"ProcessorId":"ID"}]}')
$metadataRejected=$false
try {Read-SavedReport $malformedInfoPath | Out-Null}catch{$metadataRejected=$true}
Assert $metadataRejected 'Non-scalar metadata cannot masquerade as a valid saved report'
$isoData=[ordered]@{'Report info'=@{Version='3.23';Computer='TEST';Generated='2026-01-02T03:04:05.1234567-04:00'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='ID'})}
$isoStem=Join-Path $pairFolder 'HWID-iso-date'
Write-ReportPair $isoStem 'text' ($isoData | ConvertTo-Json -Depth 8)
$isoLoaded=Read-SavedReport ($isoStem+'.json')
Assert ($isoLoaded.CPU[0].ProcessorId -eq 'ID') 'Real ISO scan timestamps round-trip through staged saves and imports'
Assert ((Format-ScanTime ([datetime]::SpecifyKind([datetime]'2026-01-02 00:00:00',[DateTimeKind]::Utc))) -match '2026-01-02 00:00:00 \+00:00') 'Parsed UTC report timestamps keep the correct timezone'
$jsonCollisionStem=Join-Path $pairFolder 'HWID-json-collision'
[IO.File]::WriteAllText($jsonCollisionStem+'.json',$pairJson)
$jsonCollision=$false
try {Write-ReportPair $jsonCollisionStem 'text' $pairJson}catch{$jsonCollision=$true}
Assert ($jsonCollision -and -not (Test-Path -LiteralPath ($jsonCollisionStem+'.txt')) -and [IO.File]::ReadAllText($jsonCollisionStem+'.json') -eq $pairJson) 'Second-file collision rolls back new TXT and preserves the existing JSON'
$ambiguousOld=[ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='OLD-A'},[pscustomobject]@{DeviceID='CPU0';ProcessorId='OLD-B'})}
$ambiguousNew=[ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='NEW-C'})}
$ambiguousDetails=@(Get-ComparisonDetails (Compare-Inventories $ambiguousOld $ambiguousNew))
Assert ($ambiguousDetails.Count -eq 0 -and (Compare-Inventories $ambiguousOld $ambiguousNew).AmbiguousDevices.Count -eq 1) 'Ambiguous duplicate device records are skipped instead of guessing a replacement'
Assert ((Get-IdentifierChangeText '123456' '123956') -eq '1 character changed at position 4: 4 -> 9') 'Comparison identifies the exact changed digit and its one-based position'
Assert ((Get-IdentifierChangeText 'ABC123' 'ABC999') -eq '3 characters changed at positions 4-6: 123 -> 999') 'Contiguous changed digits are shown as a precise range'
Assert ((Get-IdentifierChangeText 'ABC123' 'AXC129') -eq '2 characters changed at positions 2, 6.') 'Separated differences count only the characters that actually changed'
Assert ((Get-IdentifierChangeText 'ABcd' 'ABCD') -match 'cd -> CD') 'Character difference explanation preserves case-sensitive changes'
Assert ((Get-IdentifierChangeText '123' '00123') -eq 'Inserted "00" at position 1.') 'Inserted leading zeros are preserved and explained'
Assert ((Get-IdentifierChangeText '00123' '123') -eq 'Removed "00" at position 1.') 'Removed leading zeros are explained without numeric conversion'
Assert ((Get-IdentifierChangeText '' 'ABC') -eq 'Inserted "ABC" at position 1.') 'Empty previous identifier is handled safely by the difference formatter'
Assert ((Get-IdentifierChangeText 'ABC' '') -eq 'Removed "ABC" at position 1.') 'Empty current identifier is handled safely by the difference formatter'
Assert ((Get-IdentifierChangeText 'SAME' 'SAME') -eq 'No characters changed.') 'Identical identifier strings do not invent character changes'
Assert ((Get-SectionIdentifierSummary 'CPU' @([pscustomobject]@{ProcessorId='CPU123';SerialNumber='';Name='CPU'})) -eq 'IDs: 1 found, 1 missing') 'Scan progress separates found identifier fields from missing ones'
Assert ((Get-SectionIdentifierSummary 'PnP hardware IDs' @($usbKeyboard,$unknownDevice)) -eq '2 instance IDs; 1 with model IDs; 1 review') 'PnP progress keeps instance-ID and model-list units distinct'
$preservedReport=$report;$preservedWarnings=$warnings;$preservedStep=$script:scanStep
try {
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]'
    Section 'Null query test' {return $null}
    Assert ($report['Null query test'].Unavailable -and $warnings.Count -eq 1) 'A null-only query is unavailable instead of a false successful empty device'
    Section 'Mixed query test' {$null;[pscustomobject]@{SerialNumber='REAL123'}}
    Assert ($report['Mixed query test'].Count -eq 1 -and $report['Mixed query test'][0].SerialNumber -eq 'REAL123') 'Mixed query output drops null entries while retaining valid identifiers'
} finally {$report=$preservedReport;$warnings=$preservedWarnings;$script:scanStep=$preservedStep}
$script:rendered.Clear()
Show-ComparisonResult ($comparisonOld | ConvertTo-Json -Depth 8 | ConvertFrom-Json) $comparisonNew
Assert (@($script:rendered | Where-Object Text -match '#1 / Changed').Count -eq 1) 'Each changed identifier has a stable visible change number'
Assert (@($script:rendered | Where-Object Text -match 'Exact difference:').Count -eq 1) 'Changed identifiers show an explicit exact-difference explanation'
$caseSlotsOld=[ordered]@{'Memory modules'=@([pscustomobject]@{DeviceLocator='A';SerialNumber='OLD'},[pscustomobject]@{DeviceLocator='a';SerialNumber=''})}
$caseSlotsNew=[ordered]@{'Memory modules'=@([pscustomobject]@{DeviceLocator='A';SerialNumber='NEW'},[pscustomobject]@{DeviceLocator='a';SerialNumber=''})}
$caseSlotResult=Compare-Inventories $caseSlotsOld $caseSlotsNew
Assert ($caseSlotResult.Changes.Count -eq 2 -and $caseSlotResult.SkippedFields -eq 1) 'Missing data in one case-distinct slot cannot suppress a real change in another slot'
Assert (@(Get-InventoryConflicts $caseSlotsOld).Count -eq 0) 'Case-distinct memory slot labels remain separate identities'
$duplicateDisk=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='A'},[pscustomobject]@{Index=0;SerialNumber='B'})}
$duplicateKeys=@(Get-InventoryConflicts $duplicateDisk)
Assert ($duplicateKeys.Count -eq 1 -and $duplicateKeys[0].Section -eq 'Physical disks' -and $duplicateKeys[0].Count -eq 2) 'Repeated disk indices are reported as scan-data conflicts'
$goodDisk=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='C'})}
$duplicateCompare=Compare-Inventories $duplicateDisk $goodDisk
Assert ($duplicateCompare.Changes.Count -eq 0 -and $duplicateCompare.AmbiguousDevices.Count -eq 1 -and $duplicateCompare.SkippedFields -gt 0) 'Ambiguous disk records are skipped rather than guessed into identifier changes'
Assert ($duplicateCompare.AmbiguousDevices[0].Sources[0] -eq 'Previous') 'Comparison identifies which snapshot contains the duplicate records'
$bothDuplicate=Compare-Inventories $duplicateDisk $duplicateDisk
Assert (($bothDuplicate.AmbiguousDevices[0].Sources -join '+') -eq 'Previous+Current') 'Repeated device keys present in both snapshots are disclosed once with both sources'
$sharedSerial=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='SAME'},[pscustomobject]@{Index=1;SerialNumber='SAME'})}
Assert (@(Get-InventoryConflicts $sharedSerial).Count -eq 0) 'Shared serial values on distinct disk keys are not misreported as duplicate records'
Assert ((Get-DeviceKey 'Network adapters' ([pscustomobject]@{InterfaceGuid="`0 "})) -eq '') 'Null-padded empty identity fields cannot create a fake device key'
$preservedReport=$report;$preservedIds=$identifiers;$preservedWarnings=$warnings
try {
    $report=$duplicateDisk;$identifiers=@(Get-IdentifierRows $report);$warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:rendered.Clear();Show-Attention
    Assert (@($script:rendered | Where-Object Text -match 'SCAN CONFLICT').Count -gt 0 -and @($script:rendered | Where-Object Text -match 'No missing identifiers').Count -eq 0) 'Review displays duplicate-key conflicts without a misleading all-clear'
    $script:rendered.Clear();Show-ControlDeck
    Assert (@($script:rendered | Where-Object Text -match '\[REVIEW\]  1 items').Count -eq 1) 'Dashboard review count includes duplicate device-key conflicts'
} finally {$report=$preservedReport;$identifiers=$preservedIds;$warnings=$preservedWarnings}
$missingKeysOld=[ordered]@{'Memory modules'=@([pscustomobject]@{SerialNumber='A'},[pscustomobject]@{SerialNumber='B'})}
$missingKeysNew=[ordered]@{'Memory modules'=@([pscustomobject]@{SerialNumber='A'},[pscustomobject]@{SerialNumber='C'})}
$missingKeyResult=Compare-Inventories $missingKeysOld $missingKeysNew
Assert ($missingKeyResult.Changes.Count -eq 0 -and 'Memory modules' -in $missingKeyResult.UnkeyedSections) 'Multiple devices without slot keys are not guessed into changed or removed hardware'
$knownNic=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid='NIC-1';MacAddress='AABBCCDDEE12'})}
$unknownNic=[ordered]@{'Network adapters'=@([pscustomobject]@{InterfaceGuid=$null;MacAddress='AABBCCDDEE12'})}
$unknownKeyResult=Compare-Inventories $knownNic $unknownNic
Assert ($unknownKeyResult.Changes.Count -eq 0 -and 'Network adapters' -in $unknownKeyResult.UnkeyedSections) 'Losing an interface key is disclosed as unmatchable data instead of a removal plus addition'
$singleNoKeyOld=[ordered]@{CPU=@([pscustomobject]@{ProcessorId='OLD'})}
$singleNoKeyNew=[ordered]@{CPU=@([pscustomobject]@{ProcessorId='NEW'})}
Assert ((Compare-Inventories $singleNoKeyOld $singleNoKeyNew).Changes.Count -eq 2) 'A single logical device with no key on either side remains comparable'
$dateIdOld=[ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='2026-01-02T03:04:05Z'})}
$dateIdNew=[ordered]@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='2026-01-02T03:04:06Z'})}
$dateDetails=@(Get-ComparisonDetails (Compare-Inventories $dateIdOld $dateIdNew))
Assert ($dateDetails[0].Previous -ceq '2026-01-02T03:04:05Z' -and $dateDetails[0].Current -ceq '2026-01-02T03:04:06Z') 'Identifiers that resemble dates keep their exact text in comparison details'
$dateKey=@(Get-ComparisonKeys @([pscustomobject]@{Section='CPU';Device='CPU0';Field='ProcessorId';Value='2026-01-02T03:04:05Z'}))[0]
Assert ((Format-ComparisonKey $dateKey).EndsWith('2026-01-02T03:04:05Z')) 'Readable comparison keys do not reformat date-shaped identifiers'
$arrayRootPath=Join-Path $pairFolder 'array-root.json'
[IO.File]::WriteAllText($arrayRootPath,('['+$pairJson+']'))
$arrayRootRejected=$false
try {Read-SavedReport $arrayRootPath | Out-Null}catch{$arrayRootRejected=$true}
Assert $arrayRootRejected 'A single-element array cannot masquerade as a report object after JSON pipeline enumeration'
$badDeviceKeyPath=Join-Path $pairFolder 'bad-device-key.json'
[IO.File]::WriteAllText($badDeviceKeyPath,'{"Report info":{"Version":"3.26"},"Memory modules":[{"DeviceLocator":{"Name":"wrong"},"SerialNumber":"ID"}]}')
$deviceKeyRejected=$false
try {Read-SavedReport $badDeviceKeyPath | Out-Null}catch{$deviceKeyRejected=$_.Exception.Message -match 'device-key'}
Assert $deviceKeyRejected 'Nested device-slot objects are rejected rather than converted into fake matching keys'
foreach($duplicateJson in @('{"x":1,"x":2}','{"SerialNumber":"A","serialnumber":"B"}','{"a":1,"\u0061":2}')) {
    $duplicateRejected=$false
    try {Assert-UniqueJsonProperties $duplicateJson}catch{$duplicateRejected=$_.Exception.Message -match 'Duplicate JSON property'}
    Assert $duplicateRejected 'Repeated, case-variant and Unicode-escaped JSON property names are rejected before parsing'
}
$separateRecords='{"Records":[{"Id":"A"},{"Id":"B"}],"Path":"C:\\path\\file","Quoted":"\"text\"","Markers":"{} [] :"}'
$separateAccepted=$true
try {Assert-UniqueJsonProperties $separateRecords}catch{$separateAccepted=$false}
Assert $separateAccepted 'Repeated field names in separate objects and structural characters inside strings remain valid'
$nestedDuplicatePath=Join-Path $pairFolder 'nested-duplicate.json'
[IO.File]::WriteAllText($nestedDuplicatePath,'{"Report info":{"Version":"3.27"},"CPU":[{"DeviceID":"CPU0","ProcessorId":"FIRST","ProcessorId":"LAST"}]}')
$nestedDuplicateRejected=$false
try {Read-SavedReport $nestedDuplicatePath | Out-Null}catch{$nestedDuplicateRejected=$_.Exception.Message -match 'Duplicate JSON property'}
Assert $nestedDuplicateRejected 'Report import identifies a duplicate identifier property instead of silently using its last value'
$duplicateSaveStem=Join-Path $pairFolder 'HWID-duplicate-json'
$duplicateSaveRejected=$false
try {Write-ReportPair $duplicateSaveStem 'text' ([IO.File]::ReadAllText($nestedDuplicatePath))}catch{$duplicateSaveRejected=$true}
Assert ($duplicateSaveRejected -and -not (Test-Path -LiteralPath ($duplicateSaveStem+'.txt')) -and -not (Test-Path -LiteralPath ($duplicateSaveStem+'.json'))) 'Ambiguous staged JSON cannot publish either saved report file'
$depthRejected=$false
try {Assert-UniqueJsonProperties (('['*129)+'0'+(']'*129))}catch{$depthRejected=$true}
Assert $depthRejected 'Excessively nested JSON is rejected without recursive parsing'
$preservedDriver=(Get-Item Function:Get-DriverHardwareIds).ScriptBlock
$preservedReport=$report;$preservedWarnings=$warnings
try {
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]'
    function Get-DriverHardwareIds {return $null}
    Show-DriverHardwareIds
    Assert ($report['PnP hardware IDs'].Unavailable -and $warnings.Count -eq 1) 'Null-only device refresh is unavailable rather than a successful phantom device'
    function Get-DriverHardwareIds {$null;[pscustomobject]@{Name='Valid USB';PNPClass='USB';DeviceInstanceId='USB\VALID';HardwareID=@('USB\MODEL');ConfigManagerErrorCode=0}}
    Show-DriverHardwareIds
    Assert ($report['PnP hardware IDs'].Count -eq 1 -and $report['PnP hardware IDs'][0].Name -eq 'Valid USB' -and $warnings.Count -eq 0) 'Mixed-null refresh retains real devices and clears the earlier unavailable warning'
} finally {
    Set-Item Function:Get-DriverHardwareIds -Value $preservedDriver
    $report=$preservedReport;$warnings=$preservedWarnings
}
$scanReview=Get-SectionIdentifierInfo 'BIOS' @([pscustomobject]@{SerialNumber='';UUID='00000000-0000-0000-0000-000000000000'})
Assert ($scanReview.Text -eq 'IDs: 0 found, 1 missing, 1 default' -and $scanReview.Tag -eq 'CHECK' -and $scanReview.Color -eq 'Warn') 'Missing and generic IDs receive explicit counts and amber review status'
$scanFound=Get-SectionIdentifierInfo 'CPU' @([pscustomobject]@{ProcessorId='CPU123'})
Assert ($scanFound.Text -eq 'IDs: 1 found' -and $scanFound.Tag -eq 'READ') 'Supplied IDs are described directly without a ratio'
$scanDetails=Get-SectionIdentifierInfo 'System hardware' @([pscustomobject]@{Manufacturer='TEST';Model='TEST'})
Assert ($scanDetails.Text -eq 'Inventory details' -and $scanDetails.Color -eq 'Muted') 'Detail-only sections do not imply a failed or missing identifier check'
$savedCimScanFunction=(Get-Item Function:Get-CimInstance).ScriptBlock
$savedNetScanFunction=(Get-Item Function:Get-NetAdapter).ScriptBlock
try {
    function Get-NetAdapter {param([switch]$IncludeHidden) throw 'Force CIM fallback'}
    function Get-CimInstance {param($Namespace,$ClassName,$OperationTimeoutSec,$Property) [pscustomobject]@{Name='NIC';InterfaceGuid='NIC-1';NetworkAddresses=@('AABBCCDDEE12');PermanentAddress='112233445566';HardwareInterface=$true} }
    $rawNetwork=@(Get-NetworkIdentifiers)
    Assert ($rawNetwork[0].MacAddress -eq 'AABBCCDDEE12' -and $rawNetwork[0].PermanentAddress -eq '112233445566') 'CIM network fallback derives the current MAC from NetworkAddresses without mixing up the permanent MAC'
    Assert ($rawNetwork[0].NetworkAddresses[0] -eq 'AABBCCDDEE12') 'Network fallback preserves the underlying address list for full reports'
} finally {Set-Item Function:Get-CimInstance -Value $savedCimScanFunction;Set-Item Function:Get-NetAdapter -Value $savedNetScanFunction}
$timingReport=$report;$timingWarnings=$warnings;$timingStep=$script:scanStep;$timingList=$script:scanTimings
try {
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    Section 'Timing success' {[pscustomobject]@{SerialNumber='ID'}}
    Section 'Timing failure' {throw 'Simulated provider failure'}
    Assert ($script:scanTimings.Count -eq 2 -and $script:scanTimings[0].Status -eq 'READ' -and $script:scanTimings[1].Status -eq 'UNAVAILABLE') 'Per-section diagnostics distinguish completed and unavailable queries'
    Assert ($script:scanTimings[0].Results -eq 1 -and $script:scanTimings[1].Results -eq 0) 'Timing diagnostics retain accurate result counts even after failure'
} finally {$report=$timingReport;$warnings=$timingWarnings;$script:scanStep=$timingStep;$script:scanTimings=$timingList}
Assert ((Get-StorageCodeName 'PartitionStyle' 2) -eq 'GPT' -and (Get-StorageCodeName 'PartitionStyle' 1) -eq 'MBR') 'Direct storage queries retain readable partition-style names'
Assert ((Get-StorageCodeName 'BusType' 17) -eq 'NVMe' -and (Get-StorageCodeName 'HealthStatus' 0) -eq 'Healthy') 'Direct storage queries retain readable bus and health names'
Assert ((Get-StorageCodeName 'BusType' 999) -eq 'Windows code 999' -and $null -eq (Get-StorageCodeName 'BusType' $null)) 'Unknown or missing storage codes are not turned into guessed values'
$script:rendered.Clear()
Show-Records @($null)
Assert (($script:rendered.Text -join ' ') -match 'No records captured') 'Null-only inventory sections have an explicit unavailable message'
$script:rendered.Clear()
$arrayRecord=[pscustomobject]@{Name='Fixture';AccessPaths=@('PATH-ONE','PATH-TWO');Other=@()}
Show-Records @($null,$arrayRecord)
$arrayDisplay=$script:rendered.Text -join ' '
Assert ($arrayDisplay -match '\[1\].*PATH-ONE' -and $arrayDisplay -match '\[2\].*PATH-TWO') 'Full inventory arrays show every value on separate numbered lines'
Assert ($arrayDisplay -match 'none reported' -and $arrayDisplay -match 'Record 1 of 1.*Fixture' -and $arrayDisplay -notmatch 'Record 2') 'Empty lists are explicit and null entries do not inflate record numbering'
Assert ($arrayRecord.AccessPaths[0] -ceq 'PATH-ONE' -and $arrayRecord.AccessPaths.Count -eq 2) 'Inventory presentation preserves original array values'
Assert ((Format-FieldValue @()) -eq '(none reported)') 'Empty arrays never produce a silently blank value'
$script:rendered.Clear()
Show-Records @([pscustomobject]@{DiskNumber=0;PartitionNumber=2;DriveLetter=$null;GptType='TYPE';PartitionGuid='UNIQUE'}) 'Disk partitions'
Assert (@($script:rendered | Where-Object {$_.Text -match 'None assigned' -and $_.Color -eq $palette.Muted}).Count -eq 1) 'Partitions without drive letters use a neutral explanation'
Assert (($script:rendered.Text -join ' ') -match 'Disk 0 / Partition 2') 'Partition records include their disk and partition number'
Assert ((Get-FieldLabel 'GptType') -match 'shared category' -and (Get-FieldLabel 'PartitionGuid') -match 'Unique') 'Partition category GUIDs and unique partition IDs have distinct labels'
$script:rendered.Clear()
$report['Scan timing']=@([pscustomobject]@{Section='CPU';Seconds=0.12;Status='READ';Results=1;Summary='IDs: 1 found'})
Show-FullReport
$fullDisplay=$script:rendered.Text -join ' '
Assert ($fullDisplay -match 'FULL INVENTORY REPORT' -and $fullDisplay -match 'Press 1-8 to jump') 'Full report includes a contents list and section controls'
Assert ($fullDisplay -match 'STARTUP SCAN TIMING' -and $fullDisplay -match 'Query time \(seconds\)') 'Full report includes startup timing data with units'
Assert ($fullDisplay -match 'ALL PRESENT DEVICE IDs' -and $fullDisplay -match 'ITEMS TO REVIEW') 'Full report retains deep device data and review details'
Reset-UiPage
Assert ($script:reportBookmarks.Count -eq 0) 'Page reset clears full-report navigation state'
Assert ((Get-ScanProgressText -1 17 -5) -match '0%.*0 of 17.*0.0s') 'Scan progress clamps negative counts and elapsed time'
Assert ((Get-ScanProgressText 30 17 1) -match '100%.*17 of 17') 'Scan progress cannot exceed one hundred percent'
Assert ((Get-ScanProgressText 8 17 2) -match '47%.*8 of 17') 'Progress percentage describes finished queries'
Assert ((Get-ScanProgressText 17 17 123 17).Length -lt 17 -and (Get-ScanProgressText 17 17 123 17) -match '100%') 'Narrow progress keeps completion visible on one line'
Assert ((Get-MenuDestination '9') -match 'Rescan') 'Rescan is discoverable from the numeric main menu'
$scanPreserved=[pscustomobject]@{
    Report=$report;Warnings=$warnings;Identifiers=$identifiers;Previous=$lastScanPrevious
    Cim=(Get-Item Function:Get-CimInstance).ScriptBlock
    Net=(Get-Item Function:Get-NetAdapter).ScriptBlock
    Pnp=(Get-Item Function:Get-DriverHardwareIds).ScriptBlock
    Invoke=(Get-Item Function:Invoke-HardwareScan).ScriptBlock
}
try {
    $script:rescanFixture=1
    function Get-CimInstance {
        param($ClassName,$Filter,$OperationTimeoutSec,$Property,$Namespace)
        if($ClassName -eq 'MSFT_Disk' -and $script:rescanFixture -eq 1){throw 'Simulated storage permission failure'}
        if($ClassName -eq 'Win32_Processor' -and $script:rescanFixture -eq 3){throw 'Simulated CPU provider failure'}
        if($ClassName -eq 'MSFT_Disk'){return [pscustomobject]@{Number=0;SerialNumber='DISK1';Guid='DISK-GUID';UniqueId='DISK-ID';PartitionStyle=2;BusType=17;Size=1GB}}
        if($ClassName -eq 'MSFT_Partition'){return [pscustomobject]@{DiskNumber=0;PartitionNumber=1;DriveLetter='C';Guid='PART1';AccessPaths=@('PATH1');Size=1GB}}
        [pscustomobject]@{Name='Fixture';DeviceID='CPU0';Index=0;DeviceLocator='A1';BankLabel='B1';SerialNumber=('ID000'+$script:rescanFixture);ProcessorId=('ID000'+$script:rescanFixture);UUID='SYSTEM1';TotalPhysicalMemory=8GB;InstanceName='MONITOR1'}
    }
    function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Fixture NIC';InterfaceGuid='NIC1';MacAddress='001122334455';HardwareInterface=$false}}
    function Get-DriverHardwareIds {
        [pscustomobject]@{Name='Fixture USB';DeviceInstanceId='USB\NODE1';HardwareID=@('USB\MODEL');PNPClass='USB';ConfigManagerErrorCode=0}
        if($script:rescanFixture -lt 3){[pscustomobject]@{Name='Second USB';DeviceInstanceId='USB\NODE2';HardwareID=@('USB\MODEL2');PNPClass='USB';ConfigManagerErrorCode=0}}
    }
    $beforeScan=$report
    $first=Invoke-HardwareScan 1
    Assert ([object]::ReferenceEquals($beforeScan,$report)) 'Building a scan snapshot never mutates the active inventory'
    Assert ($first.Completed -and $first.Warnings.Count -eq 1 -and $first.Inventory['Scan timing'].Count -eq 17) 'A query failure completes a partial snapshot with exactly seventeen timing records'
    $report=$first.Inventory;$warnings=$first.Warnings;$identifiers=$first.Identifiers
    $script:rescanFixture=2;$script:rendered.Clear()
    Start-HardwareRescan
    Assert ($report['Report info'].ScanNumber -eq 2 -and $report['CPU'][0].ProcessorId -eq 'ID0002') 'Rescan publishes fresh metadata and hardware values'
    Assert ($warnings.Count -eq 0 -and $report['Warnings'].Count -eq 0 -and -not $report['Storage identifiers'][0].Unavailable) 'Recovered queries clear earlier warnings and unavailable records'
    Assert ($scanStep -eq 17 -and $report['Scan timing'].Count -eq 17) 'Repeated scans reset step counters and timing instead of accumulating them'
    Assert ($lastScanPrevious['CPU'][0].ProcessorId -eq 'ID0001') 'The previous snapshot remains intact for change review'
    $rescanDisplay=$script:rendered.Text -join ' '
    Assert ($rescanDisplay -match 'OLD ID.*ID0001' -and $rescanDisplay -match 'NEW ID.*ID0002' -and $rescanDisplay -match 'position 6') 'Rescan results show exact old and new IDs and changed character positions'
    Assert ($null -eq $script:scanProgressClock -and $null -eq $script:scanProgressState) 'Completed scanning releases progress display state'
    $report['CPU'][0].ProcessorId='LATER-REFRESH'
    $first.Inventory['CPU'][0].ProcessorId='OLD-REFERENCE-MUTATED'
    $report['PnP hardware IDs'][0].HardwareID[0]='LATER-MODEL'
    Assert ($lastScanPrevious['CPU'][0].ProcessorId -eq 'ID0001' -and $lastScanCurrent['CPU'][0].ProcessorId -eq 'ID0002') 'Frozen rescan before/after values cannot change when live report references are later updated'
    Assert ($lastScanCurrent['PnP hardware IDs'][0].HardwareID[0] -eq 'USB\MODEL') 'Frozen rescan comparison also isolates nested device ID arrays'
    $report['CPU'][0].ProcessorId='ID0002'
    $report['PnP hardware IDs'][0].HardwareID[0]='USB\MODEL'
    $script:rescanFixture=3
    Start-HardwareRescan
    Assert ($report['Report info'].ScanNumber -eq 3 -and $report['CPU'].Unavailable -and -not $report['CPU'].ProcessorId) 'An unreadable section replaces stale identifiers instead of carrying them forward'
    Assert ($report['PnP hardware IDs'].Count -eq 1 -and $lastScanPrevious['PnP hardware IDs'].Count -eq 2) 'Rescan removes disconnected device nodes from the active snapshot'
    $stableReport=$report;$stableWarnings=$warnings;$stablePrevious=$lastScanPrevious;$stableIds=$identifiers
    function Invoke-HardwareScan {param($ScanNumber) throw 'Simulated overall scan failure'}
    $script:rendered.Clear()
    Start-HardwareRescan
    Assert ([object]::ReferenceEquals($report,$stableReport) -and [object]::ReferenceEquals($warnings,$stableWarnings) -and [object]::ReferenceEquals($identifiers,$stableIds)) 'An overall scan failure preserves all previously active report state'
    Assert ([object]::ReferenceEquals($lastScanPrevious,$stablePrevious) -and ($script:rendered.Text -join ' ') -match 'Previous snapshot kept') 'Failed rescans preserve the last comparison baseline and explain recovery'
    $stableCurrent=$lastScanCurrent
    function Invoke-HardwareScan {param($ScanNumber) [pscustomobject]@{Completed=$true;Inventory=[ordered]@{'Report info'=@{ScanNumber=$ScanNumber};'Scan timing'=@()};Warnings=@();Identifiers=@()}}
    Start-HardwareRescan
    Assert ([object]::ReferenceEquals($report,$stableReport) -and [object]::ReferenceEquals($lastScanCurrent,$stableCurrent)) 'Malformed completed scan results cannot replace the live inventory or last comparison'
    $script:rendered.Clear()
    Show-RescanResult ([ordered]@{'Report info'=@{};CPU=@{Unavailable='Failed'}}) ([ordered]@{'Report info'=@{};CPU=@{Unavailable='Failed'}})
    Assert (($script:rendered.Text -join ' ') -match 'No usable identifier fields' -and ($script:rendered.Text -join ' ') -notmatch 'No changes in comparable') 'Rescan with no comparable data cannot claim that identifiers are unchanged'
} finally {
    $report=$scanPreserved.Report;$warnings=$scanPreserved.Warnings;$identifiers=$scanPreserved.Identifiers;$lastScanPrevious=$scanPreserved.Previous
    Set-Item Function:Get-CimInstance -Value $scanPreserved.Cim
    Set-Item Function:Get-NetAdapter -Value $scanPreserved.Net
    Set-Item Function:Get-DriverHardwareIds -Value $scanPreserved.Pnp
    Set-Item Function:Invoke-HardwareScan -Value $scanPreserved.Invoke
}
Assert ((Get-ScanFailureHint 'Access is denied') -eq 'Access blocked') 'Scan errors explain blocked access without exposing raw IDs'
Assert ((Get-ScanFailureHint 'Operation timed out') -eq 'Provider timed out') 'Scan errors identify provider timeouts'
Assert ((Get-ScanFailureHint 'No data returned by Windows.') -eq 'No records returned') 'Empty provider results have an understandable scan status'
Assert ((Get-ScanFailureHint 'Invalid namespace') -eq 'Provider unavailable') 'Unsupported providers are distinguished from missing identifiers'
Assert ((Get-ScanFailureInfo ([UnauthorizedAccessException]::new('LOCALIZED'))).Code -eq 'READ-01') 'Typed access failures do not depend on English Windows messages'
Assert ((Get-ScanFailureInfo ([Exception]::new('Outer message',[TimeoutException]::new('LOCALIZED')))).Code -eq 'READ-02') 'Wrapped provider timeouts retain their actual failure category'
$localizedClass=[Runtime.InteropServices.COMException]::new('LOCALIZED',[Convert]::ToInt32('80041010',16))
Assert ((Get-ScanFailureInfo $localizedClass).Code -eq 'READ-03') 'WMI invalid-class HRESULT is recognized without translated message matching'
$localizedPermission=New-Object System.Management.Automation.ErrorRecord ([Exception]::new('LOCALIZED')),'TestPermission',([System.Management.Automation.ErrorCategory]::PermissionDenied),$null
Assert ((Get-ScanFailureInfo $localizedPermission).Code -eq 'READ-01') 'PowerShell error categories preserve localized permission failures'
Assert ((Get-ScanFailureInfo 'Device access path could not be read').Code -eq 'READ-05') 'The word access alone does not produce misleading administrator advice'
Assert ((Get-ScanFailureInfo 'No data returned by Windows.').Code -eq 'READ-04') 'Empty query results have a separate code from blocked reads'
Assert ((Get-ScanFailureInfo 'Invalid namespace').Action -notmatch 'administrator') 'Unavailable provider advice does not promise that elevation fixes it'
Assert ((Get-ScanFailureInfo 'Operation timed out').Action -match 'Retry') 'Timeouts provide a practical rescan action'
Assert ((Get-ScanFailureInfo 'Raw provider message').Details -eq 'Raw provider message') 'Technical failure text stays available without being substituted by advice'
$missingNode=[pscustomobject]@{Name='No instance';DeviceInstanceId='';ConfigManagerErrorCode=0;HardwareID=@('MODEL')}
Assert (@(Get-PnpIssues @($missingNode) | Where-Object Kind -eq 'MissingInstance').Count -eq 1) 'A working status does not hide an unreadable device instance ID'
$nodeInfo=Get-SectionIdentifierInfo 'PnP hardware IDs' @($missingNode,$usbKeyboard)
Assert ($nodeInfo.Tag -eq 'CHECK' -and $nodeInfo.Missing -eq 1 -and $nodeInfo.Text -match '1 instance IDs missing') 'PnP scan counts missing instance IDs instead of reporting a false zero'
$failurePreserved=@{Report=$report;Warnings=$warnings;Step=$script:scanStep;Timings=$script:scanTimings}
try {
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    Section 'Unavailable sentinel test' {[pscustomobject]@{Unavailable='Invalid namespace'}}
    Assert ($script:scanTimings[0].Status -eq 'UNAVAILABLE' -and $script:scanTimings[0].Results -eq 0 -and -not (Test-SectionReadable $report['Unavailable sentinel test'])) 'Returned unavailable markers cannot masquerade as successful scan records'
    Assert ($report['Unavailable sentinel test'].FailureCode -eq 'READ-03' -and $script:scanTimings[0].FailureCode -eq 'READ-03') 'Scan rows and report metadata preserve the same failure code'
    Assert ($warnings.Count -eq 1 -and $warnings[0] -match 'Invalid namespace') 'Unavailable-marker failures retain their raw diagnostic warning'
    Section 'Localized timeout test' {throw [TimeoutException]::new('LOCALIZED')}
    Assert ($report['Localized timeout test'].FailureCode -eq 'READ-02' -and $report['Localized timeout test'].NextStep -match 'Retry') 'Section capture records typed failure guidance alongside the original message'
    $script:rendered.Clear();Show-Attention
    Assert (@($script:rendered | Where-Object Text -match '^  SECTIONS NOT READ$').Count -eq 1 -and @($script:rendered | Where-Object Text -match 'Provider timed out.*READ-02').Count -eq 1) 'Review groups unreadable sections and reuses stored localized failure reasons'
    Section 'Readable after failure test' {[pscustomobject]@{SerialNumber='REAL'}}
    Assert ($script:scanTimings[2].Status -eq 'READ' -and $null -eq $script:scanTimings[2].FailureCode -and $null -eq $script:scanTimings[2].NextStep) 'A successful scan row cannot inherit a previous failure reason or action'
} finally {$report=$failurePreserved.Report;$warnings=$failurePreserved.Warnings;$script:scanStep=$failurePreserved.Step;$script:scanTimings=$failurePreserved.Timings}
$cloneSource=[ordered]@{Empty=@();One=@('00123');Values=@($null,$false,0);DateText='2026-01-02T03:04:05Z';Nested=[pscustomobject]@{ID='ABC';Paths=@('A','B')}}
$clone=Copy-InventorySnapshot $cloneSource
$cloneSource.Nested.Paths[0]='CHANGED'
Assert ($clone.Empty -is [array] -and $clone.Empty.Count -eq 0 -and $clone.One -is [array] -and $clone.One[0] -ceq '00123') 'Snapshot copying preserves empty and singleton arrays and leading-zero identifiers'
Assert ($clone.Values.Count -eq 3 -and $null -eq $clone.Values[0] -and $clone.Values[1] -eq $false -and $clone.Values[2] -eq 0 -and $clone.DateText -is [string] -and $clone.Nested.Paths[0] -eq 'A') 'Snapshot copying preserves nulls, false, zero, date-shaped text and nested values'
$oldNodes=@([pscustomobject]@{Name='Old USB';DeviceInstanceId='USB\OLD'})
$newNodes=@([pscustomobject]@{Name='New USB';DeviceInstanceId='USB\NEW'})
$nodeDelta=Get-PnpNodeChanges $oldNodes $newNodes
Assert ($nodeDelta.Comparable -and $nodeDelta.Added.Count -eq 1 -and $nodeDelta.Removed.Count -eq 1) 'Rescan detects device arrivals and removals even when total node counts are equal'
$caseDelta=Get-PnpNodeChanges $oldNodes @([pscustomobject]@{Name='Same USB';DeviceInstanceId='usb\old'})
Assert ($caseDelta.Comparable -and -not $caseDelta.Added.Count -and -not $caseDelta.Removed.Count) 'Case-only instance ID changes do not create false device arrivals'
Assert (-not (Get-PnpNodeChanges $oldNodes @($newNodes[0],$newNodes[0])).Comparable) 'Duplicate device instance IDs prevent guessed arrival/removal matches'
Assert (-not (Get-PnpNodeChanges $oldNodes @([pscustomobject]@{Name='No instance'})).Comparable) 'Missing instance IDs are disclosed instead of treated as removed hardware'
Assert (-not (Get-PnpNodeChanges @{Unavailable='Failure'} $newNodes).Comparable) 'Unreadable PnP queries cannot masquerade as device removals'
$workerPreserved=[pscustomobject]@{Report=$report;Warnings=$warnings;Step=$scanStep;Timings=$scanTimings;Complete=(Get-Item Function:Complete-ScanLine).ScriptBlock;NewWorker=(Get-Item Function:New-ScanQueryWorker).ScriptBlock;Cim=(Get-Item Function:Get-CimInstance).ScriptBlock}
try {
    $script:scanQueryWorker=New-ScanQueryWorker
    $script:workerPulseCount=0
    $workerData=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 450;[pscustomobject]@{SerialNumber='001234';Paths=@('PATH1','PATH2');When=[datetime]'2026-01-02';Enabled=$false}} {$script:workerPulseCount++})
    Assert ($script:workerPulseCount -gt 0) 'Background queries let the main thread refresh progress while a provider is busy'
    Assert ($workerData.Count -eq 1 -and $workerData[0].SerialNumber -ceq '001234' -and $workerData[0].Paths.Count -eq 2 -and $workerData[0].When -is [datetime] -and $workerData[0].Enabled -eq $false) 'Query worker preserves original strings, arrays, dates and false values without JSON serialization'
    $partial=@();$workerFailed=$false
    try {$partial=@(Invoke-ScanQuery {[pscustomobject]@{SerialNumber='PARTIAL'};throw 'Simulated worker failure'})}catch{$workerFailed=$true}
    Assert ($workerFailed -and $partial.Count -eq 0) 'A failing worker query does not publish its partial records'
    $recovered=@(Invoke-ScanQuery {[pscustomobject]@{SerialNumber='RECOVERED'}})
    Assert ($recovered.Count -eq 1 -and $recovered[0].SerialNumber -eq 'RECOVERED') 'The same worker can read the next section after an earlier query fails'
    $fallbackNetwork=@(Invoke-ScanQuery {
        function Get-NetAdapter {throw 'Simulated primary failure'}
        function Get-CimInstance {[pscustomobject]@{Name='NIC';NetworkAddresses=@('001122334455');InterfaceGuid='NIC1'}}
        Get-NetworkIdentifiers
    })
    Assert ($fallbackNetwork.Count -eq 1 -and $fallbackNetwork[0].CollectionSource -eq 'MSFT_NetAdapter CIM fallback') 'Handled primary network failures still permit a successful worker fallback'
    $script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    Section 'Dictionary fixture' {[ordered]@{SerialNumber='001234';Captured=[datetime]'2026-01-02';Values=@('A','B')}}
    Assert ($report['Dictionary fixture'][0].SerialNumber -ceq '001234' -and $report['Dictionary fixture'][0].Values.Count -eq 2 -and $report['Dictionary fixture'][0].Captured -is [string]) 'Dictionary query records retain their actual fields and normalized dates'
    function Complete-ScanLine {param($State,$Name,$Text,$Color) throw 'Simulated display failure'}
    Section 'Display fixture' {[pscustomobject]@{SerialNumber='GOOD-DATA'}}
    Assert ($report['Display fixture'][0].SerialNumber -eq 'GOOD-DATA' -and -not $report['Display fixture'].Unavailable -and $warnings.Count -eq 0) 'A rendering failure cannot reclassify a successful hardware query as unavailable'
    Set-Item Function:Complete-ScanLine -Value $workerPreserved.Complete
    function Get-CimInstance {
        param($ClassName,$Filter,$OperationTimeoutSec,$Property,$Namespace)
        if($ClassName -eq 'MSFT_Disk'){throw 'Simulated storage failure'}
        [pscustomobject]@{DeviceID='MOCK';UUID='MOCK';SerialNumber='MOCK';TotalPhysicalMemory=8GB}
    }
    $workerSnapshot=Invoke-HardwareScan 4 -UseWorker $true
    Assert ($workerSnapshot.Completed -and $workerSnapshot.Inventory['Report info'].QueryMode -eq 'Live progress' -and $workerSnapshot.Inventory['Scan timing'].Count -eq 17) 'The worker path completes the full seventeen-section inventory with collection helpers loaded'
    Assert ($workerSnapshot.Inventory['CPU'][0].DeviceID -eq 'MOCK' -and $workerSnapshot.Inventory['System identity'][0].UUID -eq 'MOCK' -and $workerSnapshot.Warnings.Count -eq 1) 'Worker scans use the supplied synthetic providers and isolate the expected storage failure'
    Assert ($null -eq $script:scanQueryWorker -and $null -eq $script:scanProgressClock) 'Completed scans dispose the query worker and clear timer state'
    function New-ScanQueryWorker {throw 'Simulated worker startup failure'}
    $directSnapshot=Invoke-HardwareScan 5 -UseWorker $true
    Assert ($directSnapshot.Completed -and $directSnapshot.Inventory['Report info'].QueryMode -eq 'Direct queries' -and $directSnapshot.Inventory['Scan timing'].Count -eq 17) 'Worker startup failure safely falls back to direct queries'
} finally {
    if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
    $report=$workerPreserved.Report;$warnings=$workerPreserved.Warnings;$script:scanStep=$workerPreserved.Step;$script:scanTimings=$workerPreserved.Timings
    Set-Item Function:Complete-ScanLine -Value $workerPreserved.Complete
    Set-Item Function:New-ScanQueryWorker -Value $workerPreserved.NewWorker
    Set-Item Function:Get-CimInstance -Value $workerPreserved.Cim
}
$extendedPreserved=[pscustomobject]@{
    Report=$report;Owned=$ownedConsole;Redirected=$redirected
    Class=(Get-Item Function:Get-ClassHiddenState).ScriptBlock
    Native=(Get-Item Function:Get-NativeNodeStatus).ScriptBlock
    Inventory=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock
    Cim=(Get-Item Function:Get-CimInstance).ScriptBlock
}
try {
    $script:extendedFixtures=@(
        [pscustomobject]@{Name='Present USB';Present=$true;PNPDeviceID='USB\A';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@('MODEL-A','GENERAL-A');CompatibleID=@('CLASS-A');ConfigManagerErrorCode=0}
        [pscustomobject]@{Name='Remembered USB';Present=$false;PNPDeviceID='USB\B';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@('MODEL-B');ConfigManagerErrorCode=45}
        [pscustomobject]@{Name='Hidden USB';Present=$true;PNPDeviceID='USB\C';ClassGuid='NORMAL';PNPClass='USB';ConfigManagerErrorCode=0}
        [pscustomobject]@{Name='Hidden class';Present=$true;PNPDeviceID='USB\D';ClassGuid='HIDDEN';PNPClass='USB';ConfigManagerErrorCode=22}
        [pscustomobject]@{Name='Disabled USB';Present=$true;PNPDeviceID='USB\E';ClassGuid='NORMAL';PNPClass='USB';ConfigManagerErrorCode=22}
        [pscustomobject]@{Name='Unknown presence';Present=$null;PNPDeviceID='USB\F';ClassGuid='UNREAD';PNPClass='USB'}
    )
    function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) if($PresentOnly){throw 'Extended scan incorrectly requested present-only nodes'};$script:extendedFixtures}
    function Get-PnpDeviceProperty {
        param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
        $script:extendedBatchCalls++;$script:extendedBatchIds=@($InstanceId)
        foreach($id in $InstanceId | Where-Object {$_ -ne 'USB\F'}) {
            [pscustomobject]@{InstanceId=$id.ToLowerInvariant();KeyName='DEVPKEY_Device_DevNodeStatus';Data=$(if($id -eq 'USB\C'){[uint32]0x40000008}else{[uint32]8})}
        }
    }
    function Get-ClassHiddenState {param($ClassGuid) $script:extendedClassCalls++;if($ClassGuid -eq 'UNREAD'){return $null};return ($ClassGuid -eq 'HIDDEN')}
    function Get-NativeNodeStatus {param($InstanceId) return $null}
    $script:extendedBatchCalls=0;$script:extendedClassCalls=0
    $catalog=Get-ExtendedDeviceInventory
    Assert ($catalog.Devices.Count -eq 6 -and $catalog.Info.Source -match 'Get-PnpDevice') 'Extended collection includes present, non-present and unknown-presence records'
    Assert ($script:extendedBatchCalls -eq 1 -and $script:extendedBatchIds.Count -eq 6 -and $script:extendedClassCalls -eq 3) 'Node flags are batched and class visibility is read once per class'
    Assert ($catalog.Devices[2].HiddenByNodeFlag -eq $true -and $catalog.Devices[3].HiddenByClass -eq $true) 'Node and class hiding flags are independently detected with case-insensitive instance matching'
    Assert ($null -eq $catalog.Devices[5].Present -and $null -eq $catalog.Devices[5].HiddenByNodeFlag -and $null -eq $catalog.Devices[5].HiddenByClass) 'Unread presence and hiding flags remain unknown instead of becoming false'
    Assert ($catalog.Info.NodeFlagsRead -eq 5 -and $catalog.Info.ClassFlagsRead -eq 5) 'Extended coverage discloses unread flags separately'
    Assert ($catalog.Devices[0].HardwareID.Count -eq 2 -and $catalog.Devices[0].CompatibleID[0] -eq 'CLASS-A') 'Extended scan preserves complete hardware and compatible ID lists'
    Assert ($catalog.Devices[2].HardwareID.Count -eq 0) 'Missing model ID lists do not create phantom null entries'
    $groupKeys=@($catalog.Devices | ForEach-Object {Get-ExtendedDeviceGroup $_})
    Assert (($groupKeys -join ',') -eq '5,2,3,3,4,6') 'Extended groups distinguish remembered, hidden, disabled, other present and unknown records'
    $script:rendered.Clear()
    Show-PnpRecords @($catalog.Devices[1]) -Full -Extended
    Assert (@($script:rendered | Where-Object {$_.Text -match 'Not present / remembered' -and $_.Color -eq $palette.Muted}).Count -eq 1) 'Remembered devices receive a neutral presence label rather than a broken-device warning'
    $report=[ordered]@{'Report info'=[ordered]@{Version='3.35';Computer='TEST';Generated='test'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU1'});'Extended device inventory'=$catalog.Devices;'Extended scan info'=$catalog.Info;Warnings=@()}
    Assert (@(Get-IdentifierRows $report).Count -eq 1) 'Extended inventory does not inflate normal identifier-field counts'
    $script:rendered.Clear()
    Show-ExtendedDeviceReport
    $extendedText=$script:rendered.Text -join ' '
    Assert ($extendedText -match 'NOT PRESENT / REMEMBERED' -and $extendedText -match 'HIDDEN BY WINDOWS' -and $extendedText -match 'Unknown / not read') 'Extended report presents separate groups and readable unknown-state labels'
    $baseReport=[ordered]@{'Report info'=$report['Report info'];CPU=$report['CPU']}
    Assert ((Compare-Inventories $baseReport $report).Changes.Count -eq 0) 'Adding an extended catalog cannot create normal identifier comparison changes'
    $ownedConsole=$false;$redirected=$true
    Start-ExtendedDeviceScan
    Assert ($report['Extended device inventory'].Count -eq 6 -and $report['CPU'][0].ProcessorId -eq 'CPU1') 'Optional extended scanning leaves the normal CPU inventory intact'
    $kept=$report['Extended device inventory'];$captured=$report['Extended scan info']
    function Get-ExtendedDeviceInventory {throw 'Simulated access denied'}
    $script:rendered.Clear()
    Start-ExtendedDeviceScan
    Assert ([object]::ReferenceEquals($kept,$report['Extended device inventory']) -and [object]::ReferenceEquals($captured,$report['Extended scan info'])) 'Failed extended scans preserve the previous catalog and capture metadata together'
    Assert (($script:rendered.Text -join ' ') -match 'Previous catalog kept') 'Failed refresh explicitly identifies its retained older catalog'
    Set-Item Function:Get-ExtendedDeviceInventory -Value $extendedPreserved.Inventory
    $originalExtendedFixtures=$script:extendedFixtures
    $script:extendedFixtures=@(
        [pscustomobject]@{Name='Parent bridge';Present=$true;PNPDeviceID='USB\P';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@('PARENT');ConfigManagerErrorCode=0}
        [pscustomobject]@{Name=$null;Present=$null;PNPDeviceID='USB\X';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@(' ','');ConfigManagerErrorCode=28}
        [pscustomobject]@{Name='Remembered';Present=$null;PNPDeviceID='USB\Y';ClassGuid='NORMAL';PNPClass='USB';ConfigManagerErrorCode=$null}
        [pscustomobject]@{Name='Racing USB';Present=$true;PNPDeviceID='USB\Z';ClassGuid='NORMAL';PNPClass='USB';ConfigManagerErrorCode=0}
    )
    $script:nativeRecoveryCalls=0
    function Get-NativeNodeStatus {param($InstanceId) $script:nativeRecoveryCalls++;if($InstanceId -eq 'USB\X'){return [uint32]0x40000008};return $null}
    function Get-PnpDeviceProperty {
        param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
        foreach($id in $InstanceId) {
            if($id -ne 'USB\X'){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_DevNodeStatus';Data=[uint32]0}}
            if($id -in @('USB\Y','USB\Z')) {
                [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_IsPresent';Data=$false}
                [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_ProblemCode';Data=0}
            }
            if($id -eq 'USB\X') {
                $properties=[ordered]@{
                    DEVPKEY_Device_IsPresent=$true;DEVPKEY_Device_HardwareIds=@('USB\MODEL1','USB\MODEL2')
                    DEVPKEY_Device_CompatibleIds=@('USB\CLASS');DEVPKEY_Device_Parent='usb\p'
                    DEVPKEY_Device_EnumeratorName='USB';DEVPKEY_Device_LocationInfo='Port 1'
                    DEVPKEY_Device_BusReportedDeviceDesc='Recovered USB device';DEVPKEY_Device_ProblemCode=28
                    DEVPKEY_Device_ProblemStatus=-1073741823;DEVPKEY_Device_DriverInfPath='oem42.inf'
                }
                foreach($key in $properties.Keys){[pscustomobject]@{InstanceId=$id;KeyName=$key;Data=$properties[$key]}}
            }
        }
    }
    $enriched=Get-ExtendedDeviceInventory
    $child=$enriched.Devices[1]
    Assert ($enriched.Info.NativeStatusRecoveries -eq 1 -and $script:nativeRecoveryCalls -eq 1 -and $child.HiddenByNodeFlag -eq $true) 'Native status fallback recovers an unread hiding flag without retrying valid zero flags'
    Assert ($child.Name -eq 'Recovered USB device' -and $child.NameSource -eq 'Bus description' -and $child.Present -eq $true -and $child.PresenceSource -eq 'Device properties') 'Unknown names and presence can be recovered from typed Windows properties with their sources recorded'
    Assert ($child.HardwareID.Count -eq 2 -and $child.CompatibleID[0] -eq 'USB\CLASS' -and $enriched.Info.HardwareIdRecoveries -eq 1) 'Blank model lists are recovered from device properties without losing additional IDs'
    Assert ($child.ParentName -eq 'Parent bridge' -and $child.ParentInstanceId -ceq 'usb\p' -and $child.Enumerator -eq 'USB' -and $child.Location -eq 'Port 1') 'Parent links resolve case insensitively while preserving original instance text and bus/location details'
    Assert ($child.DriverInfPath -eq 'oem42.inf' -and ((@(Get-ExtendedDeviceReview $child) -join '; ') -match 'Driver not installed \(code 28\)')) 'Review explains missing-driver status and retains the reported INF path'
    Assert ($enriched.Devices[2].Present -eq $false -and $enriched.Devices[2].DeviceProblemCode -eq 0 -and $enriched.Devices[2].DevNodeStatus -eq 0) 'False presence and zero problem/status values remain real data rather than missing values'
    Assert ($null -eq $enriched.Devices[3].Present -and $enriched.Devices[3].PresenceConflict -eq $true -and ((Get-ExtendedDeviceReview $enriched.Devices[3]) -join ' ') -match 'disagreed') 'Conflicting presence readings are disclosed instead of guessed present or absent'
    Assert ((Format-DeviceProblemStatus -1073741823) -eq '0xC0000001' -and (Format-DeviceProblemStatus 0) -match 'no additional status detail') 'Signed Windows status codes render correctly and zero is not mistaken for proof that a device works'
    $script:rendered.Clear();$report['Extended device inventory']=$enriched.Devices;$report['Extended scan info']=$enriched.Info
    Show-ExtendedDeviceReport
    Assert (($script:rendered.Text -join ' ') -match 'UNKNOWN / REVIEW' -and ($script:rendered.Text -join ' ') -match 'Parent bridge' -and ($script:rendered.Text -join ' ') -match 'Driver not installed') 'Unknown review shows reasons and parent-device context alongside the full catalog'
    function Get-PnpDeviceProperty {
        param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
        [pscustomobject]@{InstanceId='USB\X';KeyName='DEVPKEY_Device_HardwareIds';Data=@('RECOVERED-BEFORE-FAILURE')}
        [pscustomobject]@{InstanceId='USB\X';KeyName='DEVPKEY_Device_IsPresent';Data=$true}
        throw 'Simulated later property-provider failure'
    }
    $partlyRead=Get-ExtendedDeviceInventory
    Assert ($partlyRead.Devices[1].HardwareID[0] -eq 'RECOVERED-BEFORE-FAILURE' -and $partlyRead.Devices[1].Present -eq $true -and $partlyRead.Info.PropertyReadErrors -gt 0) 'Successful property rows survive a later terminating error in the same batch'
    $script:extendedFixtures=$originalExtendedFixtures
    $report['Extended device inventory']=$catalog.Devices;$report['Extended scan info']=$catalog.Info
    function Get-NativeNodeStatus {param($InstanceId) return $null}
    function Get-PnpDevice {throw 'Simulated unavailable PnpDevice module'}
    function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$Property) $script:extendedFixtures}
    $fallbackCatalog=Get-ExtendedDeviceInventory
    Assert ($fallbackCatalog.Devices.Count -eq 6 -and $fallbackCatalog.Info.Source -match 'unfiltered fallback') 'Missing PnpDevice enumeration falls back to unfiltered CIM without a present-only filter'
    function Get-PnpDevice {return $null}
    $emptyPrimaryCatalog=Get-ExtendedDeviceInventory
    Assert ($emptyPrimaryCatalog.Devices.Count -eq 6 -and $emptyPrimaryCatalog.Info.Source -match 'unfiltered fallback') 'Empty primary device enumeration retries the unfiltered fallback instead of abandoning the scan'
    Assert ($emptyPrimaryCatalog.Info.FallbackReason -match 'No device records returned by Get-PnpDevice') 'Recovered extended scans retain the reason for selecting their fallback reader'
    function Get-PnpDeviceProperty {throw 'Simulated property access blocked'}
    $partialCatalog=Get-ExtendedDeviceInventory
    Assert ($partialCatalog.Info.NodeFlagsRead -eq 0 -and $partialCatalog.Info.PropertyReadErrors -gt 0 -and $partialCatalog.Devices.Count -eq 6) 'Unavailable hiding-flag reads preserve the catalog and expose incomplete coverage'
    function Get-ClassHiddenState {throw 'Simulated native property API unavailable'}
    $noClassCatalog=Get-ExtendedDeviceInventory
    Assert ($noClassCatalog.Devices.Count -eq 6 -and $noClassCatalog.Info.ClassFlagsRead -eq 0) 'Unavailable class-visibility APIs cannot discard otherwise readable device records'
    $beforeExtendedSave=@(Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports') -Filter '*.json' | ForEach-Object FullName)
    Save-Reports
    $extendedSaved=@(Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports') -Filter '*.json' | Where-Object {$_.FullName -notin $beforeExtendedSave})
    $savedCatalog=Read-SavedReport $extendedSaved[0].FullName
    Assert ($savedCatalog.'Extended device inventory'.Count -eq 6 -and $savedCatalog.'Extended scan info'.Captured) 'Extended devices and their separate capture metadata survive JSON save/import'
    $extendedTxt=[IO.File]::ReadAllText([IO.Path]::ChangeExtension($extendedSaved[0].FullName,'.txt'))
    Assert ($extendedTxt -match 'Extended scan / separate capture' -and $extendedTxt -match 'MODEL-A' -and $extendedTxt -match 'GENERAL-A') 'TXT export includes the extended catalog and every model ID'
    Set-Item Function:Get-CimInstance -Value $extendedPreserved.Cim
    function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Refreshed hidden';Present=$true;DeviceInstanceId='USB\FRESH';HardwareID=@('FRESH-ID');HiddenByNodeFlag=$true});Info=[ordered]@{Captured='NEW-CAPTURE';Records=1;Source='Synthetic refresh'}}}
    $script:rendered.Clear()
    $fullWithExtended=Invoke-HardwareScan 7 -IncludeExtended $true
    Assert ($fullWithExtended.Inventory['Extended device inventory'][0].DeviceInstanceId -eq 'USB\FRESH' -and $fullWithExtended.Inventory['Report info'].ExtendedStatus -eq 'Refreshed') 'Full rescans refresh the optional extended catalog instead of silently dropping it'
    Assert ($fullWithExtended.Inventory['Scan timing'].Count -eq 17 -and $scanStep -eq 17) 'Refreshing an extended catalog does not corrupt normal seventeen-query timing and progress'
    Assert (@($script:rendered | Where-Object {$_.Text -match '^\s+Finished:.*extended READ'}).Count -eq 1) 'The scan finish line explicitly confirms a requested extended read'
    function Get-ExtendedDeviceInventory {throw 'Simulated extended refresh failure'}
    $completionCim=(Get-Item Function:Get-CimInstance).ScriptBlock
    function Get-CimInstance {param($ClassName,$Filter,$OperationTimeoutSec,$Property,$Namespace) [pscustomobject]@{Name='Completion fixture';DeviceID='MOCK';PNPDeviceID='USB\COMPLETE';UUID='MOCK';SerialNumber='MOCK';TotalPhysicalMemory=8GB}}
    $script:rendered.Clear()
    try {$fullPartial=Invoke-HardwareScan 8 -IncludeExtended $true}finally {Set-Item Function:Get-CimInstance -Value $completionCim}
    Assert ($fullPartial.Completed -and -not $fullPartial.Inventory.Contains('Extended device inventory') -and $fullPartial.Inventory['Report info'].ExtendedStatus -eq 'Unavailable') 'A failed extended refresh keeps new normal data and cannot attach stale extended records'
    Assert ($fullPartial.Inventory['Extended scan info'].Error -and @($fullPartial.Warnings | Where-Object {$_ -match '^Extended device inventory:'}).Count -eq 1) 'Failed extended refresh diagnostics are captured once with the new snapshot'
    Assert (@($script:rendered | Where-Object {$_.Text -match '^\s+Finished:.*extended NOT READ' -and $_.Color -eq $palette.Warn}).Count -eq 1) 'A failed optional scan ends with an amber extended NOT READ completion line'
    Assert (@($fullPartial.Inventory['Scan timing'] | Where-Object Status -ne 'UNAVAILABLE').Count -eq 17 -and $fullPartial.Warnings.Count -eq 1) 'Extended failure stays visible even when every normal section was read successfully'
    $report=$fullPartial.Inventory;$warnings=$fullPartial.Warnings
    $script:rendered.Clear()
    Show-ControlDeck
    Assert (($script:rendered.Text -join ' ') -match 'SCAN PARTIAL.*extended not read') 'Dashboard cannot claim a complete scan when the requested extended refresh failed'
    function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Recovered catalog';DeviceInstanceId='USB\RECOVERED';HardwareID=@('RECOVERED')});Info=[ordered]@{Captured='RECOVERED';Records=1;Source='Synthetic retry'}}}
    Start-ExtendedDeviceScan
    Assert ($report['Report info'].ExtendedStatus -eq 'Refreshed' -and @($warnings | Where-Object {$_ -match '^Extended device inventory:'}).Count -eq 0) 'A separate extended retry clears the failed rescan status and obsolete warning'
}finally {
    $report=$extendedPreserved.Report;$ownedConsole=$extendedPreserved.Owned;$redirected=$extendedPreserved.Redirected
    Set-Item Function:Get-ClassHiddenState -Value $extendedPreserved.Class
    Set-Item Function:Get-NativeNodeStatus -Value $extendedPreserved.Native
    Set-Item Function:Get-ExtendedDeviceInventory -Value $extendedPreserved.Inventory
    Set-Item Function:Get-CimInstance -Value $extendedPreserved.Cim
    Remove-Item Function:Get-PnpDevice -ErrorAction SilentlyContinue
    Remove-Item Function:Get-PnpDeviceProperty -ErrorAction SilentlyContinue
}
Assert (-not (Get-RuntimeCompatibility '2.0' 'Win32NT' 'FullLanguage').Supported -and -not (Get-RuntimeCompatibility '5.0' 'Win32NT' 'FullLanguage').Supported) 'Unsupported engine versions receive a compatibility result before feature use'
Assert ((Get-RuntimeCompatibility '5.1' 'Win32NT' 'FullLanguage').Supported -and (Get-RuntimeCompatibility '7.6.5' 'Win32NT' 'FullLanguage').Supported) 'Windows PowerShell 5.1 and PowerShell 7 satisfy runtime requirements'
Assert ((Get-RuntimeCompatibility '7.7.0-preview.1' 'Win32NT' 'FullLanguage').Supported) 'Runtime requirement checks tolerate a PowerShell prerelease version suffix'
Assert (-not (Get-RuntimeCompatibility '7.6.5' 'Unix' 'FullLanguage').Supported) 'Non-Windows platforms receive an explicit unsupported-platform result'
Assert (-not (Get-RuntimeCompatibility '5.1' 'Win32NT' 'ConstrainedLanguage').Supported) 'Restricted language mode is disclosed rather than bypassed'
Assert (-not (Test-DedicatedConsoleSupport '6.1.7601') -and -not (Test-DedicatedConsoleSupport '10.0.17763')) 'Older Windows builds use their existing console instead of newer conhost switches'
Assert ((Test-DedicatedConsoleSupport '10.0.19041') -and (Test-DedicatedConsoleSupport '10.0.26100')) 'Modern Windows builds permit the dedicated readable-console attempt'
$compatPreserved=[pscustomobject]@{Cim=(Get-Item Function:Get-CimInstance).ScriptBlock;Report=$report}
try {
    $script:cimAvailable=$true;$script:wmiAvailable=$true;$script:cimFails=$false;$script:wmiCalls=0;$script:missingJson=$false
    function Get-CimInstance {
        param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec,$ErrorAction)
        if($script:cimFails){throw 'Simulated access denied'}
        [pscustomobject]@{Backend='CIM';ClassName=$ClassName;Namespace=$Namespace;Filter=$Filter;Properties=$Property;Timeout=$OperationTimeoutSec}
    }
    function Get-WmiObject {
        param($Class,$Namespace,$Property,$Filter,$ErrorAction)
        $script:wmiCalls++
        [pscustomobject]@{Backend='WMI';ClassName=$Class;Namespace=$Namespace;Filter=$Filter;Properties=$Property}
    }
    function Get-Command {
        param($Name,$ErrorAction)
        if($Name -eq 'Get-CimInstance'){if($script:cimAvailable){return (Get-Item Function:Get-CimInstance)};return $null}
        if($Name -eq 'Get-WmiObject'){if($script:wmiAvailable){return (Get-Item Function:Get-WmiObject)};return $null}
        if($Name -eq 'Get-PnpDeviceProperty'){return $null}
        if($script:missingJson -and $Name -in @('ConvertTo-Json','ConvertFrom-Json')){return $null}
        Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue
    }
    $modern=Get-HwidInstance Win32_Processor -Filter 'DeviceID="CPU0"' -Property Name,ProcessorId -OperationTimeoutSec 30
    Assert ((Get-QueryBackend) -eq 'CIM' -and $modern.Backend -eq 'CIM' -and $modern.Timeout -eq 30 -and $modern.Properties.Count -eq 2) 'Compatibility reader prefers CIM and preserves filters, requested properties and timeout'
    $script:cimFails=$true;$accessFailure=$false
    try {Get-HwidInstance Win32_Processor | Out-Null}catch{$accessFailure=$true}
    Assert ($accessFailure -and $script:wmiCalls -eq 0) 'A CIM access failure is not retried through another API to evade the failure'
    $script:cimAvailable=$false
    $legacy=Get-HwidInstance Win32_Processor -Namespace 'root/cimv2' -Filter 'DeviceID="CPU0"' -Property Name,ProcessorId
    Assert ((Get-QueryBackend) -eq 'Legacy WMI' -and $legacy.Backend -eq 'WMI' -and $legacy.ClassName -eq 'Win32_Processor' -and $legacy.Filter -eq 'DeviceID="CPU0"' -and $legacy.Properties.Count -eq 2) 'Missing CIM commands use an available legacy WMI reader with equivalent query selection'
    $script:wmiAvailable=$false;$noReader=$false
    try {Get-HwidInstance Win32_Processor | Out-Null}catch{$noReader=$_.Exception.Message -match 'No CIM or legacy WMI reader'}
    Assert ($noReader -and (Get-QueryBackend) -eq 'Unavailable') 'Missing CIM and WMI readers produce a specific compatibility error instead of fabricated inventory'
    $capabilities=Get-CompatibilityInfo
    Assert ($capabilities.PowerShellVersion -and $capabilities.WindowsVersion -and $capabilities.MissingCommands -contains 'Get-PnpDeviceProperty') 'Compatibility details expose runtime versions and unavailable optional commands'
    $script:missingJson=$true;$script:rendered.Clear()
    Save-Reports
    Assert (($script:rendered.Text -join ' ') -match 'JSON reports are unavailable.*missing ConvertTo-Json') 'Missing JSON support gives an actionable save error before writing report files'
    $jsonUnavailable=$false
    try {Read-SavedReport 'not-a-file.json' | Out-Null}catch{$jsonUnavailable=$_.Exception.Message -match 'JSON import is unavailable'}
    Assert $jsonUnavailable 'Missing JSON support is not misreported as a corrupted input file'
}finally {
    Remove-Item Function:Get-Command -ErrorAction SilentlyContinue
    Remove-Item Function:Get-WmiObject -ErrorAction SilentlyContinue
    Set-Item Function:Get-CimInstance -Value $compatPreserved.Cim
    $report=$compatPreserved.Report
}
# Count actual main-loop page waits, so cancellation cannot hide behind redirected output.
$summaryPreserved=@{Report=$report;Warnings=$warnings;Ids=$identifiers;Extended=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock;Scan=(Get-Item Function:Invoke-HardwareScan).ScriptBlock}
try {
    $fixture=[ordered]@{'Report info'=[ordered]@{Computer='SUMMARY';Generated='2026-10-26T12:00:00Z';ScanSeconds=1.2;ScanNumber=1}}
    foreach($name in @($sectionGroups.Values | ForEach-Object {$_})){$fixture[$name]=@([pscustomobject]@{Name='Fixture'})}
    $fixture['PnP hardware IDs']=@(
        [pscustomobject]@{DeviceInstanceId='TEST\A';PNPClass=' Net ';ConfigManagerErrorCode=0;HardwareID=@('MODEL')},
        [pscustomobject]@{DeviceInstanceId='TEST\B';PNPClass='NET';ConfigManagerErrorCode=0},
        [pscustomobject]@{DeviceInstanceId='TEST\C';PNPClass='net';ConfigManagerErrorCode=0},
        [pscustomobject]@{DeviceInstanceId='TEST\D';PNPClass='Display';ConfigManagerErrorCode=0}
    )
    $ids=@([pscustomobject]@{Quality='Missing';Section='BIOS';Field='SerialNumber';Device=''},[pscustomobject]@{Quality='Placeholder';Section='Motherboard';Field='SerialNumber';Device='';Value='OEM'},[pscustomobject]@{Quality='Reported';Section='CPU';Field='ProcessorId';Device='CPU0';Value='FOUND'})
    $summary=Get-OverviewSummary $fixture $ids @()
    Assert ($summary.Classes -eq 2 -and $summary.Nodes -eq 4) 'Summary class totals ignore casing and edge spaces while record counts remain distinct'
    Assert ($fixture['PnP hardware IDs'][0].PNPClass -ceq ' Net ') 'Summary normalization leaves the raw captured class text intact'
    Assert ($summary.ReviewTotal -eq 2 -and $summary.Complete -and $summary.NotRead -eq 0) 'Summary separates successful query reads from missing/default identifier findings'
    $report=$fixture;$identifiers=$ids;$warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:rendered.Clear();Show-Overview
    Assert (@($script:rendered | Where-Object {$_.Text -match 'Review: 2 findings' -and $_.Color -eq $palette.Warn}).Count -eq 1) 'Missing/default IDs keep the summary review line amber rather than a false green zero'
    Assert (($script:rendered.Text -join ' ') -match '4 records / 2 classes / 1 with hardware IDs') 'Summary states record and hardware-ID units explicitly'
    $fixture['CPU']=@{Unavailable='Synthetic blocked read'}
    Assert ((Get-OverviewSummary $fixture $ids @('CPU: Synthetic blocked read')).NotRead -eq 1) 'Summary shows explicit unread normal-query counts'
    $fixture['CPU']=@([pscustomobject]@{Name='Fixture'})
    $fixture['Report info']['ExtendedStatus']='Unavailable';$fixture['Report info']['ExtendedAttempted']='2026-10-26T13:00:00Z'
    $summary=Get-OverviewSummary $fixture $ids @()
    Assert ($summary.ExtendedState -eq 'NOT READ' -and -not $summary.Complete -and $summary.ExtendedCaptured -eq '2026-10-26T13:00:00Z') 'A first extended failure is not mislabeled as never scanned'
    $fixture['Extended scan info']=[ordered]@{Captured='2026-10-26T12:30:00Z';Error='Older failed attempt'}
    Assert ((Get-OverviewSummary $fixture $ids @()).ExtendedCaptured -eq '2026-10-26T13:00:00Z') 'A newer failed attempt does not display the timestamp from an older failed capture'
    $fixture['Extended scan info']=[ordered]@{Captured='2026-10-26T12:30:00Z';Source='Previous fixture'}
    $fixture['Extended device inventory']=@(
        [pscustomobject]@{Present=$false;HiddenByNodeFlag=$true;HiddenByClass=$true},
        [pscustomobject]@{Present=$true;HiddenByNodeFlag=$false;HiddenByClass=$false},
        [pscustomobject]@{Present=$null;HiddenByNodeFlag=$null;HiddenByClass=$null}
    )
    $summary=Get-OverviewSummary $fixture $ids @()
    Assert ($summary.ExtendedState -eq 'STALE' -and -not $summary.Complete -and $summary.Known -eq 3) 'Retained extended records are labeled stale when the latest attempt failed'
    Assert ($summary.PresenceUnknown -eq 1 -and $summary.Remembered -eq 1 -and $summary.Hidden -eq 1) 'Extended summary keeps unknown presence separate from remembered and overlapping hiding flags'
    $script:rendered.Clear();Show-Overview
    Assert (($script:rendered.Text -join ' ') -match 'PREVIOUS catalog.*refresh NOT READ' -and ($script:rendered.Text -join ' ') -match '2026-10-26 12:30:00') 'Summary displays the older capture time with a clear refresh-failed label'
    $oldCatalog=$fixture['Extended device inventory'];$oldInfo=$fixture['Extended scan info']
    function Get-ExtendedDeviceInventory {throw [TimeoutException]::new('Synthetic timeout')}
    Start-ExtendedDeviceScan;Start-ExtendedDeviceScan
    Assert ([object]::ReferenceEquals($oldCatalog,$report['Extended device inventory']) -and [object]::ReferenceEquals($oldInfo,$report['Extended scan info'])) 'Repeated manual failures preserve the last good extended catalog and capture together'
    Assert (@($warnings | Where-Object {$_ -like 'Extended device inventory: *'}).Count -eq 1 -and $report['Warnings'].Count -eq 1) 'Repeated extended failures produce one current review warning rather than duplicates'
    Assert ($report['Report info'].ExtendedFailureCode -eq 'READ-02' -and $report['Report info'].ExtendedAttempted) 'Manual failure metadata retains its typed reason and attempt timestamp'
    $script:rendered.Clear();Show-Attention
    Assert (($script:rendered.Text -join ' ') -match 'Provider timed out.*READ-02' -and ($script:rendered.Text -join ' ') -match '\[9\] > \[4\]') 'Review uses the stored extended failure category and extended retry action'
    function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{DeviceInstanceId='EXT\NEW';Present=$true;HiddenByNodeFlag=$false;HiddenByClass=$false;ConfigManagerErrorCode=0});Info=[ordered]@{Captured='2026-10-26T14:00:00Z';Source='Recovered fixture'}}}
    Start-ExtendedDeviceScan
    Assert ($report['Report info'].ExtendedStatus -eq 'Refreshed' -and -not $report['Report info'].ExtendedFailureCode -and -not $report['Report info'].ExtendedAttempted -and $warnings.Count -eq 0) 'Successful extended refresh clears stale failure metadata and warnings'
    Assert ((Get-OverviewSummary $report $ids $warnings).ExtendedState -eq 'READ' -and (Get-OverviewSummary $report $ids $warnings).Complete) 'Recovered summary returns to current readable catalog status'
    $fixture.Remove('Extended scan info');$fixture.Remove('Extended device inventory');$fixture['Report info']['ExtendedStatus']='Unavailable'
    function Invoke-HardwareScan {param($ScanNumber,[bool]$UseWorker,[bool]$IncludeExtended) $script:summaryExtendedRequested=$IncludeExtended;throw 'Synthetic scan stop'}
    Start-HardwareRescan -UseWorker $false
    Assert $script:summaryExtendedRequested 'PC rescan retries an explicitly requested extended scan even if the first attempt produced no catalog'
} finally {$report=$summaryPreserved.Report;$warnings=$summaryPreserved.Warnings;$identifiers=$summaryPreserved.Ids;Set-Item Function:Get-ExtendedDeviceInventory -Value $summaryPreserved.Extended;Set-Item Function:Invoke-HardwareScan -Value $summaryPreserved.Scan}
$unreadPreserved=@{Report=$report;Warnings=$warnings;Step=$script:scanStep;Timings=$script:scanTimings;Worker=$script:scanQueryWorker}
try {
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    foreach($mode in @('Direct','Worker')) {
        $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
        try {
            $queryFailure=$null;$partialOutput=@()
            try {$partialOutput=@(Invoke-ScanQuery {[pscustomobject]@{SerialNumber='PARTIAL'};Write-Error -Message 'Synthetic denied read' -Category PermissionDenied -ErrorAction Continue;[pscustomobject]@{SerialNumber='AFTER-ERROR'}})}catch{$queryFailure=$_}
            Assert ($null -ne $queryFailure -and $partialOutput.Count -eq 0) ($mode+' queries reject partial output when an uncaught non-terminating error occurs')
            Assert ((Get-ScanFailureInfo $queryFailure).Code -eq 'READ-01') ($mode+' non-terminating errors retain their permission category')
            Section ($mode+' partial read') {[pscustomobject]@{SerialNumber='PARTIAL'};Write-Error -Message 'Synthetic denied read' -Category PermissionDenied -ErrorAction Continue}
            Assert ($report[$mode+' partial read'].FailureCode -eq 'READ-01' -and $script:scanTimings[-1].Status -eq 'UNAVAILABLE' -and $script:scanTimings[-1].Results -eq 0) ($mode+' scans never count partial error output as successfully captured records')
            $fallback=@(Invoke-ScanQuery {try{throw [UnauthorizedAccessException]::new('Synthetic primary failure')}catch{};[pscustomobject]@{SerialNumber='FALLBACK'}})
            Assert ($fallback.Count -eq 1 -and $fallback[0].SerialNumber -eq 'FALLBACK') ($mode+' queries keep successful fallbacks after internally handled failures')
            $recovered=@(Invoke-ScanQuery {[pscustomobject]@{SerialNumber='CLEAN'}})
            Assert ($recovered.Count -eq 1 -and $recovered[0].SerialNumber -eq 'CLEAN') ($mode+' query failure does not leak errors or partial data into the next query')
        } finally {if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    }
    $invalidCases=@(
        @{Name='Scalar string';Query={'Unusable provider text'}},
        @{Name='Scalar boolean';Query={$false}},
        @{Name='Scalar number';Query={0}},
        @{Name='Empty object';Query={[pscustomobject]@{}}},
        @{Name='Empty dictionary';Query={@{}}},
        @{Name='Mixed malformed';Query={[pscustomobject]@{SerialNumber='PARTIAL'};'Unusable provider text'}}
    )
    foreach($case in $invalidCases) {
        Section $case.Name $case.Query
        Assert ($report[$case.Name].FailureCode -eq 'READ-06' -and $script:scanTimings[-1].Status -eq 'UNAVAILABLE' -and $script:scanTimings[-1].Results -eq 0) ($case.Name+' is invalid scan data rather than a successful hardware record')
    }
    Section 'Missing ID valid record' {[pscustomobject]@{SerialNumber=$null;Name='Known component'}}
    Assert ((Test-SectionReadable $report['Missing ID valid record']) -and $script:scanTimings[-1].Status -eq 'CHECK') 'A valid record with a missing ID remains readable and distinct from malformed query output'
    Section 'False zero and list values' {[pscustomobject]@{Name='Fixture';Enabled=$false;Capacity=0;Paths=@()}}
    Assert ($script:scanTimings[-1].Status -eq 'READ' -and $report['False zero and list values'][0].Enabled -eq $false -and $report['False zero and list values'][0].Capacity -eq 0 -and $report['False zero and list values'][0].Paths.Count -eq 0) 'Valid false zero and empty-list property values survive unreadable-data validation'
    Assert (-not (Test-SectionReadable @([pscustomobject]@{Unavailable=''})) -and -not (Test-SectionReadable @(@{Unavailable=$null}))) 'Empty unavailable-marker messages cannot masquerade as readable sections'
    Section 'Blank unavailable marker' {[pscustomobject]@{Unavailable=''}}
    Assert ($report['Blank unavailable marker'].Unavailable -match 'without a diagnostic message' -and $script:scanTimings[-1].Status -eq 'UNAVAILABLE') 'Blank unavailable markers receive an explicit failure explanation'
    Assert ((Get-ScanFailureInfo ([IO.InvalidDataException]::new('Synthetic invalid record'))).Code -eq 'READ-06') 'Invalid-data exceptions receive a specific scan code and next step'
} finally {$report=$unreadPreserved.Report;$warnings=$unreadPreserved.Warnings;$script:scanStep=$unreadPreserved.Step;$script:scanTimings=$unreadPreserved.Timings;$script:scanQueryWorker=$unreadPreserved.Worker}
$fallbackScanWorker=$script:scanQueryWorker
try {
    foreach($mode in @('Direct','Worker')) {
        $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
        try {
            $fallback=@(Invoke-ScanQuery {
                function Get-NetAdapter {return $null}
                function Get-CimInstance {[pscustomobject]@{Name='Recovered NIC';InterfaceGuid='NIC-NULL';NetworkAddresses=@('001122334455')}}
                Get-NetworkIdentifiers
            })
            Assert ($fallback.Count -eq 1 -and $fallback[0].Name -eq 'Recovered NIC' -and $fallback[0].CollectionSource -match 'fallback') ($mode+' network scan retries after null-only primary output')
            $failure=$null
            try {Invoke-ScanQuery {
                function Get-NetAdapter {throw 'Access denied by primary reader'}
                function Get-CimInstance {return $null}
                Get-NetworkIdentifiers
            } | Out-Null}catch{$failure=$_}
            Assert ($null -ne $failure -and (Get-ScanFailureInfo $failure).Code -eq 'READ-04') ($mode+' null-only network fallback is no records rather than a blank successful adapter or primary access error')
            foreach($reader in @('Network','Extended')) {
                foreach($case in @('Permission','Timeout','Category','Provider')) {
                    $query=[scriptblock]::Create((@'
function Get-NetAdapter {throw 'Access denied by primary reader'}
function Get-PnpDevice {throw 'Access denied by primary reader'}
function Get-CimInstance {
    switch('__CASE__') {
        'Permission' {throw [UnauthorizedAccessException]::new('Acces refuse - test')}
        'Timeout' {throw [TimeoutException]::new('Delai depasse - test')}
        'Category' {Write-Error -Message 'Lecture refusee - test' -Category PermissionDenied -ErrorAction Stop}
        'Provider' {throw 'Invalid class in fallback reader'}
    }
}
__READER__
'@).Replace('__CASE__',$case).Replace('__READER__',$(if($reader -eq 'Network'){'Get-NetworkIdentifiers'}else{'Get-ExtendedDeviceInventory'})))
                    $failure=$null
                    try {Invoke-ScanQuery $query | Out-Null}catch{$failure=$_}
                    $info=Get-ScanFailureInfo $failure
                    $expected=switch($case){'Permission'{'READ-01'};'Timeout'{'READ-02'};'Category'{'READ-01'};'Provider'{'READ-03'}}
                    Assert ($null -ne $failure -and $info.Code -eq $expected -and $info.Details -match 'Primary:.*Fallback:') ($mode+' '+$reader+' fallback retains both diagnostics and the final '+$case+' failure classification')
                }
            }
        }finally {if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    }
}finally {$script:scanQueryWorker=$fallbackScanWorker}
$reviewPreserved=@{Report=$report;Warnings=$warnings;Ids=$identifiers}
try {
    $ambiguousDisks=[ordered]@{
        'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='A'},[pscustomobject]@{Index=0;SerialNumber='B'})
        'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='A'})
    }
    $ambiguousQuick=@(Get-QuickDisks $ambiguousDisks)
    Assert (@($ambiguousQuick | Where-Object Quality -eq 'Conflict').Count -eq 0) 'Duplicate primary disk indices cannot create a false cross-source serial clash'
    Assert ($ambiguousQuick.Count -eq 3 -and @($ambiguousQuick | Where-Object Note -match 'sources not joined').Count -eq 2) 'Ambiguous disk records are retained separately with matching explanation'
    $ambiguousDisks['Physical disks']=@([pscustomobject]@{Index=0;SerialNumber=''},[pscustomobject]@{Index=0;SerialNumber=''})
    Assert (@(Get-QuickDisks $ambiguousDisks | Where-Object Quality -eq 'Missing').Count -eq 2) 'Ambiguous indices cannot fill two missing serials from one alternate record'
    $duplicateSecondary=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='A'});'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='B'},[pscustomobject]@{Number=0;SerialNumber='C'})}
    Assert (@(Get-QuickDisks $duplicateSecondary).Count -eq 3 -and @(Get-QuickDisks $duplicateSecondary | Where-Object Quality -eq 'Conflict').Count -eq 0) 'Duplicate alternate disk numbers are not joined by guesswork'
    $badNumbers=[ordered]@{'Physical disks'=@($null,[pscustomobject]@{Index='bad';SerialNumber='A'});'Storage identifiers'=@($null,[pscustomobject]@{Number='bad';SerialNumber='B'})}
    Assert (@(Get-QuickDisks $badNumbers).Count -eq 2 -and @(Get-QuickDisks $badNumbers | Where-Object Quality -eq 'Conflict').Count -eq 0) 'Invalid disk indices and null rows cannot crash or create fake disk clashes'
    Assert ($null -eq (Get-DiskNumber -1) -and $null -eq (Get-DiskNumber '') -and $null -eq (Get-DiskNumber $false)) 'Negative blank and boolean disk numbers are not reliable matching keys'
    Assert ((Get-DiskNumber 0) -eq 0 -and (Get-DiskNumber '4294967295') -eq [uint32]::MaxValue) 'Disk matching supports zero and the full Windows unsigned disk-number range'
    $wideDisk=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=[uint32]::MaxValue;SerialNumber='A'});'Storage identifiers'=@([pscustomobject]@{Number=[uint32]::MaxValue;SerialNumber='B'})}
    Assert (@(Get-QuickDisks $wideDisk | Where-Object Quality -eq 'Conflict').Count -eq 1) 'Large valid disk numbers do not overflow the matching set'
    $clash=[ordered]@{'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='A / literal'});'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='B'})}
    $clashRow=@(Get-QuickDisks $clash)[0]
    Assert ($clashRow.PrimaryValue -ceq 'A / literal' -and $clashRow.AlternateValue -ceq 'B') 'Conflict details preserve source serials separately even when serials contain delimiters'
    $conflictSummary=Get-ReviewSummary $clash @() @()
    Assert ($conflictSummary.ConflictCount -eq 1 -and $conflictSummary.Total -eq 1 -and $conflictSummary.DeviceCount -eq 0) 'A serial-only clash appears in the review summary even with no missing IDs'
    $pnpDuplicate=[ordered]@{'PnP hardware IDs'=@($usbKeyboard,$duplicateKeyboard)}
    $pnpSummary=Get-ReviewSummary $pnpDuplicate @() @($null,'')
    Assert ($pnpSummary.ConflictCount -eq 1 -and $pnpSummary.DeviceCount -eq 0 -and $pnpSummary.Total -eq 1 -and $pnpSummary.UnreadCount -eq 0) 'Repeated instance IDs count once as a conflict and do not inflate device findings'
    $summaryIds=@([pscustomobject]@{Quality='Missing'},[pscustomobject]@{Quality='Placeholder'},[pscustomobject]@{Quality='Reported'})
    $combined=Get-ReviewSummary $pnpDuplicate $summaryIds @('CPU: Invalid class')
    Assert ($combined.Total -eq 4 -and $combined.MissingCount -eq 1 -and $combined.DefaultCount -eq 1 -and $combined.UnreadCount -eq 1) 'Combined finding totals equal their displayed category counts'
    Assert ((Get-OverviewSummary $pnpDuplicate @() @()).Conflicts -eq 1 -and (Get-OverviewSummary $pnpDuplicate @() @()).DeviceIssues -eq 0) 'Overview classifies duplicate instance IDs consistently with review'
    Assert ((Get-DeviceReviewAction ([pscustomobject]@{Kind='Status';Code=22})) -match 'intentionally disabled') 'Disabled devices receive intent-aware advice rather than a repair claim'
    Assert ((Get-DeviceReviewAction ([pscustomobject]@{Kind='Status';Code=28})) -match 'driver') 'Missing-driver status has a specific next step'
    Assert ((Get-PnpStatus 45).Text -eq 'Not connected (code 45)') 'Disconnected status is named explicitly rather than a generic device failure'
    $report=$clash;$identifiers=@();$warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:rendered.Clear();Show-Attention
    $reviewText=$script:rendered.Text -join ' '
    Assert ($reviewText -match '1 findings / 1 conflicts' -and $reviewText -match 'CONFLICTS / VERIFY BEFORE COMPARING') 'Review summary and section expose a conflict-only report clearly'
    Assert ($reviewText -match 'Physical disks: A / literal' -and $reviewText -match 'Storage identifiers: B') 'Review displays both actual serial values with source labels'
    $report=[ordered]@{'PnP hardware IDs'=@([pscustomobject]@{Name='';DeviceInstanceId='USB\NO-NAME';ConfigManagerErrorCode=22})}
    $script:rendered.Clear();Show-Attention
    Assert (($script:rendered.Text -join ' ') -match 'USB\\NO-NAME / Disabled' -and ($script:rendered.Text -join ' ') -match 'intentionally disabled') 'Unnamed device findings identify their instance and show the relevant next step'
    $identifiers=@([pscustomobject]@{Section='BIOS';Device='';Field='SerialNumber';Quality='Placeholder';Value=('OEM'+[char]27+'[31m')})
    $script:rendered.Clear();Show-Attention
    Assert (-not (($script:rendered.Text -join '')).Contains([string][char]27)) 'Untrusted placeholder values cannot inject console escape controls into review'
} finally {$report=$reviewPreserved.Report;$warnings=$reviewPreserved.Warnings;$identifiers=$reviewPreserved.Ids}
$script:pageWaits=0
function Wait-UiPage { $script:pageWaits++ }
$script:answers.Clear()
@('3','0','7','','9','0','0') | ForEach-Object {$script:answers.Enqueue($_)}
$cancelTestCode=$interactiveTestCode.Replace('function Wait-UiPage(', 'function Original-UiPageWait(')
. ([scriptblock]::Create($cancelTestCode))
Assert ($script:pageWaits -eq 0) 'Category Back and canceled comparison skip the main-loop page wait'
Assert ($script:answers.Count -eq 0) 'Canceled navigation leaves subsequent menu choices intact'
$script:pageWaits=0
@('9','1','9','3','0') | ForEach-Object {$script:answers.Enqueue($_)}
. ([scriptblock]::Create($cancelTestCode))
Assert ($script:answers.Count -eq 0 -and $script:pageWaits -eq 2 -and $report['Report info'].ScanNumber -eq 2) 'Numeric menus support rescan and reopening its changes without restarting the checker'
$script:pageWaits=0
@('9','1','9','3','0') | ForEach-Object {$script:answers.Enqueue($_)}
& ([scriptblock]::Create($cancelTestCode))
Assert ($script:answers.Count -eq 0 -and $report['Report info'].ScanNumber -eq 2 -and $report['Scan timing'].Count -eq 17) 'Launching through a child script scope publishes rescan state to the actual menu'
Assert ($lastScanPrevious['Report info'].ScanNumber -eq 1 -and $warnings.Count -eq $report['Warnings'].Count) 'Nested launcher scopes keep the previous baseline and current warnings in sync'
$saveFolder=Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
$beforeRescanSave=@(Get-ChildItem -LiteralPath $saveFolder -Filter '*.json' | ForEach-Object FullName)
Save-Reports
$rescanSaved=@(Get-ChildItem -LiteralPath $saveFolder -Filter '*.json' | Where-Object {$_.FullName -notin $beforeRescanSave})
Assert ($rescanSaved.Count -eq 1 -and (Read-SavedReport $rescanSaved[0].FullName).'Report info'.ScanNumber -eq 2) 'Saving after a rescan exports the newly active snapshot'
Assert (@((Read-SavedReport $rescanSaved[0].FullName).'Scan timing').Count -eq 17) 'Saved rescans retain only the latest seventeen query timings'
[Console]::WriteLine("All $script:checks checks passed under PowerShell $($PSVersionTable.PSVersion). Synthetic reports: $testFolder")
