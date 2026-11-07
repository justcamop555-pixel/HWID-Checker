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
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Good='Green';Warn='Yellow';Error='Red'}
$root=Join-Path $PSScriptRoot ('test-output-console-update-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $root ("installer's ! & [1] "+[char]0x03a9)
[void][IO.Directory]::CreateDirectory($install)
$env:HWID_SCRIPT=Join-Path $install 'hwid.bat'
$env:LOCALAPPDATA=Join-Path $root 'local'
$paths=Get-CheckerUpdatePaths
Assert ((Get-CheckerPackageVersion) -ceq '1.4.1' -and $paths.InstallDirectory -ceq $install) 'BAT compares package 1.4.1 and preserves literal install paths'
$hash=[Security.Cryptography.SHA256]::Create()
try{$key=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($install.ToUpperInvariant())))).Replace('-','').Substring(0,16).ToLowerInvariant()}finally{$hash.Dispose()}
Assert ($paths.ResultPath -ceq (Join-Path $env:LOCALAPPDATA ('HWID Checker\Updates\'+$key+'-bat\result.json'))) 'The cache has the agreed install-bound component key'
$driveRoot=Get-CheckerUpdatePaths -ScriptPath 'C:\hwid.bat'
Assert ($driveRoot.InstallDirectory -ceq 'C:\' -and $driveRoot.UpdaterPath -ceq 'C:\Update-HWID.ps1') 'Drive-root installs retain absolute helper paths'
Assert ((Get-CheckerUpdatePreferences $paths).Enabled -and -not [IO.File]::Exists($paths.PreferencesPath)) 'Absent preferences enable automatic updates without creating files'
Set-CheckerAutomaticUpdates $paths $false
Assert (-not (Get-CheckerUpdatePreferences $paths).Enabled) 'Explicit automatic opt-out persists'
Set-CheckerAutomaticUpdates $paths $true
Assert ((Get-CheckerUpdatePreferences $paths).Enabled) 'Automatic setting supports atomic replacement'
[IO.File]::WriteAllText($paths.PreferencesPath,'{"automaticUpdates":"false"}',[Text.UTF8Encoding]::new($true,$true))
$p=Get-CheckerUpdatePreferences $paths
Assert (-not $p.Enabled -and $p.Warning) 'Invalid preferences suspend automatic behavior with a recovery message'
Set-CheckerAutomaticUpdates $paths $true
[IO.File]::WriteAllText($paths.UpdaterPath,'# Synthetic test helper.')
$stage=Join-Path $paths.Directory 'stage-synthetic'
[void][IO.Directory]::CreateDirectory($stage)
function Set-Result($State,$Version='1.5.0'){
    [IO.File]::WriteAllText($paths.ResultPath,(@{state=$State;message='Synthetic '+$State;latestVersion=$Version;stageDirectory=$stage;batVersion='3.86'} | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
$script:launches=New-Object 'System.Collections.Generic.List[object]'
$realProcess=(Get-Item Function:Start-CheckerUpdateProcess).ScriptBlock
function Start-CheckerUpdateProcess {param($Paths,$Mode,$HelperPath=$Paths.UpdaterPath,$StageDirectory,$CurrentVersion=(Get-CheckerPackageVersion)) $script:launches.Add([pscustomobject]@{Mode=$Mode;Helper=$HelperPath;Stage=$StageDirectory;CurrentVersion=$CurrentVersion})}
$ownedConsole=$true;$redirected=$false
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 0) 'HWID_NO_UPDATE suppresses automatic preparation'
$env:HWID_NO_UPDATE=$null
$ownedConsole=$false;Start-CheckerAutomaticUpdate
$ownedConsole=$true;$redirected=$true;Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 0) 'Automatic preparation skips redirected and current-window sessions'
$redirected=$false;Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 1 -and $script:launches[0].Mode -eq 'Prepare') 'Interactive owned sessions start background preparation'
Set-Result 'current' '1.1.0'
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 1) 'Current-result cache avoids repeated checks for 24 hours'
[IO.File]::SetLastWriteTimeUtc($paths.ResultPath,[datetime]::UtcNow.AddHours(-25))
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 2) 'An expired current result permits preparation'
Set-Result 'error'
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 2) 'A recent failure backs off for an hour'
[IO.File]::SetLastWriteTimeUtc($paths.ResultPath,[datetime]::UtcNow.AddHours(-2))
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq 3) 'An expired error can recover on a later launch'
Set-Result 'ready' '1.1.0'
Assert ((Read-CheckerUpdateResult $paths).state -ceq 'current') 'An older prepared package cannot become a downgrade'
Start-CheckerExitUpdate
Assert ($script:launches.Count -eq 3) 'Exit never schedules an older prepared package'
Set-Result 'ready'
Set-CheckerAutomaticUpdates $paths $false
Start-CheckerExitUpdate
Assert ($script:launches.Count -eq 3) 'Automatic opt-out prevents installation on exit'
Set-CheckerAutomaticUpdates $paths $true
Start-CheckerExitUpdate
$scheduled=$script:launches[-1]
Assert ($scheduled.Mode -eq 'Apply' -and $scheduled.Stage -eq $stage -and $scheduled.Helper -ne $paths.UpdaterPath -and [IO.File]::Exists($scheduled.Helper)) 'Normal exit copies a helper and binds it to the prepared stage'
Assert ([IO.File]::ReadAllText($scheduled.Helper) -ceq [IO.File]::ReadAllText($paths.UpdaterPath)) 'Copied helper content remains exact'
$transaction=Join-Path $install ('.hwid-update-'+('a'*32))
[void][IO.Directory]::CreateDirectory($transaction)
[IO.File]::WriteAllText((Join-Path $transaction 'transaction.json'),'{"version":"1.4.1"}')
$repair=@{state='ready';message='Synthetic interrupted update';latestVersion='1.4.1';currentVersion='1.4.0';installDirectory=$install;component='Bat';stageDirectory=$stage}
[IO.File]::WriteAllText($paths.ResultPath,($repair | ConvertTo-Json -Compress))
$cached=Read-CheckerUpdateResult $paths
Assert ($cached.state -ceq 'ready' -and $cached.repair) 'An unfinished matching journal permits exact same-package repair'
[IO.File]::SetLastWriteTimeUtc($paths.ResultPath,[datetime]::UtcNow.AddHours(-25))
$before=$script:launches.Count
Start-CheckerAutomaticUpdate
Assert ($script:launches.Count -eq $before) 'Automatic preparation keeps an interrupted repair cache intact'
Start-CheckerExitUpdate
Assert ($script:launches.Count -eq $before+1 -and $script:launches[-1].CurrentVersion -ceq '1.4.0') 'Repair Apply receives the original current-version binding'
$before=$script:launches.Count
$notice=Start-CheckerUpdateOperation -Mode Check -Manual
Assert ($script:launches.Count -eq $before -and $notice -match 'interrupted update' -and (Read-CheckerUpdateResult $paths).repair) 'A manual version check also preserves the interrupted update for recovery'
[IO.File]::WriteAllText((Join-Path $transaction 'completed.json'),'{}')
Assert ((Read-CheckerUpdateResult $paths).state -ceq 'current') 'A completed transaction never authorizes equal-version installation'
Set-Result 'ready'
$report=[ordered]@{'Report info'=@{ScanNumber=1;Generated='2026-11-06T10:00:00Z'}}
$env:HWID_NO_ANIMATION='1'
$script:choices=New-Object 'System.Collections.Generic.Queue[string]'
foreach($choice in @('5','3','4','0','0')){$script:choices.Enqueue($choice)}
$originalMenu=(Get-Item Function:Read-MenuChoice).ScriptBlock
function Read-MenuChoice {param($Maximum) $script:choices.Dequeue()}
$returned=Show-ScanTools
Assert ($returned -eq $false -and $script:choices.Count -eq 0) 'Update controls return through the tools menu without recursive navigation'
Assert (-not (Get-CheckerUpdatePreferences $paths).Enabled) 'Automatic update toggle works through the actual console submenu'
Set-Item Function:Read-MenuChoice -Value $originalMenu
Set-CheckerAutomaticUpdates $paths $true
$before=$script:launches.Count
$notice=Start-CheckerUpdateOperation -Mode Check -Manual
Assert ($script:launches.Count -eq $before+1 -and $script:launches[-1].Mode -eq 'Check' -and $notice -match 'version check') 'Manual checks bypass automatic cache timing'
$script:checkerUpdateProcess=[pscustomobject]@{HasExited=$false}
$notice=Start-CheckerUpdateOperation -Mode Prepare -Manual
Assert ($script:launches.Count -eq $before+1 -and $notice -match 'already running') 'An overlapping action preserves the active helper'
$script:checkerUpdateProcess=$null
[IO.File]::Delete($paths.UpdaterPath)
$failure=$null
try{Start-CheckerUpdateOperation -Mode Prepare -Manual}catch{$failure=$_.Exception.Message}
Assert ($failure -match 'Keep Update-HWID.ps1') 'Missing updater gets an actionable message'
$helperSource=@(
    'param($Mode,$InstallDirectory,$CurrentVersion,$Component,$ResultPath,$StageDirectory,[int]$WaitProcessId,[long]$WaitProcessStartTicks)',
    '$packet=@{state="current";message="Synthetic";mode=$Mode;install=$InstallDirectory;version=$CurrentVersion;component=$Component;stage=$StageDirectory;waitId=$WaitProcessId;waitTicks=$WaitProcessStartTicks}',
    '[IO.File]::WriteAllText($ResultPath,($packet | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))',
    'Write-Output "Synthetic output is suppressed."'
) -join [Environment]::NewLine
[IO.File]::WriteAllText($paths.UpdaterPath,$helperSource,[Text.UTF8Encoding]::new($false))
Set-Item Function:Start-CheckerUpdateProcess -Value $realProcess
Start-CheckerUpdateProcess $paths 'Check'
Assert ($script:checkerUpdateProcess.WaitForExit(10000) -and $script:checkerUpdateProcess.ExitCode -eq 0) 'Hidden same-runtime helper finishes with output suppressed'
$packet=Convert-ReportJson ([IO.File]::ReadAllText($paths.ResultPath))
Assert ($packet.install -ceq $install -and $packet.version -ceq '1.4.1' -and $packet.component -ceq 'Bat') 'Encoded arguments preserve Unicode and shell metacharacters'
$script:checkerUpdateProcess.Dispose();$script:checkerUpdateProcess=$null
Start-CheckerUpdateProcess $paths 'Apply' $paths.UpdaterPath $stage
Assert ($script:checkerUpdateProcess.WaitForExit(10000) -and $script:checkerUpdateProcess.ExitCode -eq 0) 'Synthetic Apply finishes without installing anything'
$packet=Convert-ReportJson ([IO.File]::ReadAllText($paths.ResultPath))
Assert ($packet.waitId -eq $PID -and $packet.waitTicks -gt 0 -and $packet.stage -ceq $stage) 'Apply transport carries the exact waiting process identity and stage'
$script:checkerUpdateProcess.Dispose();$script:checkerUpdateProcess=$null
Assert ($body.Contains("Wait-ScanContinue 'main menu'"+[char]13+[char]10+'Start-CheckerAutomaticUpdate') -and $body.Contains("'0' { Show-UiTransition 'Exit';Start-CheckerExitUpdate;return }")) 'Preparation follows scan continuation and apply belongs to normal Exit'
$env:HWID_NO_UPDATE='1'
[Console]::WriteLine("All $script:checks console update checks passed under PowerShell $($PSVersionTable.PSVersion).")
