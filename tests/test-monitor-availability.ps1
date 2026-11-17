param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
foreach($name in @('$sectionGroups','$identifierPattern')){
    $assignment=$ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq $name},$false)|Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$checks=0
function Assert($condition,$message){if(-not $condition){throw ('FAILED: '+$message)};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Show-ScanGroup {}
function Start-ScanLine {}
function Show-ScanReadResult {}
function Update-ScanProgress {}
function Reset-UiPage {}
function Start-UiReport {}
function Write-Heading {}
function Add-ReportBookmark {}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=$Value;Color=$Color})}
$ownedConsole=$false;$redirected=$true;$scanTotal=18
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($ClassName -ne 'WmiMonitorID' -or $Namespace -ne 'root\wmi' -or $Property){throw 'Unexpected monitor read scope.'}
    switch($env:HWID_TEST_MONITOR_CASE){
        'Absent' {return}
        'Denied' {throw [UnauthorizedAccessException]::new('Synthetic monitor provider denial')}
        'Timeout' {throw [TimeoutException]::new('Synthetic monitor provider wait')}
        'Unsupported' {throw [NotSupportedException]::new('Synthetic monitor provider not supported')}
        'Malformed' {return [pscustomobject]@{}}
    }
    $serial=if($env:HWID_TEST_MONITOR_CASE -eq 'MissingSerial'){@()}else{@(48,48,48,55,937,0)}
    $row=[pscustomobject]@{
        InstanceName='DISPLAY\SYNTHETIC-0001';Active=$false
        ManufacturerName=@(83,89,78,0);UserFriendlyName=@(84,101,115,116,32,937,0);UserFriendlyNameLength=6
        ProductCodeID=@(48,48,49,0);SerialNumberID=$serial
        WeekOfManufacture=0;YearOfManufacture=2026
    }
    $row
    if($env:HWID_TEST_MONITOR_CASE -eq 'PartialError'){Write-Error 'Synthetic failed monitor read after partial output' -Category PermissionDenied -ErrorAction Continue}
}
function Read-MonitorSection {
    $script:report=[ordered]@{'Report info'=@{Version='3.96';Computer='SYNTHETIC';Generated='2026-11-15T00:00:00Z'}}
    $script:warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    $script:scanStep=0
    Section 'Monitors' {Get-MonitorIdentifiers}
}
$output=Join-Path $PSScriptRoot ('test-output-monitor-availability-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($output)
$previous=$env:HWID_TEST_MONITOR_CASE
try{
    foreach($mode in @('Direct','Worker')){
        $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
        try{
            $env:HWID_TEST_MONITOR_CASE='Absent'
            Read-MonitorSection
            $marker=$report.Monitors[0]
            Assert ($scanStep -eq 1 -and $scanTimings.Count -eq 1 -and $scanTimings[0].Status -ceq 'READ' -and $warnings.Count -eq 0) ($mode+' a successful empty query completes one readable scan section without a read warning')
            Assert ($marker.RecordKind -ceq 'Collection status' -and $marker.IdentificationRecords -eq 0 -and $null -eq $marker.PSObject.Properties['Present'] -and $null -eq $marker.PSObject.Properties['SerialNumber']) ($mode+' the zero-identification status never invents a physical-presence flag or serial')
            Assert ($scanTimings[0].Summary -match '^0 monitor identification records' -and $scanTimings[0].Summary -match 'presence not determined') ($mode+' completed scan feedback explains the returned zero without claiming no connected displays')
            $ids=@(Get-IdentifierRows $report);$quick=@(Get-QuickIds $report);$review=Get-ReviewSummary $report $ids @()
            Assert ($ids.Count -eq 0 -and $quick.Count -eq 0 -and $review.IdIssues.Count -eq 0 -and $review.Total -eq 0) ($mode+' the collection-status entry cannot manufacture a missing serial or a review finding')
            $script:rendered=New-Object 'System.Collections.Generic.List[object]'
            Show-GraphicsNetworkSummary
            Assert (@($rendered|Where-Object Label -eq 'Identification read').Count -eq 1 -and @($rendered|Where-Object Label -eq 'Serial (reported)').Count -eq 0) ($mode+' graphics summary renders identification status instead of a phantom monitor')
            $plain=Get-PlainRecords $report.Monitors 'Monitors'|Out-String
            Assert ($plain -match 'Monitor identification records returned' -and $plain -match 'No monitor identification records reported by Windows' -and $plain -notmatch 'Serial number') ($mode+' TXT field labels identify the status entry without a fake serial field')
            $stem=Join-Path $output $mode
            Write-ReportPair $stem $plain ($report|ConvertTo-Json -Depth 12)
            $saved=Read-SavedReport ($stem+'.json')
            Assert ($saved.Monitors[0].IdentificationRecords -eq 0 -and $saved.Monitors[0].RecordKind -ceq 'Collection status' -and @((Get-IdentifierRows $saved)).Count -eq 0) ($mode+' saved JSON preserves the explicit status and zero identifier count')
            Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' saving and reopening the status cannot manufacture identifier changes')
            $absent=Copy-InventorySnapshot $report

            $env:HWID_TEST_MONITOR_CASE='Normal'
            Read-MonitorSection
            $monitor=$report.Monitors[0]
            Assert ($scanTimings[0].Status -ceq 'READ' -and $monitor.SerialNumber -ceq ('0007'+[char]937) -and $monitor.Name -ceq ('Test '+[char]937) -and $monitor.Active -is [bool] -and -not $monitor.Active -and $monitor.WeekOfManufacture -eq 0) ($mode+' real monitor identifiers preserve leading zeroes, Unicode, false flags and zero metadata')
            Assert ($null -eq $monitor.PSObject.Properties['RecordKind'] -and @((Get-QuickIds $report)).Count -eq 1 -and @((Get-IdentifierRows $report)|Where-Object Quality -eq 'Reported').Count -eq 1) ($mode+' real monitor records remain device records with a reported serial')
            $comparison=Compare-Inventories $report $absent
            Assert ($comparison.Changes.Count -eq 0 -and $comparison.CurrentCount -eq 0) ($mode+' missing identification after a real capture does not invent a changed serial or physical removal')
            $env:HWID_TEST_MONITOR_CASE='MissingSerial'
            Read-MonitorSection
            Assert ($scanTimings[0].Status -ceq 'CHECK' -and @((Get-QuickIds $report)|Where-Object Quality -eq 'Missing').Count -eq 1) ($mode+' an actual reported monitor with no serial still has a genuine missing-ID review')
            foreach($case in @('Denied','Timeout','Unsupported','Malformed','PartialError')){
                $env:HWID_TEST_MONITOR_CASE=$case
                Read-MonitorSection
                $expected=switch($case){'Denied'{'READ-01'} 'Timeout'{'READ-02'} 'Unsupported'{'READ-03'} 'Malformed'{'READ-06'} 'PartialError'{'READ-01'}}
                Assert ($scanStep -eq 1 -and $scanTimings.Count -eq 1 -and $scanTimings[0].Status -ceq 'UNAVAILABLE' -and $scanTimings[0].FailureCode -ceq $expected -and $warnings.Count -eq 1 -and (Test-UnavailableRecord $report.Monitors)) ($mode+' '+$case+' remains an explicit failed query instead of a no-identification status')
            }
        }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    }
}finally{$env:HWID_TEST_MONITOR_CASE=$previous}
[Console]::WriteLine(('All {0} monitor availability checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
