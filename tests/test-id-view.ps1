$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=17
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$script:checks=0;$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
$report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanStep=0;$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
$cases=@(
    @{Name='Serial array';Query={[pscustomobject]@{SerialNumber=@('A','B')}}},
    @{Name='Boolean CPU ID';Query={[pscustomobject]@{ProcessorId=$false}}},
    @{Name='Object UUID';Query={[pscustomobject]@{UUID=[pscustomobject]@{Value='ABC'}}}},
    @{Name='Dictionary key';Query={[pscustomobject]@{DeviceID=@{Value='CPU0'}}}},
    @{Name='Date serial';Query={[pscustomobject]@{SerialNumber=[datetime]'2026-01-01'}}}
)
foreach($mode in @('Direct','Worker')) {
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try {
        foreach($case in $cases) {
            Section 'Probe' $case.Query
            Assert ($report.Probe.FailureCode -eq 'READ-06' -and $script:scanTimings[-1].Results -eq 0 -and -not (Test-SectionReadable $report.Probe)) ($mode+' '+$case.Name+' is an unreadable ID, never an invented found value')
        }
        Section 'Probe' {[pscustomobject]@{SerialNumber='0000123';Index=0;Enabled=$false;HardwareID=@('HID-A','HID-B');Captured=[datetime]'2026-01-02'}}
        Assert ($script:scanTimings[-1].Status -eq 'READ' -and $report.Probe[0].SerialNumber -ceq '0000123' -and $report.Probe[0].Index -eq 0 -and $report.Probe[0].Enabled -eq $false -and $report.Probe[0].HardwareID.Count -eq 2 -and $report.Probe[0].Captured -is [string]) ($mode+' valid serials, disk zero, ordinary booleans, ID lists and dates survive after a malformed scan')
        Section 'Probe' {[pscustomobject]@{Name='Known component';SerialNumber=$null}}
        Assert ($script:scanTimings[-1].Status -eq 'CHECK' -and (Test-SectionReadable $report.Probe)) ($mode+' a missing scalar serial is CHECK rather than invalid scan data')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
$wrapped=@([pscustomobject]@{Value=''} | Select-Object @{n='SerialNumber';e={Convert-MonitorText $null}})[0].SerialNumber
Assert (Test-IdentityFieldValue 'SerialNumber' $wrapped) 'PowerShell-wrapped empty strings remain valid missing scalar values'
Assert (Test-IdentityFieldValue 'SerialNumber' ([guid]'12345678-1234-1234-1234-123456789012')) 'GUID scalar identifier types remain usable'
Assert ((Get-FieldQuality 'MacAddress' '' ([pscustomobject]@{HardwareInterface='false'})) -eq 'Missing' -and (Get-FieldQuality 'PermanentAddress' '' ([pscustomobject]@{HardwareInterface=0})) -eq 'Missing') 'Malformed adapter-type metadata cannot hide missing IDs as not applicable'
$unsafe='SER'+[char]27+'[31m'+[char]8+[char]127+'001'
$safe=Limit-TableText $unsafe 60
Assert ($safe -notmatch '[\x00-\x1f\x7f]' -and $safe -match '001') 'Quick-table values remove terminal control characters without dropping visible serial characters'
$report=[ordered]@{
    'Report info'=@{ScanNumber=3;Generated='2026-10-27T12:00:00Z'}
    'Motherboard'=@{Unavailable='Synthetic denied read'}
    'Chassis'=@([pscustomobject]@{SerialNumber='CH0001'})
    'CPU'=@($null,[pscustomobject]@{DeviceID='CPU0';ProcessorId='MODEL-ID'},[pscustomobject]@{DeviceID='CPU1';ProcessorId='MODEL-ID'})
    'Memory modules'=@([pscustomobject]@{DeviceLocator='A1';SerialNumber='000123'})
    'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber=''})
    'Storage identifiers'=@([pscustomobject]@{Number=0;SerialNumber='DISK-ALT'})
    'Monitors'=@([pscustomobject]@{SerialNumber=$unsafe})
    'Network adapters'=@([pscustomobject]@{Name='Ethernet';MacAddress='001122334455';PermanentAddress='001122334466';HardwareInterface=$true},[pscustomobject]@{Name='Virtual';MacAddress=$null;PermanentAddress=$null;HardwareInterface=$false})
    'Windows Machine GUID'=@([pscustomobject]@{MachineGuid='12345678-1234-1234-1234-123456789012'})
}
$rows=@(Get-QuickIds $report)
Assert (@($rows | Where-Object Label -eq 'Chassis serial').Count -eq 1) 'Quick IDs include the chassis serial'
Assert (@($rows | Where-Object Label -like 'CPU ID*').Count -eq 2 -and @($rows | Where-Object Quality -eq 'Missing').Count -eq 0) 'Null rows cannot create phantom missing IDs or shift component numbering'
Assert (@($rows | Where-Object Value -eq 'MODEL-ID').Count -eq 2) 'Repeated processor model IDs remain separate records instead of being wrongly deduplicated'
Assert (@($rows | Where-Object Label -like 'Net current*').Count -eq 1 -and @($rows | Where-Object Label -like 'Net permanent*').Count -eq 1) 'Current and permanent MAC addresses have distinct labels while absent virtual addresses stay omitted'
Assert (@($rows | Where-Object Value -ceq '000123').Count -eq 1 -and @($rows | Where-Object Value -eq 'DISK-ALT').Count -eq 1) 'Leading-zero memory serials and a single alternate-source disk serial remain intact'
Assert (@($rows | Select-Object -ExpandProperty Group -Unique).Count -eq 5) 'ID rows retain five navigation groups'
$script:rendered.Clear();Show-QuickIds
Assert (($script:rendered -join ' ') -notmatch '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' -and $report.Monitors[0].SerialNumber -ceq $unsafe) 'Rendering cannot inject console controls and leaves raw report identifiers unchanged'
Assert (($script:rendered -join ' ') -match 'NOT READ: Motherboard' -and ($script:rendered -join ' ') -match 'CPU, volume and network IDs are not factory serials') 'Quick view names unreadable sections and explains non-serial identifiers'
$legacy=[ordered]@{'Network adapters'=@([pscustomobject]@{Name='Old NIC';MacAddress='001122334455';HardwareInterface=$true})}
Assert (@(Get-QuickIds $legacy).Count -eq 1) 'Older schemas do not acquire a phantom missing permanent-address row'
$report=[ordered]@{'CPU'=@{Unavailable='Synthetic provider failure'}}
$script:rendered.Clear();Show-QuickIds
Assert (($script:rendered -join ' ') -match 'No IDs available' -and ($script:rendered -join ' ') -match 'NOT READ: CPU') 'An entirely unreadable quick view still identifies the blocked section'
[Console]::WriteLine("All $script:checks ID-view checks passed under PowerShell $($PSVersionTable.PSVersion).")
