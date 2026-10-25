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
Write-Host 'DETAILED HWID CHECKER - v2.0' -ForegroundColor Green
Write-Host 'Read-only hardware inventory. No identifiers or system settings are changed.'
Write-Host 'There is no single universal HWID; applications can use different combinations.'
Write-Host 'Serials may be blank, duplicated, or manufacturer placeholders. Virtual machines may expose virtual IDs.'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '2.0' }
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
$choice = Read-Host 'Save text and JSON reports? [Y/N]'
if ($choice -match '^(y|yes)$') {
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
        exit 1
    }
}
