param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($definition.Extent.Text))
}
foreach($name in @('$sectionGroups','$identifierPattern','$script:scanTotal')){
    $assignment=$ast.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq $name},$false)|Select-Object -First 1
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$script:checks=0
function Assert($Value,$Description){if(-not $Value){throw ('FAILED: '+$Description)};$script:checks++;[Console]::WriteLine('PASS: '+$Description)}
function Write-Host {param($Object,$ForegroundColor,[switch]$NoNewline)}
$ownedConsole=$false;$redirected=$true
$palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}

function New-FirmwareQuery([string]$Secure,[string]$Tpm='return',[string]$Os='[pscustomobject]@{Caption="Synthetic Windows";Version="10.0";BuildNumber="99999";OSArchitecture="64-bit"}',[switch]$MissingCommand){
    # Define both provider mocks inside the actual query so neither execution
    # mode can call the machine's real firmware or CIM providers.
    $template=@'
function Get-Command {
    [CmdletBinding()]param([string]$Name)
    if(MISSING -and $Name -eq 'Confirm-SecureBootUEFI'){return}
    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
function Confirm-SecureBootUEFI {[CmdletBinding()]param() SECURE}
function Get-CimInstance {
    [CmdletBinding()]param($ClassName,$Namespace,$OperationTimeoutSec,$Property,$Filter)
    if($ClassName -eq 'Win32_Tpm'){
        if($Namespace -ne 'root/cimv2/Security/MicrosoftTpm' -or $OperationTimeoutSec -ne 10){throw 'Synthetic TPM namespace/timeout changed.'}
        TPM;return
    }
    if($ClassName -eq 'Win32_OperatingSystem'){
        if($Namespace -ne 'root/cimv2' -or $OperationTimeoutSec -ne 20){throw 'Synthetic Windows namespace/timeout changed.'}
        OS;return
    }
    throw ('No actual hardware calls permitted: '+$ClassName)
}
Get-WindowsInventory
'@
    return [scriptblock]::Create($template.Replace('MISSING',$(if($MissingCommand){'$true'}else{'$false'})).Replace('SECURE',$Secure).Replace('TPM;return',$Tpm+';return').Replace('OS;return',$Os+';return'))
}

$root=Join-Path $PSScriptRoot ('test-output-optional-firmware-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($mode in @('Direct','Worker')){
    $script:scanQueryWorker=if($mode -eq 'Worker'){New-ScanQueryWorker}else{$null}
    $report=[ordered]@{};$warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:scanTimings=New-Object 'System.Collections.Generic.List[object]';$script:scanStep=0
    try{
        $query=New-FirmwareQuery '$true' '[pscustomobject]@{SpecVersion="2.0, 0, 1";IsEnabled_InitialValue=$false;IsActivated_InitialValue=$false}'
        $rows=@(Invoke-ScanQuery $query)
        Assert ($rows.Count -eq 1 -and $rows[0].Caption -ceq 'Synthetic Windows' -and $rows[0].SecureBoot -ceq 'Enabled') ($mode+' real boolean true supplies Enabled without changing readable Windows data')
        Assert ($rows[0].SecureBootReadStatus -ceq 'Read' -and $null -eq $rows[0].SecureBootReadCode -and $rows[0].TPMReadStatus -ceq 'Read') ($mode+' successful optional reads keep their explicit success status')
        Assert ($rows[0].TPM -ceq 'Present / SpecVersion 2.0, 0, 1 / Disabled / Not activated' -and $null -eq $rows[0].TPMReadCode) ($mode+' original TPM specification text and actual false booleans remain exact')
        $disabled=@(Invoke-ScanQuery (New-FirmwareQuery '$false'))[0]
        Assert ($disabled.SecureBoot -ceq 'Disabled' -and $disabled.SecureBootReadStatus -ceq 'Read') ($mode+' only an actual boolean false establishes Disabled')
        Assert ($null -eq $disabled.TPM -and $disabled.TPMReadStatus -ceq 'Not reported' -and $null -eq $disabled.TPMReadCode) ($mode+' empty TPM results do not invent absence, disabled state or a read error')
        $missing=@(Invoke-ScanQuery (New-FirmwareQuery 'throw "A missing reader must never be invoked"' -MissingCommand))[0]
        Assert ($null -eq $missing.SecureBoot -and $missing.SecureBootReadStatus -ceq 'Reader not available' -and $missing.SecureBootReadCode -ceq 'READ-03' -and $missing.Caption -ceq 'Synthetic Windows') ($mode+' an unavailable Secure Boot command remains distinct from Disabled and an unread OS')

        foreach($case in @(
            @{Name='access';Code='READ-01';Reason='Access blocked';Expression='throw [UnauthorizedAccessException]::new("Synthetic localized denial")'},
            @{Name='timeout';Code='READ-02';Reason='Provider timed out';Expression='throw [TimeoutException]::new("Synthetic localized wait failure")'},
            @{Name='unsupported';Code='READ-03';Reason='Provider unavailable';Expression='throw [NotSupportedException]::new("Synthetic localized unsupported platform")'}
        )){
            $record=@(Invoke-ScanQuery (New-FirmwareQuery $case.Expression))[0]
            Assert ($null -eq $record.SecureBoot -and $record.SecureBootReadCode -ceq $case.Code -and $record.SecureBootReadStatus -ceq $case.Reason -and $record.Caption -ceq 'Synthetic Windows') ($mode+' Secure Boot '+$case.Name+' stays unknown with the original typed classification')
            $record=@(Invoke-ScanQuery (New-FirmwareQuery '$true' $case.Expression))[0]
            Assert ($null -eq $record.TPM -and $record.TPMReadCode -ceq $case.Code -and $record.TPMReadStatus -ceq $case.Reason -and $record.Caption -ceq 'Synthetic Windows') ($mode+' TPM '+$case.Name+' cannot become Present or discard readable Windows data')
        }
        foreach($state in @('return','"False"','0','@($false,$true)')){
            $record=@(Invoke-ScanQuery (New-FirmwareQuery $state))[0]
            Assert ($null -eq $record.SecureBoot -and $record.SecureBootReadCode -ceq 'READ-06' -and $record.SecureBootReadStatus -ceq 'Invalid scan data') ($mode+' malformed Secure Boot output '+$state+' cannot establish Enabled or Disabled')
        }
        $nonterminating='Write-Error -Exception ([UnauthorizedAccessException]::new("Synthetic nonterminating optional denial")) -ErrorAction Continue; $false'
        $record=@(Invoke-ScanQuery (New-FirmwareQuery $nonterminating))[0]
        Assert ($record.Caption -ceq 'Synthetic Windows' -and $null -eq $record.SecureBoot -and $record.SecureBootReadCode -ceq 'READ-01') ($mode+' non-terminating Secure Boot errors cannot claim Disabled or escape into the required OS read')
        $nonterminating='Write-Error -Exception ([UnauthorizedAccessException]::new("Synthetic nonterminating optional denial")) -ErrorAction Continue; [pscustomobject]@{SpecVersion="2.0"}'
        $record=@(Invoke-ScanQuery (New-FirmwareQuery '$true' $nonterminating))[0]
        Assert ($record.Caption -ceq 'Synthetic Windows' -and $null -eq $record.TPM -and $record.TPMReadCode -ceq 'READ-01') ($mode+' non-terminating TPM errors discard partial state while retaining readable Windows data')
        $record=@(Invoke-ScanQuery (New-FirmwareQuery '$true' '[pscustomobject]@{}'))[0]
        Assert ($null -eq $record.TPM -and $record.TPMReadCode -ceq 'READ-06' -and $record.TPMReadStatus -ceq 'Invalid scan data') ($mode+' an empty TPM record cannot invent Present')
        $record=@(Invoke-ScanQuery (New-FirmwareQuery '$true' '[pscustomobject]@{SpecVersion=@("2.0");IsEnabled_InitialValue="False";IsActivated_InitialValue=0}'))[0]
        Assert ($null -eq $record.TPM -and $record.TPMReadCode -ceq 'READ-06') ($mode+' malformed TPM field shapes cannot masquerade as usable state')
        $record=@(Invoke-ScanQuery (New-FirmwareQuery '$true' '[pscustomobject]@{IsActivated_InitialValue=$false}'))[0]
        Assert ($record.TPM -ceq 'Present / Not activated' -and $record.TPMReadStatus -ceq 'Read') ($mode+' a real activation false remains usable even when enabled/specification fields are absent')

        Section 'Windows' (New-FirmwareQuery 'throw [UnauthorizedAccessException]::new("Synthetic optional denial")' 'throw [TimeoutException]::new("Synthetic optional timeout")')
        Assert ((Test-SectionReadable $report.Windows) -and $scanTimings[-1].Status -ceq 'READ' -and $warnings.Count -eq 0 -and $report.Windows[0].Caption -ceq 'Synthetic Windows') ($mode+' optional permission and timeout failures do not mark readable Windows as NOT READ')
        Assert ($report.Windows[0].SecureBootReadCode -ceq 'READ-01' -and $report.Windows[0].TPMReadCode -ceq 'READ-02') ($mode+' accepted Windows records keep both optional read diagnostics')
        $report['Report info']=@{Version='3.96';Computer='SYNTHETIC';Generated='2026-11-15T12:00:00Z'}
        $report['CPU']=@([pscustomobject]@{ProcessorId='000123';Name='Synthetic CPU'})
        $report['Scan timing']=@($scanTimings.ToArray())
        $text=Get-PlainRecords $report.Windows 'Windows' | Out-String
        Assert ($text -match 'Secure Boot read status' -and $text -match 'TPM read code' -and $text -match 'READ-01' -and $text -match 'READ-02') ($mode+' TXT formatting names optional firmware status and code fields clearly')
        $stem=Join-Path $root $mode
        Write-ReportPair $stem $text ($report | ConvertTo-Json -Depth 16)
        $saved=Read-SavedReport ($stem+'.json')
        Assert ($saved.Windows[0].SecureBootReadCode -ceq 'READ-01' -and $saved.Windows[0].TPMReadCode -ceq 'READ-02' -and $saved.CPU[0].ProcessorId -ceq '000123') ($mode+' saved JSON preserves optional failures and exact identifiers in other sections')
        Assert ((Compare-Inventories $report $saved).Changes.Count -eq 0) ($mode+' optional diagnostic fields do not manufacture identifier changes after a report round trip')

        Section 'Windows' (New-FirmwareQuery '$true' 'return' 'throw [UnauthorizedAccessException]::new("Synthetic OS denied")')
        Assert (-not (Test-SectionReadable $report.Windows) -and $scanTimings[-1].Status -ceq 'UNAVAILABLE' -and $scanTimings[-1].FailureCode -ceq 'READ-01') ($mode+' a genuine OS read failure remains NOT READ despite successful optional reads')
        foreach($invalidOs in @(
            @{Name='empty object';Expression='[pscustomobject]@{}'},
            @{Name='irrelevant-only object';Expression='[pscustomobject]@{Name="Synthetic unrelated field";SecureBootReadStatus="Synthetic status text"}'},
            @{Name='scalar record';Expression='42'}
        )){
            # Place a valid row first: a later invalid row must reject the whole
            # OS attempt, rather than leaking a seemingly complete partial list.
            $query=New-FirmwareQuery '$true' 'return' ('[pscustomobject]@{Caption="Synthetic partial Windows"};'+$invalidOs.Expression)
            $partial=@();$failure=$null
            try{$partial=@(Invoke-ScanQuery $query)}catch{$failure=Get-ScanFailureInfo $_}
            Assert ($partial.Count -eq 0 -and $null -ne $failure -and $failure.Code -ceq 'READ-06') ($mode+' '+$invalidOs.Name+' rejects partial OS output before firmware metadata can imply success')
            Section 'Windows' $query
            Assert (-not (Test-SectionReadable $report.Windows) -and $scanTimings[-1].Status -ceq 'UNAVAILABLE' -and $scanTimings[-1].FailureCode -ceq 'READ-06' -and $scanTimings[-1].Results -eq 0) ($mode+' '+$invalidOs.Name+' becomes NOT READ despite a successful Secure Boot value')
        }
        Section 'Windows' (New-FirmwareQuery '$true' 'return' 'return')
        Assert (-not (Test-SectionReadable $report.Windows) -and $scanTimings[-1].Status -ceq 'UNAVAILABLE' -and $scanTimings[-1].FailureCode -ceq 'READ-04' -and $scanTimings[-1].Results -eq 0) ($mode+' a successful zero-row OS query stays READ-04 rather than becoming a firmware-only Windows record')
    }finally{
        if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
    }
}
Assert ((Get-FieldLabel 'SecureBootReadStatus' 'Windows') -ceq 'Secure Boot read status' -and (Get-FieldLabel 'TPMReadStatus' 'Windows') -ceq 'TPM read status') 'Firmware read labels are section-specific and human-readable'
[Console]::WriteLine(('All {0} optional-firmware checks passed under PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion))
