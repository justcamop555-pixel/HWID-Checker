param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
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
function Invoke-IdentityFixture([string]$Case){
    $query=[scriptblock]::Create(@'
$script:alternateCalls=0;$script:alternateFilter='UNSET';$script:alternateTimeout=0;$script:propertyCalls=0;$script:requested=@()
function Get-PnpDevice {
    param([switch]$PresentOnly)
    if('FIXTURE_CASE' -in @('PrimaryFailed','BothFailed')){throw [NotSupportedException]::new('Synthetic primary reader unavailable')}
    if('FIXTURE_CASE' -in @('Healthy','Mixed')){
        [pscustomobject]@{Name='Primary identified';Class='USB';InstanceId='USB\PRIMARY-000123';ClassGuid='SYNTHETIC';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('PRIMARY-MODEL-0000')}
        if('FIXTURE_CASE' -eq 'Healthy'){return}
    }
    [pscustomobject]@{Name='Primary named observation';Class='USB';ClassGuid='SYNTHETIC';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('PRIMARY-NO-KEY-MODEL');UnexpectedTransportMetadata=@{Transport='Do not serialize native transport metadata'}}
    if('FIXTURE_CASE' -eq 'Narrower'){
        [pscustomobject]@{Name='Second primary observation';Class='USB';ClassGuid='SYNTHETIC';Present=$false;ConfigManagerErrorCode=45;HardwareID=@('SECOND-PRIMARY-MODEL')}
    }
}
function Get-HwidInstance {
    param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec)
    $script:alternateCalls++;$script:alternateFilter=$Filter;$script:alternateTimeout=$OperationTimeoutSec
    if($ClassName -ne 'Win32_PnPEntity'){throw 'Unexpected alternate class'}
    switch('FIXTURE_CASE'){
        'Denied' {throw [UnauthorizedAccessException]::new('Synthetic alternate access denied')}
        'Timeout' {throw [TimeoutException]::new('Synthetic alternate timeout')}
        'BothFailed' {throw [UnauthorizedAccessException]::new('Synthetic final access denied')}
        'Empty' {return}
        'NoKeys' {[pscustomobject]@{Name='Alternate named observation';PNPClass='USB';ClassGuid='SYNTHETIC';Present=$false;ConfigManagerErrorCode=45};return}
    }
    [pscustomobject]@{Name='Recovered OEM device';PNPClass='USB';PNPDeviceID=' USB\VID_0001&PID_0002\0000123 ';ClassGuid='SYNTHETIC';Present=$true;ConfigManagerErrorCode=28;HardwareID=@('MODEL-0001','MODEL-0000');CompatibleID=@('COMPAT-0000')}
    if('FIXTURE_CASE' -eq 'Narrower'){return}
    if('FIXTURE_CASE' -eq 'Malformed'){
        [pscustomobject]@{Name='Invalid alternate';PNPDeviceID=@('BAD','KEY');ClassGuid='SYNTHETIC';Present=$true};return
    }
    [pscustomobject]@{Name='Remembered OEM device';PNPClass='USB';DeviceID='USB\REMEMBERED-0000';ClassGuid='SYNTHETIC';Present=$false;ConfigManagerErrorCode=45;HardwareID=@('REMEMBERED-MODEL')}
}
function Get-PnpDeviceProperty {
    param($InstanceId,$KeyName,$ThrottleLimit,$ErrorAction,$ErrorVariable)
    $script:propertyCalls++;$script:requested+=@($InstanceId)
    foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_IsPresent';Data=($id -ne 'USB\REMEMBERED-0000')}}
}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) if($InstanceId){return [uint32]0};return $null}
$catalog=$null;$failure=$null
try{$catalog=Get-ExtendedDeviceInventory}catch{$failure=$_}
[pscustomobject]@{Catalog=$catalog;Failure=$failure;AlternateCalls=$script:alternateCalls;Filter=$script:alternateFilter;Timeout=$script:alternateTimeout;PropertyCalls=$script:propertyCalls;Requested=$script:requested}
'@.Replace('FIXTURE_CASE',$Case))
    $result=@(Invoke-ScanQuery $query)[0]
    if($null -ne $result.Catalog){Assert-ExtendedDeviceCatalog $result.Catalog}
    return $result
}
$root=Join-Path $PSScriptRoot ('test-output-extended-identity-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $recovered=Invoke-IdentityFixture 'Recovered'
        $catalog=$recovered.Catalog
        Assert ($null -eq $recovered.Failure -and $catalog.Devices.Count -eq 2 -and $catalog.Info.IdentityRecoveryAttempted -eq $true) ($mode+' an unidentified primary catalog tries one validated alternate before accepting an identity limit')
        Assert ($recovered.AlternateCalls -eq 1 -and $null -eq $recovered.Filter -and $recovered.Timeout -eq 20) ($mode+' identity recovery is one bounded unfiltered read, including remembered devices')
        Assert ($catalog.Info.Source -ceq 'Win32_PnPEntity / unfiltered identity recovery' -and $catalog.Info.FallbackReason -match 'no usable instance' -and $catalog.Info.IdentityRecoveryStatus -ceq 'Recovered instance IDs') ($mode+' the accepted reader and primary identity limitation remain explicit')
        $device=$catalog.Devices[0]
        Assert ($device.DeviceInstanceId -ceq ' USB\VID_0001&PID_0002\0000123 ' -and $device.HardwareID[1] -ceq 'MODEL-0000' -and $device.CompatibleID[0] -ceq 'COMPAT-0000') ($mode+' recovered instance/model/compatible IDs preserve exact padding, order and leading zeros')
        Assert ($device.Name -ceq 'Recovered OEM device' -and $device.ConfigManagerErrorCode -eq 28 -and $catalog.Devices[1].Present -eq $false -and $catalog.Devices[1].DeviceInstanceId -ceq 'USB\REMEMBERED-0000') ($mode+' independent alternate observations retain labels, genuine driver findings and remembered-node presence')
        Assert ($recovered.PropertyCalls -eq 1 -and $recovered.Requested.Count -eq 2 -and $recovered.Requested[0] -ceq 'USB\VID_0001&PID_0002\0000123' -and $catalog.Info.PropertyNodesRequested -eq 2) ($mode+' property queries use recovered normalized keys without rewriting the saved instance text')
        Assert (@($catalog.Devices|Where-Object Name -eq 'Primary named observation').Count -eq 0) ($mode+' replacement does not guess a name-based match or mix anonymous primary data into accepted alternate records')
        Assert ($catalog.Info.IdentityRecoveryPrimaryRecords.Count -eq 1 -and $catalog.Info.IdentityRecoveryPrimaryRecords[0].Name -ceq 'Primary named observation' -and $catalog.Info.IdentityRecoveryPrimaryRecords[0].HardwareID[0] -ceq 'PRIMARY-NO-KEY-MODEL') ($mode+' replacing the working catalog retains exact primary observations for inspection')
        Assert ($catalog.Info.IdentityRecoveryAlternateRecords.Count -eq 2 -and $catalog.Info.IdentityRecoveryAlternateRecords[0].PNPDeviceID -ceq ' USB\VID_0001&PID_0002\0000123 ' -and $catalog.Info.IdentityRecoveryAlternateRecords[1].DeviceID -ceq 'USB\REMEMBERED-0000') ($mode+' validated alternate observations retain original aliases and exact values separately')
        Assert (@($catalog.Info.IdentityRecoveryPrimaryRecords[0].PSObject.Properties).Count -eq 14 -and $null -eq $catalog.Info.IdentityRecoveryPrimaryRecords[0].PSObject.Properties['UnexpectedTransportMetadata']) ($mode+' retained observations project only known device fields rather than native transport metadata')

        foreach($case in @(@('Denied','READ-01'),@('Timeout','READ-02'),@('Malformed','READ-06'))){
            $retained=Invoke-IdentityFixture $case[0]
            Assert ($null -eq $retained.Failure -and $retained.AlternateCalls -eq 1 -and $retained.Catalog.Devices.Count -eq 1 -and $retained.Catalog.Devices[0].Name -ceq 'Primary named observation') ($mode+' '+$case[0]+' optional recovery retains the complete useful primary inventory')
            Assert ($retained.Catalog.Info.IdentityRecoveryFailureCode -ceq $case[1] -and $retained.Catalog.Info.IdentityRecoveryStatus -ceq 'Alternate read failed; primary records retained' -and $retained.Catalog.Info.IdentityRecoveryDetail) ($mode+' '+$case[0]+' recovery keeps its typed failure code and explanation without failing the catalog')
            Assert ($retained.Catalog.Info.Source -ceq 'Get-PnpDevice / all known nodes' -and $retained.PropertyCalls -eq 0 -and $null -eq $retained.Catalog.Devices[0].DeviceInstanceId) ($mode+' '+$case[0]+' cannot leak partial alternate identifiers or manufacture property lookup coverage')
        }
        foreach($case in @('NoKeys','Empty')){
            $retained=Invoke-IdentityFixture $case
            Assert ($null -eq $retained.Failure -and $retained.AlternateCalls -eq 1 -and $retained.Catalog.Devices[0].Name -ceq 'Primary named observation' -and $retained.Catalog.Info.IdentityRecoveryStatus -ceq 'No usable alternate instance IDs; primary records retained') ($mode+' '+$case+' keeps the named primary when the alternate cannot identify it')
            Assert ($null -eq $retained.Catalog.Info.IdentityRecoveryFailureCode -and $retained.Catalog.Info.IdentityRecoveryDetail -and $retained.PropertyCalls -eq 0) ($mode+' '+$case+' describes an identity limit without inventing a provider failure or property read')
        }
        $narrower=Invoke-IdentityFixture 'Narrower'
        Assert ($null -eq $narrower.Failure -and $narrower.AlternateCalls -eq 1 -and $narrower.Catalog.Devices.Count -eq 2 -and $narrower.Catalog.Devices[0].Name -ceq 'Primary named observation' -and $narrower.Catalog.Devices[1].Name -ceq 'Second primary observation') ($mode+' a narrower alternate cannot erase useful primary observations')
        Assert ($narrower.Catalog.Info.IdentityRecoveryStatus -ceq 'Alternate catalog narrower; primary records retained' -and $narrower.Catalog.Info.IdentityRecoveryAlternateRecords.Count -eq 1 -and $narrower.Catalog.Info.IdentityRecoveryAlternateRecords[0].PNPDeviceID -ceq ' USB\VID_0001&PID_0002\0000123 ' -and $narrower.PropertyCalls -eq 0) ($mode+' a narrower alternate keeps its usable raw IDs separately without claiming they matched primary rows')
        foreach($case in @('Healthy','Mixed')){
            $retained=Invoke-IdentityFixture $case
            $expected=if($case -eq 'Mixed'){2}else{1}
            Assert ($null -eq $retained.Failure -and $retained.AlternateCalls -eq 0 -and $retained.Catalog.Devices.Count -eq $expected -and -not $retained.Catalog.Info.IdentityRecoveryAttempted) ($mode+' '+$case+' catalog avoids an extra reader and retains all original observations')
            Assert ($retained.Catalog.Info.IdentityRecoveryStatus -ceq 'Not needed' -and $null -eq $retained.Catalog.Info.IdentityRecoveryFailureCode -and $null -eq $retained.Catalog.Info.IdentityRecoveryDetail) ($mode+' '+$case+' fresh collection does not inherit prior recovery diagnostics')
        }
        $existing=Invoke-IdentityFixture 'PrimaryFailed'
        Assert ($null -eq $existing.Failure -and $existing.AlternateCalls -eq 1 -and $existing.Catalog.Info.Source -ceq 'Win32_PnPEntity / unfiltered fallback' -and -not $existing.Catalog.Info.IdentityRecoveryAttempted) ($mode+' an unreadable primary keeps the established validated fallback without a second alternate pass')
        $failed=Invoke-IdentityFixture 'BothFailed'
        $failure=Get-ScanFailureInfo $failed.Failure
        Assert ($null -eq $failed.Catalog -and $failed.AlternateCalls -eq 1 -and $failure.Code -ceq 'READ-01' -and $failure.Details -match 'Primary:.*Synthetic primary reader unavailable.*Fallback:.*Synthetic final access denied') ($mode+' genuinely unreadable catalogs still fail with both reader messages and the final typed reason')

        $savedReport=[ordered]@{'Report info'=@{Version='3.97';Computer='SYNTHETIC';Generated='2026-11-16T00:00:00Z'};'Extended device inventory'=$catalog.Devices;'Extended scan info'=$catalog.Info}
        $stem=Join-Path $root ('recovered-'+$mode)
        Write-ReportPair $stem 'Synthetic identity recovery' ($savedReport|ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'[0].DeviceInstanceId -ceq ' USB\VID_0001&PID_0002\0000123 ' -and $saved.'Extended scan info'.IdentityRecoveryStatus -ceq 'Recovered instance IDs' -and $saved.'Extended scan info'.IdentityRecoveryAttempted -eq $true) ($mode+' saved snapshots retain exact recovered observations and recovery coverage metadata')
        Assert ($saved.'Extended scan info'.IdentityRecoveryPrimaryRecords[0].Name -ceq 'Primary named observation' -and $saved.'Extended scan info'.IdentityRecoveryAlternateRecords[0].PNPDeviceID -ceq ' USB\VID_0001&PID_0002\0000123 ') ($mode+' saved snapshots retain both independent reader observations without guessed matches')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine(('All {0} extended identity recovery checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
