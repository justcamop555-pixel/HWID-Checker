$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$raw=[IO.File]::ReadAllText((Join-Path $repo 'hwid.bat'))
$parts=$raw -split '(?m)^# POWERSHELL_START\r?$',2;$header=$parts[0];$body=$parts[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$functions=@{}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){$functions[$definition.Name]=$definition.Extent.Text;. ([scriptblock]::Create($definition.Extent.Text))}
$root=Join-Path $PSScriptRoot ("test-output-startup ! & ' "+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
function Run-Child($Executable,$Arguments,$Environment) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable;$start.Arguments=$Arguments;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.EnvironmentVariables['HWID_OWN_CONSOLE']=''
    foreach($key in @($Environment.Keys)){$start.EnvironmentVariables[$key]=[string]$Environment[$key]}
    $child=[Diagnostics.Process]::Start($start);$child.StandardInput.Close()
    $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(25000)){$child.Kill();throw 'Startup/recovery fixture exceeded 25 seconds.'}
    $result=[pscustomobject]@{Code=$child.ExitCode;Output=($stdout.Result+$stderr.Result)};$child.Dispose();return $result
}
function Make-Fixture($Name,$Text) {
    $folder=Join-Path $root $Name;[void][IO.Directory]::CreateDirectory($folder);$path=Join-Path $folder 'hwid.bat'
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false));return $path
}
$cmd=Join-Path $env:SystemRoot 'System32\cmd.exe'
$winps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pwsh=if($PSVersionTable.PSVersion.Major -ge 7){[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName}else{(Get-Command pwsh.exe -ErrorAction Stop).Source}
$marker=[Environment]::NewLine+'# POWERSHELL_START'+[Environment]::NewLine
$normal=Make-Fixture 'normal' ($header+$marker+'Write-Output "FIXTURE_OK"')
$result=Run-Child $cmd ('/d /c ""'+$normal+'""') @{}
Assert ($result.Code -eq 0 -and $result.Output -match 'FIXTURE_OK') 'The actual CMD bootstrap still launches from a shell-punctuation path'
Assert ($result.Output -match '(?s)\[1/3\].*Preparing.*\[2/3\].*PowerShell.*\[3/3\].*Starting.*FIXTURE_OK') 'CMD preparation stages are visible in execution order before the embedded body'
Assert ($result.Output -notmatch 'START-0[12]|CRASH-01') 'A successful startup is not labeled as a crash'
$empty=Make-Fixture 'empty' ($header+$marker+'  ')
$result=Run-Child $cmd ('/d /c ""'+$empty+'""') @{}
Assert ($result.Code -eq 1 -and $result.Output -match 'START-01.*missing or incomplete') 'An empty embedded body is rejected instead of exiting successfully'
Assert ($result.Output -match 'START-02.*exit code 1') 'CMD preserves and explains the failed startup exit code'
$missing=Make-Fixture 'missing-marker' $header
$result=Run-Child $cmd ('/d /c ""'+$missing+'""') @{}
Assert ($result.Code -eq 1 -and $result.Output -match 'missing or incomplete') 'A missing body marker receives a specific incomplete-file error'
$broken=Make-Fixture 'parse-error' ($header+$marker+'function Invalid( @{')
$result=Run-Child $cmd ('/d /c ""'+$broken+'""') @{}
Assert ($result.Code -eq 1 -and $result.Output -match 'START-01' -and $result.Output -notmatch 'FIXTURE_OK') 'A body parse failure remains visible and never runs the fixture'
$nonzero=Make-Fixture 'engine-exit' ($header+$marker+'exit 23')
$result=Run-Child $cmd ('/d /c ""'+$nonzero+'""') @{}
Assert ($result.Code -eq 23 -and $result.Output -match 'START-02.*23') 'Unexpected nonzero engine termination is not reset to a successful exit'
foreach($engine in @($winps,$pwsh)){
    $plan=Get-ReadableLaunchPlan $engine
    foreach($case in @(@($normal,0,'FIXTURE_OK'),@($empty,1,'START-01.*missing or incomplete'),@($missing,1,'START-01.*missing or incomplete'),@($broken,1,'START-01'))){
        $result=Run-Child $engine ('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$plan.EncodedLoader) @{HWID_SCRIPT=$case[0]}
        Assert ($result.Code -eq $case[1] -and $result.Output -match $case[2]) (([IO.Path]::GetFileName($engine))+' dedicated-window loader validates '+(Split-Path (Split-Path $case[0] -Parent) -Leaf)+' without hanging on redirected input')
    }
    $loaderFolder=Join-Path $root ('loader-'+[IO.Path]::GetFileNameWithoutExtension($engine));[void][IO.Directory]::CreateDirectory($loaderFolder)
    $loaderPath=Join-Path $loaderFolder 'Start-HWID.ps1';Copy-Item -LiteralPath (Join-Path $repo 'Start-HWID.ps1') -Destination $loaderPath
    foreach($case in @(@(('# POWERSHELL_START'+[Environment]::NewLine+'Write-Output "LOADER_OK"'),0,'LOADER_OK'),@(('# POWERSHELL_START'+[Environment]::NewLine+' '),1,'COMPAT-03.*incomplete'),@('Missing marker',1,'COMPAT-03.*incomplete'))){
        [IO.File]::WriteAllText((Join-Path $loaderFolder 'hwid.bat'),$case[0],[Text.UTF8Encoding]::new($false))
        $result=Run-Child $engine ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$loaderPath+'" -CurrentWindow') @{}
        Assert ($result.Code -eq $case[1] -and $result.Output -match $case[2] -and $result.Output -match '\[START\] Preparing') (([IO.Path]::GetFileName($engine))+' PowerShell-only loader validates its companion and shows preparation')
    }
}
$palette=@{Error='Red'};$ownedConsole=$false;$redirected=$true
$report=[ordered]@{'Report info'=@{ScanNumber=7};CPU=@([pscustomobject]@{ProcessorId='0000123'})}
$kept=$report;$savedWarnings=New-Object 'System.Collections.Generic.List[string]';$savedWarnings.Add('Existing warning');$warnings=$savedWarnings
$script:disposeCalls=0;$worker=New-Object psobject
$worker | Add-Member ScriptMethod Dispose {$script:disposeCalls++;throw 'Synthetic dispose failure'}
$script:scanQueryWorker=$worker;$clock=[Diagnostics.Stopwatch]::StartNew();$script:scanProgressClock=$clock
$script:scanProgressState=@{Top=1};$script:scanProgressTotal=18;$script:scanViewState=@{FollowLatest=$true};$script:reportBookmarks=@{'1'=4}
$script:rendered=New-Object 'System.Collections.Generic.List[string]'
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([string]$Object)}
Show-CheckerFailure ([Exception]::new("Synthetic`r`nerror$([char]27)")) -Phase "Report`nview"
Assert ($script:disposeCalls -eq 1 -and $null -eq $script:scanQueryWorker -and -not $clock.IsRunning -and $null -eq $script:scanProgressClock) 'Recovery disposes a worker and stops its clock even if disposal itself throws'
Assert ($null -eq $script:scanProgressState -and $null -eq $script:scanProgressTotal -and $null -eq $script:scanViewState -and $script:reportBookmarks.Count -eq 0) 'Recovery clears live display/input state and stale bookmarks'
Assert ([object]::ReferenceEquals($report,$kept) -and $report.CPU[0].ProcessorId -ceq '0000123' -and [object]::ReferenceEquals($warnings,$savedWarnings)) 'Recovery preserves the active inventory, exact identifiers and existing warnings'
Assert ($rendered.Count -eq 5 -and ($rendered -join ' ') -match '\[UI-01\].*During: Report view.*current scan is retained') 'Recoverable errors use a concise action-specific message'
Assert (@($rendered | Where-Object {$_ -match '[\x00-\x1f\x7f]'}).Count -eq 0) 'Error and phase text cannot insert control characters into the console'
$rendered.Clear();Show-CheckerFailure ([Exception]::new(('x'*1000))) -Phase 'Test' -Fatal
$detail=@($rendered | Where-Object {$_ -like 'Detail:*'})[0]
Assert ($detail.Length -le 328 -and $detail.EndsWith('...') -and ($rendered -join ' ') -match '\[CRASH-01\]') 'Fatal diagnostics are bounded and use a distinct error code'
$helpers=$functions['Restore-CheckerOperation']+[Environment]::NewLine+$functions['Show-CheckerFailure']
$trapDefinition=$ast.FindAll({param($n) $n -is [Management.Automation.Language.TrapStatementAst]},$false) | Select-Object -First 1
$trapText=$trapDefinition.Extent.Text
$fatalBody='$ErrorActionPreference="Stop";'+[Environment]::NewLine+$helpers+[Environment]::NewLine+$trapText+[Environment]::NewLine+'$script:checkerPhase="Initial hardware scan";throw "Synthetic fatal startup failure"'
$fatal=Make-Fixture 'fatal' ($header+$marker+$fatalBody)
$result=Run-Child $cmd ('/d /c ""'+$fatal+'""') @{}
Assert ($result.Code -eq 1 -and $result.Output -match 'CRASH-01' -and $result.Output -match 'During: Initial hardware scan') 'An uncaught application error reports its phase and exits nonzero'
Assert ($result.Output -notmatch 'START-01' -and ([regex]::Matches($result.Output,'CRASH-01')).Count -eq 1) 'An application crash is not printed twice as a startup failure'
$loop=$ast.FindAll({param($n) $n -is [Management.Automation.Language.WhileStatementAst] -and $n.Label -eq 'MainMenu'},$false) | Select-Object -First 1
if($null -eq $loop){throw 'Could not locate the actual main menu loop.'}
$menuHarness=@'
$script:report=[ordered]@{CPU=@{ProcessorId='0000123'}};$script:before=$script:report;$script:visits=0;$script:pauses=0;$script:reads=0
function Show-ControlDeck {$script:visits++}
function Read-MenuChoice {$script:reads++;if($script:reads -eq 1){return '5'};return '0'}
function Get-MenuDestination {param($Choice) return 'Fixture report'}
function Show-UiTransition {param($Direction,$Destination)}
function Reset-UiPage {}
function Start-UiReport {}
function Show-FullReport {throw 'Synthetic report render failure'}
function Wait-UiPage {$script:pauses++}
& {
__LOOP__
}
Write-Output ('MENU_VISITS='+$script:visits+';PAUSES='+$script:pauses+';SAME='+[object]::ReferenceEquals($script:before,$script:report)+';ID='+$script:report.CPU.ProcessorId)
'@
$menuBody='$ErrorActionPreference="Stop";'+[Environment]::NewLine+$helpers+[Environment]::NewLine+$trapText+[Environment]::NewLine+$menuHarness.Replace('__LOOP__',$loop.Extent.Text)
$menu=Make-Fixture 'menu-recovery' ($header+$marker+$menuBody)
foreach($engine in @($winps,$pwsh)){
    $result=Run-Child $engine ('-NoLogo -NoProfile -Command "& ([scriptblock]::Create(([IO.File]::ReadAllText($env:HWID_SCRIPT) -split ''(?m)^# POWERSHELL_START\r?$'',2)[1]))"') @{HWID_SCRIPT=$menu}
    Assert ($result.Code -eq 0 -and $result.Output -match 'UI-01' -and $result.Output -match 'MENU_VISITS=2;PAUSES=1;SAME=True;ID=0000123') (([IO.Path]::GetFileName($engine))+' actual menu loop recovers from a page failure without rescanning or replacing the snapshot')
    Assert ($result.Output -notmatch 'CRASH-01|START-01') (([IO.Path]::GetFileName($engine))+' recovered actions do not become fatal startup errors')
}
$fatalMenu=$menuBody.Replace('function Show-ControlDeck {$script:visits++}','function Show-ControlDeck {throw "Synthetic menu failure"}')
$fatalMenuFile=Make-Fixture 'fatal-menu' ($header+$marker+$fatalMenu)
$result=Run-Child $cmd ('/d /c ""'+$fatalMenuFile+'""') @{}
Assert ($result.Code -eq 1 -and $result.Output -match 'CRASH-01' -and $result.Output -match 'During: Main menu') 'A broken menu stops visibly rather than entering an automatic recovery loop'
[Console]::WriteLine("All $checks startup-recovery checks passed under PowerShell $($PSVersionTable.PSVersion).")
