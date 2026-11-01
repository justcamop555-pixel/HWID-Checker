param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText($Source);$parts=$raw -split '(?m)^# POWERSHELL_START\r?$',2
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($parts[1],[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$definitions=@{}
foreach($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){$definitions[$fn.Name]=$fn.Extent.Text;. ([scriptblock]::Create($fn.Extent.Text))}
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;[Console]::WriteLine('PASS: '+$Message)}
$root=Join-Path $PSScriptRoot ("test-output-startup-handoff ! & ' "+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
function Make-Fixture($Name,$Body){$folder=Join-Path $root $Name;[void][IO.Directory]::CreateDirectory($folder);$path=Join-Path $folder 'hwid.bat';[IO.File]::WriteAllText($path,($parts[0]+"`r`n# POWERSHELL_START`r`n"+$Body),[Text.UTF8Encoding]::new($false));return $path}
function Run-Cmd($Path,$Extensions='on',$Shadow=''){
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe';$start.Arguments='/d /e:'+$Extensions+' /c ""'+$Path+'""'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.EnvironmentVariables['ERRORLEVEL']=$Shadow
    $child=[Diagnostics.Process]::Start($start);$child.StandardInput.Close();$out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(15000)){$child.Kill();throw 'CMD handoff fixture exceeded 15 seconds.'}
    $result=[pscustomobject]@{Code=$child.ExitCode;Output=$out.Result+$err.Result};$child.Dispose();return $result
}
$normal=Make-Fixture normal 'Write-Output "HANDOFF_BODY_OK"'
$result=Run-Cmd $normal on 23
Assert ($result.Code -eq 0 -and $result.Output -match 'HANDOFF_BODY_OK' -and $result.Output -notmatch 'COMPAT-01|START-02') 'An inherited ERRORLEVEL variable cannot manufacture a runtime or launch failure'
$result=Run-Cmd $normal off ''
Assert ($result.Code -eq 0 -and $result.Output -match 'HANDOFF_BODY_OK') 'CMD command extensions disabled by the caller do not break BAT startup'
$nonzero=Make-Fixture nonzero 'exit 23'
$result=Run-Cmd $nonzero off 0
Assert ($result.Code -eq 23 -and $result.Output -match 'START-02.*23') 'Actual nonzero checker exits remain visible despite an inherited zero ERRORLEVEL'
$probe=@($parts[0] -split '\r?\n' | Where-Object {$_ -like '"%~1" *'})[0]
$blocked=Make-Fixture blocked 'THIS MUST NOT PARSE @('
$blockedText=[IO.File]::ReadAllText($blocked).Replace($probe,'"%~1" -NoProfile -Command "exit 13" >nul 2>nul');[IO.File]::WriteAllText($blocked,$blockedText,[Text.UTF8Encoding]::new($false))
$result=Run-Cmd $blocked on 0
Assert ($result.Code -eq 13 -and $result.Output -match 'COMPAT-02') 'Clearing the shadow variable preserves genuine restricted-runtime blocking'
$script:messages=New-Object 'System.Collections.Generic.List[string]'
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:messages.Add([string]$Object)}
# Start real isolated PowerShell children without opening visible desktop windows.
function Start-Process {
    param($FilePath,$ArgumentList,$WorkingDirectory,[switch]$PassThru)
    if($script:failStart){throw 'Synthetic process start failure'}
    $plan=Get-ReadableLaunchPlan $engine
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$engine;$start.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$plan.EncodedLoader
    $start.WorkingDirectory=$WorkingDirectory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $script:lastSignal=$env:HWID_STARTUP_SIGNAL
    $child=[Diagnostics.Process]::Start($start);$child.StandardInput.Close()
    $script:childOutput=$child.StandardOutput.ReadToEndAsync();$script:childError=$child.StandardError.ReadToEndAsync();$script:lastChildId=$child.Id;$script:lastChildStart=$child.StartTime
    return $child
}
$priorPath=$env:HWID_SCRIPT;$priorSignal=$env:HWID_STARTUP_SIGNAL
try {
    $env:HWID_STARTUP_SIGNAL='PARENT_SIGNAL_SENTINEL'
    $delayed=Make-Fixture delayed 'Start-Sleep -Milliseconds 1100;throw "Synthetic delayed startup failure"'
    $env:HWID_SCRIPT=$delayed;$clock=[Diagnostics.Stopwatch]::StartNew()
    $opened=Start-ReadableConsole $delayed $false $false ''
    Assert (-not $opened -and $clock.ElapsedMilliseconds -ge 900) 'A failure after the old 700ms handoff window returns to the original console'
    Assert (($messages -join ' ') -match 'START-03.*Synthetic delayed startup failure.*Continuing in this window') 'The original window receives the child startup failure detail'
    Assert ($env:HWID_STARTUP_SIGNAL -ceq 'PARENT_SIGNAL_SENTINEL' -and -not (Test-Path -LiteralPath $lastSignal)) 'Handoff restores the parent environment and removes its temporary signal file'
    $earlyExit=Make-Fixture early-exit 'Start-Sleep -Milliseconds 1100;exit 0'
    $env:HWID_SCRIPT=$earlyExit;$messages.Clear()
    Assert (-not (Start-ReadableConsole $earlyExit $false $false '')) 'An unconfirmed early zero exit cannot silently close the original window'
    Assert (($messages -join ' ') -match 'code 0.*Continuing in this window') 'An early zero exit has a visible startup diagnostic'
    $complete=Make-Fixture complete 'Write-Output "COMPLETED_BODY"'
    $env:HWID_SCRIPT=$complete
    Assert (Start-ReadableConsole $complete $false $false '') 'A normally completed child is distinguished from an unconfirmed exit'
    Assert (($script:childOutput.Result+$script:childError.Result) -match 'COMPLETED_BODY') 'Completion comes from the actual isolated child loader'
    $ready=Make-Fixture ready ($definitions['Set-CheckerStartupStatus']+"`r`n"+'[void](Set-CheckerStartupStatus "READY");Start-Sleep -Milliseconds 600;Write-Output "READY_BODY"')
    $env:HWID_SCRIPT=$ready;$messages.Clear()
    Assert (Start-ReadableConsole $ready $false $false '') 'An explicit ready signal allows the original launcher to finish'
    Assert (-not (Test-Path -LiteralPath $lastSignal) -and $env:HWID_STARTUP_SIGNAL -ceq 'PARENT_SIGNAL_SENTINEL') 'Successful readiness also cleans its signal and restores inherited state'
    Assert (($script:childOutput.Result+$script:childError.Result) -match 'READY_BODY' -and ($messages -join ' ') -notmatch 'START-03') 'A ready child keeps running after confirmation without a false failure'
    $missing=Make-Fixture missing ' '
    $env:HWID_SCRIPT=$missing;$messages.Clear()
    Assert (-not (Start-ReadableConsole $missing $false $false '') -and ($messages -join ' ') -match 'missing or incomplete') 'An incomplete BAT body is reported back before the new window disappears'
    $broken=Make-Fixture broken 'function Invalid( @{'
    $env:HWID_SCRIPT=$broken;$messages.Clear()
    Assert (-not (Start-ReadableConsole $broken $false $false '') -and ($messages -join ' ') -match 'START-03') 'A parser failure in the new window triggers current-window fallback'
    $trap=$ast.FindAll({param($n) $n -is [Management.Automation.Language.TrapStatementAst]},$false) | Select-Object -First 1
    $fatal=Make-Fixture fatal ($definitions['Set-CheckerStartupStatus']+"`r`n"+$definitions['Restore-CheckerOperation']+"`r`n"+$definitions['Show-CheckerFailure']+"`r`n"+$trap.Extent.Text+"`r`n"+'$script:checkerPhase="Preparing display";throw "Synthetic display failure"')
    $env:HWID_SCRIPT=$fatal;$messages.Clear()
    Assert (-not (Start-ReadableConsole $fatal $false $false '') -and ($messages -join ' ') -match 'Synthetic display failure') 'The real fatal trap reports pre-ready failure to the original launcher'
    $script:failStart=$true;$messages.Clear()
    Assert (-not (Start-ReadableConsole $ready $false $false '') -and ($messages -join ' ') -match 'START-03') 'Process creation failure keeps startup in the original window'
    Assert (-not (Test-Path -LiteralPath $lastSignal) -and $env:HWID_STARTUP_SIGNAL -ceq 'PARENT_SIGNAL_SENTINEL') 'Failed creation still restores environment and removes temporary state'
    $script:failStart=$false
    function Wait-ReadableConsoleStart {param($Child,$SignalPath,$TimeoutMilliseconds) [pscustomobject]@{State='Pending';Detail=''}}
    try {
        $pending=Make-Fixture pending 'Start-Sleep -Milliseconds 800;Write-Output "PENDING_DONE"'
        $env:HWID_SCRIPT=$pending;$messages.Clear();$clock=[Diagnostics.Stopwatch]::StartNew()
        Assert ((Start-ReadableConsole $pending $false $false '') -and $clock.ElapsedMilliseconds -ge 600 -and ($messages -join ' ') -match 'START-04') 'A slow unconfirmed child keeps the original window open until it finishes'
        $pendingFailure=Make-Fixture pending-failure 'Start-Sleep -Milliseconds 800;exit 23'
        $env:HWID_SCRIPT=$pendingFailure;$messages.Clear()
        Assert (-not (Start-ReadableConsole $pendingFailure $false $false '') -and ($messages -join ' ') -match 'START-03.*code 23') 'Failure after the initial readiness wait returns to current-window fallback'
    }finally{. ([scriptblock]::Create($definitions['Wait-ReadableConsoleStart']))}
    $fake=New-Object psobject;$fake | Add-Member ScriptMethod WaitForExit {param($ms) return $false}
    $statusFile=Join-Path $root 'status.txt';[IO.File]::WriteAllText($statusFile,'')
    Assert ((Wait-ReadableConsoleStart $fake $statusFile 0).State -eq 'Pending') 'The readiness observation has a bounded initial wait'
    [IO.File]::WriteAllText($statusFile,("FAILED`n"+('x'*500)+[char]27+"`r`n"))
    $status=Wait-ReadableConsoleStart $fake $statusFile 0
    Assert ($status.State -eq 'Failed' -and $status.Detail.Length -le 320 -and $status.Detail -notmatch '[\x00-\x1f\x7f]') 'Child startup details are bounded and cannot inject console controls'
    $env:HWID_STARTUP_SIGNAL=$statusFile
    Assert (Set-CheckerStartupStatus READY) 'The readiness writer confirms successful signal publication'
    Assert ($null -eq $env:HWID_STARTUP_SIGNAL -and ([IO.File]::ReadAllText($statusFile) -split '\n')[0] -eq 'READY') 'Publishing readiness consumes the child-only startup signal'
    $env:HWID_STARTUP_SIGNAL=Join-Path $root 'missing-folder\signal.txt'
    Assert (-not (Set-CheckerStartupStatus READY)) 'An unwritable signal does not become an application exception'
    $env:HWID_STARTUP_SIGNAL=$null
    Assert (-not (Set-CheckerStartupStatus READY)) 'Ordinary current-window runs do not create a startup signal'
}finally{
    $env:HWID_SCRIPT=$priorPath;$env:HWID_STARTUP_SIGNAL=$priorSignal
    if($script:lastChildId){$owned=Get-Process -Id $script:lastChildId -ErrorAction SilentlyContinue;if($null -ne $owned){if($owned.StartTime -eq $script:lastChildStart){$owned.Kill()};$owned.Dispose()}}
}
[Console]::WriteLine("All $script:checks startup-handoff checks passed under PowerShell $($PSVersionTable.PSVersion).")
