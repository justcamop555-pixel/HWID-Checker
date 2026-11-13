param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$env:HWID_NO_UPDATE='1';$env:HWID_NO_ANIMATION='1'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$t,[ref]$e)
if($e.Count){throw ($e.Message -join '; ')}
foreach($fn in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
$script:messages=New-Object 'System.Collections.Generic.List[string]'
function Write-PnpValue {param($Label,$Value,$Color) $script:messages.Add($Label+': '+$Value)}
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Good='Green';Warn='Yellow';Error='Red'}
$root=Join-Path $PSScriptRoot ('test-output-restart-'+[guid]::NewGuid().ToString('N'))
$folder=Join-Path $root ("literal ! & [1] %PATH% '"+[char]0x03a9)
[void][IO.Directory]::CreateDirectory($folder)
$scriptPath=Join-Path $folder 'hwid.bat'
$resultPath=Join-Path $root 'child.json'
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$probe=@(
    '$ErrorActionPreference="Stop"',
    '$result=@{script=$env:HWID_SCRIPT;owned=$env:HWID_OWN_CONSOLE;currentWindow=$env:HWID_CURRENT_WINDOW;signal=$env:HWID_STARTUP_SIGNAL;noUpdate=$env:HWID_NO_UPDATE;noAnimation=$env:HWID_NO_ANIMATION;terminal=$env:WT_SESSION;directory=[Environment]::CurrentDirectory}',
    '[IO.File]::WriteAllText($env:HWID_RESTART_TEST_RESULT,($result | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))',
    'if(-not $env:HWID_STARTUP_SIGNAL){throw "Missing restart acknowledgement path"}',
    '[IO.File]::WriteAllText($env:HWID_STARTUP_SIGNAL,"READY",[Text.UTF8Encoding]::new($false))'
) -join [Environment]::NewLine
$prelude=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[0]
$batch=$prelude+[Environment]::NewLine+'# POWERSHELL_START'+[Environment]::NewLine+$probe
if($batch.Contains('function Invoke-HardwareScan')){throw 'The synthetic restart fixture accidentally contains production collection code.'}
[IO.File]::WriteAllText($scriptPath,$batch,[Text.UTF8Encoding]::new($false))
$prior=@{}
foreach($name in @('HWID_SCRIPT','LOCALAPPDATA','HWID_OWN_CONSOLE','HWID_CURRENT_WINDOW','HWID_STARTUP_SIGNAL','WT_SESSION','HWID_RESTART_TEST_RESULT')){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
function Start-Process {
    param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru)
    Microsoft.PowerShell.Management\Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru
}
try {
    $env:HWID_SCRIPT=$scriptPath;$env:LOCALAPPDATA=Join-Path $root 'local'
    $env:HWID_OWN_CONSOLE='1';$env:HWID_CURRENT_WINDOW='--stale-window';$env:HWID_STARTUP_SIGNAL='stale-test-signal';$env:WT_SESSION='stale-test-terminal'
    $env:HWID_RESTART_TEST_RESULT=$resultPath
    $plan=Get-CheckerRestartPlan
    Assert ($plan.FilePath -eq (Join-Path $env:SystemRoot 'System32\conhost.exe') -and $plan.Arguments.Contains('-EncodedCommand ')) 'Restart uses a dedicated native console and an environment-carried CMD path'
    $child=Start-CheckerRestartWindow $scriptPath
    try{Assert ($child.WaitForExit(15000) -and $child.ExitCode -eq 0) 'The actual restart process chain runs a synthetic BAT and exits cleanly'}finally{$child.Dispose()}
    $result=Convert-ReportJson ([IO.File]::ReadAllText($resultPath))
    Assert ($result.script -ceq $scriptPath -and $result.directory -ceq $folder) 'Spaces, percent expressions, ampersands, exclamation marks and Unicode survive native CMD launch literally'
    Assert ($result.owned -ceq '1' -and -not (Test-ReadableLaunchNeeded $false ($result.owned -eq '1') $result.currentWindow) -and ($result.signal -and $result.signal -cne 'stale-test-signal') -and [string]::IsNullOrEmpty($result.terminal)) 'The restarted standalone launcher needs no second console'
    Assert ($result.noUpdate -ceq '1' -and $result.noAnimation -ceq '1') 'The real child inherits update and animation preferences'
    Assert ($env:HWID_CURRENT_WINDOW -ceq '--stale-window' -and $env:HWID_STARTUP_SIGNAL -ceq 'stale-test-signal' -and $env:WT_SESSION -ceq 'stale-test-terminal') 'Successful launch restores the original process environment'
    $failedPath=Join-Path $folder 'missing-ready.bat'
    $readyLine='[IO.File]::WriteAllText($env:HWID_STARTUP_SIGNAL,"READY",[Text.UTF8Encoding]::new($false))'
    if(-not $batch.Contains($readyLine)){throw 'Missing synthetic ready line'}
    [IO.File]::WriteAllText($failedPath,$batch.Replace($readyLine,'[void]0'),[Text.UTF8Encoding]::new($false))
    $ownedConsole=$true;$redirected=$false
    $env:HWID_SCRIPT=$failedPath
    Start-CheckerRestart
    Assert (@($script:messages | Where-Object {$_ -match '^RESTART-03: .*before confirming startup'}).Count -eq 1) 'A real child that exits without READY keeps the original checker open'
    $env:HWID_SCRIPT=$scriptPath
    $savedSystemRoot=$env:SystemRoot
    try {
        $env:SystemRoot=Join-Path $root 'missing-runtime'
        $failure=$null
        try{Get-CheckerRestartPlan | Out-Null}catch{$failure=$_.Exception.Message}
        Assert ($failure -match 'console or Command Prompt is unavailable') 'A missing native console produces a recoverable launcher message'
    }finally{$env:SystemRoot=$savedSystemRoot}
    $ownedConsole=$true;$redirected=$false
    function Start-Process {param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru) throw 'Synthetic restart failure'}
    Start-CheckerRestart
    Assert (@($script:messages | Where-Object {$_ -match '^RESTART-03: .*Synthetic restart failure'}).Count -eq 1) 'Failed launch keeps the current checker open with the original error'
    Assert ($env:HWID_CURRENT_WINDOW -ceq '--stale-window' -and $env:HWID_STARTUP_SIGNAL -ceq 'stale-test-signal' -and $env:WT_SESSION -ceq 'stale-test-terminal') 'Failed launch restores the original process environment too'
    $paths=Get-CheckerUpdatePaths
    [void][IO.Directory]::CreateDirectory($paths.Directory)
    [IO.File]::WriteAllText($paths.ResultPath,(@{state='ready';message='Synthetic prepared update';latestVersion='99.0.0';currentVersion=(Get-CheckerPackageVersion);component='Bat';installDirectory=$paths.InstallDirectory}|ConvertTo-Json -Compress))
    Start-CheckerRestart
    Assert (@($script:messages | Where-Object {$_ -match '^RESTART-02:'}).Count -eq 1) 'A prepared update defers restart to the normal update-aware exit path'
    function Test-CheckerUpdateRunning {return $true}
    Start-CheckerRestart
    Assert (@($script:messages | Where-Object {$_ -match '^RESTART-04:'}).Count -eq 1) 'An in-progress update cannot race a fresh-window restart'
    $restartFunction=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-CheckerRestart'},$false) | Select-Object -First 1
    Assert (-not $restartFunction.Extent.Text.Contains('Start-CheckerExitUpdate')) 'Restart does not schedule installation underneath its replacement console'
    Assert ($body.Contains("'7' {Start-CheckerRestart;return `$true}")) 'Restart failures return through the visible result-page wait instead of disappearing into the main menu'
}finally{
    foreach($name in $prior.Keys){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}
}
[Console]::WriteLine("All $script:checks restart checks passed under PowerShell $($PSVersionTable.PSVersion).")
