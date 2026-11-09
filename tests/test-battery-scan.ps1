param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
foreach($name in @('$sectionGroups','$identifierPattern')){
    $assignment=$ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $name},$false) | Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$ownedConsole=$false;$redirected=$true
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
function Get-CimInstance {
    param($ClassName,$Namespace,$OperationTimeoutSec,$Property)
    if($ClassName -ne 'Win32_Battery'){throw 'Unexpected class in the synthetic battery reader.'}
    $supported=@('DeviceID','PNPDeviceID','Name','EstimatedChargeRemaining','BatteryStatus','DesignVoltage','Chemistry')
    foreach($field in $Property){if($field -notin $supported){throw ('Invalid property in the real Win32_Battery schema: '+$field)}}
    if($env:HWID_TEST_BATTERY_CASE -eq 'Absent'){return}
    if($env:HWID_TEST_BATTERY_CASE -eq 'Denied'){throw [UnauthorizedAccessException]::new('Synthetic battery access denied')}
    $first=if($env:HWID_TEST_BATTERY_CASE -eq 'Changed'){'ACPI\SYNTHETIC-REPLACEMENT'}else{'ACPI\SYNTHETIC-A'}
    @(
        [pscustomobject]@{DeviceID='BAT0';PNPDeviceID=$first;Name='Synthetic internal battery';EstimatedChargeRemaining=50;BatteryStatus=10;DesignVoltage=12000;Chemistry=6},
        [pscustomobject]@{DeviceID='BAT1';PNPDeviceID='ACPI\SYNTHETIC-B';Name='Synthetic second battery';EstimatedChargeRemaining=100;BatteryStatus=3;DesignVoltage=12000;Chemistry=6}
    ) | Select-Object -Property $Property
}
$root=Join-Path $PSScriptRoot ('test-output-battery-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$previousCase=$env:HWID_TEST_BATTERY_CASE
try {
    foreach($mode in @('Direct','Worker')){
        $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
        try {
            $env:HWID_TEST_BATTERY_CASE='Normal'
            $rows=@(Invoke-ScanQuery {Get-BatteryIdentifiers})
            Assert ($rows.Count -eq 2 -and $rows[0].DeviceID -ceq 'BAT0' -and $rows[1].DeviceID -ceq 'BAT1') ($mode+' supported battery queries retain distinct device identities')
            Assert ($null -eq $rows[0].PSObject.Properties['SerialNumber'] -and $null -eq $rows[0].PSObject.Properties['Manufacturer'] -and -not $script:lastQueryRecoveries.Count) ($mode+' the normal query needs no nonexistent properties or compatibility retry')
            $info=Get-SectionIdentifierInfo 'Battery' $rows
            Assert ($info.Tag -ceq 'READ' -and $info.Found -eq 2 -and $info.Missing -eq 0) ($mode+' actual battery PnP IDs avoid fabricated missing-serial warnings')
            Assert ($rows[0].BatteryStatusName -ceq 'Undefined' -and $rows[0].RawBatteryStatus[0] -eq 10 -and $rows[1].BatteryStatusName -ceq 'Fully charged') ($mode+' battery status labels preserve Windows code semantics and raw values')
            $before=[ordered]@{'Report info'=@{Version='3.0';Computer='SYNTHETIC';Generated='2026-11-08T10:00:00Z'};Battery=$rows}
            $env:HWID_TEST_BATTERY_CASE='Changed'
            $after=[ordered]@{'Report info'=@{Version='3.0';Computer='SYNTHETIC';Generated='2026-11-08T11:00:00Z'};Battery=@(Invoke-ScanQuery {Get-BatteryIdentifiers})}
            $comparison=Compare-Inventories $before $after
            $changes=@(Get-ComparisonDetails $comparison)
            Assert ($comparison.PreviousCount -eq 2 -and $comparison.CurrentCount -eq 2 -and $comparison.UnkeyedSections -notcontains 'Battery' -and $changes.Count -eq 1 -and $changes[0].Kind -eq 'Changed' -and $changes[0].Device -eq 'DeviceID=BAT0') ($mode+' two batteries compare by stable key and identify the changed ID precisely')
            $stem=Join-Path $root $mode
            Write-ReportPair $stem (Get-PlainRecords $after.Battery 'Battery' | Out-String) ($after | ConvertTo-Json -Depth 8)
            $imported=Read-SavedReport ($stem+'.json')
            Assert ($imported.Battery[0].DeviceID -ceq 'BAT0' -and $imported.Battery[0].PNPDeviceID -ceq 'ACPI\SYNTHETIC-REPLACEMENT' -and $imported.Battery[0].RawBatteryStatus[0] -eq 10) ($mode+' snapshots retain battery identity and raw readings')
            $env:HWID_TEST_BATTERY_CASE='Absent'
            $absent=@(Invoke-ScanQuery {Get-BatteryIdentifiers})
            $info=Get-SectionIdentifierInfo 'Battery' $absent
            Assert ($absent.Count -eq 1 -and $absent[0].Present -ceq 'No' -and $info.Tag -ceq 'READ' -and $info.Missing -eq 0) ($mode+' a desktop PC without a battery stays a normal readable result')
            $env:HWID_TEST_BATTERY_CASE='Denied'
            $failure=$null
            try{Invoke-ScanQuery {Get-BatteryIdentifiers} | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -ceq 'READ-01') ($mode+' access failure cannot be presented as no battery')
        }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    }
}finally{$env:HWID_TEST_BATTERY_CASE=$previousCase}
Assert ((Get-FieldLabel 'Present' 'Battery') -ceq 'Battery present' -and (Get-FieldLabel 'Present' 'PnP hardware IDs') -ceq 'Present' -and (Get-FieldLabel 'Present' 'Network adapters') -ceq 'Present') 'Battery wording stays confined to battery fields'
$plain=Get-PlainRecords @([pscustomobject]@{Present=$true}) 'PnP hardware IDs' | Out-String
Assert ($plain -match 'Present' -and $plain -notmatch 'Battery present') 'PnP text exports retain a device presence label'
$sectionGroups=[ordered]@{'Synthetic category'=@('Unreadable','Readable')}
$report=[ordered]@{Unreadable=@{Unavailable='Synthetic provider failure'};Readable=@([pscustomobject]@{Name='A'},[pscustomobject]@{Name='B'})}
$script:categoryHint=$null
function Show-MenuItem {param($Key,$Label,$Hint) if($Key -eq 1){$script:categoryHint=$Hint}}
function Read-MenuChoice {param($Maximum) return '0'}
[void](Show-Categories)
Assert ($script:categoryHint -ceq '2 record(s) captured') 'Category counts include real records and exclude unavailable placeholders'
[Console]::WriteLine("All $script:checks battery and label checks passed under PowerShell $($PSVersionTable.PSVersion).")
