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
$identifierPattern = '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
function Get-Quality($Value) {
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Missing' }
    if ($text -match '^(unknown|none|n/a|not (specified|available|applicable)|default string|to be filled.*|system serial number|0+|f+)$' -or $text -match '^[0:{} -]+$' -or $text -match '^[fF:{} -]+$') { return 'Placeholder' }
    return 'Reported'
}
function Show-Records($Records) {
    foreach ($record in $Records) {
        $properties = if ($record -is [System.Collections.IDictionary]) {
            foreach ($key in $record.Keys) { [pscustomobject]@{Name=$key; Value=$record[$key]} }
        } elseif ($record -is [string]) {
            [pscustomobject]@{Name='Message'; Value=$record}
        } else { $record.PSObject.Properties }
        foreach ($property in $properties) {
            $value = if ($property.Value -is [array]) { $property.Value -join ', ' } else { [string]$property.Value }
            $color = 'White'
            $status = ''
            if ($property.Name -match $identifierPattern) {
                $quality = Get-Quality $value
                $color = if ($quality -eq 'Reported') { 'Green' } else { 'Yellow' }
                $status = " [$quality]"
            } elseif ($property.Name -eq 'Unavailable') { $color = 'Yellow' }
            if ([string]::IsNullOrWhiteSpace($value)) { $value = '(not provided)'; $color = 'Yellow' }
            Write-Host ('  {0,-26}: ' -f $property.Name) -ForegroundColor Gray -NoNewline
            Write-Host ($value + $status) -ForegroundColor $color
        }
        Write-Host ''
    }
}
function Section($Name, [scriptblock]$Query) {
    Write-Host "`n========== $Name ==========" -ForegroundColor Cyan
    try {
        $data = @(& $Query)
        if ($data.Count -eq 0) { throw 'No data returned by Windows.' }
        $report[$Name] = $data
        Show-Records $data
    } catch {
        $message = $_.Exception.Message
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{ Unavailable = $message }
        Write-Host "Unavailable: $message" -ForegroundColor Yellow
    }
}
function GiB($Bytes) { [math]::Round($Bytes / 1GB, 2) }
Write-Host 'DETAILED HWID CHECKER - v3.2' -ForegroundColor Green
Write-Host 'COLOR KEY: headings / actions' -ForegroundColor Cyan
Write-Host '  [Reported] Value supplied by Windows' -ForegroundColor Green
Write-Host '  [Missing / Placeholder] Check this value; unavailable sections also appear yellow' -ForegroundColor Yellow
Write-Host '  [Error] An operation failed' -ForegroundColor Red
Write-Host 'Read-only hardware inventory. No identifiers or system settings are changed.'
Write-Host 'There is no single universal HWID; applications can use different combinations.'
Write-Host 'Serials may be blank, duplicated, or manufacturer placeholders. Virtual machines may expose virtual IDs.'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.2' }
Write-Host "Administrator: $admin (if a field is denied, try Run as administrator)."
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
Write-Host "`nNotes: MachineGuid identifies the Windows installation. Volume serials identify formatted volumes."
Write-Host 'MAC addresses can be overridden or randomized. PNPDeviceID is a Windows device identifier.'
Write-Host 'Clock speeds are reported in MHz; memory speeds use the units reported by firmware.'
Write-Host 'Exported reports contain device identifiers. Share them only with people you trust.' -ForegroundColor Yellow
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
        $lines = foreach ($key in $report.Keys) {
            "========== $key =========="
            $report[$key] | Format-List * | Out-String -Width 180
        }
        $lines | Set-Content -LiteralPath ($stem + '.txt') -Encoding UTF8
        Write-Host "Saved: $stem.txt" -ForegroundColor Green
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($stem + '.json') -Encoding UTF8
        Write-Host "Saved: $stem.json" -ForegroundColor Green
    } catch {
        Write-Host "Unable to save reports: $($_.Exception.Message)" -ForegroundColor Red
    }
}
$identifiers = @(Get-IdentifierRows $report)
Write-Host "`nScan complete: $($warnings.Count) unavailable sections; $(@($identifiers | Where-Object Quality -ne 'Reported').Count) missing or placeholder identifiers." -ForegroundColor Cyan
Write-Host 'Reported means Windows supplied a value; it does not verify uniqueness or authenticity.'
while ($true) {
    Write-Host "`n================ ACTIONS ================" -ForegroundColor Cyan
    Write-Host '[1] Identifier summary  [2] Full report  [3] Save TXT + JSON' -ForegroundColor Cyan
    Write-Host '[4] Compare identifiers with saved JSON  [5] Open reports folder  [0] Exit' -ForegroundColor Cyan
    Write-Host 'TIP: Save a report now to compare against a future scan.' -ForegroundColor Gray
    $choice = Read-Host 'Choose an option'
    if ($null -eq $choice) { return }
    $choice = $choice.Trim()
    switch ($choice) {
        '1' {
            if ($identifiers.Count) {
                foreach ($group in ($identifiers | Group-Object Section)) {
                    Write-Host "`n[$($group.Name)]" -ForegroundColor Cyan
                    foreach ($row in $group.Group) {
                        $color = if ($row.Quality -eq 'Reported') { 'Green' } else { 'Yellow' }
                        $value = if ($row.Value) { $row.Value } else { '(not provided)' }
                        $deviceLabel = if ($row.Device) { " ($($row.Device))" } else { '' }
                        Write-Host "  [$($row.Quality)] $($row.Field)${deviceLabel}: $value" -ForegroundColor $color
                    }
                }
            }
            else { Write-Host 'No identifiers available.' -ForegroundColor Yellow }
        }
        '2' {
            foreach ($key in $report.Keys) {
                Write-Host "`n========== $key ==========" -ForegroundColor Cyan
                Show-Records $report[$key]
            }
        }
        '3' { Save-Reports }
        '4' {
            try {
                $previousPath = ([string](Read-Host 'Path to a previously saved JSON report (blank cancels)')).Trim().Trim('"')
                if (-not $previousPath) { continue }
                $previous = Read-SavedReport $previousPath
                $oldRows = @(Get-IdentifierRows $previous)
                # Compare a multiset of identifiers; ignore volatile metrics and enumeration order.
                $before = @(Get-ComparisonKeys $oldRows | Sort-Object)
                $after = @(Get-ComparisonKeys $identifiers | Sort-Object)
                Write-Host "Previous computer: $($previous.'Report info'.Computer); captured: $($previous.'Report info'.Generated)"
                if ($previous.'Report info'.Computer -ne $report['Report info'].Computer) { Write-Host 'These reports are from different computer names.' -ForegroundColor Yellow }
                Write-Host 'Device slots and disk numbers are compared too; moving hardware can produce differences.' -ForegroundColor Gray
                if ($warnings.Count -or @($previous.Warnings).Count) { Write-Host 'One or both scans have unavailable sections; differences may reflect missing access.' -ForegroundColor Yellow }
                if (-not $before.Count -or -not $after.Count) { throw 'Both reports must contain identifiers to compare.' }
                $changes = @(Compare-Object -ReferenceObject $before -DifferenceObject $after -CaseSensitive)
                if (-not $changes.Count) { Write-Host 'No identifier differences found.' -ForegroundColor Green }
                else {
                    foreach ($change in $changes) {
                        $description = Format-ComparisonKey $change.InputObject
                        if ($change.SideIndicator -eq '=>') { Write-Host "[+] Current only: $description" -ForegroundColor Cyan }
                        else { Write-Host "[-] Previous only: $description" -ForegroundColor Yellow }
                    }
                }
            } catch { Write-Host "Comparison unavailable: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
        '5' {
            $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
            try {
                if (Test-Path -LiteralPath $folder -PathType Container) { Start-Process explorer.exe -ArgumentList ('"' + $folder + '"') }
                else { Write-Host 'Save a report first to create the reports folder.' }
            } catch { Write-Host "Unable to open folder: $($_.Exception.Message)" -ForegroundColor Red }
        }
        '0' { return }
        default { Write-Host 'Enter 0, 1, 2, 3, 4, or 5.' -ForegroundColor Yellow }
    }
}
