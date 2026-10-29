$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($definition.Extent.Text))}
$script:checks=0
function Assert($Condition,$Description){if(-not $Condition){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
foreach($direction in @('Next','Back','Exit')){
    foreach($width in @(0,8,16,27,40,99)){
        $valid=$true
        foreach($step in 0..17){$lines=@(Get-UiTransitionLines $direction $step $width 'Quick IDs');if($lines.Count -ne 3 -or @($lines | Where-Object {$_.Length -gt $width -or $_ -match '[\x00-\x1f\x7f]'}).Count){$valid=$false;break}}
        Assert $valid ($direction+' animation uses exactly three bounded, single-line rows at width '+$width)
    }
    Assert (((Get-UiTransitionLines $direction -9 99) -join '|') -ceq ((Get-UiTransitionLines $direction 0 99) -join '|')) ($direction+' border clamps negative frame indexes')
    Assert (((Get-UiTransitionLines $direction 80 99) -join '|') -ceq ((Get-UiTransitionLines $direction 17 99) -join '|')) ($direction+' border clamps excess frame indexes')
    Assert ((Get-UiTransitionFrame $direction 8 16) -match $direction.ToUpperInvariant()) ($direction+' narrow animation keeps its action label visible')
}
$next=@(0..17 | ForEach-Object {(Get-UiTransitionLines Next $_ 99)[0]})
$back=@(0..17 | ForEach-Object {(Get-UiTransitionLines Back $_ 99)[0]})
Assert ($next[0] -match '^  \+>' -and $back[0] -match '<\+$') 'Moving borders follow the chosen navigation direction'
Assert (($next | Select-Object -Unique).Count -ge 12 -and ($back | Select-Object -Unique).Count -ge 12) 'Borders advance through distinct positions instead of flashing a static frame'
Assert ($next[-1] -match '^  \+=+\+$' -and $back[-1] -eq $next[-1]) 'Both navigation borders settle on the same completed shape'
$exitStart=(Get-UiTransitionLines Exit 0 99)[0];$exitEnd=(Get-UiTransitionLines Exit 17 99)[0]
Assert ($exitStart -match '=' -and $exitEnd -notmatch '[=<>]') 'Exit borders close toward the center and finish empty'
Assert ((Get-UiTransitionFrame Next 8 99) -match '=.*>>' -and (Get-UiTransitionFrame Back 8 99) -match '<<.*=') 'Directional trails remain behind their arrow heads'
Assert ((Get-UiTransitionFrame Back 8 99 'Hardware details') -match 'BACK / Hardware details') 'Back animation honors an explicit destination'
Assert ((Get-UiTransitionFrame Next 8 99 "Quick`nIDs$([char]27)") -notmatch '[\x00-\x1f\x7f]') 'Destination text cannot add console controls or extra lines'
Assert ((Get-UiTransitionDuration Back) -lt (Get-UiTransitionDuration Next) -and (Get-UiTransitionDuration Next) -lt (Get-UiTransitionDuration Exit) -and (Get-UiTransitionDuration Exit) -le 300) 'Motion stays brief with quicker Back and a distinct closing duration'
$ownedConsole=$false;$redirected=$false;$script:inputChecks=0
Show-UiTransition Next -PendingInput {$script:inputChecks++;$false}
Assert ($script:inputChecks -eq 0) 'Shared consoles skip animation without probing keyboard state'
$ownedConsole=$true;$redirected=$true
Show-UiTransition Next -PendingInput {$script:inputChecks++;$false}
Assert ($script:inputChecks -eq 0) 'Redirected runs skip animation without probing keyboard state'
$redirected=$false;$before=$env:HWID_NO_ANIMATION
try{$env:HWID_NO_ANIMATION='1';Show-UiTransition Next -PendingInput {$script:inputChecks++;$false};Assert ($script:inputChecks -eq 0) 'The existing no-animation preference bypasses motion and input checks'}finally{$env:HWID_NO_ANIMATION=$before}
[Console]::WriteLine("All $script:checks animation checks passed under PowerShell $($PSVersionTable.PSVersion).")
