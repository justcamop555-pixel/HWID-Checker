$ErrorActionPreference='Stop'
$script:checks=0
function Assert($Condition,[string]$Message) {
    if(-not $Condition){throw ('FAILED: '+$Message)}
    $script:checks++
    [Console]::WriteLine('PASS: '+$Message)
}
function Assert-Throws([scriptblock]$Action,[string]$Message,[string]$Pattern='') {
    $caught=$null
    try{& $Action | Out-Null}catch{$caught=$_.Exception}
    Assert ($null -ne $caught -and (-not $Pattern -or $caught.Message -match $Pattern)) $Message
}
$source=Join-Path $PSScriptRoot '..\Update-HWID.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'The shared updater parses on this PowerShell runtime'
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
foreach($assignment in $ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -like '$script:update*'},$false)){
    . ([scriptblock]::Create($assignment.Extent.Text))
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Join-Path ([IO.Path]::GetTempPath()) ('HWID-Update-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$previousLocal=$env:LOCALAPPDATA
$env:LOCALAPPDATA=Join-Path $root 'local'
$Component='Package';$CurrentVersion='1.3.0';$InstallDirectory=Join-Path $root ('App & [1] '+[char]0x03a9)
$Mode='Prepare';$StageDirectory='';$ResultPath='';$WaitProcessId=0;$WaitProcessStartTicks=0;$Relaunch=$false
$utf8=[Text.UTF8Encoding]::new($false,$true)
$nl=[Environment]::NewLine
function New-FixtureExecutable([string]$Version) {
    $path=Join-Path $root ($Version+'.exe')
    $type='Fixture'+[guid]::NewGuid().ToString('N')
    $code=Join-Path $root ($Version+'.cs')
    [IO.File]::WriteAllText($code,('using System.Reflection; [assembly:AssemblyVersion("'+$Version+'")] [assembly:AssemblyFileVersion("'+$Version+'")] [assembly:AssemblyInformationalVersion("'+$Version+'+synthetic")] public class '+$type+' {}'))
    $compiler=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:library ('/out:'+$path) $code
    if($LASTEXITCODE -ne 0){throw 'The versioned updater fixture could not be compiled.'}
    return $path
}
function New-FixtureRelease([string]$Version) {
    $name='HWID-Checker-Desktop-'+$Version+'-win-x64.zip'
    return [pscustomobject]@{
        tag_name='desktop-v'+$Version;draft=$false;prerelease=$false
        assets=@([pscustomobject]@{name=$name;state='uploaded';size=123L;digest=('sha256:'+('a'*64));browser_download_url=('https://github.com/'+$script:updateRepository+'/releases/download/desktop-v'+$Version+'/'+$name)})
    }
}
function New-FixtureArchive([string]$Name,[hashtable]$Options=@{}) {
    $files=[ordered]@{
        'HWID Checker.exe'=[IO.File]::ReadAllBytes($fixtureNext)
        'hwid.bat'=$utf8.GetBytes("Version = '3.86'"+$nl+'# POWERSHELL_START'+$nl+'function Get-Test {}')
        'Start-HWID.ps1'=$utf8.GetBytes('# synthetic launcher')
        'Update-HWID.ps1'=$utf8.GetBytes("# HWID_PACKAGE_VERSION = '1.4.0'"+$nl+'# synthetic updater')
        'README.md'=$utf8.GetBytes('Synthetic package guide')
        'notices/LICENSE.txt'=$utf8.GetBytes('Synthetic runtime notice')
    }
    if($Options.ContainsKey('Replace')){foreach($key in $Options.Replace.Keys){$files[$key]=$Options.Replace[$key]}}
    if($Options.Omit){$files.Remove($Options.Omit)}
    $hashes=New-Object 'System.Collections.Generic.List[string]'
    foreach($key in $files.Keys){
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$digest=[BitConverter]::ToString($hash.ComputeHash($files[$key])).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
        $hashes.Add($digest+'  '+$key)
    }
    if($Options.BadHash){$hashes[0]=('0'*64)+'  HWID Checker.exe'}
    if($Options.DuplicateHash){$hashes.Add($hashes[0])}
    $files['SHA256SUMS.txt']=$utf8.GetBytes(($hashes -join $nl)+$nl)
    $path=Join-Path $root ($Name+'.zip')
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($key in $files.Keys){
            $entry=$zip.CreateEntry('HWID Checker Desktop/'+$key)
            if($Options.Symlink -and $key -ceq 'hwid.bat'){$entry.ExternalAttributes=-1577058304}
            $output=$entry.Open()
            try{$output.Write($files[$key],0,$files[$key].Length)}finally{$output.Dispose()}
        }
        if($Options.Extra){
            foreach($extra in $Options.Extra){
                $entry=$zip.CreateEntry($extra)
                $output=$entry.Open()
                try{$output.WriteByte(1)}finally{$output.Dispose()}
            }
        }
    }finally{$zip.Dispose()}
    return $path
}
function New-FixtureInstall([string]$Name) {
    $path=Join-Path $root $Name
    [void][IO.Directory]::CreateDirectory($path)
    [IO.File]::Copy($fixtureCurrent,(Join-Path $path 'HWID Checker.exe'))
    [IO.File]::WriteAllText((Join-Path $path 'hwid.bat'),"Version = '3.85'")
    [IO.File]::WriteAllText((Join-Path $path 'Update-HWID.ps1'),"# HWID_PACKAGE_VERSION = '1.3.0'")
    [void][IO.Directory]::CreateDirectory((Join-Path $path 'HWID-Reports'))
    [IO.File]::WriteAllText((Join-Path $path 'HWID-Reports\synthetic.json'),'synthetic saved report')
    [IO.File]::WriteAllText((Join-Path $path 'README.md'),'user file')
    [IO.File]::WriteAllText((Join-Path $path 'unrelated.txt'),'user file')
    return $path
}
try{
    Assert ((ConvertTo-UpdateVersion '1.10.0') -gt (ConvertTo-UpdateVersion '1.9.0')) 'Version ordering is numeric'
    foreach($value in @('1.3','1.03.0','1.4.0-preview','v1.4.0','-1.4.0','1.4.0.0','999999999999.0.0')){
        Assert-Throws {ConvertTo-UpdateVersion $value} ('Invalid package version is rejected '+$value)
    }
    Assert ($null -eq (Select-UpdateRelease @((New-FixtureRelease '1.1.0')) ([version]'1.3.0'))) 'Published desktop 1.1 cannot downgrade local desktop 1.3'
    Assert ($null -eq (Select-UpdateRelease @((New-FixtureRelease '1.3.0')) ([version]'1.3.0'))) 'An identical release is not an update'
    $candidate=Select-UpdateRelease @((New-FixtureRelease '1.9.0'),(New-FixtureRelease '1.10.0')) ([version]'1.3.0')
    Assert ($candidate.Version -ceq '1.10.0') 'The newest numeric compatible release wins'
    # Windows PowerShell 5.1 nests a top-level JSON array from ConvertFrom-Json,
    # which previously made every release unreadable. Selection must recover.
    $nested=@(@((New-FixtureRelease '1.9.0'),(New-FixtureRelease '1.10.0')))
    $recovered=Select-UpdateRelease $nested ([version]'1.3.0')
    Assert ($recovered.Version -ceq '1.10.0') 'A nested release array still selects the newest compatible release'
    $parseJson='['+((New-FixtureRelease '1.9.0') | ConvertTo-Json -Depth 8 -Compress)+','+((New-FixtureRelease '1.10.0') | ConvertTo-Json -Depth 8 -Compress)+']'
    $parsed=@(ConvertFrom-Json -InputObject $parseJson)
    if($parsed.Count -eq 1 -and $parsed[0] -is [System.Collections.IEnumerable] -and $parsed[0] -isnot [string]){$parsed=@($parsed[0])}
    $fromJson=Select-UpdateRelease @($parsed) ([version]'1.3.0')
    Assert ($fromJson.Version -ceq '1.10.0') 'ConvertFrom-Json release lists select correctly on this runtime'
    foreach($kind in @('draft','prerelease','tag','digest','url','platform','duplicate','size','state')){
        $bad=New-FixtureRelease '9.0.0'
        switch($kind){
            'draft'{$bad.draft=$true}
            'prerelease'{$bad.prerelease=$true}
            'tag'{$bad.tag_name='v9.0.0'}
            'digest'{$bad.assets[0].digest=$null}
            'url'{$bad.assets[0].browser_download_url='https://example.com/file.zip'}
            'platform'{$bad.assets[0].name=$bad.assets[0].name.Replace('win-x64','win-arm64')}
            'duplicate'{$bad.assets=@($bad.assets[0],$bad.assets[0])}
            'size'{$bad.assets[0].size=257MB}
            'state'{$bad.assets[0].state='new'}
        }
        Assert ($null -eq (Select-UpdateRelease @($bad) ([version]'1.3.0'))) ('Incompatible release metadata is excluded '+$kind)
    }
    foreach($uri in @('http://github.com/a','https://github.com.evil.example/a','https://user@github.com/a','https://github.com:444/a','file:///C:/a')){
        Assert (-not (Test-UpdateUrl ([uri]$uri))) ('Download URL is restricted '+$uri)
    }
    Assert (Test-UpdateUrl ([uri]'https://release-assets.githubusercontent.com/a')) 'GitHub asset redirects are supported'
    foreach($path in @('../a','/a','C:/a','a//b','a/../b','a\b','a/file:stream','a/NUL.txt','a/NUL .txt','a/b.','a/b ','a/CONIN$')){
        Assert-Throws {Assert-UpdateRelativePath $path} ('Unsafe ZIP path is rejected '+$path)
    }
    Assert ((ConvertTo-UpdateDirectory ($InstallDirectory+'\child\..')) -ceq $InstallDirectory) 'Install paths normalize before cache identity is calculated'
    Assert ((Get-UpdateCacheDirectory $InstallDirectory 'Bat') -eq (Get-UpdateCacheDirectory $InstallDirectory.ToUpperInvariant() 'Bat')) 'Installation cache identity is case insensitive'
    $fixtureCurrent=New-FixtureExecutable '1.3.0'
    $fixtureNext=New-FixtureExecutable '1.4.0'
    Assert ([Diagnostics.FileVersionInfo]::GetVersionInfo($fixtureNext).ProductVersion -ceq '1.4.0+synthetic') 'The fixture includes real Windows version metadata and a Git-style build suffix'
    $good=New-FixtureArchive 'valid'
    $payload=Join-Path $root 'validated'
    $package=Read-UpdatePackage $good $payload '1.4.0'
    Assert ($package.Files.Count -eq 6 -and $package.BatVersion -ceq '3.86') 'A complete checked release extracts all application files and the actual scanner version'
    Assert-Throws {Read-UpdatePackage $good (Join-Path $root 'wrong-version') '1.5.0'} 'The actual EXE version must match the release tag'
    $variants=@(
        @{Name='bad-hash';Options=@{BadHash=$true}},
        @{Name='duplicate-hash';Options=@{DuplicateHash=$true}},
        @{Name='missing-updater';Options=@{Omit='Update-HWID.ps1'}},
        @{Name='traversal';Options=@{Extra=@('../outside.txt')}},
        @{Name='case-duplicate';Options=@{Extra=@('HWID Checker Desktop/HWID.BAT')}},
        @{Name='symlink';Options=@{Symlink=$true}},
        @{Name='user-report';Options=@{Extra=@('HWID Checker Desktop/HWID-Reports/snapshot.json')}},
        @{Name='collision';Options=@{Extra=@('HWID Checker Desktop/notices/LICENSE.txt/child')}},
        @{Name='bad-bat';Options=@{Replace=@{'hwid.bat'=$utf8.GetBytes('invalid scanner')}}},
        @{Name='bad-stamp';Options=@{Replace=@{'Update-HWID.ps1'=$utf8.GetBytes("# HWID_PACKAGE_VERSION = '1.3.0'")}}}
    )
    foreach($variant in $variants){
        $archive=New-FixtureArchive $variant.Name $variant.Options
        Assert-Throws {Read-UpdatePackage $archive (Join-Path $root ($variant.Name+'-payload')) '1.4.0'} ('Damaged or unsafe package is rejected '+$variant.Name)
    }
    $oldCap=$script:updateMaximumExpanded
    $script:updateMaximumExpanded=10
    try{Assert-Throws {Read-UpdatePackage $good (Join-Path $root 'expanded-overflow') '1.4.0'} 'Expanded-byte limits are enforced before extraction'}finally{$script:updateMaximumExpanded=$oldCap}
    $receiveBody=(Get-Item Function:\Receive-UpdateBytes).ScriptBlock
    function Receive-UpdateBytes([string]$Url,[long]$Maximum,[string]$Destination,[int]$Seconds){
        [IO.File]::Copy($good,$Destination)
        return (Get-Item -LiteralPath $good).Length
    }
    $InstallDirectory=New-FixtureInstall 'apply package'
    $release=Select-UpdateRelease @((New-FixtureRelease '1.4.0')) ([version]'1.3.0')
    $release.AssetSize=(Get-Item -LiteralPath $good).Length
    $release.Digest=Get-UpdateHash $good
    $cache=Get-UpdateCacheDirectory $InstallDirectory 'Package'
    [void][IO.Directory]::CreateDirectory($cache)
    $ready=Prepare-HwidUpdate $InstallDirectory '1.3.0' 'Package' $release $cache
    Assert ($ready.state -ceq 'ready' -and $ready.batVersion -ceq '3.86') 'Prepare returns ready only after archive and application validation'
    $ResultPath=Join-Path $cache 'result.json'
    Write-UpdateJson $ResultPath $ready
    $retained=Get-PreparedUpdateResult $ResultPath $InstallDirectory '1.3.0' 'Package' $cache
    Assert ($retained.state -ceq 'ready' -and $retained.stageDirectory -ceq $ready.stageDirectory) 'A verified ready package can be reused without another download'
    $findBody=(Get-Item Function:\Find-UpdateRelease).ScriptBlock
    function Find-UpdateRelease([version]$Current){return $release}
    $Mode='Check'
    Assert ((Invoke-HwidUpdate).state -ceq 'ready') 'A manual Check preserves the prepared stage for the same latest release'
    function Find-UpdateRelease([version]$Current){throw 'Synthetic offline failure'}
    Assert ((Invoke-HwidUpdate).state -ceq 'ready') 'A temporary offline failure retains a verified prepared package'
    Set-Item Function:\Find-UpdateRelease $findBody
    $Mode='Prepare'
    $held=Open-UpdateGate (Join-Path $cache 'update.lock')
    try{Assert ((Invoke-HwidUpdate).state -ceq 'ready') 'A concurrent updater cannot discard an already prepared package'}finally{$held.Dispose()}
    Assert-Throws {Apply-HwidUpdate $InstallDirectory '1.2.0' 'Package' $ready.stageDirectory 0 0 $false} 'Apply refuses a current-version binding mismatch'
    Assert-Throws {Apply-HwidUpdate $InstallDirectory '1.3.0' 'Bat' $ready.stageDirectory 0 0 $false} 'Apply refuses the wrong component cache'
    $elsewhere=New-FixtureInstall 'wrong target'
    Assert-Throws {Apply-HwidUpdate $elsewhere '1.3.0' 'Package' $ready.stageDirectory 0 0 $false} 'Apply refuses another installation target'
    $manifestPath=Join-Path $ready.stageDirectory 'ready.json'
    $manifest=Read-UpdateJson $manifestPath
    $manifest.files[0].sha256='0'*64
    Write-UpdateJson $manifestPath $manifest
    Assert-Throws {Apply-HwidUpdate $InstallDirectory '1.3.0' 'Package' $ready.stageDirectory 0 0 $false} 'Apply revalidates the ready file hashes against the verified archive'
    $manifest.files=@($package.Files)
    Write-UpdateJson $manifestPath $manifest
    [IO.File]::WriteAllText((Join-Path $ready.stageDirectory 'payload\hwid.bat'),'altered staged file')
    $updated=Apply-HwidUpdate $InstallDirectory '1.3.0' 'Package' $ready.stageDirectory 0 0 $false
    Assert ($updated.state -ceq 'updated') 'A complete package applies from a fresh reverified extraction'
    Assert ((Get-UpdateHash (Join-Path $InstallDirectory 'hwid.bat')) -ceq (Get-UpdateHash (Join-Path $payload 'hwid.bat'))) 'Apply uses the verified archive rather than a changed old extraction'
    Assert ([IO.File]::ReadAllText((Join-Path $InstallDirectory 'README.md')) -ceq 'user file') 'A preexisting user README remains untouched'
    Assert ([IO.File]::ReadAllText((Join-Path $InstallDirectory 'DESKTOP-README.md')) -ceq 'Synthetic package guide') 'The package guide maps to DESKTOP-README.md'
    Assert ([IO.File]::ReadAllText((Join-Path $InstallDirectory 'HWID-Reports\synthetic.json')) -ceq 'synthetic saved report') 'Saved reports stay intact'
    Assert ([IO.File]::ReadAllText((Join-Path $InstallDirectory 'unrelated.txt')) -ceq 'user file') 'Unrelated application-folder files stay intact'
    $installedHashes=Read-UpdateChecksums ([IO.File]::ReadAllText((Join-Path $InstallDirectory 'HWID-INSTALLED-SHA256SUMS.txt'))) -Installed
    Assert ($installedHashes.ContainsKey('DESKTOP-README.md') -and -not $installedHashes.ContainsKey('README.md')) 'Installed checksums use the transformed documentation filename'
    foreach($name in $installedHashes.Keys){
        Assert ((Get-UpdateHash (Join-Path $InstallDirectory $name)) -ceq $installedHashes[$name]) ('Installed checksum verifies '+$name)
    }
    Assert-Throws {Apply-HwidUpdate $InstallDirectory '1.3.0' 'Package' $ready.stageDirectory 0 0 $false} 'A repeated Apply cannot replace an already installed current version'
    $InstallDirectory=New-FixtureInstall 'apply bat'
    $Component='Bat'
    $cache=Get-UpdateCacheDirectory $InstallDirectory 'Bat'
    [void][IO.Directory]::CreateDirectory($cache)
    $ready=Prepare-HwidUpdate $InstallDirectory '1.3.0' 'Bat' $release $cache
    $before=Get-UpdateHash (Join-Path $InstallDirectory 'HWID Checker.exe')
    $updated=Apply-HwidUpdate $InstallDirectory '1.3.0' 'Bat' $ready.stageDirectory 0 0 $false
    Assert ($updated.state -ceq 'updated' -and (Get-UpdateHash (Join-Path $InstallDirectory 'HWID Checker.exe')) -ceq $before) 'A BAT update installs only the three console runtime files'
    Assert (-not [IO.File]::Exists((Join-Path $InstallDirectory 'DESKTOP-README.md')) -and -not [IO.Directory]::Exists((Join-Path $InstallDirectory 'notices'))) 'A BAT update leaves desktop documentation and runtime notices alone'
    Assert-UpdateNewerThanInstalled $InstallDirectory '1.4.0' '1.3.0' 'Package' '3.86'
    Assert $true 'A full package can complete a split BAT upgrade while the desktop is older'
    Assert-Throws {Assert-UpdateNewerThanInstalled $InstallDirectory '1.4.0' '1.3.0' 'Bat' '3.86'} 'A BAT-only update cannot repeat its installed package version'
    [IO.File]::WriteAllText((Join-Path $InstallDirectory 'hwid.bat'),"Version = '9.99'")
    Assert-Throws {Assert-UpdateNewerThanInstalled $InstallDirectory '1.5.0' '1.3.0' 'Package' '3.86'} 'A package update cannot downgrade an independently newer scanner'
    Set-Item Function:\Receive-UpdateBytes $receiveBody
    $installBody=(Get-Item Function:\Install-UpdateFile).ScriptBlock
    $rollback=New-FixtureInstall 'rollback'
    $oldExe=Get-UpdateHash (Join-Path $rollback 'HWID Checker.exe')
    $oldBat=Get-UpdateHash (Join-Path $rollback 'hwid.bat')
    $script:installCalls=0
    function Install-UpdateFile([string]$Source,[string]$Destination,[string]$Backup){
        $script:installCalls++
        if($script:installCalls -eq 3){throw [IO.IOException]::new('Synthetic locked destination')}
        & $installBody $Source $Destination $Backup
    }
    Assert-Throws {Invoke-UpdateTransaction $rollback $payload $package.Files 'Package' '1.4.0'} 'A mid-install error triggers rollback' 'restored'
    Assert ((Get-UpdateHash (Join-Path $rollback 'HWID Checker.exe')) -ceq $oldExe -and (Get-UpdateHash (Join-Path $rollback 'hwid.bat')) -ceq $oldBat) 'Rollback restores the exact previous EXE and BAT bytes'
    Assert (-not [IO.File]::Exists((Join-Path $rollback 'DESKTOP-README.md'))) 'Rollback removes newly introduced application files'
    Set-Item Function:\Install-UpdateFile $installBody
    $interrupted=New-FixtureInstall 'interrupted'
    $transaction=Join-Path $interrupted ('.hwid-update-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($transaction)
    $prior=Get-UpdateHash (Join-Path $interrupted 'HWID Checker.exe')
    [IO.File]::Copy((Join-Path $interrupted 'HWID Checker.exe'),(Join-Path $transaction '0.previous'))
    [IO.File]::Copy($fixtureNext,(Join-Path $interrupted 'HWID Checker.exe'),$true)
    [IO.File]::WriteAllText((Join-Path $interrupted 'DESKTOP-README.md'),'interrupted guide')
    $recovery=[pscustomobject]@{
        schema=1;state='active';version='1.4.0';component='Package';installDirectory=$interrupted
        files=@(
            [pscustomobject]@{destination='HWID Checker.exe';backup='0.previous';existed=$true;previous=$prior;sha256=(Get-UpdateHash $fixtureNext);applied=$false},
            [pscustomobject]@{destination='DESKTOP-README.md';backup='1.previous';existed=$false;previous=$null;sha256=(Get-UpdateHash (Join-Path $interrupted 'DESKTOP-README.md'));applied=$false}
        )
    }
    Write-UpdateJson (Join-Path $transaction 'transaction.json') $recovery
    Restore-InterruptedUpdates $interrupted
    Assert ((Get-UpdateHash (Join-Path $interrupted 'HWID Checker.exe')) -ceq $prior) 'An interrupted journal restores a previous EXE before another version guard'
    Assert (-not [IO.File]::Exists((Join-Path $interrupted 'DESKTOP-README.md'))) 'Interrupted recovery removes only the recorded newly installed file'
    Assert ((Read-UpdateJson (Join-Path $transaction 'transaction.json')).state -ceq 'recovered' -and [IO.File]::Exists((Join-Path $transaction 'recovered.json'))) 'Recovery publishes both the terminal journal state and recovery marker'
    Restore-InterruptedUpdates $interrupted
    Assert ((Get-UpdateHash (Join-Path $interrupted 'HWID Checker.exe')) -ceq $prior) 'Already recovered transactions are skipped on later runs'
    $recovery.state='active';$recovery.files[0].destination='README.md'
    Assert-Throws {Restore-UpdateTransaction $interrupted $transaction $recovery} 'A recovery journal cannot target a user README or another unsupported file'
    Assert ([IO.File]::ReadAllText((Join-Path $interrupted 'README.md')) -ceq 'user file') 'Rejected recovery retains unrelated user content'
    Assert-Throws {Wait-UpdateProcess $PID 1} 'The updater never waits on its own process'
    Assert-Throws {Wait-UpdateProcess 0 1} 'Partial wait-process identities are rejected'
    $runtime=Join-Path $PSHOME 'powershell.exe'
    if(-not [IO.File]::Exists($runtime)){$runtime=Join-Path $PSHOME 'pwsh.exe'}
    $start=[Diagnostics.ProcessStartInfo]::new($runtime)
    $start.Arguments='-NoLogo -NoProfile -Command "Start-Sleep -Milliseconds 900"'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $process=[Diagnostics.Process]::Start($start)
    try{
        $ticks=$process.StartTime.ToUniversalTime().Ticks
        Assert-Throws {Wait-UpdateProcess $process.Id ($ticks+1)} 'A reused PID with a different start time cannot be mistaken for the original application'
        Wait-UpdateProcess $process.Id $ticks
        Assert $process.HasExited 'Apply waits for the identified application to exit gracefully'
    }finally{$process.Dispose()}
    $packetPath=Join-Path $root 'updater-result.json'
    [IO.File]::WriteAllText($packetPath,'previous result')
    $start=[Diagnostics.ProcessStartInfo]::new($runtime)
    $start.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$source+'" -Mode Check -InstallDirectory "'+$InstallDirectory+'" -CurrentVersion invalid -ResultPath "'+$packetPath+'"'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($start)
    try{
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        Assert ($process.WaitForExit(10000)) 'The command-line updater terminates after publishing a failure result'
        $text=$stdout.GetAwaiter().GetResult().Trim()
        $packet=ConvertFrom-Json -InputObject $text
        Assert ($packet.state -ceq 'error' -and $text -notmatch '[\r\n]' -and $process.ExitCode -eq 1) 'The command line emits one JSON packet and a failure exit code'
        Assert ([IO.File]::ReadAllText($packetPath).Trim() -ceq $text -and -not $stderr.GetAwaiter().GetResult()) 'ResultPath is atomically replaced before exit without writing a second error stream'
    }finally{$process.Dispose()}
    [Console]::WriteLine(($script:checks.ToString()+' updater checks passed.'))
}finally{$env:LOCALAPPDATA=$previousLocal}
