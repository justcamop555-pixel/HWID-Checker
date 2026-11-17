#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$SetupPath,[Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$setup=[IO.Path]::GetFullPath($SetupPath)
if([IO.Path]::GetFileName($setup) -notmatch '^HWID-Checker-Setup-\d+\.\d+\.\d+-win-x64\.exe$'){throw 'Use the production installer for this check.'}
if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'Run this check with a standard, non-elevated Windows token.'
}
$root=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $root){throw 'Choose a new verification directory.'}
$target=Join-Path $env:LOCALAPPDATA 'Programs\HWID Checker'
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{492BF2C2-619B-4DDE-B594-F90D2C3AC922}_is1'
$machineKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{492BF2C2-619B-4DDE-B594-F90D2C3AC922}_is1'
$shortcut=Join-Path ([Environment]::GetFolderPath('Programs')) 'HWID Checker\HWID Checker (current user).lnk'
$repairLink=Join-Path ([Environment]::GetFolderPath('Programs')) 'HWID Checker\Repair HWID Checker (current user).lnk'
if((Test-Path -LiteralPath $target) -or (Test-Path $key) -or (Test-Path -LiteralPath $shortcut) -or (Test-Path -LiteralPath $repairLink)){
    throw 'A personal installation or its shortcuts already exist; leave them untouched.'
}
$machineBefore=if(Test-Path $machineKey){Get-ItemProperty $machineKey|Select-Object DisplayName,DisplayVersion,InstallLocation|ConvertTo-Json -Compress}else{''}
[void][IO.Directory]::CreateDirectory($root)
$package=[IO.Path]::GetFullPath($PackageDirectory);$checks=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
function Run-Setup($exe,$name,[switch]$Uninstall,[switch]$ExpectBlocked,[string[]]$Extra=@()){
    $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $root ($name+'.log'))+'"'))
    if(-not $Uninstall){$arguments+='/CURRENTUSER'}
    $arguments+=$Extra
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if(-not $process.WaitForExit(90000)){throw ($name+' timed out; inspect its log.')}
    if($ExpectBlocked){Assert ($process.ExitCode -ne 0) ($name+' is blocked before changing installed files');return}
    if($process.ExitCode -ne 0){throw ($name+' did not complete successfully; inspect its log.')}
}
function Get-SetupMutexName([string]$directory){
    $normalized=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($directory))
    $characters=$normalized.ToCharArray()
    for($i=0;$i -lt $characters.Length;$i++){
        $code=[int]$characters[$i]
        if($code -ge 97 -and $code -le 122){$characters[$i]=[char]($code-32)}
    }
    return 'Local\HWID-Desktop-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::Unicode.GetBytes((-join $characters)))).ToLowerInvariant()
}
Run-Setup $setup 'install'
Assert ([IO.File]::Exists((Join-Path $target 'HWID Checker.exe'))) 'production setup installs into the current user Programs folder without elevation'
$marker=[IO.File]::ReadAllText((Join-Path $target 'HWID-SETUP.ini'))
Assert ($marker -match '(?m)^Scope=CurrentUser\s*$') 'personal installation records CurrentUser scope'
$registered=Get-ItemProperty $key
Assert ($registered.DisplayName -eq 'HWID Checker (current user)' -and $registered.InstallLocation.TrimEnd('\') -eq $target) 'personal uninstall entry is clearly named in HKCU'
Assert ($registered.ModifyPath -like '*/CURRENTUSER') 'Windows repair command keeps personal installation mode'
Assert ((Test-Path -LiteralPath $shortcut) -and (Test-Path -LiteralPath $repairLink)) 'personal Start menu shortcuts are created'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut($repairLink)
Assert ($link.Arguments -eq '/CURRENTUSER') 'Start menu repair shortcut keeps personal mode'
$link=$null;$shell=$null
$cached=@(Get-ChildItem -LiteralPath (Join-Path $target 'Maintenance') -File -Filter '*.exe')
Assert ($cached.Count -eq 1 -and (Get-FileHash $cached[0].FullName).Hash -eq (Get-FileHash $setup).Hash) 'personal setup retains its exact offline repair installer'
$wrongFolder=Join-Path $root 'wrong installation folder'
Run-Setup $setup 'wrong-folder' -ExpectBlocked -Extra @('/DIR="'+$wrongFolder+'"')
Assert (-not (Test-Path -LiteralPath (Join-Path $wrongFolder 'HWID Checker.exe'))) 'personal setup refuses another installation folder'
$reports=Join-Path $target 'HWID-Reports';[void][IO.Directory]::CreateDirectory($reports)
$snapshot=Join-Path $reports ('HWID-setup-synthetic-'+[guid]::NewGuid().ToString('N')+'.json')
$custom=Join-Path $target ('setup-synthetic-'+[guid]::NewGuid().ToString('N')+'.txt')
[IO.File]::WriteAllText($snapshot,'{"synthetic":true,"id":"000123"}')
[IO.File]::WriteAllText($custom,'User data preservation check.')
$snapshotHash=(Get-FileHash $snapshot).Hash;$customHash=(Get-FileHash $custom).Hash
[IO.File]::Delete((Join-Path $target 'hwid.bat'))
Run-Setup $cached[0].FullName 'repair'
Assert ((Get-FileHash (Join-Path $target 'hwid.bat')).Hash -eq (Get-FileHash (Join-Path $package 'hwid.bat')).Hash) 'personal repair restores a deleted scanner without elevation'
Assert ((Get-FileHash $snapshot).Hash -eq $snapshotHash -and (Get-FileHash $custom).Hash -eq $customHash) 'personal repair preserves snapshots and custom files'
$installedExe=Join-Path $target 'HWID Checker.exe'
$installedHash=(Get-FileHash $installedExe).Hash
$running=[Threading.Mutex]::new($false,(Get-SetupMutexName $target))
try{
    Run-Setup (Join-Path $target 'unins000.exe') 'uninstall-running' -Uninstall -ExpectBlocked
    Assert ((Test-Path $key) -and (Get-FileHash $installedExe).Hash -eq $installedHash) 'running-app guard leaves registration and application bytes intact'
}finally{$running.Dispose()}
# A later version in the existing folder must never be replaced by this setup.
$futureSource=Join-Path $root 'future-version.cs';$futureExe=Join-Path $root 'future-version.exe'
[IO.File]::WriteAllText($futureSource,'[assembly:System.Reflection.AssemblyFileVersion("99.0.0.0")] class Future { static void Main() {} }')
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe (('/out:')+$futureExe) $futureSource
if($LASTEXITCODE){throw 'Synthetic future-version fixture failed to compile.'}
try{
    [IO.File]::Copy($futureExe,$installedExe,$true)
    Run-Setup $setup 'downgrade' -ExpectBlocked
    Assert ((Get-FileHash $installedExe).Hash -eq (Get-FileHash $futureExe).Hash) 'downgrade rejection preserves the newer installed executable'
}finally{[IO.File]::Copy((Join-Path $package 'HWID Checker.exe'),$installedExe,$true)}
$other=[Threading.Mutex]::new($false,(Get-SetupMutexName (Join-Path $root 'other installation')))
try{
    Run-Setup (Join-Path $target 'unins000.exe') 'uninstall' -Uninstall
}finally{$other.Dispose()}
Assert (-not (Test-Path $key) -and -not (Test-Path -LiteralPath (Join-Path $target 'HWID Checker.exe'))) 'personal uninstall removes its application and HKCU registration without elevation'
Assert (-not (Test-Path -LiteralPath $shortcut) -and -not (Test-Path -LiteralPath $repairLink)) 'personal uninstall removes only its own Start menu shortcuts'
Assert ((Get-FileHash $snapshot).Hash -eq $snapshotHash -and (Get-FileHash $custom).Hash -eq $customHash) 'personal uninstall retains snapshots and custom files'
$machineAfter=if(Test-Path $machineKey){Get-ItemProperty $machineKey|Select-Object DisplayName,DisplayVersion,InstallLocation|ConvertTo-Json -Compress}else{''}
Assert ($machineBefore -ceq $machineAfter) 'personal lifecycle leaves the machine uninstall entry unchanged'
# Remove only the exact two files created above after proving that uninstall kept them.
foreach($file in @($snapshot,$custom)){
    $full=[IO.Path]::GetFullPath($file)
    if(-not $full.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic cleanup escaped the personal test directory.'}
    [IO.File]::Delete($full)
}
foreach($folder in @($reports,$target)){if([IO.Directory]::Exists($folder) -and [IO.Directory]::GetFileSystemEntries($folder).Length -eq 0){[IO.Directory]::Delete($folder,$false)}}
[pscustomobject]@{success=$true;checks=$checks;productionCurrentUserTested=$true;elevated=$false;machineInstallTested=$false;preservedData=$true}|
    ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'result.json')
