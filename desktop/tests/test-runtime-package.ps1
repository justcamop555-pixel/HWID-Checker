#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Archive,[Parameter(Mandatory=$true)][string]$Version,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $root){throw 'Choose a new verification directory.'}
[void][IO.Directory]::CreateDirectory($root)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\..\Update-HWID.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Updater parsing failed.'}
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
foreach($assignment in $ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -like '$script:update*'},$false)){
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$package=Read-UpdatePackage $Archive (Join-Path $root 'valid') $Version
if($package.Files.Count -lt 10){throw 'The real runtime payload was not validated.'}
[Console]::WriteLine('PASS: all '+$package.Files.Count+' real package files pass updater checksum, path and version validation')
# Preserve every other file and its hash so the missing-runtime rule, rather
# than an unrelated checksum failure, rejects the incomplete package.
$broken=Join-Path $root 'incomplete.zip'
[IO.File]::Copy([IO.Path]::GetFullPath($Archive),$broken)
$zip=[IO.Compression.ZipFile]::Open($broken,[IO.Compression.ZipArchiveMode]::Update)
try{
    $zip.GetEntry('HWID Checker Desktop/hostfxr.dll').Delete()
    $entry=$zip.GetEntry('HWID Checker Desktop/SHA256SUMS.txt')
    $reader=[IO.StreamReader]::new($entry.Open())
    try{$lines=$reader.ReadToEnd() -split '\r?\n'|Where-Object {$_ -and $_ -notmatch '  hostfxr\.dll$'}}finally{$reader.Dispose()}
    $entry.Delete()
    $entry=$zip.CreateEntry('HWID Checker Desktop/SHA256SUMS.txt')
    $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try{$writer.Write(($lines -join "`n")+"`n")}finally{$writer.Dispose()}
}finally{$zip.Dispose()}
$rejected=$false
try{Read-UpdatePackage $broken (Join-Path $root 'invalid') $Version|Out-Null}catch{
    if($_.Exception.Message -notlike '*runtime package is incomplete*'){throw}
    $rejected=$true
}
if(-not $rejected){throw 'Incomplete runtime package was accepted.'}
[Console]::WriteLine('PASS: incomplete runtime payload is rejected despite consistent checksums')
[pscustomobject]@{success=$true;files=$package.Files.Count;checks=2}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'result.json')
