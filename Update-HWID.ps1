# HWID_PACKAGE_VERSION = '1.4.6'
[CmdletBinding()]
param(
    [ValidateSet('Check','Prepare','Apply')][string]$Mode='Check',
    [Parameter(Mandatory=$true)][string]$InstallDirectory,
    [Parameter(Mandatory=$true)][string]$CurrentVersion,
    [ValidateSet('Package','Bat')][string]$Component='Package',
    [string]$StageDirectory,
    [int]$WaitProcessId=0,
    [long]$WaitProcessStartTicks=0,
    [switch]$Relaunch,
    [string]$ResultPath
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$script:updateUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:updateRepository='justcamop555-pixel/HWID-Checker'
$script:updateArchiveRoot='HWID Checker Desktop'
$script:updateMaximumDownload=256MB
$script:updateMaximumExpanded=512MB

function ConvertTo-UpdateVersion([string]$Value) {
    if($Value -cnotmatch '\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z'){
        throw [IO.InvalidDataException]::new('Expected a desktop package version such as 1.3.0.')
    }
    $version=$null
    if(-not [version]::TryParse($Value,[ref]$version)){throw [IO.InvalidDataException]::new('The desktop package version is too large.')}
    return $version
}
function ConvertTo-UpdateDirectory([string]$Path) {
    if($Path -cnotmatch '\A[A-Za-z]:[\\/]' -or $Path.Length -gt 32767 -or $Path -match '[\p{Cc}<>"|?*]'){
        throw [IO.InvalidDataException]::new('Choose an absolute folder on a Windows drive.')
    }
    if($Path.Substring(2).Contains(':')){throw [IO.InvalidDataException]::new('The folder contains an invalid path component.')}
    foreach($part in ($Path.Substring(3) -split '[\\/]')){
        if(-not $part -or $part -in @('.','..')){continue}
        if($part.EndsWith(' ') -or $part.EndsWith('.') -or $part.Split('.')[0].TrimEnd(' ') -match '\A(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|(?:COM|LPT)[1-9\u00B9\u00B2\u00B3])\z'){
            throw [IO.InvalidDataException]::new('The folder contains an invalid Windows path component.')
        }
    }
    $full=[IO.Path]::GetFullPath($Path.Replace('/','\'))
    if($full.Length -gt 32767){throw [IO.PathTooLongException]::new()}
    if($full.Length -gt 3){$full=$full.TrimEnd('\')}
    return $full
}
function Assert-UpdatePlainPath([string]$Path) {
    $cursor=$Path
    while($cursor){
        if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
            if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw [IO.IOException]::new('Automatic replacement cannot use linked or redirected application paths. Extract the verified package to a regular local folder.')
            }
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break}
        $cursor=$parent
    }
}
function Get-UpdateCacheDirectory([string]$Installation,[string]$Kind) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$bytes=$hash.ComputeHash($script:updateUtf8.GetBytes($Installation.TrimEnd('\').ToUpperInvariant()))}finally{$hash.Dispose()}
    $key=([BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()).Substring(0,16)
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if($env:LOCALAPPDATA){$local=$env:LOCALAPPDATA}
    if(-not $local){throw [IO.IOException]::new('The local application-data folder is unavailable.')}
    return Join-Path $local ('HWID Checker\Updates\'+$key+'-'+$Kind.ToLowerInvariant())
}
function Get-UpdateHash([string]$Path) {
    $hash=[Security.Cryptography.SHA256]::Create()
    $stream=$null
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
    }finally{if($stream){$stream.Dispose()};$hash.Dispose()}
}
function Write-UpdateJson([string]$Path,$Value) {
    $parent=[IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary=$Path+'.pending-'+[guid]::NewGuid().ToString('N')
    try{
        [IO.File]::WriteAllText($temporary,(ConvertTo-Json -InputObject $Value -Depth 12 -Compress),$script:updateUtf8)
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[NullString]::Value)}
        else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Read-UpdateJson([string]$Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -le 0 -or $stream.Length -gt 256KB){throw [IO.InvalidDataException]::new('Update metadata has an invalid size.')}
        $bytes=New-Object byte[] ([int]$stream.Length)
        $position=0
        while($position -lt $bytes.Length){
            $read=$stream.Read($bytes,$position,$bytes.Length-$position)
            if(-not $read){throw [IO.EndOfStreamException]::new('Update metadata is incomplete.')}
            $position+=$read
        }
        $offset=0
        if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){$offset=3}
        $value=ConvertFrom-Json -InputObject $script:updateUtf8.GetString($bytes,$offset,$bytes.Length-$offset)
        if($value -isnot [pscustomobject]){throw [IO.InvalidDataException]::new('Update metadata must be a JSON object.')}
        return $value
    }finally{$stream.Dispose()}
}
function New-UpdateResult([string]$State,[string]$Current,[string]$Latest,[string]$Release,[string]$Message,[string]$Stage='') {
    return [ordered]@{
        state=$State;currentVersion=$Current;latestVersion=$Latest;releaseUrl=$Release;message=$Message
        stageDirectory=$Stage;component=$Component;installDirectory=$InstallDirectory;desktopVersion=$Latest;batVersion=$null
    }
}
function Open-UpdateGate([string]$Path) {
    try{return [IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{
        if(($_.Exception.HResult -band 65535) -in @(32,33)){return $null}
        throw
    }
}
function Test-UpdateUrl([uri]$Uri) {
    return $Uri.Scheme -ceq 'https' -and $Uri.IsDefaultPort -and -not $Uri.UserInfo -and $Uri.Host -in @(
        'api.github.com','github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com')
}
function Receive-UpdateBytes([string]$Url,[long]$Maximum,[string]$Destination='',[int]$Seconds=25) {
    Add-Type -AssemblyName System.Net.Http
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect=$false
    $client=[Net.Http.HttpClient]::new($handler)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('HWID-Checker-Updater/1.3.0')
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept','application/vnd.github+json')
    $timer=[Threading.CancellationTokenSource]::new()
    $timer.CancelAfter([TimeSpan]::FromSeconds($Seconds))
    $response=$null;$input=$null;$output=$null
    try{
        $uri=[uri]$Url
        for($redirect=0;$redirect -le 5;$redirect++){
            if(-not (Test-UpdateUrl $uri)){throw [IO.InvalidDataException]::new('The release download redirected outside the supported GitHub hosts.')}
            $response=$client.GetAsync($uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$timer.Token).GetAwaiter().GetResult()
            if([int]$response.StatusCode -in @(301,302,303,307,308)){
                if($redirect -eq 5 -or $null -eq $response.Headers.Location){throw [IO.IOException]::new('The release download redirected too many times.')}
                $uri=[uri]::new($uri,$response.Headers.Location)
                $response.Dispose();$response=$null
                continue
            }
            break
        }
        if([int]$response.StatusCode -in @(403,429)){throw [IO.IOException]::new('GitHub temporarily limited update checks. Try again later.')}
        if(-not $response.IsSuccessStatusCode){throw [IO.IOException]::new('GitHub returned HTTP '+[int]$response.StatusCode+'. Try again later.')}
        if($response.Content.Headers.ContentLength -gt $Maximum){throw [IO.InvalidDataException]::new('The update response exceeds its size limit.')}
        if($Destination){$output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)}
        else{$output=[IO.MemoryStream]::new()}
        $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $buffer=New-Object byte[] 65536
        $total=0L
        while(($read=$input.ReadAsync($buffer,0,$buffer.Length,$timer.Token).GetAwaiter().GetResult()) -gt 0){
            $total+=$read
            if($total -gt $Maximum){throw [IO.InvalidDataException]::new('The update response exceeds its size limit.')}
            $output.Write($buffer,0,$read)
        }
        if($response.Content.Headers.ContentLength -ne $null -and $total -ne $response.Content.Headers.ContentLength){
            throw [IO.EndOfStreamException]::new('The release download ended early.')
        }
        if($Destination){$output.Flush();return $total}
        return ,$output.ToArray()
    }finally{
        if($input){$input.Dispose()};if($output){$output.Dispose()};if($response){$response.Dispose()}
        $timer.Dispose();$client.Dispose();$handler.Dispose()
    }
}
function Select-UpdateRelease($Releases,[version]$Current) {
    $choices=New-Object 'System.Collections.Generic.List[object]'
    foreach($release in $Releases){
        $tagMatch=[regex]::Match([string]$release.tag_name,'\Adesktop-v(.+)\z')
        if($release.draft -ne $false -or $release.prerelease -ne $false -or -not $tagMatch.Success){continue}
        try{$version=ConvertTo-UpdateVersion $tagMatch.Groups[1].Value}catch{continue}
        if($version -le $Current){continue}
        $name='HWID-Checker-Desktop-'+$version.ToString(3)+'-win-x64.zip'
        $assets=@($release.assets | Where-Object { $_.name -ceq $name })
        if($assets.Count -ne 1){continue}
        $asset=$assets[0]
        $url='https://github.com/'+$script:updateRepository+'/releases/download/desktop-v'+$version.ToString(3)+'/'+$name
        if($asset.state -ne 'uploaded' -or $asset.digest -cnotmatch '\Asha256:([a-fA-F0-9]{64})\z' -or
            $asset.browser_download_url -cne $url -or ($asset.size -isnot [int] -and $asset.size -isnot [long]) -or
            $asset.size -le 0 -or $asset.size -gt $script:updateMaximumDownload){continue}
        $choices.Add([pscustomobject]@{
            Version=$version.ToString(3);NumericVersion=$version;AssetName=$name;AssetSize=[long]$asset.size
            Digest=([string]$asset.digest).Substring(7).ToLowerInvariant();DownloadUrl=$url
            ReleaseUrl='https://github.com/'+$script:updateRepository+'/releases/tag/desktop-v'+$version.ToString(3)
        })
    }
    return $choices | Sort-Object NumericVersion -Descending | Select-Object -First 1
}
function Find-UpdateRelease([version]$Current) {
    $all=New-Object 'System.Collections.Generic.List[object]'
    for($page=1;$page -le 5;$page++){
        $url='https://api.github.com/repos/'+$script:updateRepository+'/releases?per_page=100&page='+$page
        $bytes=Receive-UpdateBytes $url 4MB
        $json=$script:updateUtf8.GetString($bytes)
        if($json -notmatch '^\s*\['){throw [IO.InvalidDataException]::new('GitHub did not return a release list.')}
        $releases=@(ConvertFrom-Json -InputObject $json)
        # Windows PowerShell 5.1 emits a top-level JSON array as one nested array
        # object, which made foreach treat every release as a single concatenated
        # record and reject the version. Unwrap exactly one level when present.
        if($releases.Count -eq 1 -and $releases[0] -is [System.Collections.IEnumerable] -and $releases[0] -isnot [string]){
            $releases=@($releases[0])
        }
        foreach($release in $releases){$all.Add($release)}
        if($releases.Count -lt 100){return Select-UpdateRelease $all.ToArray() $Current}
    }
    throw [IO.InvalidDataException]::new('The release list exceeds the automatic check limit. Open the GitHub releases page.')
}
function Assert-UpdateRelativePath([string]$Path) {
    if(-not $Path -or $Path.Length -gt 512 -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path -match '[\p{Cc}:<>"|?*]'){
        throw [IO.InvalidDataException]::new('The update contains an invalid archive path.')
    }
    foreach($part in $Path.Split('/')){
        if(-not $part -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part.Split('.')[0].TrimEnd(' ') -match '\A(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|(?:COM|LPT)[1-9\u00B9\u00B2\u00B3])\z'){
            throw [IO.InvalidDataException]::new('The update contains an invalid archive path component.')
        }
    }
}
function Test-UpdateManagedFile([string]$Path) {
    if($Path -cin @('HWID Checker.exe','hwid.bat','Start-HWID.ps1','Update-HWID.ps1','README.md')){return $true}
    return $Path.StartsWith('notices/',[StringComparison]::Ordinal) -and ($Path.EndsWith('.txt',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($Path) -ceq 'LICENSE')
}
function Read-UpdateChecksums([string]$Text,[switch]$Installed) {
    $hashes=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($line in ($Text -split '\r?\n')){
        if(-not $line){continue}
        if($line -cnotmatch '\A([a-fA-F0-9]{64})  (.+)\z'){throw [IO.InvalidDataException]::new('The package checksum list is invalid.')}
        $hash=$Matches[1].ToLowerInvariant();$name=$Matches[2]
        Assert-UpdateRelativePath $name
        $supported=if($Installed){Test-UpdateInstalledFile $name}else{Test-UpdateManagedFile $name}
        if(-not $supported -or $hashes.ContainsKey($name)){throw [IO.InvalidDataException]::new('The package checksum list contains an unsupported or duplicate file.')}
        $hashes.Add($name,$hash)
    }
    return ,$hashes
}
function Read-UpdatePackage([string]$Archive,[string]$Payload,[string]$Version) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $expected=ConvertTo-UpdateVersion $Version
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try{
        if($zip.Entries.Count -lt 6 -or $zip.Entries.Count -gt 512){throw [IO.InvalidDataException]::new('The update has an invalid number of archive entries.')}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $files=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        $expanded=0L
        foreach($entry in $zip.Entries){
            $directory=$entry.FullName.EndsWith('/')
            $name=$entry.FullName.TrimEnd('/')
            Assert-UpdateRelativePath $name
            if(-not $seen.Add($name)){throw [IO.InvalidDataException]::new('The update contains duplicate archive paths.')}
            $unix=($entry.ExternalAttributes -shr 16) -band 61440
            if(($entry.ExternalAttributes -band 1024) -ne 0 -or $unix -notin @(0,16384,32768) -or
                ($unix -eq 16384 -and -not $directory) -or ($unix -eq 32768 -and $directory)){
                throw [IO.InvalidDataException]::new('The update contains a linked or unsupported archive entry.')
            }
            if($directory){
                if($entry.Length -ne 0 -or ($name -cne $script:updateArchiveRoot -and -not $name.StartsWith($script:updateArchiveRoot+'/notices',[StringComparison]::Ordinal))){
                    throw [IO.InvalidDataException]::new('The update contains an unexpected directory.')
                }
                continue
            }
            $prefix=$script:updateArchiveRoot+'/'
            if(-not $name.StartsWith($prefix,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('The update has an unexpected package root.')}
            $relative=$name.Substring($prefix.Length)
            if($relative -cne 'SHA256SUMS.txt' -and -not (Test-UpdateManagedFile $relative)){throw [IO.InvalidDataException]::new('The update contains an unsupported application file.')}
            $expanded+=$entry.Length
            if($entry.Length -le 0 -or $entry.Length -gt $script:updateMaximumDownload -or $expanded -gt $script:updateMaximumExpanded){
                throw [IO.InvalidDataException]::new('The update exceeds the expanded package size limit.')
            }
            $files.Add($relative,$entry)
        }
        foreach($path in $files.Keys){
            foreach($other in $seen){
                if($other.StartsWith($script:updateArchiveRoot+'/'+$path+'/',[StringComparison]::OrdinalIgnoreCase)){
                    throw [IO.InvalidDataException]::new('The update contains a file/directory collision.')
                }
            }
        }
        foreach($required in @('HWID Checker.exe','hwid.bat','Start-HWID.ps1','Update-HWID.ps1','README.md','SHA256SUMS.txt')){
            if(-not $files.ContainsKey($required)){throw [IO.InvalidDataException]::new('The update is missing '+$required+'.')}
        }
        $checksum=$files['SHA256SUMS.txt']
        if($checksum.Length -gt 256KB){throw [IO.InvalidDataException]::new('The package checksum list is too large.')}
        $reader=[IO.StreamReader]::new($checksum.Open(),$script:updateUtf8,$true)
        try{$hashes=Read-UpdateChecksums $reader.ReadToEnd()}finally{$reader.Dispose()}
        if($hashes.Count -ne $files.Count-1){throw [IO.InvalidDataException]::new('The package checksum list does not cover every file.')}
        if([IO.Directory]::Exists($Payload)){throw [IO.IOException]::new('The update extraction folder already exists.')}
        [void][IO.Directory]::CreateDirectory($Payload)
        $items=New-Object 'System.Collections.Generic.List[object]'
        foreach($relative in ($files.Keys | Sort-Object)){
            if($relative -ceq 'SHA256SUMS.txt'){continue}
            if(-not $hashes.ContainsKey($relative)){throw [IO.InvalidDataException]::new('An application file has no checksum.')}
            $destination=Join-Path $Payload $relative.Replace('/','\')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            $input=$files[$relative].Open()
            $output=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{
                $buffer=New-Object byte[] 65536
                $total=0L
                while(($count=$input.Read($buffer,0,$buffer.Length)) -gt 0){
                    $total+=$count
                    if($total -gt $files[$relative].Length){throw [IO.InvalidDataException]::new('An archive entry exceeds its declared size.')}
                    $output.Write($buffer,0,$count)
                }
                if($total -ne $files[$relative].Length){throw [IO.InvalidDataException]::new('An archive entry is incomplete.')}
                $output.Flush()
            }finally{$input.Dispose();$output.Dispose()}
            if((Get-UpdateHash $destination) -cne $hashes[$relative]){throw [IO.InvalidDataException]::new('An application file failed SHA-256 verification.')}
            $items.Add([pscustomobject]@{path=$relative;sha256=$hashes[$relative];size=$files[$relative].Length})
        }
        $fileInfo=[Diagnostics.FileVersionInfo]::GetVersionInfo(('\\?\'+(Join-Path $Payload 'HWID Checker.exe')))
        $fileVersion=[version]::new($fileInfo.FileMajorPart,$fileInfo.FileMinorPart,$fileInfo.FileBuildPart)
        if($fileVersion -ne $expected -or $fileInfo.ProductVersion -cnotmatch ('\A'+[regex]::Escape($Version)+'(?:\+[0-9A-Za-z.-]+)?\z')){
            throw [IO.InvalidDataException]::new('The packaged desktop version does not match the release tag.')
        }
        $bat=[IO.File]::ReadAllText((Join-Path $Payload 'hwid.bat'),$script:updateUtf8)
        $scanner=[regex]::Match($bat,"(?m)Version\s*=\s*'(?<version>[0-9]+(?:\.[0-9]+)+)'")
        if(-not $scanner.Success -or [regex]::Matches($bat,'(?m)^# POWERSHELL_START\r?$').Count -ne 1){
            throw [IO.InvalidDataException]::new('The package does not contain the expected HWID scanner.')
        }
        $updater=[IO.File]::ReadAllText((Join-Path $Payload 'Update-HWID.ps1'),$script:updateUtf8)
        if($updater -cnotmatch ("(?m)^# HWID_PACKAGE_VERSION = '"+[regex]::Escape($Version)+"'\r?$")){
            throw [IO.InvalidDataException]::new('The packaged updater version does not match the release tag.')
        }
        return [pscustomobject]@{Files=$items.ToArray();BatVersion=$scanner.Groups['version'].Value;DesktopVersion=$Version}
    }finally{$zip.Dispose()}
}
function Get-InstalledUpdateVersion([string]$Installation) {
    $path=Join-Path $Installation 'HWID Checker.exe'
    if(-not [IO.File]::Exists($path)){return $null}
    $info=[Diagnostics.FileVersionInfo]::GetVersionInfo(('\\?\'+$path))
    if([string]::IsNullOrWhiteSpace($info.FileVersion)){return $null}
    return [version]::new($info.FileMajorPart,$info.FileMinorPart,$info.FileBuildPart)
}
function Assert-UpdateNewerThanInstalled([string]$Installation,[string]$Candidate,[string]$Current,[string]$Kind='Package',[string]$BatVersion='') {
    $latest=ConvertTo-UpdateVersion $Candidate
    if($latest -le (ConvertTo-UpdateVersion $Current)){throw [IO.InvalidDataException]::new('The update would not advance the current package version.')}
    $installedScript=Join-Path $Installation 'Update-HWID.ps1'
    if([IO.File]::Exists($installedScript)){
        $text=[IO.File]::ReadAllText($installedScript,$script:updateUtf8)
        $stamp=[regex]::Match($text,"(?m)^# HWID_PACKAGE_VERSION = '(?<version>[^']+)'\r?$")
        if($stamp.Success -and (($latest -lt (ConvertTo-UpdateVersion $stamp.Groups['version'].Value)) -or
            ($Kind -eq 'Bat' -and $latest -eq (ConvertTo-UpdateVersion $stamp.Groups['version'].Value)))){
            throw [IO.InvalidDataException]::new('The installed updater is already this version or newer.')
        }
    }
    $version=Get-InstalledUpdateVersion $Installation
    if($null -ne $version){
        if($latest -le $version){
            if((ConvertTo-UpdateVersion $Current) -lt $version){
                # The files on disk are newer than the running application: the
                # update was already applied. Say so instead of reporting a failure.
                throw [IO.InvalidDataException]::new(('The update is already installed on disk (desktop '+$version.ToString(3)+'). Restart the application to load it.'))
            }
            throw [IO.InvalidDataException]::new('The installed desktop application is already this version or newer.')
        }
    }
    $installedBat=Join-Path $Installation 'hwid.bat'
    if($BatVersion -and [IO.File]::Exists($installedBat)){
        if((Get-Item -LiteralPath $installedBat).Length -gt 4MB){throw [IO.InvalidDataException]::new('The installed scanner is too large for automatic replacement.')}
        $scanner=[regex]::Match([IO.File]::ReadAllText($installedBat,$script:updateUtf8),"(?m)Version\s*=\s*'(?<version>[0-9]+(?:\.[0-9]+)+)'")
        if($scanner.Success -and [version]$scanner.Groups['version'].Value -gt [version]$BatVersion){
            throw [IO.InvalidDataException]::new('The installed scanner is newer than the scanner in this package. Automatic replacement would downgrade it.')
        }
    }
}
function Prepare-HwidUpdate([string]$Installation,[string]$Current,[string]$Kind,$Release,[string]$Cache) {
    Assert-UpdatePlainPath $Installation
    if(-not [IO.Directory]::Exists($Installation)){throw [IO.DirectoryNotFoundException]::new('The application folder no longer exists.')}
    Assert-UpdateNewerThanInstalled $Installation $Release.Version $Current $Kind
    $probe=Join-Path $Installation ('.hwid-update-probe-'+[guid]::NewGuid().ToString('N'))
    try{
        $test=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $test.Dispose()
    }finally{if([IO.File]::Exists($probe)){[IO.File]::Delete($probe)}}
    $stage=Join-Path $Cache ('stage-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $archive=Join-Path $stage 'package.zip'
    $downloaded=Receive-UpdateBytes $Release.DownloadUrl $script:updateMaximumDownload $archive 300
    if($downloaded -ne $Release.AssetSize -or (Get-UpdateHash $archive) -cne $Release.Digest){
        throw [IO.InvalidDataException]::new('The downloaded archive failed its GitHub SHA-256 or length verification.')
    }
    $package=Read-UpdatePackage $archive (Join-Path $stage 'payload') $Release.Version
    Assert-UpdateNewerThanInstalled $Installation $Release.Version $Current $Kind $package.BatVersion
    $manifest=[ordered]@{
        schema=1;installDirectory=$Installation;component=$Kind;currentVersion=$Current;latestVersion=$Release.Version
        desktopVersion=$package.DesktopVersion;batVersion=$package.BatVersion;releaseUrl=$Release.ReleaseUrl
        assetName=$Release.AssetName;assetDigest=$Release.Digest;assetSize=$Release.AssetSize;files=@($package.Files)
    }
    Write-UpdateJson (Join-Path $stage 'ready.json') $manifest
    $result=New-UpdateResult 'ready' $Current $Release.Version $Release.ReleaseUrl 'The update is verified and ready to install after this app closes.' $stage
    $result.batVersion=$package.BatVersion
    return $result
}
function Wait-UpdateProcess([int]$ProcessId,[long]$StartTicks) {
    if($ProcessId -eq 0 -and $StartTicks -eq 0){return}
    if($ProcessId -le 0 -or $StartTicks -le 0 -or $ProcessId -eq $PID){throw [IO.InvalidDataException]::new('The update wait-process identity is invalid.')}
    $process=$null
    try{
        try{$process=[Diagnostics.Process]::GetProcessById($ProcessId)}catch [ArgumentException]{return}
        try{$actualTicks=$process.StartTime.ToUniversalTime().Ticks}catch [InvalidOperationException]{
            if($process.HasExited){return}
            throw
        }
        if($actualTicks -ne $StartTicks){throw [IO.InvalidDataException]::new('The original application process identity has changed.')}
        if(-not $process.WaitForExit(120000)){throw [IO.IOException]::new('The application is still open. Close it before applying the prepared update.')}
    }finally{if($process){$process.Dispose()}}
}
function Install-UpdateFile([string]$Source,[string]$Destination,[string]$Backup) {
    if([IO.File]::Exists($Destination)){[IO.File]::Replace($Source,$Destination,$Backup)}
    else{[IO.File]::Move($Source,$Destination)}
}
function Test-UpdateInstalledFile([string]$Name) {
    $relative=$Name.Replace('\','/')
    Assert-UpdateRelativePath $relative
    if($relative -ceq 'README.md'){return $false}
    return $relative -cin @('DESKTOP-README.md','HWID-INSTALLED-SHA256SUMS.txt') -or (Test-UpdateManagedFile $relative)
}
function Restore-UpdateTransaction([string]$Installation,[string]$Transaction,$Record) {
    if($Record.schema -ne 1 -or $Record.state -cne 'active' -or
        -not [string]::Equals($Record.installDirectory,$Installation,[StringComparison]::OrdinalIgnoreCase) -or
        $Record.component -cnotin @('Package','Bat') -or @($Record.files).Count -gt 513){
        throw [IO.InvalidDataException]::new('An interrupted update has an invalid recovery record.')
    }
    [void](ConvertTo-UpdateVersion $Record.version)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $Record.files){
        if(-not (Test-UpdateInstalledFile $entry.destination) -or -not $seen.Add($entry.destination) -or
            $entry.backup -cnotmatch '\A[0-9]+\.previous\z' -or $entry.sha256 -cnotmatch '\A[a-f0-9]{64}\z' -or
            $entry.existed -isnot [bool] -or ($entry.existed -and $entry.previous -cnotmatch '\A[a-f0-9]{64}\z') -or
            ($Record.component -ceq 'Bat' -and $entry.destination -cnotin @('hwid.bat','Start-HWID.ps1','Update-HWID.ps1','HWID-INSTALLED-SHA256SUMS.txt'))){
            throw [IO.InvalidDataException]::new('An interrupted update contains an unsupported recovery file.')
        }
    }
    for($index=@($Record.files).Count-1;$index -ge 0;$index--){
        $entry=$Record.files[$index]
        $target=Join-Path $Installation $entry.destination
        $backup=Join-Path $Transaction $entry.backup
        Assert-UpdatePlainPath $target
        Assert-UpdatePlainPath $backup
        $targetHash=if([IO.File]::Exists($target)){Get-UpdateHash $target}else{$null}
        if($targetHash -and $targetHash -cne $entry.sha256 -and $targetHash -cne $entry.previous){
            throw [IO.IOException]::new('An application file changed outside the interrupted update. Keep its recovery backups.')
        }
        if($entry.existed -and [IO.File]::Exists($backup)){
            if((Get-UpdateHash $backup) -cne $entry.previous){throw [IO.InvalidDataException]::new('A previous application backup changed.')}
            if([IO.File]::Exists($target)){[IO.File]::Replace($backup,$target,[NullString]::Value)}
            else{[IO.File]::Move($backup,$target)}
            if((Get-UpdateHash $target) -cne $entry.previous){throw [IO.IOException]::new('A previous application file could not be restored.')}
        }elseif(-not $entry.existed -and $targetHash){[IO.File]::Delete($target)}
        elseif($entry.existed -and $targetHash -cne $entry.previous){throw [IO.IOException]::new('A previous application file needs manual recovery.')}
    }
    $Record.state='recovered'
    Write-UpdateJson (Join-Path $Transaction 'transaction.json') $Record
    Write-UpdateJson (Join-Path $Transaction 'recovered.json') @{version=$Record.version;state='recovered'}
}
function Restore-InterruptedUpdates([string]$Installation) {
    foreach($directory in [IO.Directory]::GetDirectories($Installation,'.hwid-update-*',[IO.SearchOption]::TopDirectoryOnly)){
        if([IO.Path]::GetFileName($directory) -cnotmatch '\A\.hwid-update-[a-f0-9]{32}\z'){continue}
        Assert-UpdatePlainPath $directory
        $path=Join-Path $directory 'transaction.json'
        if(-not [IO.File]::Exists($path)){continue}
        $record=Read-UpdateJson $path
        if($record.state -ceq 'active'){Restore-UpdateTransaction $Installation $directory $record}
    }
}
function Invoke-UpdateTransaction([string]$Installation,[string]$Payload,$Files,[string]$Kind,[string]$Version) {
    $transaction=Join-Path $Installation ('.hwid-update-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($transaction)
    $journal=New-Object 'System.Collections.Generic.List[object]'
    $complete=$false
    $record=[pscustomobject]@{schema=1;installDirectory=$Installation;component=$Kind;version=$Version;state='active';files=@()}
    try{
        $installFiles=New-Object 'System.Collections.Generic.List[object]'
        foreach($file in $Files){
            if($Kind -eq 'Bat' -and $file.path -cnotin @('hwid.bat','Start-HWID.ps1','Update-HWID.ps1')){continue}
            if(-not (Test-UpdateManagedFile $file.path)){throw [IO.InvalidDataException]::new('The update attempted an unsupported application path.')}
            $installFiles.Add($file)
        }
        $installedHashes=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($name in @('HWID Checker.exe','hwid.bat','Start-HWID.ps1','Update-HWID.ps1','DESKTOP-README.md')){
            $existing=Join-Path $Installation $name
            if([IO.File]::Exists($existing)){Assert-UpdatePlainPath $existing;$installedHashes[$name]=Get-UpdateHash $existing}
        }
        foreach($file in $installFiles){
            $name=if($file.path -ceq 'README.md'){'DESKTOP-README.md'}else{$file.path}
            $installedHashes[$name]=$file.sha256
        }
        $checksumName='HWID-INSTALLED-SHA256SUMS.txt'
        $checksumSource=Join-Path $Payload $checksumName
        $lines=@($installedHashes.Keys | Sort-Object | ForEach-Object {$installedHashes[$_]+'  '+$_})
        [IO.File]::WriteAllText($checksumSource,($lines -join [Environment]::NewLine)+[Environment]::NewLine,$script:updateUtf8)
        $installFiles.Add([pscustomobject]@{path=$checksumName;sha256=(Get-UpdateHash $checksumSource);size=([IO.FileInfo]$checksumSource).Length})
        foreach($file in $installFiles){
            $name=if($file.path -ceq 'README.md'){'DESKTOP-README.md'}else{$file.path.Replace('/','\')}
            $destination=Join-Path $Installation $name
            Assert-UpdatePlainPath $destination
            $source=Join-Path $Payload $file.path.Replace('/','\')
            if((Get-UpdateHash $source) -cne $file.sha256){throw [IO.InvalidDataException]::new('A prepared application file changed before installation.')}
            $next=Join-Path $transaction ($journal.Count.ToString()+'.new')
            $backup=Join-Path $transaction ($journal.Count.ToString()+'.previous')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [IO.File]::Copy($source,$next,$false)
            if((Get-UpdateHash $next) -cne $file.sha256){throw [IO.InvalidDataException]::new('An application replacement failed staging verification.')}
            $existed=[IO.File]::Exists($destination)
            $previous=if($existed){Get-UpdateHash $destination}else{$null}
            # Record intent before ReplaceFile, which may move the old file before reporting an error.
            $entry=[pscustomobject]@{destination=$name;backup=[IO.Path]::GetFileName($backup);existed=$existed;previous=$previous;sha256=$file.sha256;applied=$false}
            $journal.Add($entry)
            $record.files=$journal.ToArray()
            Write-UpdateJson (Join-Path $transaction 'transaction.json') $record
            Install-UpdateFile $next $destination $backup
            $entry.applied=$true
            if((Get-UpdateHash $destination) -cne $file.sha256){throw [IO.InvalidDataException]::new('An installed application file failed verification.')}
        }
        $record.state='committed'
        Write-UpdateJson (Join-Path $transaction 'transaction.json') $record
        $complete=$true
    }catch{
        $failure=$_
        $record.files=$journal.ToArray();$record.state='active'
        try{Restore-UpdateTransaction $Installation $transaction $record}
        catch{throw [IO.IOException]::new('Update failed and some application files need recovery. Keep the backups in '+$transaction+'. '+$failure.Exception.Message)}
        throw [IO.IOException]::new('Update failed. Previous application files were restored. '+$failure.Exception.Message)
    }finally{
        # Leave the exact owned backup/journal directory for recovery. It contains application files only.
        if($complete){try{Write-UpdateJson (Join-Path $transaction 'completed.json') @{version=$Version;state='updated'}}catch{}}
    }
}
function Apply-HwidUpdate([string]$Installation,[string]$Current,[string]$Kind,[string]$Stage,[int]$ProcessId,[long]$StartTicks,[bool]$Restart) {
    $stagePath=ConvertTo-UpdateDirectory $Stage
    $cache=ConvertTo-UpdateDirectory (Get-UpdateCacheDirectory $Installation $Kind)
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($stagePath),$cache,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($stagePath) -cnotmatch '\Astage-[a-f0-9]{32}\z'){
        throw [IO.InvalidDataException]::new('The prepared update is outside this installation cache.')
    }
    Assert-UpdatePlainPath $stagePath
    $manifest=Read-UpdateJson (Join-Path $stagePath 'ready.json')
    if($manifest.schema -ne 1 -or $manifest.component -cne $Kind -or
        -not [string]::Equals($manifest.installDirectory,$Installation,[StringComparison]::OrdinalIgnoreCase) -or
        $manifest.currentVersion -cne $Current -or $manifest.assetDigest -cnotmatch '\A[a-f0-9]{64}\z' -or
        $manifest.assetSize -le 0 -or $manifest.assetSize -gt $script:updateMaximumDownload){
        throw [IO.InvalidDataException]::new('The prepared update does not match this application folder, component or version.')
    }
    $latest=(ConvertTo-UpdateVersion $manifest.latestVersion).ToString(3)
    if($manifest.desktopVersion -cne $latest -or $manifest.assetName -cne ('HWID-Checker-Desktop-'+$latest+'-win-x64.zip') -or
        $manifest.releaseUrl -cne ('https://github.com/'+$script:updateRepository+'/releases/tag/desktop-v'+$latest)){
        throw [IO.InvalidDataException]::new('The prepared release identity is invalid.')
    }
    $archive=Join-Path $stagePath 'package.zip'
    $stream=[IO.File]::Open($archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -ne $manifest.assetSize -or (Get-UpdateHash $archive) -cne $manifest.assetDigest){
            throw [IO.InvalidDataException]::new('The prepared release archive changed or is incomplete.')
        }
        $verified=Join-Path $stagePath ('verify-'+[guid]::NewGuid().ToString('N'))
        $package=Read-UpdatePackage $archive $verified $latest
        if($manifest.batVersion -cne $package.BatVersion -or @($manifest.files).Count -ne $package.Files.Count){
            throw [IO.InvalidDataException]::new('The prepared file manifest changed.')
        }
        foreach($file in $package.Files){
            $previous=@($manifest.files | Where-Object { $_.path -ceq $file.path })
            if($previous.Count -ne 1 -or $previous[0].sha256 -cne $file.sha256 -or $previous[0].size -ne $file.size){
                throw [IO.InvalidDataException]::new('The prepared application hashes do not match the archive.')
            }
        }
        Wait-UpdateProcess $ProcessId $StartTicks
        Assert-UpdatePlainPath $Installation
        $gate=Open-UpdateGate (Join-Path $Installation '.hwid-update.lock')
        if(-not $gate){return New-UpdateResult 'busy' $Current $latest $manifest.releaseUrl 'Another update is applying to this application folder.' $stagePath}
        try{
            Restore-InterruptedUpdates $Installation
            Assert-UpdateNewerThanInstalled $Installation $latest $Current $Kind $package.BatVersion
            Invoke-UpdateTransaction $Installation $verified $package.Files $Kind $latest
        }finally{$gate.Dispose()}
    }finally{$stream.Dispose()}
    $result=New-UpdateResult 'updated' $Current $latest $manifest.releaseUrl 'The verified application files were updated. Saved reports and folder preferences are available.' $stagePath
    $result.batVersion=$package.BatVersion
    if($Restart){
        try{
            $path=if($Kind -eq 'Package'){Join-Path $Installation 'HWID Checker.exe'}else{Join-Path $Installation 'hwid.bat'}
            $start=[Diagnostics.ProcessStartInfo]::new($path)
            $start.UseShellExecute=$true;$start.WorkingDirectory=$Installation
            $process=[Diagnostics.Process]::Start($start)
            if($process){$process.Dispose()}
        }catch{$result.message='The update completed. Open the application manually to restart it.'}
    }
    return $result
}
function Get-PreparedUpdateResult([string]$Path,[string]$Installation,[string]$Current,[string]$Kind,[string]$Cache) {
    if(-not $Path -or -not [IO.File]::Exists($Path)){return $null}
    try{
        $result=Read-UpdateJson $Path
        if($result.state -cne 'ready' -or $result.component -cne $Kind -or $result.currentVersion -cne $Current -or
            -not [string]::Equals($result.installDirectory,$Installation,[StringComparison]::OrdinalIgnoreCase)){return $null}
        $stage=ConvertTo-UpdateDirectory $result.stageDirectory
        if(-not [string]::Equals([IO.Path]::GetDirectoryName($stage),$Cache,[StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($stage) -cnotmatch '\Astage-[a-f0-9]{32}\z'){return $null}
        Assert-UpdatePlainPath $stage
        $manifest=Read-UpdateJson (Join-Path $stage 'ready.json')
        Assert-UpdateNewerThanInstalled $Installation $manifest.latestVersion $Current $Kind $manifest.batVersion
        if($manifest.schema -ne 1 -or $manifest.component -cne $Kind -or $manifest.currentVersion -cne $Current -or
            -not [string]::Equals($manifest.installDirectory,$Installation,[StringComparison]::OrdinalIgnoreCase) -or
            $manifest.latestVersion -cne $result.latestVersion -or $manifest.assetDigest -cnotmatch '\A[a-f0-9]{64}\z' -or
            $manifest.assetSize -le 0 -or $manifest.assetSize -gt $script:updateMaximumDownload){return $null}
        $zip=Join-Path $stage 'package.zip'
        if((Get-Item -LiteralPath $zip -ErrorAction Stop).Length -ne $manifest.assetSize -or
            (Get-UpdateHash $zip) -cne $manifest.assetDigest){return $null}
        $ready=New-UpdateResult 'ready' $Current $manifest.latestVersion $manifest.releaseUrl 'The verified update is already prepared for the next clean exit.' $stage
        $ready.batVersion=$manifest.batVersion
        return $ready
    }catch{return $null}
}
function Invoke-HwidUpdate {
    $current=ConvertTo-UpdateVersion $CurrentVersion
    $installation=ConvertTo-UpdateDirectory $InstallDirectory
    if($Mode -eq 'Apply'){return Apply-HwidUpdate $installation $current.ToString(3) $Component $StageDirectory $WaitProcessId $WaitProcessStartTicks ([bool]$Relaunch)}
    if($Component -eq 'Package'){
        $installed=Get-InstalledUpdateVersion $installation
        if($null -ne $installed -and $installed -gt $current){
            return New-UpdateResult 'restart' $current.ToString(3) $installed.ToString(3) '' ('Desktop '+$installed.ToString(3)+' is installed, and this window is running Desktop '+$current.ToString(3)+'. Close and reopen the app to use the installed version.')
        }
    }
    $cache=Get-UpdateCacheDirectory $installation $Component
    Assert-UpdatePlainPath $cache
    [void][IO.Directory]::CreateDirectory($cache)
    $prepared=Get-PreparedUpdateResult $ResultPath $installation $current.ToString(3) $Component $cache
    $gate=Open-UpdateGate (Join-Path $cache 'update.lock')
    if(-not $gate){
        if($prepared){return $prepared}
        return New-UpdateResult 'busy' $current.ToString(3) '' '' 'An update check or download is already running for this application folder.'
    }
    try{
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        try{$release=Find-UpdateRelease $current}catch{
            if(-not $prepared){throw}
            $prepared.message='The prepared update remains verified. GitHub could not be checked again, so the existing download is retained.'
            return $prepared
        }
        if($null -eq $release){return New-UpdateResult 'current' $current.ToString(3) $current.ToString(3) ('https://github.com/'+$script:updateRepository+'/releases') 'No newer compatible desktop package is published.'}
        if($prepared -and $prepared.latestVersion -ceq $release.Version){return $prepared}
        if($Mode -eq 'Check'){return New-UpdateResult 'available' $current.ToString(3) $release.Version $release.ReleaseUrl 'A newer Windows x64 desktop package is available.'}
        return Prepare-HwidUpdate $installation $current.ToString(3) $Component $release $cache
    }finally{$gate.Dispose()}
}

$result=$null
try{
    if($PSVersionTable.PSVersion -lt [version]'5.1' -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){
        throw [NotSupportedException]::new('The updater requires Windows PowerShell 5.1 or PowerShell 7 in FullLanguage mode.')
    }
    $result=Invoke-HwidUpdate
}catch{
    $message=$_.Exception.Message
    if($message.Length -gt 1600){$message=$message.Substring(0,1600)}
    $result=New-UpdateResult 'error' $CurrentVersion '' '' ('The update could not finish. '+$message)
}
if($ResultPath){
    try{
        $outputPath=[IO.Path]::GetFullPath($ResultPath)
        Write-UpdateJson $outputPath $result
    }catch{
        $result=New-UpdateResult 'error' $CurrentVersion '' '' ('The updater could not publish its result. '+$_.Exception.Message)
    }
}
[Console]::Out.WriteLine((ConvertTo-Json -InputObject $result -Depth 12 -Compress))
if($result.state -eq 'error'){exit 1}
if($result.state -eq 'busy'){exit 2}
