param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
$root=Join-Path $PSScriptRoot ('test-output-managed-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $root 'App & space';$local=Join-Path $root 'Local'
[void][IO.Directory]::CreateDirectory($app)
$env:HWID_SCRIPT=Join-Path $app 'hwid.bat'
$env:LOCALAPPDATA=$local
$portable=Get-ReportLocations -ScriptPath $env:HWID_SCRIPT -LocalRoot $local
Assert ($portable.Primary -eq (Join-Path $app 'HWID-Reports')) 'portable report folders remain unchanged'
[IO.File]::WriteAllText((Join-Path $app 'HWID-SETUP.ini'),'[Installation]')
$managed=Get-ReportLocations -ScriptPath $env:HWID_SCRIPT -LocalRoot $local
Assert ($managed.Primary -eq (Join-Path $local 'HWID Checker\HWID-Reports')) 'machine-wide BAT reports default to per-user local data'
$library=Join-Path $local 'HWID Checker\snapshot-library.json'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $library))
$custom=Join-Path $root 'Existing reports'
[IO.File]::WriteAllText($library,(@{version=1;primary=$custom;folders=@()}|ConvertTo-Json))
Assert ((Get-ReportLocations -ScriptPath $env:HWID_SCRIPT -LocalRoot $local).Primary -eq $custom) 'existing shared report folder selection survives installation'
Assert (Test-CheckerManagedInstall (Join-Path $env:ProgramFiles 'HWID Checker')) 'Program Files remains protected if the marker was deleted'
Assert (-not (Test-CheckerManagedInstall ($env:ProgramFiles+' copy\HWID Checker'))) 'similar folder prefixes do not falsely identify a managed installation'
$updater=Join-Path (Split-Path -Parent $Source) 'Update-HWID.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($updater,[ref]$t,[ref]$e)
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$Mode='Apply';$InstallDirectory=$app;$CurrentVersion='1.4.8';$Component='Package'
$rejected=$false
try{Invoke-HwidUpdate}catch{$rejected=$_.Exception.Message -like '*administrator approval*'}
Assert $rejected 'portable updater rejects machine-wide writes before reading a payload or waiting for the app'
[Console]::WriteLine(('All {0} managed installation checks passed. Synthetic paths only.' -f $checks))
