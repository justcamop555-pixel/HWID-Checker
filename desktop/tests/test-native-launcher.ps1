#requires -Version 7.0
param([Parameter(Mandatory=$true)][string]$ExePath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $root){throw 'Choose a new test output directory.'}
[void][IO.Directory]::CreateDirectory($root)
$checks=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:checks++;Write-Output ('PASS: '+$message)}
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$fixture=Join-Path $root 'fixture.exe'
& $csc /nologo /target:winexe (('/out:')+$fixture) (Join-Path $PSScriptRoot 'NativeLauncherFixture.cs')
if($LASTEXITCODE){throw 'Synthetic fixture compilation failed.'}
foreach($mode in @('ready','slow','missing')){
    $folder=Join-Path $root $mode
    [void][IO.Directory]::CreateDirectory($folder)
    $launcher=Join-Path $folder 'HWID Checker.exe'
    Copy-Item -LiteralPath $ExePath -Destination $launcher
    if($mode -ne 'missing'){Copy-Item -LiteralPath $fixture -Destination (Join-Path $folder 'HWID Checker.App.exe')}
    $start=[Diagnostics.ProcessStartInfo]::new($launcher);$start.UseShellExecute=$false
    foreach($arg in @($folder,$mode,'spaces and Unicode Ω','literal "quotes"','trailing slash\')){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start)
    try{
        $clock=[Diagnostics.Stopwatch]::StartNew()
        do{$process.Refresh();if($process.MainWindowHandle -ne 0){break};Start-Sleep -Milliseconds 20}while(-not $process.HasExited -and $clock.Elapsed.TotalSeconds -lt 15)
        Assert ($process.MainWindowHandle -ne 0) ($mode+': native loading/error window appears')
        if($mode -ne 'missing'){
            while(-not (Test-Path -LiteralPath (Join-Path $folder 'child.pid')) -and $clock.Elapsed.TotalSeconds -lt 15){Start-Sleep -Milliseconds 20}
            $childId=[int][IO.File]::ReadAllText((Join-Path $folder 'child.pid'))
            $received=[IO.File]::ReadAllLines((Join-Path $folder 'arguments.txt'))
            Assert ($received.Count -eq 5 -and $received[2] -ceq 'spaces and Unicode Ω' -and $received[3] -ceq 'literal "quotes"' -and $received[4] -ceq 'trailing slash\') ($mode+': arguments retain exact quoting and Unicode')
        }
        if($mode -eq 'missing'){Start-Sleep -Milliseconds 350}
        if($mode -ne 'ready'){Assert ($process.CloseMainWindow()) ($mode+': close request is accepted')}
        Assert ($process.WaitForExit(15000)) ($mode+': launcher exits')
        if($mode -eq 'ready'){
            Assert ($process.ExitCode -eq 17 -and (Test-Path -LiteralPath (Join-Path $folder 'completed.txt'))) 'handoff waits for the managed child and returns its exit code'
        }elseif($mode -eq 'slow'){
            Assert ($process.ExitCode -eq 0 -and -not (Get-Process -Id $childId -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath (Join-Path $folder 'completed.txt'))) 'cancellation stops only the newly started child'
        }else{Assert ($process.ExitCode -ne 0) 'missing payload reports failure instead of silently disappearing'}
    }finally{if(-not $process.HasExited){$process.Kill($true)};$process.Dispose()}
}
[pscustomobject]@{success=$true;checks=$checks;syntheticOnly=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'result.json')
