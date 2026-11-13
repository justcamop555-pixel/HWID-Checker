#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$ExePath,
    [string]$BatPath=(Join-Path $PSScriptRoot '..\..\hwid.bat'),
    [ValidateSet('Render','Workflow','Interactions','Readability','Scrolling','Restart','Theme','Welcome','Library','ScanUI','LiveScan')][string]$Mode='Render',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('test-output-ui-'+[guid]::NewGuid().ToString('N'))),
    [ValidateSet('Midnight','Daylight')][string]$Theme='Midnight',
    [ValidatePattern('^[1-9][0-9]{2,3}[xX][1-9][0-9]{2,3}$')][string]$Size,
    [switch]$LayoutStress,
    [switch]$TestSharedLibrary,
    [switch]$RepeatScan
)
$ErrorActionPreference='Stop'
if($Size -and $Mode -eq 'LiveScan'){throw 'Choose Render, Workflow, Interactions or Readability mode to request a window size.'}
if($LayoutStress -and $Mode -ne 'Render'){throw 'Choose Render mode to exercise the layout stress states.'}
if($TestSharedLibrary -and $Mode -ne 'Workflow'){throw 'Choose Workflow mode to exercise the shared snapshot library.'}
if($RepeatScan -and $Mode -ne 'LiveScan'){throw 'Choose LiveScan mode to verify a second live scan.'}
if($Size){
    $Size=$Size.ToLowerInvariant()
    $sizeParts=$Size.Split('x')
    $requestedWidth=[int]$sizeParts[0]
    $requestedHeight=[int]$sizeParts[1]
}
$ExePath=[IO.Path]::GetFullPath($ExePath);$BatPath=[IO.Path]::GetFullPath($BatPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not [IO.File]::Exists($ExePath) -or -not [IO.File]::Exists($BatPath)){throw 'Select an existing desktop EXE and its HWID BAT.'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$before=(Get-FileHash -LiteralPath $BatPath).Hash
$pages=if($Mode -eq 'Render'){@('Overview','Identifiers','Hardware','Review','Snapshots','Compare')}else{@('Compare')}
$checks=0
foreach($page in $pages){
    $resultPath=Join-Path $OutputDirectory ($page.ToLowerInvariant()+'-result.json')
    $start=[Diagnostics.ProcessStartInfo]::new($ExePath)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle='Hidden'
    $start.Environment['HWID_NO_UPDATE']='1'
    $arguments=@('--engine',$BatPath)
    if($Mode -ne 'LiveScan'){$arguments+=@('--theme',$Theme.ToLowerInvariant())}
    if($Mode -eq 'LiveScan'){$arguments+=@('--scan-test',$resultPath);if($RepeatScan){$arguments+='--rescan-test'}}
    else{
        if($Size){$arguments+=@('--size',$Size)}
        if($LayoutStress){$arguments+='--layout-stress'}
        $arguments+=@('--fixture',(Join-Path $PSScriptRoot 'fixtures\desktop-scan.json'),'--page',$page,'--render',(Join-Path $OutputDirectory ($page.ToLowerInvariant()+'.png')),'--verify',$resultPath)
        if($Mode -eq 'Workflow'){$arguments+=@('--workflow-test',(Join-Path $OutputDirectory 'workflow-result.json'))}
        if($Mode -eq 'Interactions'){$arguments+=@('--ui-test',(Join-Path $OutputDirectory 'ui-result.json'))}
        if($Mode -eq 'Readability'){$arguments+=@('--readability-test',(Join-Path $OutputDirectory 'readability-result.json'))}
        if($Mode -eq 'Theme'){$arguments+=@('--theme-test',(Join-Path $OutputDirectory 'theme-result.json'))}
        if($Mode -eq 'Welcome'){$arguments+=@('--welcome-test',(Join-Path $OutputDirectory 'welcome-result.json'))}
        if($Mode -eq 'Library'){$arguments+=@('--library-test',(Join-Path $OutputDirectory 'library-result.json'))}
        if($Mode -eq 'ScanUI'){$arguments+=@('--scan-ui-test',(Join-Path $OutputDirectory 'scan-ui-result.json'))}
        if($Mode -eq 'Scrolling'){$arguments+=@('--scroll-test',(Join-Path $OutputDirectory 'scrolling-result.json'))}
        if($Mode -eq 'Restart'){$arguments+=@('--restart-test',$resultPath)}
        if($TestSharedLibrary){$arguments+=@('--shared-settings',(Join-Path $OutputDirectory ('shared-'+[guid]::NewGuid().ToString('N')+'\snapshot-library.json')))}
    }
    foreach($argument in $arguments){$start.ArgumentList.Add($argument)}
    $verificationStarted=[DateTime]::UtcNow
    $process=[Diagnostics.Process]::Start($start);$clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $limit=if($Mode -eq 'LiveScan'){660}else{120}
        while(-not $process.WaitForExit(500)){if($clock.Elapsed.TotalSeconds -gt $limit){$process.Kill($true);throw ('Desktop verification timed out: '+$page)}}
        if($process.ExitCode -ne 0){
            $failure=if(Test-Path -LiteralPath $resultPath){Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}
            $detail=if($failure.layoutFailure){' / '+$failure.layoutFailure}else{''}
            throw ('Desktop verification exited with an error: '+$page+$detail)
        }
    }finally{$process.Dispose()}
    if($Mode -eq 'Restart'){
        $completion=[Diagnostics.Stopwatch]::StartNew()
        $restartResult=$null
        while($completion.Elapsed.TotalSeconds -lt 35){
            try{
                if([IO.File]::GetLastWriteTimeUtc($resultPath) -ge $verificationStarted){
                    $restartResult=Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
                    break
                }
            }catch{}
            Start-Sleep -Milliseconds 100
        }
        if($null -eq $restartResult){throw 'The replacement window did not publish a new, complete restart result.'}
    }
    $result=if($Mode -eq 'Restart'){$restartResult}else{Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}
    if(-not $result.success -or -not $result.engineConnected -or $result.busy -or $result.hardwareIdentifiersSaved){throw ('Desktop result failed validation: '+$page)}
    if($Size){
        $contentWidth=$result.contentWidth -as [double]
        $contentHeight=$result.contentHeight -as [double]
        if($null -eq $contentWidth -or $null -eq $contentHeight -or
            $contentWidth -le 0 -or $contentHeight -le 0 -or
            -not [double]::IsFinite($contentWidth) -or -not [double]::IsFinite($contentHeight)){
            throw ('Desktop verification did not report usable content dimensions for '+$page+'.')
        }
        # The requested window size includes native chrome. The rendered WPF content does not.
        if([Math]::Abs($contentWidth-$requestedWidth) -gt 24 -or [Math]::Abs($contentHeight-$requestedHeight) -gt 64){
            throw ('{0} reported content {1:F1}x{2:F1} DIP for the requested {3} window. Check size coercion or clipping.' -f $page,$contentWidth,$contentHeight,$Size)
        }
    }
    if($LayoutStress -and ($result.layoutStress -isnot [bool] -or -not $result.layoutStress)){
        throw ('Desktop verification did not apply the layout stress state for '+$page+'.')
    }
    if($Mode -eq 'LiveScan' -and ($result.sectionsRead -ne 18 -or $result.knownDeviceRecords -lt 1 -or $result.responsiveTicks -lt 1)){throw 'Live desktop scan did not retain full section coverage and UI responsiveness.'}
    if($RepeatScan -and $result.scanNumber -ne 2){throw 'A repeated live scan did not advance from snapshot 1 to snapshot 2.'}
    if($Mode -eq 'Workflow'){
        $workflow=Get-Content -LiteralPath (Join-Path $OutputDirectory 'workflow-result.json') -Raw | ConvertFrom-Json
        $expectedChecks=if($TestSharedLibrary){24}else{22}
        if(-not $workflow.success -or $workflow.checks -ne $expectedChecks -or -not $workflow.syntheticOnly){throw 'Synthetic desktop workflow failed.'}
        $checks=$workflow.checks
    }elseif($Mode -eq 'Interactions'){
        $interaction=Get-Content -LiteralPath (Join-Path $OutputDirectory 'ui-result.json') -Raw | ConvertFrom-Json
        if(-not $interaction.success -or $interaction.checks -ne 80 -or -not $interaction.syntheticOnly){throw 'Synthetic desktop interactions failed.'}
        $checks=$interaction.checks
    }elseif($Mode -eq 'ScanUI'){
        $scanUi=Get-Content -LiteralPath (Join-Path $OutputDirectory 'scan-ui-result.json') -Raw|ConvertFrom-Json
        if(-not $scanUi.success -or -not $scanUi.syntheticOnly -or $scanUi.checks -lt 15){throw 'Scan UI checks failed.'}
        $checks=$scanUi.checks
    }elseif($Mode -eq 'Library'){
        $libraryResult=Get-Content -LiteralPath (Join-Path $OutputDirectory 'library-result.json') -Raw|ConvertFrom-Json
        if(-not $libraryResult.success -or -not $libraryResult.syntheticOnly -or $libraryResult.checks -lt 20){throw 'Snapshot library and comparison checks failed.'}
        $checks=$libraryResult.checks
    }elseif($Mode -eq 'Welcome'){
        $welcomeResult=Get-Content -LiteralPath (Join-Path $OutputDirectory 'welcome-result.json') -Raw|ConvertFrom-Json
        if(-not $welcomeResult.success -or -not $welcomeResult.syntheticOnly -or $welcomeResult.checks -lt 20){throw 'Welcome notice checks failed.'}
        $checks=$welcomeResult.checks
    }elseif($Mode -eq 'Theme'){
        $themeResult=Get-Content -LiteralPath (Join-Path $OutputDirectory 'theme-result.json') -Raw|ConvertFrom-Json
        if(-not $themeResult.success -or -not $themeResult.syntheticOnly -or $themeResult.checks -lt 20){throw 'Native theme checks failed.'}
        $checks=$themeResult.checks
    }elseif($Mode -eq 'Scrolling'){
        $scrolling=Get-Content -LiteralPath (Join-Path $OutputDirectory 'scrolling-result.json') -Raw | ConvertFrom-Json
        if(-not $scrolling.success -or -not $scrolling.syntheticOnly -or $scrolling.checks -ne 31){throw 'Synthetic desktop scrolling checks failed.'}
        $checks=$scrolling.checks
    }elseif($Mode -eq 'Readability'){
        $readability=Get-Content -LiteralPath (Join-Path $OutputDirectory 'readability-result.json') -Raw | ConvertFrom-Json
        if(-not $readability.success -or $readability.checks -ne 14 -or -not $readability.syntheticOnly){throw 'Synthetic desktop readability checks failed.'}
        $checks=$readability.checks
    }else{$checks++}
    [Console]::WriteLine('PASS: '+$Mode+' / '+$page)
}
if((Get-FileHash -LiteralPath $BatPath).Hash -ne $before){throw 'The desktop test changed the BAT source.'}
$summary=[ordered]@{Mode=$Mode;Checks=$checks;OutputDirectory=$OutputDirectory;BatUnchanged=$true;HardwareIdentifiersSaved=$false}
if($Size){$summary.RequestedSize=$Size}
if($LayoutStress){$summary.LayoutStress=$true}
if($TestSharedLibrary){$summary.SharedLibrary=$true}
[pscustomobject]$summary | ConvertTo-Json
