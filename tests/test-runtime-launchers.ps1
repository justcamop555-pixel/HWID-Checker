$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot ("test-runtime ! & ' "+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$bootstrap=($source -split '(?m)^# POWERSHELL_START\r?$',2)[0]
$loader=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Start-HWID.ps1'))
$checks=0
function Assert($Value,$Message){if(-not $Value){throw ('FAILED: '+$Message)};$script:checks++;Write-Output ('PASS: '+$Message)}
function Run-Process($File,$Arguments,$PathOverride) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$File;$start.Arguments=$Arguments;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    if($null -ne $PathOverride){$start.EnvironmentVariables['PATH']=$PathOverride}
    $process=[Diagnostics.Process]::Start($start)
    $process.StandardInput.Close()
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(25000)){$process.Kill();throw 'Launcher diagnostic exceeded 25 seconds.'}
    [pscustomobject]@{Code=$process.ExitCode;Output=($stdout.Result+$stderr.Result)}
}
function Make-Case($Name,$Header,$Body) {
    $folder=Join-Path $root $Name;New-Item -ItemType Directory -Path $folder | Out-Null
    $path=Join-Path $folder 'hwid.bat'
    [IO.File]::WriteAllText($path,($Header+[Environment]::NewLine+'# POWERSHELL_START'+[Environment]::NewLine+$Body),(New-Object Text.UTF8Encoding($false)))
    return $path
}
$cmd=Join-Path $env:SystemRoot 'System32\cmd.exe'
$winps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$body='Write-Output "BOOTSTRAP_OK"; Write-Output ("ENGINE_MAJOR="+$PSVersionTable.PSVersion.Major)'
$normal=Make-Case 'normal' $bootstrap $body
$result=Run-Process $cmd ('/d /c ""'+$normal+'""') $null
Assert ($result.Code -eq 0 -and $result.Output -match 'BOOTSTRAP_OK') 'Real batch launcher probes and starts the embedded body from a path with spaces and shell punctuation'
$noCandidates=$bootstrap -replace '(?m)^(call :hwid_try_engine |for %%P in ).*\r?$','rem Test: no runtime candidates'
$missing=Make-Case 'missing' $noCandidates 'THIS MUST NEVER PARSE @('
$result=Run-Process $cmd ('/d /c ""'+$missing+'""') $null
Assert ($result.Code -eq 10 -and $result.Output -match 'COMPAT-01' -and $result.Output -notmatch 'ParserError') 'No-runtime startup explains the requirement without parsing the modern body'
$probeLine=@($bootstrap -split '\r?\n' | Where-Object {$_ -like '"%~1" *'})[0]
$blocked=Make-Case 'restricted' ($bootstrap.Replace($probeLine,'"%~1" -NoLogo -NoProfile -Command "exit 13" >nul 2>nul')) 'THIS MUST NEVER PARSE @('
$result=Run-Process $cmd ('/d /c ""'+$blocked+'""') $null
Assert ($result.Code -eq 13 -and $result.Output -match 'COMPAT-02') 'Restricted-language probe result stops startup rather than switching engines to bypass policy'
$old=Make-Case 'old' ($bootstrap.Replace($probeLine,'"%~1" -NoLogo -NoProfile -Command "exit 11" >nul 2>nul')) 'THIS MUST NEVER PARSE @('
$result=Run-Process $cmd ('/d /c ""'+$old+'""') $null
Assert ($result.Code -eq 10 -and $result.Output -match 'older than the required version 5.1') 'Old-runtime probe results explain the required upgrade before body parsing'
$pwsh=if($PSVersionTable.PSVersion.Major -ge 7){[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName}else{(Get-Command pwsh.exe -ErrorAction Stop).Source}
$alternateHeader=$bootstrap -replace '(?m)^call :hwid_try_engine .*\r?$','rem Test: use PATH runtime'
$alternateHeader=$alternateHeader -replace '(?m)^for %%P in \(powershell.exe\).*\r?$','rem Test: Windows PowerShell unavailable'
$alternate=Make-Case 'powershell7' $alternateHeader $body
$result=Run-Process $cmd ('/d /c ""'+$alternate+'""') (Split-Path -Parent $pwsh)
Assert ($result.Code -eq 0 -and $result.Output -match 'ENGINE_MAJOR=7') 'PowerShell 7 on PATH is used when Windows PowerShell candidates are unavailable'
$directFolder=Join-Path $root 'direct'
New-Item -ItemType Directory -Path $directFolder | Out-Null
$direct=Join-Path $directFolder 'Start-HWID.ps1'
[IO.File]::WriteAllText($direct,$loader,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $directFolder 'hwid.bat'),('# POWERSHELL_START'+[Environment]::NewLine+$body),(New-Object Text.UTF8Encoding($false)))
$result=Run-Process $winps ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$direct+'" -CurrentWindow') ''
Assert ($result.Code -eq 0 -and $result.Output -match 'BOOTSTRAP_OK') 'PowerShell-only launcher works with an empty PATH and does not require cmd.exe'
$orphanFolder=Join-Path $root 'orphan';New-Item -ItemType Directory -Path $orphanFolder | Out-Null
$orphan=Join-Path $orphanFolder 'Start-HWID.ps1'
[IO.File]::WriteAllText($orphan,$loader,(New-Object Text.UTF8Encoding($false)))
$result=Run-Process $winps ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$orphan+'"') ''
Assert ($result.Code -eq 1 -and $result.Output -match 'Keep Start-HWID.ps1 beside hwid.bat') 'Missing companion BAT gets a specific PowerShell-only launcher error'
$oldLoader=$loader.Replace('$ErrorActionPreference=''Stop''','Import-Module Microsoft.PowerShell.Utility; $PSVersionTable.PSVersion=[version]''2.0''; $ErrorActionPreference=''Stop''')
[IO.File]::WriteAllText($direct,$oldLoader,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $directFolder 'hwid.bat'),('# POWERSHELL_START'+[Environment]::NewLine+'THIS MUST NEVER PARSE @('),(New-Object Text.UTF8Encoding($false)))
$result=Run-Process $winps ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$direct+'"') ''
Assert ($result.Code -eq 1 -and $result.Output -match 'PowerShell 5.1' -and $result.Output -notmatch 'ParserError') 'PowerShell-only launcher checks engine requirements before parsing the embedded checker'
Write-Output ("All $checks launcher checks passed. No hardware queries were run.")
