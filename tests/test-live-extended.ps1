$ErrorActionPreference='Stop'
# Read-only diagnostic. Print counts and coverage only, never device identifiers.
$raw=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\hwid.bat'))
$code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
# Preloading the module must not copy its generated wrapper functions out of module scope.
Import-Module PnpDevice
$script:scanQueryWorker=New-ScanQueryWorker
$timer=[Diagnostics.Stopwatch]::StartNew()
try {
    $result=Invoke-ScanQuery {Get-ExtendedDeviceInventory}
    if(-not $result.Devices.Count){throw 'Extended scan returned no device nodes.'}
    [pscustomobject]@{
        Records=$result.Devices.Count;Source=$result.Info.Source
        Present=@($result.Devices | Where-Object {$_.Present -eq $true}).Count
        NotPresent=@($result.Devices | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count
        UnknownPresence=@($result.Devices | Where-Object {$null -eq $_.Present}).Count
        HiddenByNode=@($result.Devices | Where-Object {$_.HiddenByNodeFlag -eq $true}).Count
        HiddenByClass=@($result.Devices | Where-Object {$_.HiddenByClass -eq $true}).Count
        NodeFlagsRead=$result.Info.NodeFlagsRead;ClassFlagsRead=$result.Info.ClassFlagsRead
        PropertyReadErrors=$result.Info.PropertyReadErrors
        NativeStatusRecoveries=$result.Info.NativeStatusRecoveries
        ParentLinks=$result.Info.ParentLinks;HardwareIdRecoveries=$result.Info.HardwareIdRecoveries
        DetailReview=@($result.Devices | Where-Object {@(Get-ExtendedDeviceReview $_).Count -gt 0}).Count
        Seconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    } | ConvertTo-Json
}finally{$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null;$timer.Stop()}
