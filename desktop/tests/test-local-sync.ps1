#requires -Version 7.0
param([string]$BatPath = (Join-Path $PSScriptRoot '..\..\hwid.bat'))
$ErrorActionPreference = 'Stop'
$BatPath = [IO.Path]::GetFullPath($BatPath)
$probeProject = Join-Path $PSScriptRoot 'SnapshotSyncProbe\SnapshotSyncProbe.csproj'
dotnet build $probeProject --configuration Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Could not build the Desktop sync probe.' }
$probe = Join-Path (Split-Path -Parent $probeProject) 'bin\Release\net10.0\SnapshotSyncProbe.exe'

$source = ([IO.File]::ReadAllText($BatPath) -split '(?m)^# POWERSHELL_START\r?$', 2)[1]
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join ', ') }
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$groups = $ast.FindAll({
    param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$sectionGroups'
}, $false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern = '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
$palette = @{ Heading='Cyan'; Text='White'; Muted='Gray'; Good='Green'; Warn='Yellow'; Error='Red' }

$script:checks = 0
function Assert-Interop($condition, [string]$description) {
    if (!$condition) { throw "FAIL: $description" }
    $script:checks++
    Write-Host "PASS: $description"
}
function Invoke-DesktopProbe([string[]]$arguments) {
    $result = & $probe @arguments | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Desktop probe terminated unexpectedly.' }
    $result
}

$root = Join-Path $PSScriptRoot ('test-output-sync-interop-' + [guid]::NewGuid().ToString('N'))
$local = Join-Path $root 'Local'
$preferences = Join-Path $local 'HWID Checker'
$settings = Join-Path $preferences 'snapshot-library.json'
$legacy = Join-Path $root ('Legacy ' + [char]0x03A9)
$primary = Join-Path $root ('Preferred ' + [char]0x03B2)
$watched = Join-Path $root 'Watched & reports'
$desktopExtra = Join-Path $root 'Desktop extra'
$batExtra = Join-Path $root 'BAT extra'
$batFolder = Join-Path $root 'BAT'
foreach ($folder in @($legacy,$primary,$watched,$desktopExtra,$batExtra,$batFolder,(Join-Path $preferences 'Desktop'))) {
    [void][IO.Directory]::CreateDirectory($folder)
}
$fakeBat = Join-Path $batFolder 'hwid.bat'
[IO.File]::WriteAllText($fakeBat, '')
$legacyFile = Join-Path $preferences 'Desktop\settings.json'
[IO.File]::WriteAllText($legacyFile, (@{lastSaveFolder=$legacy;snapshotFolders=@('relative',$legacy)} | ConvertTo-Json))

$first = Invoke-DesktopProbe @('read',$settings)
Assert-Interop (!$first.IsConfigured -and @($first.Folders).Count -eq 1 -and $first.Folders -contains $legacy) 'Desktop imports a Unicode legacy folder without writing settings'
$batFirst = Get-SnapshotLibrary -LocalRoot $local
Assert-Interop ($batFirst.Folders -contains $legacy -and !(Test-Path -LiteralPath $settings)) 'BAT discovers the same legacy folder without creating settings'

$choice = Invoke-DesktopProbe @('set-primary',$settings,$primary)
$locations = Get-ReportLocations -ScriptPath $fakeBat -LocalRoot $local
Assert-Interop (!$choice.Failed -and $locations.Primary -eq $primary -and $locations.Search -contains $legacy) 'A Desktop shared preference becomes the BAT save target while keeping older folders'
Assert-Interop ($locations.Search -contains (Join-Path $batFolder 'HWID-Reports') -and $locations.Search -contains $locations.Fallback) 'The BAT still searches its original folder and fallback'

$null = Update-SnapshotLibrary $settings Add $watched
$read = Invoke-DesktopProbe @('read',$settings)
Assert-Interop ($read.IsConfigured -and $read.Primary -eq $primary -and $read.Folders -contains $watched) 'Desktop sees the new BAT watched folder with literal punctuation'

$stamp = '2026-01-02T12:00:00Z'
$previous = [ordered]@{'Report info'=[ordered]@{Version='3.84';Computer='SYNTHETIC-SYNC';Generated=$stamp};CPU=@([ordered]@{DeviceID='CPU0';ProcessorId='SYNTHETIC-01'})}
$captured = [ordered]@{'Report info'=[ordered]@{Version='3.84';Computer='SYNTHETIC-SYNC';Generated='2026-01-03T12:00:00Z'};CPU=@([ordered]@{DeviceID='CPU0';ProcessorId='SYNTHETIC-02'})}
$batPair = Write-SnapshotWithFallback $locations.Primary $locations.Fallback 'HWID-BAT-synthetic' 'Synthetic BAT report' ($previous | ConvertTo-Json -Depth 6)
$desktopCatalog = Invoke-DesktopProbe @('catalog',$read.Primary,$watched)
Assert-Interop ($desktopCatalog.Entries.Name -contains 'HWID-BAT-synthetic.json' -and (Test-Path -LiteralPath ($batPair.Stem+'.txt'))) 'Desktop discovers the complete pair saved by the BAT writer'

$fixture = Join-Path $root 'current-fixture.json'
[IO.File]::WriteAllText($fixture, ($captured | ConvertTo-Json -Depth 6))
$export = Invoke-DesktopProbe @('export',$BatPath,$fixture,$watched)
$locations = Get-ReportLocations -ScriptPath $fakeBat -LocalRoot $local
$batCatalog = Get-SavedSnapshotCatalog $locations.Search $captured
Assert-Interop (!$export.Failed -and @($batCatalog.Entries).Count -eq 2 -and @($batCatalog.Entries | Where-Object TextAvailable).Count -eq 2) 'BAT discovers the pair saved through the Desktop export bridge'
$batSnapshotHash = (Get-FileHash -LiteralPath ($batPair.Stem+'.json')).Hash

$gate = [IO.File]::Open((Join-Path $preferences 'snapshot-library.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$start = [Diagnostics.ProcessStartInfo]::new($probe)
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = 'Hidden'
$start.RedirectStandardOutput = $true
foreach ($argument in @('add-folder',$settings,$desktopExtra)) { $start.ArgumentList.Add($argument) }
$writer = $null
try {
    $writer = [Diagnostics.Process]::Start($start)
    Assert-Interop (!$writer.WaitForExit(300)) 'The Desktop writer waits while BAT holds the shared lock'
}
finally { $gate.Dispose() }
try {
    $null = Update-SnapshotLibrary $settings Add $batExtra
    if (!$writer.WaitForExit(10000)) { $writer.Kill($true); throw 'The Desktop writer did not finish.' }
    $writerResult = $writer.StandardOutput.ReadToEnd() | ConvertFrom-Json
    $mixed = Invoke-DesktopProbe @('read',$settings)
    Assert-Interop (!$writerResult.Failed -and $mixed.Folders -contains $desktopExtra -and $mixed.Folders -contains $batExtra) 'Concurrent Desktop and BAT writes preserve both folder changes'
}
finally { $writer.Dispose() }

$null = Update-SnapshotLibrary $settings Reset
$reset = Invoke-DesktopProbe @('read',$settings)
Assert-Interop (!$reset.Primary -and $reset.Folders -contains $primary) 'Reset restores the default and keeps the old save folder watched'
$null = Invoke-DesktopProbe @('remove-folder',$settings,$legacy)
$after = Get-SnapshotLibrary -LocalRoot $local
Assert-Interop ($after.Folders -notcontains $legacy -and (Test-Path -LiteralPath $legacy)) 'Removing a migrated folder stops discovery without touching its files'
Assert-Interop ((Get-FileHash -LiteralPath ($batPair.Stem+'.json')).Hash -eq $batSnapshotHash) 'Folder changes leave previously saved JSON bytes intact'

$raw = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
Assert-Interop (@($raw.PSObject.Properties).Count -eq 3 -and $raw.version -eq 1 -and $null -ne $raw.folders) 'Shared settings contain only the version and folder preferences'
$brokenRoot = Join-Path $root 'Broken'
$brokenSettings = Join-Path $brokenRoot 'HWID Checker\snapshot-library.json'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $brokenSettings))
[IO.File]::WriteAllText($brokenSettings,'{"version":1,"VERSION":1,"primary":null,"folders":[]}')
$before = (Get-FileHash -LiteralPath $brokenSettings).Hash
$badDesktop = Invoke-DesktopProbe @('read',$brokenSettings)
$badBat = Get-SnapshotLibrary -LocalRoot $brokenRoot
$refused = Invoke-DesktopProbe @('add-folder',$brokenSettings,$watched)
Assert-Interop ($badDesktop.Error -and $badBat.Warning -and $refused.Failed -and (Get-FileHash -LiteralPath $brokenSettings).Hash -eq $before) 'Both readers fall back on corrupt settings and the Desktop writer preserves the original'

[pscustomobject]@{Checks=$script:checks;SyntheticOnly=$true;OutputDirectory=$root} | ConvertTo-Json
