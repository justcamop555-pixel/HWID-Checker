$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '..\hwid.bat'
$raw=[IO.File]::ReadAllText($source)
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$parseErrors)
foreach ($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$folder=Join-Path $PSScriptRoot ('test-launch ! & ' + [char]0x00E9 + " ' " + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
$testScript=Join-Path $folder 'hwid.bat'
$resultPath=Join-Path $folder 'startup-result.json'
$resultLiteral=$resultPath.Replace("'","''")
# A test-only copy auto-exits at the main menu and writes display metadata, never IDs.
$menuTest = @'
$choice = Read-MenuChoice -Reader {
    param($inputArea)
    if ($null -eq $script:menuTestKeys) {
        $script:menuTestKeys=New-Object 'System.Collections.Generic.Queue[System.ConsoleKeyInfo]'
        $texts=@('fgsdv235','10') + @(1..100 | ForEach-Object {'bad'}) + @('0')
        foreach($text in $texts) {
            foreach($character in $text.ToCharArray()) { $script:menuTestKeys.Enqueue((New-Object ConsoleKeyInfo($character,[ConsoleKey]::A,$false,$false,$false))) }
            $script:menuTestKeys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
            if($text -in @('fgsdv235','10')) { for($repeat=0;$repeat -lt 1000;$repeat++) { $script:menuTestKeys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false))) } }
        }
        $script:menuReads=0; $script:keyReads=0
    }
    $script:menuReads++
    Read-MenuKeyboard -Area $inputArea -KeyReader { $script:keyReads++; $script:menuTestKeys.Dequeue() }
}
'@
$testRaw=$raw.Replace('$choice = Read-MenuChoice', $menuTest)
$testRaw=$testRaw.Replace("Wait-ScanContinue 'main menu'", "Wait-ScanContinue 'main menu' -KeyReader { `$script:startupContinueReads++; New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,`$false,`$false,`$false) }")
$failureTrap='trap { @{Error=$_.Exception.Message;AtLine=$_.InvocationInfo.ScriptLineNumber;Stack=$_.ScriptStackTrace} | ConvertTo-Json | Set-Content -LiteralPath ''__RESULT__'' -Encoding UTF8; exit 1 }'
$failureTrap=$failureTrap.Replace('__RESULT__',$resultLiteral)
$sourceTrap=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.TrapStatementAst]},$false) | Select-Object -First 1
if($null -ne $sourceTrap){$testRaw=$testRaw.Replace($sourceTrap.Extent.Text,$failureTrap)}
else{$testRaw=$testRaw.Replace('$ErrorActionPreference = ''Stop''','$ErrorActionPreference = ''Stop'''+[Environment]::NewLine+$failureTrap)}
$diagnostic="'0' { `$display.InputModeAfter=[HwidConsoleDisplay]::ReadInputMode(); `$display | Add-Member NoteProperty WindowTop ([Console]::WindowTop); `$display | Add-Member NoteProperty MenuReads `$script:menuReads; `$display | Add-Member NoteProperty KeyReads `$script:keyReads; `$display | Add-Member NoteProperty StartupContinueReads `$script:startupContinueReads; `$display | Add-Member NoteProperty CursorRow ([Console]::CursorTop); `$display | Add-Member NoteProperty OwnConsole (`$env:HWID_OWN_CONSOLE -eq '1'); `$display | Add-Member NoteProperty Admin `$admin; `$display | ConvertTo-Json | Set-Content -LiteralPath '$resultLiteral' -Encoding UTF8; return }"
$testRaw=$testRaw.Replace("'0' { Show-UiTransition 'Exit'; return }",$diagnostic)
[IO.File]::WriteAllText($testScript,$testRaw,(New-Object Text.UTF8Encoding($false)))
$priorPath=$env:HWID_SCRIPT
try {
    $env:HWID_SCRIPT=$testScript
    if (-not (Start-ReadableConsole $testScript $false $false '')) { throw 'Dedicated startup fell back unexpectedly.' }
    $deadline=(Get-Date).AddSeconds(25)
    while (-not (Test-Path -LiteralPath $resultPath)) {
        if ((Get-Date) -gt $deadline) { throw 'Checker did not reach the main menu.' }
        Start-Sleep -Milliseconds 250
    }
    Start-Sleep -Milliseconds 300
    $result=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($result.Error){throw ($result.Error+' / '+$result.Stack)}
    if($result.StartupContinueReads -ne 1){throw 'Actual checker did not wait to continue after its startup scan.'}
    if(-not $result.ContextMenuDisabled){throw 'Actual checker did not disable its Edit popup.'}
    if (-not $result.QuickEditDisabled -or ($result.InputModeAfter -band 64) -ne 0) { throw 'Quick Edit was re-enabled before the main menu.' }
    if (-not $result.ThemeApplied -or $result.BackgroundRGB -ne 2101772) { throw 'The navy theme was not applied to the actual checker.' }
    if ($result.CursorRow -ge $result.Rows) { throw 'Control deck overflowed the viewport.' }
    if ($result.MenuReads -ne 103 -or $result.KeyReads -ne 2414) { throw 'Repeated invalid input or held Enter did not get handled correctly.' }
    if ($result.CursorRow -ne 29 -or $result.WindowTop -ne 0) { throw 'Repeated errors scrolled the dashboard or moved its input area.' }
    if (-not $result.OwnConsole -or -not $result.FontApplied -or $result.FontWeight -ne 400 -or $result.Columns -ne 100 -or $result.Rows -ne 34) { throw 'Actual checker did not use the expected display.' }
    $parentAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($result.Admin -ne $parentAdmin) { throw 'Privilege level changed during startup.' }
    $result | ConvertTo-Json
    'PASS: Actual checker startup reaches menu with regular font and unchanged privilege level from a path containing spaces, apostrophe, !, &, and Unicode.'
} finally { $env:HWID_SCRIPT=$priorPath }
