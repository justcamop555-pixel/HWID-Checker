param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
$checks=0
function Assert($value,$description){if(-not $value){throw ('FAILED: '+$description)};$script:checks++;[Console]::WriteLine('PASS: '+$description)}
function Read-PartialFixture([string]$Case){
    $query=[scriptblock]::Create(@'
$script:attempts=New-Object 'System.Collections.Generic.List[object]'
function Get-PnpDeviceProperty {
    [CmdletBinding()]param([string[]]$InstanceId,[string[]]$KeyName,[int]$ThrottleLimit)
    $script:attempts.Add([pscustomobject]@{Ids=@($InstanceId);Concurrency=$ThrottleLimit})
    if($InstanceId.Count -gt 1){
        if($InstanceId[0] -eq 'USB\NODE0'){
            [pscustomobject]@{InstanceId=' usb\node0 ';KeyName='DEVPKEY_Device_HardwareIds';Data=@('Exact-000123')}
            if('FIXTURE_CASE' -in @('AllReturned','MissingOptional','Healthy')){
                foreach($id in $InstanceId|Select-Object -Skip 1){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('Original-0000')}}
            }
            if('FIXTURE_CASE' -in @('Foreign','BadKeyNoError')){
                [pscustomobject]@{InstanceId='USB\UNREQUESTED';KeyName='DEVPKEY_Device_HardwareIds';Data=@('FOREIGN-0000')}
                [pscustomobject]@{InstanceId='USB\NODE1';KeyName=@('DEVPKEY_Device_HardwareIds');Data=@('MALFORMED-KEY-0000')}
            }
            if('FIXTURE_CASE' -in @('NoError','BadKeyNoError','Healthy')){return}
            Write-Error 'Synthetic node disappeared during this batch' -ErrorAction Continue
            $blocked='FIXTURE_CASE' -replace '^MixedTerminal','' -replace '^Blocked',''
            $exception=switch($blocked){
                'Access' {[UnauthorizedAccessException]::new('Synthetic localized access failure')}
                'Timeout' {[TimeoutException]::new('Synthetic localized timeout')}
                'Provider' {[NotSupportedException]::new('Synthetic localized provider failure')}
            }
            if($null -ne $exception){
                $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new($exception,'Synthetic.BlockedBatch',[Management.Automation.ErrorCategory]::NotSpecified,$InstanceId[0]))
            }
            if('FIXTURE_CASE' -like 'MixedTerminal*'){throw 'Synthetic generic terminal failure after a blocked error'}
            return
        }
        foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_HardwareIds';Data=@('Later-0000')}}
        return
    }
    if('FIXTURE_CASE' -like 'Stop*'){
        $exception=switch('FIXTURE_CASE'){
            'StopAccess' {[UnauthorizedAccessException]::new('Synthetic localized retry denial')}
            'StopTimeout' {[TimeoutException]::new('Synthetic localized retry timeout')}
            'StopProvider' {[NotSupportedException]::new('Synthetic localized retry provider failure')}
        }
        $PSCmdlet.WriteError([Management.Automation.ErrorRecord]::new($exception,'Synthetic.BlockedRetry',[Management.Automation.ErrorCategory]::NotSpecified,$InstanceId[0]))
        return
    }
    if('FIXTURE_CASE' -eq 'PersistentGeneric'){
        Write-Error 'Synthetic node remained unavailable on its only retry' -ErrorAction Continue
        return
    }
    [pscustomobject]@{InstanceId=$InstanceId[0];KeyName='DEVPKEY_Device_HardwareIds';Data=@('Recovered-0001')}
}
$ids=if('FIXTURE_CASE' -eq 'Duplicates'){@('USB\NODE0',' usb\node0 ','USB\NODE1','USB\NODE1')}else{@(0..39|ForEach-Object {'USB\NODE'+$_})}
$keys=@('DEVPKEY_Device_HardwareIds','DEVPKEY_Device_CompatibleIds')
$read=Read-DevicePropertyBatches $ids $keys
[pscustomobject]@{Read=$read;Attempts=@($script:attempts.ToArray());Codes=@($read.Errors|ForEach-Object {(Get-ScanFailureInfo $_).Code})}
'@.Replace('FIXTURE_CASE',$Case))
    return @(Invoke-ScanQuery $query)[0]
}
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    try{
        $partial=Read-PartialFixture 'Partial'
        Assert ($partial.Read.RetriedDevices -eq 31 -and $partial.Attempts.Count -eq 33) ($mode+' a generic non-terminating partial batch retries only its 31 missing nodes once')
        Assert ($partial.Read.NodesRequested -eq 40 -and $partial.Read.NodesReturned -eq 40 -and $partial.Read.NodesWithoutRows -eq 0 -and $partial.Read.Rows.Count -eq 40) ($mode+' targeted retries recover complete distinct-node coverage without dropping the later batch')
        Assert ($partial.Read.Rows[0].InstanceId -ceq ' usb\node0 ' -and $partial.Read.Rows[0].Data[0] -ceq 'Exact-000123' -and $partial.Read.Rows[-1].Data[0] -ceq 'Later-0000') ($mode+' accepted exact IDs and raw instance padding survive recovery and later independent batches')
        $single=@($partial.Attempts|Where-Object {$_.Ids.Count -eq 1})
        Assert (@($single|Where-Object {$_.Ids[0] -eq 'USB\NODE0'}).Count -eq 0 -and @($single|Group-Object {$_.Ids[0]}|Where-Object Count -ne 1).Count -eq 0) ($mode+' successful nodes are not queried again and each missing node receives at most one retry')
        Assert (@($partial.Attempts|Where-Object Concurrency -ne 1).Count -eq 0 -and $partial.Read.Errors.Count -gt 0 -and $partial.Codes -contains 'READ-05') ($mode+' serialized calls and original generic error diagnostics are retained after recovery')
        foreach($case in @('AllReturned','MissingOptional')){
            $read=Read-PartialFixture $case
            Assert ($read.Read.RetriedDevices -eq 0 -and $read.Attempts.Count -eq 2 -and $read.Read.NodesReturned -eq 40 -and $read.Read.Errors.Count -gt 0) ($mode+' '+$case+' does not retry complete node coverage merely because optional keys or an error remain')
        }
        $read=Read-PartialFixture 'NoError'
        Assert ($read.Read.RetriedDevices -eq 0 -and $read.Attempts.Count -eq 2 -and $read.Read.NodesWithoutRows -eq 31 -and $read.Read.Errors.Count -eq 0) ($mode+' a quiet omitted optional property set does not authorize recovery calls')
        $read=Read-PartialFixture 'Foreign'
        Assert ($read.Read.RetriedDevices -eq 31 -and $read.Read.NodesReturned -eq 40 -and $read.Read.NodesWithoutRows -eq 0) ($mode+' foreign-node and malformed-key rows cannot mask missing requested nodes')
        Assert (@($read.Read.Rows|Where-Object {$_.InstanceId -ceq 'USB\UNREQUESTED'}).Count -eq 1 -and @($read.Read.Rows|Where-Object {$_.KeyName -is [array]}).Count -eq 1) ($mode+' raw unrequested and malformed observations remain available without counting as requested coverage')
        $read=Read-PartialFixture 'BadKeyNoError'
        Assert ($read.Read.RetriedDevices -eq 0 -and $read.Read.NodesReturned -eq 9 -and $read.Read.NodesWithoutRows -eq 31) ($mode+' malformed property keys cannot falsely count as returned coverage even without recovery')
        foreach($kind in @('Access','Timeout','Provider')){
            $expected=switch($kind){'Access'{'READ-01'} 'Timeout'{'READ-02'} 'Provider'{'READ-03'}}
            foreach($prefix in @('Blocked','MixedTerminal')){
                $read=Read-PartialFixture ($prefix+$kind)
                Assert ($read.Read.RetriedDevices -eq 0 -and $read.Attempts.Count -eq 2 -and $read.Read.NodesReturned -eq 9) ($mode+' '+$prefix+$kind+' suppresses expansion even when a generic batch error is also present')
                Assert ($read.Codes -contains $expected -and $read.Codes -contains 'READ-05' -and $read.Read.Rows[0].Data[0] -ceq 'Exact-000123') ($mode+' '+$prefix+$kind+' preserves typed blocked errors, generic history and accepted IDs')
            }
            $read=Read-PartialFixture ('Stop'+$kind)
            Assert ($read.Read.RetriedDevices -eq 1 -and $read.Attempts.Count -eq 3 -and $read.Read.NodesReturned -eq 9 -and $read.Codes -contains $expected) ($mode+' '+$kind+' stops the new missing-node recovery immediately while the later batch still runs')
        }
        $read=Read-PartialFixture 'PersistentGeneric'
        Assert ($read.Read.RetriedDevices -eq 31 -and $read.Attempts.Count -eq 33 -and $read.Read.NodesWithoutRows -eq 31 -and $read.Read.Errors.Count -eq 32) ($mode+' unrecovered generic failures remain explicit and cannot recurse into further retries')
        $read=Read-PartialFixture 'Duplicates'
        Assert ($read.Read.RetriedDevices -eq 1 -and $read.Attempts.Count -eq 2 -and $read.Read.NodesRequested -eq 2 -and $read.Read.NodesReturned -eq 2) ($mode+' normalized duplicate requests cannot retry the same missing node twice')
        $read=Read-PartialFixture 'Healthy'
        Assert ($read.Read.RetriedDevices -eq 0 -and $read.Read.Errors.Count -eq 0 -and $read.Read.NodesReturned -eq 40) ($mode+' a later healthy query starts with clean recovery state')
    }finally{if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}}
}
[Console]::WriteLine(('All {0} partial-property recovery checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
