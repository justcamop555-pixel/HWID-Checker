$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat')) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$assignment=$ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false)|Select-Object -First 1
. ([scriptblock]::Create($assignment.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$lines=New-Object 'System.Collections.Generic.List[string]'
function Reset-UiPage {}
function Start-UiReport {}
function Add-ReportBookmark($Key) {}
function Write-Heading($Title){$lines.Add($Title)}
function Write-PnpValue($Label,$Value,$Color){$lines.Add($Label+': '+$Value)}
$checks=0
function Assert($value,$name){if(-not $value){throw ('FAILED: '+$name)};$script:checks++;[Console]::WriteLine('PASS: '+$name)}
$old=[ordered]@{'Report info'=@{Version='3.92';Computer='TEST';Generated='2026-11-12T12:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='0001'},[pscustomobject]@{DeviceID='CPU0';ProcessorId='0002'});'Memory modules'=@([pscustomobject]@{SerialNumber='001'},[pscustomobject]@{SerialNumber='002'})}
$new=[ordered]@{'Report info'=@{Version='3.92';Computer='TEST';Generated='2026-11-12T13:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='0003'});'Memory modules'=@([pscustomobject]@{SerialNumber='003'},[pscustomobject]@{SerialNumber='004'})}
$comparison=Compare-Inventories $old $new
Assert ($comparison.PreviousCount -eq 0 -and $comparison.CurrentCount -eq 0 -and $comparison.Changes.Count -eq 0) 'Ambiguous and unkeyed records cannot produce guessed identifier changes'
Assert ($comparison.UnkeyedSections -contains 'Memory modules' -and $comparison.AmbiguousDevices.Count -eq 1) 'Comparison retains distinct missing-key and duplicate-key reasons'
Show-ComparisonResult $old $new $comparison 'synthetic.json'
$render=$lines -join "`n"
Assert ($render -match 'No identifiers could be compared' -and $render -match 'NOT COMPARED') 'An empty comparable set displays its explanation without aborting the report'
Assert ($render -match 'Slot or instance keys were missing' -and $render -match 'CPU / DeviceID=CPU0' -and $render -notmatch 'No identifier differences found') 'The BAT retains matching diagnostics instead of claiming unchanged IDs'
[Console]::WriteLine("All $checks comparison-coverage checks passed.")
