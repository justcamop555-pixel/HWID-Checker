#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$ExePath,
    [string]$BatPath=(Join-Path $PSScriptRoot '..\..\hwid.bat'),
    [ValidateSet('Render','Workflow','Interactions','LiveScan')][string]$Mode='Render',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('test-output-ui-'+[guid]::NewGuid().ToString('N'))),
    [ValidatePattern('^[1-9][0-9]{2,3}[xX][1-9][0-9]{2,3}$')][string]$Size,
    [switch]$LayoutStress,
    [switch]$TestSharedLibrary
)
$ErrorActionPreference='Stop'
if($Size -and $Mode -eq 'LiveScan'){throw 'Choose Render, Workflow or Interactions mode to request a window size.'}
if($LayoutStress -and $Mode -ne 'Render'){throw 'Choose Render mode to exercise the layout stress states.'}
if($TestSharedLibrary -and $Mode -ne 'Workflow'){throw 'Choose Workflow mode to exercise the shared snapshot library.'}
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
    if($Mode -eq 'LiveScan'){$arguments+=@('--scan-test',$resultPath)}
    else{
        if($Size){$arguments+=@('--size',$Size)}
        if($LayoutStress){$arguments+='--layout-stress'}
        $arguments+=@('--fixture',(Join-Path $PSScriptRoot 'fixtures\desktop-scan.json'),'--page',$page,'--render',(Join-Path $OutputDirectory ($page.ToLowerInvariant()+'.png')),'--verify',$resultPath)
        if($Mode -eq 'Workflow'){$arguments+=@('--workflow-test',(Join-Path $OutputDirectory 'workflow-result.json'))}
        if($Mode -eq 'Interactions'){$arguments+=@('--ui-test',(Join-Path $OutputDirectory 'ui-result.json'))}
        if($TestSharedLibrary){$arguments+=@('--shared-settings',(Join-Path $OutputDirectory ('shared-'+[guid]::NewGuid().ToString('N')+'\snapshot-library.json')))}
    }
    foreach($argument in $arguments){$start.ArgumentList.Add($argument)}
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
    $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
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
    if($Mode -eq 'Workflow'){
        $workflow=Get-Content -LiteralPath (Join-Path $OutputDirectory 'workflow-result.json') -Raw | ConvertFrom-Json
        $expectedChecks=if($TestSharedLibrary){24}else{22}
        if(-not $workflow.success -or $workflow.checks -ne $expectedChecks -or -not $workflow.syntheticOnly){throw 'Synthetic desktop workflow failed.'}
        $checks=$workflow.checks
    }elseif($Mode -eq 'Interactions'){
        $interaction=Get-Content -LiteralPath (Join-Path $OutputDirectory 'ui-result.json') -Raw | ConvertFrom-Json
        if(-not $interaction.success -or $interaction.checks -ne 21 -or -not $interaction.syntheticOnly){throw 'Synthetic desktop interactions failed.'}
        $checks=$interaction.checks
    }else{$checks++}
    [Console]::WriteLine('PASS: '+$Mode+' / '+$page)
}
if((Get-FileHash -LiteralPath $BatPath).Hash -ne $before){throw 'The desktop test changed the BAT source.'}
$summary=[ordered]@{Mode=$Mode;Checks=$checks;OutputDirectory=$OutputDirectory;BatUnchanged=$true;HardwareIdentifiersSaved=$false}
if($Size){$summary.RequestedSize=$Size}
if($LayoutStress){$summary.LayoutStress=$true}
if($TestSharedLibrary){$summary.SharedLibrary=$true}
[pscustomobject]$summary | ConvertTo-Json
