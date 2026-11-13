param(
    [string]$EngineDirectory='',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'artifacts'),
    [switch]$NoZip
)
$ErrorActionPreference='Stop'

function Resolve-FileSystemPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)){throw 'A filesystem path is required.'}
    return [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}

function Copy-RuntimePackageNotices([string]$AssetsPath,[string]$PackageRoot,[string]$DotnetRoot) {
    if(-not (Test-Path -LiteralPath $AssetsPath -PathType Leaf)){throw 'The restored project.assets.json is missing; runtime notice sources could not be determined.'}
    $assets=Get-Content -LiteralPath $AssetsPath -Raw | ConvertFrom-Json
    $restored=@{}
    foreach($framework in $assets.project.frameworks.PSObject.Properties){
        foreach($dependency in $framework.Value.downloadDependencies){
            $id=[string]$dependency.name
            if($id -notmatch '^Microsoft\.(NETCore|WindowsDesktop)\.App\.Runtime\.win-x64$'){continue}
            $range=[regex]::Match([string]$dependency.version,'^\[(?<Minimum>[^,\]]+),\s*(?<Maximum>[^\]]+)\]$')
            if(-not $range.Success -or $range.Groups['Minimum'].Value.Trim() -ne $range.Groups['Maximum'].Value.Trim()){throw ('An exact runtime package version is required for notice collection: '+$id)}
            $version=$range.Groups['Minimum'].Value.Trim()
            if($version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'){throw ('Unexpected runtime package version: '+$id)}
            if($restored.ContainsKey($id) -and $restored[$id] -ne $version){throw ('Multiple runtime package versions were restored: '+$id)}
            $restored[$id]=$version
        }
    }
    if($restored.Count -ne 2){throw 'The restored .NET Core and Windows Desktop runtime package versions could not both be determined.'}
    $copied=New-Object 'System.Collections.Generic.List[string]'
    $sources=New-Object 'System.Collections.Generic.List[string]'
    foreach($id in @($restored.Keys | Sort-Object)){
        $version=[string]$restored[$id]
        $packageId=$id.ToLowerInvariant()
        $candidates=@(foreach($folder in $assets.packageFolders.PSObject.Properties.Name){Join-Path (Join-Path $folder $packageId) $version})
        if($DotnetRoot){$candidates+=Join-Path (Join-Path (Join-Path $DotnetRoot 'packs') $id) $version}
        $source=@($candidates | Where-Object {Test-Path -LiteralPath $_ -PathType Container} | Select-Object -First 1)
        if(-not $source.Count){throw ('The restored runtime package was not found for notice collection: '+$id+' '+$version)}
        $noticeFiles=@(Get-ChildItem -LiteralPath $source[0] -File | Where-Object {$_.Name -match '^(LICENSE(?:\.TXT)?|THIRD[-_ ]?PARTY[-_ ]?NOTICES(?:\.TXT)?)$'})
        if(-not $noticeFiles.Count){throw ('No original license/notice files were found in runtime package '+$id+' '+$version)}
        $relativeDirectory='notices\runtime-packs\'+$packageId+'\'+$version
        $destination=Join-Path $PackageRoot $relativeDirectory
        [void][IO.Directory]::CreateDirectory($destination)
        foreach($file in $noticeFiles){
            $target=Join-Path $destination $file.Name
            $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            if(Test-Path -LiteralPath $target){
                if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash){throw ('Existing runtime notice differs from its original package: '+$target)}
            }else{Copy-Item -LiteralPath $file.FullName -Destination $target}
            if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash){throw ('Runtime notice verification failed: '+$target)}
            $relative=(Join-Path $relativeDirectory $file.Name).Replace('\','/')
            $copied.Add($relative)
            $sources.Add($id+' / '+$version+' / '+$file.Name)
        }
    }
    $manifest=Join-Path $PackageRoot 'notices\runtime-package-sources.txt'
    [IO.File]::WriteAllText($manifest,($sources -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    return @($copied.ToArray())
}

$project=Join-Path $PSScriptRoot 'HwidDesktop.csproj'
if(-not (Test-Path -LiteralPath $project -PathType Leaf)){throw 'Keep build-desktop.ps1 beside HwidDesktop.csproj in the desktop source directory.'}
if([string]::IsNullOrWhiteSpace($EngineDirectory)){
    foreach($candidate in @((Split-Path -Parent $PSScriptRoot),$PSScriptRoot)){
        if(Test-Path -LiteralPath (Join-Path $candidate 'hwid.bat') -PathType Leaf){$EngineDirectory=$candidate;break}
    }
}
if([string]::IsNullOrWhiteSpace($EngineDirectory)){throw 'Scanner files were not found. Pass -EngineDirectory with the directory containing hwid.bat (normally the repository root).'}
$engineRoot=Resolve-FileSystemPath $EngineDirectory
$batchPath=Join-Path $engineRoot 'hwid.bat'
$launcherPath=Join-Path $engineRoot 'Start-HWID.ps1'
if(-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)){throw 'Start-HWID.ps1 is required beside hwid.bat to build offline console recovery.'}
if(-not (Test-Path -LiteralPath $batchPath -PathType Leaf)){throw ('hwid.bat was not found in the selected engine directory: '+$engineRoot)}
$batchText=[IO.File]::ReadAllText($batchPath)
if([regex]::Matches($batchText,'(?m)^# POWERSHELL_START\r?$').Count -ne 1){throw 'The selected hwid.bat does not contain the expected embedded PowerShell checker.'}
$bridgePath=Join-Path $PSScriptRoot 'engine\DesktopBridge.ps1'
if(-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)){throw 'The desktop engine bridge is missing. Restore engine\DesktopBridge.ps1 before building.'}
$readmePath=Join-Path $PSScriptRoot 'README.md'
if(-not (Test-Path -LiteralPath $readmePath -PathType Leaf)){throw 'The desktop README.md is missing.'}
$updaterPath=Join-Path $engineRoot 'Update-HWID.ps1'
if(-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)){throw 'Keep Update-HWID.ps1 beside hwid.bat when building the portable package.'}
$updaterHash=(Get-FileHash -LiteralPath $updaterPath -Algorithm SHA256).Hash
$batchHash=(Get-FileHash -LiteralPath $batchPath -Algorithm SHA256).Hash
$launcherHash=if(Test-Path -LiteralPath $launcherPath -PathType Leaf){(Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash}else{$null}
$engineVersionMatch=[regex]::Match($batchText,"Version\s*=\s*'(?<Version>[0-9]+(?:\.[0-9]+)+)'")
$engineVersion=if($engineVersionMatch.Success){$engineVersionMatch.Groups['Version'].Value}else{'unknown'}
[xml]$projectXml=[IO.File]::ReadAllText($project)
$versions=@($projectXml.Project.PropertyGroup | ForEach-Object {$_.Version} | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)})
$desktopVersion=if($versions.Count){[string]$versions[0]}else{'development'}
$versionToken=$desktopVersion -replace '[^A-Za-z0-9._-]','-'
$updaterVersion=[regex]::Match([IO.File]::ReadAllText($updaterPath),"(?m)^# HWID_PACKAGE_VERSION = '(?<Version>[0-9.]+)'\r?$")
if(-not $updaterVersion.Success -or $updaterVersion.Groups['Version'].Value -ne $desktopVersion){throw 'The updater stamp must match the desktop package version.'}
$batPackageVersion=[regex]::Match($batchText,"function Get-CheckerPackageVersion\s*\{\s*return\s+'(?<Version>[0-9.]+)'\s*\}")
if(-not $batPackageVersion.Success -or $batPackageVersion.Groups['Version'].Value -ne $desktopVersion){throw 'The BAT package version must match the desktop package version.'}
$dotnet=Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if($null -eq $dotnet){throw 'Install the .NET 10 SDK to build the desktop application, then run this script again.'}
$sdkOutput=@(& $dotnet.Source --version)
if($LASTEXITCODE -ne 0){throw 'The .NET SDK could not start. Check the installed SDK and the build environment.'}
$sdkVersion=@($sdkOutput | Where-Object {$_ -match '^\d+\.\d+\.\d+'} | Select-Object -First 1)
if(-not $sdkVersion.Count -or [int](([string]$sdkVersion[0] -split '\.')[0]) -lt 10){throw 'This desktop project requires the .NET 10 SDK or a compatible newer SDK.'}

# Every invocation owns a new directory. Existing builds and snapshots are never
# deleted or overwritten, even when OutputDirectory already contains artifacts.
$outputRoot=Resolve-FileSystemPath $OutputDirectory
$buildName='build-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$buildRoot=Join-Path $outputRoot $buildName
if(Test-Path -LiteralPath $buildRoot){throw 'The new build directory already exists; run the build again.'}
[void][IO.Directory]::CreateDirectory($buildRoot)
$publishRoot=Join-Path $buildRoot 'publish'
$packageRoot=Join-Path $buildRoot 'HWID Checker Desktop'
[void][IO.Directory]::CreateDirectory($packageRoot)
Write-Host ('Building desktop '+$desktopVersion+' with scanner '+$engineVersion+'...')
$publishArguments=@(
    'publish',$project,'--configuration','Release','--runtime','win-x64',
    '--self-contained','true','--output',$publishRoot,
    '-p:PublishSingleFile=true','-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:PublishReadyToRun=false','-p:PublishReadyToRunComposite=false',
    '-p:EnableCompressionInSingleFile=false',
    '-p:PublishTrimmed=false','-p:DebugType=None','-p:DebugSymbols=false',
    '-p:UseSharedCompilation=false'
    ('-p:HwidEngineDirectory='+$engineRoot)
)
& $dotnet.Source @publishArguments
if($LASTEXITCODE -ne 0){throw ('Desktop publish failed. Build diagnostics remain in '+$buildRoot)}
$publishedExe=Join-Path $publishRoot 'HWID Checker.exe'
if(-not (Test-Path -LiteralPath $publishedExe -PathType Leaf)){throw 'Publish completed without the expected HWID Checker.exe.'}
if((Get-FileHash -LiteralPath $batchPath -Algorithm SHA256).Hash -ne $batchHash){throw 'The scanner changed while the desktop application was building. Run the build again with a stable engine.'}
if($launcherHash -and (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash -ne $launcherHash){throw 'The alternative launcher changed during the build.'}

# Preserve the complete SDK publish output, including any runtime notices or
# dependencies the SDK leaves beside the bundled executable.
foreach($item in Get-ChildItem -LiteralPath $publishRoot -Force){Copy-Item -LiteralPath $item.FullName -Destination $packageRoot -Recurse}
Copy-Item -LiteralPath $batchPath -Destination (Join-Path $packageRoot 'hwid.bat') -Force
if($launcherHash){Copy-Item -LiteralPath $launcherPath -Destination (Join-Path $packageRoot 'Start-HWID.ps1') -Force}
Copy-Item -LiteralPath $readmePath -Destination (Join-Path $packageRoot 'README.md') -Force
Copy-Item -LiteralPath $updaterPath -Destination (Join-Path $packageRoot 'Update-HWID.ps1') -Force
if((Get-FileHash -LiteralPath (Join-Path $packageRoot 'Update-HWID.ps1')).Hash -ne $updaterHash){throw 'Packaged updater verification failed.'}
$runtimeNoticeFiles=@(Copy-RuntimePackageNotices (Join-Path $PSScriptRoot 'obj\project.assets.json') $packageRoot (Split-Path -Parent $dotnet.Source))
if((Get-FileHash -LiteralPath (Join-Path $packageRoot 'hwid.bat') -Algorithm SHA256).Hash -ne $batchHash){throw 'Packaged BAT verification failed.'}
if($launcherHash -and (Get-FileHash -LiteralPath (Join-Path $packageRoot 'Start-HWID.ps1') -Algorithm SHA256).Hash -ne $launcherHash){throw 'Packaged alternative launcher verification failed.'}
$packageExe=Join-Path $packageRoot 'HWID Checker.exe'
$exeHash=(Get-FileHash -LiteralPath $publishedExe -Algorithm SHA256).Hash
if((Get-FileHash -LiteralPath $packageExe -Algorithm SHA256).Hash -ne $exeHash){throw 'Packaged executable verification failed.'}
$checksumLines=@(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative=$_.FullName.Substring($packageRoot.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$relative
})
$checksumsPath=Join-Path $packageRoot 'SHA256SUMS.txt'
[IO.File]::WriteAllText($checksumsPath,($checksumLines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
$archivePath=$null
if(-not $NoZip){
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archivePath=Join-Path $buildRoot ('HWID-Checker-Desktop-'+$versionToken+'-win-x64.zip')
    # Windows PowerShell 5.1 uses the .NET Framework ZipFile, which writes
    # subdirectory entry names with backslashes that the update verifier
    # rejects. Create every entry explicitly with forward slashes instead.
    $separator=[string][char]92
    $archiveStream=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $baseName=Split-Path -Leaf $packageRoot
        foreach($item in (Get-ChildItem -LiteralPath $packageRoot -File -Recurse)){
            $relative=$baseName+'/'+$item.FullName.Substring($packageRoot.Length).TrimStart([char[]]@([char]92,[char]47)).Replace($separator,'/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archiveStream,$item.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal)
        }
    }finally{$archiveStream.Dispose()}
    $archiveLine=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($archivePath)
    [IO.File]::WriteAllText((Join-Path $buildRoot 'SHA256SUMS.txt'),$archiveLine+"`n",[Text.UTF8Encoding]::new($false))
}
if((Get-FileHash -LiteralPath $batchPath -Algorithm SHA256).Hash -ne $batchHash){throw 'The original scanner changed before packaging completed.'}
if((Get-FileHash -LiteralPath $updaterPath -Algorithm SHA256).Hash -ne $updaterHash){throw 'The updater changed before packaging completed.'}
[pscustomobject]@{
    DesktopVersion=$desktopVersion
    EngineVersion=$engineVersion
    Runtime='win-x64'
    SelfContained=$true
    ReadyToRun=$false
    CompositeReadyToRun=$false
    SingleFileCompression=$false
    PackageDirectory=$packageRoot
    Executable=$packageExe
    Archive=$archivePath
    Checksums=$checksumsPath
    EngineSha256=$batchHash
    ApplicationSha256=$exeHash
    UpdaterSha256=$updaterHash
    OriginalEngineUnchanged=$true
    RuntimeNoticeFiles=$runtimeNoticeFiles
} | ConvertTo-Json
