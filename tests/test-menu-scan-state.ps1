param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$compact=(Get-Item -LiteralPath Function:Show-CompactDeck).ScriptBlock
$checks=0
function Assert($condition,$message){if(-not $condition){throw ('FAILED: '+$message)};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
$report=[ordered]@{'Report info'=[ordered]@{Computer='SYNTHETIC';Generated='2026-11-17T00:00:00Z';ExtendedStatus='Refreshed'}}
$identifiers=@([pscustomobject]@{Quality='Reported';Value='SYNTHETIC-000123'});$warnings=@();$scanTotal=18;$admin=$false
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Good='Green';Warn='Yellow';Error='Red'}
$script:rendered=New-Object 'System.Collections.Generic.List[object]'
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline) $script:rendered.Add([pscustomobject]@{Text=[string]$Object;Color=[string]$ForegroundColor})}
function Reset-UiPage {}
function Write-Heading {}
function Format-ScanTime {param($Value) return 'Synthetic capture time'}
function Get-ReviewSummary {param($Inventory,$Ids,$Warnings) $script:summaryCalls++;[pscustomobject]@{Total=$script:reviewTotal;CoverageCount=$script:coverageCount}}
function Get-ScanCoverage {param($Inventory) [pscustomobject]@{Read=$script:readCount}}
# Exercise the normal production renderer even if an attached console is narrow.
# Its existing native-layout try/catch safely falls through when the compact
# renderer is unavailable; no terminal size, mode or screen buffer is changed.
function Show-CompactDeck {param($Width) throw 'Synthetic compact renderer unavailable; verify the normal production deck.'}
function Read-DeckState([int]$Coverage,[int]$Read,[string]$ExtendedStatus,$ParentReview){
    $script:coverageCount=$Coverage;$script:reviewTotal=$Coverage;$script:readCount=$Read;$script:summaryCalls=0
    $script:reviewInfo=$ParentReview
    $report['Report info'].ExtendedStatus=$ExtendedStatus
    $script:rendered.Clear()
    Show-ControlDeck
    $header=@($script:rendered|Where-Object Text -match '^  \[SCAN ')
    if($header.Count -ne 1){throw 'The normal deck did not emit exactly one scan-state header.'}
    return $header[0]
}
$state=Read-DeckState 1 18 'Refreshed' $null
Assert ($state.Text -match '\[SCAN FINISHED / REVIEW\]' -and $state.Color -ceq 'Yellow') 'identification coverage findings prevent a green successful-scan header in the normal deck'
Assert ($script:summaryCalls -eq 1 -and @($script:rendered|Where-Object {$_.Text -match '\[REVIEW\]  1 items' -and $_.Color -ceq 'Yellow'}).Count -eq 1) 'the scan-state header and review count use one current summary'
$parent=[pscustomobject]@{CoverageCount=99;Total=99}
$state=Read-DeckState 0 18 'Refreshed' $parent
Assert ($state.Text -match '\[SCAN COMPLETE\]' -and $state.Color -ceq 'Green') 'a healthy capture clears earlier coverage state instead of inheriting a caller warning'
Assert ($script:reviewInfo.CoverageCount -eq 99 -and $script:summaryCalls -eq 1) 'rendering owns its summary without mutating or reusing the caller state'
$state=Read-DeckState 2 18 'Refreshed' ([pscustomobject]@{CoverageCount=0;Total=0})
Assert ($state.Text -match '\[SCAN FINISHED / REVIEW\]' -and $state.Color -ceq 'Yellow') 'an unrelated clear caller summary cannot hide current identification findings'
$state=Read-DeckState 0 17 'Refreshed' $null
Assert ($state.Text -match '\[SCAN PARTIAL\]' -and $state.Color -ceq 'Yellow') 'failed normal read coverage remains partial even without identification findings'
$state=Read-DeckState 0 18 'Unavailable' $null
Assert ($state.Text -match '\[SCAN PARTIAL\]' -and $state.Text -match 'extended not read' -and $state.Color -ceq 'Yellow') 'a failed device catalog cannot become a green complete scan'
# The compact production view reports the same current count, rather than
# manufacturing a successful-completion claim where space is limited.
Set-Item -LiteralPath Function:Show-CompactDeck -Value $compact
$script:coverageCount=1;$script:reviewTotal=1;$script:summaryCalls=0;$script:reviewInfo=[pscustomobject]@{CoverageCount=0;Total=0}
$script:rendered.Clear();Show-CompactDeck 60
Assert (@($script:rendered|Where-Object Text -match 'Found: 1 / Review: 1').Count -eq 1 -and $script:summaryCalls -eq 1) 'the compact production deck shows the current identifier and review counts'
Assert (@($script:rendered|Where-Object Text -match '\[SCAN COMPLETE\]').Count -eq 0) 'the compact deck does not contradict its review count with a successful-completion header'
[Console]::WriteLine(('All {0} menu scan-state checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
