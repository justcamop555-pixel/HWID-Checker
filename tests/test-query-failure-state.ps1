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
$script:checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    if($Property){throw [Runtime.InteropServices.COMException]::new('Synthetic unsupported projection',[Convert]::ToInt32('80041017',16))}
    [pscustomobject]@{DeviceID='CPU0';Name='Synthetic component';ProcessorId='CPU-000123';SerialNumber='000123';QueryClass=$ClassName}
}
$root=Join-Path $PSScriptRoot ('test-output-query-failure-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        $failure=$null;$partial=@()
        try{$partial=@(Invoke-ScanQuery {Get-HwidInstance First -Property ProcessorId;throw [TimeoutException]::new('Synthetic final timeout')})}catch{$failure=Get-ScanFailureInfo $_}
        Assert ($script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryRecoveries[0].Class -eq 'First' -and $script:lastQueryRecoveries[0].PrimaryFailure -match 'Synthetic unsupported projection') ($mode+' a final query failure retains earlier compatible-read diagnostics')
        Assert ($failure.Code -eq 'READ-02' -and $failure.Details -eq 'Synthetic final timeout' -and $partial.Count -eq 0) ($mode+' the final typed failure wins without returning partial records')
        foreach($case in @('Denied','Unavailable','Invalid','NonTerminating','MixedErrors')){
            $tail=switch($case){
                'Denied' {'throw [UnauthorizedAccessException]::new("Synthetic final denial")'}
                'Unavailable' {'throw [NotSupportedException]::new("Synthetic final provider unavailable")'}
                'Invalid' {'throw [IO.InvalidDataException]::new("Synthetic invalid final data")'}
                'NonTerminating' {'Write-Error -Exception ([UnauthorizedAccessException]::new("Synthetic nonterminating denial")) -ErrorAction Continue;[pscustomobject]@{ProcessorId="PARTIAL-MUST-NOT-LEAK"}'}
                'MixedErrors' {'Write-Error -Exception ([UnauthorizedAccessException]::new("Synthetic earlier denial")) -ErrorAction Continue;throw [TimeoutException]::new("Synthetic terminal timeout")'}
            }
            $query=[scriptblock]::Create(('Get-HwidInstance First -Property ProcessorId;Get-HwidInstance Second -Property ProcessorId;'+$tail))
            $failure=$null;$partial=@()
            try{$partial=@(Invoke-ScanQuery $query)}catch{$failure=Get-ScanFailureInfo $_}
            $expected=switch($case){'Denied' {'READ-01'};'Unavailable' {'READ-03'};'Invalid' {'READ-06'};'NonTerminating' {'READ-01'};'MixedErrors' {'READ-02'}}
            Assert ($failure.Code -eq $expected -and $partial.Count -eq 0) ($mode+' '+$case+' retains the final error category and discards partial records')
            Assert ($script:lastQueryRecoveries.Count -eq 2 -and $script:lastQueryRecoveries[0].Class -eq 'First' -and $script:lastQueryRecoveries[1].Class -eq 'Second') ($mode+' '+$case+' retains every completed recovery in order')
        }
        Section CPU {Get-HwidInstance SectionFixture -Property ProcessorId;throw [TimeoutException]::new('Synthetic section timeout')}
        Assert ($scanTimings[0].Status -eq 'UNAVAILABLE' -and $scanTimings[0].Results -eq 0 -and $scanTimings[0].FailureCode -eq 'READ-02' -and $warnings.Count -eq 1) ($mode+' an incomplete section remains NOT READ with zero accepted results')
        Assert ($scanTimings[0].Recoveries.Count -eq 1 -and $scanTimings[0].Recoveries[0].Class -eq 'SectionFixture' -and $scanTimings[0].Summary -notmatch 'compatible read') ($mode+' timing preserves earlier recovery without declaring the failed section recovered')
        $report['Report info']=@{Version='3.76';Computer='TEST';Generated='2026-10-31T12:00:00Z'}
        $report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem ((Get-PlainRecords $report['Scan timing']) -join [Environment]::NewLine) ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Scan timing'[0].Recoveries[0].Class -eq 'SectionFixture' -and $saved.CPU.FailureCode -eq 'READ-02') ($mode+' saved snapshots preserve both recovery history and final failure')
        Assert ([IO.File]::ReadAllText($stem+'.txt') -match 'Synthetic unsupported projection') ($mode+' text reports retain earlier reader diagnostics')
        $old=@{CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-OLD'})};$comparison=Compare-Inventories $old $saved
        Assert ($comparison.Changes.Count -eq 0 -and $comparison.SkippedSections -contains 'CPU') ($mode+' recovery history cannot make failed hardware comparable or invent an ID removal')
        $healthy=@(Invoke-ScanQuery {[pscustomobject]@{Name='Healthy';ProcessorId='CPU-000123'}})
        Assert ($healthy.Count -eq 1 -and $healthy[0].ProcessorId -ceq 'CPU-000123' -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' the next successful query reuses the worker without stale errors or recoveries')
        $empty=@(Invoke-ScanQuery {})
        Assert ($empty.Count -eq 0 -and $script:lastQueryRecoveries.Count -eq 0) ($mode+' an empty query does not reuse old results or diagnostics')
        $commented=@(Invoke-ScanQuery ([scriptblock]::Create('[pscustomobject]@{Name="Synthetic trailing comment"} # trailing comment')))
        Assert ($commented.Count -eq 1 -and $commented[0].Name -eq 'Synthetic trailing comment') ($mode+' a trailing query comment cannot consume the worker wrapper')
        $scalars=@(Invoke-ScanQuery {0;$false;'000123'})
        Assert ($scalars.Count -eq 3 -and $scalars[0] -eq 0 -and $scalars[1] -is [bool] -and -not $scalars[1] -and $scalars[2] -ceq '000123') ($mode+' query transport preserves zero, false and exact string values')
        $providerFailure=$null
        try{Invoke-ScanQuery {throw [Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Synthetic provider blocked'),'Synthetic.ProviderBlocked',[Management.Automation.ErrorCategory]::PermissionDenied,'Synthetic target')} | Out-Null}catch{$providerFailure=$_}
        Assert ($providerFailure.FullyQualifiedErrorId -match 'Synthetic.ProviderBlocked' -and $providerFailure.CategoryInfo.Category -eq 'PermissionDenied' -and $providerFailure.TargetObject -eq 'Synthetic target') ($mode+' the original provider error identity, category and target survive query transport')
        Section CPU {Get-HwidInstance Healthy -Property ProcessorId | Select-Object DeviceID,Name,ProcessorId}
        Assert ($scanTimings[-1].Status -eq 'READ' -and $scanTimings[-1].Recoveries.Count -eq 1 -and $report.CPU[0].ProcessorId -ceq 'CPU-000123') ($mode+' a later genuine recovery remains readable and accurately counted')
        Assert (@($scanTimings | Where-Object {$_.Status -ne 'UNAVAILABLE' -and $_.Recoveries.Count -gt 0}).Count -eq 1) ($mode+' compatible-read totals exclude earlier failed sections')
        if($mode -eq 'Worker'){
            $failure=$null
            try{Invoke-ScanQuery {Get-HwidInstance Slow -Property ProcessorId;Start-Sleep -Milliseconds 350;throw [TimeoutException]::new('Synthetic slow timeout')} {throw 'Synthetic pulse failure'} | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq 'READ-02' -and $script:lastQueryRecoveries.Count -eq 1 -and $script:lastQueryFeedbackFailure -eq 'Synthetic pulse failure') 'Worker display-feedback failure stays separate from query failure and recovery history'
            $failure=$null
            try{Invoke-ScanQuery {exit} | Out-Null}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($failure.Code -eq 'READ-06' -and $script:lastQueryRecoveries.Count -eq 0) 'Worker incomplete attempt output is invalid data rather than an empty successful query'
            $healthy=@(Invoke-ScanQuery {[pscustomobject]@{Name='After incomplete attempt'}})
            Assert ($healthy.Count -eq 1 -and $healthy[0].Name -eq 'After incomplete attempt') 'Worker a later query can run after an incomplete attempt'
        }
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks query-failure-state checks passed under PowerShell $($PSVersionTable.PSVersion).")
