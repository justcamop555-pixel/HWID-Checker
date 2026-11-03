param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Write-PnpValue {param($Label,$Value,$Color) $script:rendered.Add([pscustomobject]@{Label=$Label;Value=[string]$Value;Color=$Color})}
function Get-PnpDevice {
    param([switch]$PresentOnly)
    foreach($name in @('CHILD','PARENT-A','PARENT-B')){[pscustomobject]@{Name=$name;PNPDeviceID=('USB\'+$name);PNPClass='USB';ClassGuid='TEST';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-'+$name)}}
}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw 'Synthetic suite must not query real hardware'}
function Read-ParentFixture([string]$ParentBody){
    $query='function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) foreach($id in $InstanceId){if($id -eq "USB\CHILD"){'+$ParentBody+'};[pscustomobject]@{InstanceId=$id;KeyName="DEVPKEY_Device_DevNodeStatus";Data=[uint32]0}}};Get-ExtendedDeviceInventory'
    return @(Invoke-ScanQuery ([scriptblock]::Create($query)))[0]
}
function Parent-Property([string]$Value){return ('[pscustomobject]@{InstanceId=$id;KeyName="DEVPKEY_Device_Parent";Data='+$Value+'}')}
$root=Join-Path $PSScriptRoot ('test-output-parent-readings-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        foreach($order in @('Forward','Reverse')){
            $values=if($order -eq 'Forward'){@('"USB\PARENT-A"','"USB\PARENT-B"')}else{@('"USB\PARENT-B"','"USB\PARENT-A"')}
            $catalog=Read-ParentFixture (($values | ForEach-Object {Parent-Property $_}) -join ';');$child=$catalog.Devices[0]
            Assert ($null -eq $child.ParentInstanceId -and $null -eq $child.ParentName -and $child.ParentInstanceIdConflict -eq $true) ($mode+' '+$order+' contradictory parent readings cannot silently choose the last parent')
            Assert ($child.ParentInstanceIdReadings.Count -eq 2 -and $child.ParentInstanceIdReadings -contains 'USB\PARENT-A' -and $child.ParentInstanceIdReadings -contains 'USB\PARENT-B') ($mode+' '+$order+' both parent observations remain available')
            Assert ($catalog.Info.ParentLinks -eq 0 -and $catalog.Info.ParentLinkConflicts -eq 1 -and $child.ParentReadStatus -match '^Conflicting') ($mode+' '+$order+' conflicted relationships are excluded from usable parent links')
            Assert ((@(Get-ExtendedDeviceReview $child) -join ' ') -match 'Parent.*disagreed' -and (Get-ExtendedProblemCode $child) -eq 0) ($mode+' '+$order+' metadata disagreement is explained without inventing a Windows device fault')
            $conflicted=$catalog
        }
        $same=Read-ParentFixture ((@('" USB\PARENT-A "','"usb\parent-a"','"`0USB\PARENT-A`0"') | ForEach-Object {Parent-Property $_}) -join ';');$child=$same.Devices[0]
        Assert (-not $child.ParentInstanceIdConflict -and $child.ParentInstanceId -ceq ' USB\PARENT-A ' -and $child.ParentName -ceq 'PARENT-A') ($mode+' equivalent case and padding readings resolve the parent while preserving original text')
        Assert ($child.ParentInstanceIdReadings.Count -eq 3 -and $same.Info.ParentLinks -eq 1 -and $same.Info.ParentLinkConflicts -eq 0 -and @((Get-ExtendedDeviceReview $child) | Where-Object {$_ -match '^Parent'}).Count -eq 0) ($mode+' equivalent readings keep observations without a false conflict or review finding')
        foreach($order in @('InvalidFirst','InvalidLast')){
            $values=if($order -eq 'InvalidFirst'){@('@("USB\PARENT-B")','"USB\PARENT-A"')}else{@('"USB\PARENT-A"','@("USB\PARENT-B")')}
            $mixed=Read-ParentFixture (($values | ForEach-Object {Parent-Property $_}) -join ';');$child=$mixed.Devices[0]
            Assert ($child.ParentInstanceId -ceq 'USB\PARENT-A' -and $child.ParentName -ceq 'PARENT-A' -and -not $child.ParentInstanceIdConflict -and $child.ParentReadStatus -match '^Invalid') ($mode+' '+$order+' malformed neighboring metadata cannot erase a valid parent reading')
            $invalidIndex=if($order -eq 'InvalidFirst'){0}else{1}
            Assert ($child.ParentInstanceIdReadings[$invalidIndex] -is [System.Collections.IList] -and $child.ParentInstanceIdReadings[$invalidIndex][0] -ceq 'USB\PARENT-B' -and $mixed.Info.ParentLinkConflicts -eq 0) ($mode+' '+$order+' raw nested metadata is preserved without coercion into an instance ID')
        }
        foreach($bad in @('@("USB\PARENT-A")','@{Value="USB\PARENT-A"}','$true','0')){
            $invalid=Read-ParentFixture (Parent-Property $bad);$child=$invalid.Devices[0]
            Assert ($null -eq $child.ParentInstanceId -and $null -eq $child.ParentName -and -not $child.ParentInstanceIdConflict -and $child.ParentReadStatus -match '^Invalid' -and $null -ne $child.RawParentInstanceId) ($mode+' malformed '+$bad+' parent data leaves the catalog and raw observation usable')
        }
        $empty=Read-ParentFixture ((@('""','" "','"`0 "') | ForEach-Object {Parent-Property $_}) -join ';');$child=$empty.Devices[0]
        Assert ($null -eq $child.ParentInstanceId -and $child.ParentReadStatus -eq 'Not supplied' -and -not $child.ParentInstanceIdConflict -and $empty.Info.ParentLinks -eq 0) ($mode+' empty and NUL-only parent values do not create a phantom link or conflict')
        $retry=@(Invoke-ScanQuery {
            function Get-PnpDeviceProperty {
                param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
                if($InstanceId.Count -gt 1){[pscustomobject]@{InstanceId='USB\CHILD';KeyName='DEVPKEY_Device_Parent';Data='USB\PARENT-A'};throw 'Synthetic device disappeared during batch'}
                if($InstanceId[0] -eq 'USB\CHILD'){[pscustomobject]@{InstanceId='USB\CHILD';KeyName='DEVPKEY_Device_Parent';Data='USB\PARENT-B'}}
            }
            Get-ExtendedDeviceInventory
        })[0];$child=$retry.Devices[0]
        Assert ($retry.Info.PropertyRetryDevices -eq 3 -and $child.ParentInstanceIdConflict -and $null -eq $child.ParentName -and $child.ParentInstanceIdReadings.Count -eq 2) ($mode+' batch recovery preserves disagreeing earlier and later parent readings')
        Assert ($child.DeviceInstanceId -ceq 'USB\CHILD' -and $child.HardwareID[0] -ceq 'MODEL-CHILD' -and $retry.Devices.Count -eq 3 -and $retry.Info.PropertyReadErrors -gt 0) ($mode+' changing parent data cannot discard core IDs or neighboring device records')
        $fresh=Read-ParentFixture (Parent-Property '"USB\PARENT-A"')
        Assert (-not $fresh.Devices[0].ParentInstanceIdConflict -and $fresh.Info.ParentLinkConflicts -eq 0 -and $fresh.Devices[0].ParentName -ceq 'PARENT-A' -and $fresh.Devices[0].ParentInstanceIdReadings.Count -eq 1) ($mode+' the next scan does not inherit stale parent conflicts or observations')
        $report=[ordered]@{'Report info'=@{Version='3.83';Computer='TEST';Generated='2026-11-02T12:00:00-05:00'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='CPU-000123'});'Extended device inventory'=$conflicted.Devices;'Extended scan info'=$conflicted.Info}
        $stem=Join-Path $root $mode;Write-ReportPair $stem ((Get-PlainRecords $conflicted.Devices) -join [Environment]::NewLine) ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json');$child=$saved.'Extended device inventory'[0]
        Assert ($child.ParentInstanceIdConflict -and $null -eq $child.ParentInstanceId -and $child.ParentInstanceIdReadings.Count -eq 2 -and $saved.'Extended scan info'.ParentLinkConflicts -eq 1) ($mode+' JSON preserves unresolved parent relationships and all observations')
        Assert ([IO.File]::ReadAllText($stem+'.txt') -match 'USB\\PARENT-A' -and [IO.File]::ReadAllText($stem+'.txt') -match 'USB\\PARENT-B') ($mode+' TXT retains both parent observations for inspection')
        $comparison=Compare-Inventories $report $saved
        Assert ($comparison.Changes.Count -eq 0 -and $comparison.PreviousCount -gt 0 -and $comparison.PreviousCount -eq $comparison.CurrentCount) ($mode+' unresolved topology cannot manufacture hardware identifier changes')
        $script:rendered.Clear();Show-PnpRecords $conflicted.Devices -Full -Extended
        Assert (@($rendered | Where-Object {$_.Label -eq 'Parent link' -and $_.Value -match 'Unresolved' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' detailed device view labels the conflicted parent link explicitly')
        $script:rendered.Clear();Show-ExtendedDeviceReport
        Assert (@($rendered | Where-Object {$_.Label -eq 'Parent conflicts' -and $_.Value -match '^1 ' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' extended summary distinguishes unresolved parent links from readable IDs')
        $script:rendered.Clear();Show-ScanCompletion $report @(Get-IdentifierRows $report) 17 17 $true ' / extended READ'
        Assert (@($rendered | Where-Object {$_.Label -eq 'Device relationships' -and $_.Value -match '^1 ' -and $_.Color -eq $palette.Warn}).Count -eq 1) ($mode+' scan completion discloses conflicting parent observations without marking valid reads unavailable')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks parent-reading checks passed under PowerShell $($PSVersionTable.PSVersion).")
