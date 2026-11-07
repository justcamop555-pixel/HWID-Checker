param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$groups=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$ownedConsole=$false;$redirected=$true;$scanTotal=18;$display=[pscustomobject]@{Mode='Synthetic reading test'}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
Assert ((Get-FieldLabel Speed 'Memory modules') -match 'raw' -and (Get-FieldLabel Speed 'Memory modules') -notmatch 'MHz') 'Memory Speed is labeled as raw Windows data without an unsupported MHz claim'
Assert ((Get-FieldLabel ConfiguredClockSpeed 'Memory modules') -match 'MHz') 'The documented configured-clock field retains its MHz unit'
Assert ((Format-RecordFieldValue ConfiguredClockSpeed 0 'Memory modules') -eq 'Unknown (Windows reports 0)') 'A zero configured clock means unknown rather than a measured zero-frequency reading'
Assert ((Format-RecordFieldValue ConfiguredClockSpeed '0' 'Memory modules') -match '^Unknown') 'Numeric-string zero uses the same unknown-clock meaning'
Assert ((Format-RecordFieldValue ConfiguredClockSpeed '003200' 'Memory modules') -ceq '003200') 'A positive reported clock keeps its exact string representation'
Assert ((Format-RecordFieldValue ConfiguredClockSpeed $null 'Memory modules') -eq '(not provided)') 'An omitted configured clock remains distinct from reported zero'
Assert ((Format-RecordFieldValue ConfiguredClockSpeed $true 'Memory modules') -match '^Unknown / invalid') 'Boolean clock metadata is not presented as a frequency'
Assert ((Format-RecordFieldValue Speed 0 'Memory modules') -ceq '0' -and (Format-RecordFieldValue ConfiguredClockSpeed 0 'Other section') -ceq '0') 'Unknown-clock formatting does not reinterpret unrelated raw zero values'
$memory=[pscustomobject]@{DeviceLocator='DIMM0';SerialNumber='000123';Speed=3200;ConfiguredClockSpeed=0}
$plain=@(Get-PlainRecords @($memory) 'Memory modules') -join "`n"
Assert ($plain -match 'Memory speed \(Windows-reported raw\): 3200' -and $plain -match 'Configured speed \(MHz\): Unknown \(Windows reports 0\)') 'TXT memory labels and unknown-clock values match the hardware viewer'
$plainNetwork=@(Get-PlainRecords @([pscustomobject]@{Speed=1000000000}) 'Network adapters') -join "`n"
Assert ($plainNetwork -match 'bandwidth \(bits/s\): 1000000000' -and $plainNetwork -notmatch 'MHz') 'TXT raw network Speed fields receive network units through section context'
$script:fields=New-Object 'System.Collections.Generic.List[object]'
function Write-PnpValue {param($Label,$Value,$Color) $script:fields.Add([pscustomobject]@{Label=$Label;Value=$Value;Color=$Color})}
Show-Records @($memory) 'Memory modules'
Assert (@($fields | Where-Object {$_.Label -eq 'Configured speed (MHz)' -and $_.Value -match '^Unknown' -and $_.Color -eq 'Gray'}).Count -eq 1) 'Unknown configured clocks are readable muted metadata rather than a hardware-fault color'
Assert ($memory.Speed -eq 3200 -and $memory.ConfiguredClockSpeed -eq 0 -and $memory.SerialNumber -ceq '000123') 'Reading-friendly formatting never modifies captured clock values or serials'
$cases=@(
    @('CPU','READ',1,'IDs: 1 found'),
    @('BIOS','CHECK',1,'IDs: 1 found, 2 missing, 3 default / compatible read'),
    @('Network adapters','NOT READ',0,'Provider unavailable / Main [4] / READ-03'),
    @('PnP hardware IDs','CHECK',171,'171 instance IDs; 164 with model IDs; 2 review')
)
foreach($width in @(24,60,80,100)){
    $first=if($width -ge 60){$width-35}else{$width-1}
    foreach($case in $cases){
        $lines=@(Get-ScanReadLines $case[0] $case[1] $case[2] $case[3] 1.2 $width $first)
        $joined=($lines -join ' ') -replace '\s+',' '
        Assert ($lines.Count -gt 0 -and $lines[0].Length -le $first -and @($lines | Where-Object {$_.Length -gt $width}).Count -eq 0 -and $joined.Contains($case[3]) -and $joined -match '1\.2s') ($width.ToString()+'-column '+$case[1]+' reading keeps status, timing and complete detail within its line widths')
    }
}
$check=@(Get-ScanReadLines BIOS CHECK 1 'IDs: 0 found, 1 missing, 1 default' 0.1 100 65)
Assert ($check[0] -match '\[CHECK\].*1 record' -and $check[0] -notmatch 'missing' -and ($check[1..($check.Count-1)] -join ' ') -match '1 missing, 1 default') 'CHECK rows separate record/time status from ID review counts'
$pnp=@(Get-ScanReadLines 'PnP hardware IDs' READ 171 '171 instance IDs; 164 with model IDs' 0.4 100 65)
Assert ($pnp.Count -ge 2 -and $pnp[0] -match '171 records' -and ($pnp -join ' ') -match '164 with model IDs') 'Device-record totals remain distinct from model-ID coverage'
$failure=@(Get-ScanReadLines BIOS 'NOT READ' 0 'Provider timed out / Main [4] / READ-02' 20 100 65)
Assert ($failure[0] -match '\[NOT READ\].*no usable data' -and ($failure -join ' ') -notmatch '0 (records|devices)') 'An unread query does not claim that no devices exist'
$read=@(Get-ScanReadLines CPU READ 1 'IDs: 1 found' 0.1 100 65)
Assert ($read.Count -eq 1 -and $read[0] -match 'IDs: 1 found') 'Short successful results remain compact'
$safe=@(Get-ScanReadLines BIOS CHECK 1 ("IDs: 1 found`n"+[char]27+'[31m') 0 24 23)
Assert (@($safe | Where-Object {$_ -match '[\x00-\x1f\x7f]'}).Count -eq 0) 'Detail wrapping strips console-control characters'
$long='ABCDEFGHIJKL0123456789ABCDEFGHIJKL0123456789'
$wrapped=@(Split-ScanReadText $long 12)
Assert ((($wrapped -join '') -replace '\s','') -ceq $long -and @($wrapped | Where-Object {$_.Length -gt 12}).Count -eq 0) 'Long individual tokens wrap without ellipses or lost characters'
Assert ((Get-ScanProgressText 1 18 1.2 96) -match '1\.2s' -and (Get-ScanProgressText 1 18 1.2 60) -match '1\.2s') 'Wide and medium progress displays retain fractional elapsed seconds'
$root=Join-Path $PSScriptRoot ('test-output-scan-reading-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$script:primary=New-Object 'System.Collections.Generic.List[object]';$script:details=New-Object 'System.Collections.Generic.List[string]'
function Start-ScanLine {param($Prefix) [pscustomobject]@{Prefix=$Prefix;Width=100;Left=35}}
function Complete-ScanLine {param($State,$Name,$Text,$Color) if($script:failResult -eq $Name){throw 'Synthetic completion rendering failure'};$script:primary.Add([pscustomobject]@{Name=$Name;Text=$Text;Color=$Color})}
function Write-PnpLine {param($Text,$Color) $script:details.Add([string]$Text)}
$originalSection=(Get-Item Function:Section).ScriptBlock;$originalExtended=(Get-Item Function:Get-ExtendedDeviceInventory).ScriptBlock
foreach($mode in @('Direct','Worker')){
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]';$script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0;$script:scanGroupState=$null;$script:failResult=$null
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try {
        $primary.Clear();$details.Clear()
        Section BIOS {[pscustomobject]@{Name='Synthetic BIOS';SerialNumber=''}}
        Assert ($primary[-1].Text -match '\[CHECK\].*1 record' -and ($details -join ' ') -match 'IDs: 0 found, 1 missing') ($mode+' real section rendering uses separate CHECK detail lines')
        $script:failResult='CPU'
        Section CPU {[pscustomobject]@{Name='Synthetic CPU';DeviceID='CPU0';ProcessorId='CPU-0001'}}
        Assert ($scanTimings[-1].Status -eq 'READ' -and $scanTimings[-1].Results -eq 1 -and $report.CPU[0].ProcessorId -ceq 'CPU-0001') ($mode+' result-rendering failure cannot discard usable hardware data')
        Assert ($scanTimings[-1].ProgressWarning -match 'completion rendering') ($mode+' completion-rendering failures are retained as display diagnostics')
        $script:failResult=$null;$details.Clear()
        Section 'Network adapters' {throw [UnauthorizedAccessException]::new('Synthetic provider blocked')}
        Assert ($primary[-1].Text -match '\[NOT READ\]' -and ($details -join ' ') -match 'READ-01' -and $report['Network adapters'].FailureCode -eq 'READ-01') ($mode+' read errors retain their typed reason and next-step code')
        Section 'Memory modules' {[pscustomobject]@{DeviceLocator='DIMM0';SerialNumber='000123';Speed=3200;ConfiguredClockSpeed=0}}
        Assert ($report['Memory modules'][0].ConfiguredClockSpeed -eq 0 -and $report['Memory modules'][0].Speed -eq 3200) ($mode+' scanner captures original memory values despite display interpretation')
        $report['Report info']=@{Version='3.74';Computer='SYNTHETIC';Generated='2026-10-31T12:00:00Z'};$report['Scan timing']=@($scanTimings.ToArray())
        $stem=Join-Path $root $mode;Write-ReportPair $stem 'Synthetic readable scan' ($report | ConvertTo-Json -Depth 12)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.'Memory modules'[0].ConfiguredClockSpeed -eq 0 -and $saved.'Memory modules'[0].Speed -eq 3200 -and $saved.'Memory modules'[0].SerialNumber -ceq '000123') ($mode+' JSON retains exact raw memory fields and leading-zero serials')
        Assert ($saved.'Scan timing'[1].ProgressWarning -match 'completion rendering') ($mode+' saved timing keeps completion-rendering diagnostics')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' reading changes do not manufacture ID comparison changes')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
    function Section {param($Name,$Query) $script:scanStep++;$report[$Name]=@([pscustomobject]@{Name='Synthetic component';SerialNumber='000123'});$script:scanTimings.Add([pscustomobject]@{Section=$Name;Status='READ';Results=1;Recoveries=@();ProgressWarning=$null})}
    function Get-ExtendedDeviceInventory {[pscustomobject]@{Devices=@([pscustomobject]@{Name='Synthetic device';DeviceInstanceId='USB\SYNTHETIC';PNPClass='USB';Present=$true;ConfigManagerErrorCode=0});Info=@{Captured='2026-10-31T12:00:00Z';Source='Synthetic';Records=1}}}
    try {
        $script:failResult='Extended catalog'
        $snapshot=Invoke-HardwareScan 1 -UseWorker ($mode -eq 'Worker') -IncludeExtended $true
        Assert ($snapshot.Inventory['Report info'].ExtendedStatus -eq 'Refreshed' -and $snapshot.Inventory['Extended scan info'].ProgressWarning -match 'completion rendering') ($mode+' catalog completion-rendering failures remain separate from successful collection')
    }finally{Set-Item Function:Section -Value $originalSection;Set-Item Function:Get-ExtendedDeviceInventory -Value $originalExtended;$script:failResult=$null}
}
[Console]::WriteLine("All $checks scan-reading checks passed under PowerShell $($PSVersionTable.PSVersion).")
