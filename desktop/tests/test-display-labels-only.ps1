param([string]$Source=(Join-Path $PSScriptRoot '..\engine\DesktopBridge.ps1'))
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
foreach($name in @('Get-DesktopDisplayFields','ConvertTo-DesktopInventory','Get-DesktopAbsolutePath')){
    $definition=$ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)|Select-Object -First 1
    if($null -eq $definition){throw ('Bridge function was not found: '+$name)}
    . ([scriptblock]::Create($definition.Extent.Text))
}
$checks=0
function Assert($value,$message){if(-not $value){throw ('FAILED: '+$message)};$script:checks++;[Console]::WriteLine('PASS: '+$message)}
$script:labelCalls=0;$script:valueCalls=0;$script:rejectValues=$false
function Get-FieldLabel($Name,$SectionName){$script:labelCalls++;return ($SectionName+'/'+$Name)}
function Format-RecordFieldValue($Name,$Value,$SectionName){
    $script:valueCalls++
    if($script:rejectValues){throw 'Comparison attempted to format discarded values.'}
    if($null -eq $Value){return 'null'}
    return (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
}
$inventory=[ordered]@{
    'Memory modules'=@(
        [pscustomobject][ordered]@{SerialNumber='000123';Capacity=0;Present=$false;HardwareID=@('ID-A','ID-00')},
        [ordered]@{SerialNumber='000124';Capacity=42;Present=$true;HardwareID=@('ID-B');Extra=[ordered]@{Raw='00000'}},
        [pscustomobject]@{customField='1'},
        [pscustomobject]@{customfield='2'})
    CPU=@([ordered]@{SerialNumber='000125'})
    Other=@(0,$false,$null,'00009')
    Empty=@()
}
$before=ConvertTo-Json -InputObject $inventory -Depth 16 -Compress
$normal=Get-DesktopDisplayFields $inventory
Assert ($script:valueCalls -eq 16) 'normal scan metadata formats every original field and scalar record'
Assert ($normal.Values['Memory modules'].Count -eq 4 -and $normal.Values.Other.Count -eq 4 -and $normal.Values.Empty.Count -eq 0) 'normal scan metadata retains record order, scalar records and empty sections'
Assert ($normal.Values['Memory modules'][0].SerialNumber -ceq '"000123"' -and $normal.Values.CPU[0].SerialNumber -ceq '"000125"') 'normal formatting receives exact leading-zero identifiers'
Assert ($normal.Values['Memory modules'][0].HardwareID -ceq '["ID-A","ID-00"]' -and $normal.Values['Memory modules'][1].Extra -ceq '{"Raw":"00000"}') 'normal formatting receives original arrays and nested field values'
Assert ($normal.Values.Other[0].Value -ceq '0' -and $normal.Values.Other[1].Value -ceq 'false' -and $normal.Values.Other[2].Value -ceq 'null' -and $normal.Values.Other[3].Value -ceq '"00009"') 'zero, false, null and string scalar values remain distinct'
Assert ($script:labelCalls -eq 9) 'each exact section and field-name pair is labeled once across repeated records'
Assert ($normal.Labels['Memory modules'].SerialNumber -ceq 'Memory modules/SerialNumber' -and $normal.Labels.CPU.SerialNumber -ceq 'CPU/SerialNumber') 'label caching remains scoped to the original section'
Assert ($normal.Labels['Memory modules'].customField -ceq 'Memory modules/customfield') 'case-varied unknown field names retain their final-observation label'
$script:valueCalls=0;$script:labelCalls=0;$script:rejectValues=$true
$labels=Get-DesktopDisplayFields $inventory -LabelsOnly
Assert ((ConvertTo-Json -InputObject $labels.Labels -Depth 16 -Compress) -ceq (ConvertTo-Json -InputObject $normal.Labels -Depth 16 -Compress)) 'labels-only mode produces the exact normal section labels and field order'
Assert ($script:valueCalls -eq 0 -and $null -eq $labels.Values) 'labels-only mode neither formats values nor allocates a value-result tree'
Assert ($script:labelCalls -eq 9 -and $labels.Labels.Empty.Count -eq 0) 'labels-only mode deduplicates exact labels and retains empty sections'
Assert ((ConvertTo-Json -InputObject $inventory -Depth 16 -Compress) -ceq $before) 'neither mode mutates the raw inventory or its identifiers'

# Execute the production Compare clause with in-memory readers. This proves the
# call site requests labels-only; the formatter above throws on any value read.
$actionSwitch=$ast.FindAll({param($node)$node -is [Management.Automation.Language.SwitchStatementAst] -and $node.Condition.Extent.Text -eq '$Action'},$true)|Select-Object -First 1
$compareClause=$actionSwitch.Clauses|Where-Object {$_.Item1.Value -eq 'Compare'}|Select-Object -First 1
if($null -eq $compareClause){throw 'The production Compare clause was not found.'}
function Resolve-ComparisonReportPath($Path){return $Path}
function Read-SavedReport($Path){return $inventory}
function Compare-Inventories($Previous,$Current){return [pscustomobject]@{PreviousCount=3;CurrentCount=3;SkippedSections=@();UnkeyedSections=@();AmbiguousDevices=@();SkippedFields=0;ScopeWarnings=@()}}
function Get-ComparisonDetails($Comparison){return @()}
$request=[pscustomobject]@{previousPath='C:\synthetic-previous.json';currentPath='C:\synthetic-current.json'}
$script:valueCalls=0;$script:labelCalls=0
$clause=$compareClause.Item2.Extent.Text
. ([scriptblock]::Create($clause.Substring(1,$clause.Length-2)))
Assert ($script:valueCalls -eq 0 -and $null -eq $result.fieldValues) 'the actual Compare action does not format discarded value metadata'
Assert ((ConvertTo-Json -InputObject $result.fieldLabels -Depth 16 -Compress) -ceq (ConvertTo-Json -InputObject $normal.Labels -Depth 16 -Compress)) 'the actual Compare action retains the exact label payload'

# Non-gating workload comparison. Timings describe only this synthetic metadata
# operation and are not startup measurements or a minimum-PC performance claim.
$script:rejectValues=$false
$large=[ordered]@{'Extended device inventory'=@(0..1999|ForEach-Object {
    [pscustomobject][ordered]@{Name=('Synthetic device '+$_);DeviceInstanceId=('USB\SYNTHETIC-'+$_);HardwareID=@('MODEL-0001','MODEL-0002');Present=$true;ConfigManagerErrorCode=0;Details=[ordered]@{Location='Synthetic location';Serial='000123'}}
})}
$allocated=@([GC].GetMethods()|Where-Object {$_.Name -eq 'GetAllocatedBytesForCurrentThread' -and $_.GetParameters().Count -eq 0}|Select-Object -First 1)
function Measure-Metadata([bool]$OnlyLabels){
    $script:valueCalls=0;$script:labelCalls=0
    $startBytes=if($allocated.Count){$allocated[0].Invoke($null,@())}else{$null}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $metadata=Get-DesktopDisplayFields $large -LabelsOnly:$OnlyLabels
    $clock.Stop()
    $endBytes=if($allocated.Count){$allocated[0].Invoke($null,@())}else{$null}
    [pscustomobject]@{Mode=$(if($OnlyLabels){'LabelsOnly'}else{'FullMetadata'});Records=2000;Milliseconds=[math]::Round($clock.Elapsed.TotalMilliseconds,2);AllocatedBytes=$(if($null -ne $startBytes){$endBytes-$startBytes}else{$null});ValueFormatCalls=$script:valueCalls;LabelCalls=$script:labelCalls}
}
# Warm up both paths using the small fixture before measuring the large one.
$null=Get-DesktopDisplayFields $inventory
$null=Get-DesktopDisplayFields $inventory -LabelsOnly
$measurements=@(Measure-Metadata $false;Measure-Metadata $true)
Assert ($measurements[0].ValueFormatCalls -eq 12000 -and $measurements[1].ValueFormatCalls -eq 0) 'the synthetic workload eliminates all 12000 discarded value-format calls'
[Console]::WriteLine(('All {0} display-label checks passed under PowerShell {1}.' -f $checks,$PSVersionTable.PSVersion))
[Console]::WriteLine((ConvertTo-Json -InputObject ([ordered]@{SyntheticOnly=$true;GatingTiming=$false;Measurements=$measurements}) -Depth 5 -Compress))
