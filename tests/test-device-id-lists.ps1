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
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
function Get-PnpDevice {param([switch]$PresentOnly) [pscustomobject]@{Name='Fixture';PNPDeviceID='USB\A';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0;HardwareID=@();CompatibleID=@()}}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)}
function Get-ClassHiddenState {param($ClassGuid) return $false}
function Get-NativeNodeStatus {param($InstanceId) return [uint32]0}
function Get-CimInstance {param($ClassName,$Namespace,$Property,$Filter,$OperationTimeoutSec) [pscustomobject]@{Name='Fixture';PNPDeviceID='USB\A';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0;HardwareID=@([string][char]0,' ');CompatibleID=@([string][char]0)}}
function Read-IdListFixture([string]$Properties,[string]$Primary=''){
    $text='function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable) '+$Properties+'};'
    if($Primary){$text+='function Get-PnpDevice {param([switch]$PresentOnly) '+$Primary+'};'}
    $text+='Get-ExtendedDeviceInventory'
    return @(Invoke-ScanQuery ([scriptblock]::Create($text)))[0]
}
function Test-IdRawValue($Value,$Expected,[int]$Depth=0){
    if($Depth -gt 12 -or $null -eq $Value){return $false}
    if($Value -is [System.Collections.IList]){foreach($item in $Value){if(Test-IdRawValue $item $Expected ($Depth+1)){return $true}};return $false}
    if($Expected -is [bool]){return $Value -is [bool] -and $Value -eq $Expected}
    if($Expected -is [string]){return $Value -is [string] -and $Value -ceq $Expected}
    return $Value -is [ValueType] -and $Value -isnot [bool] -and $Value -eq $Expected
}
$root=Join-Path $PSScriptRoot ('test-output-device-id-lists-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $normal=@(Invoke-ScanQuery {Get-DriverHardwareIds})
        $blank=Read-IdListFixture '' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@([string][char]0," ");CompatibleID=@([string][char]0)}'
        Assert ($normal[0].HardwareID.Count -eq 0 -and $normal[0].CompatibleID.Count -eq 0 -and $blank.Devices[0].HardwareID.Count -eq 0 -and $blank.Devices[0].CompatibleID.Count -eq 0) ($mode+' normal and extended readers do not count NUL-only or blank model strings as IDs')
        $exact=Read-IdListFixture '' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@(" Model-0001 ","MODEL-0002");CompatibleID=@(" COMPAT-A ","COMPAT-B")}'
        Assert (($exact.Devices[0].HardwareID -join '|') -ceq ' Model-0001 |MODEL-0002' -and ($exact.Devices[0].CompatibleID -join '|') -ceq ' COMPAT-A |COMPAT-B') ($mode+' valid native model and compatible IDs preserve exact case, padding, zeros and order')
        $mixed=Read-IdListFixture '' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@(" Model-0001 ",$true,123);CompatibleID=@(" COMPAT-A ",$false)}'
        $row=$mixed.Devices[0]
        Assert ($row.HardwareID.Count -eq 1 -and $row.HardwareID[0] -ceq ' Model-0001 ' -and $row.CompatibleID.Count -eq 1 -and $row.CompatibleID[0] -ceq ' COMPAT-A ' -and $row.HardwareIDReadStatus -match '^Invalid' -and $row.CompatibleIDReadStatus -match '^Invalid') ($mode+' malformed native list entries do not hide neighboring valid IDs')
        Assert ((Test-IdRawValue $row.RawHardwareID $true) -and (Test-IdRawValue $row.RawHardwareID 123) -and (Test-IdRawValue $row.RawCompatibleID $false)) ($mode+' malformed native hardware and compatible observations remain raw')
        Assert ((@(Get-ExtendedDeviceReview $row) -join ' ') -match '(?i)invalid') ($mode+' malformed extended ID lists have an explicit review finding')
        $propertyMixed=Read-IdListFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@(" PROP-0001 ",$true,123,"PROP-0002")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@(" PROP-COMPAT-1 ",$false)}'
        $row=$propertyMixed.Devices[0]
        Assert (($row.HardwareID -join '|') -ceq ' PROP-0001 |PROP-0002' -and ($row.CompatibleID -join '|') -ceq ' PROP-COMPAT-1 ' -and $row.HardwareIDReadStatus -match '^Invalid' -and $row.CompatibleIDReadStatus -match '^Invalid') ($mode+' property-list recovery preserves valid exact IDs and labels malformed entries')
        Assert ((Test-IdRawValue $row.RawPropertyHardwareID $true) -and (Test-IdRawValue $row.RawPropertyHardwareID 123) -and (Test-IdRawValue $row.RawPropertyCompatibleID $false)) ($mode+' raw malformed property observations are retained separately from native lists')
        $equal=Read-IdListFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("A","B")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("A","B")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("C0")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("C0")}'
        Assert (-not $equal.Devices[0].HardwareIDPropertyConflict -and -not $equal.Devices[0].CompatibleIDPropertyConflict -and ($equal.Devices[0].HardwareID -join '|') -ceq 'A|B' -and $equal.Devices[0].HardwareIDPropertyReadings.Count -eq 2 -and $equal.Devices[0].CompatibleIDPropertyReadings.Count -eq 2) ($mode+' repeated equal optional lists retain observations without false conflicts or duplicate IDs')
        $conflicted=Read-IdListFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("A","B")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("B","C")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("C0","C1")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("C1","C2")}'
        $row=$conflicted.Devices[0]
        Assert (($row.HardwareID -join '|') -ceq 'A|B|C' -and ($row.CompatibleID -join '|') -ceq 'C0|C1|C2') ($mode+' differing property lists retain all exact valid observations in first-observation order')
        Assert ($row.HardwareIDPropertyConflict -eq $true -and $row.CompatibleIDPropertyConflict -eq $true -and $row.HardwareIDPropertyReadings.Count -eq 2 -and $row.CompatibleIDPropertyReadings.Count -eq 2) ($mode+' differing list observations remain visible with explicit conflict flags')
        Assert ((@(Get-ExtendedDeviceReview $row) -join ' ') -match '(?i)(differ|conflict|disagree)') ($mode+' differing optional ID lists have an explicit review explanation')
        $laterInvalid=Read-IdListFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("A","B")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@()};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@($true)};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("C0")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@()};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@($false)}'
        $row=$laterInvalid.Devices[0]
        Assert (($row.HardwareID -join '|') -ceq 'A|B' -and ($row.CompatibleID -join '|') -ceq 'C0' -and $row.HardwareIDReadStatus -match '^Invalid' -and $row.CompatibleIDReadStatus -match '^Invalid') ($mode+' later empty or malformed observations cannot erase previously read IDs')
        Assert ($row.HardwareIDPropertyReadings.Count -eq 3 -and $row.CompatibleIDPropertyReadings.Count -eq 3 -and (Test-IdRawValue $row.RawPropertyHardwareID $true) -and (Test-IdRawValue $row.RawPropertyCompatibleID $false)) ($mode+' empty and malformed trailing list observations remain available for inspection')
        $preferred=Read-IdListFixture '[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_HardwareIds";Data=@("ALT-A","ALT-B")};[pscustomobject]@{InstanceId="USB\A";KeyName="DEVPKEY_Device_CompatibleIds";Data=@("ALT-C")}' '[pscustomobject]@{Name="Fixture";PNPDeviceID="USB\A";PNPClass="USB";Present=$true;ConfigManagerErrorCode=0;HardwareID=@("PRIMARY-A");CompatibleID=@("PRIMARY-C")}'
        $row=$preferred.Devices[0]
        Assert (($row.HardwareID -join '|') -ceq 'PRIMARY-A' -and ($row.CompatibleID -join '|') -ceq 'PRIMARY-C' -and $row.HardwareIdSource -eq 'PnP record') ($mode+' usable native lists remain preferred over optional property lists')
        Assert ((Test-IdRawValue $row.HardwareIDPropertyReadings 'ALT-A') -and (Test-IdRawValue $row.HardwareIDPropertyReadings 'ALT-B') -and (Test-IdRawValue $row.CompatibleIDPropertyReadings 'ALT-C')) ($mode+' optional list observations stay inspectable even when the native source is preferred')
        $savedReport=[ordered]@{'Report info'=@{Version='3.62';Computer='TEST';Generated='2026-10-30T12:00:00Z'};'Extended device inventory'=@($mixed.Devices[0],$propertyMixed.Devices[0],$conflicted.Devices[0],$laterInvalid.Devices[0]);'Extended scan info'=@{Captured='2026-10-30T12:00:00Z';Source='Synthetic ID lists';Records=4}}
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic device ID observations' ($savedReport | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ((Test-IdRawValue $saved.'Extended device inventory'[0].RawHardwareID $true) -and (Test-IdRawValue $saved.'Extended device inventory'[0].RawCompatibleID $false) -and (Test-IdRawValue $saved.'Extended device inventory'[1].RawPropertyHardwareID $true) -and (Test-IdRawValue $saved.'Extended device inventory'[1].RawPropertyCompatibleID $false) -and $saved.'Extended device inventory'[1].HardwareID[0] -ceq ' PROP-0001 ') ($mode+' exact identifiers and typed malformed raw values survive saved-snapshot import')
        Assert ($saved.'Extended device inventory'[2].HardwareIDPropertyConflict -eq $true -and $saved.'Extended device inventory'[2].CompatibleIDPropertyConflict -eq $true -and ($saved.'Extended device inventory'[2].HardwareID -join '|') -ceq 'A|B|C' -and $saved.'Extended device inventory'[3].HardwareIDPropertyReadings.Count -eq 3 -and $saved.'Extended device inventory'[3].HardwareIDReadStatus -match '^Invalid') ($mode+' conflict flags and every raw list observation survive saved-snapshot import')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine("All $script:checks device-id-list checks passed under PowerShell $($PSVersionTable.PSVersion).")
