@echo off
setlocal DisableDelayedExpansion
title Detailed HWID Checker
set "HWID_SCRIPT=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw = [IO.File]::ReadAllText($env:HWID_SCRIPT); & ([scriptblock]::Create(($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]))"
set "HWID_EXIT=%errorlevel%"
echo.
if not "%HWID_EXIT%"=="0" echo The checker encountered an error. See the message above.
pause
exit /b %HWID_EXIT%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
$report = [ordered]@{}
$warnings = New-Object 'System.Collections.Generic.List[string]'
$palette = @{ Heading='Cyan'; Text='White'; Muted='Gray'; Good='Green'; Warn='Yellow'; Error='Red'; Added='Cyan' }
try {
    if ([Console]::BackgroundColor -in @('White','Gray','Yellow','Cyan','Green','Magenta')) {
        $palette = @{ Heading='DarkCyan'; Text='Black'; Muted='DarkGray'; Good='DarkGreen'; Warn='DarkYellow'; Error='DarkRed'; Added='DarkCyan' }
    }
} catch { }
$scanStep = 0
$sectionGroups = [ordered]@{
    'SYSTEM & FIRMWARE' = @('System identity','System hardware','Motherboard','BIOS','Chassis')
    'CPU & MEMORY' = @('CPU','Memory modules')
    'STORAGE' = @('Physical disks','Storage identifiers','Volumes')
    'GRAPHICS & NETWORK' = @('Graphics adapters','Network adapters')
    'WINDOWS' = @('Windows','Windows Machine GUID')
}
function Write-Heading($Title) {
    $width = 72
    try { if ([Console]::WindowWidth -gt 0) { $width = [math]::Min(88, [math]::Max(32, [Console]::WindowWidth - 2)) } } catch { }
    Write-Host ''
    Write-Host ('-' * $width) -ForegroundColor $palette.Muted
    Write-Host ('  ' + $Title) -ForegroundColor $palette.Heading
    Write-Host ('-' * $width) -ForegroundColor $palette.Muted
}
function Show-MenuItem($Key, $Label, $Hint) {
    Write-Host "  [$Key] " -ForegroundColor $palette.Heading -NoNewline
    Write-Host $Label -ForegroundColor $palette.Text
    if ($Hint) { Write-Host "      $Hint" -ForegroundColor $palette.Muted }
}
function Show-Overview {
    Write-Heading 'SCAN OVERVIEW'
    Write-Host "  Computer : $($report['Report info'].Computer)" -ForegroundColor $palette.Text
    Write-Host "  Captured : $($report['Report info'].Generated)" -ForegroundColor $palette.Muted
    $reported = @($identifiers | Where-Object Quality -eq 'Reported').Count
    $missing = @($identifiers | Where-Object Quality -eq 'Missing').Count
    $placeholder = @($identifiers | Where-Object Quality -eq 'Placeholder').Count
    Write-Host "  [REPORTED] $reported identifiers supplied by Windows" -ForegroundColor $palette.Good
    $attentionColor = if ($missing + $placeholder + $warnings.Count) { $palette.Warn } else { $palette.Good }
    Write-Host "  [REVIEW]   $missing missing / $placeholder placeholder / $($warnings.Count) unavailable sections" -ForegroundColor $attentionColor
    foreach ($group in $sectionGroups.Keys) {
        $available = @($sectionGroups[$group] | Where-Object { $report.Contains($_) -and -not $report[$_].Unavailable }).Count
        $total = @($sectionGroups[$group]).Count
        $color = if ($available -eq $total) { $palette.Good } else { $palette.Warn }
        Write-Host ('  {0,-24} {1}/{2} sections available' -f $group, $available, $total) -ForegroundColor $color
    }
    Write-Host '  Reported does not mean authentic or unique. Use [4] to review warnings.' -ForegroundColor $palette.Muted
}
function Show-FullReport {
    Write-Heading 'REPORT INFORMATION'
    Show-Records $report['Report info']
    foreach ($group in $sectionGroups.Keys) {
        Write-Heading $group
        foreach ($name in $sectionGroups[$group]) {
            Write-Host "`n  > $name" -ForegroundColor $palette.Heading
            Show-Records $report[$name]
        }
    }
    Show-Attention
}
function Show-Attention {
    Write-Heading 'ITEMS TO REVIEW'
    $issues = @($identifiers | Where-Object Quality -ne 'Reported')
    if (-not $issues.Count -and -not $warnings.Count) {
        Write-Host '  [OK] No missing identifiers, placeholders, or failed sections detected.' -ForegroundColor $palette.Good
    }
    foreach ($warning in $warnings) { Write-Host "  [UNAVAILABLE] $warning" -ForegroundColor $palette.Warn }
    foreach ($row in $issues) {
        $device = if ($row.Device) { " ($($row.Device))" } else { '' }
        Write-Host "  [$($row.Quality.ToUpper())] $($row.Section)${device} / $($row.Field)" -ForegroundColor $palette.Warn
    }
    if ($warnings.Count) { Write-Host '  Access denied? Try Run as administrator. Some providers may still be unavailable.' -ForegroundColor $palette.Muted }
    if ($issues.Count) { Write-Host '  Missing or placeholder values can be normal firmware limitations.' -ForegroundColor $palette.Muted }
}
function Show-Categories {
    Write-Heading 'BROWSE HARDWARE'
    $names = @($sectionGroups.Keys)
    for ($index = 0; $index -lt $names.Count; $index++) { Show-MenuItem ($index + 1) $names[$index] '' }
    Show-MenuItem '0' 'Back to main menu' ''
    $selection = ([string](Read-Host 'Category')).Trim()
    if (-not $selection -or $selection -eq '0') { return }
    if ($selection -notmatch '^[1-5]$') { Write-Host '  Choose a category from 1 to 5.' -ForegroundColor $palette.Warn; return }
    $name = $names[[int]$selection - 1]
    Write-Heading $name
    foreach ($section in $sectionGroups[$name]) {
        Write-Host "`n  > $section" -ForegroundColor $palette.Heading
        Show-Records $report[$section]
    }
}
function Show-Help {
    Write-Heading 'HELP & COLOR KEY'
    Write-Host '  [REPORTED / OK] Windows returned data, or an action succeeded.' -ForegroundColor $palette.Good
    Write-Host '  [REVIEW] Missing, placeholder, unavailable, or previous-only data.' -ForegroundColor $palette.Warn
    Write-Host '  [ERROR] A save or folder action failed.' -ForegroundColor $palette.Error
    Write-Host '  [+] Current-only comparison data; headings and menu keys.' -ForegroundColor $palette.Heading
    Write-Host '  Labels and notes use neutral text. Status words also explain every color.' -ForegroundColor $palette.Muted
    Write-Host ''
    @(
        'HWID is not one universal number. Applications choose different identifiers.',
        'MachineGuid identifies Windows; volume serials identify formatted volumes.',
        'MAC addresses can be overridden or randomized. PNPDeviceID identifies a Windows device.',
        'CPU clocks are MHz; memory speed units come from firmware. Capacity uses GiB.',
        'Compare saved JSON reports to track changes. Moving hardware can change slot labels.',
        'Save reports before closing; each launch performs a fresh scan.',
        'Reports contain device identifiers. Share them only with people you trust.'
    ) | ForEach-Object { Write-Host "  $_" -ForegroundColor $palette.Text }
}
$identifierPattern = '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
function Get-Quality($Value) {
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Missing' }
    if ($text -match '^(unknown|none|n/a|not (specified|available|applicable)|default string|to be filled.*|system serial number|0+|f+)$' -or $text -match '^[0:{} -]+$' -or $text -match '^[fF:{} -]+$') { return 'Placeholder' }
    return 'Reported'
}
function Show-Records($Records) {
    $recordIndex = 0
    foreach ($record in $Records) {
        $recordIndex++
        if (@($Records).Count -gt 1) { Write-Host "  Device $recordIndex of $(@($Records).Count)" -ForegroundColor $palette.Muted }
        $properties = if ($record -is [System.Collections.IDictionary]) {
            foreach ($key in $record.Keys) { [pscustomobject]@{Name=$key; Value=$record[$key]} }
        } elseif ($record -is [string]) {
            [pscustomobject]@{Name='Message'; Value=$record}
        } else { $record.PSObject.Properties }
        foreach ($property in $properties) {
            $value = if ($property.Value -is [array]) { $property.Value -join ', ' } else { [string]$property.Value }
            $color = $palette.Text
            $status = ''
            if ($property.Name -match $identifierPattern) {
                $quality = Get-Quality $value
                $color = if ($quality -eq 'Reported') { $palette.Good } else { $palette.Warn }
                $status = " [$quality]"
            } elseif ($property.Name -eq 'Unavailable') { $color = $palette.Warn }
            if ([string]::IsNullOrWhiteSpace($value)) { $value = '(not provided)'; $color = $palette.Warn }
            Write-Host ('  {0,-26}: ' -f $property.Name) -ForegroundColor $palette.Muted -NoNewline
            Write-Host ($value + $status) -ForegroundColor $color
        }
        Write-Host ''
    }
}
function Section($Name, [scriptblock]$Query) {
    $script:scanStep++
    Write-Host ('  [{0:00}/14] {1,-24} ' -f $script:scanStep, $Name) -ForegroundColor $palette.Muted -NoNewline
    try {
        $data = @(& $Query)
        if ($data.Count -eq 0) { throw 'No data returned by Windows.' }
        $report[$Name] = $data
        Write-Host "[OK] $($data.Count) record(s)" -ForegroundColor $palette.Good
    } catch {
        $message = $_.Exception.Message
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{ Unavailable = $message }
        Write-Host '[UNAVAILABLE] Review with [4]' -ForegroundColor $palette.Warn
    }
}
function GiB($Bytes) { [math]::Round($Bytes / 1GB, 2) }
Write-Heading 'HWID CHECKER  /  v3.3'
Write-Host '  Hardware identity and Windows inventory. Read-only scan.' -ForegroundColor $palette.Text
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.3' }
$permissionLabel = if ($admin) { 'Administrator' } else { 'Standard user' }
Write-Host "  Computer: $env:COMPUTERNAME  |  Access: $permissionLabel" -ForegroundColor $palette.Muted
Write-Heading 'SCANNING 14 SECTIONS'
Section 'System identity' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_ComputerSystemProduct | Select-Object Vendor, Name, Version, IdentifyingNumber, UUID
}
Section 'System hardware' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemType, @{n='TotalRAM_GiB';e={GiB $_.TotalPhysicalMemory}}
}
Section 'CPU' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_Processor | Select-Object DeviceID, Name, Manufacturer, ProcessorId, SocketDesignation, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
}
Section 'Motherboard' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_BaseBoard | Select-Object Manufacturer, Product, Version, SerialNumber
}
Section 'BIOS' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate, SMBIOSMajorVersion, SMBIOSMinorVersion
}
Section 'Chassis' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_SystemEnclosure | Select-Object Manufacturer, SerialNumber, SMBIOSAssetTag, ChassisTypes
}
Section 'Memory modules' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_PhysicalMemory | Select-Object DeviceLocator, BankLabel, Manufacturer, PartNumber, SerialNumber, @{n='Capacity_GiB';e={GiB $_.Capacity}}, Speed, ConfiguredClockSpeed
}
Section 'Physical disks' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_DiskDrive | Select-Object Index, Model, SerialNumber, FirmwareRevision, InterfaceType, MediaType, @{n='Size_GiB';e={GiB $_.Size}}, PNPDeviceID
}
Section 'Storage identifiers' {
    Get-Disk | Select-Object Number, FriendlyName, SerialNumber, UniqueId, Guid, Signature, PartitionStyle, BusType, HealthStatus
}
Section 'Volumes' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, VolumeSerialNumber, FileSystem, @{n='Size_GiB';e={GiB $_.Size}}, @{n='Free_GiB';e={GiB $_.FreeSpace}}
}
Section 'Graphics adapters' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_VideoController | Select-Object Name, VideoProcessor, PNPDeviceID, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution
}
Section 'Network adapters' {
    Get-NetAdapter -IncludeHidden | Select-Object Name, InterfaceDescription, InterfaceGuid, MacAddress, PermanentAddress, Status, LinkSpeed, HardwareInterface
}
Section 'Windows' {
    Get-CimInstance -OperationTimeoutSec 20 Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime
}
Section 'Windows Machine GUID' {
    [pscustomobject]@{ MachineGuid = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid }
}
$report['Warnings'] = @($warnings.ToArray())
function Get-IdentifierRows($Inventory) {
    # Support both the live ordered dictionary and reports imported from JSON.
    $names = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory.Keys } else { $Inventory.PSObject.Properties.Name }
    foreach ($name in $names) {
        if ($name -in @('Report info', 'Warnings')) { continue }
        $records = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory[$name] } else { $Inventory.$name }
        foreach ($record in $records) {
            $device = Get-DeviceKey $name $record
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Name -notmatch $identifierPattern) { continue }
                $value = ([string]$property.Value).Trim()
                $quality = Get-Quality $value
                [pscustomobject]@{ Section = $name; Device = $device; Field = $property.Name; Value = $value; Quality = $quality }
            }
        }
    }
}
function Get-DeviceKey($SectionName, $Record) {
    $fields = switch ($SectionName) {
        'CPU' { @('DeviceID') }
        'Memory modules' { @('DeviceLocator', 'BankLabel') }
        'Physical disks' { @('Index') }
        'Storage identifiers' { @('Number') }
        'Volumes' { @('DeviceID') }
        'Graphics adapters' { @('PNPDeviceID') }
        'Network adapters' { @('InterfaceGuid') }
        default { @() }
    }
    $parts = foreach ($field in $fields) {
        $value = $Record.$field
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { "${field}=$value" }
    }
    return ($parts -join '; ')
}
function Get-ComparisonKeys($Rows) {
    foreach ($row in $Rows) {
        # JSON tuple prevents delimiter collisions in device names and identifiers.
        ConvertTo-Json -InputObject @($row.Section, $row.Device, $row.Field, $row.Value) -Compress
    }
}
function Format-ComparisonKey($Key) {
    $parts = ConvertFrom-Json -InputObject $Key
    $deviceLabel = if ($parts[1]) { " ($($parts[1]))" } else { '' }
    return "[$($parts[0])] $($parts[2])${deviceLabel}: $($parts[3])"
}
function Read-SavedReport($Path) {
    $previous = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($previous -is [array] -or -not $previous.'Report info' -or $previous.'Report info'.Version -notmatch '^([23])\.') {
        throw 'This file is not a supported HWID v2 or v3 report.'
    }
    return $previous
}
function Save-Reports {
    try {
        $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $stem = Join-Path $folder ('HWID-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        $lines = @(
            'HWID CHECKER - HARDWARE REPORT'
            '========== Report info =========='
            ($report['Report info'] | Format-List * | Out-String -Width 180)
            foreach ($group in $sectionGroups.Keys) {
                "`n========== $group =========="
                foreach ($key in $sectionGroups[$group]) {
                    if ($report.Contains($key)) {
                        "--- $key ---"
                        $report[$key] | Format-List * | Out-String -Width 180
                    }
                }
            }
            '========== Warnings =========='
            $report['Warnings']
        )
        $lines | Set-Content -LiteralPath ($stem + '.txt') -Encoding UTF8
        Write-Host "Saved: $stem.txt" -ForegroundColor $palette.Good
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($stem + '.json') -Encoding UTF8
        Write-Host "Saved: $stem.json" -ForegroundColor $palette.Good
    } catch {
        Write-Host "Unable to save reports: $($_.Exception.Message)" -ForegroundColor $palette.Error
    }
}
$identifiers = @(Get-IdentifierRows $report)
Show-Overview
while ($true) {
    Write-Heading 'MAIN MENU'
    Write-Host '  VIEW' -ForegroundColor $palette.Muted
    Show-MenuItem '1' 'Scan overview' ''
    Show-MenuItem '2' 'Identifier summary' ''
    Show-MenuItem '3' 'Browse hardware by category' ''
    Show-MenuItem '4' 'Items to review' ''
    Show-MenuItem '5' 'Full report' ''
    Write-Host '  REPORTS' -ForegroundColor $palette.Muted
    Show-MenuItem '6' 'Save TXT + JSON' 'Save now to compare with a future scan.'
    Show-MenuItem '7' 'Compare with a saved JSON report' ''
    Show-MenuItem '8' 'Open reports folder' ''
    Write-Host '  HELP & EXIT' -ForegroundColor $palette.Muted
    Show-MenuItem '9' 'Help and color key' ''
    Show-MenuItem '0' 'Exit' ''
    $choice = Read-Host 'Choose an option'
    if ($null -eq $choice) { return }
    $choice = $choice.Trim()
    switch ($choice) {
        '2' {
            if ($identifiers.Count) {
                foreach ($group in ($identifiers | Group-Object Section)) {
                    Write-Host "`n[$($group.Name)]" -ForegroundColor $palette.Heading
                    foreach ($row in $group.Group) {
                        $color = if ($row.Quality -eq 'Reported') { $palette.Good } else { $palette.Warn }
                        $value = if ($row.Value) { $row.Value } else { '(not provided)' }
                        $deviceLabel = if ($row.Device) { " ($($row.Device))" } else { '' }
                        Write-Host "  [$($row.Quality)] $($row.Field)${deviceLabel}: $value" -ForegroundColor $color
                    }
                }
            }
            else { Write-Host 'No identifiers available.' -ForegroundColor $palette.Warn }
        }
        '5' {
            Show-FullReport
        }
        '6' { Save-Reports }
        '3' { Show-Categories }
        '4' { Show-Attention }
        '9' { Show-Help }
        '1' { Show-Overview }
        '7' {
            try {
                $previousPath = ([string](Read-Host 'Path to a previously saved JSON report (blank cancels)')).Trim().Trim('"')
                if (-not $previousPath) { continue }
                $previous = Read-SavedReport $previousPath
                $oldRows = @(Get-IdentifierRows $previous)
                # Compare a multiset of identifiers; ignore volatile metrics and enumeration order.
                $before = @(Get-ComparisonKeys $oldRows | Sort-Object)
                $after = @(Get-ComparisonKeys $identifiers | Sort-Object)
                Write-Host "Previous computer: $($previous.'Report info'.Computer); captured: $($previous.'Report info'.Generated)"
                if ($previous.'Report info'.Computer -ne $report['Report info'].Computer) { Write-Host 'These reports are from different computer names.' -ForegroundColor $palette.Warn }
                Write-Host 'Device slots and disk numbers are compared too; moving hardware can produce differences.' -ForegroundColor $palette.Muted
                if ($warnings.Count -or @($previous.Warnings).Count) { Write-Host 'One or both scans have unavailable sections; differences may reflect missing access.' -ForegroundColor $palette.Warn }
                if (-not $before.Count -or -not $after.Count) { throw 'Both reports must contain identifiers to compare.' }
                $changes = @(Compare-Object -ReferenceObject $before -DifferenceObject $after -CaseSensitive)
                if (-not $changes.Count) { Write-Host 'No identifier differences found.' -ForegroundColor $palette.Good }
                else {
                    foreach ($change in $changes) {
                        $description = Format-ComparisonKey $change.InputObject
                        if ($change.SideIndicator -eq '=>') { Write-Host "[+] Current only: $description" -ForegroundColor $palette.Heading }
                        else { Write-Host "[-] Previous only: $description" -ForegroundColor $palette.Warn }
                    }
                }
            } catch { Write-Host "Comparison unavailable: $($_.Exception.Message)" -ForegroundColor $palette.Warn }
        }
        '8' {
            $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
            try {
                if (Test-Path -LiteralPath $folder -PathType Container) { Start-Process explorer.exe -ArgumentList ('"' + $folder + '"') }
                else { Write-Host 'Save a report first to create the reports folder.' }
            } catch { Write-Host "Unable to open folder: $($_.Exception.Message)" -ForegroundColor $palette.Error }
        }
        '0' { return }
        default { Write-Host 'Enter a menu number from 0 to 9.' -ForegroundColor $palette.Warn }
    }
}
