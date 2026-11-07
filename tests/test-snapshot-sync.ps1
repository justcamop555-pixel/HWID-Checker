$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$groups=$ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$sectionGroups'},$false) | Select-Object -First 1
. ([scriptblock]::Create($groups.Extent.Text))
$identifierPattern='^(ProcessorId)$'
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
$ownedConsole=$false;$redirected=$true
$script:checks=0
$script:output=New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition,$Description){
    if(-not $Condition){throw ('FAILED: '+$Description)}
    $script:checks++
    [Console]::WriteLine('PASS: '+$Description)
}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:output.Add([string]$Object)}

$root=Join-Path $PSScriptRoot ('test-output-sync-'+[guid]::NewGuid().ToString('N'))
$env:HWID_SCRIPT=Join-Path $root 'app\repo\hwid.bat'
$env:LOCALAPPDATA=Join-Path $root 'local'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $env:HWID_SCRIPT))
[IO.File]::WriteAllText((Join-Path $root 'app\hwid.bat'),'test launcher')
$recent=Join-Path $root ("legacy ! & [1] "+[char]0x03a9)
$tracked=Join-Path $root 'legacy tracked'
$preferred=Join-Path $root 'shared primary'
$legacy=Join-Path $env:LOCALAPPDATA 'HWID Checker\Desktop\settings.json'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $legacy))
$legacyJson=ConvertTo-Json -InputObject @{lastSaveFolder=$recent; snapshotFolders=@($tracked,$recent.ToUpperInvariant(),'relative','\\server\share')}
[IO.File]::WriteAllText($legacy,$legacyJson,[Text.UTF8Encoding]::new($true,$true))
$initial=Get-ReportLocations
$settings=$initial.Library.Path
Assert ($initial.Search.Count -eq 5 -and $initial.Search[-2] -ceq $recent -and $initial.Search[-1] -ceq $tracked) 'Legacy UTF-8 BOM settings supply only normalized local folder candidates'
Assert ($initial.Primary -eq (Join-Path $root 'app\repo\HWID-Reports') -and -not [IO.File]::Exists($settings)) 'Discovery keeps the existing default and creates no settings file'
Assert ((Convert-SnapshotFolderPath ($preferred.Replace('\','/')+'/next/../')) -ceq $preferred) 'Absolute path normalizes separators and navigation'
Assert ((Convert-SnapshotFolderPath 'C:\') -ceq 'C:\') 'Drive root keeps its separator'
$rejected=@('C:relative','\relative','\\server\share','\\?\C:\device','C:\test:stream','C:\file.','C:\dir \test','C:\NUL.txt','C:\LPT1','C:\test?',[string]('C:\control'+[char]0x85))
Assert (@($rejected | ForEach-Object {Convert-SnapshotFolderPath $_} | Where-Object {$_}).Count -eq 0) 'Invalid, reserved, device, UNC and drive-relative paths are rejected'

Update-SnapshotLibrary $settings SetPrimary $preferred
$locations=Get-ReportLocations
$lockPath=Join-Path (Split-Path -Parent $settings) 'snapshot-library.lock'
Assert ($locations.Primary -eq $preferred -and $locations.Search.Count -eq 6 -and [IO.File]::Exists($lockPath)) 'First write promotes the shared folder, retains existing search and leaves the lock file'
Assert ($locations.Library.Folders.Count -eq 2 -and $locations.Library.Folders[0] -ceq $recent) 'First write migrates legacy discovery paths in order'
Update-SnapshotLibrary $settings SetPrimary $recent
$library=Read-SnapshotLibrary $settings
Assert ($library.Primary -ceq $recent -and $library.Folders -contains $preferred -and $library.Folders -notcontains $recent) 'Promoting a tracked folder retains the previous primary'
Update-SnapshotLibrary $settings Remove $tracked
Assert ((Get-ReportLocations).Search -notcontains $tracked) 'Explicit untracking supersedes the legacy settings'
Update-SnapshotLibrary $settings Reset
$locations=Get-ReportLocations
Assert ($locations.Primary -eq $initial.Primary -and $locations.Library.Folders -contains $recent) 'Reset restores the default while retaining the previous shared folder'

$held=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $message=$null
    try{Update-SnapshotLibrary $settings Add $tracked}catch{$message=$_.Exception.Message}
    Assert ($message -like 'Another window*' -and $clock.ElapsedMilliseconds -ge 1500 -and $clock.ElapsedMilliseconds -lt 4000) 'A held lock produces a bounded retry and useful message'
}finally{$held.Dispose()}
$reader=[IO.File]::Open($settings,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
try {
    Update-SnapshotLibrary $settings Add $tracked
    Assert ((Read-SnapshotLibrary $settings).Folders -contains $tracked) 'A concurrent reader can stay open while settings are atomically replaced'
}finally{$reader.Dispose()}
Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $settings) -Filter '*.tmp').Count -eq 0) 'Successful publication leaves no temporary settings file'

$malformed='{"version":1,"primary":null,"folders":[],"vers\u0069on":1}'
[IO.File]::WriteAllText($settings,$malformed,[Text.UTF8Encoding]::new($false,$true))
$locations=Get-ReportLocations
Assert ($locations.Primary -eq $initial.Primary -and $locations.Library.Warning -and $locations.Search -contains $tracked) 'Duplicate settings keys warn and fall back to existing discovery'
$message=$null
try{Update-SnapshotLibrary $settings Reset}catch{$message=$_.Exception.Message}
Assert ($message -match 'settings could not be read' -and [IO.File]::ReadAllText($settings) -ceq $malformed) 'A malformed settings file remains unchanged after an attempted write'
[IO.File]::Delete($settings)

$env:LOCALAPPDATA=Join-Path $root 'picker-local'
$settings=(Get-SnapshotLibrary).Path
$report=[ordered]@{'Report info'=@{Computer='SYNTHETIC';Version='3.84';Generated='2026-11-04T10:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='TEST-A'})}
$baselineFolder=Join-Path $root 'refresh folder'
$baseline=Join-Path $baselineFolder 'older.json'
[void][IO.Directory]::CreateDirectory($baselineFolder)
$older=[ordered]@{'Report info'=@{Computer='SYNTHETIC';Version='3.83';Generated='2026-11-03T10:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='TEST-B'})}
[IO.File]::WriteAllText($baseline,($older | ConvertTo-Json -Depth 5))
$script:pickerReads=0
function Read-CheckerLine {
    param($Prompt)
    $script:pickerReads++
    if($script:pickerReads -eq 1){Update-SnapshotLibrary $settings Add $baselineFolder;return '8'}
    return '1'
}
Assert ((Read-CompareReportPath) -ceq $baseline) 'Compare refresh reloads settings and discovers the newly tracked older snapshot'

$env:LOCALAPPDATA=Join-Path $root 'menu-local'
$script:choices=New-Object 'System.Collections.Generic.Queue[string]'
$script:answers=New-Object 'System.Collections.Generic.Queue[string]'
foreach($choice in @('3','4','5','6','0')){$script:choices.Enqueue($choice)}
foreach($answer in @(('"'+$preferred+'"'),$baselineFolder,'1')){$script:answers.Enqueue($answer)}
function Read-MenuChoice {param($Maximum) $script:choices.Dequeue()}
function Read-CheckerLine {param($Prompt) $script:answers.Dequeue()}
Show-SnapshotLibrary
$library=Get-SnapshotLibrary
Assert ($script:choices.Count -eq 0 -and $script:answers.Count -eq 0 -and -not $library.Warning) 'Saved-snapshot submenu accepts set, track, remove, reset and back inputs'
Assert ($null -eq $library.Primary -and $library.Folders.Count -eq 1 -and $library.Folders[0] -ceq $preferred -and [IO.File]::Exists($baseline)) 'Untracking preserves report files and reset tracks the previous shared folder'
[Console]::WriteLine("All $script:checks snapshot sync checks passed under PowerShell $($PSVersionTable.PSVersion).")
