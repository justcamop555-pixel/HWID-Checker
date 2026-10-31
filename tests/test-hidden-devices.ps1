$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Fixture';PNPDeviceID='USB\A';PNPClass='USB';ClassGuid='NORMAL';Present=$true;ConfigManagerErrorCode=0;HardwareID=@('MODEL-A')}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) throw 'No real provider query is allowed in this synthetic suite'}
function Read-HiddenFixture([string]$PropertyBody,[string]$PrimaryBody=''){
    $text='function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) '+$PropertyBody+'};'
    if($PrimaryBody){$text+='function Get-PnpDevice {param([switch]$PresentOnly) '+$PrimaryBody+'};'}
    $text+='Get-ExtendedDeviceInventory'
    return @(Invoke-ScanQuery ([scriptblock]::Create($text)))[0]
}
foreach($case in @(@{Name='singleton array';Value=@(22)},@{Name='boolean';Value=$true},@{Name='dictionary';Value=@{Value=22}},@{Name='object';Value=[pscustomobject]@{Value=22}},@{Name='date';Value=[datetime]'2026-10-30'})){
    $status=Get-PnpStatus $case.Value
    Assert ($null -eq $status.Code -and $status.Quality -eq 'Unknown') ('A '+$case.Name+' cannot masquerade as a scalar device problem code')
}
foreach($case in @(@('0022',22),@([uint32]0,0),@([uint32]22,22))){Assert ((Get-PnpStatus $case[0]).Code -eq $case[1]) 'Valid scalar numeric problem codes keep their documented value'}
$root=Join-Path $PSScriptRoot ('test-output-hidden-devices-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $arrayProblem=Read-HiddenFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data=@(22)}'
        $row=$arrayProblem.Devices[0]
        Assert ($null -eq $row.DeviceProblemCode -and $row.ProblemCodeReadStatus -match '^Invalid' -and (Get-ExtendedProblemCode $row) -eq 0) ($mode+' an array-valued optional problem code stays invalid while valid native status remains usable')
        Assert ($row.RawProblemCode.Count -eq 1 -and $row.RawProblemCode[0] -is [System.Collections.IList] -and $row.RawProblemCode[0][0] -eq 22 -and $row.DeviceInstanceId -ceq 'USB\A' -and $row.HardwareID[0] -ceq 'MODEL-A') ($mode+' malformed raw problem observations and valid neighboring identifiers are preserved')
        $booleanProblem=Read-HiddenFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data=$true}'
        Assert ($null -eq $booleanProblem.Devices[0].DeviceProblemCode -and $booleanProblem.Devices[0].ProblemCodeReadStatus -match '^Invalid' -and $booleanProblem.Devices[0].RawProblemCode[0] -is [bool] -and (Get-ExtendedProblemCode $booleanProblem.Devices[0]) -eq 0) ($mode+' a boolean optional problem code cannot hide an available native code')
        foreach($order in @('Forward','Reverse')){
            $values=if($order -eq 'Forward'){@(0,22)}else{@(22,0)}
            $body=($values | ForEach-Object {'[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data='+$_+'}'}) -join ';'
            $conflicted=Read-HiddenFixture $body;$row=$conflicted.Devices[0]
            Assert ($row.ProblemCodeConflict -eq $true -and $null -eq (Get-ExtendedProblemCode $row) -and $row.ProblemCodeReadings.Count -eq 2 -and $row.ProblemCodeReadings -contains 0 -and $row.ProblemCodeReadings -contains 22) ($mode+' '+$order+' conflicting optional problem readings cannot assert working or disabled')
            Assert ((@(Get-ExtendedDeviceReview $row) -join ' ') -match '(?i)(problem|status).*(conflict|disagree)') ($mode+' '+$order+' conflicting problem readings have an explicit review finding')
        }
        $nativeDisagrees=Read-HiddenFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data=22}'
        Assert ($nativeDisagrees.Devices[0].ProblemCodeConflict -eq $true -and $null -eq (Get-ExtendedProblemCode $nativeDisagrees.Devices[0]) -and $nativeDisagrees.Devices[0].ProblemCodeReadings.Count -eq 1 -and $nativeDisagrees.Devices[0].ConfigManagerErrorCode -eq 0) ($mode+' one optional code disagreeing with the native code remains a conflict')
        $invalidNative=Read-HiddenFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data=0}' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=@(22);HardwareID=@("MODEL-A")}'
        Assert ((Get-ExtendedProblemCode $invalidNative.Devices[0]) -eq 0 -and -not $invalidNative.Devices[0].ProblemCodeConflict) ($mode+' malformed native status cannot fabricate disagreement with a valid optional reading')
        $equal=Read-HiddenFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data="0022"};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_ProblemCode";Data=22}' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=22;HardwareID=@("MODEL-A")}'
        Assert ((Get-ExtendedProblemCode $equal.Devices[0]) -eq 22 -and -not $equal.Devices[0].ProblemCodeConflict -and $equal.Devices[0].ProblemCodeReadings.Count -eq 1) ($mode+' repeated equivalent optional/native disabled codes remain usable')
        foreach($parent in @(@('array','@("USB\ROOT")'),@('dictionary','@{Value="USB\ROOT"}'),@('boolean','$true'))){
            $parentCatalog=Read-HiddenFixture ('[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_Parent";Data='+$parent[1]+'}')
            $row=$parentCatalog.Devices[0];$failure=$null
            try{Assert-ExtendedDeviceCatalog $parentCatalog}catch{$failure=$_}
            Assert ($null -eq $failure -and $null -eq $row.ParentInstanceId -and $row.ParentReadStatus -match '^Invalid' -and $null -ne $row.RawParentInstanceId -and $row.DeviceInstanceId -ceq 'USB\A' -and $row.HardwareID[0] -ceq 'MODEL-A') ($mode+' malformed '+$parent[0]+' parent metadata cannot discard the usable device catalog')
            if($parent[0] -eq 'array'){$arrayParent=$parentCatalog}
        }
        $alias=Read-HiddenFixture '' '[pscustomobject]@{Name=$null;FriendlyName="Alias fixture";InstanceId="USB\ALIAS";PNPClass=" ";Class="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@("MODEL-ALIAS")}'
        Assert ($alias.Devices[0].Name -eq 'Alias fixture' -and $alias.Devices[0].DeviceInstanceId -ceq 'USB\ALIAS' -and $alias.Devices[0].PNPClass -eq 'USB' -and ((@(Get-ExtendedDeviceReview $alias.Devices[0]) -join ' ') -notmatch 'class was not supplied')) ($mode+' Class aliases remain available rather than becoming false missing-class findings')
        $savedReport=[ordered]@{'Report info'=@{Version='3.61';Computer='TEST';Generated='2026-10-30T12:00:00Z'};'Extended device inventory'=@($conflicted.Devices[0],$arrayProblem.Devices[0],$arrayParent.Devices[0]);'Extended scan info'=@{Captured='2026-10-30T12:00:00Z';Source='Synthetic mixed metadata';Records=3}}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic hidden-device metadata' ($savedReport | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Extended device inventory'[0].ProblemCodeConflict -eq $true -and $saved.'Extended device inventory'[0].ProblemCodeReadings.Count -eq 2 -and $null -eq (Get-ExtendedProblemCode $saved.'Extended device inventory'[0])) ($mode+' saved snapshots retain problem conflicts and distinct readings')
        Assert ($saved.'Extended device inventory'[1].RawProblemCode[0][0] -eq 22 -and $saved.'Extended device inventory'[1].ProblemCodeReadStatus -match '^Invalid' -and $saved.'Extended device inventory'[2].RawParentInstanceId[0] -ceq 'USB\ROOT' -and $saved.'Extended device inventory'[2].ParentReadStatus -match '^Invalid') ($mode+' raw malformed problem/parent values and read-status details survive import')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$devices=@(
    [pscustomobject]@{Name='Remembered hidden';DeviceInstanceId='USB\REMEMBERED';PNPClass='USB';Present=$false;HiddenByNodeFlag=$true;HiddenByClass=$false;ConfigManagerErrorCode=45},
    [pscustomobject]@{Name='Hidden disabled';DeviceInstanceId='USB\DISABLED';PNPClass='USB';Present=$true;HiddenByNodeFlag=$true;HiddenByClass=$false;ConfigManagerErrorCode=22},
    [pscustomobject]@{Name='Plain present';DeviceInstanceId='USB\PRESENT';PNPClass='USB';Present=$true;HiddenByNodeFlag=$false;HiddenByClass=$false;ConfigManagerErrorCode=0},
    [pscustomobject]@{Name='Unknown hidden';DeviceInstanceId='USB\UNKNOWN';PNPClass='USB';Present=$null;HiddenByNodeFlag=$true;HiddenByClass=$false;ConfigManagerErrorCode=0}
)
foreach($case in @(@(0,'2,3'),@(1,'3,4,5'),@(2,'5'),@(3,'3,6'))){
    $matching=@('2','3','4','5','6' | Where-Object {Test-ExtendedDeviceGroup $devices[$case[0]] $_}) -join ','
    Assert ($matching -ceq $case[1]) ('Independent extended views include all matching groups for '+$devices[$case[0]].Name)
}
$report=[ordered]@{'Report info'=@{Computer='TEST'};'Extended device inventory'=$devices;'Extended scan info'=@{Captured='2026-10-30T12:00:00Z';Source='Synthetic overlap';Records=4;NodeFlagsRead=4;ClassFlagsRead=4}}
$script:uiRows=New-Object 'System.Collections.Generic.List[object]';$script:shownSets=New-Object 'System.Collections.Generic.List[string]';$script:rendered.Clear()
function Write-PnpValue {param($Label,$Value,$Color) $script:uiRows.Add([pscustomobject]@{Label=$Label;Value=$Value});$script:rendered.Add(([string]$Label+' '+[string]$Value))}
function Show-PnpRecords {param($Devices,[switch]$Full,[switch]$Extended) $script:shownSets.Add((@($Devices.Name) -join '|'))}
Show-ExtendedDeviceReport
Assert (@($script:uiRows | Where-Object {$_.Label -like '[[]2[]]*' -and $_.Value -eq 1}).Count -eq 1 -and @($script:uiRows | Where-Object {$_.Label -like '[[]3[]]*' -and $_.Value -eq 3}).Count -eq 1 -and @($script:uiRows | Where-Object {$_.Label -like '[[]4[]]*' -and $_.Value -eq 1}).Count -eq 1 -and @($script:uiRows | Where-Object {$_.Label -like '[[]5[]]*' -and $_.Value -eq 2}).Count -eq 1 -and @($script:uiRows | Where-Object {$_.Label -like '[[]6[]]*' -and $_.Value -eq 1}).Count -eq 1) 'Rendered group counts use independent filters rather than a priority-only partition'
Assert ($script:shownSets[0] -eq 'Remembered hidden' -and $script:shownSets[1] -eq 'Remembered hidden|Hidden disabled|Unknown hidden' -and $script:shownSets[2] -eq 'Hidden disabled' -and $script:shownSets[3] -eq 'Hidden disabled|Plain present' -and $script:shownSets[4] -eq 'Unknown hidden') 'Hidden/disconnected and hidden/disabled records appear in every matching report view'
Assert (($script:rendered -join ' ') -match '(?i)overlap') 'Extended report explains that its group counts overlap'
[Console]::WriteLine("All $script:checks hidden-device checks passed under PowerShell $($PSVersionTable.PSVersion).")
