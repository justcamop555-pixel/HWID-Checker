$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
$fixtures=[ordered]@{
    'System identity'=@{IdentifyingNumber='SN-0001'}
    CPU=@{DeviceID='CPU0';ProcessorId='CPU-0001'}
    Motherboard=@{SerialNumber='BOARD-0001'}
    BIOS=@{SerialNumber='BIOS-0001'}
    Chassis=@{SerialNumber='CASE-0001'}
    'Memory modules'=@{DeviceLocator='A1';BankLabel='BANK0';SerialNumber='RAM-0001'}
    'Physical disks'=@{Index=0;SerialNumber='DISK-0001'}
    'Storage identifiers'=@{Number=0;UniqueId='STORAGE-0001'}
    Volumes=@{DeviceID='C:';VolumeSerialNumber='VOL-0001'}
    'Graphics adapters'=@{PNPDeviceID='PCI\DISPLAY-0001'}
    'Network adapters'=@{InterfaceGuid='01234567-89ab-cdef-0123-456789abcdef';MacAddress='001122334455'}
    'Windows Machine GUID'=@{MachineGuid='12345678-89ab-cdef-0123-456789abcdef'}
    Monitors=@{InstanceName='DISPLAY\MONITOR-0001';SerialNumber='MON-0001'}
}
$old=[ordered]@{'Report info'=@{Version='3.53';Computer='TEST';Generated='2026-10-28T12:00:00Z'}}
$current=[ordered]@{'report INFO'=@{version='3.53';computer='TEST';generated='2026-10-28T13:00:00Z'}}
foreach($section in $fixtures.Keys){
    $old[$section]=@([pscustomobject]$fixtures[$section])
    $fields=[ordered]@{};foreach($field in $fixtures[$section].Keys){$fields[$field.ToLowerInvariant()]=$fixtures[$section][$field]}
    $current[$section.ToLowerInvariant()]=@([pscustomobject]$fields)
}
$root=Join-Path $PSScriptRoot ('test-output-comparison-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$path=Join-Path $root 'case-varied.json';[IO.File]::WriteAllText($path,($current | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$imported=Read-SavedReport $path
$comparison=Compare-Inventories $old $imported
Assert ($comparison.Changes.Count -eq 0 -and $comparison.PreviousCount -eq $comparison.CurrentCount -and $comparison.PreviousCount -gt 0) 'JSON name capitalization alone cannot create identifier changes'
foreach($section in $fixtures.Keys){
    $rows=@(Get-IdentifierRows $imported | Where-Object Section -eq $section)
    Assert ($rows.Count -gt 0 -and @($rows | Where-Object {$_.Section -cne $section}).Count -eq 0 -and @($rows | Where-Object {$_.Field -cnotmatch $identifierPattern}).Count -eq 0) ($section+' identifier rows use stable section and field names')
}
Assert ($imported.cpu[0].PSObject.Properties.Name -ccontains 'processorid' -and $imported.cpu[0].processorid -ceq 'CPU-0001') 'Comparison normalization preserves original imported field names and values'
$imported.cpu[0].processorid='cpu-0001'
$details=@(Get-ComparisonDetails (Compare-Inventories $old $imported))
Assert ($details.Count -eq 1 -and $details[0].Section -ceq 'CPU' -and $details[0].Field -ceq 'ProcessorId' -and $details[0].Kind -eq 'Changed' -and $details[0].Previous -ceq 'CPU-0001' -and $details[0].Current -ceq 'cpu-0001') 'Actual case-only changes in identifier values retain exact OLD and NEW values'
$imported.cpu[0].processorid=$null
$comparison=Compare-Inventories $old $imported
Assert ($comparison.Changes.Count -eq 0 -and $comparison.SkippedFields -eq 1) 'Case-varied names cannot turn a missing current ID into a false removal'
foreach($section in @('System identity','Motherboard','BIOS','Chassis','Windows Machine GUID')){
    $field=if($section -eq 'System identity'){'IdentifyingNumber'}elseif($section -eq 'Windows Machine GUID'){'MachineGuid'}else{'SerialNumber'}
    $previous=[ordered]@{};$now=[ordered]@{}
    $previous[$section]=@([pscustomobject]@{$field='FIRST-ID'},[pscustomobject]@{$field='SECOND-ID'})
    $now[$section]=@([pscustomobject]@{$field='FIRST-ID'},[pscustomobject]@{$field='THIRD-ID'})
    $comparison=Compare-Inventories $previous $now
    Assert ($comparison.Changes.Count -eq 0 -and $comparison.UnkeyedSections -contains $section -and $comparison.SkippedSections -contains $section) ($section+' multiple unkeyed records are skipped rather than paired arbitrarily')
    $conflicts=@(Get-InventoryConflicts $previous)
    Assert ($conflicts.Count -eq 1 -and $conflicts[0].Section -eq $section -and $conflicts[0].Count -eq 2 -and $conflicts[0].Message -match 'no reliable device key') ($section+' ambiguous records remain visible as one review finding')
    $summary=Get-ReviewSummary $previous @() @()
    Assert ($summary.RecordConflicts.Count -eq 1) ($section+' record ambiguity reaches the warning and conflict summary')
}
$singleOld=[ordered]@{BIOS=@([pscustomobject]@{SerialNumber='0001'})}
$singleNow=[ordered]@{BIOS=@([pscustomobject]@{SerialNumber='0002'})}
Assert (@(Get-ComparisonDetails (Compare-Inventories $singleOld $singleNow)).Count -eq 1 -and @(Get-InventoryConflicts $singleOld).Count -eq 0) 'A single unkeyed firmware record remains comparable'
$duplicate=[ordered]@{BIOS=@([pscustomobject]@{SerialNumber='0001'},[pscustomobject]@{SerialNumber='0001'})}
Assert ((Compare-Inventories $duplicate $singleNow).Changes.Count -eq 0) 'Repeated identical unkeyed records cannot masquerade as a reliable single-device match'
[Console]::WriteLine("All $script:checks comparison-identity checks passed under PowerShell $($PSVersionTable.PSVersion).")
