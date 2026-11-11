param([string]$Action,[string]$BatPath,[string]$RequestPath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $BatPath) 'last-operation.txt'),$PSScriptRoot,(New-Object Text.UTF8Encoding($false)))
function Emit($Value){[Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 15 -Compress));[Console]::Out.Flush()}
$mode=[IO.File]::ReadAllText($BatPath).Trim()
$inventory=[ordered]@{'Report info'=@{Version='3.83';Computer='SYNTHETIC';Generated='2026-11-04T12:00:00-05:00'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='SYNTHETIC-ONLY-000123';Name='Synthetic é 中文'})}
if($Action -eq 'Compare'){
    $request=[IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
    $current=[IO.File]::ReadAllText($request.currentPath) | ConvertFrom-Json
    Emit @{type='result';data=@{changes=@();previousCount=1;currentCount=1;skippedSections=@();skippedFields=0;scopeWarnings=@();previousPath=$request.previousPath;processor=$current.CPU[0].ProcessorId}}
    exit 0
}
if($Action -eq 'Export'){
    $request=[IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
    [void][IO.Directory]::CreateDirectory($request.folder)
    $textPath=Join-Path $request.folder 'synthetic.txt';$jsonPath=Join-Path $request.folder 'synthetic.json'
    $json=[IO.File]::ReadAllText($request.inventoryPath)
    [IO.File]::WriteAllText($textPath,'Synthetic report',(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($jsonPath,$json,(New-Object Text.UTF8Encoding($false)))
    Emit @{type='result';data=@{textPath=$textPath;jsonPath=$jsonPath;folder=$request.folder}}
    exit 0
}
if($mode -eq 'read-guidance'){
    Emit @{type='progress';section='CPU';name='Synthetic é 中文';completed=1;total=18;status='NOT READ';records=0;message='Windows denied access';failureCode='READ-01';nextStep='Synthetic retry guidance é 中文'}
}else{Emit @{type='progress';section='CPU';name='Synthetic é 中文';completed=1;total=18;status='READ';records=1;message='Synthetic only'}}
if($mode -eq 'slow'){Start-Sleep -Seconds 15}
if($mode -eq 'error'){Emit @{type='error';code='READ-02';message='Synthetic localized é 中文 failure'};exit 1}
if($mode -eq 'error-hang'){Emit @{type='error';code='READ-02';message='Synthetic localized é 中文 failure'};Start-Sleep -Seconds 15;exit 1}
if($mode -eq 'bad-json'){[Console]::Out.WriteLine('invalid protocol');exit 0}
if($mode -eq 'no-result'){exit 0}
if($mode -eq 'incomplete'){Emit @{type='result';data=@{inventory=@{}}};exit 0}
if($mode -eq 'stderr'){[Console]::Error.Write(('X'*200000));[Console]::Error.Flush()}
$result=@{type='result';data=@{inventory=$inventory;identifiers=@();warnings=@();review=@{Total=0};version='3.83';captured='2026-11-04T12:00:00-05:00'}}
Emit $result
if($mode -eq 'duplicate'){Emit $result}
if($mode -eq 'bad-exit'){exit 7}
exit 0
