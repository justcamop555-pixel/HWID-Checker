@echo off
setlocal
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
function Section($Name, [scriptblock]$Query) {
    Write-Host "`n========== $Name ==========" -ForegroundColor Cyan
    try {
        $data = @(& $Query)
        if ($data.Count -eq 0) { throw 'No data returned by Windows.' }
        $report[$Name] = $data
        $data | Format-List * | Out-String -Width 180 | Write-Host
    } catch {
        $message = $_.Exception.Message
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{ Unavailable = $message }
        Write-Host "Unavailable: $message" -ForegroundColor Yellow
    }
}
function GiB($Bytes) { [math]::Round($Bytes / 1GB, 2) }
Write-Host 'DETAILED HWID CHECKER - v3.0' -ForegroundColor Green
Write-Host 'Read-only hardware inventory. No identifiers or system settings are changed.'
Write-Host 'There is no single universal HWID; applications can use different combinations.'
Write-Host 'Serials may be blank, duplicated, or manufacturer placeholders. Virtual machines may expose virtual IDs.'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.0' }
Write-Host "Administrator: $admin (if a field is denied, try Run as administrator)."
Section 'System identity' {
    Get-CimInstance Win32_ComputerSystemProduct | Select-Object Vendor, Name, Version, IdentifyingNumber, UUID
    Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemType, @{n='TotalRAM_GiB';e={GiB $_.TotalPhysicalMemory}}
}
Section 'CPU' {
    Get-CimInstance Win32_Processor | Select-Object DeviceID, Name, Manufacturer, ProcessorId, SocketDesignation, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
}
Section 'Motherboard' {
    Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, Version, SerialNumber
}
Section 'BIOS' {
    Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate, SMBIOSMajorVersion, SMBIOSMinorVersion
}
Section 'Chassis' {
    Get-CimInstance Win32_SystemEnclosure | Select-Object Manufacturer, SerialNumber, SMBIOSAssetTag, ChassisTypes
}
Section 'Memory modules' {
    Get-CimInstance Win32_PhysicalMemory | Select-Object DeviceLocator, BankLabel, Manufacturer, PartNumber, SerialNumber, @{n='Capacity_GiB';e={GiB $_.Capacity}}, Speed, ConfiguredClockSpeed
}
Section 'Physical disks' {
    Get-CimInstance Win32_DiskDrive | Select-Object Index, Model, SerialNumber, FirmwareRevision, InterfaceType, MediaType, @{n='Size_GiB';e={GiB $_.Size}}, PNPDeviceID
}
Section 'Storage identifiers' {
    Get-Disk | Select-Object Number, FriendlyName, SerialNumber, UniqueId, Guid, Signature, PartitionStyle, BusType, HealthStatus
}
Section 'Volumes' {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, VolumeSerialNumber, FileSystem, @{n='Size_GiB';e={GiB $_.Size}}, @{n='Free_GiB';e={GiB $_.FreeSpace}}
}
Section 'Graphics adapters' {
    Get-CimInstance Win32_VideoController | Select-Object Name, VideoProcessor, PNPDeviceID, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution
}
Section 'Network adapters' {
    Get-NetAdapter -IncludeHidden | Select-Object Name, InterfaceDescription, InterfaceGuid, MacAddress, PermanentAddress, Status, LinkSpeed, HardwareInterface
}
Section 'Windows' {
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime
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
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Name -notmatch '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$') { continue }
                $value = ([string]$property.Value).Trim()
                $quality = if ([string]::IsNullOrWhiteSpace($value)) { 'Missing' }
                    elseif ($value -match '^(unknown|none|n/a|not (specified|available|applicable)|default string|to be filled.*|system serial number|0+|f+|0{8}-0{4}-0{4}-0{4}-0{12}|f{8}-f{4}-f{4}-f{4}-f{12})$') { 'Placeholder' }
                    else { 'Reported' }
                [pscustomobject]@{ Section = $name; Field = $property.Name; Value = $value; Quality = $quality }
            }
        }
    }
}
function Save-Reports {
    try {
        $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $stem = Join-Path $folder ('HWID-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        $lines = foreach ($key in $report.Keys) {
            "========== $key =========="
            $report[$key] | Format-List * | Out-String -Width 180
        }
        $lines | Set-Content -LiteralPath ($stem + '.txt') -Encoding UTF8
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($stem + '.json') -Encoding UTF8
        Write-Host "Saved: $stem.txt" -ForegroundColor Green
        Write-Host "Saved: $stem.json" -ForegroundColor Green
    } catch {
        Write-Host "Unable to save reports: $($_.Exception.Message)" -ForegroundColor Red
    }
}
$identifiers = @(Get-IdentifierRows $report)
Write-Host "`nScan complete: $($warnings.Count) unavailable sections; $(@($identifiers | Where-Object Quality -ne 'Reported').Count) missing or placeholder identifiers." -ForegroundColor Cyan
Write-Host 'Reported means Windows supplied a value; it does not verify uniqueness or authenticity.'
while ($true) {
    Write-Host "`n[1] Identifier summary  [2] Full report  [3] Save TXT + JSON"
    Write-Host '[4] Compare identifiers with saved JSON  [5] Open reports folder  [0] Exit'
    $choice = Read-Host 'Choose an option'
    switch ($choice) {
        '1' {
            if ($identifiers.Count) { $identifiers | Format-Table Section, Field, Value, Quality -Wrap | Out-String -Width 180 | Write-Host }
            else { Write-Host 'No identifiers available.' -ForegroundColor Yellow }
        }
        '2' {
            foreach ($key in $report.Keys) {
                Write-Host "`n========== $key ==========" -ForegroundColor Cyan
                $report[$key] | Format-List * | Out-String -Width 180 | Write-Host
            }
        }
        '3' { Save-Reports }
        '4' {
            $previousPath = (Read-Host 'Path to a previously saved JSON report').Trim().Trim('"')
            try {
                $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
                if (-not $previous.'Report info' -or -not $previous.'Report info'.Version) { throw 'This file is not a supported HWID report.' }
                $oldRows = @(Get-IdentifierRows $previous)
                # Compare a multiset of identifiers; ignore volatile metrics and enumeration order.
                $before = @($oldRows | ForEach-Object { '{0} | {1} | {2}' -f $_.Section, $_.Field, $_.Value } | Sort-Object)
                $after = @($identifiers | ForEach-Object { '{0} | {1} | {2}' -f $_.Section, $_.Field, $_.Value } | Sort-Object)
                Write-Host "Previous computer: $($previous.'Report info'.Computer); captured: $($previous.'Report info'.Generated)"
                if ($warnings.Count -or @($previous.Warnings).Count) { Write-Host 'One or both scans have unavailable sections; differences may reflect missing access.' -ForegroundColor Yellow }
                if (-not $before.Count -or -not $after.Count) { throw 'Both reports must contain identifiers to compare.' }
                $changes = @(Compare-Object -ReferenceObject $before -DifferenceObject $after)
                if (-not $changes.Count) { Write-Host 'No identifier differences found.' -ForegroundColor Green }
                else {
                    $changes | Select-Object @{n='Change';e={if ($_.SideIndicator -eq '=>') {'Current only'} else {'Previous only'}}}, @{n='Identifier';e={$_.InputObject}} | Format-Table -Wrap | Out-String -Width 180 | Write-Host
                }
            } catch { Write-Host "Comparison unavailable: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
        '5' {
            $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
            if (Test-Path -LiteralPath $folder -PathType Container) { Start-Process explorer.exe -ArgumentList ('"' + $folder + '"') }
            else { Write-Host 'Save a report first to create the reports folder.' }
        }
        '0' { return }
        default { Write-Host 'Enter 0, 1, 2, 3, 4, or 5.' -ForegroundColor Yellow }
    }
}
