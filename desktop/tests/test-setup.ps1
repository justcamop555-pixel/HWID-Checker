#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$SetupPath,
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$setup=[IO.Path]::GetFullPath($SetupPath)
if([IO.Path]::GetFileName($setup) -notmatch '^HWID-Checker-Setup-\d+\.\d+\.\d+-win-x64-TEST\.exe$'){throw 'Only the separately compiled TEST installer may be used by this test.'}
$root=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)){throw 'Choose a new, empty verification directory.'}
[void][IO.Directory]::CreateDirectory($root)
$target=Join-Path $root 'Installed application'
$package=[IO.Path]::GetFullPath($PackageDirectory)
$checks=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
function Run-Setup([string]$Executable,[string]$Name,[switch]$Uninstall){
    $log=Join-Path $root ($Name+'.log')
    $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+$log+'"'))
    if(-not $Uninstall){$arguments+=('/DIR="'+$target+'"')}
    $process=Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if(-not $process.WaitForExit(90000)){throw ('Setup did not finish; inspect '+$log)}
    if($process.ExitCode -ne 0){throw ($Name+' returned '+$process.ExitCode+'; inspect '+$log)}
}
Run-Setup $setup 'install'
$installedExe=Join-Path $target 'HWID Checker.exe'
Assert ([IO.File]::Exists($installedExe)) 'setup installs the desktop executable'
Assert ([IO.File]::Exists((Join-Path $target 'HWID-SETUP.ini'))) 'setup writes its installation marker'
$cached=@(Get-ChildItem -LiteralPath (Join-Path $target 'Maintenance') -File -Filter '*.exe')
Assert ($cached.Count -eq 1 -and (Get-FileHash -LiteralPath $cached[0].FullName).Hash -eq (Get-FileHash -LiteralPath $setup).Hash) 'offline repair retains the exact setup executable'
$reports=Join-Path $target 'HWID-Reports'
[void][IO.Directory]::CreateDirectory($reports)
$snapshot=Join-Path $reports 'HWID-synthetic-preserve.json'
$custom=Join-Path $target 'keep-my-notes.txt'
[IO.File]::WriteAllText($snapshot,'{"synthetic":true,"identifier":"000123"}')
[IO.File]::WriteAllText($custom,'User-owned file; preserve during repair and uninstall.')
$snapshotHash=(Get-FileHash -LiteralPath $snapshot).Hash
$customHash=(Get-FileHash -LiteralPath $custom).Hash
$bat=[IO.Path]::GetFullPath((Join-Path $target 'hwid.bat'))
if(-not $bat.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Test mutation escaped its verification directory.'}
[IO.File]::Delete($bat)
[IO.File]::WriteAllText((Join-Path $target 'Start-HWID.ps1'),'Synthetic corruption')
if([IO.File]::Exists((Join-Path $target 'HWID Checker.App.exe'))){
    [IO.File]::Delete((Join-Path $target 'hostfxr.dll'))
    [IO.File]::WriteAllText((Join-Path $target 'HWID Checker.runtimeconfig.json'),'Synthetic corruption')
}
Run-Setup $cached[0].FullName 'repair'
$required=@('hwid.bat','Start-HWID.ps1','HWID Checker.exe','Update-HWID.ps1')
if([IO.File]::Exists((Join-Path $package 'HWID Checker.App.exe'))){$required+=@('HWID Checker.App.exe','HWID Checker.dll','hostfxr.dll','HWID Checker.runtimeconfig.json')}
foreach($relative in $required){
    Assert ((Get-FileHash -LiteralPath (Join-Path $target $relative)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $package $relative)).Hash) ('repair restores exact package file: '+$relative)
}
Assert ((Get-FileHash -LiteralPath $snapshot).Hash -eq $snapshotHash -and (Get-FileHash -LiteralPath $custom).Hash -eq $customHash) 'repair preserves reports and custom files'
$uninstaller=Join-Path $target 'unins000.exe'
Assert ([IO.File]::Exists($uninstaller)) 'setup creates its uninstaller'
Run-Setup $uninstaller 'uninstall' -Uninstall
Assert (-not [IO.File]::Exists($installedExe) -and -not [IO.File]::Exists($bat) -and -not [IO.File]::Exists((Join-Path $target 'HWID-SETUP.ini'))) 'uninstall removes installed application files and marker'
foreach($relative in $required){Assert (-not [IO.File]::Exists((Join-Path $target $relative))) ('uninstall removes tracked payload: '+$relative)}
Assert ((Get-FileHash -LiteralPath $snapshot).Hash -eq $snapshotHash -and (Get-FileHash -LiteralPath $custom).Hash -eq $customHash) 'uninstall keeps snapshots and custom files byte-for-byte'
[pscustomobject]@{success=$true;checks=$checks;testInstall=$true;productionUacTested=$false;preservedData=$true;path=$root} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'result.json') -Encoding UTF8
