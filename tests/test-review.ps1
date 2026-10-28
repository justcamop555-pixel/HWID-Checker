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
$marker=@{Unavailable='Localized failure';FailureCode='READ-02';FailureReason='Provider timed out';NextStep='Retry [9] > [1].'}
$report=[ordered]@{CPU=$marker}
$summary=Get-ReviewSummary $report @() @()
Assert ($summary.UnreadCount -eq 1 -and $summary.Total -eq 1 -and $summary.UnreadDetails[0].Code -eq 'READ-02') 'A stored unread section is detected even without warning text'
$warnings=New-Object 'System.Collections.Generic.List[string]'
@('CPU: First error','cpu: Repeated error',' ','CPU: Third error') | ForEach-Object {$warnings.Add($_)}
$summary=Get-ReviewSummary $report @() $warnings
Assert ($summary.UnreadCount -eq 1 -and $summary.UnreadDetails[0].Reason -eq 'Provider timed out') 'Repeated warning lines count once per unread section and retain stored typed guidance'
Assert ($warnings.Count -eq 4 -and $marker.Unavailable -ceq 'Localized failure') 'Review classification preserves raw warnings and stored diagnostics'
$report.CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU123'})
Assert ((Get-ReviewSummary $report @() $warnings).UnreadCount -eq 0) 'Old warning text cannot keep a successfully refreshed section in Not read'
$report.CPU=@()
Assert ((Get-ReviewSummary $report @() @()).UnreadDetails[0].Code -eq 'READ-04') 'An explicitly empty captured section is no records rather than an all-clear'
Assert ((Get-ReviewSummary ([ordered]@{}) @() @()).UnreadCount -eq 0) 'Absent sections in older schemas do not become invented read failures'
$summary=Get-ReviewSummary ([ordered]@{}) @() @('Unclassified first','Unclassified first','Unclassified second')
Assert ($summary.UnreadCount -eq 2 -and $summary.UnreadDetails[0].Message -eq 'Unclassified first') 'Unlabelled warnings retain their messages while exact repeats are collapsed'
$custom=[ordered]@{'Custom section'=$marker}
Assert ((Get-ReviewSummary $custom @() @('Custom section: Localized failure')).UnreadDetails[0].Code -eq 'READ-02') 'Named custom-query failures retain their stored code through the warning fallback'
$report=[ordered]@{
    'Report info'=@{ExtendedStatus='Unavailable';ExtendedFailureCode='READ-02';ExtendedFailureReason='Provider timed out';ExtendedNextStep='Retry [9] > [4].'}
    'Extended scan info'=@{Captured='old capture'}
    'Extended device inventory'=@([pscustomobject]@{DeviceInstanceId='USB\OLD';ConfigManagerErrorCode=0})
}
$summary=Get-ReviewSummary $report @() @()
Assert ($summary.UnreadCount -eq 1 -and $summary.UnreadDetails[0].Code -eq 'READ-02' -and $summary.UnreadDetails[0].Action -match '\[9\] > \[4\]') 'A failed extended refresh remains reviewable while its prior catalog is readable'
$report.'Report info'=@{}
$report.'Extended scan info'=@{Error='Access denied';FailureCode='READ-01';FailureReason='Access blocked';NextStep='Retry [9] > [1].'}
$report.'Extended device inventory'=@()
Assert ((Get-ReviewSummary $report @() @()).UnreadDetails[0].Code -eq 'READ-01' -and (Get-ReviewSummary $report @() @()).UnreadDetails[0].Action -match '\[9\] > \[4\]') 'Extended failure metadata takes priority over an empty catalog and uses the extended retry action'
$duplicate=@([pscustomobject]@{Name='Repeated';DeviceInstanceId='USB\DUP';ConfigManagerErrorCode=22},[pscustomobject]@{Name='Repeated';DeviceInstanceId=' usb\dup ';ConfigManagerErrorCode=22})
$report=[ordered]@{'PnP hardware IDs'=$duplicate}
$summary=Get-ReviewSummary $report @() @()
Assert ($summary.ConflictCount -eq 1 -and $summary.DeviceCount -eq 0 -and $summary.Total -eq 1 -and $summary.PnpConflicts[0].Statuses.Count -eq 1) 'Repeated disabled-device rows are one conflict rather than duplicate status findings'
$duplicate[0].ConfigManagerErrorCode=0;$duplicate[1].ConfigManagerErrorCode=28
$report.'PnP hardware IDs'=@($duplicate)+@([pscustomobject]@{Name='Repeated';DeviceInstanceId='USB\DUP';ConfigManagerErrorCode=$null})
$summary=Get-ReviewSummary $report @() @()
Assert ($summary.ConflictCount -eq 1 -and $summary.DeviceCount -eq 0 -and $summary.PnpConflicts[0].Statuses.Count -eq 3) 'Conflicting duplicate rows retain working/error/unknown status observations inside the conflict'
Assert ($duplicate[1].DeviceInstanceId -ceq ' usb\dup ' -and $duplicate[0].ConfigManagerErrorCode -eq 0) 'Duplicate matching does not rewrite original IDs or statuses'
$report.'PnP hardware IDs'=@([pscustomobject]@{Name='Resource device';DeviceInstanceId='PCI\RESOURCE';ConfigManagerErrorCode=12})
$summary=Get-ReviewSummary $report @() @()
Assert ($summary.ConflictCount -eq 1 -and $summary.DeviceCount -eq 0 -and $summary.PnpConflicts[0].Kind -eq 'ResourceConflict') 'Windows code 12 belongs in Conflicts and is counted once'
Assert ((Get-DeviceReviewAction $summary.PnpConflicts[0]) -match 'resource conflict.*Device Manager') 'Resource conflict advice points to the reported resource problem'
$report.'PnP hardware IDs'[0].ConfigManagerErrorCode=22
Assert ((Get-ReviewSummary $report @() @()).ConflictCount -eq 0 -and (Get-ReviewSummary $report @() @()).DeviceCount -eq 1) 'Disabled status alone is a device finding rather than a resource conflict'
$report.'PnP hardware IDs'=@([pscustomobject]@{Name='A';DeviceInstanceId='USB\A';ConfigManagerErrorCode=0;HardwareID=@('SHARED')},[pscustomobject]@{Name='B';DeviceInstanceId='USB\B';ConfigManagerErrorCode=0;HardwareID=@('SHARED')})
Assert ((Get-ReviewSummary $report @() @()).Total -eq 0) 'Shared hardware-model IDs are not false conflicts'
$report.'PnP hardware IDs'=@([pscustomobject]@{Name='Unknown';DeviceInstanceId='';ConfigManagerErrorCode=$null})
Assert ((Get-ReviewSummary $report @() @()).DeviceCount -eq 2) 'Missing instance and unread status remain separate findings when a reliable node key is absent'
$report=[ordered]@{CPU=$marker};$identifiers=@([pscustomobject]@{Quality='Not applicable'})
$script:rendered.Clear();Show-CompactDeck 79
$expected=(Get-ReviewSummary $report $identifiers $warnings).Total
Assert (($script:rendered -join ' ') -match ('Review: '+$expected)) 'Compact dashboard totals use the same deduplicated model as review'
$report=[ordered]@{};$identifiers=@();$warnings=New-Object 'System.Collections.Generic.List[string]'
$script:rendered.Clear();Show-Attention
$view=$script:rendered -join ' '
Assert ($view -match 'No conflicts detected' -and $view -match 'No device-status findings' -and $view -match 'No unread sections reported' -and $view -match 'No missing/default identifier findings') 'Empty review groups explain their results instead of landing on a different group'
$report=[ordered]@{'PnP hardware IDs'=@([pscustomobject]@{Name='Same name';DeviceInstanceId='PCI\A';ConfigManagerErrorCode=28},[pscustomobject]@{Name='Same name';DeviceInstanceId='PCI\B';ConfigManagerErrorCode=22})}
$script:rendered.Clear();Show-Attention
Assert (($script:rendered -join ' ') -match 'Instance: PCI\\A' -and ($script:rendered -join ' ') -match 'Instance: PCI\\B') 'Device findings include instance context when friendly names are identical'
$report=[ordered]@{'PnP hardware IDs'=@([pscustomobject]@{Name='Resource device';DeviceInstanceId='PCI\RESOURCE';ConfigManagerErrorCode=12})}
$script:rendered.Clear();Show-Attention
Assert (($script:rendered -join ' ') -match 'Resource device / Resource conflict' -and ($script:rendered -join ' ') -match 'Instance: PCI\\RESOURCE') 'The conflict view identifies the resource-conflicted device and instance'
$report=[ordered]@{'PnP hardware IDs'=$duplicate}
$script:rendered.Clear();Show-Attention
Assert (($script:rendered -join ' ') -match 'Status readings: Working.*Driver not installed') 'The duplicate conflict view retains its observed status differences'
$report=[ordered]@{CPU=@{Unavailable='Invalid namespace'}}
$script:rendered.Clear();Show-Attention
Assert (($script:rendered -join ' ') -match 'Main \[5\]') 'Review guidance distinguishes the main full-report action from the page conflict shortcut'
[Console]::WriteLine("All $script:checks review checks passed under PowerShell $($PSVersionTable.PSVersion).")
