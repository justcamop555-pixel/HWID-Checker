#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$TestInstall
)
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($output.Equals($package,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Keep setup output outside its input package.'}
if(-not [IO.File]::Exists($CompilerPath)){throw 'Pass the path to ISCC.exe from Inno Setup 7 or later.'}
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(-not [IO.File]::Exists($manifest)){throw 'Build the portable package first; its checksum manifest is required.'}
$listed=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach($line in [IO.File]::ReadAllLines($manifest)){
    if($line -notmatch '^([a-fA-F0-9]{64})  (.+)$'){throw 'Malformed package checksum entry.'}
    $expected=$Matches[1];$relative=$Matches[2]
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative.Contains(':')){throw 'Unsafe package checksum path.'}
    $file=[IO.Path]::GetFullPath((Join-Path $package $relative))
    if(-not $file.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $listed.Add($file)){throw 'Duplicate or escaped package path.'}
    if(-not [IO.File]::Exists($file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected){throw ('Package checksum failed: '+$relative)}
}
foreach($entry in (Get-ChildItem -LiteralPath $package -Force -Recurse)){
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Package inputs cannot contain linked files or directories.'}
    if(-not $entry.PSIsContainer -and $entry.FullName -ne $manifest -and -not $listed.Contains($entry.FullName)){throw ('Unlisted package file: '+$entry.Name)}
    if($entry.Name -match '^(HWID-Reports|settings\.json|snapshot-library\.json|HWID-SETUP\.ini|Maintenance)$'){throw 'The setup input must be a clean build, without user data or a previous installation.'}
}
$exe=Join-Path $package 'HWID Checker.exe'
$info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
$version='{0}.{1}.{2}' -f $info.FileMajorPart,$info.FileMinorPart,$info.FileBuildPart
if($version -notmatch '^\d+\.\d+\.\d+$' -or $info.FileMajorPart -lt 1){throw 'Missing desktop package version.'}
foreach($required in @('hwid.bat','Start-HWID.ps1','Update-HWID.ps1','README.md')){if(-not [IO.File]::Exists((Join-Path $package $required))){throw ('Missing package file: '+$required)}}
if([version]$version -ge [version]'1.5.0'){
    foreach($required in @('HWID Checker.App.exe','HWID Checker.dll','HWID Checker.runtimeconfig.json','HWID Checker.deps.json','hostfxr.dll','hostpolicy.dll','coreclr.dll')){
        if(-not [IO.File]::Exists((Join-Path $package $required))){throw ('The folder-based desktop package is incomplete: '+$required)}
    }
}
$license=Join-Path (Split-Path -Parent $PSScriptRoot) 'LICENSE'
[void][IO.Directory]::CreateDirectory($output)
$arguments=@(('/DPackageDir='+$package),('/DAppVersion='+$version),('/DOutputDir='+$output))
if([IO.File]::Exists($license)){$arguments+='/DLicensePath='+$license}
if($TestInstall){$arguments+='/DTestInstall=1'}
$arguments+=Join-Path $PSScriptRoot 'installer\HWID-Checker.iss'
& $CompilerPath @arguments
if($LASTEXITCODE -ne 0){throw ('Inno Setup compilation failed with exit code '+$LASTEXITCODE)}
$name='HWID-Checker-Setup-'+$version+'-win-x64'+$(if($TestInstall){'-TEST'}else{''})+'.exe'
$setup=Join-Path $output $name
$hash=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($setup+'.sha256'),$hash.ToLowerInvariant()+'  '+$name+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Setup=$setup;Version=$version;Sha256=$hash;AllUsers=(-not $TestInstall);TestOnly=[bool]$TestInstall} | ConvertTo-Json
