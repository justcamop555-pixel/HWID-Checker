$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\hwid.bat'
$resultPath = Join-Path $PSScriptRoot 'display-test-result.json'
$sourceLiteral = $source.Replace("'", "''")
$outputLiteral = $resultPath.Replace("'", "''")
$diagnostic = @'
$ErrorActionPreference = 'Stop'
try {
    $raw=[IO.File]::ReadAllText('__SOURCE__')
    $code=($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]
    $tokens=$null; $parseErrors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$parseErrors)
    foreach ($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $result=Initialize-ReadableConsole $true $false
    if(-not $result.ContextMenuDisabled -or [HwidConsoleDisplay]::ReadEditPopupItems() -ne 0 -or -not [HwidConsoleDisplay]::HasWindowCloseCommand()){throw 'Edit popup was not emptied or window Close was removed.'}
    foreach ($mode in @(0,64,128,192,511,1023)) {
        $newMode=[HwidConsoleDisplay]::WithoutQuickEdit([uint32]$mode)
        if (($newMode -band 64) -ne 0 -or ($newMode -band 128) -eq 0 -or ($mode -band 0xFFFFFF3F) -ne ($newMode -band 0xFFFFFF3F)) { throw 'Quick Edit mask changed unrelated input flags.' }
    }
    $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $result | Add-Member NoteProperty Administrator $admin
    $ownedConsole=$true; $redirected=$false
    Start-UiReport
    for($line=0;$line -lt 150;$line++){[Console]::WriteLine('Scrolling test row '+$line)}
    $lastRow=[Console]::CursorTop
    Complete-UiReport
    $history=[Console]::BufferHeight
    if($history -ne (Get-ReportHistoryRows ([Console]::WindowHeight) $lastRow)){throw 'Report history was not trimmed to content.'}
    Move-UiReportView 'Home'
    if([Console]::WindowTop -ne 0){throw 'Home scrolling failed.'}
    Move-UiReportView 'PageDown'
    if([Console]::WindowTop -ne 33){throw 'PageDown scrolling failed.'}
    Move-UiReportView 'End'
    if([Console]::WindowTop -ne $history-[Console]::WindowHeight){throw 'End scrolling failed.'}
    Move-UiReportView 'UpArrow'
    if([Console]::WindowTop -ne $history-[Console]::WindowHeight-1){throw 'Up scrolling failed.'}
    Move-UiReportView 'Home'
    Reset-UiPage
    if([Console]::BufferHeight -ne [Console]::WindowHeight){throw 'Dashboard kept report history.'}
    $palette=@{Heading='Cyan';Muted='Gray'}
    # A wrapped footer must be written before calculating the final history size.
    [Console]::SetWindowSize(20,34)
    [Console]::SetBufferSize(20,34)
    Start-UiReport
    for($line=0;$line -lt 80;$line++){[Console]::WriteLine('Narrow test '+$line)}
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))){throw 'Wrapped footer was not included in report history.'}
    $result | Add-Member NoteProperty NarrowFooterHistoryRows ([Console]::BufferHeight)
    [Console]::SetWindowPosition(0,0)
    [Console]::SetBufferSize(100,[Console]::BufferHeight)
    [Console]::SetWindowSize(100,34)
    Reset-UiPage

    $palette.Error='Red'; $palette.Text='White'; $palette.Border='DarkGray'; $palette.Good='Green'; $palette.Warn='Yellow'
    Start-UiReport
    [Console]::SetCursorPosition(0,4090)
    Write-PnpValue 'Long report guard' 'Last lines retained' $palette.Text
    if([Console]::BufferHeight -le 4096){throw 'Long deep report did not grow its history buffer.'}
    $grown=[Console]::BufferHeight
    Start-UiReport
    if([Console]::BufferHeight -ne $grown){throw 'Repeated report setup shrank extended history.'}
    $result | Add-Member NoteProperty ExtendedDeepHistoryRows $grown
    Reset-UiPage
    [Console]::SetWindowSize(20,34)
    [Console]::SetBufferSize(20,34)
    Start-UiReport
    $testDevice=[pscustomobject]@{Name='Narrow USB device';PNPClass='HIDClass';DeviceInstanceId='USB\TEST\INSTANCE';HardwareID=@(('USB\'+('A'*160)),'USB\SECOND');CompatibleID=@('USB\CLASS');ConfigManagerErrorCode=22}
    Show-PnpRecords @($testDevice) -Full
    Complete-UiReport
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))){throw 'Deep view did not retain narrow wrapped content.'}
    $result | Add-Member NoteProperty NarrowDeepViewRows ([Console]::BufferHeight)
    [Console]::SetWindowPosition(0,0)
    [Console]::SetBufferSize(100,[Console]::BufferHeight)
    [Console]::SetWindowSize(100,34)
    Reset-UiPage
    $report=[ordered]@{'Report info'=@{Computer='TEST';Generated='test'}}
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    $identifiers=@();$admin=$false
    [Console]::SetWindowSize(40,20)
    [Console]::SetBufferSize(40,20)
    Show-ControlDeck
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -gt 17){throw 'Compact dashboard overflowed a 40x20 viewport.'}
    $result | Add-Member NoteProperty CompactDashboardCursorRow ([Console]::CursorTop)
    $categoryKeys=New-Object 'System.Collections.Generic.Queue[System.ConsoleKeyInfo]'
    foreach($text in (@(1..100 | ForEach-Object {'bad'})+@('6'))) {
        foreach($character in $text.ToCharArray()){$categoryKeys.Enqueue((New-Object ConsoleKeyInfo($character,[ConsoleKey]::A,$false,$false,$false)))}
        $categoryKeys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
    }
    $picked=Read-MenuChoice -Maximum 6 -Reader {
        param($area)
        Read-MenuKeyboard -Area $area -Maximum 6 -KeyReader {$categoryKeys.Dequeue()}
    }
    if($picked -ne '6' -or [Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 20){throw 'Repeated category errors scrolled or broke the fixed picker.'}
    $result | Add-Member NoteProperty CategoryErrorCursorRow ([Console]::CursorTop)

    [Console]::SetBufferSize(100,34)
    [Console]::SetWindowSize(100,34)
    Reset-UiPage
    $sectionGroups=[ordered]@{'SYSTEM & FIRMWARE'=@('System identity');'CPU & MEMORY'=@('CPU');'STORAGE'=@('Physical disks');'GRAPHICS & NETWORK'=@('Graphics adapters');'WINDOWS'=@('Windows')}
    $quickPreviousReport=$report
    $report=[ordered]@{
        'Report info'=@{Computer='TEST';Generated='2026-10-27T12:00:00Z';ScanNumber=1}
        'Chassis'=@([pscustomobject]@{SerialNumber='CHASSIS0001'})
        'CPU'=@([pscustomobject]@{ProcessorId='CPU0001'})
        'Memory modules'=@([pscustomobject]@{DeviceLocator='A1';SerialNumber='0000123'})
        'Physical disks'=@([pscustomobject]@{Index=0;SerialNumber='DISK0001'})
        'Monitors'=@(foreach($i in 1..25){[pscustomobject]@{SerialNumber=('MONITOR'+$i)}})
        'Network adapters'=@([pscustomobject]@{Name='Ethernet';MacAddress='001122334455';PermanentAddress='001122334466';HardwareInterface=$true})
        'Windows Machine GUID'=@([pscustomobject]@{MachineGuid='12345678-1234-1234-1234-123456789012'})
    }
    Show-QuickIds
    $script:quickNavigationStep=0
    Wait-UiPage -KeyReader {
        $script:quickNavigationStep++
        if($script:quickNavigationStep -eq 1){
            if([Console]::WindowTop -ne 0 -or $script:reportBookmarks.Count -ne 5){throw 'Quick ID view did not start at its header with five section shortcuts.'}
            return (New-Object ConsoleKeyInfo([char]'3',[ConsoleKey]::D3,$false,$false,$false))
        }
        $target=if($script:quickNavigationStep -eq 2){'3'}else{'5'}
        $expected=[math]::Min($script:reportBookmarks[$target],[Console]::BufferHeight-[Console]::WindowHeight)
        if([Console]::WindowTop -ne $expected){throw 'Quick ID shortcut missed its group.'}
        if($script:quickNavigationStep -eq 2){return (New-Object ConsoleKeyInfo([char]'5',[ConsoleKey]::D5,$false,$false,$false))}
        New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
    }
    $result | Add-Member NoteProperty QuickIdGroupNavigation $true
    [Console]::SetWindowPosition(0,0);[Console]::SetWindowSize(40,34);[Console]::SetBufferSize(40,[Console]::BufferHeight)
    Show-QuickIds
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))){throw 'Narrow ID view history did not include its stacked fields.'}
    $result | Add-Member NoteProperty NarrowQuickIdView $true
    [Console]::SetWindowPosition(0,0);[Console]::SetBufferSize(100,[Console]::BufferHeight);[Console]::SetWindowSize(100,34)
    $report=$quickPreviousReport
    $report['Report info'].Generated='2026-10-25T10:38:04.4334337-04:00'
    $report['Report info'].ScanSeconds=25.39;$scanTotal=17
    $report['Scan timing']=@([pscustomobject]@{Section='Storage identifiers';Seconds=11.6;Status='READ';Results=2;Summary='IDs: 6 found'})
    foreach($sectionName in @($sectionGroups.Values | ForEach-Object {$_})) {$report[$sectionName]=@([pscustomobject]@{Name='Fixture'})}
    $report['PnP hardware IDs']=@([pscustomobject]@{Name='Device';PNPClass='System';HardwareID=@('MODEL');DeviceInstanceId='TEST\NODE';ConfigManagerErrorCode=0})
    Start-UiReport
    Show-Overview
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 34 -or [Console]::BufferHeight -ne 34){throw 'Overview did not fit one standard console viewport.'}
    $result | Add-Member NoteProperty OverviewCursorRow ([Console]::CursorTop)
    $report['Extended scan info']=[ordered]@{Captured='2026-10-25T11:00:04.4334337-04:00'}
    $report['Extended device inventory']=@([pscustomobject]@{Present=$false;HiddenByNodeFlag=$true;HiddenByClass=$null})
    Show-Overview
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 34 -or [Console]::BufferHeight -ne 34){throw 'Populated extended overview did not fit the standard viewport.'}
    $result | Add-Member NoteProperty ExtendedOverviewCursorRow ([Console]::CursorTop)
    $report['Extended scan info']['Error']='Provider unavailable'
    Show-Overview
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 34 -or [Console]::BufferHeight -ne 34){throw 'Failed extended overview did not fit the standard viewport.'}
    $result | Add-Member NoteProperty FailedOverviewCursorRow ([Console]::CursorTop)
    $report['Extended scan info'].Remove('Error')
    $report['Report info']['ExtendedStatus']='Unavailable'
    $savedOverviewIds=$identifiers
    $identifiers=@([pscustomobject]@{Quality='Missing'},[pscustomobject]@{Quality='Placeholder'})
    $overviewWarningIndex=$warnings.Count;$warnings.Add('Extended device inventory: Synthetic timeout')
    Show-Overview
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 34 -or [Console]::BufferHeight -ne 34){throw 'Stale catalog overview did not fit the standard viewport.'}
    $result | Add-Member NoteProperty StaleOverviewCursorRow ([Console]::CursorTop)
    $savedOverviewInfo=$report['Extended scan info'];$savedOverviewDevices=$report['Extended device inventory']
    $report.Remove('Extended scan info');$report.Remove('Extended device inventory')
    $report['Report info']['ExtendedAttempted']='2026-10-25T11:02:04-04:00'
    Show-Overview
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)}
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ge 34 -or [Console]::BufferHeight -ne 34){throw 'First failed extended attempt overview did not fit the standard viewport.'}
    $result | Add-Member NoteProperty FirstExtendedFailureCursorRow ([Console]::CursorTop)
    $report['Extended scan info']=$savedOverviewInfo;$report['Extended device inventory']=$savedOverviewDevices
    $report['Report info'].Remove('ExtendedStatus');$report['Report info'].Remove('ExtendedAttempted')
    $warnings.RemoveAt($overviewWarningIndex);$identifiers=$savedOverviewIds
    [Console]::SetWindowSize(50,20)
    Show-Overview
    $overviewKeys=New-Object 'System.Collections.Generic.Queue[ConsoleKeyInfo]'
    $overviewKeys.Enqueue((New-Object ConsoleKeyInfo([char]0,[ConsoleKey]::End,$false,$false,$false)))
    $overviewKeys.Enqueue((New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)))
    Wait-UiPage -KeyReader {
        if($overviewKeys.Count -eq 2 -and [Console]::WindowTop -ne 0){throw 'Narrow overview did not open at its summary.'}
        if($overviewKeys.Count -eq 1 -and [Console]::WindowTop -le 0){throw 'Narrow overview did not scroll to its footer.'}
        $overviewKeys.Dequeue()
    }
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows 20 ([Console]::CursorTop))){throw 'Narrow overview retained excessive blank history.'}
    $result | Add-Member NoteProperty NarrowOverviewScrolls $true
    Reset-UiPage
    [Console]::SetBufferSize(100,34)
    [Console]::SetWindowSize(100,34)
    $report.Remove('Extended scan info');$report.Remove('Extended device inventory')
    $reviewPreviousReport=$report;$reviewPreviousWarnings=$warnings;$reviewPreviousIds=$identifiers
    $report=[ordered]@{'PnP hardware IDs'=@([pscustomobject]@{Name='Unknown status fixture';DeviceInstanceId='TEST\NODE';ConfigManagerErrorCode=$null})}
    $report['Physical disks']=@([pscustomobject]@{Index=0;SerialNumber='A'},[pscustomobject]@{Index=0;SerialNumber='B'})
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    foreach($n in 1..15){$warnings.Add(('Unread fixture '+$n+': Invalid namespace'))}
    $identifiers=@([pscustomobject]@{Section='CPU';Device='CPU0';Field='ProcessorId';Quality='Missing'})
    Show-Attention
    $script:reviewKeyStep=0
    Wait-UiPage -KeyReader {
        $script:reviewKeyStep++
        if($script:reviewKeyStep -eq 1){
            if([Console]::WindowTop -ne 0){throw 'Review page did not open at its counts and controls.'}
            return (New-Object ConsoleKeyInfo([char]'5',[ConsoleKey]::D5,$false,$false,$false))
        }
        if($script:reviewKeyStep -eq 2){
            $expected=[math]::Min($script:reportBookmarks['5'],[Console]::BufferHeight-[Console]::WindowHeight)
            if([Console]::WindowTop -ne $expected){throw 'Conflict shortcut missed its section.'}
            return (New-Object ConsoleKeyInfo([char]'3',[ConsoleKey]::D3,$false,$false,$false))
        }
        if($script:reviewKeyStep -eq 3){
            $expected=[math]::Min($script:reportBookmarks['3'],[Console]::BufferHeight-[Console]::WindowHeight)
            if([Console]::WindowTop -ne $expected){throw 'Unread-section shortcut missed its section.'}
            return (New-Object ConsoleKeyInfo([char]'4',[ConsoleKey]::D4,$false,$false,$false))
        }
        $expected=[math]::Min($script:reportBookmarks['4'],[Console]::BufferHeight-[Console]::WindowHeight)
        if([Console]::WindowTop -ne $expected){throw 'Missing-ID shortcut missed its section.'}
        New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
    }
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows 34 ([Console]::CursorTop))){throw 'Review page retained oversized blank history.'}
    $result | Add-Member NoteProperty UnreadReviewNavigation $true
    $result | Add-Member NoteProperty ConflictReviewNavigation $true
    $report=$reviewPreviousReport;$warnings=$reviewPreviousWarnings;$identifiers=$reviewPreviousIds
    $report['Report info'].Version='3.23'
    $report['CPU']=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='AFTER'})
    $previous=[pscustomobject]@{'Report info'=[pscustomobject]@{Version='3.23';Computer='TEST';Generated='2026-01-01T00:00:00Z'};CPU=@([pscustomobject]@{DeviceID='CPU0';ProcessorId='BEFORE'})}
    Show-ComparisonResult $previous $report -SourcePath 'C:\Reports\baseline.json'
    $script:comparisonStep=0
    Wait-UiPage -KeyReader {
        $script:comparisonStep++
        if($script:comparisonStep -eq 1){
            if([Console]::WindowTop -ne 0 -or $script:reportBookmarks.Count -ne 3){throw 'Comparison did not open at its summary with section shortcuts.'}
            return (New-Object ConsoleKeyInfo([char]'2',[ConsoleKey]::D2,$false,$false,$false))
        }
        $targetKey=if($script:comparisonStep -eq 2){'2'}else{'3'}
        $expected=[math]::Min($script:reportBookmarks[$targetKey],[Console]::BufferHeight-[Console]::WindowHeight)
        if([Console]::WindowTop -ne $expected){throw 'Comparison shortcut did not reach its section.'}
        if($script:comparisonStep -eq 2){return (New-Object ConsoleKeyInfo([char]'3',[ConsoleKey]::D3,$false,$false,$false))}
        New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
    }
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))){throw 'Comparison history did not match its rendered content.'}
    $result | Add-Member NoteProperty ComparisonSectionNavigation $true
    $result | Add-Member NoteProperty ComparisonHistoryRows ([Console]::BufferHeight)
    $catalogFunction=(Get-Item Function:Get-SavedSnapshotCatalog).ScriptBlock
    $locationsFunction=(Get-Item Function:Get-ReportLocations).ScriptBlock
    $lineFunction=(Get-Item Function:Read-CheckerLine).ScriptBlock
    try {
        function Get-ReportLocations {[pscustomobject]@{Search=@('C:\Reports')}}
        function Get-SavedSnapshotCatalog {
            [pscustomobject]@{Entries=@(foreach($i in 1..6){[pscustomobject]@{FullName=('C:\Reports\older-'+$i+'.json');Name=('older-'+$i+'.json');Relation='OLDER';Computer='TEST';Generated='2026-01-01T00:00:00Z'}});Skipped=@()}
        }
        $script:pickerReads=0
        function Read-CheckerLine {
            param($Prompt)
            $script:pickerReads++
            if([Console]::CursorTop -ge 32 -or [Console]::WindowTop -ne 0){throw 'Snapshot picker does not fit the standard console.'}
            if($script:pickerReads -eq 1){return '6'}
            return '1'
        }
        if((Read-CompareReportPath) -ne 'C:\Reports\older-6.json' -or $script:pickerReads -ne 2){throw 'Native snapshot picker lost its page selection.'}
        $result | Add-Member NoteProperty SnapshotPickerPagination $true
    }finally{Set-Item Function:Get-SavedSnapshotCatalog -Value $catalogFunction;Set-Item Function:Get-ReportLocations -Value $locationsFunction;Set-Item Function:Read-CheckerLine -Value $lineFunction}

    Reset-UiPage
    Start-UiReport
    Show-FullReport
    $script:reportNavigationStep=0
    Wait-UiPage -KeyReader {
        $script:reportNavigationStep++
        switch($script:reportNavigationStep) {
            1 {
                if([Console]::WindowTop -ne 0){throw 'Full report opened at the bottom instead of its contents.'}
                New-Object ConsoleKeyInfo([char]'4',[ConsoleKey]::D4,$false,$false,$false)
            }
            2 {
                if([Console]::WindowTop -ne $script:reportBookmarks['4']){throw 'Storage section jump missed its heading.'}
                New-Object ConsoleKeyInfo([char]'8',[ConsoleKey]::D8,$false,$false,$false)
            }
            3 {
                $expected=[math]::Min($script:reportBookmarks['8'],[Console]::BufferHeight-[Console]::WindowHeight)
                if([Console]::WindowTop -ne $expected){throw 'Review section jump missed its heading.'}
                New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
            }
            default {throw 'Full report did not return on 0.'}
        }
    }
    if($script:reportBookmarks.Count -ne 8){throw 'Full report is missing section bookmarks.'}
    if([Console]::BufferHeight -ne (Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop))){throw 'Full inventory history does not match rendered content.'}
    $result | Add-Member NoteProperty FullReportHistoryRows ([Console]::BufferHeight)
    $result | Add-Member NoteProperty FullReportSectionJumps 2
    Reset-UiPage
    if($script:reportBookmarks.Count){throw 'Full report navigation leaked into the next page.'}
    Start-UiReport
    for($line=0;$line -lt 80;$line++){[Console]::WriteLine('Report row '+$line)}
    Complete-UiReport
    Move-UiReportView 'Home'
    $oldCursor=[Console]::CursorTop
    Show-UiTransition 'Back'
    if([Console]::WindowTop -ne 0 -or [Console]::CursorTop -ne $oldCursor){throw 'Animation changed the scrolled report viewport or cursor.'}
    Reset-UiPage
    $oldMotion=$env:HWID_NO_ANIMATION
    try {
        $env:HWID_NO_ANIMATION='1'
        $noMotionTimer=[Diagnostics.Stopwatch]::StartNew()
        Show-UiTransition 'Next'
        $noMotionTimer.Stop()
        if($noMotionTimer.ElapsedMilliseconds -gt 100){throw 'Disabled animation still delayed navigation.'}
    } finally {$env:HWID_NO_ANIMATION=$oldMotion}
    $script:scanStep=0;$scanTotal=17
    $script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    $probeRow=[Console]::CursorTop
    Section 'Scan display probe' {[pscustomobject]@{SerialNumber='TEST'}}
    if([Console]::CursorTop -ne $probeRow+1 -or $script:scanTimings.Count -ne 1){throw 'Active scan status appended extra rows instead of replacing Reading text.'}
    $result | Add-Member NoteProperty ScanStatusRows ([Console]::CursorTop-$probeRow)
    Reset-UiPage
    $identifierPattern='^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
    $display=$result
    function Get-CimInstance {
        param($ClassName,$Filter,$OperationTimeoutSec,$Property,$Namespace)
        if([Console]::CursorVisible){throw 'Typing cursor was visible while a scan query was running.'}
        if($ClassName -eq 'MSFT_Disk'){return [pscustomobject]@{Number=0;SerialNumber='DISK1';PartitionStyle=2;Guid='DISK1';Size=1GB}}
        if($ClassName -eq 'MSFT_Partition'){return [pscustomobject]@{DiskNumber=0;PartitionNumber=1;Guid='PART1';DriveLetter='C';AccessPaths=@('PATH');Size=1GB}}
        [pscustomobject]@{Name='Fixture';DeviceID='CPU0';SerialNumber='SERIAL1';UUID='SYSTEM1';ProcessorId='CPU1';TotalPhysicalMemory=8GB}
    }
    function Get-NetAdapter {param([switch]$IncludeHidden) [pscustomobject]@{Name='NIC';InterfaceGuid='NIC1';MacAddress='001122334455';HardwareInterface=$false}}
    function Get-ItemProperty {param($LiteralPath,$Name) [pscustomobject]@{MachineGuid='WINDOWS1'}}
    function Get-DriverHardwareIds {[pscustomobject]@{Name='USB';DeviceInstanceId='USB\NODE';HardwareID=@('USB\MODEL');PNPClass='USB';ConfigManagerErrorCode=0}}
    for($scan=1;$scan -le 3;$scan++) {
        [Console]::CursorVisible=($scan -ne 2)
        $beforeScanVisible=[Console]::CursorVisible
        $snapshot=Invoke-HardwareScan $scan
        if([Console]::CursorVisible -ne $beforeScanVisible){throw 'Scanning did not restore the previous cursor visibility.'}
        if($snapshot.Warnings.Count){throw 'Native scan had unavailable sections or exposed the typing cursor during collection.'}
        if($snapshot.Inventory['Report info'].QueryMode -ne 'Live progress'){throw 'The native checker fell back instead of using its live scan worker.'}
        if($snapshot.Inventory['Scan timing'].Count -ne 17 -or $scanStep -ne 17){throw 'Repeated native scans accumulated timing or counters.'}
        if([Console]::CursorTop -ge 34 -or [Console]::WindowTop -ne 0){throw 'The standard scan dashboard overflowed one screen.'}
        $result | Add-Member NoteProperty ('Scan'+$scan+'CursorRow') ([Console]::CursorTop)
        Complete-UiReport
        if([Console]::BufferHeight -ne 34){throw 'Scanning left excess history.'}
    }
    $result | Add-Member NoteProperty RepeatedNativeScans 3
    $result | Add-Member NoteProperty ScanCursorHiddenDuringQueries $true
    $result | Add-Member NoteProperty ScanCursorVisibilityRestored $true
    $script:scanContinueStep=0
    $scanBottom=[Console]::CursorTop
    Wait-ScanContinue 'main menu' -KeyReader {
        $script:scanContinueStep++
        if($script:scanContinueStep -eq 1) {
            if([Console]::CursorTop -le $scanBottom){throw 'Continue prompt was not written after the finished scan.'}
            $scanCells=[HwidConsoleDisplay]::CaptureRegion(0,0,99,([Console]::CursorTop))
            $scanText=-join @($scanCells.Cells | ForEach-Object {[char]$_.Character})
            if($scanText -notmatch 'SCANNING 17 SECTIONS' -or $scanText -notmatch 'Finished:' -or $scanText -notmatch 'Press Enter for main menu'){throw 'Finished scan was cleared before the user could continue.'}
            return (New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false))
        }
        if($script:scanContinueStep -eq 2){return (New-Object ConsoleKeyInfo([char]0,[ConsoleKey]::Home,$false,$false,$false))}
        New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)
    }
    if($script:scanContinueStep -ne 3){throw 'Scan continuation accepted an unrelated key.'}
    $result | Add-Member NoteProperty ScanContinuesAfterEnter $true
    $originalHeading=(Get-Item Function:Write-Heading).ScriptBlock
    try {
        function Write-Heading {param($Title) throw 'Simulated early scan render failure'}
        [Console]::CursorVisible=$true
        $earlyFailureCaught=$false
        try {Invoke-HardwareScan 4 | Out-Null}catch{$earlyFailureCaught=$true}
        if(-not $earlyFailureCaught -or -not [Console]::CursorVisible){throw 'Early scan failure left the typing cursor hidden.'}
    }finally{Set-Item Function:Write-Heading -Value $originalHeading}
    $result | Add-Member NoteProperty ScanCursorRestoredAfterFailure $true
    Reset-UiPage;Start-UiReport
    $script:scanProgressClock=[Diagnostics.Stopwatch]::StartNew()
    $script:scanProgressState=[pscustomobject]@{Top=[Console]::CursorTop;Width=[Console]::WindowWidth}
    Write-Host 'Initial progress'
    $script:scanStep=1
    $activeLine=Start-ScanLine '  [01/17] Slow query probe '
    $script:nativePulses=0
    $script:scanQueryWorker=New-ScanQueryWorker
    try {
        $probe=@(Invoke-ScanQuery {Start-Sleep -Milliseconds 450;[pscustomobject]@{SerialNumber='TEST'}} {
            $script:nativePulses++
            Update-ScanProgress 0
            Update-ScanWaiting $activeLine 6
        })
        if($script:nativePulses -lt 1 -or $activeLine.LastLength -le 12 -or [Console]::CursorTop -ne 1){throw 'Live scan feedback failed to update in place during a slow provider read.'}
        Complete-ScanLine $activeLine 'Probe' '[READ] Complete' $palette.Good
        if([Console]::CursorTop -ne 2 -or [Console]::WindowTop -ne 0){throw 'Completing a waiting status added extra rows or scrolled.'}
        $result | Add-Member NoteProperty LiveTimerPulseCount $script:nativePulses
        $result | Add-Member NoteProperty WaitingStatusCompletedInPlace $true
    }finally{
        $script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null
        $script:scanProgressClock.Stop();$script:scanProgressClock=$null;$script:scanProgressState=$null
    }
    Show-RescanResult $snapshot.Inventory $snapshot.Inventory
    Wait-UiPage -KeyReader {
        if([Console]::WindowTop -ne 0 -or $script:reportBookmarks.Count -ne 3){throw 'Rescan results did not open at the summary with section shortcuts.'}
        New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
    }
    $result | Add-Member NoteProperty RescanSummaryStartsAtTop $true
    function Get-PnpDevice {
        param($ErrorAction)
        if([Console]::CursorVisible){throw 'Typing cursor was visible during extended enumeration.'}
        [pscustomobject]@{Name='Hidden fixture';Present=$true;PNPDeviceID='USB\HIDDEN';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@('MODEL1','MODEL2');ConfigManagerErrorCode=0}
        [pscustomobject]@{Name='Remembered fixture';Present=$false;PNPDeviceID='USB\OLD';ClassGuid='NORMAL';PNPClass='USB';HardwareID=@('OLDMODEL');ConfigManagerErrorCode=45}
        [pscustomobject]@{Name='Unknown fixture';Present=$null;PNPDeviceID='USB\UNKNOWN';ClassGuid='NORMAL';PNPClass='USB'}
    }
    function Get-PnpDeviceProperty {
        param($InstanceId,$KeyName,$ErrorAction,$ErrorVariable)
        foreach($id in $InstanceId){[pscustomobject]@{InstanceId=$id;KeyName='DEVPKEY_Device_DevNodeStatus';Data=$(if($id -eq 'USB\HIDDEN'){[uint32]0x40000008}else{[uint32]8})}}
    }
    function Get-ClassHiddenState {param($ClassGuid) return $false}
    [Console]::CursorVisible=$true
    $normalCpu=$report['CPU'][0].ProcessorId
    Start-ExtendedDeviceScan
    if($report['Extended device inventory'].Count -ne 3 -or $report['CPU'][0].ProcessorId -ne $normalCpu){throw 'Extended worker scan failed or replaced normal inventory data.'}
    if(-not [Console]::CursorVisible -or $null -ne $script:scanQueryWorker){throw 'Extended scanning did not restore the cursor and release its worker.'}
    $script:extendedNavigationStep=0
    Wait-UiPage -KeyReader {
        $script:extendedNavigationStep++
        if($script:extendedNavigationStep -eq 1) {
            if([Console]::WindowTop -ne 0 -or $script:reportBookmarks.Count -ne 7){throw 'Extended catalog did not start at its summary with group shortcuts.'}
            return (New-Object ConsoleKeyInfo([char]'7',[ConsoleKey]::D7,$false,$false,$false))
        }
        if($script:extendedNavigationStep -eq 2) {
            $reviewTop=[math]::Min($script:reportBookmarks['7'],[Console]::BufferHeight-[Console]::WindowHeight)
            if([Console]::WindowTop -ne $reviewTop){throw 'Unknown/review shortcut missed its heading.'}
            return (New-Object ConsoleKeyInfo([char]'3',[ConsoleKey]::D3,$false,$false,$false))
        }
        $expected=[math]::Min($script:reportBookmarks['3'],[Console]::BufferHeight-[Console]::WindowHeight)
        if([Console]::WindowTop -ne $expected){throw 'Extended catalog hidden-device shortcut missed its heading.'}
        New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)
    }
    $result | Add-Member NoteProperty ExtendedCatalogRecords $report['Extended device inventory'].Count
    $result | Add-Member NoteProperty ExtendedCatalogNavigation $true
    $result | Add-Member NoteProperty UnknownReviewNavigation $true
    $result | Add-Member NoteProperty ExtendedCursorRestored $true
    $script:rescanContinueReads=0
    $script:expectedRescanNumber=1+[int]$report['Report info'].ScanNumber
    Start-HardwareRescan -ContinueReader {
        $script:rescanContinueReads++
        if($report['Report info'].ScanNumber -ne $script:expectedRescanNumber){throw 'Rescan was not published before the continue prompt.'}
        New-Object ConsoleKeyInfo([char]13,[ConsoleKey]::Enter,$false,$false,$false)
    }
    if($script:rescanContinueReads -ne 1){throw 'Rescan skipped its continue prompt before displaying changes.'}
    if($report['Report info'].ExtendedStatus -ne 'Refreshed' -or $report['Extended device inventory'].Count -ne 3){throw 'Full rescan dropped the previously scanned extended catalog.'}
    if(-not [Console]::CursorVisible -or $null -ne $script:scanQueryWorker){throw 'Rescan with an extended refresh did not restore its cursor and worker state.'}
    Wait-UiPage -KeyReader {New-Object ConsoleKeyInfo([char]'0',[ConsoleKey]::D0,$false,$false,$false)}
    if([Console]::WindowTop -ne 0){throw 'Rescan with an extended refresh did not open at its summary.'}
    $result | Add-Member NoteProperty RescanRefreshedExtendedCatalog $true
    Reset-UiPage
    $animationLeft=[Console]::CursorLeft; $animationTop=[Console]::CursorTop
    $animationVisible=[Console]::CursorVisible
    $animationForeground=[Console]::ForegroundColor;$animationBackground=[Console]::BackgroundColor
    $animationInputMode=[HwidConsoleDisplay]::ReadInputMode()
    $fixture=[HwidConsoleDisplay]::CaptureRegion(0,([Console]::WindowHeight-4),([Console]::WindowWidth-1),3)
    if($null -eq $fixture){throw 'Could not capture the animation test region.'}
    if(-not [HwidConsoleDisplay]::PaintRegion($fixture,[string[]]@('KEEP / cyan footer','KEEP / white report record','KEEP / amber status'),[uint16[]]@(11,15,14))){throw 'Could not paint the animation restoration fixture.'}
    $expectedCells=[HwidConsoleDisplay]::CaptureRegion($fixture.Left,$fixture.Top,$fixture.Width,$fixture.Height)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    foreach($direction in @('Next','Back','Exit')){
        Show-UiTransition $direction 'Scan summary'
        $actualCells=[HwidConsoleDisplay]::CaptureRegion($fixture.Left,$fixture.Top,$fixture.Width,$fixture.Height)
        for($cell=0;$cell -lt $expectedCells.Cells.Length;$cell++){
            if($expectedCells.Cells[$cell].Character -ne $actualCells.Cells[$cell].Character -or $expectedCells.Cells[$cell].Attributes -ne $actualCells.Cells[$cell].Attributes){throw 'Animation did not restore the original text and per-cell colors.'}
        }
    }
    $timer.Stop()
    if([Console]::CursorLeft -ne $animationLeft -or [Console]::CursorTop -ne $animationTop -or [Console]::CursorVisible -ne $animationVisible){throw 'Animation did not restore cursor state.'}
    if([Console]::BufferHeight -ne [Console]::WindowHeight -or [Console]::WindowTop -ne 0){throw 'Animation added scrollbar history.'}
    if($timer.ElapsedMilliseconds -gt 1800){throw 'Transitions took too long.'}
    if([Console]::ForegroundColor -ne $animationForeground -or [Console]::BackgroundColor -ne $animationBackground -or [HwidConsoleDisplay]::ReadInputMode() -ne $animationInputMode){throw 'Animation changed console colors or input modes.'}
    [Console]::CursorVisible=$false
    Show-UiTransition 'Back'
    if([Console]::CursorVisible){throw 'Animation exposed a previously hidden cursor.'}
    [Console]::CursorVisible=$animationVisible
    [void][HwidConsoleDisplay]::RestoreRegion($fixture)
    $result | Add-Member NoteProperty AnimationTextAndColorsRestored $true
    $result | Add-Member NoteProperty AnimationInputModesPreserved $true
    $result | Add-Member NoteProperty ThreeTransitionsMs $timer.ElapsedMilliseconds
    $result | Add-Member NoteProperty ReportHistoryRows $history
    $result | Add-Member NoteProperty RestoredBufferRows ([Console]::BufferHeight)
    $result | ConvertTo-Json | Set-Content -LiteralPath '__OUTPUT__' -Encoding UTF8
    Write-Host 'HWID CHECKER - STANDARD DISPLAY TEST' -ForegroundColor Cyan
    Write-Host ('Font: ' + $result.FontName + ' / ' + $result.FontHeight + ' pixels')
    Write-Host ('Window: ' + $result.Columns + ' columns x ' + $result.Rows + ' rows')
    Write-Host 'Regular text, consistent spacing, no administrator request.'
    Start-Sleep -Seconds 2
} catch {
    @{Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath '__OUTPUT__' -Encoding UTF8
    exit 1
}
'@
$diagnostic = $diagnostic.Replace('__SOURCE__',$sourceLiteral).Replace('__OUTPUT__',$outputLiteral)
$diagnosticPath=Join-Path $PSScriptRoot ('display-diagnostic-'+[guid]::NewGuid().ToString('N')+'.ps1')
[IO.File]::WriteAllText($diagnosticPath,$diagnostic,(New-Object Text.UTF8Encoding($true)))
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-ForceNoHandoff -- "' + $powerShellPath + '" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $diagnosticPath + '"'
$process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arguments -PassThru
if (-not $process.WaitForExit(20000)) { throw 'Display test did not complete in 20 seconds.' }
$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($result.Error) { throw $result.Error }
if (-not $result.ThemeApplied -or $result.BackgroundRGB -ne 2101772) { throw 'The navy console background was not applied.' }
if (-not $result.QuickEditDisabled -or ($result.InputModeAfter -band 64) -ne 0 -or ($result.InputModeAfter -band 128) -eq 0) { throw 'Quick Edit is still enabled.' }
if (-not $result.MouseInputDisabled -or ($result.InputModeAfter -band 16) -ne 0) { throw 'Mouse input is still captured instead of left to host scrolling.' }
if (($result.InputModeBefore -band 0xFFFFFF2F) -ne ($result.InputModeAfter -band 0xFFFFFF2F)) { throw 'Unrelated keyboard input flags changed.' }
if ($result.BufferRows -ne $result.Rows) { throw 'Dashboard inherited an oversized history buffer.' }
if (-not $result.FontApplied -or $result.FontName -ne 'Consolas' -or $result.FontHeight -ne 16 -or $result.FontWeight -ne 400) { throw 'The readable regular font was not applied.' }
if ($result.Columns -le 0 -or $result.Columns -gt 100 -or $result.Rows -le 0 -or $result.Rows -gt 34) { throw 'Window dimensions are invalid.' }
$parentAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($result.Administrator -ne $parentAdmin) { throw 'Privilege level changed.' }
$result | ConvertTo-Json
'PASS: Mouse capture off; real report scrolling, content-sized history, clean dashboard buffer, font, and privilege level verified.'
