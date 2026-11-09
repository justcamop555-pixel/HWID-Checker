param(
    [Parameter(Mandatory=$true)][ValidateSet('Scan','Compare','Export')][string]$Action,
    [Parameter(Mandatory=$true)][string]$BatPath,
    [string]$RequestPath
)

$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$InformationPreference='SilentlyContinue'
$WarningPreference='SilentlyContinue'
$script:bridgeResultWritten=$false
$script:bridgeFailureCode='BRIDGE-01'
try{[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)}catch{}

function Send-DesktopMessage($Message) {
    $json=ConvertTo-Json -InputObject $Message -Depth 32 -Compress -ErrorAction Stop -WarningAction Stop
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}
function Send-DesktopProgress([string]$Name,[int]$Completed,[int]$Total,[string]$Status,[int]$Records,[string]$Message,[double]$Seconds=-1) {
    Send-DesktopMessage ([ordered]@{type='progress';section=$Name;name=$Name;completed=$Completed;total=$Total;status=$Status;records=$Records;message=$Message;seconds=$(if($Seconds -ge 0){$Seconds}else{$null})})
}
function Get-DesktopAbsolutePath($Value,[string]$Description) {
    if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or -not [IO.Path]::IsPathRooted($Value)){throw [IO.InvalidDataException]::new(($Description+' must be an absolute path.'))}
    return [IO.Path]::GetFullPath($Value)
}
function ConvertTo-DesktopInventory($Inventory) {
    $copy=[ordered]@{}
    if($Inventory -is [Collections.IDictionary]){foreach($key in $Inventory.Keys){$copy[$key]=$Inventory[$key]}}
    else{foreach($property in $Inventory.PSObject.Properties){$copy[$property.Name]=$property.Value}}
    return $copy
}
function Get-DesktopDisplayFields($Inventory) {
    $labels=[ordered]@{};$values=[ordered]@{}
    foreach($section in $Inventory.Keys){
        $sectionLabels=[ordered]@{};$sectionValues=New-Object 'System.Collections.Generic.List[object]'
        foreach($record in @($Inventory[$section])){
            $fields=[ordered]@{}
            $properties=if($record -is [Collections.IDictionary]){foreach($key in $record.Keys){[pscustomobject]@{Name=$key;Value=$record[$key]}}}elseif($record -is [pscustomobject]){$record.PSObject.Properties}else{@([pscustomobject]@{Name='Value';Value=$record})}
            foreach($property in $properties){
                $sectionLabels[$property.Name]=Get-FieldLabel $property.Name $section
                $fields[$property.Name]=Format-RecordFieldValue $property.Name $property.Value $section
            }
            $sectionValues.Add($fields)
        }
        $labels[$section]=$sectionLabels;$values[$section]=@($sectionValues.ToArray())
    }
    return [pscustomobject]@{Labels=$labels;Values=$values}
}

try {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'The HWID desktop collector requires Windows.'}
    if($PSVersionTable.PSVersion -lt [version]'5.1'){throw 'The HWID desktop collector requires Windows PowerShell 5.1 or PowerShell 7.'}
    if($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){throw 'The HWID desktop collector requires an approved FullLanguage PowerShell session.'}
    $BatPath=Get-DesktopAbsolutePath $BatPath 'BAT engine path'
    if(-not [IO.File]::Exists($BatPath)){throw 'The companion hwid.bat was not found. Keep the desktop app and its engine files together.'}
    $raw=[IO.File]::ReadAllText($BatPath)
    $parts=$raw -split '(?m)^# POWERSHELL_START\r?$',2
    if($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])){throw 'The companion BAT is incomplete or is not a supported HWID Checker engine.'}
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($parts[1],[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'The companion BAT contains PowerShell syntax errors. Restore a complete engine copy.'}
    # Load collection/report functions only. The BAT's startup, console and menu
    # statements are deliberately not executed by the desktop transport.
    foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    foreach($constant in @('$sectionGroups','$identifierPattern','$script:scanTotal')){
        $assignment=$ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq $constant},$false) | Select-Object -First 1
        if($null -eq $assignment){throw ('The companion BAT is missing a required engine setting: '+$constant)}
        . ([scriptblock]::Create($assignment.Extent.Text))
    }
    foreach($required in @('Invoke-HardwareScan','Get-IdentifierRows','Get-ReviewSummary','Read-SavedReport','Compare-Inventories','Get-ComparisonDetails','Get-IdentifierChangeText','Save-Reports')){
        if(-not (Test-Path -LiteralPath ('Function:\'+$required))){throw ('The companion BAT is missing a required engine function: '+$required)}
    }
    $env:HWID_SCRIPT=$BatPath
    $ownedConsole=$false;$redirected=$true
    $display=[pscustomobject]@{Mode='Desktop companion'}
    $palette=@{Heading='Cyan';Text='White';Muted='Gray';Border='DarkGray';Good='Green';Warn='Yellow';Error='Red'}
    $script:bridgeCurrentSection='Preparing';$script:bridgeProgressStatus='READING'
    $script:bridgeLastPulse=[datetime]::UtcNow
    $script:bridgeSaveError=$null;$script:bridgeSaveCompleted=$false

    # The desktop owns rendering. Preserve the original scan/report functions
    # and replace their presentation callbacks with structured protocol events.
    function Write-Host {param($Object,$ForegroundColor,$BackgroundColor,[switch]$NoNewline)}
    function Reset-UiPage {}
    function Start-UiReport {param([switch]$Scanning)}
    function Complete-UiReport {}
    function Write-Heading {param($Title)}
    function Write-PnpLine {param($Text,$Color)}
    function Write-PnpValue {
        param($Label,$Value,$Color)
        if([string]$Label -like 'SAVE-01*'){$script:bridgeSaveError=[string]$Value}
        elseif([string]$Label -eq 'SAVED'){$script:bridgeSaveCompleted=$true}
    }
    function Show-ScanGroup {param($Name) return $null}
    function Start-ScanLine {
        param($Prefix)
        $name='Extended device inventory';$completed=$scanTotal
        if([string]$Prefix -match '\[(\d+)/(\d+)\]\s+(.+?)\s*$'){$name=$matches[3].Trim();$completed=[int]$matches[1]-1}
        $script:bridgeCurrentSection=$name;$script:bridgeProgressStatus='READING';$script:bridgeLastPulse=[datetime]::UtcNow
        Send-DesktopProgress $name $completed ($scanTotal+1) 'READING' 0 'Reading the Windows provider.'
        return [pscustomobject]@{Name=$name}
    }
    function Show-ScanReadResult {
        param($State,$Name,$Status,[int]$Count,$Summary,[double]$Seconds,$Color)
        $script:bridgeProgressStatus=$Status
        Send-DesktopProgress $Name $script:scanStep ($scanTotal+1) $Status $Count ([string]$Summary) $Seconds
        return $null
    }
    function Complete-ScanLine {
        param($State,$Name,$Text,$Color)
        $status='NOT READ';$count=0
        if([string]$Text -match '^\[READ\]\s+(\d+)'){$status='READ';$count=[int]$matches[1]}
        $script:bridgeProgressStatus=$status
        Send-DesktopProgress 'Extended device inventory' ($scanTotal+1) ($scanTotal+1) $status $count ([string]$Text)
    }
    function Update-ScanWaiting {param($State,[double]$Seconds)}
    function Update-ScanProgress {
        param([int]$Completed=$script:scanStep)
        if($script:bridgeProgressStatus -ne 'READING' -or ([datetime]::UtcNow-$script:bridgeLastPulse).TotalSeconds -lt 1){return}
        $script:bridgeLastPulse=[datetime]::UtcNow
        Send-DesktopProgress $script:bridgeCurrentSection $Completed ($scanTotal+1) 'READING' 0 'Waiting for the Windows provider.'
    }
    function Show-ScanCompletion {param($Inventory,$Identifiers,[int]$Read,[int]$Total,[bool]$Complete,[string]$ExtendedNote) return $null}
    function Get-ReportLocations {
        param([string]$ScriptPath,[string]$LocalRoot)
        return [pscustomobject]@{Primary=$script:bridgeExportFolder;Fallback=$script:bridgeExportFolder;Search=@($script:bridgeExportFolder)}
    }

    $request=$null
    if($RequestPath){
        $script:bridgeFailureCode='BRIDGE-03'
        $RequestPath=Get-DesktopAbsolutePath $RequestPath 'Request file'
        if(-not [IO.File]::Exists($RequestPath)){throw 'The desktop request file is missing.'}
        if((Get-Item -LiteralPath $RequestPath).Length -gt 1MB){throw 'The desktop request exceeds its 1 MB limit.'}
        $requestText=Read-ReportJsonText $RequestPath
        Assert-UniqueJsonProperties $requestText
        $request=Convert-ReportJson $requestText
        if($request -isnot [pscustomobject]){throw 'The desktop request must be a JSON object.'}
    }

    switch($Action){
        'Scan' {
            $script:bridgeFailureCode='BRIDGE-02'
            $scanNumber=1
            if($null -ne $request -and $null -ne $request.scanNumber){
                $number=0
                if($request.scanNumber -is [bool] -or -not [int]::TryParse([string]$request.scanNumber,[ref]$number) -or $number -lt 1){throw 'The scan number must be a positive integer.'}
                $scanNumber=$number
            }
            Send-DesktopProgress 'Preparing' 0 ($scanTotal+1) 'READING' 0 'Loading the BAT hardware collector.'
            $snapshot=Invoke-HardwareScan $scanNumber -UseWorker $true -IncludeExtended $true
            if($null -eq $snapshot -or -not $snapshot.Completed -or $snapshot.Inventory -isnot [Collections.IDictionary] -or @($snapshot.Inventory['Scan timing']).Count -ne $scanTotal){throw 'The BAT engine did not return a completed hardware snapshot.'}
            foreach($section in @($sectionGroups.Values | ForEach-Object {$_})+@('PnP hardware IDs')){if(-not $snapshot.Inventory.Contains($section)){throw ('The BAT engine did not return the expected section: '+$section)}}
            $inventory=$snapshot.Inventory
            $review=Get-ReviewSummary $inventory $snapshot.Identifiers $snapshot.Warnings
            $displayFields=Get-DesktopDisplayFields $inventory
            $result=[ordered]@{inventory=$inventory;identifiers=@($snapshot.Identifiers);warnings=@($snapshot.Warnings.ToArray());review=$review;version=[string]$inventory['Report info'].Version;captured=[string]$inventory['Report info'].Generated;fieldLabels=$displayFields.Labels;fieldValues=$displayFields.Values}
        }
        'Compare' {
            $script:bridgeFailureCode='BRIDGE-03'
            if($null -eq $request){throw 'Comparison requires a request with previousPath and currentPath.'}
            $previousPath=Get-DesktopAbsolutePath $request.previousPath 'Previous snapshot'
            $currentPath=Get-DesktopAbsolutePath $request.currentPath 'Current snapshot'
            $previous=ConvertTo-DesktopInventory (Read-SavedReport (Resolve-ComparisonReportPath $previousPath))
            $current=ConvertTo-DesktopInventory (Read-SavedReport (Resolve-ComparisonReportPath $currentPath))
            $comparison=Compare-Inventories $previous $current
            $changes=@(foreach($change in (Get-ComparisonDetails $comparison)){
                [ordered]@{kind=$change.Kind;section=$change.Section;field=$change.Field;device=$change.Device;previous=$change.Previous;current=$change.Current;difference=$(if($change.Kind -eq 'Changed'){Get-IdentifierChangeText $change.Previous $change.Current}else{''})}
            })
            $result=[ordered]@{changes=$changes;previousCount=$comparison.PreviousCount;currentCount=$comparison.CurrentCount;skippedSections=@($comparison.SkippedSections);skippedFields=$comparison.SkippedFields;scopeWarnings=@($comparison.ScopeWarnings);previousComputer=[string]$previous.'Report info'.Computer;previousCaptured=[string]$previous.'Report info'.Generated;currentComputer=[string]$current.'Report info'.Computer;currentCaptured=[string]$current.'Report info'.Generated;fieldLabels=(Get-DesktopDisplayFields $previous).Labels;fieldValues=$null}
        }
        'Export' {
            $script:bridgeFailureCode='BRIDGE-03'
            if($null -eq $request){throw 'Export requires a request with inventoryPath and folder.'}
            $inventoryPath=Get-DesktopAbsolutePath $request.inventoryPath 'Current inventory'
            $script:bridgeExportFolder=Get-DesktopAbsolutePath $request.folder 'Export folder'
            $script:report=ConvertTo-DesktopInventory (Read-SavedReport $inventoryPath)
            $script:lastSavedReportPath=$null
            Save-Reports
            if($script:bridgeSaveError){$script:bridgeFailureCode='SAVE-01';throw $script:bridgeSaveError}
            if(-not $script:bridgeSaveCompleted -or -not $script:lastSavedReportPath){$script:bridgeFailureCode='SAVE-01';throw 'The BAT engine did not confirm the report pair was saved.'}
            $jsonPath=[IO.Path]::GetFullPath($script:lastSavedReportPath)
            $textPath=[IO.Path]::ChangeExtension($jsonPath,'.txt')
            if(-not [IO.File]::Exists($jsonPath) -or -not [IO.File]::Exists($textPath)){$script:bridgeFailureCode='SAVE-01';throw 'The completed report pair could not be found.'}
            $result=[ordered]@{textPath=$textPath;jsonPath=$jsonPath;folder=$script:bridgeExportFolder}
        }
    }
    Send-DesktopMessage ([ordered]@{type='result';data=$result})
    $script:bridgeResultWritten=$true
    exit 0
}catch{
    $message=$_.Exception.Message
    $code=$script:bridgeFailureCode
    if($message -match '\b((?:READ|STORE|SAVE|COMPAT)-\d{2})\b'){$code=$matches[1]}
    try{Send-DesktopMessage ([ordered]@{type='error';code=$code;message=$message})}catch{try{[Console]::Error.WriteLine('The desktop collector could not return its error response.')}catch{}}
    exit 1
}
