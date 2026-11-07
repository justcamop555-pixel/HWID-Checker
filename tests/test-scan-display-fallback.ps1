param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$script:checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$ownedConsole=$false;$redirected=$true
$script:paintAttempts=0
$script:lines=New-Object 'System.Collections.Generic.List[string]'
function Write-PnpLine {param($Text,$Color) $script:lines.Add($Text)}
function Write-ScanStatus {param($State,$Text,$Color) $script:paintAttempts++;return $false}
$script:scanProgressState=[pscustomobject]@{Top=0;Width=80}
$script:scanProgressClock=[Diagnostics.Stopwatch]::StartNew()
$script:scanProgressTotal=18;$script:scanProgressFallbackUsed=$false
Update-ScanProgress 7
Assert ($script:paintAttempts -eq 1 -and $script:scanProgressFallbackUsed -and $script:scanProgressState.BoundaryFallback) 'A failed or resized live row switches to boundary progress'
Assert ($script:lines.Count -eq 0) 'Waiting pulses never append progress rows'
Update-ScanProgress 7 -Boundary
Assert ($script:lines.Count -eq 1 -and $script:lines[0] -match '7 of 18') 'A completed section receives a current progress summary'
Update-ScanProgress 7 -Boundary
Update-ScanProgress 7
Assert ($script:lines.Count -eq 1 -and $script:paintAttempts -eq 1) 'Repeated pulses avoid repainting stale coordinates or duplicating a boundary'
Update-ScanProgress 8 -Boundary
Assert ($script:lines.Count -eq 2 -and $script:lines[1] -match '8 of 18') 'Later section boundaries keep progress moving'
$script:scanProgressClock.Stop()
$script:scanProgressState=$null;$script:scanProgressClock=$null;$script:scanProgressTotal=$null
Update-ScanProgress 9 -Boundary
Assert ($script:lines.Count -eq 2) 'Inactive scan progress produces no output'

$report=[ordered]@{'Report info'=[ordered]@{Version='3.85';Computer='SYNTHETIC';Generated='2026-11-06T10:00:00Z'}}
$warnings=New-Object 'System.Collections.Generic.List[string]'
$script:scanQueryWorker=$null
$script:events=New-Object 'System.Collections.Generic.List[string]'
function Reset-UiPage {}
function Start-UiReport {param([switch]$Scanning)}
function Write-Heading {param($Title)}
function Write-PnpValue {param($Label,$Value,$Color) $script:events.Add($Label)}
function Start-ScanLine {param($Prefix) $script:events.Add('pending');return [pscustomobject]@{Left=0;Top=0;Width=80}}
function Complete-ScanLine {
    param($State,$Name,$Text,$Color)
    $script:events.Add($Text)
    if($script:failDisplay){throw 'Synthetic extended display failure'}
}
function Show-ExtendedDeviceReport {$script:events.Add('report')}
function Get-ExtendedDeviceInventory {
    if($script:failCollection){throw [TimeoutException]::new('Synthetic provider timeout')}
    [pscustomobject]@{Devices=@([pscustomobject]@{Name='Synthetic device';DeviceInstanceId='USB\SYNTHETIC';Present=$true;ConfigManagerErrorCode=0});Info=@{Captured='2026-11-06T10:30:00Z';Source='Synthetic';Records=1}}
}
Start-ExtendedDeviceScan
Assert ($report['Report info'].ExtendedStatus -eq 'Refreshed' -and $script:events -contains '[READ] 1 known nodes') 'Successful extended refresh closes its pending row'
Assert ($script:events.IndexOf('[READ] 1 known nodes') -lt $script:events.IndexOf('report')) 'Pending completion precedes the extended report'
$script:events.Clear();$script:failCollection=$true
Start-ExtendedDeviceScan
$completed=@($script:events | Where-Object {$_ -like '[[]NOT READ[]]*'})
Assert ($completed.Count -eq 1 -and $report['Report info'].ExtendedStatus -eq 'Unavailable') 'Failed extended refresh closes the pending row with a read error'
Assert ($script:events.IndexOf($completed[0]) -lt $script:events.IndexOf('EXTENDED-01 / not completed')) 'Failure diagnostics start after the pending row has completed'
$script:events.Clear();$script:failCollection=$false;$script:failDisplay=$true
Start-ExtendedDeviceScan
Assert ($report['Report info'].ExtendedStatus -eq 'Refreshed' -and $report['Report info'].ExtendedProgressWarning -match 'display failure' -and $warnings.Count -eq 0) 'A pending-row display failure preserves accepted scan data with a diagnostic'
$script:failDisplay=$false
Start-ExtendedDeviceScan
Assert (-not $report['Report info'].ExtendedProgressWarning) 'A later successful display clears the obsolete diagnostic'
[Console]::WriteLine("All $script:checks scan display checks passed under PowerShell $($PSVersionTable.PSVersion).")
