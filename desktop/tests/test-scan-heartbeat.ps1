param([string]$Source=(Join-Path $PSScriptRoot '..\engine\DesktopBridge.ps1'))
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$definition=$ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-ScanProgress'},$true)|Select-Object -First 1
if($null -eq $definition){throw 'Bridge progress function was not found.'}
. ([scriptblock]::Create($definition.Extent.Text))
$checks=0
function Assert($value,$message){if(-not $value){throw ('FAILED: '+$message)};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
$script:events=New-Object 'System.Collections.Generic.List[object]'
function Send-DesktopProgress {param($Name,$Completed,$Total,$Status,$Records,$Message,$Seconds) $script:events.Add([pscustomobject]@{Name=$Name;Completed=$Completed;Total=$Total;Status=$Status;Seconds=$Seconds})}
$scanTotal=18;$script:scanStep=2;$script:bridgeCurrentSection='CPU';$script:bridgeProgressStatus='READING'
$script:bridgeSectionClock=[Diagnostics.Stopwatch]::StartNew()
$script:bridgePulseClock=[pscustomobject]@{Elapsed=[TimeSpan]::Zero;Restarts=0}
$script:bridgePulseClock|Add-Member ScriptMethod Restart {$this.Elapsed=[TimeSpan]::Zero;$this.Restarts++}
# The old wall-clock marker deliberately lies in the future. No system clock is changed.
$script:bridgeLastPulse=[datetime]::UtcNow.AddDays(1)
Update-ScanProgress 1
Assert ($events.Count -eq 0) 'waiting feedback is throttled before its interval'
$script:bridgePulseClock.Elapsed=[TimeSpan]::FromSeconds(2)
Update-ScanProgress 1
Assert ($events.Count -eq 1 -and $events[0].Name -eq 'CPU' -and $events[0].Completed -eq 1 -and $events[0].Total -eq 19) 'elapsed-clock feedback preserves the active section and stage counts despite an invalid wall-clock marker'
Assert ($script:bridgePulseClock.Restarts -eq 1 -and $events[0].Seconds -ge 0) 'a sent heartbeat resets its interval and retains elapsed query time'
Update-ScanProgress 1
Assert ($events.Count -eq 1) 'repeated calls cannot flood the progress stream'
$script:bridgeProgressStatus='READ';$script:bridgePulseClock.Elapsed=[TimeSpan]::FromSeconds(5)
Update-ScanProgress 2
Assert ($events.Count -eq 1) 'finished reads do not receive stale waiting messages'
[Console]::WriteLine(('All {0} scan-heartbeat checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
