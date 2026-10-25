@echo off
setlocal DisableDelayedExpansion
title Detailed HWID Checker
set "HWID_SCRIPT=%~f0"
set "HWID_CURRENT_WINDOW=%~1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw = [IO.File]::ReadAllText($env:HWID_SCRIPT); & ([scriptblock]::Create(($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]))"
set "HWID_EXIT=%errorlevel%"
echo.
if not "%HWID_EXIT%"=="0" (
    echo The checker encountered an error. See the message above.
    pause
)
exit /b %HWID_EXIT%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
function Get-ReadableLaunchPlan($PowerShellPath) {
    # Environment carries the path literally, including spaces, !, &, and Unicode.
    $loader = @'
$env:HWID_OWN_CONSOLE = '1'
$env:WT_SESSION = $null
$env:WT_PROFILE_ID = $null
try {
    $raw = [IO.File]::ReadAllText($env:HWID_SCRIPT)
    & ([scriptblock]::Create(($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1]))
} catch {
    Write-Host ('Unable to run checker: ' + $_.Exception.Message) -ForegroundColor Red
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($loader))
    [pscustomobject]@{
        FilePath=(Join-Path $env:SystemRoot 'System32\conhost.exe')
        Arguments=('-ForceNoHandoff -- "' + $PowerShellPath + '" -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded)
        EncodedLoader=$encoded
    }
}
function Test-ReadableLaunchNeeded($Redirected, $Owned, $CurrentWindow) {
    return -not $Redirected -and -not $Owned -and $CurrentWindow -ne '--current-window'
}
function Start-ReadableConsole($ScriptPath, $Redirected, $Owned, $CurrentWindow) {
    if (-not (Test-ReadableLaunchNeeded $Redirected $Owned $CurrentWindow)) { return $false }
    try {
        $plan = Get-ReadableLaunchPlan (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        if (-not (Test-Path -LiteralPath $plan.FilePath -PathType Leaf)) { return $false }
        $child = Start-Process -FilePath $plan.FilePath -ArgumentList $plan.Arguments -WorkingDirectory (Split-Path -Parent $ScriptPath) -PassThru
        # If this host cannot start, continue in the current window instead of looping.
        if ($child.WaitForExit(700) -and $child.ExitCode -ne 0) { return $false }
        return $true
    } catch { return $false }
}
function Initialize-ReadableConsole($Owned, $Redirected) {
    $result = [ordered]@{ Mode='Current window'; FontApplied=$false; FontName=''; FontHeight=0; FontWeight=0; Columns=0; Rows=0; QuickEditDisabled=$false; InputModeBefore=0; InputModeAfter=0 }
    if (-not $Owned -or $Redirected) { return [pscustomobject]$result }
    $result.Mode = 'Classic console'
    try {
        if (-not ('HwidConsoleDisplay' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HwidConsoleDisplay {
    [StructLayout(LayoutKind.Sequential)] public struct Coord { public short X; public short Y; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct FontInfo {
        public uint Size; public uint Index; public Coord Cell; public uint Family; public uint Weight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Face;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetConsoleMode(IntPtr handle, out uint mode);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetConsoleMode(IntPtr handle, uint mode);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool GetCurrentConsoleFontEx(IntPtr output, bool maximum, ref FontInfo info);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool SetCurrentConsoleFontEx(IntPtr output, bool maximum, ref FontInfo info);
    public static bool ApplyFont() {
        if (!IsWindowVisible(GetConsoleWindow())) return false;
        var info = new FontInfo(); info.Size = (uint)Marshal.SizeOf(typeof(FontInfo));
        if (!GetCurrentConsoleFontEx(GetStdHandle(-11), false, ref info)) return false;
        info.Face = "Consolas"; info.Cell.X = 0; info.Cell.Y = 16; info.Weight = 400; info.Family = 54;
        return SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref info);
    }
    public static FontInfo ReadFont() {
        var info = new FontInfo(); info.Size = (uint)Marshal.SizeOf(typeof(FontInfo));
        GetCurrentConsoleFontEx(GetStdHandle(-11), false, ref info); return info;
    }
    public static uint WithoutQuickEdit(uint mode) { return (mode | 0x0080u) & ~0x0040u; }
    public static uint ReadInputMode() {
        uint mode; return GetConsoleMode(GetStdHandle(-10), out mode) ? mode : 0;
    }
    public static bool DisableQuickEdit(out uint before, out uint after) {
        before = 0; after = 0;
        var input = GetStdHandle(-10);
        if (!GetConsoleMode(input, out before)) return false;
        if (!SetConsoleMode(input, WithoutQuickEdit(before))) return false;
        return GetConsoleMode(input, out after) && (after & 0x0040u) == 0 && (after & 0x0080u) != 0;
    }
}
'@
        }
        # Quick Edit mouse selection suspends console output. Disable it for this owned window only.
        $before=[uint32]0; $after=[uint32]0
        $result.QuickEditDisabled=[HwidConsoleDisplay]::DisableQuickEdit([ref]$before,[ref]$after)
        $result.InputModeBefore=$before; $result.InputModeAfter=$after
        $result.FontApplied = [HwidConsoleDisplay]::ApplyFont()
        $font = [HwidConsoleDisplay]::ReadFont()
        $result.FontName=$font.Face; $result.FontHeight=$font.Cell.Y; $result.FontWeight=$font.Weight
        [Console]::Title = 'HWID Checker - Readable view'
        # Resize only the dedicated window. Respect the screen's maximum character dimensions.
        $width=[math]::Min(100,[Console]::LargestWindowWidth)
        $height=[math]::Min(34,[Console]::LargestWindowHeight)
        if ($width -gt 0 -and $height -gt 0) {
            [Console]::SetBufferSize([math]::Max($width,[Console]::BufferWidth),[math]::Max(300,[Console]::BufferHeight))
            [Console]::SetWindowPosition(0,0)
            [Console]::SetWindowSize($width,$height)
            [Console]::SetBufferSize($width,[math]::Max(300,[Console]::BufferHeight))
        }
        $result.Columns=[Console]::WindowWidth; $result.Rows=[Console]::WindowHeight
    } catch { $result.Mode='Classic console (default display)' }
    return [pscustomobject]$result
}
$redirected = [Console]::IsInputRedirected -or [Console]::IsOutputRedirected
$ownedConsole = $env:HWID_OWN_CONSOLE -eq '1'
if (Start-ReadableConsole $env:HWID_SCRIPT $redirected $ownedConsole $env:HWID_CURRENT_WINDOW) { return }
$display = Initialize-ReadableConsole $ownedConsole $redirected
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
function Test-SectionReadable($Records) {
    $items = @($Records | Where-Object { $null -ne $_ })
    return $items.Count -gt 0 -and @($items | Where-Object { $_.Unavailable }).Count -eq 0
}
function Get-FieldLabel($Name) {
    $labels = @{
        ProcessorId='CPU identifier'; UUID='System UUID'; SerialNumber='Serial number'
        IdentifyingNumber='System serial number'; MachineGuid='Windows installation ID'
        PNPDeviceID='Windows device ID'; SMBIOSAssetTag='Asset tag'
        SMBIOSBIOSVersion='BIOS version'; SMBIOSMajorVersion='SMBIOS major version'; SMBIOSMinorVersion='SMBIOS minor version'
        TotalRAM_GiB='Total memory (GiB)'; Capacity_GiB='Module size (GiB)'; Size_GiB='Size (GiB)'; Free_GiB='Free space (GiB)'
        MaxClockSpeed='Maximum CPU clock (MHz)'; Speed='Rated speed (MHz)'; ConfiguredClockSpeed='Configured speed (MHz)'
        MacAddress='Current MAC address'; PermanentAddress='Permanent MAC address'; InterfaceGuid='Network interface ID'
        VolumeSerialNumber='Volume serial number'; Guid='GPT disk ID'; UniqueId='Storage unique ID'; Signature='MBR disk signature'
        DeviceLocator='Memory slot'; BankLabel='Memory bank'; DeviceID='Device / drive'; NumberOfCores='CPU cores'; NumberOfLogicalProcessors='CPU threads'
    }
    if ($labels.ContainsKey($Name)) { return $labels[$Name] }
    return (($Name -creplace '([a-z])([A-Z])', '$1 $2') -replace '_', ' ')
}
function Get-FieldQuality($Name, $Value, $Record) {
    if ($Name -eq 'Guid' -and $null -ne $Record.PartitionStyle -and [string]$Record.PartitionStyle -in @('MBR','RAW','0','1')) { return 'Not applicable' }
    if ($Name -eq 'PermanentAddress' -and [string]::IsNullOrWhiteSpace([string]$Value) -and $null -ne $Record.HardwareInterface -and $Record.HardwareInterface -eq $false) { return 'Not applicable' }
    return (Get-Quality $Value)
}
function Get-StatusLabel($Quality) {
    switch ($Quality) {
        'Reported' { 'Found' }
        'Missing' { 'Not supplied' }
        'Placeholder' { 'Default value' }
        default { $Quality }
    }
}
function Format-FieldValue($Value) {
    if ($null -eq $Value) { return '(not provided)' }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm:ss zzz') }
    if ($Value -is [bool]) { if ($Value) { return 'Yes' }; return 'No' }
    if ($Value -is [array]) { return (($Value | ForEach-Object { Format-FieldValue $_ }) -join ', ') }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '(not provided)' }
    return [string]$Value
}
function Get-PlainRecords($Records) {
    foreach ($record in $Records) {
        $properties = if ($record -is [System.Collections.IDictionary]) {
            foreach ($key in $record.Keys) { [pscustomobject]@{Name=$key;Value=$record[$key]} }
        } else { $record.PSObject.Properties }
        foreach ($property in $properties) { '  {0}: {1}' -f (Get-FieldLabel $property.Name), (Format-FieldValue $property.Value) }
        ''
    }
}
function Get-QuickIds($Inventory) {
    $fields = @(
        @('System identity','IdentifyingNumber','System serial'), @('System identity','UUID','System UUID'),
        @('Motherboard','SerialNumber','Board serial'), @('BIOS','SerialNumber','BIOS serial'),
        @('CPU','ProcessorId','CPU'), @('Memory modules','SerialNumber','RAM'),
        @('Disk summary','',''), @('Volumes','VolumeSerialNumber','Volume'),
        @('Network adapters','MacAddress','Net'), @('Windows Machine GUID','MachineGuid','Windows ID')
    )
    foreach ($entry in $fields) {
        $section = $entry[0]; $field = $entry[1]; $label = $entry[2]
        if ($section -eq 'Disk summary') { Get-QuickDisks $Inventory; continue }
        $records = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory[$section] } else { $Inventory.$section }
        if (-not (Test-SectionReadable $records)) { continue }
        $index = 0
        foreach ($record in $records) {
            $index++
            $suffix = switch ($section) {
                'CPU' { if (@($records).Count -gt 1) { " $index" } }
                'Memory modules' { if ($record.DeviceLocator) { " $index " + $record.DeviceLocator } else { " $index" } }
                'Physical disks' { if ($null -ne $record.Index) { ' ' + $record.Index } else { " $index" } }
                'Storage identifiers' { if ($null -ne $record.Number) { ' ' + $record.Number } else { " $index" } }
                'Volumes' { ' ' + $record.DeviceID }
                'Network adapters' { if ($record.Name) { " $index " + $record.Name } else { " $index" } }
                default { '' }
            }
            $value = ([string]$record.$field).Trim()
            [pscustomobject]@{Label=($label + $suffix);Value=$value;Quality=(Get-Quality $value)}
        }
    }
}
function Get-QuickDisks($Inventory) {
    $physical = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory['Physical disks'] } else { $Inventory.'Physical disks' }
    $storage = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory['Storage identifiers'] } else { $Inventory.'Storage identifiers' }
    $primary = if (Test-SectionReadable $physical) { @($physical) } else { @() }
    $secondary = if (Test-SectionReadable $storage) { @($storage) } else { @() }
    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    $index = 0
    foreach ($disk in $primary) {
        $index++
        $number = $disk.Index
        $matches = @($secondary | Where-Object { $null -ne $number -and $null -ne $_.Number -and $_.Number -eq $number })
        $value = ([string]$disk.SerialNumber).Trim()
        $quality = Get-Quality $value
        $note = ''
        if ($matches.Count -eq 1) {
            [void]$used.Add([int]$matches[0].Number)
            $other = ([string]$matches[0].SerialNumber).Trim()
            if ((Get-Quality $other) -eq 'Reported') {
                if ($quality -ne 'Reported') { $value=$other; $quality='Reported'; $note='Alternate source' }
                elseif ($value -cne $other) { $quality='Conflict'; $note='Sources disagree'; $value += ' / ' + $other }
            }
        }
        $label = if ($null -ne $number) { "Disk $number" } else { "Disk ?$index" }
        [pscustomobject]@{Label=$label;Value=$value;Quality=$quality;Note=$note}
    }
    foreach ($disk in $secondary) {
        if ($null -ne $disk.Number -and $used.Contains([int]$disk.Number)) { continue }
        # Without a reliable disk number, do not guess that two records are the same device.
        $index++
        $label = if ($null -ne $disk.Number) { "Disk $($disk.Number)" } else { "Disk ?$index" }
        $value = ([string]$disk.SerialNumber).Trim()
        [pscustomobject]@{Label=$label;Value=$value;Quality=(Get-Quality $value);Note='Alternate source'}
    }
}
function Get-QuickLayout($Width) {
    if ($Width -le 0) { $Width = 72 }
    $label = if ($Width -ge 68) { 18 } elseif ($Width -ge 45) { 12 } else { 7 }
    [pscustomobject]@{LabelWidth=$label;ValueWidth=[math]::Max(8,[math]::Min(60,$Width-$label-14))}
}
function Limit-TableText($Text, $Width) {
    $clean = ([string]$Text -replace '[\r\n\t]', ' ')
    if ($Width -le 0) { return '' }
    if ($clean.Length -le $Width) { return $clean }
    if ($Width -le 3) { return ('.' * $Width) }
    return $clean.Substring(0, $Width - 3) + '...'
}
function Show-QuickIds {
    Write-Heading 'DEVICE IDs / QUICK VIEW'
    $rows = @(Get-QuickIds $report)
    if (-not $rows.Count) { Write-Host '  No IDs available. Use [4] to check why.' -ForegroundColor $palette.Warn; return }
    $windowWidth = 72
    try { if ([Console]::WindowWidth -gt 0) { $windowWidth = [Console]::WindowWidth } } catch { }
    $layout = Get-QuickLayout $windowWidth
    $valueWidth = $layout.ValueWidth; $labelWidth=$layout.LabelWidth
    $format = '  {0,-' + $labelWidth + '}  {1,-' + $valueWidth + '}  {2}'
    Write-Host ($format -f 'DEVICE', 'ID / SERIAL', 'STATUS') -ForegroundColor $palette.Muted
    foreach ($row in $rows) {
        $status = switch ($row.Quality) { 'Reported' { if ($row.Note -eq 'Alternate source') { 'OK*' } else { 'OK' } }; 'Missing' { 'Missing' }; 'Conflict' { 'Clash' }; default { 'Default' } }
        $value = if ($row.Quality -eq 'Missing') { '-' } elseif ($row.Quality -eq 'Placeholder') { '(default value)' } else { $row.Value }
        $color = if ($row.Quality -eq 'Reported') { $palette.Good } else { $palette.Warn }
        Write-Host (('  {0,-' + $labelWidth + '}  ') -f (Limit-TableText $row.Label $labelWidth)) -ForegroundColor $palette.Text -NoNewline
        Write-Host (('{0,-' + $valueWidth + '}  ') -f (Limit-TableText $value $valueWidth)) -ForegroundColor $color -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    Write-Host "`n  ... = shortened. [5] All details / full IDs   [6] Save report" -ForegroundColor $palette.Muted
    if (@($rows | Where-Object Note -eq 'Alternate source').Count) { Write-Host '  * Serial from the alternate Windows storage source.' -ForegroundColor $palette.Muted }
    if (@($rows | Where-Object Quality -eq 'Conflict').Count) { Write-Host '  Clash = Windows sources disagree. [4] Review / [5] Both sources' -ForegroundColor $palette.Warn }
    if ($warnings.Count) { Write-Host '  Some sections could not be read. [4] Review issues' -ForegroundColor $palette.Warn }
}
function Show-Overview {
    Write-Heading 'SCAN OVERVIEW'
    Write-Host "  Computer : $($report['Report info'].Computer)" -ForegroundColor $palette.Text
    Write-Host "  Captured : $($report['Report info'].Generated)" -ForegroundColor $palette.Muted
    $reported = @($identifiers | Where-Object Quality -eq 'Reported').Count
    $missing = @($identifiers | Where-Object Quality -eq 'Missing').Count
    $placeholder = @($identifiers | Where-Object Quality -eq 'Placeholder').Count
    $clashCount = @(Get-QuickDisks $report | Where-Object Quality -eq 'Conflict').Count
    Write-Host "  [FOUND]    $reported device IDs supplied by Windows" -ForegroundColor $palette.Good
    $attentionColor = if ($missing + $placeholder + $warnings.Count + $clashCount) { $palette.Warn } else { $palette.Good }
    Write-Host "  [CHECK]    $missing not supplied / $placeholder default values / $($warnings.Count) sections not read" -ForegroundColor $attentionColor
    if ($clashCount) { Write-Host "  [CLASH]    $clashCount disk serial(s) differ between sources. Use [4]." -ForegroundColor $palette.Warn }
    foreach ($group in $sectionGroups.Keys) {
        $available = @($sectionGroups[$group] | Where-Object { $report.Contains($_) -and (Test-SectionReadable $report[$_]) }).Count
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
    $conflicts = @(Get-QuickDisks $report | Where-Object Quality -eq 'Conflict')
    if (-not $issues.Count -and -not $warnings.Count -and -not $conflicts.Count) {
        Write-Host '  [OK] No missing identifiers, placeholders, or failed sections detected.' -ForegroundColor $palette.Good
    }
    foreach ($conflict in $conflicts) { Write-Host "  [SOURCE CLASH] $($conflict.Label): Windows reports two different serials. See [5]." -ForegroundColor $palette.Warn }
    foreach ($warning in $warnings) {
        $split = $warning -split ': ', 2
        Write-Host "  [NOT READ] $($split[0])" -ForegroundColor $palette.Warn
        $advice = if ($split[1] -match 'access|denied|privilege|permission|authorized') { 'Windows blocked access. Try Run as administrator.' }
            elseif ($split[1] -match 'No data') { 'Windows did not return a device for this section.' }
            else { 'Windows could not read this section. See Full report for the technical message.' }
        Write-Host "      $advice" -ForegroundColor $palette.Muted
    }
    foreach ($row in $issues) {
        $device = if ($row.Device) { " ($($row.Device))" } else { '' }
        $status = if ($row.Quality -eq 'Missing') { 'NOT SUPPLIED' } else { 'DEFAULT VALUE' }
        Write-Host "  [$status] $($row.Section)${device} / $(Get-FieldLabel $row.Field)" -ForegroundColor $palette.Warn
        if ($row.Quality -eq 'Placeholder') { Write-Host "      Windows returned '$($row.Value)' instead of a useful ID." -ForegroundColor $palette.Muted }
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
    Write-Host '  [FOUND / OK] Windows returned data, or an action succeeded.' -ForegroundColor $palette.Good
    Write-Host '  [REVIEW] Missing, placeholder, unavailable, or previous-only data.' -ForegroundColor $palette.Warn
    Write-Host '  [ERROR] A save or folder action failed.' -ForegroundColor $palette.Error
    Write-Host '  [+] Current-only comparison data; headings and menu keys.' -ForegroundColor $palette.Heading
    Write-Host '  Labels and notes use neutral text. Status words also explain every color.' -ForegroundColor $palette.Muted
    Write-Host ''
    @(
        'HWID is not one universal number. Applications choose different identifiers.',
        'MachineGuid identifies Windows; volume serials identify formatted volumes.',
        'MAC addresses can be overridden or randomized. PNPDeviceID identifies a Windows device.',
        'CPU and memory speeds are shown as MHz reported by Windows. Capacity uses GiB.',
        'Not supplied means Windows returned no ID. Default value means a generic firmware value.',
        'A GPT disk ID does not apply to MBR or RAW disks. This is normal.',
        'Virtual adapters may have no permanent MAC address. This is normal.',
        'Compare saved JSON reports to track changes. Moving hardware can change slot labels.',
        'Comparisons skip unreadable sections and missing/default fields on either scan.',
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
            $value = Format-FieldValue $property.Value
            $color = $palette.Text
            $status = ''
            if ($property.Name -match $identifierPattern) {
                $quality = Get-FieldQuality $property.Name $property.Value $record
                $color = if ($quality -eq 'Reported') { $palette.Good } elseif ($quality -eq 'Not applicable') { $palette.Muted } else { $palette.Warn }
                if ($quality -eq 'Not applicable') { $value = 'Not used by this device' }
                $status = " [$(Get-StatusLabel $quality)]"
            } elseif ($property.Name -eq 'Unavailable') { $color = $palette.Warn }
            if ($value -eq '(not provided)') { $color = $palette.Warn }
            Write-Host ('  {0,-28}: ' -f (Get-FieldLabel $property.Name)) -ForegroundColor $palette.Muted -NoNewline
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
        # Normalize dates before export so JSON is consistent in Windows PowerShell 5.1 and 7.
        $data = @(foreach ($record in $data) {
            $normalized = [ordered]@{}
            foreach ($property in $record.PSObject.Properties) {
                $normalized[$property.Name] = if ($property.Value -is [datetime]) { $property.Value.ToString('o') }
                    elseif ($property.Value -is [enum]) { $property.Value.ToString() }
                    else { $property.Value }
            }
            [pscustomobject]$normalized
        })
        $report[$Name] = $data
        Write-Host "[OK] $($data.Count) record(s)" -ForegroundColor $palette.Good
    } catch {
        $message = $_.Exception.Message
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{ Unavailable = $message }
        Write-Host '[UNAVAILABLE] Review with [4]' -ForegroundColor $palette.Warn
    }
}
function GiB($Bytes) { if ($null -eq $Bytes) { return $null }; [math]::Round($Bytes / 1GB, 2) }
Write-Heading 'HWID CHECKER  /  v3.9'
Write-Host '  Hardware identity and Windows inventory. Read-only scan.' -ForegroundColor $palette.Text
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.9'; Display=$display.Mode }
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
                $quality = Get-FieldQuality $property.Name $property.Value $record
                if ($quality -eq 'Not applicable') { continue }
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
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { "${field}=$(Get-CanonicalIdentifier $field $value)" }
    }
    return ($parts -join '; ')
}
function Get-CanonicalIdentifier($Field, $Value) {
    $text = ([string]$Value).Trim()
    if ($Field -in @('MacAddress','PermanentAddress')) {
        $compact = $text -replace '[-:]', ''
        if ($compact -match '^[0-9a-fA-F]{12}$') { return $compact.ToUpperInvariant() }
    }
    if ($Field -in @('UUID','Guid','InterfaceGuid','MachineGuid')) {
        $parsed = [guid]::Empty
        if ([guid]::TryParse($text, [ref]$parsed)) { return $parsed.ToString('D') }
    }
    return $text
}
function Get-ComparisonKeys($Rows) {
    foreach ($row in $Rows) {
        # JSON tuple prevents delimiter collisions in device names and identifiers.
        ConvertTo-Json -InputObject @($row.Section, $row.Device, $row.Field, (Get-CanonicalIdentifier $row.Field $row.Value)) -Compress
    }
}
function Compare-Inventories($Previous, $Current) {
    $idSections = @('System identity','CPU','Motherboard','BIOS','Chassis','Memory modules','Physical disks','Storage identifiers','Volumes','Graphics adapters','Network adapters','Windows Machine GUID')
    $common = @()
    $skipped = @()
    foreach ($section in $idSections) {
        $old = if ($Previous -is [System.Collections.IDictionary]) { $Previous[$section] } else { $Previous.$section }
        $new = if ($Current -is [System.Collections.IDictionary]) { $Current[$section] } else { $Current.$section }
        if ((Test-SectionReadable $old) -and (Test-SectionReadable $new)) { $common += $section }
        else { $skipped += $section }
    }
    $oldRows = @(Get-IdentifierRows $Previous | Where-Object { $_.Section -in $common })
    $newRows = @(Get-IdentifierRows $Current | Where-Object { $_.Section -in $common })
    # If either side has an unreadable value for the same field/device, skip that field on both sides.
    $unreadable = @{}
    foreach ($row in @($oldRows) + @($newRows)) {
        if ($row.Quality -ne 'Reported') {
            $key = ConvertTo-Json -InputObject @($row.Section,$row.Device,$row.Field) -Compress
            $unreadable[$key] = $true
        }
    }
    $eligible = {
        $key = ConvertTo-Json -InputObject @($_.Section,$_.Device,$_.Field) -Compress
        $_.Quality -eq 'Reported' -and -not $unreadable.ContainsKey($key)
    }
    $oldUsable = @($oldRows | Where-Object $eligible)
    $newUsable = @($newRows | Where-Object $eligible)
    $before = @(Get-ComparisonKeys $oldUsable | Sort-Object)
    $after = @(Get-ComparisonKeys $newUsable | Sort-Object)
    $changes = if ($before.Count -and $after.Count) { @(Compare-Object $before $after -CaseSensitive) }
        elseif ($before.Count) { @($before | ForEach-Object { [pscustomobject]@{InputObject=$_;SideIndicator='<='} }) }
        elseif ($after.Count) { @($after | ForEach-Object { [pscustomobject]@{InputObject=$_;SideIndicator='=>'} }) }
        else { @() }
    [pscustomobject]@{
        Changes=@($changes); PreviousCount=$before.Count; CurrentCount=$after.Count
        SkippedSections=@($skipped); SkippedFields=$unreadable.Count
    }
}
function Format-ComparisonKey($Key) {
    $parts = ConvertFrom-Json -InputObject $Key
    $deviceLabel = if ($parts[1]) { " ($($parts[1]))" } else { '' }
    return "[$($parts[0])] $(Get-FieldLabel $parts[2])${deviceLabel}: $($parts[3])"
}
function Read-SavedReport($Path) {
    $previous = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($previous -is [array] -or -not $previous.'Report info' -or $previous.'Report info'.Version -notmatch '^[23]\.\d+(\.\d+)?$') {
        throw 'This file is not a supported HWID v2 or v3 report.'
    }
    $knownSections = @($sectionGroups.Values | ForEach-Object { $_ })
    $found = 0
    foreach ($property in $previous.PSObject.Properties) {
        if ($property.Name -notin $knownSections) { continue }
        $found++
        foreach ($record in @($property.Value)) {
            if ($null -eq $record -or $record -isnot [pscustomobject]) { throw "Invalid data in section: $($property.Name)" }
        }
    }
    if (-not $found) { throw 'This report has no recognized hardware sections.' }
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
            (Get-PlainRecords $report['Report info'])
            foreach ($group in $sectionGroups.Keys) {
                "`n========== $group =========="
                foreach ($key in $sectionGroups[$group]) {
                    if ($report.Contains($key)) {
                        "--- $key ---"
                        Get-PlainRecords $report[$key]
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
    Show-MenuItem '1' 'Summary - start here' ''
    Show-MenuItem '2' 'Device IDs - quick table' ''
    Show-MenuItem '3' 'Hardware details by category' ''
    Show-MenuItem '4' 'What needs checking?' ''
    Show-MenuItem '5' 'Full report (all details)' ''
    Write-Host '  REPORTS' -ForegroundColor $palette.Muted
    Show-MenuItem '6' 'Save TXT + JSON' 'Save now to compare with a future scan.'
    Show-MenuItem '7' 'Compare with a saved JSON report' ''
    Show-MenuItem '8' 'Open reports folder' ''
    Write-Host '  HELP & EXIT' -ForegroundColor $palette.Muted
    Show-MenuItem '9' 'Help and color key' ''
    Show-MenuItem '0' 'Exit (or press Enter)' ''
    $choice = Read-Host 'Choose an option'
    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $choice = $choice.Trim()
    switch ($choice) {
        '2' {
            Show-QuickIds
            Read-Host 'Press Enter to return to the menu' | Out-Null
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
                $comparison = Compare-Inventories $previous $report
                Write-Host "Previous computer: $($previous.'Report info'.Computer); captured: $($previous.'Report info'.Generated)"
                if ($previous.'Report info'.Computer -ne $report['Report info'].Computer) { Write-Host 'These reports are from different computer names.' -ForegroundColor $palette.Warn }
                Write-Host 'Device slots and disk numbers are compared too; moving hardware can produce differences.' -ForegroundColor $palette.Muted
                Write-Host "Checked usable IDs: $($comparison.PreviousCount) previous / $($comparison.CurrentCount) current" -ForegroundColor $palette.Text
                if ($comparison.SkippedSections.Count) { Write-Host ('Not compared (not readable in both scans): ' + ($comparison.SkippedSections -join ', ')) -ForegroundColor $palette.Warn }
                if ($comparison.SkippedFields) { Write-Host "Not compared: $($comparison.SkippedFields) device fields with missing or default values." -ForegroundColor $palette.Warn }
                if (-not $comparison.PreviousCount -and -not $comparison.CurrentCount) { throw 'No usable IDs in the sections readable in both scans.' }
                $changes = @($comparison.Changes)
                $incomplete = $comparison.SkippedSections.Count -or $comparison.SkippedFields
                if (-not $changes.Count) {
                    if ($incomplete) { Write-Host 'No differences found in available data. Some IDs could not be checked.' -ForegroundColor $palette.Warn }
                    else { Write-Host 'No identifier differences found in the saved scan.' -ForegroundColor $palette.Good }
                }
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
