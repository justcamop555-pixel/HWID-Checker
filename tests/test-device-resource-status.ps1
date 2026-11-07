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
function New-StatusDevice($Code,$Id='PCI\STATUS-0001'){[pscustomobject]@{Name='Synthetic resource device';DeviceInstanceId=$Id;PNPClass='System';Present=$true;HiddenByNodeFlag=$false;HiddenByClass=$false;ConfigManagerErrorCode=$Code;HardwareID=@('MODEL-0001')}}
$device=New-StatusDevice 12
$inventory=[ordered]@{'PnP hardware IDs'=@($device)}
$summary=Get-ReviewSummary $inventory @() @()
Assert ($summary.ConflictCount -eq 0 -and $summary.DeviceCount -eq 1 -and $summary.Total -eq 1) 'Windows code 12 remains a device finding without asserting a confirmed resource conflict'
$issue=$summary.DeviceIssues[0];$status=Get-PnpStatus 12
Assert ($issue.Kind -eq 'Status' -and $issue.Code -eq 12 -and $status.Quality -eq 'Review' -and $status.Text -match 'Insufficient resources') 'Resource shortage retains its exact code and review status'
Assert ((Get-DeviceReviewAction $issue) -match 'resource allocation.*Device Manager.*shortage or a conflict') 'Code 12 guidance explains both resource shortage and possible conflict'
$overview=Get-OverviewSummary $inventory @() @()
Assert ($overview.Conflicts -eq 0 -and $overview.DeviceIssues -eq 1 -and $overview.ReviewTotal -eq 1) 'The dashboard and summary use the same non-inflated conflict count'
Assert ((Get-SectionIdentifierInfo 'PnP hardware IDs' @($device)).Tag -eq 'CHECK') 'Reducing a false conflict cannot turn the real resource finding into an all-clear'
$report=$inventory;$identifiers=@();$warnings=New-Object 'System.Collections.Generic.List[string]'
$rendered.Clear();Show-Attention
Assert (@($rendered | Where-Object {$_.Label -eq 'DEVICE REVIEW' -and $_.Value -match 'Insufficient resources'}).Count -eq 1 -and @($rendered | Where-Object Label -eq 'DEVICE CONFLICT').Count -eq 0) 'Review displays code 12 under device findings rather than confirmed conflicts'
foreach($case in @(@(6,'Boot configuration conflict'),@(30,'IRQ resource conflict'))){
    $device=New-StatusDevice $case[0];$issues=@(Get-PnpIssues @($device));$summary=Get-ReviewSummary ([ordered]@{'PnP hardware IDs'=@($device)}) @() @()
    Assert ($issues.Count -eq 1 -and $issues[0].Kind -eq 'ResourceConflict' -and $issues[0].Code -eq $case[0] -and $issues[0].Message -match $case[1]) 'Documented boot/IRQ conflicts are identified from their actual Windows codes'
    Assert ($summary.ConflictCount -eq 1 -and $summary.DeviceCount -eq 0 -and $summary.Total -eq 1) 'A genuine Windows conflict is counted once in the conflict group'
    Assert ((Get-DeviceReviewAction $issues[0]) -match 'resource conflict.*Device Manager') 'Specific conflict guidance points to the Windows-reported assignment'
}
foreach($code in @(0,10,12,22,24,28,43,45)){
    $device=New-StatusDevice $code;$issues=@(Get-PnpIssues @($device))
    Assert (@($issues | Where-Object Kind -eq 'ResourceConflict').Count -eq 0) 'Other Windows status codes cannot masquerade as specific boot/IRQ conflicts'
}
$status=Get-PnpStatus 24
Assert ($status.Text -match 'Not present, malfunctioning, or drivers incomplete' -and $status.Quality -eq 'Review') 'Code 24 preserves every documented alternative rather than assuming disconnection or missing drivers'
$device=New-StatusDevice 24
Assert ((Test-ExtendedDeviceGroup $device 5) -and -not (Test-ExtendedDeviceGroup $device 2)) 'An ambiguous status code cannot override an explicitly present node'
Assert ((Get-DeviceReviewAction (@(Get-PnpIssues @($device))[0])) -match 'presence, operation and drivers') 'Code 24 advice checks all alternatives without choosing an unsupported cause'
$mixed=@((New-StatusDevice 6 'PCI\BOOT'),(New-StatusDevice 12 'PCI\SHORTAGE'),(New-StatusDevice 30 'PCI\IRQ'),(New-StatusDevice 24 'PCI\AMBIGUOUS'),(New-StatusDevice 0 'PCI\WORKING'))
$summary=Get-ReviewSummary ([ordered]@{'PnP hardware IDs'=$mixed}) @() @()
Assert ($summary.ConflictCount -eq 2 -and $summary.DeviceCount -eq 2 -and $summary.Total -eq 4) 'Mixed scan totals retain real conflicts and other findings without duplicate counts'
$duplicate=@((New-StatusDevice 6 'PCI\DUP'),(New-StatusDevice 12 'PCI\DUP'),(New-StatusDevice 30 'PCI\DUP'))
$summary=Get-ReviewSummary ([ordered]@{'PnP hardware IDs'=$duplicate}) @() @()
Assert ($summary.ConflictCount -eq 1 -and $summary.DeviceCount -eq 0 -and $summary.PnpConflicts[0].Kind -eq 'Duplicate' -and $summary.PnpConflicts[0].Statuses.Count -eq 3) 'Duplicate nodes remain one ambiguity while retaining each status observation'
function Get-CimInstance {
    param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
    foreach($code in @(6,12,30,24,0)){[pscustomobject]@{Name='Synthetic resource device';PNPDeviceID=('PCI\STATUS-'+$code);PNPClass='System';ClassGuid='SYNTHETIC';Present=$true;ConfigManagerErrorCode=$code;HardwareID=@('MODEL-0001')}}
}
$root=Join-Path $PSScriptRoot ('test-output-resource-status-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        Section 'PnP hardware IDs' {Get-DriverHardwareIds}
        $rows=$report['PnP hardware IDs'];$summary=Get-ReviewSummary $report @() @()
        Assert ($rows.Count -eq 5 -and $warnings.Count -eq 0 -and $scanTimings[0].Status -eq 'CHECK' -and $scanTimings[0].Results -eq 5) ($mode+' readable resource findings do not turn the complete scan into an unread section')
        Assert ($summary.ConflictCount -eq 2 -and $summary.DeviceCount -eq 2 -and $summary.Total -eq 4) ($mode+' actual scanner output uses corrected status categories and totals')
        Assert (($rows.ConfigManagerErrorCode -join ',') -eq '0,12,24,30,6' -and $rows[1].DeviceInstanceId -ceq 'PCI\STATUS-12') ($mode+' raw status codes and device IDs remain exact')
        Assert ((Get-SectionIdentifierInfo 'PnP hardware IDs' $rows).Text -match '4 review') ($mode+' progress retains every genuine review finding after reclassification')
        $rendered.Clear();Show-PnpRecords $rows
        Assert (@($rendered | Where-Object {$_.Value -match '^Insufficient resources \(code 12\)$' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' device browsing retains a visible resource-shortage warning')
        $report['Report info']=@{Version='3.79';Computer='TEST';Generated='2026-11-01T12:00:00-05:00'}
        $stem=Join-Path $root $mode;Write-ReportPair $stem ((Get-PlainRecords $rows) -join [Environment]::NewLine) ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json');$savedSummary=Get-ReviewSummary $saved @() @()
        Assert ($savedSummary.ConflictCount -eq 2 -and $savedSummary.DeviceCount -eq 2 -and $saved.'PnP hardware IDs'[1].ConfigManagerErrorCode -eq 12) ($mode+' imported snapshots use corrected categories without rewriting their stored codes')
        Assert ([IO.File]::ReadAllText($stem+'.txt') -match 'Windows device status code: 12') ($mode+' text exports preserve the original Windows status number')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0 -and $rows[1].ConfigManagerErrorCode -eq 12) ($mode+' status interpretation cannot alter identifiers or original scan data')
        $extended=New-StatusDevice 12
        Assert ((@(Get-ExtendedDeviceReview $extended) -join ' ') -match 'Insufficient resources' -and (Get-ExtendedProblemCode $extended) -eq 12) ($mode+' extended-device review uses the same resource wording and raw problem code')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks device-resource-status checks passed under PowerShell $($PSVersionTable.PSVersion).")
