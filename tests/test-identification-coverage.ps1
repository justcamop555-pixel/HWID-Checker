param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
foreach($name in @('$sectionGroups','$identifierPattern','$script:scanTotal')){
    $assignment=$ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq $name},$false)|Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$checks=0
function Assert($value,$description){if(-not $value){throw ('FAILED: '+$description)};$script:checks++;[Console]::WriteLine('PASS: '+$description)}
$ownedConsole=$false;$redirected=$true;$display=[pscustomobject]@{Mode='Synthetic identification coverage'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Good='Green';Warn='Yellow';Error='Red';Border='DarkGray'}
$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Write-Host {param($Object,$ForegroundColor,$BackgroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
function Reset-UiPage {}
function Present-Fixture([string]$Case){
    $query=[scriptblock]::Create(@'
function Get-Command {param($Name,$ErrorAction) if($Name -eq 'Get-PnpDeviceProperty' -and 'FIXTURE_CASE' -eq 'NoReader'){return};Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue}
function Get-CimInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    [pscustomobject]@{Name=$(if('FIXTURE_CASE' -like 'Recovered*'){$null}else{'Synthetic device'});PNPDeviceID='USB\SYNTHETIC-000123';PNPClass='USB';Present=$true;HardwareID=@();CompatibleID=@();ConfigManagerErrorCode=$(if('FIXTURE_CASE' -eq 'RecoveredAccess'){28}else{0})}
}
function Get-PnpDeviceProperty {
    [CmdletBinding()]param($InstanceId,$KeyName,$ThrottleLimit)
    if('FIXTURE_CASE' -eq 'NoAdditional'){return}
    if('FIXTURE_CASE' -like 'Recovered*' -or 'FIXTURE_CASE' -eq 'Healthy'){
        [pscustomobject]@{InstanceId='USB\SYNTHETIC-000123';KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-000123')}
        [pscustomobject]@{InstanceId='USB\SYNTHETIC-000123';KeyName='DEVPKEY_Device_FriendlyName';Data='Recovered Ω name'}
    }
    if('FIXTURE_CASE' -in @('Denied','RecoveredAccess')){
        $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Synthetic localized identification denial'),'Synthetic.OptionalDenied',[Management.Automation.ErrorCategory]::PermissionDenied,$InstanceId))
    }elseif('FIXTURE_CASE' -ne 'Healthy'){
        Write-Error 'Synthetic optional property could not be supplied' -ErrorAction Continue
    }
}
Get-DriverHardwareIds
'@.Replace('FIXTURE_CASE',$Case))
    return @(Invoke-ScanQuery $query)
}
function Extended-Fixture([string]$Case){
    $query=[scriptblock]::Create(@'
function Get-Command {param($Name,$ErrorAction) Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    foreach($id in @('USB\A-000123','USB\B-000124')){[pscustomobject]@{InstanceId=$id;Name='Synthetic device';Class='USB';ClassGuid='SYNTHETIC';Present=($id -like '*A-*');HardwareID=@('MODEL-000123');CompatibleID=@();ConfigManagerErrorCode=0}}
}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw 'Unexpected hardware fallback in synthetic coverage fixture'}
function Get-ClassHiddenState {param($ClassGuid) $false}
function Get-NativeNodeStatus {param($InstanceId) [uint32]0}
function Get-PnpDeviceProperty {
    [CmdletBinding()]param($InstanceId,$KeyName,$ThrottleLimit)
    foreach($id in $InstanceId){
        if('FIXTURE_CASE' -eq 'MissingRows' -and $id -like '*B-*'){continue}
        [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@($(if('FIXTURE_CASE' -eq 'SourceConflict'){'OTHER-000123'}else{'MODEL-000123'}))}
        [pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_DevNodeStatus';Data=[uint32]0}
        if('FIXTURE_CASE' -eq 'PropertyConflict'){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('OTHER-000124')}}
    }
    if('FIXTURE_CASE' -eq 'InvalidRows'){[pscustomobject]@{InstanceId=@('USB\A-000123');KeyName='DEVPKEY_Device_HardwareIds';Data=@('DO-NOT-ATTACH')}}
    if('FIXTURE_CASE' -eq 'Blocked'){
        $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Synthetic localized property denial'),'Synthetic.PropertyDenied',[Management.Automation.ErrorCategory]::PermissionDenied,$InstanceId))
    }elseif('FIXTURE_CASE' -eq 'GenericOptional'){Write-Error 'Synthetic optional property not supplied' -ErrorAction Continue}
}
Get-ExtendedDeviceInventory
'@.Replace('FIXTURE_CASE',$Case))
    return @(Invoke-ScanQuery $query)[0]
}
$root=Join-Path $PSScriptRoot ('test-output-identification-coverage-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $denied=@(Present-Fixture 'Denied');$present=Get-PresentIdentificationCoverage $denied
        Assert ($present.NeedsReview -and $present.AffectedNodes -eq 1 -and $present.BlockingFailures -eq 1 -and $denied[0].IdentificationReadFailureCodes -contains 'READ-01') ($mode+' a typed blocked identification lookup remains reviewable beside accepted device records')
        $info=Get-SectionIdentifierInfo 'PnP hardware IDs' $denied
        Assert ($info.Tag -eq 'CHECK' -and $info.Found -eq 1 -and $info.Missing -eq 0 -and $info.Text -match 'identification checks incomplete') ($mode+' identification coverage qualifies READ as CHECK without marking the instance record unread')
        $inventory=[ordered]@{'PnP hardware IDs'=$denied}
        $review=Get-ReviewSummary $inventory @() @()
        Assert ($review.CoverageCount -eq 1 -and $review.UnreadCount -eq 0 -and $review.DeviceCount -eq 0 -and $review.Total -eq 1) ($mode+' failed identification is a separate coverage finding rather than an invented hardware fault')
        $empty=@(Present-Fixture 'NoAdditional')
        Assert (-not (Get-PresentIdentificationCoverage $empty).NeedsReview -and (Get-SectionIdentifierInfo 'PnP hardware IDs' $empty).Tag -eq 'READ') ($mode+' absent optional IDs without failed lookup diagnostics are not false warnings')
        $generic=@(Present-Fixture 'GenericUnresolved')
        Assert ((Get-PresentIdentificationCoverage $generic).NeedsReview -and $generic[0].IdentificationReadFailureCodes -contains 'READ-05') ($mode+' unresolved essential identification and a generic failed lookup remain explicit')
        $noReader=@(Present-Fixture 'NoReader')
        Assert ((Get-PresentIdentificationCoverage $noReader).NeedsReview -and $noReader[0].IdentificationReadFailureCodes -contains 'READ-03') ($mode+' an unavailable optional reader retains its provider code')
        $recovered=@(Present-Fixture 'RecoveredGeneric')
        Assert (-not (Get-PresentIdentificationCoverage $recovered).NeedsReview -and $recovered[0].IdentificationReadStatus -match 'Recovered.*lookup incomplete') ($mode+' recovered essential values with a generic optional error retain partial diagnostics without a false coverage warning')
        Assert ($recovered[0].HardwareID[0] -ceq 'MODEL-000123' -and $recovered[0].Name -ceq 'Recovered Ω name') ($mode+' coverage evaluation does not rewrite exact recovered IDs or Unicode names')
        $blockedRecovery=@(Present-Fixture 'RecoveredAccess')
        $blockedReview=Get-ReviewSummary ([ordered]@{'PnP hardware IDs'=$blockedRecovery}) @() @()
        Assert ((Get-PresentIdentificationCoverage $blockedRecovery).NeedsReview -and $blockedReview.CoverageCount -eq 1 -and $blockedReview.DeviceCount -eq 1 -and $blockedReview.Total -eq 2) ($mode+' partial recovery retains a real driver finding separately from a blocked identification check')
        $healthy=@(Present-Fixture 'Healthy')
        Assert (-not (Get-PresentIdentificationCoverage $healthy).NeedsReview -and @($healthy[0].IdentificationReadFailureCodes | Where-Object {$_}).Count -eq 0) ($mode+' a healthy later present-device read cannot inherit earlier failure codes')

        $optional=Extended-Fixture 'GenericOptional';$extra=Get-ExtendedIdentificationCoverage $optional.Info $optional.Devices
        Assert (-not $extra.NeedsReview -and $optional.Info.PropertyReadErrors -gt 0 -and $optional.Info.PropertyBlockingErrors -eq 0 -and $extra.NodesWithoutRows -eq 0) ($mode+' generic optional property errors with complete node coverage do not manufacture failed identification')
        $missing=Extended-Fixture 'MissingRows'
        Assert ((Get-ExtendedIdentificationCoverage $missing.Info $missing.Devices).NeedsReview -and $missing.Info.PropertyNodesWithoutRows -eq 1 -and $missing.Devices.Count -eq 2) ($mode+' absent requested-node property rows remain reviewable while both base records survive')
        $blocked=Extended-Fixture 'Blocked'
        Assert ((Get-ExtendedIdentificationCoverage $blocked.Info $blocked.Devices).NeedsReview -and $blocked.Info.PropertyBlockingErrors -gt 0 -and $blocked.Info.PropertyNodesWithoutRows -eq 0) ($mode+' typed blocking property errors cannot be hidden by other successful rows')
        foreach($case in @('InvalidRows','SourceConflict','PropertyConflict')){
            $catalog=Extended-Fixture $case
            Assert ((Get-ExtendedIdentificationCoverage $catalog.Info $catalog.Devices).NeedsReview -and $catalog.Devices.Count -eq 2) ($mode+' '+$case+' becomes coverage review without dropping base devices')
        }
        $missingIdRows=@([pscustomobject]@{Name='Readable node';DeviceInstanceId='';HardwareID=@();ConfigManagerErrorCode=0})
        Assert ((Get-ExtendedIdentificationCoverage @{} $missingIdRows).MissingInstanceIds -eq 1 -and (Get-ExtendedIdentificationCoverage @{} $missingIdRows).NeedsReview) ($mode+' a readable base node without an instance key cannot claim complete identity coverage')
        # Legacy captures preserve the provider's key name. Presence evaluation
        # must match Desktop without coercing malformed aliases or rewriting IDs.
        foreach($alias in @('DeviceInstanceId','PNPDeviceID','InstanceId','DeviceID')){
            $rawAlias='  USB\LEGACY-000123'+[char]0+'  '
            $aliasFields=[ordered]@{Name='Legacy capture';HardwareID=@('MODEL-000123');ConfigManagerErrorCode=0}
            $aliasFields[$alias]=$rawAlias;$aliasRow=[pscustomobject]$aliasFields
            $legacyCoverage=Get-ExtendedIdentificationCoverage ([pscustomobject]@{PropertyNodesRequested=1;PropertyNodesReturned=1;PropertyNodesWithoutRows=0}) @($aliasRow)
            Assert (-not $legacyCoverage.NeedsReview -and $legacyCoverage.MissingInstanceIds -eq 0 -and $aliasRow.$alias -ceq $rawAlias -and @($aliasRow.PSObject.Properties).Count -eq $aliasFields.Count) ($mode+' legacy '+$alias+' identifies a covered node without changing its raw field or value')
            foreach($badAlias in @([pscustomobject]@{Kind='numeric';Value=123},[pscustomobject]@{Kind='array';Value=@('USB\LEGACY-000123')})){
                $badFields=[ordered]@{Name='Malformed legacy alias';HardwareID=@('MODEL-000123');ConfigManagerErrorCode=0}
                $badFields[$alias]=$badAlias.Value
                $badCoverage=Get-ExtendedIdentificationCoverage @{} @([pscustomobject]$badFields)
                Assert ($badCoverage.NeedsReview -and $badCoverage.MissingInstanceIds -eq 1) ($mode+' '+$badAlias.Kind+' '+$alias+' cannot be coerced into a valid instance key')
            }
        }
        $alternateAlias=[pscustomobject]@{DeviceInstanceId=@('INVALID-ARRAY');PNPDeviceID=17;InstanceId='USB\VALID-000123';DeviceID='';Name='Valid legacy fallback'}
        Assert (-not (Get-ExtendedIdentificationCoverage @{} @($alternateAlias)).NeedsReview) ($mode+' a valid alternate string key is accepted beside malformed primary aliases')
        $emptyAliases=[pscustomobject]@{DeviceInstanceId=(' '+[char]0+' ');PNPDeviceID="`t";InstanceId='';DeviceID=$null;Name='No usable legacy key'}
        Assert ((Get-ExtendedIdentificationCoverage @{} @($emptyAliases)).MissingInstanceIds -eq 1) ($mode+' null, blank and NUL-only alias strings remain missing')
        $storedCoverage=Get-ExtendedIdentificationCoverage ([pscustomobject]@{MissingInstanceIds=2}) @($alternateAlias)
        Assert ($storedCoverage.NeedsReview -and $storedCoverage.MissingInstanceIds -eq 2) ($mode+' valid aliases do not erase an explicit positive stored missing-instance counter')
        $containerRows=@([pscustomobject]@{DeviceInstanceId='USB\GROUP';ContainerIdConflict=$true})
        Assert ((Get-ExtendedIdentificationCoverage @{} $containerRows).ContainerIdConflicts -eq 1 -and (Get-ExtendedIdentificationCoverage @{} $containerRows).NeedsReview) ($mode+' genuine container-ID disagreements remain separate from hardware condition')
        $combined=[ordered]@{'Report info'=@{Version='3.97';Computer='SYNTHETIC';Generated='2026-11-16T00:00:00Z';ExtendedStatus='Refreshed'};'PnP hardware IDs'=$denied;'Extended device inventory'=$missing.Devices;'Extended scan info'=$missing.Info}
        $review=Get-ReviewSummary $combined @() @()
        Assert ($review.CoverageCount -eq 2 -and $review.Total -eq 2 -and $review.UnreadCount -eq 0 -and @($review.CoverageIssues|Where-Object Kind -ne 'Identification coverage').Count -eq 0) ($mode+' review aggregates present and extended coverage without classifying them as unread sections')
        $report=$combined;$identifiers=@();$warnings=New-Object 'System.Collections.Generic.List[string]'
        $script:rendered.Clear();Show-Attention -Inline
        Assert (($script:rendered -join ' ') -match 'IDENTIFICATION COVERAGE / 2' -and ($script:rendered -join ' ') -match 'do not establish a hardware fault') ($mode+' BAT attention view explains identification coverage and its limits')
        $stem=Join-Path $root $mode
        Write-ReportPair $stem (Get-PlainRecords $combined.'PnP hardware IDs' 'PnP hardware IDs'|Out-String) ($combined|ConvertTo-Json -Depth 16)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ((Get-ReviewSummary $saved @() @()).CoverageCount -eq 2 -and $saved.'PnP hardware IDs'[0].DeviceInstanceId -ceq 'USB\SYNTHETIC-000123' -and $saved.'PnP hardware IDs'[0].IdentificationReadFailureCodes -contains 'READ-01') ($mode+' saved JSON retains coverage and exact raw instance data')
        Assert ([IO.File]::ReadAllText($stem+'.txt') -match 'READ-01') ($mode+' text reporting retains the failed identification code')
        $combined.'Report info'.ExtendedStatus='Unavailable'
        Assert (@(Get-ScanIdentificationIssues $combined).Count -eq 1) ($mode+' stale retained catalog coverage is not counted again after its refresh failed')
        $combined.'Report info'.ExtendedStatus='Refreshed';$combined.'PnP hardware IDs'=$healthy;$combined.'Extended device inventory'=$optional.Devices;$combined.'Extended scan info'=$optional.Info
        Assert ((Get-ReviewSummary $combined @() @()).CoverageCount -eq 0) ($mode+' healthy refreshed captures clear earlier coverage findings')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}

# Exercise the production complete-scan path in both modes using synthetic
# providers. No native device/status/firmware reader is called by this fixture.
function Get-CimInstance {
    param($ClassName,$Namespace,$Filter,$Property,$OperationTimeoutSec)
    if($ClassName -eq 'Win32_Tpm'){return [pscustomobject]@{SpecVersion='2.0';IsEnabled_InitialValue=$true;IsActivated_InitialValue=$true}}
    [pscustomobject]@{Name='Synthetic device';Caption='Synthetic Windows';InstanceName='DISPLAY\SYNTHETIC';DeviceID='CPU0';PNPDeviceID='USB\A-000123';PNPClass='USB';ClassGuid='SYNTHETIC';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-000123');CompatibleID=@();ProcessorId='CPU-000123';UUID='SYSTEM-000123';SerialNumber='SERIAL-000123';Manufacturer='Synthetic';Model='Synthetic';Index=0;Number=0;DiskNumber=0;PartitionNumber=1;TotalPhysicalMemory=8GB;Capacity=8GB;Size=8GB;FreeSpace=4GB;SerialNumberID=@(48,48,49)}
}
function Get-PnpDevice {param([switch]$PresentOnly) foreach($id in @('USB\A-000123','USB\B-000124')){[pscustomobject]@{InstanceId=$id;Name='Synthetic device';Class='USB';ClassGuid='SYNTHETIC';Present=$true;HardwareID=@('MODEL-000123');CompatibleID=@();ConfigManagerErrorCode=0}}}
function Get-PnpDeviceProperty {
    [CmdletBinding()]param($InstanceId,$KeyName,$ThrottleLimit)
    foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('MODEL-000123')}}
    if($env:HWID_COVERAGE_FIXTURE -eq 'Blocked'){$PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Synthetic lookup denial'),'Synthetic.FullDenied',[Management.Automation.ErrorCategory]::PermissionDenied,$InstanceId))}
}
function Get-ClassHiddenState {param($ClassGuid) $false}
function Get-NativeNodeStatus {param($InstanceId) [uint32]0}
function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='Synthetic NIC';InterfaceGuid='NIC-000123';MacAddress='001122334455';HardwareInterface=$false}}
function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='MACHINE-000123'}}
function Confirm-SecureBootUEFI {param($ErrorAction) $true}
$prior=$env:HWID_COVERAGE_FIXTURE
try{
    foreach($worker in @($false,$true)){
        $env:HWID_COVERAGE_FIXTURE='Blocked'
        $capture=Invoke-HardwareScan 1 -UseWorker $worker -IncludeExtended $true
        $coverage=Get-ExtendedIdentificationCoverage $capture.Inventory.'Extended scan info' $capture.Inventory.'Extended device inventory'
        $review=Get-ReviewSummary $capture.Inventory $capture.Identifiers $capture.Warnings
        Assert ($capture.Completed -and $capture.Inventory.'Scan timing'.Count -eq 18 -and $coverage.NeedsReview -and $review.CoverageCount -eq 1 -and $review.UnreadCount -eq 0) ('Full scan worker='+$worker+' remains readable but cannot hide a blocked all-known identification check')
        $env:HWID_COVERAGE_FIXTURE='Healthy'
        $next=Invoke-HardwareScan 2 -UseWorker $worker -IncludeExtended $true
        Assert ($next.Completed -and $next.Inventory.'Report info'.ScanNumber -eq 2 -and (Get-ReviewSummary $next.Inventory $next.Identifiers $next.Warnings).CoverageCount -eq 0) ('Full scan worker='+$worker+' clears the coverage finding on a healthy subsequent capture')
    }
}finally{$env:HWID_COVERAGE_FIXTURE=$prior}
[Console]::WriteLine(('All {0} identification-coverage checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
