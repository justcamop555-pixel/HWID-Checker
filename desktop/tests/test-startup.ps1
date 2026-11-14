#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$Exe,[ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Name='startup',[string]$BatPath=(Join-Path $PSScriptRoot '..\..\hwid.bat'),[string]$OutputDirectory=(Join-Path $PSScriptRoot 'test-output-startup'),[switch]$OneCore,[switch]$StartupFlow,[ValidateRange(0,5000)][int]$DelayMs=0,[switch]$CancelStartup)
$ErrorActionPreference='Stop'
if($CancelStartup -and (-not $StartupFlow -or $DelayMs -lt 1000)){throw 'Cancellation verification requires StartupFlow and at least 1000 milliseconds of synthetic preparation delay.'}
$Exe=[IO.Path]::GetFullPath($Exe);$BatPath=[IO.Path]::GetFullPath($BatPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$folder=Join-Path $OutputDirectory ($Name+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($folder)
$fixture=Join-Path $folder 'fixture.json'
[IO.File]::WriteAllText($fixture,'{"version":"3.91","inventory":{"Report info":{"Version":"3.91","Computer":"SYNTHETIC","Generated":"2026-11-12T12:00:00Z"},"CPU":[{"Name":"Synthetic CPU","ProcessorId":"SYNTHETIC-ID"}]},"identifiers":[],"warnings":[]}',[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($Exe)
$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$start.Environment['DOTNET_BUNDLE_EXTRACT_BASE_DIR']=Join-Path $folder 'bundle-cache'
$start.Environment['HWID_NO_UPDATE']='1'
$arguments=@('--engine',$BatPath)
if($StartupFlow){$arguments+=@('--startup-test',(Join-Path $folder 'result.json'),'--startup-delay-ms',[string]$DelayMs)}
else{$arguments+=@('--fixture',$fixture,'--render',(Join-Path $folder 'overview.png'),'--verify',(Join-Path $folder 'result.json'),'--size','640x480')}
foreach($value in $arguments){[void]$start.ArgumentList.Add($value)}
$launchedAt=[Diagnostics.Stopwatch]::GetTimestamp();$clock=[Diagnostics.Stopwatch]::StartNew();$p=[Diagnostics.Process]::Start($start)
if($OneCore){try{$bits=[long][Diagnostics.Process]::GetCurrentProcess().ProcessorAffinity;$p.ProcessorAffinity=[IntPtr]($bits -band (-$bits));$p.PriorityClass='BelowNormal'}catch{throw 'Could not constrain this synthetic startup measurement.'}}
$firstWindow=$null;$peak=0L;$cancelled=$false
while(-not $p.HasExited){
 $p.Refresh();if($null -eq $firstWindow -and $p.MainWindowHandle -ne [IntPtr]::Zero){$firstWindow=[math]::Round($clock.Elapsed.TotalMilliseconds)}
 $peak=[math]::Max($peak,$p.WorkingSet64)
 if($CancelStartup -and $null -ne $firstWindow -and -not $cancelled -and $clock.ElapsedMilliseconds -gt ($firstWindow+200)){
  if(-not $p.CloseMainWindow()){throw 'The startup window did not accept a normal close request.'};$cancelled=$true
 }
 if($clock.Elapsed.TotalSeconds -gt 180){$p.Kill();throw 'Only the synthetic startup probe exceeded its 180-second limit.'}
 Start-Sleep -Milliseconds 20
}
$p.WaitForExit();$elapsed=[math]::Round($clock.Elapsed.TotalMilliseconds)
$result=if(-not $cancelled){Get-Content (Join-Path $folder 'result.json') -Raw|ConvertFrom-Json}
if($p.ExitCode -ne 0 -or (-not $cancelled -and -not $result.success)){throw 'Synthetic startup did not complete successfully.'}
if($cancelled -and (Test-Path (Join-Path $folder 'result.json'))){throw 'Closing the loading window must not continue into the dashboard.'}
if($StartupFlow -and -not $cancelled){
 if([IO.Path]::GetFileName($Exe) -ceq 'HWID Checker.exe' -and [IO.File]::Exists((Join-Path ([IO.Path]::GetDirectoryName($Exe)) 'HWID Checker.App.exe')) -and -not $result.nativeLauncherValidated){throw 'The managed app did not validate the native parent identity used by updates.'}
 if(-not $result.startupLoadingShown -or $result.phases.loadingRenderedMs -ge $result.phases.preferencesReadMs -or $result.phases.dashboardBuiltMs -gt $result.phases.dashboardRenderedMs){throw 'Startup phases did not paint the loading window before settings and the dashboard.'}
 if($DelayMs -gt 0 -and $elapsed - $firstWindow -lt $DelayMs){throw 'The startup loading window was not visible during the simulated slow preparation.'}
}
$cache=Join-Path $folder 'bundle-cache'
$files=@(if(Test-Path $cache){Get-ChildItem -LiteralPath $cache -Recurse -File})
$loadingPaint=if($result.measurementFrequency -gt 0){[math]::Round(1000*($result.measurementStartedTimestamp-$launchedAt)/$result.measurementFrequency+$result.phases.loadingRenderedMs)}else{$null}
$data=[pscustomobject]@{Name=$Name;OneCore=[bool]$OneCore;StartupFlow=[bool]$StartupFlow;CancelledDuringStartup=$cancelled;FirstWindowMs=$firstWindow;LoadingPaintMs=$loadingPaint;CompleteMs=$elapsed;PeakWorkingSetMB=[math]::Round($peak/1MB,1);ExtractedFiles=$files.Count;ExtractedMB=[math]::Round(($files|Measure-Object Length -Sum).Sum/1MB,1);Phases=$result.phases;Success=$true;SyntheticOnly=$true}
$data|ConvertTo-Json|Set-Content (Join-Path $folder 'timing.json') -Encoding utf8
$data|ConvertTo-Json
