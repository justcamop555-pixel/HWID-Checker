param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop';$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
foreach($name in @('$sectionGroups','$identifierPattern')){
    $assignment=$ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $name},$false) | Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$script:checks=0;$script:lines=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Message){if(-not $Condition){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:lines.Add([string]$Object)}
$ownedConsole=$false;$redirected=$true
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$iso='2026-11-11T12:34:56.1234567-04:00'
$display='2026-11-11 12:34:56 -04:00'
$info=[ordered]@{Version='3.0';Generated=$iso;SavedAt=$iso;Computer='SYNTHETIC-PC';Administrator=$false;Display='Desktop companion';QueryMode='Live progress';ExtendedStatus='Refreshed';ScanCompleted=$iso;ScanNumber=1}
$report=[ordered]@{'Report info'=$info;CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='SYNTHETIC-ID'});Warnings=@()}
$warnings=New-Object 'System.Collections.Generic.List[string]';$identifiers=@(Get-IdentifierRows $report)
$before=$report | ConvertTo-Json -Depth 12 -Compress
Assert ((Get-FieldLabel 'Generated' 'Report info') -ceq 'Captured at' -and (Get-FieldLabel 'Computer' 'Report info') -ceq 'PC name') 'Report metadata labels explain capture time and computer identity'
Assert ((Get-FieldLabel 'Version' 'Report info') -ceq 'Scanner version' -and (Get-FieldLabel 'Version' 'Windows') -ceq 'Version' -and (Get-FieldLabel 'Version' 'System identity') -ceq 'Version') 'Scanner version wording stays confined to report information'
Assert ((Get-FieldLabel 'Administrator' 'Report info') -ceq 'Access level' -and (Format-RecordFieldValue 'Administrator' $false 'Report info') -ceq 'Standard user' -and (Format-RecordFieldValue 'Administrator' $true 'Report info') -ceq 'Administrator') 'The administrator flag displays as an understandable access level'
Assert ((Format-RecordFieldValue 'Administrator' 'Unknown' 'Report info') -ceq 'Unknown' -and (Format-RecordFieldValue 'Administrator' $false 'Other data') -ceq 'No') 'Unknown values and unrelated boolean fields keep their existing meanings'
foreach($field in @('Generated','SavedAt','ScanCompleted','ExtendedAttempted')){
    Assert ((Format-RecordFieldValue $field $iso 'Report info') -ceq $display) ($field+' displays a readable timestamp while retaining its offset')
}
Assert ((Format-RecordFieldValue 'Captured' $iso 'Extended scan info') -ceq $display -and (Get-FieldLabel 'Captured' 'Extended scan info') -ceq 'Captured at') 'Extended device captures use the same readable time convention'
Assert ((Format-RecordFieldValue 'Generated' 'not recorded' 'Report info') -ceq 'not recorded' -and (Format-RecordFieldValue 'Generated' '123456' 'Report info') -ceq '123456') 'Unrecognized metadata dates are never guessed'
Assert ((Format-RecordFieldValue 'SerialNumber' $iso 'Memory modules') -ceq $iso -and (Format-RecordFieldValue 'Generated' $iso 'Other data') -ceq $iso -and (Format-RecordFieldValue 'SerialNumber' ' 000123 ' 'Memory modules') -ceq ' 000123 ') 'Date-like IDs, leading zeroes and padding stay exact'
Assert ((Format-RecordFieldValue 'ExtendedStatus' 'Refreshed' 'Report info') -ceq 'Device list read' -and (Format-RecordFieldValue 'ExtendedStatus' 'Unavailable' 'Report info') -ceq 'Device list could not be read') 'Device-list metadata explains whether its read succeeded'
Assert ((Format-RecordFieldValue 'ExtendedStatus' 'Unexpected source state' 'Report info') -ceq 'Unexpected source state' -and (Format-RecordFieldValue 'QueryMode' 'Direct queries' 'Report info') -ceq 'Basic progress') 'Unknown states are kept and known progress modes use plain wording'
Assert ((Format-RecordFieldValue 'Display' 'Desktop companion' 'Report info') -ceq 'Desktop dashboard' -and (Format-RecordFieldValue 'Display' 'Classic console' 'Report info') -ceq 'BAT console') 'The interface label identifies the app the capture came from'
$culture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture=[cultureinfo]::GetCultureInfo('fa-IR')
    Assert ((Format-RecordFieldValue 'Generated' $iso 'Report info') -ceq $display) 'Display timestamps keep the captured Gregorian date under another calendar culture'
}finally{[Threading.Thread]::CurrentThread.CurrentCulture=$culture}
Show-FullReport
Assert (@($lines | Where-Object {$_ -match 'Captured at: 2026-11-11 12:34:56 -04:00'}).Count -eq 1 -and @($lines | Where-Object {$_ -match 'Access level: Standard user'}).Count -eq 1) 'The real console full-report entry point applies metadata formatting'
Assert (($report | ConvertTo-Json -Depth 12 -Compress) -ceq $before) 'Rendering metadata leaves every original inventory value unchanged'
$root=Join-Path $PSScriptRoot ('test-output-report-metadata-'+[guid]::NewGuid().ToString('N'))
$env:HWID_SCRIPT=Join-Path $root 'app\hwid.bat';$env:LOCALAPPDATA=Join-Path $root 'local'
Save-Reports
$plain=[IO.File]::ReadAllText([IO.Path]::ChangeExtension($script:lastSavedReportPath,'.txt'))
$saved=Read-SavedReport $script:lastSavedReportPath
Assert ($plain -match 'Captured at: 2026-11-11 12:34:56 -04:00' -and $plain -match 'Scanner version: 3.0' -and $plain -match 'Access level: Standard user') 'Saved TXT reports use the same section-aware labels and values'
Assert ($saved.'Report info'.Generated -ceq $iso -and $saved.'Report info'.Administrator -eq $false -and $saved.CPU[0].ProcessorId -ceq 'SYNTHETIC-ID') 'JSON snapshots retain original metadata types, timestamps and exact identifiers'
[Console]::WriteLine("All $script:checks report-metadata checks passed under PowerShell $($PSVersionTable.PSVersion).")
