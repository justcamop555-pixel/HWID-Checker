@echo off
setlocal DisableDelayedExpansion
title Detailed HWID Checker
set "HWID_SCRIPT=%~f0"
set "HWID_CURRENT_WINDOW=%~1"
set "HWID_ENGINE="
set "HWID_OLD_ENGINE="
set "HWID_BLOCKED_ENGINE="
call :hwid_try_engine "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if defined HWID_BLOCKED_ENGINE goto hwid_runtime_blocked
if defined HWID_ENGINE goto hwid_run
call :hwid_try_engine "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined HWID_BLOCKED_ENGINE goto hwid_runtime_blocked
if defined HWID_ENGINE goto hwid_run
call :hwid_try_engine "%ProgramFiles%\PowerShell\7\pwsh.exe"
if defined HWID_BLOCKED_ENGINE goto hwid_runtime_blocked
if defined HWID_ENGINE goto hwid_run
for %%P in (pwsh.exe) do call :hwid_try_engine "%%~$PATH:P"
if defined HWID_BLOCKED_ENGINE goto hwid_runtime_blocked
if defined HWID_ENGINE goto hwid_run
for %%P in (powershell.exe) do call :hwid_try_engine "%%~$PATH:P"
if defined HWID_BLOCKED_ENGINE goto hwid_runtime_blocked
if defined HWID_ENGINE goto hwid_run
echo [COMPAT-01] No compatible PowerShell runtime could be started.
ver
if defined HWID_OLD_ENGINE echo Installed PowerShell is older than the required version 5.1.
echo Use Windows PowerShell 5.1 or PowerShell 7 compatible with your Windows version.
echo If installed, repair its executable or PATH. This checker does not install software.
echo PowerShell help: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
set "HWID_EXIT=10"
goto hwid_finish
:hwid_runtime_blocked
echo [COMPAT-02] PowerShell is restricted or Windows blocked runtime startup.
echo This checker needs FullLanguage for read-only hardware and console APIs.
echo Ask your administrator about approved execution. Security settings were not changed.
set "HWID_EXIT=13"
goto hwid_finish
:hwid_run
"%HWID_ENGINE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { $raw = [IO.File]::ReadAllText($env:HWID_SCRIPT); & ([scriptblock]::Create(($raw -split '(?m)^# POWERSHELL_START\r?$',2)[1])) } catch { Write-Host ('[START-01] Unable to start checker: ' + $_.Exception.Message); exit 1 }"
set "HWID_EXIT=%errorlevel%"
:hwid_finish
echo.
if not "%HWID_EXIT%"=="0" (
    echo The checker could not complete. See the message above.
    pause
)
exit /b %HWID_EXIT%
:hwid_try_engine
if defined HWID_ENGINE exit /b 0
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
"%~1" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) { exit 11 }; if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 13 }; if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { exit 12 }; exit 0" >nul 2>nul
if "%errorlevel%"=="0" set "HWID_ENGINE=%~1"
if "%errorlevel%"=="11" set "HWID_OLD_ENGINE=1"
if "%errorlevel%"=="13" set "HWID_BLOCKED_ENGINE=1"
if "%errorlevel%"=="5" set "HWID_BLOCKED_ENGINE=1"
if "%errorlevel%"=="1260" set "HWID_BLOCKED_ENGINE=1"
exit /b 0
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
function Get-RuntimeCompatibility($Version,$Platform,$LanguageMode) {
    if([string]$Platform -ne 'Win32NT'){return [pscustomobject]@{Supported=$false;Message='This checker requires Windows; other operating systems do not expose its hardware providers.'}}
    if([version](([string]$Version -split '-')[0]) -lt [version]'5.1'){return [pscustomobject]@{Supported=$false;Message='Use Windows PowerShell 5.1 or PowerShell 7. Older engines cannot parse all checker features.'}}
    if([string]$LanguageMode -ne 'FullLanguage'){return [pscustomobject]@{Supported=$false;Message='FullLanguage is required for read-only hardware and console APIs. Ask your administrator about approved execution; policy was not changed.'}}
    return [pscustomobject]@{Supported=$true;Message='Runtime supported'}
}
function Get-QueryBackend {
    if(Get-Command Get-CimInstance -ErrorAction SilentlyContinue){return 'CIM'}
    if(Get-Command Get-WmiObject -ErrorAction SilentlyContinue){return 'Legacy WMI'}
    return 'Unavailable'
}
function Test-ProjectionReadFailure($Failure) {
    $exception=$Failure.Exception;$projection=$false
    for($depth=0;$null -ne $exception -and $depth -lt 16;$depth++) {
        $code=$exception.HResult.ToString('X8')
        $status=if($exception.PSObject.Properties['StatusCode']){[string]$exception.StatusCode}elseif($exception.PSObject.Properties['ErrorCode']){[string]$exception.ErrorCode}else{''}
        if($exception -is [UnauthorizedAccessException] -or $exception -is [TimeoutException] -or $code -in @('80070005','80041003','800705B4') -or $status -in @('AccessDenied','Timeout')){return $false}
        if($code -in @('80041017','80041031') -or $status -in @('InvalidQuery','InvalidProperty','NoSuchProperty')){$projection=$true}
        $exception=$exception.InnerException
    }
    if($Failure.CategoryInfo.Category -in @('PermissionDenied','OperationTimeout')){return $false}
    $text=[string]$Failure
    if($text -match '(?i)access\s+(is\s+)?denied|unauthori[sz]ed|permission denied|timed out|timeout|0x80070005|0x80041003|0x800705b4'){return $false}
    return $projection -or ($text -match '(?i)invalid query|invalid property|no such property|0x80041017|0x80041031')
}
function Get-HwidInstance {
    param([Parameter(Position=0)][string]$ClassName,[string]$Namespace='root/cimv2',[string]$Filter,[string[]]$Property,[int]$OperationTimeoutSec=20)
    $cim=Get-Command Get-CimInstance -ErrorAction SilentlyContinue
    if($null -ne $cim) {
        $arguments=@{ClassName=$ClassName;Namespace=$Namespace;OperationTimeoutSec=$OperationTimeoutSec;ErrorAction='Stop'}
        if($Filter){$arguments.Filter=$Filter}
        if($Property){$arguments.Property=$Property}
        $reader=$cim
    }
    else {
        $wmi=Get-Command Get-WmiObject -ErrorAction SilentlyContinue
        if($null -eq $wmi){throw 'No CIM or legacy WMI reader is available. Repair/install the approved Windows PowerShell/CimCmdlets component.'}
        $arguments=@{Class=$ClassName;Namespace=$Namespace;ErrorAction='Stop'}
        if($Filter){$arguments.Filter=$Filter}
        if($Property){$arguments.Property=$Property}
        $reader=$wmi
    }
    try {$records=@(& $reader @arguments)}
    catch {
        if(-not $Property -or -not (Test-ProjectionReadFailure $_)){throw}
        $primary=$_.Exception.Message
        # Keep the same reader, namespace, filter and timeout; only relax the requested fields once.
        $arguments.Remove('Property')
        try {$records=@(& $reader @arguments)}
        catch {
            $exception=[Exception]::new(('Requested fields failed: '+$primary+' / Compatible read failed: '+$_.Exception.Message),$_.Exception)
            $exception.Data['HwidFallbackFailure']=$_.Exception.Message
            throw [System.Management.Automation.ErrorRecord]::new($exception,'Hwid.ProjectionRetryFailed',$_.CategoryInfo.Category,$_.TargetObject)
        }
        if($null -ne $script:hwidQueryRecoveries){$script:hwidQueryRecoveries.Add([pscustomobject]@{Class=$ClassName;Namespace=$Namespace;Method='Read available properties';PrimaryFailure=$primary})}
    }
    return $records
}
function Get-CompatibilityInfo {
    $missing=@(foreach($name in @('Get-NetAdapter','Get-PnpDevice','Get-PnpDeviceProperty','Get-WmiObject','Add-Type','Start-Process','ConvertTo-Json','ConvertFrom-Json')) {
        if(-not (Get-Command $name -ErrorAction SilentlyContinue)){$name}
    })
    [pscustomobject][ordered]@{
        PowerShellVersion=$PSVersionTable.PSVersion.ToString()
        WindowsVersion=[Environment]::OSVersion.Version.ToString()
        LanguageMode=[string]$ExecutionContext.SessionState.LanguageMode
        QueryBackend=Get-QueryBackend
        MissingCommands=$missing
        Note='Providers depend on Windows version, drivers and access. Missing sections remain unavailable, not zero or changed IDs.'
    }
}
function Test-DedicatedConsoleSupport($WindowsVersion) {
    $version=[version]$WindowsVersion
    return $version.Major -ge 10 -and $version.Build -ge 19041
}
function Get-ReadableLaunchPlan($PowerShellPath) {
    # Environment carries the path literally, including spaces, !, &, and Unicode.
    $loader = @'
$env:HWID_OWN_CONSOLE = '1'
$env:WT_SESSION = $null
$env:WT_PROFILE_ID = $null
try {
    if($PSVersionTable.PSVersion -lt [version]'5.1'){throw 'PowerShell 5.1 or 7 is required.'}
    if($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){throw 'PowerShell language mode is restricted. Ask your administrator about approved execution.'}
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
        if(-not (Test-DedicatedConsoleSupport ([Environment]::OSVersion.Version))){return $false}
        $engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $plan = Get-ReadableLaunchPlan $engine
        if (-not (Test-Path -LiteralPath $plan.FilePath -PathType Leaf)) { return $false }
        $child = Start-Process -FilePath $plan.FilePath -ArgumentList $plan.Arguments -WorkingDirectory (Split-Path -Parent $ScriptPath) -PassThru
        # If this host cannot start, continue in the current window instead of looping.
        if ($child.WaitForExit(700) -and $child.ExitCode -ne 0) { return $false }
        return $true
    } catch { return $false }
}
function Initialize-ReadableConsole($Owned, $Redirected) {
    $result = [ordered]@{ Mode='Current window'; FontApplied=$false; FontName=''; FontHeight=0; FontWeight=0; Columns=0; Rows=0; BufferRows=0; QuickEditDisabled=$false; MouseInputDisabled=$false; ContextMenuDisabled=$false; InputModeBefore=0; InputModeAfter=0; ThemeApplied=$false; BackgroundRGB=0 }
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
    [DllImport("user32.dll")] static extern IntPtr GetSystemMenu(IntPtr window, bool revert);
    [DllImport("user32.dll")] static extern IntPtr GetSubMenu(IntPtr menu, int position);
    [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr menu);
    [DllImport("user32.dll")] static extern uint GetMenuState(IntPtr menu, uint item, uint flags);
    [DllImport("user32.dll")] static extern bool RemoveMenu(IntPtr menu, uint item, uint flags);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    public static bool EnterIsDown() { return (GetAsyncKeyState(13) & 0x8000) != 0; }
    static IntPtr editMenu=IntPtr.Zero;
    static IntPtr FindEditMenu() {
        if(editMenu!=IntPtr.Zero) return editMenu;
        var system=GetSystemMenu(GetConsoleWindow(),false);
        for(int i=0;i<GetMenuItemCount(system);i++) {
            var sub=GetSubMenu(system,i);
            // Console Edit popup: Mark and Copy command IDs. No localized text matching.
            if(sub!=IntPtr.Zero && GetMenuState(sub,0xFFF2,0)!=0xFFFFFFFFu && GetMenuState(sub,0xFFF0,0)!=0xFFFFFFFFu) {
                editMenu=sub; return sub;
            }
        }
        return IntPtr.Zero;
    }
    public static bool DisableEditPopup() {
        if(!IsWindowVisible(GetConsoleWindow())) return false;
        var menu=FindEditMenu();
        if(menu==IntPtr.Zero) return false;
        while(GetMenuItemCount(menu)>0) { if(!RemoveMenu(menu,0,0x400)) return false; }
        return GetMenuItemCount(menu)==0;
    }
    public static int ReadEditPopupItems() { var menu=FindEditMenu(); return menu==IntPtr.Zero ? -1 : GetMenuItemCount(menu); }
    public static bool HasWindowCloseCommand() { return GetMenuState(GetSystemMenu(GetConsoleWindow(),false),0xF060,0)!=0xFFFFFFFFu; }

    [StructLayout(LayoutKind.Sequential)] public struct Rect { public short Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Explicit)] public struct ScreenCell {
        [FieldOffset(0)] public ushort Character;
        [FieldOffset(2)] public ushort Attributes;
    }
    public sealed class ScreenPatch {
        public int Left, Top, Width, Height;
        public ScreenCell[] Cells;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern bool ReadConsoleOutputW(IntPtr output, [Out] ScreenCell[] data, Coord size, Coord origin, ref Rect region);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern bool WriteConsoleOutputW(IntPtr output, ScreenCell[] data, Coord size, Coord origin, ref Rect region);
    public static ScreenPatch CaptureRegion(int left, int top, int width, int height) {
        if(left<0 || top<0 || width<1 || height<1 || width>32767 || height>32767) return null;
        var patch=new ScreenPatch { Left=left, Top=top, Width=width, Height=height, Cells=new ScreenCell[width*height] };
        var rect=new Rect { Left=(short)left, Top=(short)top, Right=(short)(left+width-1), Bottom=(short)(top+height-1) };
        var size=new Coord { X=(short)width, Y=(short)height };
        if(!ReadConsoleOutputW(GetStdHandle(-11),patch.Cells,size,new Coord(),ref rect)) return null;
        if(rect.Left!=left || rect.Top!=top || rect.Right!=left+width-1 || rect.Bottom!=top+height-1) return null;
        return patch;
    }
    public static bool RestoreRegion(ScreenPatch patch) {
        if(patch==null) return false;
        var rect=new Rect { Left=(short)patch.Left, Top=(short)patch.Top, Right=(short)(patch.Left+patch.Width-1), Bottom=(short)(patch.Top+patch.Height-1) };
        return WriteConsoleOutputW(GetStdHandle(-11),patch.Cells,new Coord { X=(short)patch.Width, Y=(short)patch.Height },new Coord(),ref rect);
    }
    public static bool PaintRegion(ScreenPatch patch, string[] lines, ushort[] attributes) {
        if(patch==null || lines.Length!=patch.Height || attributes.Length!=patch.Height) return false;
        var cells=new ScreenCell[patch.Width*patch.Height];
        for(int y=0;y<patch.Height;y++) {
            string line=lines[y] ?? "";
            for(int x=0;x<patch.Width;x++) {
                cells[y*patch.Width+x].Character=(ushort)(x<line.Length ? line[x] : ' ');
                cells[y*patch.Width+x].Attributes=attributes[y];
            }
        }
        var rect=new Rect { Left=(short)patch.Left, Top=(short)patch.Top, Right=(short)(patch.Left+patch.Width-1), Bottom=(short)(patch.Top+patch.Height-1) };
        return WriteConsoleOutputW(GetStdHandle(-11),cells,new Coord { X=(short)patch.Width, Y=(short)patch.Height },new Coord(),ref rect);
    }
    [StructLayout(LayoutKind.Sequential)] public struct BufferInfo {
        public uint Size; public Coord BufferSize; public Coord Cursor; public ushort Attributes;
        public Rect Window; public Coord MaximumWindow; public ushort PopupAttributes;
        [MarshalAs(UnmanagedType.Bool)] public bool Fullscreen;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=16)] public uint[] Colors;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetConsoleScreenBufferInfoEx(IntPtr output, ref BufferInfo info);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetConsoleScreenBufferInfoEx(IntPtr output, ref BufferInfo info);
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
    public static bool UseHostScrolling() {
        uint mode; var input=GetStdHandle(-10);
        return GetConsoleMode(input,out mode) && SetConsoleMode(input,mode & ~0x0010u);
    }
    static uint Rgb(uint r, uint g, uint b) { return r | (g << 8) | (b << 16); }
    static BufferInfo ReadBuffer() {
        var info = new BufferInfo(); info.Size=(uint)Marshal.SizeOf(typeof(BufferInfo)); info.Colors=new uint[16];
        GetConsoleScreenBufferInfoEx(GetStdHandle(-11), ref info); return info;
    }
    public static uint ReadBackground() { return ReadBuffer().Colors[0]; }
    public static bool ApplyTheme() {
        var info=ReadBuffer();
        info.Colors[0]=Rgb(12,18,32);     // Deep navy background
        info.Colors[1]=Rgb(19,32,53);     // Panel navy
        info.Colors[7]=Rgb(144,164,190);  // Secondary labels
        info.Colors[8]=Rgb(68,95,127);    // Borders
        info.Colors[10]=Rgb(100,235,175); // Success mint
        info.Colors[11]=Rgb(80,220,245);  // Navigation cyan
        info.Colors[12]=Rgb(255,112,133); // Errors
        info.Colors[14]=Rgb(255,209,112); // Warnings
        info.Colors[15]=Rgb(230,241,255); // Main text
        info.Window.Right++; info.Window.Bottom++;
        return SetConsoleScreenBufferInfoEx(GetStdHandle(-11), ref info);
    }
}
'@
        }
        # Quick Edit mouse selection suspends console output. Disable it for this owned window only.
        $before=[uint32]0; $after=[uint32]0
        $result.QuickEditDisabled=[HwidConsoleDisplay]::DisableQuickEdit([ref]$before,[ref]$after)
        $result.MouseInputDisabled=[HwidConsoleDisplay]::UseHostScrolling()
        $result.ContextMenuDisabled=[HwidConsoleDisplay]::DisableEditPopup()
        $result.InputModeBefore=$before; $result.InputModeAfter=[HwidConsoleDisplay]::ReadInputMode()
        $result.ThemeApplied=[HwidConsoleDisplay]::ApplyTheme()
        $result.BackgroundRGB=[HwidConsoleDisplay]::ReadBackground()
        [Console]::BackgroundColor=[ConsoleColor]::Black
        [Console]::ForegroundColor=[ConsoleColor]::White
        $result.FontApplied = [HwidConsoleDisplay]::ApplyFont()
        $font = [HwidConsoleDisplay]::ReadFont()
        $result.FontName=$font.Face; $result.FontHeight=$font.Cell.Y; $result.FontWeight=$font.Weight
        [Console]::Title = 'HWID // System Console'
        # Resize only the dedicated window. Respect the screen's maximum character dimensions.
        $width=[math]::Min(100,[Console]::LargestWindowWidth)
        $height=[math]::Min(34,[Console]::LargestWindowHeight)
        if ($width -gt 0 -and $height -gt 0) {
            [Console]::SetBufferSize([math]::Max($width,[Console]::BufferWidth),[math]::Max($height,[Console]::BufferHeight))
            [Console]::SetWindowPosition(0,0)
            [Console]::SetWindowSize($width,$height)
            [Console]::Clear()
            [Console]::SetBufferSize($width,$height)
        }
        $result.Columns=[Console]::WindowWidth; $result.Rows=[Console]::WindowHeight
        $result.BufferRows=[Console]::BufferHeight
        [Console]::Clear()
    } catch { $result.Mode='Classic console (default display)' }
    return [pscustomobject]$result
}
$runtime=Get-RuntimeCompatibility $PSVersionTable.PSVersion ([Environment]::OSVersion.Platform) $ExecutionContext.SessionState.LanguageMode
if(-not $runtime.Supported){Write-Host ('[COMPAT-04] '+$runtime.Message);return}
$redirected = [Console]::IsInputRedirected -or [Console]::IsOutputRedirected
$ownedConsole = $env:HWID_OWN_CONSOLE -eq '1'
if (Start-ReadableConsole $env:HWID_SCRIPT $redirected $ownedConsole $env:HWID_CURRENT_WINDOW) { return }
$display = Initialize-ReadableConsole $ownedConsole $redirected
$script:report = [ordered]@{}
$script:warnings = New-Object 'System.Collections.Generic.List[string]'
$palette = @{ Heading='Cyan'; Text='White'; Muted='Gray'; Border='DarkGray'; Good='Green'; Warn='Yellow'; Error='Red'; Added='Cyan' }
try {
    if ([Console]::BackgroundColor -in @('White','Gray','Yellow','Cyan','Green','Magenta')) {
        $palette = @{ Heading='DarkCyan'; Text='Black'; Muted='DarkGray'; Border='DarkGray'; Good='DarkGreen'; Warn='DarkYellow'; Error='DarkRed'; Added='DarkCyan' }
    }
} catch { }
$script:scanStep = 0
$script:scanTotal = 17
$script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
$sectionGroups = [ordered]@{
    'SYSTEM & FIRMWARE' = @('System identity','System hardware','Motherboard','BIOS','Chassis')
    'CPU & MEMORY' = @('CPU','Memory modules')
    'STORAGE' = @('Physical disks','Storage identifiers','Volumes','Disk partitions')
    'GRAPHICS & NETWORK' = @('Graphics adapters','Network adapters','Monitors')
    'WINDOWS' = @('Windows','Windows Machine GUID')
}
function Write-Heading($Title) {
    $width = 72
    try { if ([Console]::WindowWidth -gt 0) { $width = [math]::Min(88, [math]::Max(8, [Console]::WindowWidth - 2)) } } catch { }
    Write-Host ''
    $inner=$width-4
    $text=Limit-TableText $Title $inner
    Write-Host ('  +' + ('-' * ($width-4)) + '+') -ForegroundColor $palette.Border
    Write-Host ('  |' + $text.PadRight($inner) + '|') -ForegroundColor $palette.Heading
    Write-Host ('  +' + ('-' * ($width-4)) + '+') -ForegroundColor $palette.Border
}
function Get-UiTransitionFrame($Direction,$Step,$Width,$Destination) {
    $cells=[math]::Max(4,[math]::Min(32,[math]::Floor(($Width-8)*0.45)))
    $step=[math]::Max(0,[math]::Min(17,[int]$Step))
    $bar=('-'*$cells).ToCharArray()
    $time=$step/17.0
    $progress=$time*$time*(3-2*$time)
    if($Direction -eq 'Exit') {
        $bar=(' '*$cells).ToCharArray()
        $label=if($step -eq 17){'EXIT / Goodbye'}else{'EXIT / Closing console'}
        $edge=[int][math]::Ceiling(($cells/2.0)*$progress)
        for($i=$edge;$i -lt $cells-$edge;$i++){$bar[$i]='='}
        if($edge -gt 0 -and $edge -lt $cells-$edge){$bar[$edge]='>';$bar[$cells-$edge-1]='<'}
    } else {
        $label=if($Direction -eq 'Back'){'BACK / '+$(if($Destination){$Destination}else{'Main menu'})}elseif($Destination){'NEXT / '+$Destination}else{'NEXT / Opening page'}
        $position=[int][math]::Round(($cells-2)*$progress)
        if($Direction -eq 'Back'){$position=$cells-2-$position}
        $arrow=if($Direction -eq 'Back'){'<'}else{'>'}
        $bar[$position]=$arrow; $bar[$position+1]=$arrow
        for($trail=1;$trail -le 4;$trail++) {
            $tail=if($Direction -eq 'Back'){$position+1+$trail}else{$position-$trail}
            if($tail -ge 0 -and $tail -lt $cells){$bar[$tail]=if($trail -le 2){'='}else{'.'}}
        }
    }
    $label=$label -replace '[\x00-\x1F\x7F]',' '
    if($Width -lt 28){return (Limit-TableText ('  '+$label) ([math]::Max(0,$Width)))}
    return (Limit-TableText ('  ['+(-join $bar)+']  '+$label) ([math]::Max(0,$Width)))
}
function Get-UiTransitionLines($Direction,$Step,[int]$Width,$Destination) {
    $width=[math]::Max(0,$Width);$step=[math]::Max(0,[math]::Min(17,[int]$Step))
    $inner=[math]::Max(0,$width-4);$bar=('-'*$inner).ToCharArray()
    $time=$step/17.0;$progress=$time*$time*(3-2*$time)
    if($Direction -eq 'Exit'){
        $edge=[int][math]::Ceiling($inner*$progress/2)
        for($i=0;$i -lt $inner;$i++){$bar[$i]=if($i -lt $edge -or $i -ge $inner-$edge){' '}else{'='}}
    }else{
        $filled=[int][math]::Floor($inner*$progress)
        for($i=0;$i -lt $filled;$i++){$index=if($Direction -eq 'Back'){$inner-1-$i}else{$i};$bar[$index]='='}
        if($filled -lt $inner){$index=if($Direction -eq 'Back'){$inner-1-$filled}else{$filled};$bar[$index]=if($Direction -eq 'Back'){'<'}else{'>'}}
    }
    $border=Limit-TableText ('  +'+(-join $bar)+'+') $width
    @($border,(Get-UiTransitionFrame $Direction $step $width $Destination),$border)
}
function Get-UiTransitionDuration($Direction) {
    switch($Direction){'Back'{return 160};'Exit'{return 260};default{return 200}}
}
function Show-UiTransition([ValidateSet('Back','Next','Exit')]$Direction,$Destination,[scriptblock]$PendingInput) {
    if(-not $ownedConsole -or $redirected -or $env:HWID_NO_ANIMATION -eq '1'){return}
    $saved=$false
    $patch=$null
    try {
        if([Console]::IsOutputRedirected -or [Console]::IsInputRedirected){return}
        if(-not $PendingInput){$PendingInput={[Console]::KeyAvailable}}
        if(& $PendingInput){return}
        $viewTop=[Console]::WindowTop; $viewLeft=[Console]::WindowLeft
        $width=[Console]::WindowWidth; $height=[Console]::WindowHeight
        if($width -lt 16 -or $height -lt 5){return}
        $patch=[HwidConsoleDisplay]::CaptureRegion($viewLeft,($viewTop+$height-4),($width-1),3)
        if($null -eq $patch){return}
        $visible=[Console]::CursorVisible; $saved=$true
        [Console]::CursorVisible=$false
        $duration=Get-UiTransitionDuration $Direction
        $background=16*[int][Console]::BackgroundColor
        $border=[uint16]($background+[int][ConsoleColor]$palette.Border)
        $heading=[uint16]($background+[int][ConsoleColor]$palette.Heading)
        $clock=[Diagnostics.Stopwatch]::StartNew()
        for($frame=0;$frame -le 17;$frame++) {
            if([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height -or [Console]::WindowTop -ne $viewTop -or [Console]::WindowLeft -ne $viewLeft){break}
            if(& $PendingInput){break}
            $step=[math]::Max($frame,[math]::Min(17,[int][math]::Floor(17*$clock.Elapsed.TotalMilliseconds/$duration)))
            $lines=[string[]]@(Get-UiTransitionLines $Direction $step ($width-1) $Destination)
            if(-not [HwidConsoleDisplay]::PaintRegion($patch,$lines,[uint16[]]@($border,$heading,$border))){break}
            if($step -eq 17){break}
            $frame=$step
            $delay=[int][math]::Ceiling((($step+1)*$duration/17.0)-$clock.Elapsed.TotalMilliseconds)
            if($delay -gt 0){Start-Sleep -Milliseconds $delay}
        }
    } catch {
        # Resize and unavailable console APIs must not prevent navigation.
    } finally {
        if($saved) {
            try {[void][HwidConsoleDisplay]::RestoreRegion($patch)}catch{}
            try {[Console]::CursorVisible=$visible}catch{}
        }
    }
}
function Reset-UiPage {
    $script:reportBookmarks=[ordered]@{}
    if ($ownedConsole -and -not $redirected) {
        try {
            [Console]::Clear()
            [Console]::SetWindowPosition(0,0)
            [Console]::SetBufferSize([Console]::WindowWidth,[Console]::WindowHeight)
        } catch { }
    }
}
function Start-UiReport {
    if($ownedConsole -and -not $redirected) {
        try {[Console]::SetBufferSize([Console]::WindowWidth,[math]::Max([Console]::BufferHeight,[math]::Max(4096,[Console]::WindowHeight)))}catch{}
    }
}
function Get-ReportHistoryRows($WindowRows,$LastRow) { return [math]::Max($WindowRows,$LastRow+3) }
function Complete-UiReport {
    if($ownedConsole -and -not $redirected) {
        try {
            $rows=Get-ReportHistoryRows ([Console]::WindowHeight) ([Console]::CursorTop)
            [Console]::SetWindowPosition(0,[math]::Min([Console]::WindowTop,[math]::Max(0,$rows-[Console]::WindowHeight)))
            [Console]::SetBufferSize([Console]::WindowWidth,$rows)
        }catch{}
    }
}
function Get-ReportScrollTop($Key,$Current,$WindowRows,$BufferRows) {
    $step=[math]::Max(1,$WindowRows-1)
    $target=switch($Key) {
        'UpArrow' {$Current-1}; 'DownArrow' {$Current+1}
        'PageUp' {$Current-$step}; 'PageDown' {$Current+$step}
        'Home' {0}; 'End' {$BufferRows-$WindowRows}; default {$Current}
    }
    return [math]::Max(0,[math]::Min($target,[math]::Max(0,$BufferRows-$WindowRows)))
}
function Move-UiReportView($Key) {
    try {
        $top=Get-ReportScrollTop $Key ([Console]::WindowTop) ([Console]::WindowHeight) ([Console]::BufferHeight)
        [Console]::SetWindowPosition(0,$top)
    }catch{}
}
function Add-ReportBookmark($Key) {
    if($ownedConsole -and -not $redirected) {
        try {$script:reportBookmarks[[string]$Key]=[Console]::CursorTop}catch{}
    }
}
function Move-ReportBookmark($Key) {
    if($null -ne $script:reportBookmarks -and $script:reportBookmarks.Contains([string]$Key)) {
        try {
            $top=[math]::Max(0,[math]::Min($script:reportBookmarks[[string]$Key],[Console]::BufferHeight-[Console]::WindowHeight))
            [Console]::SetWindowPosition(0,$top)
        }catch{}
    }
}
function Wait-UiPage([scriptblock]$KeyReader,[string]$ContinueTo) {
    if ($ownedConsole -and -not $redirected) {
        Start-UiReport
        if($ContinueTo) {
            Write-PnpValue 'Continue' ('Press Enter for '+$ContinueTo+'. Release Enter first if held during scanning.') $palette.Heading
            Write-PnpValue 'Scroll' 'Mouse wheel / Up Down / PgUp PgDn / Home End.' $palette.Muted
        }else {Write-Host '  Scroll: mouse wheel / Up Down / PgUp PgDn / Home End. Enter = menu.' -ForegroundColor $palette.Muted}
        Complete-UiReport
        $bookmarked=$null -ne $script:reportBookmarks -and $script:reportBookmarks.Count -gt 0
        if($bookmarked -and -not $ContinueTo){Move-UiReportView 'Home'}
        if($ContinueTo -and -not $KeyReader){Clear-ScanTypeAhead}
        while($true) {
            $key=if($KeyReader){& $KeyReader}else{[Console]::ReadKey($true)}
            if($null -eq $key){return}
            if($key.Key -eq [ConsoleKey]::Enter){return}
            if($bookmarked -and -not $ContinueTo) {
                if($key.KeyChar -eq '0'){return}
                Move-ReportBookmark ([string]$key.KeyChar)
            }
            Move-UiReportView ($key.Key.ToString())
        }
    } elseif(-not $redirected) {
        $prompt=if($ContinueTo){'Scan finished. Press Enter to continue to '+$ContinueTo}else{'Press Enter to return to the menu'}
        Read-CheckerLine $prompt | Out-Null
    }
}
function Clear-ScanTypeAhead([scriptblock]$HeldReader,[scriptblock]$AvailableReader,[scriptblock]$DrainReader) {
    try {
        # Wait without repainting while Enter is held, then discard scan-time keys.
        while($(if($HeldReader){& $HeldReader}else{[HwidConsoleDisplay]::EnterIsDown()})){Start-Sleep -Milliseconds 40}
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while($clock.ElapsedMilliseconds -lt 250 -and $(if($AvailableReader){& $AvailableReader}else{[Console]::KeyAvailable})) {
            if($DrainReader){& $DrainReader | Out-Null}else{[void][Console]::ReadKey($true)}
        }
    }catch{}
}
function Wait-ScanContinue([string]$Destination='main menu',[scriptblock]$KeyReader) {
    # Keep scan collection usable by diagnostics and redirected launchers.
    if($redirected){return}
    Wait-UiPage -ContinueTo $Destination -KeyReader $KeyReader
}
function Read-CheckerLine($Prompt) {
    if ([Console]::IsInputRedirected) {
        Write-Host ($Prompt + ': ') -ForegroundColor $palette.Heading -NoNewline
        return [Console]::ReadLine()
    }
    return (Read-Host $Prompt)
}
function Get-MenuInputLayout($Width,$Height,$WindowTop,$RequestedRow) {
    if ($Width -lt 8 -or $Height -lt 2) { return [pscustomobject]@{Enabled=$false} }
    $top=[math]::Max($WindowTop,[math]::Min($RequestedRow,$WindowTop+$Height-2))
    [pscustomobject]@{Enabled=$true; Width=$Width-1; Top=$top; PromptRow=$top+1}
}
function Get-MenuInputLines($Width,$Buffer,$Message,$Maximum=9) {
    $prefix=if($Width -ge 24){"  Select [0-$Maximum]: "}else{"[0-$Maximum]> "}
    # Display ASCII cells only; Unicode lookalikes still fail validation without shifting columns.
    $visible=([string]$Buffer -replace '[^\x20-\x7E]','?')
    $room=[math]::Max(0,$Width-$prefix.Length-1)
    if($visible.Length -gt $room){$visible=$visible.Substring($visible.Length-$room)}
    $prompt=Limit-TableText ($prefix+$visible) $Width
    [pscustomobject]@{
        Status=(Limit-TableText $Message $Width).PadRight($Width)
        Prompt=$prompt.PadRight($Width)
        Cursor=[math]::Min($Width-1,$prompt.Length)
    }
}
function New-MenuInputArea {
    if (-not $ownedConsole -or $redirected -or [Console]::IsOutputRedirected) { return $null }
    try { return [pscustomobject]@{Enabled=$true; Top=[Console]::CursorTop; Error=''; Geometry=''; LastStatus=$null; LastPrompt=$null; Maximum=9} } catch { return $null }
}
function Write-MenuInputArea($Area,$Buffer) {
    if ($null -eq $Area -or -not $Area.Enabled) { return $false }
    # Resize can occur between reading dimensions and positioning the cursor. Retry once.
    for($attempt=0;$attempt -lt 2;$attempt++) {
        try {
            $left=[Console]::WindowLeft
            $width=[math]::Min([Console]::WindowWidth,[Console]::BufferWidth-$left)
            $height=[math]::Min([Console]::WindowHeight,[Console]::BufferHeight-[Console]::WindowTop)
            $layout=Get-MenuInputLayout $width $height ([Console]::WindowTop) $Area.Top
            if(-not $layout.Enabled){break}
            $lines=Get-MenuInputLines $layout.Width $Buffer $Area.Error $Area.Maximum
            $Area.Top=$layout.Top
            $geometry="$left/$($layout.Top)/$($layout.Width)"
            if($Area.Geometry -cne $geometry -or $Area.LastStatus -cne $lines.Status) {
                [Console]::SetCursorPosition($left,$layout.Top)
                Write-Host $lines.Status -ForegroundColor $palette.Error -NoNewline
                $Area.LastStatus=$lines.Status
            }
            if($Area.Geometry -cne $geometry -or $Area.LastPrompt -cne $lines.Prompt) {
                [Console]::SetCursorPosition($left,$layout.PromptRow)
                Write-Host $lines.Prompt -ForegroundColor $palette.Text -NoNewline
                $Area.LastPrompt=$lines.Prompt
            }
            $Area.Geometry=$geometry
            [Console]::SetCursorPosition(($left+$lines.Cursor),$layout.PromptRow)
            return $true
        } catch { }
    }
    $Area.Enabled=$false
    return $false
}
function Show-MenuInputError($Area,$Maximum=9) {
    $message=if($Maximum -eq 9){'  [INPUT-01] Invalid option. Type one digit: 0-9.'}else{"  [INPUT-02] Choose 0-$Maximum. [0] Back."}
    if($null -ne $Area -and $Area.Enabled) {
        $Area.Error=$message
        if(Write-MenuInputArea $Area ''){return}
    }
    Write-Host $message -ForegroundColor $palette.Error
}
function Read-MenuKeyboard([scriptblock]$KeyReader,$Area,$Maximum=9) {
    $fixed=Write-MenuInputArea $Area ''
    if(-not $fixed){Write-Host "  Select [0-$Maximum]: " -ForegroundColor $palette.Text -NoNewline}
    $buffer=''
    $overflow=$false
    while ($true) {
        # This blocks while idle; empty Enter repeats never print or repaint anything.
        $key=if($KeyReader){& $KeyReader}else{[Console]::ReadKey($true)}
        if ($null -eq $key) { return $null }
        if ($key.Key -eq [ConsoleKey]::Enter) {
            if ([string]::IsNullOrWhiteSpace($buffer)) { continue }
            if(-not $fixed){Write-Host ''}
            if($overflow){return '[input too long]'}
            return $buffer
        }
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            $overflow=$false
            if($buffer.Length){
                $buffer=$buffer.Substring(0,$buffer.Length-1)
                if($fixed){$fixed=Write-MenuInputArea $Area $buffer}else{Write-Host "`b `b" -NoNewline}
            }
            continue
        }
        if ($buffer.Length -eq 0 -and [char]::IsWhiteSpace($key.KeyChar)) { continue }
        if (-not [char]::IsControl($key.KeyChar)) {
            if ($buffer.Length -ge 32) { $overflow=$true; continue }
            $buffer += $key.KeyChar
            if($fixed){
                if($buffer -cmatch '\A[0-9]\z' -and [int]$buffer -le $Maximum){$Area.Error=''}
                $fixed=Write-MenuInputArea $Area $buffer
            } else {Write-Host ([string]$key.KeyChar) -ForegroundColor $palette.Text -NoNewline}
        }
    }
}
function Read-MenuChoice([scriptblock]$Reader,[ValidateRange(0,9)][int]$Maximum=9) {
    $errorShown=$false
    $area=New-MenuInputArea
    if($null -ne $area){$area.Maximum=$Maximum}
    while ($true) {
        if ($Reader) { $value = & $Reader $area }
        elseif ([Console]::IsInputRedirected) { $value = Read-CheckerLine "  Select [0-$Maximum]" }
        else { $value = Read-MenuKeyboard -Area $area -Maximum $Maximum }
        # EOF is not an invalid key. Exit cleanly when a redirected input stream closes.
        if ($null -eq $value) { return $null }
        $text = ([string]$value).Trim()
        if (-not $text.Length) { continue }
        if ($text -cmatch '\A[0-9]\z' -and [int]$text -le $Maximum) { return $text }
        if (($null -ne $area -and $area.Enabled) -or -not $errorShown) { Show-MenuInputError $area $Maximum; $errorShown=$true }
    }
}
function Get-MenuDestination($Key) {
    foreach($entry in (Get-MenuEntries)) {
        if($entry[0] -eq $Key){return $entry[1]}
        if($entry[2] -eq $Key){return $entry[3]}
    }
    return 'Opening page'
}
function Get-MenuEntries {
    @('1','Scan summary - start here','6','Save snapshot (TXT + JSON)'), @('2','ID numbers / serials','7','Compare old and current IDs'),
    @('3','Browse hardware / devices','8','Saved reports / storage'), @('4','Check warnings / conflicts','9','Rescan / extended devices / help'),
    @('5','Full inventory report','0','Exit')
}
function Show-CompactDeck($Width) {
    $size=[math]::Max(8,$Width-1)
    Write-Host (Limit-TableText '  HWID / MAIN MENU' $size) -ForegroundColor $palette.Heading
    $found=@($identifiers | Where-Object Quality -eq 'Reported').Count
    $review=(Get-ReviewSummary $report $identifiers $warnings).Total
    Write-Host (Limit-TableText ("  Found: $found / Review: $review") $size) -ForegroundColor $palette.Text
    Write-Host ''
    foreach($entry in @(@('1','Summary'),@('2','ID numbers'),@('3','Browse devices'),@('4','Check warnings'),@('5','Full inventory'),@('6','Save reports'),@('7','Compare IDs'),@('8','Saved reports'),@('9','Rescan / help'),@('0','Exit'))) {
        Write-Host (Limit-TableText ('  ['+$entry[0]+'] '+$entry[1]) $size) -ForegroundColor $palette.Heading
    }
    Write-Host (Limit-TableText '  Type 0-9 + Enter.' $size) -ForegroundColor $palette.Muted
    Write-Host (Limit-TableText '  Empty Enter is ignored.' $size) -ForegroundColor $palette.Muted
}
function Show-ControlDeck {
    Reset-UiPage
    try {
        if([Console]::WindowWidth -gt 0 -and ([Console]::WindowWidth -lt 80 -or [Console]::WindowHeight -lt 32)) {
            Show-CompactDeck ([Console]::WindowWidth)
            return
        }
    } catch {}
    Write-Heading 'MAIN MENU / HWID CHECKER'
    Write-Host '  HWID CHECKER  /  v3.59' -ForegroundColor $palette.Text
    $access=if($admin){'Administrator'}else{'Standard user'}
    Write-Host ("  "+$report['Report info'].Computer+"  /  $access  /  Read-only scan") -ForegroundColor $palette.Muted
    $found=@($identifiers | Where-Object Quality -eq 'Reported').Count
    $review=(Get-ReviewSummary $report $identifiers $warnings).Total
    Write-Host ''
    $read=(Get-ScanCoverage $report | Measure-Object Read -Sum).Sum
    $complete=$read -eq $scanTotal -and $report['Report info'].ExtendedStatus -ne 'Unavailable'
    $status=if($complete){'SCAN COMPLETE'}else{'SCAN PARTIAL'}
    Write-Host ("  [$status]  $found identifier fields / $read of $scanTotal sections read"+$(if($report['Report info'].ExtendedStatus -eq 'Unavailable'){' / extended not read'})) -ForegroundColor $(if($complete){$palette.Good}else{$palette.Warn})
    Write-Host "  [REVIEW]  $review items  /  [4] explains missing IDs and conflicts" -ForegroundColor $(if($review){$palette.Warn}else{$palette.Muted})
    $captured=Format-ScanTime $report['Report info'].Generated
    Write-Host ("  Captured: $captured  /  [9] Rescan when devices change") -ForegroundColor $palette.Muted
    Write-Host ''
    Write-Host '  VIEW THIS SCAN' -ForegroundColor $palette.Heading
    foreach($key in @('1','2','3','4','5')){Show-MenuItem $key (Get-MenuDestination $key) ''}
    Write-Host ''
    Write-Host '  SAVE & COMPARE' -ForegroundColor $palette.Heading
    foreach($key in @('6','7','8')){Show-MenuItem $key (Get-MenuDestination $key) ''}
    Write-Host ''
    Write-Host '  RESCAN, HELP & EXIT' -ForegroundColor $palette.Heading
    foreach($key in @('9','0')){Show-MenuItem $key (Get-MenuDestination $key) ''}
    Write-Host ''
    Write-Host '  Type a number 0-9, then Enter. Empty Enter is ignored.' -ForegroundColor $palette.Muted
}
function Show-MenuItem($Key, $Label, $Hint) {
    Write-Host "  [$Key] " -ForegroundColor $palette.Heading -NoNewline
    Write-Host $Label -ForegroundColor $palette.Text
    if ($Hint) { Write-Host "      $Hint" -ForegroundColor $palette.Muted }
}
function Test-UnavailableRecord($Record) {
    if($null -eq $Record){return $false}
    if($Record -is [System.Collections.IDictionary]){return @($Record.Keys) -contains 'Unavailable'}
    return $null -ne $Record.PSObject.Properties['Unavailable']
}
function Test-SectionReadable($Records) {
    $items = @($Records | Where-Object { $null -ne $_ })
    return $items.Count -gt 0 -and @($items | Where-Object {Test-UnavailableRecord $_}).Count -eq 0
}
function Get-FieldLabel($Name) {
    $labels = @{
        PartitionGuid='Unique GPT partition ID'; GptType='GPT partition type (shared category)'; MbrType='MBR partition type code'; AccessPaths='Volume GUID / access paths'; DiskNumber='Disk number'; PartitionNumber='Partition number'
        ScanSeconds='Total scan time (seconds)'; ScanCompleted='Scan completed'; ScanNumber='Session snapshot number'; QueryMode='Scan mode'; Seconds='Query time (seconds)'; Results='Records returned'
        FailureCode='Read error code';FailureReason='Read failure';NextStep='Suggested next step'
        PowerShellVersion='PowerShell version';WindowsVersion='Windows version';QueryBackend='Hardware query backend';MissingCommands='Unavailable commands (may be optional)';LanguageMode='PowerShell language mode'
        ProcessorId='CPU identifier'; UUID='System UUID'; SerialNumber='Serial number'
        DeviceInstanceId='Device instance ID'; HardwareID='Hardware IDs (driver match)'; CompatibleID='Compatible driver IDs'; ConfigManagerErrorCode='Windows device status code'
        IdentifyingNumber='System serial number'; MachineGuid='Windows installation ID'
        PNPDeviceID='Windows device ID'; SMBIOSAssetTag='Asset tag'
        SMBIOSBIOSVersion='BIOS version'; SMBIOSMajorVersion='SMBIOS major version'; SMBIOSMinorVersion='SMBIOS minor version'
        TotalRAM_GiB='Total memory (GiB)'; Capacity_GiB='Module size (GiB)'; Size_GiB='Size (GiB)'; Free_GiB='Free space (GiB)'
        MaxClockSpeed='Maximum CPU clock (MHz)'; Speed='Rated speed (MHz)'; ConfiguredClockSpeed='Configured speed (MHz)'
        MacAddress='Current MAC address'; PermanentAddress='Permanent MAC address'; InterfaceGuid='Network interface ID'
        MacAddressReadStatus='Current MAC read status';NetworkAddresses='Reported network addresses';RawInterfaceOperationalStatus='Raw interface status code'
        SavedAt='Saved at';ProgressWarning='Progress display warning'
        HardwareIDReadStatus='Model-ID read status';CompatibleIDReadStatus='Compatible-ID read status';RawHardwareID='Raw reported model IDs';RawCompatibleID='Raw reported compatible IDs'
        CollectionSource='Read using'; UniqueIdFormat='Storage ID format (Windows code)'
        RawPartitionStyle='Raw partition-style code';RawBusType='Raw bus-type code';RawHealthStatus='Raw disk-health code'
        RawDriveLetter='Raw drive-letter value';DriveLetterReadStatus='Drive-letter read status'
        TotalPhysicalMemory='Raw installed memory (bytes)';Capacity='Raw module capacity (bytes)';Size='Raw size (bytes)';FreeSpace='Raw free space (bytes)'
        ManufacturerName='Raw monitor maker codes';UserFriendlyName='Raw monitor name codes';ProductCodeID='Raw monitor product codes';SerialNumberID='Raw monitor serial codes'
        SerialNumberReadStatus='Monitor serial read status';NameReadStatus='Monitor name read status';RawLinkSpeedBps='Raw link speed (bits/s)';ReceiveLinkSpeed='Raw receive link speed (bits/s)'
        VolumeSerialNumber='Volume serial number'; Guid='GPT disk ID'; UniqueId='Storage unique ID'; Signature='MBR disk signature'
        DeviceLocator='Memory slot'; BankLabel='Memory bank'; DeviceID='Device / drive'; NumberOfCores='CPU cores'; NumberOfLogicalProcessors='CPU threads'
    }
    if ($labels.ContainsKey($Name)) { return $labels[$Name] }
    return (($Name -creplace '([a-z])([A-Z])', '$1 $2') -replace '_', ' ')
}
function Get-FieldQuality($Name, $Value, $Record) {
    if ($Name -eq 'Guid' -and $null -ne $Record.PartitionStyle -and [string]$Record.PartitionStyle -in @('MBR','RAW','0','1')) { return 'Not applicable' }
    $Value=Normalize-IdentifierText $Value
    if($Name -eq 'VolumeSerialNumber' -and -not $Value -and [string]$Record.DriveType -in @('2','5') -and [string]::IsNullOrWhiteSpace([string]$Record.FileSystem) -and ($null -eq $Record.Size_GiB -or $Record.Size_GiB -eq 0)){return 'Not applicable'}
    if ($Name -in @('PermanentAddress','MacAddress','PNPDeviceID') -and [string]::IsNullOrWhiteSpace([string]$Value) -and $Record.HardwareInterface -is [bool] -and -not $Record.HardwareInterface) { return 'Not applicable' }
    return (Get-Quality $Value)
}
function Test-IdentityFieldValue($Name,$Value) {
    if($Name -notmatch $identifierPattern -and $Name -notin @('DeviceID','DeviceInstanceId','ClassGuid','Index','Number','DeviceLocator','BankLabel','InstanceName')){return $true}
    if($null -eq $Value){return $true}
    # Calculated properties can wrap even strings in PSObject. Test scalar types first.
    if($Value -is [string] -or $Value -is [char]){return $true}
    return ($Value -is [ValueType] -and $Value -isnot [bool] -and $Value -isnot [datetime] -and $Value -isnot [datetimeoffset] -and $Value -isnot [timespan])
}
function Get-QuickIdGroup($Section) {
    switch($Section) {
        {$_ -in @('System identity','Motherboard','BIOS','Chassis')} {return '1'}
        {$_ -in @('CPU','Memory modules')} {return '2'}
        {$_ -in @('Physical disks','Storage identifiers','Disk summary','Volumes')} {return '3'}
        {$_ -in @('Monitors','Network adapters')} {return '4'}
        default {return '5'}
    }
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
    if ($Value -is [array]) {
        if(-not $Value.Count){return '(none reported)'}
        return (($Value | ForEach-Object { Format-FieldValue $_ }) -join ', ')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '(not provided)' }
    return [string]$Value
}
function Get-PlainRecords($Records) {
    foreach ($record in $Records) {
        $properties = if ($record -is [System.Collections.IDictionary]) {
            foreach ($key in $record.Keys) { [pscustomobject]@{Name=$key;Value=$record[$key]} }
        } else { $record.PSObject.Properties }
        foreach ($property in $properties) {
            if($property.Value -is [array]) {
                '  {0}:' -f (Get-FieldLabel $property.Name)
                if(-not $property.Value.Count){'    (none reported)'}
                $index=0
                foreach($value in $property.Value){$index++;'    [{0}] {1}' -f $index,(Format-FieldValue $value)}
            } else {'  {0}: {1}' -f (Get-FieldLabel $property.Name), (Format-FieldValue $property.Value)}
        }
        ''
    }
}
function Get-QuickIds($Inventory) {
    $fields = @(
        @('System identity','IdentifyingNumber','System serial'), @('System identity','UUID','System UUID'),
        @('Motherboard','SerialNumber','Board serial'), @('BIOS','SerialNumber','BIOS serial'), @('Chassis','SerialNumber','Chassis serial'),
        @('CPU','ProcessorId','CPU ID'), @('Memory modules','SerialNumber','RAM'),
        @('Disk summary','',''), @('Volumes','VolumeSerialNumber','Volume'),
        @('Monitors','SerialNumber','Monitor'), @('Network adapters','MacAddress','Net current'), @('Network adapters','PermanentAddress','Net permanent'), @('Windows Machine GUID','MachineGuid','Windows ID')
    )
    foreach ($entry in $fields) {
        $section = $entry[0]; $field = $entry[1]; $label = $entry[2]
        if ($section -eq 'Disk summary') {
            foreach($disk in (Get-QuickDisks $Inventory)){$disk | Add-Member NoteProperty Group '3';$disk}
            continue
        }
        $records = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory[$section] } else { $Inventory.$section }
        if (-not (Test-SectionReadable $records)) { continue }
        $records=@($records | Where-Object {$null -ne $_})
        $index = 0
        foreach ($record in $records) {
            $index++
            # Older snapshots may not contain the permanent-address field at all.
            $hasField=if($record -is [System.Collections.IDictionary]){@($record.Keys) -contains $field}else{$null -ne $record.PSObject.Properties[$field]}
            if($field -eq 'PermanentAddress' -and -not $hasField){continue}
            $suffix = switch ($section) {
                'Monitors' { " $index" }
                'CPU' { if (@($records).Count -gt 1) { " $index" } }
                'Memory modules' { if ($record.DeviceLocator) { " $index " + $record.DeviceLocator } else { " $index" } }
                'Physical disks' { if ($null -ne $record.Index) { ' ' + $record.Index } else { " $index" } }
                'Storage identifiers' { if ($null -ne $record.Number) { ' ' + $record.Number } else { " $index" } }
                'Volumes' { ' ' + $record.DeviceID }
                'Network adapters' { if ($record.Name) { " $index " + $record.Name } else { " $index" } }
                default { if($records.Count -gt 1){" $index"}else{''} }
            }
            $value = Normalize-IdentifierText $record.$field
            $quality=Get-FieldQuality $field $value $record
            if($quality -eq 'Not applicable'){continue}
            [pscustomobject]@{Label=($label + $suffix);Value=$value;Quality=$quality;Group=(Get-QuickIdGroup $section);Section=$section;Field=$field}
        }
    }
}
function Get-DiskNumber($Value) {
    $number=[uint32]0
    if($null -ne $Value -and [uint32]::TryParse([string]$Value,[ref]$number)){return $number}
    return $null
}
function Get-QuickDisks($Inventory) {
    $physical = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory['Physical disks'] } else { $Inventory.'Physical disks' }
    $storage = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory['Storage identifiers'] } else { $Inventory.'Storage identifiers' }
    $primary = if (Test-SectionReadable $physical) { @($physical | Where-Object {$null -ne $_}) } else { @() }
    $secondary = if (Test-SectionReadable $storage) { @($storage | Where-Object {$null -ne $_}) } else { @() }
    $used = New-Object 'System.Collections.Generic.HashSet[uint32]'
    $index = 0
    foreach ($disk in $primary) {
        $index++
        $number = Get-DiskNumber $disk.Index
        $matches = @($secondary | Where-Object { $candidate=Get-DiskNumber $_.Number; $null -ne $number -and $null -ne $candidate -and $candidate -eq $number })
        $primaryCount=@($primary | Where-Object {$candidate=Get-DiskNumber $_.Index;$null -ne $number -and $null -ne $candidate -and $candidate -eq $number}).Count
        $value = Normalize-IdentifierText $disk.SerialNumber
        $primaryValue=$value;$alternateValue=$null
        $quality = Get-Quality $value
        $note = ''
        if ($primaryCount -eq 1 -and $matches.Count -eq 1) {
            [void]$used.Add($number)
            $other = Normalize-IdentifierText $matches[0].SerialNumber
            $alternateValue=$other
            if ((Get-Quality $other) -eq 'Reported') {
                if ($quality -ne 'Reported') { $value=$other; $quality='Reported'; $note='Alternate source' }
                elseif ($value -cne $other) { $quality='Conflict'; $note='Sources disagree'; $value += ' / ' + $other }
            }
        } elseif($primaryCount -gt 1 -or $matches.Count -gt 1){$note='Duplicate disk number; sources not joined'}
        $label = if ($null -ne $number) { "Disk $number" } else { "Disk ?$index" }
        [pscustomobject]@{Label=$label;Value=$value;Quality=$quality;Note=$note;PrimaryValue=$primaryValue;AlternateValue=$alternateValue}
    }
    foreach ($disk in $secondary) {
        $number=Get-DiskNumber $disk.Number
        if ($null -ne $number -and $used.Contains($number)) { continue }
        # Without a reliable disk number, do not guess that two records are the same device.
        $index++
        $label = if ($null -ne $number) { "Disk $number" } else { "Disk ?$index" }
        $value = Normalize-IdentifierText $disk.SerialNumber
        [pscustomobject]@{Label=$label;Value=$value;Quality=(Get-Quality $value);Note='Alternate source';PrimaryValue=$null;AlternateValue=$value}
    }
}
function Get-QuickLayout($Width) {
    if ($Width -le 0) { $Width = 72 }
    $label = if ($Width -ge 68) { 18 } elseif ($Width -ge 45) { 12 } else { 7 }
    [pscustomobject]@{LabelWidth=$label;ValueWidth=[math]::Max(8,[math]::Min(60,$Width-$label-14))}
}
function Limit-TableText($Text, $Width) {
    $clean = ([string]$Text -replace '[\x00-\x1f\x7f]', ' ')
    if ($Width -le 0) { return '' }
    if ($clean.Length -le $Width) { return $clean }
    if ($Width -le 3) { return ('.' * $Width) }
    return $clean.Substring(0, $Width - 3) + '...'
}
function Show-QuickIds {
    Reset-UiPage
    Start-UiReport
    Write-Heading 'DEVICE IDs / QUICK VIEW'
    Write-PnpValue 'Snapshot' ('#'+$report.'Report info'.ScanNumber+' / '+(Format-ScanTime $report.'Report info'.Generated)) $palette.Muted
    $rows = @(Get-QuickIds $report)
    $unread=@(foreach($section in @('System identity','Motherboard','BIOS','Chassis','CPU','Memory modules','Physical disks','Storage identifiers','Volumes','Monitors','Network adapters','Windows Machine GUID')) {
        $exists=if($report -is [System.Collections.IDictionary]){$report.Contains($section)}else{$null -ne $report.PSObject.Properties[$section]}
        if($exists -and -not (Test-SectionReadable $report.$section)){$section}
    })
    if (-not $rows.Count) {
        Write-Host '  No IDs available. Main [4] explains why.' -ForegroundColor $palette.Warn
        if($unread.Count){Write-PnpValue 'NOT READ' ($unread -join ', ') $palette.Warn}
        return
    }
    $nav=[ordered]@{'1'='PC & firmware';'2'='CPU & RAM';'3'='Storage';'4'='Monitor/network';'5'='Windows'}
    $jumps=@(foreach($key in $nav.Keys){if(@($rows | Where-Object Group -eq $key).Count){$key+' '+$nav[$key]}})
    Write-PnpValue 'Jump' ($jumps -join ' / ') $palette.Muted
    $windowWidth = 72
    try { if ([Console]::WindowWidth -gt 0) { $windowWidth = [Console]::WindowWidth } } catch { }
    $stacked=$windowWidth -lt 45
    $layout = Get-QuickLayout $windowWidth
    $valueWidth = $layout.ValueWidth; $labelWidth=$layout.LabelWidth
    $format = '  {0,-' + $labelWidth + '}  {1,-' + $valueWidth + '}  {2}'
    if(-not $stacked){Write-Host ($format -f 'DEVICE', 'ID / SERIAL', 'STATUS') -ForegroundColor $palette.Muted}
    $groups=[ordered]@{'1'='PC & FIRMWARE';'2'='CPU & RAM';'3'='DISK SERIALS & VOLUME IDs';'4'='MONITORS & NETWORK ADDRESSES';'5'='WINDOWS INSTALLATION ID'}
    foreach($group in $groups.Keys) {
        $items=@($rows | Where-Object Group -eq $group)
        if(-not $items.Count){continue}
        Add-ReportBookmark $group
        Write-Host ("`n  [$group] "+$groups[$group]) -ForegroundColor $palette.Heading
    foreach ($row in $items) {
        $status = switch ($row.Quality) { 'Reported' { if ($row.Note -eq 'Alternate source') { 'OK*' } else { 'OK' } }; 'Missing' { 'Missing' }; 'Conflict' { 'Clash' }; default { 'Default' } }
        $value = if ($row.Quality -eq 'Missing') { '-' } elseif ($row.Quality -eq 'Placeholder') { '(default value)' } else { $row.Value }
        $color = if ($row.Quality -eq 'Reported') { $palette.Good } else { $palette.Warn }
        if($stacked){Write-PnpValue ($row.Label+' ['+$status+']') $value $color;Write-Host '';continue}
        Write-Host (('  {0,-' + $labelWidth + '}  ') -f (Limit-TableText $row.Label $labelWidth)) -ForegroundColor $palette.Text -NoNewline
        Write-Host (('{0,-' + $valueWidth + '}  ') -f (Limit-TableText $value $valueWidth)) -ForegroundColor $color -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    }
    if($unread.Count){Write-PnpValue 'NOT READ' (($unread -join ', ')+'. Main [4] explains why.') $palette.Warn}
    Write-Host "`n  ... = shortened. Main [5] All details / full IDs   Main [6] Save report" -ForegroundColor $palette.Muted
    if (@($rows | Where-Object Note -eq 'Alternate source').Count) { Write-Host '  * Serial from the alternate Windows storage source.' -ForegroundColor $palette.Muted }
    if (@($rows | Where-Object Quality -eq 'Conflict').Count) { Write-Host '  Clash = Windows sources disagree. Main [4] Review / Main [5] Both sources' -ForegroundColor $palette.Warn }
    if ($warnings.Count) { Write-Host '  Some sections could not be read. Main [4] Review issues' -ForegroundColor $palette.Warn }
    Write-PnpValue 'Meaning' 'OK = supplied by Windows. CPU, volume and network IDs are not factory serials.' $palette.Muted
}
function Get-ScanCoverage($Inventory) {
    $labels=@{'SYSTEM & FIRMWARE'='System & firmware';'CPU & MEMORY'='CPU & memory';'STORAGE'='Storage';'GRAPHICS & NETWORK'='Graphics / network / monitors';'WINDOWS'='Windows'}
    foreach($group in $sectionGroups.Keys) {
        $available=0
        foreach($name in $sectionGroups[$group]) {
            $records=if($Inventory -is [System.Collections.IDictionary]){$Inventory[$name]}else{$Inventory.$name}
            if(Test-SectionReadable $records){$available++}
        }
        $total=@($sectionGroups[$group]).Count
        $status=if($available -eq $total){'OK'}elseif($available -eq 0){'NOT READ'}else{'PARTIAL'}
        [pscustomobject]@{Area=$labels[$group];Read=$available;Total=$total;Status=$status}
    }
    $pnp=if($Inventory -is [System.Collections.IDictionary]){$Inventory['PnP hardware IDs']}else{$Inventory.'PnP hardware IDs'}
    $read=if(Test-SectionReadable $pnp){1}else{0}
    [pscustomobject]@{Area='All present device classes';Read=$read;Total=1;Status=$(if($read){'OK'}else{'NOT READ'})}
}
function Format-ScanTime($Value) {
    if($Value -is [datetimeoffset]){return $Value.ToString('yyyy-MM-dd HH:mm:ss zzz')}
    if($Value -is [datetime]){return ([datetimeoffset]$Value).ToString('yyyy-MM-dd HH:mm:ss zzz')}
    $parsed=[datetimeoffset]::MinValue
    if([datetimeoffset]::TryParse([string]$Value,[ref]$parsed)){return $parsed.ToString('yyyy-MM-dd HH:mm:ss zzz')}
    return (Format-FieldValue $Value)
}
function Get-OverviewSummary($Inventory,$IdRows,$QueryWarnings) {
    $review=Get-ReviewSummary $Inventory $IdRows $QueryWarnings
    $coverage=@(Get-ScanCoverage $Inventory)
    $read=($coverage | Measure-Object Read -Sum).Sum
    $total=($coverage | Measure-Object Total -Sum).Sum
    $deviceReadable=Test-SectionReadable $Inventory['PnP hardware IDs']
    $nodes=$null; $classes=$null; $models=$null
    if($deviceReadable) {
        $devices=@($Inventory['PnP hardware IDs'] | Where-Object {$null -ne $_})
        $nodes=$devices.Count
        $classNames=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($device in $devices){if(-not [string]::IsNullOrWhiteSpace([string]$device.PNPClass)){[void]$classNames.Add(([string]$device.PNPClass).Trim())}}
        $classes=$classNames.Count
        $models=@($devices | Where-Object {@($_.HardwareID | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0}).Count
    }
    $extraState='NOT SCANNED'; $known=$null; $hidden=$null; $remembered=$null; $visibilityUnread=$null; $presenceUnknown=$null; $captured=$null
    if($Inventory.Contains('Extended scan info')) {
        $info=$Inventory['Extended scan info']; $captured=$info.Captured
        if($info.Error -or -not (Test-SectionReadable $Inventory['Extended device inventory'])) {
            $extraState='NOT READ'
        } else {
            $extraState=if($Inventory['Report info'].ExtendedStatus -eq 'Unavailable'){'STALE'}else{'READ'}
            $extra=@($Inventory['Extended device inventory'] | Where-Object {$null -ne $_})
            $known=$extra.Count
            $hidden=@($extra | Where-Object {$_.HiddenByNodeFlag -eq $true -or $_.HiddenByClass -eq $true}).Count
            $remembered=@($extra | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count
            $visibilityUnread=@($extra | Where-Object {$null -eq $_.HiddenByNodeFlag -or $null -eq $_.HiddenByClass}).Count
            $presenceUnknown=@($extra | Where-Object {$_.Present -isnot [bool]}).Count
        }
    } elseif($Inventory['Report info'].ExtendedStatus -eq 'Unavailable') {
        $extraState='NOT READ';$captured=$Inventory['Report info'].ExtendedAttempted
    }
    if($extraState -eq 'NOT READ' -and $Inventory['Report info'].ExtendedAttempted){$captured=$Inventory['Report info'].ExtendedAttempted}
    [pscustomobject]@{
        Coverage=$coverage;Read=$read;Total=$total;NotRead=($total-$read);Complete=($read -eq $total -and $extraState -notin @('NOT READ','STALE'))
        Found=@($IdRows | Where-Object Quality -eq 'Reported').Count
        Missing=@($IdRows | Where-Object Quality -eq 'Missing').Count
        Default=@($IdRows | Where-Object Quality -eq 'Placeholder').Count
        DeviceReadable=$deviceReadable;Nodes=$nodes;Classes=$classes;Models=$models
        DeviceIssues=$review.DeviceCount
        QueryWarnings=$review.UnreadCount
        Conflicts=$review.ConflictCount
        ReviewTotal=$review.Total
        ExtendedState=$extraState;Known=$known;Hidden=$hidden;Remembered=$remembered;VisibilityUnread=$visibilityUnread;PresenceUnknown=$presenceUnknown;ExtendedCaptured=$captured
    }
}
function Show-Overview {
    Reset-UiPage
    Start-UiReport
    Add-ReportBookmark '1'
    $summary=Get-OverviewSummary $report $identifiers $warnings
    Write-Heading 'SCAN OVERVIEW'
    $status=if($summary.Complete){'READ COMPLETE'}else{'READS PARTIAL'}
    Write-PnpValue 'Read status' ($status+' / '+$summary.Read+'/'+$summary.Total+' normal / '+$summary.NotRead+' not read') $(if($summary.Complete){$palette.Good}else{$palette.Warn})
    Write-PnpValue 'Computer' $report['Report info'].Computer $palette.Text
    Write-PnpValue 'Captured' (Format-ScanTime $report['Report info'].Generated) $palette.Muted
    if($null -ne $report['Report info'].ScanSeconds) {
        $time='{0:0.00}s' -f $report['Report info'].ScanSeconds
        if($report.Contains('Scan timing') -and $report['Scan timing'].Count) {
            $slowest=$report['Scan timing'] | Sort-Object Seconds -Descending | Select-Object -First 1
            $time+=' / slowest: '+$slowest.Section+' ('+('{0:0.0}s' -f $slowest.Seconds)+')'
        }
        Write-PnpValue 'Time' $time $palette.Muted
    }
    Write-Host ''; Write-Host '  RESULTS' -ForegroundColor $palette.Heading
    Write-PnpValue 'Identifier fields' ("$($summary.Found) found / $($summary.Missing) missing / $($summary.Default) default") $(if($summary.Missing+$summary.Default){$palette.Warn}else{$palette.Good})
    if($summary.DeviceReadable) {
        Write-PnpValue 'Present devices' ("$($summary.Nodes) records / $($summary.Classes) classes / $($summary.Models) with hardware IDs") $palette.Text
    } else {Write-PnpValue 'Present devices' 'Not read; device count unknown. See [4].' $palette.Warn}
    Write-PnpValue 'Review' ("$($summary.ReviewTotal) findings / $($summary.DeviceIssues) device / $($summary.Conflicts) conflicts / $($summary.QueryWarnings) not read -> [4]") $(if($summary.ReviewTotal){$palette.Warn}else{$palette.Good})
    switch($summary.ExtendedState) {
        'READ' {
            Write-PnpValue 'Extended devices' ("$($summary.Known) known records / $($summary.Hidden) hidden / $($summary.Remembered) remembered") $palette.Text
            Write-PnpValue 'Uncertainty' ("$($summary.VisibilityUnread) flags unread / $($summary.PresenceUnknown) presence unknown; groups overlap") $(if($summary.VisibilityUnread+$summary.PresenceUnknown){$palette.Warn}else{$palette.Muted})
            Write-PnpValue 'Extended capture' (Format-ScanTime $summary.ExtendedCaptured) $palette.Muted
        }
        'STALE' {
            Write-PnpValue 'Extended devices' ("PREVIOUS catalog / $($summary.Known) records / refresh NOT READ") $palette.Warn
            Write-PnpValue 'Extended capture' (Format-ScanTime $summary.ExtendedCaptured) $palette.Muted
            Write-PnpValue 'Next' 'Retry [9] > [4]. [4] explains the latest failure.' $palette.Warn
        }
        'NOT READ' {
            Write-PnpValue 'Extended devices' 'NOT READ / retry [9] > [4]' $palette.Warn
            Write-PnpValue 'Extended attempt' (Format-ScanTime $summary.ExtendedCaptured) $palette.Muted
        }
        default {Write-PnpValue 'Extended devices' 'Not scanned / [9] > [4] checks hidden and remembered records' $palette.Muted}
    }
    Write-Host ''; Write-Host '  COVERAGE / QUERIES' -ForegroundColor $palette.Heading
    $width=96
    try {if([Console]::WindowWidth -gt 0){$width=[Console]::WindowWidth}}catch{}
    if($width -ge 60){Write-Host ('    {0,-30} {1,-9} {2}' -f 'AREA','READ','STATUS') -ForegroundColor $palette.Muted}
    foreach($row in $summary.Coverage) {
        $color=if($row.Status -eq 'OK'){$palette.Good}else{$palette.Warn}
        if($width -ge 60){Write-PnpLine ('    {0,-30} {1,-9} {2}' -f $row.Area,("$($row.Read)/$($row.Total)"),$row.Status) $color}
        else {Write-PnpValue $row.Area ("$($row.Read)/$($row.Total) read [$($row.Status)]") $color}
    }
    Write-Host ''; Write-Host '  NEXT' -ForegroundColor $palette.Heading
    Write-PnpValue 'View / keep' '[2] IDs / [4] Review / [5] Full report / [6] Save' $palette.Text
    Write-PnpValue 'Scan again' '[9] > [1] PC scan / [9] > [4] Extended scan' $palette.Text
    Write-PnpValue 'Scope' 'ID fields are not unique PC counts. Records include physical and virtual nodes.' $palette.Muted
}

function Show-FullReport {
    Start-UiReport
    $script:reportBookmarks=[ordered]@{}
    Write-Heading 'FULL INVENTORY REPORT'
    Write-PnpValue 'Contents' '1 Report info / 2 System & firmware / 3 CPU & memory' $palette.Heading
    Write-PnpValue '' '4 Storage / 5 Graphics & network / 6 Windows' $palette.Heading
    Write-PnpValue '' '7 All device IDs / 8 Review & scan timing' $palette.Heading
    Write-PnpValue 'Controls' 'Press 1-8 to jump. Wheel / arrows to scroll. 0 or Enter = menu.' $palette.Muted
    Write-PnpValue 'About this report' 'Windows-reported inventory; missing values can be normal. Main [6] saves TXT + JSON.' $palette.Muted
    Add-ReportBookmark '1'
    Write-Heading 'REPORT INFORMATION'
    Show-Records $report['Report info']
    if($report.Contains('Compatibility')){Write-Heading 'RUNTIME & AVAILABLE COMMANDS';Show-Records $report['Compatibility']}
    $groupNumber=1
    foreach ($group in $sectionGroups.Keys) {
        $groupNumber++
        Add-ReportBookmark ([string]$groupNumber)
        Write-Heading $group
        foreach ($name in $sectionGroups[$group]) {
            Write-Host "`n  > $name" -ForegroundColor $palette.Heading
            $count=@($report[$name] | Where-Object {$null -ne $_ -and -not (Test-UnavailableRecord $_)}).Count
            Write-PnpValue 'Records captured' $count $palette.Muted
            Show-Records $report[$name] $name
        }
    }
    Add-ReportBookmark '7'
    Write-Heading 'ALL PRESENT DEVICE IDs / FULL LISTS'
    if($report.Contains('PnP hardware IDs')) {
        Show-PnpRecords $report['PnP hardware IDs'] -Full
    }else{Show-Records $null}
    if($report.Contains('Extended scan info')) {
        Write-Heading 'EXTENDED DEVICE CATALOG / SEPARATE CAPTURE'
        Show-Records $report['Extended scan info']
        Show-PnpRecords $report['Extended device inventory'] -Full -Extended
    }
    Add-ReportBookmark '8'
    Show-Attention -Inline
    Write-Heading 'STARTUP SCAN TIMING'
    Write-PnpValue 'Timing scope' 'Startup queries only; refreshed device views do not retime the original scan.' $palette.Muted
    Show-Records $report['Scan timing']
}
function Get-ReviewReadFailures($Inventory,$QueryWarnings) {
    $entries=New-Object 'System.Collections.Generic.List[object]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $names=if($Inventory -is [System.Collections.IDictionary]){@($Inventory.Keys)}else{@($Inventory.PSObject.Properties.Name)}
    $known=@($sectionGroups.Values | ForEach-Object {$_})+@('PnP hardware IDs','Extended device inventory')
    $extra=$Inventory.'Report info'
    $extraInfo=$Inventory.'Extended scan info'
    $extraFailed=$extra.ExtendedStatus -eq 'Unavailable' -or $extraInfo.Error
    $add={param($Section,$Message,$Stored,$Key)
        if(-not $Key){$Key=$Section}
        if(-not $seen.Add($Key)){return}
        if([string]::IsNullOrWhiteSpace([string]$Message)){$Message='Windows returned an unavailable section without a diagnostic message.'}
        $failure=Get-ScanFailureInfo $Message
        if($Stored.FailureCode -and $Stored.FailureReason -and $Stored.NextStep){$failure=[pscustomobject]@{Code=$Stored.FailureCode;Reason=$Stored.FailureReason;Action=$Stored.NextStep}}
        if($Section -eq 'Extended device inventory' -and $extra.ExtendedFailureCode -and $extra.ExtendedFailureReason -and $extra.ExtendedNextStep){$failure=[pscustomobject]@{Code=$extra.ExtendedFailureCode;Reason=$extra.ExtendedFailureReason;Action=$extra.ExtendedNextStep}}
        $action=if($Section -eq 'Extended device inventory'){$failure.Action.Replace('[9] > [1]','[9] > [4]')}else{$failure.Action}
        $entries.Add([pscustomobject]@{Section=$Section;Message=[string]$Message;Code=$failure.Code;Reason=$failure.Reason;Action=$action})
    }
    foreach($name in $known | Select-Object -Unique) {
        if($name -notin $names){continue}
        if($name -eq 'Extended device inventory' -and $extraFailed){continue}
        $records=$Inventory.$name
        if(Test-SectionReadable $records){continue}
        $stored=@($records | Where-Object {Test-UnavailableRecord $_} | Select-Object -First 1)
        if($stored.Count){& $add $name $stored[0].Unavailable $stored[0]}
        else{& $add $name 'No records returned by Windows.' $null}
    }
    if($extraFailed) {
        $message=if($extraInfo.Error){$extraInfo.Error}else{(@($QueryWarnings | Where-Object {$_ -like 'Extended device inventory: *'} | Select-Object -First 1) -join '') -ireplace '^Extended device inventory: ',''}
        if(-not $message){$message='The latest extended refresh did not complete.'}
        & $add 'Extended device inventory' $message $extraInfo
    }
    foreach($warning in $QueryWarnings) {
        $text=([string]$warning).Trim()
        if(-not $text){continue}
        $parts=$text -split ': ',2
        $name=$parts[0].Trim()
        if($parts.Count -lt 2){& $add 'Query warning' $text $null ('Unclassified: '+$text);continue}
        if($name -in $names -and (Test-SectionReadable $Inventory.$name) -and -not ($name -eq 'Extended device inventory' -and $extraFailed)){continue}
        $stored=@($Inventory.$name | Where-Object {Test-UnavailableRecord $_} | Select-Object -First 1)
        & $add $name $parts[1] $(if($stored.Count){$stored[0]}else{$null})
    }
    $entries.ToArray()
}
function Get-ReviewSummary($Inventory,$IdRows,$QueryWarnings) {
    $ids=@($IdRows | Where-Object {$null -ne $_ -and $_.Quality -in @('Missing','Placeholder')})
    $disk=@(Get-QuickDisks $Inventory | Where-Object Quality -eq 'Conflict')
    $records=@(Get-InventoryConflicts $Inventory)
    $pnp=if($Inventory -is [System.Collections.IDictionary]){$Inventory['PnP hardware IDs']}else{$Inventory.'PnP hardware IDs'}
    $pnpFindings=@(Get-PnpIssues $pnp)
    $pnpConflicts=@($pnpFindings | Where-Object Kind -in @('Duplicate','ResourceConflict'))
    $devices=@($pnpFindings | Where-Object Kind -notin @('Duplicate','ResourceConflict'))
    $unreadDetails=@(Get-ReviewReadFailures $Inventory $QueryWarnings)
    $unread=@($unreadDetails | ForEach-Object {$_.Section+': '+$_.Message})
    $conflictCount=$disk.Count+$records.Count+$pnpConflicts.Count
    [pscustomobject]@{
        IdIssues=$ids;DiskClashes=$disk;RecordConflicts=$records;PnpConflicts=$pnpConflicts;DeviceIssues=$devices;Unread=$unread;UnreadDetails=$unreadDetails
        ConflictCount=$conflictCount;UnreadCount=$unread.Count;DeviceCount=$devices.Count
        MissingCount=@($ids | Where-Object Quality -eq 'Missing').Count
        DefaultCount=@($ids | Where-Object Quality -eq 'Placeholder').Count
        Total=($conflictCount+$unread.Count+$devices.Count+$ids.Count)
    }
}
function Get-DeviceReviewAction($Issue) {
    switch($Issue.Kind) {
        'UnknownStatus' {return 'Rescan [9] > [1]. If still unknown, inspect this device in Main [5] or Device Manager.'}
        'MissingInstance' {return 'Rescan. A device instance ID is needed to match this node reliably.'}
        'Duplicate' {return 'Rescan before comparing. Repeated instance IDs cannot be matched reliably.'}
        'InvalidIdList' {return 'Rescan [9] > [1]. Inspect valid and raw model/compatible IDs in Main [5].'}
    }
    switch($Issue.Code) {
        22 {return 'Check whether this device was intentionally disabled in Device Manager.'}
        45 {return 'Check whether this device is disconnected; rescan to refresh its presence.'}
        12 {return 'Inspect the reported resource conflict in Device Manager before changing settings.'}
        14 {return 'Windows requests a restart. Save your work before restarting, then rescan.'}
        28 {return 'Inspect this device in Device Manager and check its driver.'}
        default {return 'Inspect this device and its reported code in Device Manager, then rescan.'}
    }
}
function Show-Attention([switch]$Inline) {
    if(-not $Inline){Reset-UiPage}
    Start-UiReport
    if(-not $Inline){Add-ReportBookmark '1'}
    Write-Heading 'ITEMS TO REVIEW'
    $review=Get-ReviewSummary $report $identifiers $warnings
    Write-PnpValue 'Review counts' ("$($review.Total) findings / $($review.ConflictCount) conflicts / $($review.UnreadCount) sections not read") $(if($review.Total){$palette.Warn}else{$palette.Good})
    Write-PnpValue 'Other findings' ("$($review.DeviceCount) device findings / $($review.MissingCount) missing IDs / $($review.DefaultCount) default IDs") $palette.Text
    if(-not $Inline){Write-PnpValue 'Jump' '1 Top / 2 Devices / 3 Not read / 4 IDs / 5 Conflicts. 0 or Enter = menu.' $palette.Muted}
    if(-not $Inline -and $review.Total) {
        $first=if($review.ConflictCount){'[5] Conflicts: verify repeated or disagreeing readings first.'}elseif($review.UnreadCount){'[3] Not read: check which readers failed.'}elseif($review.DeviceCount){'[2] Devices: inspect the Windows-reported status.'}else{'[4] IDs: missing/default values can be normal.'}
        Write-PnpValue 'Start with' $first $palette.Heading
    }
    Write-PnpValue 'Meaning' 'Counts are findings, not unique devices. A finding alone does not prove hardware failure.' $palette.Muted
    if(-not $review.Total){Write-PnpValue 'OK' 'No missing identifiers, placeholders, failed sections or conflicts detected.' $palette.Good}
    if(-not $Inline){Add-ReportBookmark '5'}
    Write-Host '';Write-Host ('  CONFLICTS / VERIFY BEFORE COMPARING / '+$review.ConflictCount) -ForegroundColor $palette.Heading
    if(-not $review.ConflictCount){Write-PnpValue 'Result' 'No conflicts detected.' $palette.Muted}
    foreach($conflict in $review.RecordConflicts) {
        $keyLabel=if($conflict.DeviceKey){$conflict.DeviceKey}else{'no reliable device key'}
        Write-PnpValue 'SCAN CONFLICT' ($conflict.Section+' / '+$keyLabel) $palette.Warn
        Write-PnpValue 'Why' $conflict.Message $palette.Text
        Write-PnpValue 'Next' 'Rescan [9] > [1]. Check the duplicate records in Main [5]; do not guess which record matches.' $palette.Muted
    }
    foreach($conflict in $review.DiskClashes) {
        Write-PnpValue '[SOURCE CLASH]' ($conflict.Label+' / Windows storage sources report different serials') $palette.Warn
        Write-PnpValue 'Physical disks' $conflict.PrimaryValue $palette.Text
        Write-PnpValue 'Storage identifiers' $conflict.AlternateValue $palette.Text
        Write-PnpValue 'Next' 'Rescan [9] > [1] and check both sources in Main [5]. This disagreement is not proof of a failing disk.' $palette.Muted
    }
    foreach($conflict in $review.PnpConflicts) {
        $label=if($conflict.Kind -eq 'ResourceConflict' -and $conflict.Device){$conflict.Device+' / '+$conflict.Message}else{$conflict.Message}
        Write-PnpValue 'DEVICE CONFLICT' $label $palette.Warn
        if($conflict.InstanceId -and $conflict.Kind -ne 'Duplicate'){Write-PnpValue 'Instance' $conflict.InstanceId $palette.Muted}
        if($conflict.Statuses){Write-PnpValue 'Status readings' ($conflict.Statuses -join ' / ') $palette.Text}
        Write-PnpValue 'Next' (Get-DeviceReviewAction $conflict) $palette.Muted
    }
    if(-not $Inline){Add-ReportBookmark '2'}
    Write-Host '';Write-Host ('  DEVICE STATUS & RECORDS / '+$review.DeviceCount) -ForegroundColor $palette.Heading
    if(-not $review.DeviceCount){Write-PnpValue 'Result' 'No device-status findings.' $palette.Muted}
    foreach($problem in $review.DeviceIssues) {
        $name=if(-not [string]::IsNullOrWhiteSpace([string]$problem.Device)){$problem.Device}elseif($problem.InstanceId){$problem.InstanceId}else{'Unnamed device'}
        Write-PnpValue 'DEVICE REVIEW' ($name+' / '+$problem.Message) $palette.Warn
        if($problem.InstanceId -and $name -ne $problem.InstanceId){Write-PnpValue 'Instance' $problem.InstanceId $palette.Muted}
        Write-PnpValue 'Next' (Get-DeviceReviewAction $problem) $palette.Muted
    }
    if(-not $Inline){Add-ReportBookmark '3'}
    Write-Host '';Write-Host ('  SECTIONS NOT READ / '+$review.UnreadCount) -ForegroundColor $palette.Heading
    if(-not $review.UnreadCount){Write-PnpValue 'Result' 'No unread sections reported.' $palette.Muted}
    foreach($failure in $review.UnreadDetails) {
        Write-PnpValue ('NOT READ / '+$failure.Section) ($failure.Reason+' ['+$failure.Code+']') $palette.Warn
        Write-PnpValue 'Next' ($failure.Action -ireplace '(?<!Main )\[5\]','Main [5]') $palette.Muted
    }
    if(-not $Inline){Add-ReportBookmark '4'}
    Write-Host '';Write-Host ('  IDENTIFIERS NOT SUPPLIED / DEFAULT / '+$review.IdIssues.Count) -ForegroundColor $palette.Heading
    if(-not $review.IdIssues.Count){Write-PnpValue 'Result' 'No missing/default identifier findings.' $palette.Muted}
    foreach($row in $review.IdIssues) {
        $device=if($row.Device){' ('+$row.Device+')'}else{''}
        $status=if($row.Quality -eq 'Missing'){'NOT SUPPLIED'}else{'DEFAULT VALUE'}
        Write-PnpValue $status ($row.Section+$device+' / '+(Get-FieldLabel $row.Field)) $palette.Warn
        if($row.Quality -eq 'Placeholder'){Write-PnpValue 'Windows supplied' $row.Value $palette.Muted}
    }
    if($review.IdIssues.Count){Write-PnpValue 'Next' 'Check full values in Main [5]. Missing/default IDs can be firmware limitations; rescanning may not supply them.' $palette.Muted}
}

function Show-Categories {
    Write-Heading 'BROWSE HARDWARE'
    $names = @($sectionGroups.Keys)
    for ($index = 0; $index -lt $names.Count; $index++) { Show-MenuItem ($index + 1) $names[$index] '' }
    Show-MenuItem '6' 'All device IDs (PnP / drivers)' ''
    Show-MenuItem '0' 'Back to main menu' ''
    Write-Host '  [0] Back. Empty Enter is ignored.' -ForegroundColor $palette.Muted
    Complete-UiReport
    $selection=Read-MenuChoice -Maximum 6
    if($null -eq $selection -or $selection -eq '0'){return $false}
    $destination=if($selection -eq '6'){'Deep hardware IDs'}else{$names[[int]$selection-1]}
    Show-UiTransition 'Next' $destination
    Reset-UiPage
    if($selection -eq '6'){Show-DriverHardwareIds;return $true}
    $name = $names[[int]$selection - 1]
    Start-UiReport
    Write-Heading $name
    foreach ($section in $sectionGroups[$name]) {
        Write-Host "`n  > $section" -ForegroundColor $palette.Heading
        Show-Records $report[$section] $section
    }
    return $true
}
function Get-StorageCodeName($Kind,$Code) {
    if($null -eq $Code){return $null}
    $maps=@{
        PartitionStyle=@{0='RAW';1='MBR';2='GPT'}
        HealthStatus=@{0='Healthy';1='Warning';2='Unhealthy'}
        BusType=@{0='Unknown';1='SCSI';2='ATAPI';3='ATA';4='IEEE 1394';5='SSA';6='Fibre Channel';7='USB';8='RAID';9='iSCSI';10='SAS';11='SATA';12='SD';13='MMC';14='Virtual';15='File Backed Virtual';16='Storage Spaces';17='NVMe';18='SCM';19='UFS'}
    }
    $number=[uint16]0
    if($Code -is [bool] -or -not [uint16]::TryParse([string]$Code,[ref]$number)){return 'Unknown (invalid Windows code)'}
    $number=[int]$number
    if($maps.ContainsKey($Kind) -and $maps[$Kind].ContainsKey($number)){return $maps[$Kind][$number]}
    return "Windows code $number"
}
function Get-StorageIdentifiers {
    Get-HwidInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Disk -OperationTimeoutSec 30 -Property Number,FriendlyName,SerialNumber,UniqueId,UniqueIdFormat,Guid,Signature,PartitionStyle,BusType,HealthStatus |
        Select-Object Number,FriendlyName,SerialNumber,UniqueId,UniqueIdFormat,Guid,Signature,
            @{n='PartitionStyle';e={Get-StorageCodeName 'PartitionStyle' $_.PartitionStyle}},
            @{n='BusType';e={Get-StorageCodeName 'BusType' $_.BusType}},
            @{n='HealthStatus';e={Get-StorageCodeName 'HealthStatus' $_.HealthStatus}},
            @{n='RawPartitionStyle';e={$_.PartitionStyle}},@{n='RawBusType';e={$_.BusType}},@{n='RawHealthStatus';e={$_.HealthStatus}}
}
function Get-PartitionLetterInfo($Value) {
    if($null -eq $Value -or [string]$Value -in @('',[string][char]0,'0')){return [pscustomobject]@{Text=$null;Status='Not assigned'}}
    $text=[string]$Value;$number=[uint16]0
    if($Value -isnot [bool] -and [uint16]::TryParse($text,[ref]$number)){$text=[string][char]$number}
    if($text -cmatch '^[A-Za-z]$'){return [pscustomobject]@{Text=$text.ToUpperInvariant();Status='Read'}}
    return [pscustomobject]@{Text=$null;Status='Invalid value'}
}
function Get-PartitionIdentifiers {
    Get-HwidInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Partition -OperationTimeoutSec 30 -Property DiskNumber,PartitionNumber,DriveLetter,Guid,GptType,MbrType,AccessPaths,Size |
        Select-Object DiskNumber,PartitionNumber,@{n='DriveLetter';e={(Get-PartitionLetterInfo $_.DriveLetter).Text}},@{n='DriveLetterReadStatus';e={(Get-PartitionLetterInfo $_.DriveLetter).Status}},@{n='RawDriveLetter';e={$_.DriveLetter}},@{n='PartitionGuid';e={$_.Guid}},GptType,MbrType,AccessPaths,Size,@{n='Size_GiB';e={GiB $_.Size}}
}
function Format-NetworkLinkSpeed($Value) {
    $bits=[uint64]0
    if($null -eq $Value -or $Value -is [bool] -or -not [uint64]::TryParse([string]$Value,[ref]$bits)){return $null}
    return ('{0:0.##} Mbps' -f ($bits/1000000.0))
}
function Format-NetworkStatus($Value,[switch]$Legacy) {
    if($null -eq $Value){return $null}
    $number=[uint32]0
    if($Value -is [bool] -or -not [uint32]::TryParse([string]$Value,[ref]$number) -or ($Legacy -and $number -gt 65535)){return 'Unknown (invalid Windows network status)'}
    $labels=if($Legacy){@{0='Down';1='Connecting';2='Up';3='Disconnecting';4='Hardware not present';5='Disabled';6='Hardware malfunction';7='Down';8='Authenticating';9='Authenticated';10='Authentication failed';11='Invalid address';12='Credentials required'}}else{@{1='Up';2='Down';3='Testing';4='Unknown';5='Dormant';6='Not present';7='Lower layer down'}}
    if($number -le [int]::MaxValue -and $labels.ContainsKey([int]$number)){return $labels[[int]$number]}
    if($Legacy){return "Windows network status $number"}
    return "Windows status $number"
}
function Get-NetworkAddressInfo($Addresses,$Explicit=$null) {
    if($Explicit -is [string] -and -not [string]::IsNullOrWhiteSpace($Explicit)){return [pscustomobject]@{Value=$Explicit;Status='Explicit current address'}}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $values=New-Object 'System.Collections.Generic.List[string]'
    foreach($address in $Addresses){
        if($address -isnot [string] -or [string]::IsNullOrWhiteSpace($address)){continue}
        $key=$address.Trim();$compact=$key -replace '[-:]',''
        if($compact -match '^[0-9a-fA-F]+$'){$key=$compact.ToUpperInvariant()}
        if($seen.Add($key)){$values.Add($address)}
    }
    if($values.Count -eq 1){return [pscustomobject]@{Value=$values[0];Status='Single reported address'}}
    if($values.Count -gt 1){return [pscustomobject]@{Value=$null;Status='Multiple reported addresses; current address not identified'}}
    return [pscustomobject]@{Value=$null;Status='No usable address supplied'}
}
function Get-NetworkIdentifiers {
    try {
        $adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {$null -ne $_})
        if(-not $adapters.Count){throw 'No adapters returned by Get-NetAdapter.'}
        $rows=@($adapters | Select-Object Name,InterfaceDescription,InterfaceGuid,MacAddress,PermanentAddress,PNPDeviceID,Status,LinkSpeed,HardwareInterface,@{n='CollectionSource';e={'Get-NetAdapter'}})
        return $rows
    } catch {$primaryError=$_.Exception.Message}
    try {
        $adapters=@(Get-HwidInstance -Namespace 'root/StandardCimv2' -ClassName MSFT_NetAdapter -OperationTimeoutSec 20 -Property Name,InterfaceDescription,InterfaceGuid,NetworkAddresses,PermanentAddress,PNPDeviceID,InterfaceOperationalStatus,ReceiveLinkSpeed,HardwareInterface | Where-Object {$null -ne $_})
        if(-not $adapters.Count){throw 'No adapters returned by the CIM fallback.'}
        $rows=@($adapters | Select-Object Name,InterfaceDescription,InterfaceGuid,@{n='MacAddress';e={(Get-NetworkAddressInfo $_.NetworkAddresses $_.MacAddress).Value}},@{n='MacAddressReadStatus';e={(Get-NetworkAddressInfo $_.NetworkAddresses $_.MacAddress).Status}},PermanentAddress,PNPDeviceID,NetworkAddresses,
            @{n='Status';e={Format-NetworkStatus $_.InterfaceOperationalStatus}},@{n='RawInterfaceOperationalStatus';e={$_.InterfaceOperationalStatus}},
            @{n='LinkSpeed';e={Format-NetworkLinkSpeed $_.ReceiveLinkSpeed}},ReceiveLinkSpeed,HardwareInterface,@{n='CollectionSource';e={'MSFT_NetAdapter CIM fallback'}})
        return $rows
    } catch {$modernError=$_.Exception.Message}
    try {
        # Last resort for older Windows/provider installations; never infer a permanent MAC.
        $adapters=@(Get-HwidInstance -ClassName Win32_NetworkAdapter -OperationTimeoutSec 20 -Property Name,NetConnectionID,GUID,MACAddress,PNPDeviceID,PhysicalAdapter,NetConnectionStatus,NetEnabled,Speed | Where-Object {$null -ne $_})
        if(-not $adapters.Count){throw 'No adapters returned by the Win32 fallback.'}
        $rows=@($adapters | Select-Object @{n='Name';e={if(-not [string]::IsNullOrWhiteSpace([string]$_.NetConnectionID)){$_.NetConnectionID}else{$_.Name}}},@{n='InterfaceDescription';e={$_.Name}},@{n='InterfaceGuid';e={$_.GUID}},MacAddress,@{n='PermanentAddress';e={$null}},PNPDeviceID,
            @{n='Status';e={Format-NetworkStatus $_.NetConnectionStatus -Legacy}},
            @{n='LinkSpeed';e={Format-NetworkLinkSpeed $_.Speed}},@{n='RawLinkSpeedBps';e={$_.Speed}},@{n='HardwareInterface';e={$_.PhysicalAdapter}},NetConnectionStatus,NetEnabled,@{n='CollectionSource';e={'Win32_NetworkAdapter fallback'}})
        return $rows
    } catch {
        $message="Network identifiers unavailable. Primary: $primaryError / CIM fallback: $modernError / Fallback: "+$_.Exception.Message
        # Keep the final reader's type/category, including localized Windows errors.
        $exception=[Exception]::new($message,$_.Exception)
        $exception.Data['HwidFallbackFailure']=$_.Exception.Message
        throw [System.Management.Automation.ErrorRecord]::new($exception,'Hwid.NetworkFallbackFailed',$_.CategoryInfo.Category,$_.TargetObject)
    }
}
function Get-DeviceIdListInfo($Value) {
    $values=New-Object 'System.Collections.Generic.List[string]';$invalid=0
    foreach($item in $Value){
        if($null -eq $item){continue}
        if($item -isnot [string]){$invalid++;continue}
        if([string]::IsNullOrWhiteSpace(($item -replace '^[\s\x00]+|[\s\x00]+$',''))){continue}
        $values.Add($item)
    }
    [pscustomobject]@{Values=@($values.ToArray());InvalidCount=$invalid;Raw=$Value}
}
function Get-PresentDeviceRecords {
    try{
        $output=@(Get-HwidInstance -OperationTimeoutSec 20 Win32_PnPEntity -Filter 'Present = True' -Property Name,Manufacturer,PNPClass,ClassGuid,Service,Present,PNPDeviceID,HardwareID,CompatibleID,ConfigManagerErrorCode 2>&1)
        $errors=@($output | Where-Object {$_ -is [System.Management.Automation.ErrorRecord]})
        if($errors.Count){throw $errors[0]}
        $devices=@($output | Where-Object {$null -ne $_})
        if(-not $devices.Count){throw 'No present device records returned by the Win32 reader.'}
        return $devices
    }catch{
        $failure=Get-ScanFailureInfo $_
        if($failure.Code -notin @('READ-03','READ-04') -and -not (Test-ProjectionReadFailure $_)){throw}
        $primaryError=$_.Exception.Message
    }
    try{
        if(-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)){throw [NotSupportedException]::new('Get-PnpDevice present-only reader is not supported on this runtime.')}
        $output=@(Get-PnpDevice -PresentOnly -ErrorAction Stop 2>&1)
        $errors=@($output | Where-Object {$_ -is [System.Management.Automation.ErrorRecord]})
        if($errors.Count){throw $errors[0]}
        $devices=@($output | Where-Object {$null -ne $_ -and -not ($_.Present -is [bool] -and -not $_.Present)})
        if(-not $devices.Count){throw 'No present device records returned by the fallback reader.'}
        $rows=@(foreach($device in $devices){
            $name=if(-not [string]::IsNullOrWhiteSpace([string]$device.Name)){$device.Name}else{$device.FriendlyName}
            $class=if(-not [string]::IsNullOrWhiteSpace([string]$device.PNPClass)){$device.PNPClass}else{$device.Class}
            $id=if(-not [string]::IsNullOrWhiteSpace([string]$device.PNPDeviceID)){$device.PNPDeviceID}else{$device.InstanceId}
            [pscustomobject]@{Name=$name;Manufacturer=$device.Manufacturer;PNPClass=$class;ClassGuid=$device.ClassGuid;Service=$device.Service;Present=$true;PNPDeviceID=$id;HardwareID=$device.HardwareID;CompatibleID=$device.CompatibleID;ConfigManagerErrorCode=$device.ConfigManagerErrorCode;CollectionSource='Get-PnpDevice present-only fallback'}
        })
        if($null -ne $script:hwidQueryRecoveries){$script:hwidQueryRecoveries.Add([pscustomobject]@{Class='Win32_PnPEntity';Namespace='root/cimv2';Method='Get-PnpDevice present-only fallback';PrimaryFailure=$primaryError})}
        return $rows
    }catch{
        $exception=[Exception]::new(('Present device inventory unavailable. Primary: '+$primaryError+' / Fallback: '+$_.Exception.Message),$_.Exception)
        $exception.Data['HwidFallbackFailure']=$_.Exception.Message
        throw [System.Management.Automation.ErrorRecord]::new($exception,'Hwid.PresentDeviceFallbackFailed',$_.CategoryInfo.Category,$_.TargetObject)
    }
}
function Get-DriverHardwareIds {
    # All present device classes, including physical, virtual, system and peripheral nodes.
    foreach($device in (Get-PresentDeviceRecords | Sort-Object PNPClass,Name,PNPDeviceID)){
        $hardware=Get-DeviceIdListInfo $device.HardwareID;$compatible=Get-DeviceIdListInfo $device.CompatibleID
        $row=[ordered]@{Name=$device.Name;Manufacturer=$device.Manufacturer;PNPClass=$device.PNPClass;ClassGuid=$device.ClassGuid;Service=$device.Service;Present=$device.Present;DeviceInstanceId=$device.PNPDeviceID;HardwareID=$hardware.Values;CompatibleID=$compatible.Values;ConfigManagerErrorCode=$device.ConfigManagerErrorCode}
        if($hardware.InvalidCount){$row['HardwareIDReadStatus']="Invalid entries ignored: $($hardware.InvalidCount)";$row['RawHardwareID']=$hardware.Raw}
        if($compatible.InvalidCount){$row['CompatibleIDReadStatus']="Invalid entries ignored: $($compatible.InvalidCount)";$row['RawCompatibleID']=$compatible.Raw}
        if($device.CollectionSource){$row['CollectionSource']=$device.CollectionSource}
        [pscustomobject]$row
    }
}
function Get-ClassHiddenState($ClassGuid) {
    if(-not ('HwidClassVisibility' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HwidClassVisibility {
    [StructLayout(LayoutKind.Sequential)]
    struct Key { public Guid Format; public uint Id; }
    [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern uint CM_Get_Class_PropertyW(ref Guid cls, ref Key key, out uint type, byte[] data, ref uint size, uint flags);
    public static int Read(string text) {
        Guid cls;
        if (!Guid.TryParse(text, out cls)) return -1;
        Key key = new Key { Format=new Guid("259abffc-50a7-47ce-af08-68c9a7d73366"), Id=8 };
        uint type, size=1;
        byte[] data=new byte[1];
        uint result=CM_Get_Class_PropertyW(ref cls, ref key, out type, data, ref size, 0);
        if (result==0 && type==0x11 && size==1) return data[0]!=0 ? 1 : 0;
        if (result==0x25) return 0; // No value set: NoDisplayClass is not enabled.
        return -1;
    }
}
'@
    }
    try {
        $state=[HwidClassVisibility]::Read([string]$ClassGuid)
        if($state -lt 0){return $null}
        return ($state -eq 1)
    }catch{return $null}
}
function Get-NativeNodeStatus($InstanceId) {
    if([string]::IsNullOrWhiteSpace([string]$InstanceId)){return $null}
    if(-not ('HwidNodeStatus' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HwidNodeStatus {
    [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    static extern uint CM_Locate_DevNodeW(out uint node, string id, uint flags);
    [DllImport("cfgmgr32.dll", ExactSpelling=true)]
    static extern uint CM_Get_DevNode_Status(out uint status, out uint problem, uint node, uint flags);
    public static uint? Read(string id) {
        if (String.IsNullOrWhiteSpace(id)) return null;
        uint node, status, problem;
        if (CM_Locate_DevNodeW(out node, id, 0)!=0) return null;
        if (CM_Get_DevNode_Status(out status, out problem, node, 0)!=0) return null;
        return status;
    }
}
'@
    }
    try {return [HwidNodeStatus]::Read([string]$InstanceId)}catch{return $null}
}
function Get-ExtendedProblemCode($Device) {
    if($null -ne $Device.DeviceProblemCode){return $Device.DeviceProblemCode}
    return $Device.ConfigManagerErrorCode
}
function Get-ExtendedDeviceReview($Device) {
    if([string]::IsNullOrWhiteSpace([string]$Device.Name) -or $Device.Name -match '^Unknown\b'){'Device name is missing or unknown'}
    if([string]::IsNullOrWhiteSpace([string]$Device.PNPClass)){'Device class was not supplied'}
    if($Device.PresenceConflict -eq $true){'Presence sources disagreed during collection; the device may have changed'}
    elseif($null -eq $Device.Present){'Presence was not reported'}
    if($null -eq $Device.HiddenByNodeFlag){'Windows hiding flag was not read'}
    if($null -eq $Device.HiddenByClass){'Class visibility was not read'}
    $code=Get-ExtendedProblemCode $Device
    if($null -eq $code){'Device status was not supplied'}
    elseif([string]$code -notin @('0','22','45')){(Get-PnpStatus $code).Text}
}
function Format-DeviceProblemStatus($Value) {
    if($null -eq $Value){return 'Not supplied'}
    $number=[long]0
    if([long]::TryParse([string]$Value,[ref]$number) -and $number -ge -2147483648 -and $number -le 4294967295) {
        $text='0x{0:X8}' -f ($number -band [long]4294967295)
        if($number -eq 0){$text+=' (no additional status detail)'}
        return $text
    }
    return [string]$Value
}
function Get-ExtendedDeviceInventory {
    $source='Get-PnpDevice / all known nodes'
    $primaryError=$null
    try {
        $devices=@(Get-PnpDevice -ErrorAction Stop | Where-Object {$null -ne $_})
        if(-not $devices.Count){throw 'No device records returned by Get-PnpDevice.'}
    }
    catch {
        $primaryError=$_.Exception.Message
        $source='Win32_PnPEntity / unfiltered fallback'
        try {
            $devices=@(Get-HwidInstance -ClassName Win32_PnPEntity -OperationTimeoutSec 20 -Property Name,Manufacturer,PNPClass,ClassGuid,Service,Present,PNPDeviceID,HardwareID,CompatibleID,ConfigManagerErrorCode | Where-Object {$null -ne $_})
            if(-not $devices.Count){throw 'No device records returned by the CIM/WMI fallback.'}
        }catch {
            $message="Extended devices unavailable. Primary: $primaryError / Fallback: "+$_.Exception.Message
            $exception=[Exception]::new($message,$_.Exception)
            $exception.Data['HwidFallbackFailure']=$_.Exception.Message
            throw [System.Management.Automation.ErrorRecord]::new($exception,'Hwid.ExtendedFallbackFailed',$_.CategoryInfo.Category,$_.TargetObject)
        }
    }
    if(-not $devices.Count){throw 'No device records returned by Windows.'}
    $flags=New-Object 'System.Collections.Generic.Dictionary[string,uint32]' ([StringComparer]::OrdinalIgnoreCase)
    $details=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $classes=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $ids=@($devices | ForEach-Object {if($_.PNPDeviceID){[string]$_.PNPDeviceID}else{[string]$_.InstanceId}} | Where-Object {-not [string]::IsNullOrWhiteSpace($_)} | Select-Object -Unique)
    $propertyErrors=@()
    $keys=@('DEVPKEY_Device_DevNodeStatus','DEVPKEY_Device_IsPresent','DEVPKEY_Device_HardwareIds','DEVPKEY_Device_CompatibleIds','DEVPKEY_Device_Parent','DEVPKEY_Device_EnumeratorName','DEVPKEY_Device_LocationInfo','DEVPKEY_Device_BusReportedDeviceDesc','DEVPKEY_Device_ProblemCode','DEVPKEY_Device_ProblemStatus','DEVPKEY_Device_DriverInfPath')
    if($ids.Count) {
        try {
            # Process successful property rows immediately, even if a later row terminates.
            Get-PnpDeviceProperty -InstanceId $ids -KeyName $keys -ErrorAction SilentlyContinue -ErrorVariable propertyErrors | ForEach-Object {
                $property=$_
                $number=[uint32]0
                if($property.InstanceId -and $property.KeyName -in $keys -and $null -ne $property.Data) {
                    $propertyId=[string]$property.InstanceId
                    if(-not $details.ContainsKey($propertyId)){$details[$propertyId]=@{}}
                    $details[$propertyId][[string]$property.KeyName]=$property.Data
                    if($property.KeyName -eq 'DEVPKEY_Device_DevNodeStatus' -and [uint32]::TryParse([string]$property.Data,[ref]$number)) {$flags[$propertyId]=$number}
                }
            }
        }catch{$propertyErrors=@($_)}
    }
    $rows=@(foreach($device in $devices) {
        $id=if($device.PNPDeviceID){[string]$device.PNPDeviceID}else{[string]$device.InstanceId}
        $classGuid=[string]$device.ClassGuid
        if(-not $classes.ContainsKey($classGuid)){
            try {$classes[$classGuid]=Get-ClassHiddenState $classGuid}catch{$classes[$classGuid]=$null}
        }
        $properties=if($details.ContainsKey($id)){$details[$id]}else{@{}}
        $nodeFlags=$null;$nodeHidden=$null;$nodeSource='Not supplied'
        if($flags.ContainsKey($id)){$nodeFlags=$flags[$id];$nodeSource='Device properties'}
        else {
            try {$native=Get-NativeNodeStatus $id;if($null -ne $native){$nodeFlags=[uint32]$native;$nodeSource='Configuration Manager'}}catch{}
        }
        if($null -ne $nodeFlags){$nodeHidden=($nodeFlags -band [uint32]0x40000000) -ne 0}
        $present=if($device.Present -is [bool]){$device.Present}else{$null}
        $presenceSource=if($null -eq $present){'Not supplied'}else{'PnP record'}
        $presenceConflict=$false
        if($null -ne $present -and $properties['DEVPKEY_Device_IsPresent'] -is [bool] -and $present -ne $properties['DEVPKEY_Device_IsPresent']) {
            $present=$null;$presenceSource='Conflicting readings';$presenceConflict=$true
        }
        if(-not $presenceConflict -and $null -eq $present -and $properties['DEVPKEY_Device_IsPresent'] -is [bool]){$present=$properties['DEVPKEY_Device_IsPresent'];$presenceSource='Device properties'}
        $hardware=@($device.HardwareID | Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)})
        $compatible=@($device.CompatibleID | Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)})
        $hardwareSource=if($hardware.Count){'PnP record'}else{'Not supplied'}
        if(-not $hardware.Count){$hardware=@($properties['DEVPKEY_Device_HardwareIds'] | Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)});if($hardware.Count){$hardwareSource='Device properties'}}
        if(-not $compatible.Count){$compatible=@($properties['DEVPKEY_Device_CompatibleIds'] | Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)})}
        $name=$device.Name;$nameSource='PnP name'
        if([string]::IsNullOrWhiteSpace([string]$name)){$name=$device.FriendlyName;$nameSource='Friendly name'}
        if([string]::IsNullOrWhiteSpace([string]$name)){$name=$properties['DEVPKEY_Device_BusReportedDeviceDesc'];$nameSource='Bus description'}
        if([string]::IsNullOrWhiteSpace([string]$name)){$nameSource='Not supplied'}
        $problem=$null;$problemNumber=[uint32]0
        if($null -ne $properties['DEVPKEY_Device_ProblemCode'] -and [uint32]::TryParse([string]$properties['DEVPKEY_Device_ProblemCode'],[ref]$problemNumber)){$problem=$problemNumber}
        [pscustomobject][ordered]@{
            Name=$name;NameSource=$nameSource
            Manufacturer=$device.Manufacturer;PNPClass=$device.PNPClass;ClassGuid=$classGuid;Service=$device.Service
            Present=$present;PresenceSource=$presenceSource;PresenceConflict=$presenceConflict;DeviceInstanceId=$id
            HardwareID=$hardware;HardwareIdSource=$hardwareSource;CompatibleID=$compatible
            ConfigManagerErrorCode=$device.ConfigManagerErrorCode
            DeviceProblemCode=$problem;ProblemStatus=$properties['DEVPKEY_Device_ProblemStatus']
            ParentInstanceId=$properties['DEVPKEY_Device_Parent'];ParentName=$null
            Enumerator=$properties['DEVPKEY_Device_EnumeratorName'];Location=$properties['DEVPKEY_Device_LocationInfo']
            BusDescription=$properties['DEVPKEY_Device_BusReportedDeviceDesc'];DriverInfPath=$properties['DEVPKEY_Device_DriverInfPath']
            DevNodeStatus=$nodeFlags;NodeStatusSource=$nodeSource;HiddenByNodeFlag=$nodeHidden;HiddenByClass=$classes[$classGuid]
        }
    })
    $names=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $rows) {
        if(-not $row.DeviceInstanceId){continue}
        if($names.ContainsKey($row.DeviceInstanceId)){$names[$row.DeviceInstanceId]='(duplicate instance ID; parent name ambiguous)'}
        else{$names[$row.DeviceInstanceId]=[string]$row.Name}
    }
    foreach($row in $rows){if($row.ParentInstanceId -and $names.ContainsKey([string]$row.ParentInstanceId)){$row.ParentName=$names[[string]$row.ParentInstanceId]}}
    [pscustomobject]@{
        Devices=$rows
        Info=[ordered]@{
            Captured=(Get-Date).ToString('o');Source=$source;Records=$rows.Count;FallbackReason=$primaryError
            NodeFlagsRead=@($rows | Where-Object {$null -ne $_.HiddenByNodeFlag}).Count
            ClassFlagsRead=@($rows | Where-Object {$null -ne $_.HiddenByClass}).Count
            NativeStatusRecoveries=@($rows | Where-Object NodeStatusSource -eq 'Configuration Manager').Count
            ParentLinks=@($rows | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.ParentInstanceId)}).Count
            HardwareIdRecoveries=@($rows | Where-Object HardwareIdSource -eq 'Device properties').Count
            PropertyReadErrors=@($propertyErrors).Count
        }
    }
}
function Get-ExtendedDeviceGroup($Device) {
    if($Device.Present -is [bool] -and -not $Device.Present){return '2'}
    if($Device.HiddenByNodeFlag -eq $true -or $Device.HiddenByClass -eq $true){return '3'}
    if($Device.Present -eq $true -and [string](Get-ExtendedProblemCode $Device) -eq '22'){return '4'}
    if($Device.Present -eq $true){return '5'}
    return '6'
}
function Show-ExtendedDeviceReport {
    Reset-UiPage;Start-UiReport
    Add-ReportBookmark '1'
    Write-Heading 'EXTENDED DEVICE SCAN / HIDDEN & REMEMBERED'
    Write-PnpValue 'Controls' '1 Summary / 2 Disconnected / 3 Hidden / 4 Disabled / 5 Present / 6 Unknown presence / 7 Unknown & review. 0 or Enter = menu.' $palette.Heading
    $info=$report['Extended scan info']
    Write-PnpValue 'Captured' (Format-ScanTime $info.Captured) $palette.Muted
    Write-PnpValue 'Source' $info.Source $palette.Muted
    $devices=@($report['Extended device inventory'])
    Write-PnpValue 'Coverage' ("$($devices.Count) known nodes / $($info.NodeFlagsRead) with node flags / $($info.ClassFlagsRead) with class flags") $palette.Text
    Write-PnpValue 'Recovered detail' ("$([int]$info.NativeStatusRecoveries) native status reads / $([int]$info.HardwareIdRecoveries) model-ID lists / $([int]$info.ParentLinks) parent links") $palette.Text
    Write-PnpValue 'Meaning' 'Hidden flags and disconnected records can be normal. They do not prove that hardware is physically hidden or unsafe.' $palette.Muted
    Write-PnpValue 'Limits' 'Only records exposed by Windows are visible. Unread flags remain unknown; missing serials cannot be recovered from absent hardware.' $palette.Muted
    Write-PnpValue 'Parent links' 'Windows-reported topology; remembered devices may point to the root if their earlier parent is gone.' $palette.Muted
    Write-PnpValue 'Keep results' 'Main [6] saves TXT + JSON. Full PC rescans refresh this catalog too; [9] > [4] refreshes it separately.' $palette.Muted
    $groups=[ordered]@{'2'='NOT PRESENT / REMEMBERED';'3'='HIDDEN BY WINDOWS FLAG OR CLASS';'4'='DISABLED / PRESENT';'5'='OTHER PRESENT NODES';'6'='PRESENCE UNKNOWN'}
    foreach($key in $groups.Keys) {
        Write-PnpValue ('['+$key+'] '+$groups[$key]) (@($devices | Where-Object {(Get-ExtendedDeviceGroup $_) -eq $key}).Count) $palette.Text
    }
    $review=@($devices | Where-Object {@(Get-ExtendedDeviceReview $_).Count -gt 0})
    Write-PnpValue '[7] UNKNOWN / REVIEW' ("$($review.Count) records; overlaps the groups above") $palette.Warn
    foreach($key in $groups.Keys) {
        Add-ReportBookmark $key
        $items=@($devices | Where-Object {(Get-ExtendedDeviceGroup $_) -eq $key})
        Write-Heading ($groups[$key]+' / '+$items.Count)
        if($items.Count){Show-PnpRecords $items -Full -Extended}
        else {Write-PnpValue 'Result' 'No records in this group.' $palette.Muted}
    }
    Add-ReportBookmark '7'
    Write-Heading ('UNKNOWN / REVIEW / '+$review.Count)
    Write-PnpValue 'Read this first' 'Unread fields and unknown names can be normal. Driver error codes and the specific missing fields are shown separately.' $palette.Muted
    if($review.Count){Show-PnpRecords $review -Full -Extended}
    else{Write-PnpValue 'Result' 'No records need this detail review.' $palette.Muted}
}
function Start-ExtendedDeviceScan {
    $cursor=$null;$queryWorker=$null
    try {
        if($ownedConsole -and -not $redirected){try{$cursor=[Console]::CursorVisible;[Console]::CursorVisible=$false}catch{}}
        Reset-UiPage;Start-UiReport
        Write-Heading 'READING EXTENDED DEVICE INVENTORY'
        Write-PnpValue 'Scope' 'All known PnP nodes, including non-present records, plus Windows hiding flags.' $palette.Muted
        $line=Start-ScanLine '  Devices and visibility flags: '
        $clock=[Diagnostics.Stopwatch]::StartNew()
        if($ownedConsole -and -not $redirected){try{$script:scanQueryWorker=New-ScanQueryWorker;$queryWorker=$script:scanQueryWorker}catch{}}
        $result=Invoke-ScanQuery {Get-ExtendedDeviceInventory} {Update-ScanWaiting $line $clock.Elapsed.TotalSeconds}
        if($null -eq $result -or -not @($result.Devices).Count){throw 'No device records captured.'}
        $report['Extended device inventory']=@($result.Devices)
        $report['Extended scan info']=$result.Info
        $report['Report info']['ExtendedStatus']='Refreshed'
        foreach($field in @('ExtendedAttempted','ExtendedFailureCode','ExtendedFailureReason','ExtendedNextStep')){$report['Report info'].Remove($field)}
        for($i=$warnings.Count-1;$i -ge 0;$i--){if($warnings[$i].StartsWith('Extended device inventory: ')){$warnings.RemoveAt($i)}}
        $report['Warnings']=@($warnings.ToArray())
    }catch {
        $failure=Get-ScanFailureInfo $_
        $report['Report info']['ExtendedStatus']='Unavailable'
        $report['Report info']['ExtendedAttempted']=(Get-Date).ToString('o')
        $report['Report info']['ExtendedFailureCode']=$failure.Code
        $report['Report info']['ExtendedFailureReason']=$failure.Reason
        $report['Report info']['ExtendedNextStep']=$failure.Action.Replace('[9] > [1]','[9] > [4]')
        for($i=$warnings.Count-1;$i -ge 0;$i--){if($warnings[$i].StartsWith('Extended device inventory: ')){$warnings.RemoveAt($i)}}
        $warnings.Add('Extended device inventory: '+$failure.Details)
        $report['Warnings']=@($warnings.ToArray())
        Write-PnpValue 'EXTENDED-01 / not completed' ($failure.Reason+' ['+$failure.Code+']') $palette.Warn
        Write-PnpValue 'Technical detail' $failure.Details $palette.Muted
        Write-PnpValue 'Retry' 'Use [9] > [4] again. Existing normal-scan data is unchanged.' $palette.Muted
        if($report.Contains('Extended device inventory') -and $report.Contains('Extended scan info')){Write-PnpValue 'Previous catalog kept' ('Earlier capture: '+(Format-ScanTime $report['Extended scan info'].Captured)) $palette.Warn}
        return
    }finally{
        if($null -ne $queryWorker){$queryWorker.Dispose();$script:scanQueryWorker=$null}
        if($null -ne $clock){$clock.Stop()}
        if($null -ne $cursor){try{[Console]::CursorVisible=$cursor}catch{}}
    }
    Show-ExtendedDeviceReport
}
function Get-PnpStatus($Code) {
    $number=[uint32]0
    if($null -eq $Code -or -not [uint32]::TryParse([string]$Code,[ref]$number)) {
        return [pscustomobject]@{Text='Status not supplied';Quality='Unknown';Code=$null}
    }
    $description=switch($number) {
        0 {'Working'}; 10 {'Cannot start'}; 12 {'Resource conflict'}; 14 {'Restart needed'}
        18 {'Reinstall driver'}; 19 {'Configuration problem'}; 21 {'Being removed'}
        22 {'Disabled'}; 24 {'Not present or driver incomplete'}; 28 {'Driver not installed'}
        31 {'Driver cannot load'}; 43 {'Windows stopped this device'}; 45 {'Not connected'}
        default {'Device issue'}
    }
    [pscustomobject]@{Text=('{0} (code {1})' -f $description,$number);Quality=$(if($number -eq 0){'OK'}else{'Review'});Code=$number}
}
function Get-PnpGroups { @('GRAPHICS','NETWORK','STORAGE','USB','INPUT','AUDIO','BLUETOOTH','CAMERAS','MONITORS','SYSTEM & FIRMWARE','OTHER DEVICES') }
function Get-PnpGroup($Device) {
    switch([string]$Device.PNPClass) {
        'Display' {return 'GRAPHICS'}; 'Net' {return 'NETWORK'}
        'DiskDrive' {return 'STORAGE'}; 'SCSIAdapter' {return 'STORAGE'}; 'HDC' {return 'STORAGE'}
        'USB' {return 'USB'}
    }
    switch([string]$Device.PNPClass) {
        'Keyboard' {return 'INPUT'}; 'Mouse' {return 'INPUT'}; 'HIDClass' {return 'INPUT'}
        'MEDIA' {return 'AUDIO'}; 'AudioEndpoint' {return 'AUDIO'}
        'Bluetooth' {return 'BLUETOOTH'}; 'Camera' {return 'CAMERAS'}; 'Image' {return 'CAMERAS'}
        'Monitor' {return 'MONITORS'}
        'System' {return 'SYSTEM & FIRMWARE'}; 'Computer' {return 'SYSTEM & FIRMWARE'}
        'Processor' {return 'SYSTEM & FIRMWARE'}; 'Firmware' {return 'SYSTEM & FIRMWARE'}
        'SecurityDevices' {return 'SYSTEM & FIRMWARE'}; 'Memory' {return 'SYSTEM & FIRMWARE'}
    }
    # Prefer a known device function over its transport (USB cameras are cameras).
    if([string]$Device.DeviceInstanceId -match '^USB\\'){return 'USB'}
    return 'OTHER DEVICES'
}
function Get-PnpIssues($Devices) {
    if(-not (Test-SectionReadable $Devices)){return}
    $duplicates=@($Devices | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.DeviceInstanceId)} |
        Group-Object -Property {([string]$_.DeviceInstanceId).Trim().ToUpperInvariant()} | Where-Object Count -gt 1)
    $duplicateKeys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($duplicate in $duplicates){[void]$duplicateKeys.Add(([string]$duplicate.Group[0].DeviceInstanceId).Trim())}
    foreach($device in $Devices) {
        if($null -eq $device){continue}
        # Repeated node rows are one conflict; keep their status observations below.
        if($duplicateKeys.Contains(([string]$device.DeviceInstanceId).Trim())){continue}
        if([string]::IsNullOrWhiteSpace([string]$device.DeviceInstanceId)) {
            [pscustomobject]@{Device=$device.Name;InstanceId=$device.DeviceInstanceId;Code=$null;Message='Device instance ID was not supplied; this node cannot be matched reliably.';Kind='MissingInstance'}
        }
        if($device.HardwareIDReadStatus -match '^Invalid' -or $device.CompatibleIDReadStatus -match '^Invalid'){
            [pscustomobject]@{Device=$device.Name;InstanceId=$device.DeviceInstanceId;Code=$null;Message='Some model/compatible ID entries were invalid. Valid strings were retained; raw entries are in Main [5].';Kind='InvalidIdList'}
        }
        $status=Get-PnpStatus $device.ConfigManagerErrorCode
        if($status.Quality -eq 'Review') {
            [pscustomobject]@{Device=$device.Name;InstanceId=$device.DeviceInstanceId;Code=$status.Code;Message=$status.Text;Kind=$(if($status.Code -eq 12){'ResourceConflict'}else{'Status'})}
        } elseif($status.Quality -eq 'Unknown') {
            [pscustomobject]@{Device=$device.Name;InstanceId=$device.DeviceInstanceId;Code=$null;Message='Windows device status was not read; condition is unknown.';Kind='UnknownStatus'}
        }
    }
    # Hardware IDs describe models, so sharing them is expected. Only instance IDs
    # should identify a unique device node within this single scan.
    foreach($duplicate in $duplicates) {
        $statuses=@($duplicate.Group | ForEach-Object {(Get-PnpStatus $_.ConfigManagerErrorCode).Text} | Select-Object -Unique)
        [pscustomobject]@{Device=$duplicate.Group[0].Name;InstanceId=$duplicate.Group[0].DeviceInstanceId;Statuses=$statuses;Message=('Repeated instance ID in scan ('+$duplicate.Count+' records): '+$duplicate.Group[0].DeviceInstanceId);Kind='Duplicate'}
    }
}
function Write-PnpLine($Text,$Color) {
    if($ownedConsole -and -not $redirected) {
        try {
            if([Console]::BufferHeight-[Console]::CursorTop -lt 16 -and [Console]::BufferHeight -lt 32766) {
                [Console]::SetBufferSize([Console]::BufferWidth,[math]::Min(32766,[Console]::BufferHeight+512))
            }
        } catch {}
    }
    Write-Host $Text -ForegroundColor $Color
}
function Write-PnpValue($Label,$Value,$Color) {
    $width=96
    try {if([Console]::WindowWidth -gt 0){$width=[math]::Max(8,[Console]::WindowWidth-2)}}catch{}
    $text=([string]$Value -replace '[\x00-\x1f\x7f]',' ')
    if([string]::IsNullOrWhiteSpace($text)){$text='(not supplied)'}
    $safeLabel=([string]$Label -replace '[\x00-\x1f\x7f]',' ')
    $text='    '+$safeLabel+': '+$text
    while($text.Length -gt $width) {
        Write-PnpLine ($text.Substring(0,$width)) $Color
        $text='    '+$text.Substring($width)
    }
    Write-PnpLine $text $Color
}
function Show-PnpRecords($Devices,[switch]$Full,[switch]$Extended) {
    if(-not (Test-SectionReadable $Devices)) {Show-Records $Devices;return}
    foreach($group in (Get-PnpGroups)) {
        $items=@($Devices | Where-Object {(Get-PnpGroup $_) -eq $group} | Sort-Object Name,DeviceInstanceId)
        if(-not $items.Count){continue}
        Write-Heading ("$group / $($items.Count) device(s)")
        $index=0
        foreach($device in $items) {
            $index++
            $status=Get-PnpStatus $(if($Extended){Get-ExtendedProblemCode $device}else{$device.ConfigManagerErrorCode})
            $color=if($status.Quality -eq 'OK'){$palette.Good}elseif($status.Quality -eq 'Review'){$palette.Warn}else{$palette.Muted}
            if($Extended -and $device.Present -is [bool] -and -not $device.Present){$status=[pscustomobject]@{Text='Not present / remembered by Windows'};$color=$palette.Muted}
            $name=if([string]::IsNullOrWhiteSpace([string]$device.Name)){'Unnamed device'}else{$device.Name}
            Write-PnpValue ("[$index] "+$name) $status.Text $color
            $hardware=@($device.HardwareID | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)})
            $compatible=@($device.CompatibleID | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)})
            Write-PnpValue 'Instance' $device.DeviceInstanceId $palette.Muted
            if($Extended) {
                Write-PnpValue 'Present now' $(if($null -eq $device.Present){'Unknown'}elseif($device.Present){'Yes'}else{'No / remembered record'}) $palette.Muted
                foreach($field in @('HiddenByNodeFlag','HiddenByClass')) {
                    Write-PnpValue $(if($field -eq 'HiddenByNodeFlag'){'Windows hiding flag'}else{'Hidden device class'}) $(if($null -eq $device.$field){'Unknown / not read'}elseif($device.$field){'Yes'}else{'No'}) $palette.Muted
                }
                foreach($reason in @(Get-ExtendedDeviceReview $device)){Write-PnpValue 'DETAIL REVIEW' $reason $palette.Warn}
                if($device.NameSource){Write-PnpValue 'Name read from' $device.NameSource $palette.Muted}
                if($device.NodeStatusSource){Write-PnpValue 'Status read from' $device.NodeStatusSource $palette.Muted}
                if($device.HardwareIdSource){Write-PnpValue 'IDs read from' $device.HardwareIdSource $palette.Muted}
                Write-PnpValue 'Parent device' $device.ParentName $palette.Muted
                Write-PnpValue 'Parent instance' $device.ParentInstanceId $palette.Muted
                Write-PnpValue 'Enumerator / bus' $device.Enumerator $palette.Muted
                Write-PnpValue 'Location' $device.Location $palette.Muted
                Write-PnpValue 'Bus description' $device.BusDescription $palette.Muted
                Write-PnpValue 'Driver INF' $device.DriverInfPath $palette.Muted
                Write-PnpValue 'Problem status' (Format-DeviceProblemStatus $device.ProblemStatus) $palette.Muted
            }
            if($Full) {
                Write-PnpValue 'Manufacturer' $device.Manufacturer $palette.Muted
                Write-PnpValue 'Windows class' $device.PNPClass $palette.Muted
                Write-PnpValue 'Class GUID' $device.ClassGuid $palette.Muted
                Write-PnpValue 'Driver service' $device.Service $palette.Muted
                if(-not $hardware.Count){Write-PnpValue 'Hardware ID' '' $palette.Muted}
                for($i=0;$i -lt $hardware.Count;$i++){Write-PnpValue ("Hardware ID "+($i+1)) $hardware[$i] $palette.Text}
                if(-not $compatible.Count){Write-PnpValue 'Compatible ID' '(none reported; can be normal)' $palette.Muted}
                for($i=0;$i -lt $compatible.Count;$i++){Write-PnpValue ("Compatible ID "+($i+1)) $compatible[$i] $palette.Muted}
            } else {
                $primary=if($hardware.Count){$hardware[0]}else{'(not supplied)'}
                Write-PnpValue ("Hardware ID ["+$hardware.Count+"]") $primary $palette.Text
            }
            Write-Host ''
        }
    }
}
function Show-DriverHardwareIds {
    Start-UiReport
    Write-Heading 'ALL PRESENT DEVICE IDs / PNP'
    Write-Host '  Reading connected devices...' -ForegroundColor $palette.Muted
    # Refresh every visit: hot-plugged devices and changed driver states must not stay cached.
    for($i=$warnings.Count-1;$i -ge 0;$i--){if($warnings[$i].StartsWith('PnP hardware IDs: ')){$warnings.RemoveAt($i)}}
    try {
        $devices=@(Get-DriverHardwareIds | Where-Object {$null -ne $_})
        if(-not $devices.Count){throw 'No matching present devices were returned.'}
        $report['PnP hardware IDs']=$devices
    } catch {
        $message=$_.Exception.Message
        $failure=Get-ScanFailureInfo $_
        $report['PnP hardware IDs']=@{Unavailable=$message;FailureCode=$failure.Code;FailureReason=$failure.Reason;NextStep=$failure.Action}
        $warnings.Add("PnP hardware IDs: $message")
    }
    $report['Warnings']=@($warnings.ToArray())
    $devices=$report['PnP hardware IDs']
    if(-not (Test-SectionReadable $devices)) {
        Show-Records $devices
        Write-Host '  Reopen [3] > [6] to retry.' -ForegroundColor $palette.Warn
        return
    }
    $problems=@(Get-PnpIssues $devices)
    Write-Host ("  $(@($devices).Count) devices / $($problems.Count) item(s) to review") -ForegroundColor $palette.Text
    Write-Host '  Physical and virtual device nodes, across every present Windows device class.' -ForegroundColor $palette.Muted
    Write-Host '  Model IDs can be shared. Instance IDs identify device nodes.' -ForegroundColor $palette.Muted
    Write-Host '  Compact view: first hardware ID. Full lists: main [5]. Save: main [6].' -ForegroundColor $palette.Muted
    foreach($problem in $problems){Write-PnpValue 'REVIEW' ($problem.Device+' / '+$problem.Message) $palette.Warn}
    Show-PnpRecords $devices
}
function Show-Help {
    Start-UiReport
    Write-Heading 'HELP & COLOR KEY'
    Write-PnpValue 'Menu' 'Type one digit 0-9, then Enter. Empty Enter is ignored.' $palette.Text
    Write-PnpValue 'Compatibility' 'Needs Windows with PowerShell 5.1 or 7 in FullLanguage. Missing optional commands/providers are reported as unavailable. Full report includes runtime details.' $palette.Text
    Write-PnpValue 'Alternative launcher' 'Start-HWID.ps1 can launch this checker without cmd.exe when PowerShell is available. Keep both files together.' $palette.Muted
    Write-PnpValue 'Rescan [9] > [1]' 'Refresh all 17 sections. The previous snapshot stays available in [9] > [3] for change review. Saving is manual.' $palette.Text
    Write-PnpValue 'Extended [9] > [4]' 'Reads known nodes, hiding flags, parent links, bus and driver details. Use [7] inside that view for unknown/review reasons.' $palette.Text
    Write-PnpValue 'Long pages' 'Wheel / Up Down / PgUp PgDn / Home End. Enter returns to menu.' $palette.Text
    Write-PnpValue 'Colors' 'Cyan: navigate. Green: found/working. Amber: review. Red: failed action or invalid input.' $palette.Muted
    Write-PnpValue 'Motion' 'Next sweeps forward, Back reverses, Exit closes inward. Set HWID_NO_ANIMATION=1 before launch to disable.' $palette.Muted
    Write-Heading 'UNDERSTAND YOUR IDs'
    Write-PnpValue 'Quick IDs [2]' 'Short serial-number table. Full values are in [5] or saved reports.' $palette.Text
    Write-PnpValue 'Deep IDs [3] > [6]' 'All present device classes are scanned at startup. This view refreshes their names, status and IDs.' $palette.Text
    Write-PnpValue 'Hardware IDs' 'Driver-match model IDs can be shared by multiple devices.' $palette.Muted
    Write-PnpValue 'Instance IDs' 'Device nodes on this Windows system; bus location can affect them.' $palette.Muted
    Write-PnpValue 'Other IDs' 'ProcessorId is CPU signature/features; MachineGuid is Windows installation data; volume serials identify formatted volumes.' $palette.Muted
    Write-Heading 'REPORTS & REVIEW'
    Write-PnpValue 'Save [6]' 'Saves complete TXT + JSON, including deep IDs after viewing them.' $palette.Text
    Write-PnpValue 'Compare [7]' 'Choose a saved JSON. Moving hardware can change slot labels. Unreadable sections and missing/default fields are skipped.' $palette.Text
    Write-PnpValue 'Review [4]' 'Missing/default IDs can be normal. MBR/RAW disks do not require GPT IDs; virtual adapters may have no permanent MAC.' $palette.Muted
    Write-PnpValue 'PC-wide coverage' 'Normal scan: present nodes plus firmware, disks, partitions, volumes and monitors. Extended scan: known disconnected/hidden records. Manufacturers may omit serials.' $palette.Muted
    Write-PnpValue 'Keep in mind' 'Windows-reported does not guarantee authentic or unique. Reports contain identifiers; share carefully.' $palette.Muted
}
$identifierPattern = '^(SerialNumber|IdentifyingNumber|UUID|ProcessorId|MachineGuid|VolumeSerialNumber|UniqueId|Guid|MacAddress|PermanentAddress|InterfaceGuid|PNPDeviceID|SMBIOSAssetTag)$'
function Normalize-IdentifierText($Value) {
    # Normalize only padding for evaluation. Original report values stay untouched.
    return ([string]$Value -replace '^[\s\x00]+|[\s\x00]+$','')
}
function Get-Quality($Value) {
    $text = Normalize-IdentifierText $Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^(not provided|not set|not defined|unspecified)$') { return 'Missing' }
    if ($text -match '^(unknown|none|n/a|not (specified|available|applicable)|default string|to be filled.*|system serial number|0+|f+)$' -or $text -match '^[0:{} -]+$' -or $text -match '^[fF:{} -]+$') { return 'Placeholder' }
    return 'Reported'
}
function Show-Records($Records,$SectionName='') {
    $Records=@($Records | Where-Object {$null -ne $_})
    if(-not $Records.Count) {
        Write-PnpValue 'Unavailable' 'No records captured for this section.' $palette.Warn
        return
    }
    $recordIndex = 0
    foreach ($record in $Records) {
        $recordIndex++
        $title=''
        if($SectionName -eq 'Disk partitions') {$title="Disk $($record.DiskNumber) / Partition $($record.PartitionNumber)"}
        else {
            foreach($field in @('FriendlyName','Name','Model','DeviceLocator','DeviceID','Section')) {
                $candidate=if($record -is [System.Collections.IDictionary]){$record[$field]}else{$record.$field}
                if(-not [string]::IsNullOrWhiteSpace([string]$candidate)){$title=[string]$candidate;break}
            }
        }
        Write-PnpValue ("Record $recordIndex of $($Records.Count)") $title $palette.Muted
        $properties = if ($record -is [System.Collections.IDictionary]) {
            foreach ($key in $record.Keys) { [pscustomobject]@{Name=$key; Value=$record[$key]} }
        } elseif ($record -is [string]) {
            [pscustomobject]@{Name='Message'; Value=$record}
        } else { $record.PSObject.Properties }
        foreach ($property in $properties) {
            if($property.Value -is [array]) {
                Write-PnpValue (Get-FieldLabel $property.Name) ("$($property.Value.Count) value(s)") $palette.Text
                if(-not $property.Value.Count){Write-PnpValue '' '(none reported)' $palette.Muted}
                $valueIndex=0
                foreach($item in $property.Value) {
                    $valueIndex++
                    Write-PnpValue ("[$valueIndex]") (Format-FieldValue $item) $palette.Text
                }
                continue
            }
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
            if($SectionName -eq 'Disk partitions' -and $property.Name -eq 'DriveLetter' -and $value -eq '(not provided)') {
                if($record.DriveLetterReadStatus -eq 'Invalid value'){$value='Unknown / invalid provider value; inspect Raw drive-letter value';$color=$palette.Warn}
                else{$value='None assigned (normal for some system/recovery partitions)';$color=$palette.Muted}
            }
            Write-PnpValue (Get-FieldLabel $property.Name) ($value+$status) $color
        }
        Write-Host ''
    }
}
function Get-SectionIdentifierInfo($Name,$Records) {
    if($Name -eq 'PnP hardware IDs') {
        $nodes=@($Records | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.DeviceInstanceId)}).Count
        $missingNodes=@($Records | Where-Object {$null -ne $_ -and [string]::IsNullOrWhiteSpace([string]$_.DeviceInstanceId)}).Count
        $models=@($Records | Where-Object {@($_.HardwareID | Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace(($_ -replace '^[\s\x00]+|[\s\x00]+$',''))}).Count -gt 0}).Count
        $review=@(Get-PnpIssues $Records).Count
        $text="$nodes instance IDs; $models with model IDs"
        if($missingNodes){$text+="; $missingNodes instance IDs missing"}
        $repaired=@($Records | Where-Object {$_.HardwareIDReadStatus -match '^Invalid' -or $_.CompatibleIDReadStatus -match '^Invalid'}).Count
        if($repaired){$text+="; $repaired nodes with invalid ID entries"}
        if($review){$text+="; $review review"}
        if(@($Records | Where-Object CollectionSource -match 'fallback').Count){$text+=' / fallback reader'}
        return [pscustomobject]@{Text=$text;Tag=$(if($review){'CHECK'}else{'READ'});Color=$(if($review){'Warn'}else{'Good'});Found=$nodes;Missing=$missingNodes;Default=0}
    }
    $found=0;$missing=0;$defaults=0
    foreach($record in $Records) {
        foreach($property in $record.PSObject.Properties) {
            if($property.Name -notmatch $identifierPattern){continue}
            switch(Get-FieldQuality $property.Name $property.Value $record) {
                'Reported' {$found++}; 'Missing' {$missing++}; 'Placeholder' {$defaults++}
            }
        }
    }
    if(-not ($found+$missing+$defaults)){return [pscustomobject]@{Text='Inventory details';Tag='READ';Color='Muted';Found=0;Missing=0;Default=0}}
    $text="IDs: $found found"
    if($missing){$text+=", $missing missing"}
    if($defaults){$text+=", $defaults default"}
    if($Name -eq 'Network adapters' -and @($Records | Where-Object CollectionSource -match 'fallback').Count){$text+=' / fallback reader'}
    $review=$missing+$defaults
    [pscustomobject]@{Text=$text;Tag=$(if($review){'CHECK'}else{'READ'});Color=$(if($review){'Warn'}else{'Good'});Found=$found;Missing=$missing;Default=$defaults}
}
function Get-SectionIdentifierSummary($Name,$Records) {return (Get-SectionIdentifierInfo $Name $Records).Text}
function Get-ScanProgressText([int]$Completed,[int]$Total,[double]$Seconds,[int]$Width=96) {
    $Total=[math]::Max(1,$Total)
    $Completed=[math]::Max(0,[math]::Min($Completed,$Total))
    if($Width -lt 40){return ('{0}/{1} / {2:0}%' -f $Completed,$Total,(100*$Completed/$Total))}
    if($Width -lt 70){return ('{0}/{1} finished / {2:0}% / {3:0.0}s' -f $Completed,$Total,(100*$Completed/$Total),[math]::Max(0,$Seconds))}
    $filled=[int][math]::Floor(20*$Completed/$Total)
    return ('[{0}{1}] {2,3:0}% / {3} of {4} finished / {5:0.0}s elapsed' -f ('#'*$filled),('-'*(20-$filled)),(100*$Completed/$Total),$Completed,$Total,[math]::Max(0,$Seconds))
}
function Update-ScanProgress([int]$Completed=$script:scanStep) {
    if($null -eq $script:scanProgressState -or $null -eq $script:scanProgressClock){return}
    try {
        $left=[Console]::CursorLeft;$top=[Console]::CursorTop
        if([Console]::WindowWidth -ne $script:scanProgressState.Width){return}
        $text='  '+(Get-ScanProgressText $Completed $scanTotal $script:scanProgressClock.Elapsed.TotalSeconds ([Console]::WindowWidth-3))
        $text=Limit-TableText $text ([Console]::WindowWidth-1)
        [Console]::SetCursorPosition(0,$script:scanProgressState.Top)
        Write-Host ($text.PadRight([Console]::WindowWidth-1)) -ForegroundColor $palette.Heading -NoNewline
    }catch{}finally{
        if($null -ne $top){try{[Console]::SetCursorPosition($left,$top)}catch{}}
    }
}
function Start-ScanLine($Prefix) {
    Write-Host $Prefix -ForegroundColor $palette.Muted -NoNewline
    if($ownedConsole -and -not $redirected) {
        try {
            if([Console]::WindowWidth-[Console]::CursorLeft -lt 22){Write-Host ''}
            $state=[pscustomobject]@{Left=[Console]::CursorLeft;Top=[Console]::CursorTop;Width=[Console]::WindowWidth;LastLength=12}
            Write-Host '[READING...]' -ForegroundColor $palette.Muted -NoNewline
            return $state
        }catch{}
    }
    return $null
}
function Update-ScanWaiting($State,[double]$Seconds) {
    if($null -eq $State -or $Seconds -lt 5){return}
    try {
        $left=[Console]::CursorLeft;$top=[Console]::CursorTop
        if([Console]::WindowWidth -ne $State.Width){return}
        $text=Limit-TableText ('[WAITING {0:0.0}s] Reading Windows provider' -f $Seconds) ($State.Width-$State.Left-1)
        [Console]::SetCursorPosition($State.Left,$State.Top)
        Write-Host $text -ForegroundColor $palette.Muted -NoNewline
        $State.LastLength=$text.Length
    }catch{}finally{
        if($null -ne $top){try{[Console]::SetCursorPosition($left,$top)}catch{}}
    }
}
function Complete-ScanLine($State,$Name,$Text,$Color) {
    if($null -ne $State) {
        try {
            if([Console]::WindowWidth -ne $State.Width){throw 'Console resized'}
            [Console]::SetCursorPosition($State.Left,$State.Top)
            if($State.LastLength -gt $Text.Length){$Text=$Text.PadRight($State.LastLength)}
        }catch{Write-Host '';Write-Host ($Name+': ') -ForegroundColor $palette.Muted -NoNewline}
    }
    Write-Host $Text -ForegroundColor $Color
}
function New-ScanQueryWorker {
    $worker=[PowerShell]::Create()
    try {
        $setup=New-Object Text.StringBuilder
        [void]$setup.AppendLine('$ErrorActionPreference="Stop"')
        # Only collection helpers run here; UI and snapshot state stay on the main thread.
        foreach($name in @('GiB','Get-MonitorTextResult','Convert-MonitorText','Get-MonitorIdentifiers','Get-StorageCodeName','Get-StorageIdentifiers','Get-PartitionLetterInfo','Get-PartitionIdentifiers','Format-NetworkLinkSpeed','Format-NetworkStatus','Get-NetworkAddressInfo','Get-NetworkIdentifiers','Get-DeviceIdListInfo','Get-PresentDeviceRecords','Get-DriverHardwareIds','Get-ScanFailureInfo','Test-ProjectionReadFailure','Get-HwidInstance','Get-ClassHiddenState','Get-NativeNodeStatus','Get-ExtendedDeviceInventory','Get-CimInstance','Get-NetAdapter','Get-ItemProperty','Get-PnpDevice','Get-PnpDeviceProperty','Get-WmiObject')) {
            $function=Get-Item -LiteralPath ('Function:\'+$name) -ErrorAction SilentlyContinue
            if($null -ne $function -and -not $function.ModuleName){[void]$setup.AppendLine(('function '+$name+' {'+$function.Definition+'}'))}
        }
        [void]$worker.AddScript($setup.ToString()).Invoke()
        if($worker.HadErrors){throw 'Could not initialize the query worker.'}
        $worker.Commands.Clear()
        return $worker
    }catch{$worker.Dispose();throw}
}
function Invoke-ScanQuery([scriptblock]$Query,[scriptblock]$Pulse) {
    $script:lastQueryRecoveries=@()
    $script:lastQueryFeedbackFailure=$null
    if($null -eq $script:scanQueryWorker) {
        # An explicit -ErrorAction Continue can override the query preference.
        # Capture errors that escape the query so partial data is never an all-clear.
        $script:hwidQueryRecoveries=New-Object 'System.Collections.Generic.List[object]'
        try {$output=@(& $Query 2>&1)}finally{$script:lastQueryRecoveries=@($script:hwidQueryRecoveries.ToArray());$script:hwidQueryRecoveries=$null}
        $uncaught=@($output | Where-Object {$_ -is [System.Management.Automation.ErrorRecord]})
        if($uncaught.Count){throw $uncaught[0]}
        return $output
    }
    # Reuse the initialized session, but give every query its own output/error buffers.
    $worker=[PowerShell]::Create()
    $pending=$null
    try {
        $worker.Runspace=$script:scanQueryWorker.Runspace
        [void]$worker.AddScript('$ErrorActionPreference="Stop";$script:hwidQueryRecoveries=New-Object "System.Collections.Generic.List[object]";$collected=@(& {'+$Query.ToString()+'});[pscustomobject]@{Records=$collected;Recoveries=@($script:hwidQueryRecoveries.ToArray())}')
        $pending=$worker.BeginInvoke()
        $feedbackAvailable=$true
        while(-not $pending.IsCompleted) {
            if($pending.AsyncWaitHandle.WaitOne(100)){break}
            if($Pulse -and $feedbackAvailable){
                try{& $Pulse | Out-Null}catch{$feedbackAvailable=$false;$script:lastQueryFeedbackFailure=$_.Exception.Message}
            }
        }
        try {$output=$worker.EndInvoke($pending)}catch {
            # EndInvoke adds a method-call wrapper; retain the provider's ErrorRecord.
            $sourceFailure=$_;$nested=$_.Exception.InnerException
            for($depth=0;$null -ne $nested -and $depth -lt 16;$depth++) {
                if($nested -is [System.Management.Automation.RuntimeException] -and $null -ne $nested.ErrorRecord){$sourceFailure=$nested.ErrorRecord;break}
                $nested=$nested.InnerException
            }
            throw $sourceFailure
        }
        if($worker.Streams.Error.Count){throw $worker.Streams.Error[0]}
        $script:lastQueryRecoveries=@($output[0].Recoveries)
        return $output[0].Records
    }finally{
        if($null -ne $pending -and $pending.IsCompleted){$pending.AsyncWaitHandle.Close()}
        $worker.Dispose()
    }
}
function Get-ScanFailureInfo($Failure) {
    $details=[string]$Failure
    $classificationDetails=$null
    $category='';$kind='Other'
    $exception=$null
    if($Failure -is [System.Management.Automation.ErrorRecord]) {
        $details=$Failure.Exception.Message;$category=[string]$Failure.CategoryInfo.Category;$exception=$Failure.Exception
    } elseif($Failure -is [Exception]) {$details=$Failure.Message;$exception=$Failure}
    # Typed errors and standard HRESULTs remain useful on non-English Windows.
    for($depth=0;$null -ne $exception -and $depth -lt 16;$depth++) {
        if($exception.Data.Contains('HwidFallbackFailure')){$classificationDetails=[string]$exception.Data['HwidFallbackFailure']}
        $hresult=$exception.HResult.ToString('X8')
        $cimStatus=if($exception.PSObject.Properties['StatusCode']){[string]$exception.StatusCode}else{''}
        if($exception -is [UnauthorizedAccessException] -or $hresult -in @('80070005','80041003') -or $cimStatus -eq 'AccessDenied'){$kind='Access';break}
        if($exception -is [TimeoutException] -or $hresult -eq '800705B4'){$kind='Timeout';break}
        if($exception -is [IO.InvalidDataException]){$kind='Data';break}
        if($exception -is [NotSupportedException] -or $exception -is [System.Management.Automation.CommandNotFoundException] -or $hresult -in @('8004100E','80041010','80041013','800706BA') -or $cimStatus -in @('InvalidClass','InvalidNamespace','NotSupported')){$kind='Provider';break}
        $exception=$exception.InnerException
    }
    if($kind -eq 'Other') {
        # Both reader messages stay in Details; classify the final reader alone.
        $reasonText=if($null -ne $classificationDetails){$classificationDetails}else{$details}
        if($category -eq 'PermissionDenied' -or $reasonText -match '(?i)access\s+(is\s+)?denied|unauthori[sz]ed|permission denied|insufficient privileges?|0x80070005|0x80041003'){$kind='Access'}
        elseif($category -eq 'OperationTimeout' -or $reasonText -match '(?i)timed out|timeout|time-out|0x800705B4'){$kind='Timeout'}
        elseif($reasonText -match '(?i)Invalid class|Invalid namespace|not supported|not recognized|No CIM or legacy WMI|0x8004100e|0x80041010|0x80041013|0x800706ba'){$kind='Provider'}
        elseif($reasonText -match '(?i)No data returned|No .* returned'){$kind='Empty'}
    }
    $info=switch($kind) {
        'Access' {@('READ-01','Access blocked','Run as administrator if appropriate, then rescan [9] > [1].')}
        'Timeout' {@('READ-02','Provider timed out','Retry [9] > [1]. A slow or stalled Windows provider may need attention.')}
        'Provider' {@('READ-03','Provider unavailable','Check runtime/provider details in [5]. This Windows version may not expose it.')}
        'Empty' {@('READ-04','No records returned','No matching records were returned. If a device is expected, connect it and rescan.')}
        'Data' {@('READ-06','Invalid scan data','Rescan [9] > [1]. Windows returned unusable record data; inspect details in [5].')}
        default {@('READ-05','Windows read failed','Retry [9] > [1]. Technical details are in [5] and saved reports.')}
    }
    [pscustomobject]@{Code=$info[0];Reason=$info[1];Action=$info[2];Details=$details}
}
function Get-ScanFailureHint($Message) {
    return (Get-ScanFailureInfo $Message).Reason
}
function Test-ScanValuePresent($Value,[int]$Depth=0) {
    if($null -eq $Value){return $false}
    if($Value -is [string]){return -not [string]::IsNullOrWhiteSpace((Normalize-IdentifierText $Value))}
    if($Value -is [ValueType]){return $true}
    if($Value -is [System.Collections.IList]){
        if(-not $Value.Count){return $false}
        if($Depth -ge 16){return $true}
        foreach($item in $Value){if(Test-ScanValuePresent $item ($Depth+1)){return $true}}
        return $false
    }
    if($Value -is [System.Collections.IDictionary]){return $Value.Count -gt 0}
    if($Value -is [pscustomobject]){return @($Value.PSObject.Properties).Count -gt 0}
    return $true
}
function Section($Name, [scriptblock]$Query) {
    $script:scanStep++
    $line=Start-ScanLine ('  [{0:00}/{2}] {1,-24} ' -f $script:scanStep, $Name, $scanTotal)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $status='UNAVAILABLE';$results=0;$summary='Not read'
    $failureCode=$null;$nextStep=$null
    try {
        $data = @(Invoke-ScanQuery $Query {
            Update-ScanProgress ([math]::Max(0,$script:scanStep-1))
            Update-ScanWaiting $line $timer.Elapsed.TotalSeconds
        } | Where-Object {$null -ne $_})
        if ($data.Count -eq 0) { throw 'No data returned by Windows.' }
        $unavailable=@($data | Where-Object {Test-UnavailableRecord $_})
        if($unavailable.Count){
            $reason=[string]$unavailable[0].Unavailable
            if([string]::IsNullOrWhiteSpace($reason)){$reason='Windows reported an unavailable record without a diagnostic message.'}
            throw $reason
        }
        # Normalize dates before export so JSON is consistent in Windows PowerShell 5.1 and 7.
        $data = @(foreach ($record in $data) {
            if($record -is [string] -or $record -is [ValueType] -or $record -is [System.Collections.IList]) {
                throw [IO.InvalidDataException]::new('Windows returned a scalar or list where a hardware record was expected.')
            }
            $normalized = [ordered]@{}
            $properties=if($record -is [System.Collections.IDictionary]){
                foreach($key in $record.Keys){[pscustomobject]@{Name=$key;Value=$record[$key]}}
            }else{$record.PSObject.Properties}
            foreach ($property in $properties) {
                if(-not (Test-IdentityFieldValue $property.Name $property.Value)){throw [IO.InvalidDataException]::new(('Windows returned an invalid scalar ID or device key: '+$property.Name))}
                if ($property.Value -is [datetime]) { $normalized[$property.Name]=$property.Value.ToString('o') }
                elseif ($property.Value -is [enum]) { $normalized[$property.Name]=$property.Value.ToString() }
                else { $normalized[$property.Name]=$property.Value }
            }
            if(-not $normalized.Count){throw [IO.InvalidDataException]::new('Windows returned a hardware record with no readable fields.')}
            $hasData=$false
            foreach($entry in $normalized.GetEnumerator()){if($entry.Key -notmatch 'ReadStatus$' -and $entry.Key -ne 'CollectionSource' -and (Test-ScanValuePresent $entry.Value)){$hasData=$true;break}}
            if(-not $hasData){throw [IO.InvalidDataException]::new('Windows returned a hardware record whose fields were all empty.')}
            [pscustomobject]$normalized
        })
        $report[$Name] = $data
        $info=Get-SectionIdentifierInfo $Name $data
        $unit=if($data.Count -eq 1){'result'}else{'results'}
        $timer.Stop();$status=$info.Tag;$results=$data.Count;$summary=$info.Text
        if($script:lastQueryRecoveries.Count){$summary+=' / compatible read'}
        try {Complete-ScanLine $line $Name ("[$status] $results $unit | $summary | {0:0.0}s" -f $timer.Elapsed.TotalSeconds) $palette[$info.Color]}catch{}
    } catch {
        $message = $_.Exception.Message
        $failure=Get-ScanFailureInfo $_
        $summary=$failure.Reason;$failureCode=$failure.Code;$nextStep=$failure.Action
        $status='UNAVAILABLE';$results=0
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{Unavailable=$message;FailureCode=$failure.Code;FailureReason=$failure.Reason;NextStep=$failure.Action}
        $timer.Stop()
        try {Complete-ScanLine $line $Name ('[NOT READ] '+$summary+' / [4] / '+$failure.Code+' | '+('{0:0.0}s' -f $timer.Elapsed.TotalSeconds)) $palette.Warn}catch{}
    } finally {
        $timer.Stop()
        if($null -ne $script:scanTimings){$script:scanTimings.Add([pscustomobject]@{Section=$Name;Status=$status;Results=$results;Seconds=[math]::Round($timer.Elapsed.TotalSeconds,3);Summary=$summary;FailureCode=$failureCode;NextStep=$nextStep;Recoveries=@($script:lastQueryRecoveries);ProgressWarning=$script:lastQueryFeedbackFailure})}
        Update-ScanProgress
    }
}
function Get-MonitorTextResult($Codes,$Length=$null) {
    $items=@()
    if($null -ne $Codes){$items=@($Codes)}
    $count=$items.Count
    if($null -ne $Length) {
        $size=[uint16]0
        if($Length -is [bool] -or -not [uint16]::TryParse([string]$Length,[ref]$size) -or $size -gt $count){return [pscustomobject]@{Text='';Status='Invalid length'}}
        $count=[int]$size
    }
    $text=New-Object Text.StringBuilder
    for($index=0;$index -lt $count;$index++) {
        $number=[uint16]0
        if($null -eq $items[$index] -or $items[$index] -is [bool] -or -not [uint16]::TryParse([string]$items[$index],[ref]$number)){return [pscustomobject]@{Text='';Status='Invalid text codes'}}
        if($number -ne 0){[void]$text.Append([char]$number)}
    }
    $value=$text.ToString().Trim()
    [pscustomobject]@{Text=$value;Status=$(if($value){'Read'}else{'Not supplied'})}
}
function Convert-MonitorText($Codes) {return (Get-MonitorTextResult $Codes).Text}
function Get-MonitorIdentifiers {
    # Some providers reject a projected query containing an optional length field.
    # Read this small class as exposed and use length metadata only when present.
    foreach($monitor in (Get-HwidInstance -OperationTimeoutSec 20 -Namespace 'root\wmi' -ClassName WmiMonitorID)) {
        if($null -eq $monitor){continue}
        $serial=Get-MonitorTextResult $monitor.SerialNumberID
        $name=Get-MonitorTextResult $monitor.UserFriendlyName $monitor.UserFriendlyNameLength
        [pscustomobject][ordered]@{
            InstanceName=$monitor.InstanceName;Active=$monitor.Active
            Manufacturer=(Get-MonitorTextResult $monitor.ManufacturerName $monitor.ManufacturerNameLength).Text
            Name=$name.Text;ProductCode=(Convert-MonitorText $monitor.ProductCodeID);SerialNumber=$serial.Text
            SerialNumberReadStatus=$serial.Status;NameReadStatus=$name.Status
            WeekOfManufacture=$monitor.WeekOfManufacture;YearOfManufacture=$monitor.YearOfManufacture
            ManufacturerName=$monitor.ManufacturerName;ManufacturerNameLength=$monitor.ManufacturerNameLength
            UserFriendlyName=$monitor.UserFriendlyName;UserFriendlyNameLength=$monitor.UserFriendlyNameLength
            ProductCodeID=$monitor.ProductCodeID;SerialNumberID=$monitor.SerialNumberID
        }
    }
}
function GiB($Bytes) {
    $number=[uint64]0
    if($null -eq $Bytes -or $Bytes -is [bool] -or -not [uint64]::TryParse([string]$Bytes,[ref]$number)){return $null}
    return [math]::Round($number / 1GB,2)
}
function Invoke-HardwareScan([int]$ScanNumber=1,[bool]$UseWorker=($ownedConsole -and -not $redirected),[bool]$IncludeExtended=$false) {
    $scanCursorVisible=$null
    if($ownedConsole -and -not $redirected) {
        try {$scanCursorVisible=[Console]::CursorVisible;[Console]::CursorVisible=$false}catch{}
    }
    try {
    # Build a separate snapshot; publish only after every query finishes.
    $report=[ordered]@{}
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    $script:scanStep=0
    $script:scanTimings=New-Object 'System.Collections.Generic.List[object]'
    Reset-UiPage
    Start-UiReport
    Write-Heading ('PC SCAN / SNAPSHOT #'+$ScanNumber)
Write-Host '  Hardware identity and Windows inventory. Read-only scan.' -ForegroundColor $palette.Text
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.59'; Display=$display.Mode; ScanNumber=$ScanNumber }
$report['Compatibility']=Get-CompatibilityInfo
$permissionLabel = if ($admin) { 'Administrator' } else { 'Standard user' }
Write-Host "  Computer: $env:COMPUTERNAME  |  Access: $permissionLabel" -ForegroundColor $palette.Muted
$scanClock=[Diagnostics.Stopwatch]::StartNew()
$script:scanProgressClock=$scanClock
$script:scanProgressState=$null
$script:scanQueryWorker=$null
if($ownedConsole -and -not $redirected) {
    try {$script:scanProgressState=[pscustomobject]@{Top=[Console]::CursorTop;Width=[Console]::WindowWidth}}catch{}
}
if($null -ne $script:scanProgressState) {
    Write-PnpLine (Limit-TableText ('  '+(Get-ScanProgressText 0 $scanTotal 0 ([Console]::WindowWidth-3))) ([Console]::WindowWidth-1)) $palette.Heading
}else{Write-PnpValue 'Progress' (Get-ScanProgressText 0 $scanTotal 0) $palette.Heading}
try {
if($UseWorker) {
    try {$script:scanQueryWorker=New-ScanQueryWorker}
    catch {Write-PnpValue 'Scan mode' 'Live timer unavailable; using direct Windows queries.' $palette.Muted}
}
$report['Report info']['QueryMode']=if($null -ne $script:scanQueryWorker){'Live progress'}else{'Direct queries'}
Write-Heading "SCANNING $scanTotal SECTIONS"
Write-Host '  READ = data read. CHECK = values or device records need review; query succeeded.' -ForegroundColor $palette.Muted
Write-Host '  Found = supplied by Windows. Missing = not supplied. Default = generic value.' -ForegroundColor $palette.Muted
Section 'System identity' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_ComputerSystemProduct -Property Vendor,Name,Version,IdentifyingNumber,UUID | Select-Object Vendor, Name, Version, IdentifyingNumber, UUID
}
Section 'System hardware' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_ComputerSystem -Property Manufacturer,Model,SystemType,TotalPhysicalMemory | Select-Object Manufacturer, Model, SystemType, TotalPhysicalMemory,@{n='TotalRAM_GiB';e={GiB $_.TotalPhysicalMemory}}
}
Section 'CPU' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_Processor -Property DeviceID,Name,Manufacturer,ProcessorId,SocketDesignation,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | Select-Object DeviceID, Name, Manufacturer, ProcessorId, SocketDesignation, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
}
Section 'Motherboard' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_BaseBoard -Property Manufacturer,Product,Version,SerialNumber | Select-Object Manufacturer, Product, Version, SerialNumber
}
Section 'BIOS' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_BIOS -Property Manufacturer,SMBIOSBIOSVersion,SerialNumber,ReleaseDate,SMBIOSMajorVersion,SMBIOSMinorVersion | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate, SMBIOSMajorVersion, SMBIOSMinorVersion
}
Section 'Chassis' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_SystemEnclosure -Property Manufacturer,SerialNumber,SMBIOSAssetTag,ChassisTypes | Select-Object Manufacturer, SerialNumber, SMBIOSAssetTag, ChassisTypes
}
Section 'Memory modules' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_PhysicalMemory -Property DeviceLocator,BankLabel,Manufacturer,PartNumber,SerialNumber,Capacity,Speed,ConfiguredClockSpeed | Select-Object DeviceLocator, BankLabel, Manufacturer, PartNumber, SerialNumber,Capacity,@{n='Capacity_GiB';e={GiB $_.Capacity}}, Speed, ConfiguredClockSpeed
}
Section 'Physical disks' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_DiskDrive -Property Index,Model,SerialNumber,FirmwareRevision,InterfaceType,MediaType,Size,PNPDeviceID | Select-Object Index, Model, SerialNumber, FirmwareRevision, InterfaceType, MediaType,Size,@{n='Size_GiB';e={GiB $_.Size}}, PNPDeviceID
}
Section 'Storage identifiers' {
    Get-StorageIdentifiers
}
Section 'Volumes' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_LogicalDisk -Filter 'DriveType=2 OR DriveType=3 OR DriveType=5' -Property DeviceID,DriveType,VolumeName,VolumeSerialNumber,FileSystem,Size,FreeSpace | Select-Object DeviceID, DriveType, VolumeName, VolumeSerialNumber, FileSystem,Size,FreeSpace,@{n='Size_GiB';e={GiB $_.Size}}, @{n='Free_GiB';e={GiB $_.FreeSpace}}
}
Section 'Disk partitions' {
    Get-PartitionIdentifiers
}
Section 'Graphics adapters' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_VideoController -Property Name,VideoProcessor,PNPDeviceID,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution | Select-Object Name, VideoProcessor, PNPDeviceID, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution
}
Section 'Monitors' {
    Get-MonitorIdentifiers
}
Section 'Network adapters' {
    Get-NetworkIdentifiers
}
Section 'Windows' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_OperatingSystem -Property Caption,Version,BuildNumber,OSArchitecture,InstallDate,LastBootUpTime | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime
}
Section 'Windows Machine GUID' {
    [pscustomobject]@{ MachineGuid = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid }
}
Section 'PnP hardware IDs' { Get-DriverHardwareIds }
if($IncludeExtended) {
    Write-PnpValue 'Extra scan' 'Normal queries finished; refreshing hidden/disconnected device records.' $palette.Muted
    $extraLine=Start-ScanLine '  [EXTRA] Extended device catalog '
    $extraClock=[Diagnostics.Stopwatch]::StartNew()
    try {
        $extra=Invoke-ScanQuery {Get-ExtendedDeviceInventory} {Update-ScanProgress $scanTotal;Update-ScanWaiting $extraLine $extraClock.Elapsed.TotalSeconds}
        if($null -eq $extra -or -not @($extra.Devices).Count){throw 'No device records returned.'}
        $report['Extended device inventory']=@($extra.Devices)
        $report['Extended scan info']=$extra.Info
        $report['Report info']['ExtendedStatus']='Refreshed'
        try {Complete-ScanLine $extraLine 'Extended catalog' ("[READ] $(@($extra.Devices).Count) known nodes") $palette.Good}catch{}
    }catch {
        $message=$_.Exception.Message
        $warnings.Add('Extended device inventory: '+$message)
        $failure=Get-ScanFailureInfo $_
        $report['Extended scan info']=[ordered]@{Captured=(Get-Date).ToString('o');Source='Extended refresh failed';Records=0;Error=$message;FailureCode=$failure.Code;FailureReason=$failure.Reason;NextStep='Retry the extended scan using [9] > [4].'}
        $report['Report info']['ExtendedStatus']='Unavailable'
        try {Complete-ScanLine $extraLine 'Extended catalog' ('[NOT READ] '+$failure.Reason+' / '+$failure.Code) $palette.Warn}catch{}
    }finally{$extraClock.Stop()}
}
$scanClock.Stop()
$report['Report info']['ScanSeconds']=[math]::Round($scanClock.Elapsed.TotalSeconds,2)
$report['Report info']['ScanCompleted']=(Get-Date).ToString('o')
$report['Scan timing']=@($scanTimings.ToArray())
$compatible=@($scanTimings | Where-Object {$_.Status -ne 'UNAVAILABLE' -and $_.Recoveries.Count -gt 0}).Count
$report['Report info']['CompatibleReadSections']=$compatible
$report['Report info']['ProgressFallbackSections']=@($scanTimings | Where-Object {$_.ProgressWarning}).Count
$report['Warnings'] = @($warnings.ToArray())
    if($script:scanStep -ne $scanTotal -or $scanTimings.Count -ne $scanTotal){throw 'The scan did not finish every section.'}
    $read=@($scanTimings | Where-Object Status -ne 'UNAVAILABLE').Count
    $complete=($read -eq $scanTotal)
    $extendedNote=''
    if($IncludeExtended) {
        $extraRead=($report['Report info'].ExtendedStatus -eq 'Refreshed')
        $complete=$complete -and $extraRead
        $extendedNote=if($extraRead){' / extended READ'}else{' / extended NOT READ'}
    }
    Write-PnpValue 'Finished' ("$scanTotal/$scanTotal finished / $read read / $($scanTotal-$read) not read$extendedNote / $($report['Report info'].ScanSeconds)s") $(if($complete){$palette.Good}else{$palette.Warn})
    if($compatible){Write-PnpValue 'Compatible reads' ("$compatible sections recovered through a compatible reader/query. Main [5] shows details.") $palette.Good}
    if($report['Report info'].ProgressFallbackSections){Write-PnpValue 'Progress display' ("$($report['Report info'].ProgressFallbackSections) sections finished after live display updates failed. Read results are shown above; Main [5] has details.") $palette.Warn}
    $rows=@(Get-IdentifierRows $report)
    return [pscustomobject]@{Inventory=$report;Warnings=$warnings;Identifiers=$rows;Completed=$true}
} finally {
    $scanClock.Stop()
    $script:scanProgressClock=$null
    $script:scanProgressState=$null
    if($null -ne $script:scanQueryWorker){$script:scanQueryWorker.Dispose();$script:scanQueryWorker=$null}
}
    }finally{
        if($null -ne $scanCursorVisible){try{[Console]::CursorVisible=$scanCursorVisible}catch{}}
    }
}
function Get-IdentifierRows($Inventory) {
    # Support both the live ordered dictionary and reports imported from JSON.
    # JSON names are read case-insensitively; use the schema's spelling for matching.
    $sectionNames=@{};$fieldNames=@{}
    foreach($section in @($sectionGroups.Values | ForEach-Object {$_})+@('PnP hardware IDs')){$sectionNames[$section]=$section}
    foreach($field in (($identifierPattern -replace '^\^\(|\)\$$','') -split '\|')){$fieldNames[$field]=$field}
    $names = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory.Keys } else { $Inventory.PSObject.Properties.Name }
    foreach ($name in $names) {
        if ($name -in @('Report info', 'Warnings','Compatibility','Extended scan info','Extended device inventory')) { continue }
        $section=if($sectionNames.ContainsKey($name)){$sectionNames[$name]}else{$name}
        $records = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory[$name] } else { $Inventory.$name }
        foreach ($record in $records) {
            $device = Get-DeviceKey $section $record
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Name -notmatch $identifierPattern) { continue }
                $field=$fieldNames[$property.Name]
                $value = Normalize-IdentifierText $property.Value
                $quality = Get-FieldQuality $field $property.Value $record
                if ($quality -eq 'Not applicable') { continue }
                [pscustomobject]@{ Section = $section; Device = $device; Field = $field; Value = $value; Quality = $quality }
            }
        }
    }
}
function Get-DeviceKey($SectionName, $Record) {
    $fields = switch ($SectionName) {
        'CPU' { @('DeviceID') }
        'Monitors' { @('InstanceName') }
        'Memory modules' { @('DeviceLocator', 'BankLabel') }
        'Physical disks' { @('Index') }
        'Storage identifiers' { @('Number') }
        'Volumes' { @('DeviceID') }
        'Graphics adapters' { @('PNPDeviceID') }
        'Network adapters' { @('InterfaceGuid') }
        default { @() }
    }
    $parts = foreach ($field in $fields) {
        $value = Normalize-IdentifierText $Record.$field
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { "${field}=$(Get-CanonicalIdentifier $field $value)" }
    }
    return ($parts -join '; ')
}
function Get-InventoryConflicts($Inventory) {
    foreach($section in @('System identity','CPU','Motherboard','BIOS','Chassis','Memory modules','Physical disks','Storage identifiers','Volumes','Graphics adapters','Network adapters','Windows Machine GUID','Monitors')) {
        $records=if($Inventory -is [System.Collections.IDictionary]){$Inventory[$section]}else{$Inventory.$section}
        if(-not (Test-SectionReadable $records)){continue}
        if($section -in @('System identity','Motherboard','BIOS','Chassis','Windows Machine GUID') -and @($records).Count -gt 1){
            [pscustomobject]@{Section=$section;DeviceKey='';Count=@($records).Count;Message=("$(@($records).Count) records have no reliable device key. Inspect the records in [5]; comparisons skip this section.")}
            continue
        }
        $counts=New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
        foreach($record in $records) {
            $key=Get-DeviceKey $section $record
            if(-not $key){continue}
            if($counts.ContainsKey($key)){$counts[$key]++}else{$counts[$key]=1}
        }
        foreach($key in ($counts.Keys | Sort-Object)) {
            if($counts[$key] -gt 1){[pscustomobject]@{Section=$section;DeviceKey=$key;Count=$counts[$key];Message=("$($counts[$key]) records share this device key. Verify the provider data in [5]; comparisons skip this device.")}}
        }
    }
}
function Get-CanonicalIdentifier($Field, $Value) {
    $text = Normalize-IdentifierText $Value
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
    $idSections = @('System identity','CPU','Motherboard','BIOS','Chassis','Memory modules','Physical disks','Storage identifiers','Volumes','Graphics adapters','Network adapters','Windows Machine GUID','Monitors')
    $common = @()
    $skipped = @()
    $unkeyedSections=@()
    $keyedSections=$idSections
    foreach ($section in $idSections) {
        $old = if ($Previous -is [System.Collections.IDictionary]) { $Previous[$section] } else { $Previous.$section }
        $new = if ($Current -is [System.Collections.IDictionary]) { $Current[$section] } else { $Current.$section }
        if ((Test-SectionReadable $old) -and (Test-SectionReadable $new)) {
            if($section -in $keyedSections) {
                $oldKeys=@($old | ForEach-Object {Get-DeviceKey $section $_})
                $newKeys=@($new | ForEach-Object {Get-DeviceKey $section $_})
                $oldMissing=@($oldKeys | Where-Object {-not $_}).Count
                $newMissing=@($newKeys | Where-Object {-not $_}).Count
                $multiple=@($old).Count -gt 1 -or @($new).Count -gt 1
                $oneSided=($oldMissing -gt 0) -ne ($newMissing -gt 0)
                if(($oldMissing -or $newMissing) -and ($multiple -or $oneSided)) {
                    $skipped+=$section;$unkeyedSections+=$section;continue
                }
            }
            $common += $section
        }
        else { $skipped += $section }
    }
    $oldRows = @(Get-IdentifierRows $Previous | Where-Object { $_.Section -in $common })
    $newRows = @(Get-IdentifierRows $Current | Where-Object { $_.Section -in $common })
    # If either side has an unreadable value for the same field/device, skip that field on both sides.
    $unreadable=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    $oldDevices=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    $newDevices=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    $oldFields=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    $newFields=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    $ambiguous=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $ambiguousList=New-Object 'System.Collections.Generic.List[object]'
    foreach($side in @('Previous','Current')) {
        $inventory=if($side -eq 'Previous'){$Previous}else{$Current}
        foreach($conflict in (Get-InventoryConflicts $inventory)) {
            $key=ConvertTo-Json -InputObject @($conflict.Section,$conflict.DeviceKey) -Compress
            if(-not $ambiguous.ContainsKey($key)) {
                $entry=[pscustomobject]@{Section=$conflict.Section;DeviceKey=$conflict.DeviceKey;Count=$conflict.Count;Sources=@($side)}
                $ambiguous[$key]=$entry;$ambiguousList.Add($entry)
            } else {$ambiguous[$key].Sources+=@($side)}
        }
    }
    foreach($row in $oldRows) {
        $oldDevices[(ConvertTo-Json -InputObject @($row.Section,$row.Device) -Compress)]=$true
        $oldFields[(ConvertTo-Json -InputObject @($row.Section,$row.Device,$row.Field) -Compress)]=$true
    }
    foreach($row in $newRows) {
        $newDevices[(ConvertTo-Json -InputObject @($row.Section,$row.Device) -Compress)]=$true
        $newFields[(ConvertTo-Json -InputObject @($row.Section,$row.Device,$row.Field) -Compress)]=$true
    }
    foreach ($row in @($oldRows) + @($newRows)) {
        $deviceKey=ConvertTo-Json -InputObject @($row.Section,$row.Device) -Compress
        $fieldKey=ConvertTo-Json -InputObject @($row.Section,$row.Device,$row.Field) -Compress
        $schemaGap=$oldDevices.ContainsKey($deviceKey) -and $newDevices.ContainsKey($deviceKey) -and (-not $oldFields.ContainsKey($fieldKey) -or -not $newFields.ContainsKey($fieldKey))
        if ($row.Quality -ne 'Reported' -or $schemaGap -or $ambiguous.ContainsKey($deviceKey)) {
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
        SkippedSections=@($skipped); UnkeyedSections=@($unkeyedSections); SkippedFields=$unreadable.Count; AmbiguousDevices=@($ambiguousList.ToArray())
    }
}
function Assert-UniqueJsonProperties($Json) {
    if(-not ('HwidJsonObjectKeys' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class HwidJsonObjectKeys {
    static string ReadString(string text, ref int i) {
        var value=new StringBuilder();
        for(i++;i<text.Length;i++) {
            char c=text[i];
            if(c=='"') return value.ToString();
            if(c<32) throw new InvalidDataException("Unescaped control character in JSON string.");
            if(c!='\\') {value.Append(c);continue;}
            if(++i>=text.Length) throw new InvalidDataException("Incomplete JSON escape.");
            switch(text[i]) {
                case '"':value.Append('"');break;
                case '\\':value.Append('\\');break;
                case '/':value.Append('/');break;
                case 'b':value.Append('\b');break;
                case 'f':value.Append('\f');break;
                case 'n':value.Append('\n');break;
                case 'r':value.Append('\r');break;
                case 't':value.Append('\t');break;
                case 'u':
                    if(i+4>=text.Length) throw new InvalidDataException("Incomplete Unicode escape.");
                    ushort code;
                    if(!UInt16.TryParse(text.Substring(i+1,4),System.Globalization.NumberStyles.HexNumber,System.Globalization.CultureInfo.InvariantCulture,out code)) throw new InvalidDataException("Invalid Unicode escape.");
                    value.Append((char)code);i+=4;break;
                default:throw new InvalidDataException("Invalid JSON escape.");
            }
        }
        throw new InvalidDataException("Unterminated JSON string.");
    }
    public static void Validate(string text) {
        var objects=new Stack<HashSet<string>>();
        for(int i=0;i<text.Length;i++) {
            char c=text[i];
            if(c=='"') {
                string token=ReadString(text,ref i);
                int next=i+1;while(next<text.Length && Char.IsWhiteSpace(text[next]))next++;
                if(next<text.Length && text[next]==':' && objects.Count>0 && objects.Peek()!=null && !objects.Peek().Add(token)) throw new InvalidDataException("Duplicate JSON property name: "+token);
            } else if(c=='{' || c=='[') {
                if(objects.Count>=128) throw new InvalidDataException("JSON nesting exceeds 128 levels.");
                objects.Push(c=='{' ? new HashSet<string>(StringComparer.OrdinalIgnoreCase) : null);
            } else if(c=='}' || c==']') {
                if(objects.Count==0 || (c=='}')!=(objects.Peek()!=null)) throw new InvalidDataException("Mismatched JSON structure.");
                objects.Pop();
            }
        }
        if(objects.Count!=0) throw new InvalidDataException("Incomplete JSON structure.");
    }
}
'@
    }
    try {[HwidJsonObjectKeys]::Validate([string]$Json)}
    catch {
        $message=if($_.Exception.InnerException){$_.Exception.InnerException.Message}else{$_.Exception.Message}
        throw ("Invalid or ambiguous JSON: "+$message)
    }
}
function Convert-ReportJson($Json) {
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        return (ConvertFrom-Json -InputObject $Json -DateKind String -ErrorAction Stop)
    }
    return (ConvertFrom-Json -InputObject $Json -ErrorAction Stop)
}
function Format-ComparisonKey($Key) {
    $parts = Convert-ReportJson $Key
    $deviceLabel = if ($parts[1]) { " ($($parts[1]))" } else { '' }
    return "[$($parts[0])] $(Get-FieldLabel $parts[2])${deviceLabel}: $($parts[3])"
}
function Get-SnapshotFailureInfo($Failure) {
    $exception=if($Failure -is [System.Management.Automation.ErrorRecord]){$Failure.Exception}else{$Failure}
    $details=[string]$Failure;$kind=if($Failure -is [System.Management.Automation.ErrorRecord] -and $Failure.CategoryInfo.Category -eq 'PermissionDenied'){'Access'}else{'Data'};$messages=New-Object 'System.Collections.Generic.List[string]'
    for($depth=0;$exception -is [Exception] -and $depth -lt 16;$depth++) {
        $messages.Add($exception.Message)
        if($exception -is [UnauthorizedAccessException]){$kind='Access'}
        elseif($exception -is [Text.DecoderFallbackException] -and $kind -ne 'Access'){$kind='Encoding'}
        elseif($exception -is [IO.IOException] -and $exception -isnot [IO.InvalidDataException] -and $kind -notin @('Access','Encoding')){$kind='Unavailable'}
        $exception=$exception.InnerException
    }
    $text=$messages -join ' / '
    if($text -match '64 MB import limit'){$kind='Size'}
    elseif($text -match 'not a supported HWID v2 or v3'){$kind='Version'}
    elseif($text -match 'Report file not found'){$kind='Unavailable'}
    $info=switch($kind) {
        'Access' {@('STORE-01','Access blocked','Check file permissions or choose a readable local copy.','Warn')}
        'Unavailable' {@('STORE-02','File unavailable or in use','Close any writer, wait for sync, then refresh or retry.','Warn')}
        'Encoding' {@('STORE-03','Invalid text encoding','Keep the original and choose a valid exported JSON snapshot.','Error')}
        'Size' {@('STORE-05','Report exceeds the 64 MB import limit','Choose a smaller exported snapshot.','Warn')}
        'Version' {@('STORE-06','Unsupported snapshot version','Choose a supported HWID v2 or v3 JSON snapshot.','Warn')}
        default {@('STORE-04','Invalid or damaged snapshot','Keep the original and choose another valid JSON snapshot.','Error')}
    }
    [pscustomobject]@{Code=$info[0];Reason=$info[1];Action=$info[2];Color=$info[3];Details=$details}
}
function Read-ReportJsonText($Path) {
    $stream=$null
    try {
        # One read handle enforces size and prevents reading an in-progress writer.
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if($stream.Length -gt 64MB){throw [IO.InvalidDataException]::new('Report exceeds the 64 MB import limit.')}
        $prefix=New-Object byte[] 4;$count=$stream.Read($prefix,0,4);$offset=0
        $encoding=[Text.UTF8Encoding]::new($false,$true)
        if($count -ge 4 -and $prefix[0] -eq 255 -and $prefix[1] -eq 254 -and $prefix[2] -eq 0 -and $prefix[3] -eq 0){$encoding=[Text.UTF32Encoding]::new($false,$false,$true);$offset=4}
        elseif($count -ge 4 -and $prefix[0] -eq 0 -and $prefix[1] -eq 0 -and $prefix[2] -eq 254 -and $prefix[3] -eq 255){$encoding=[Text.UTF32Encoding]::new($true,$false,$true);$offset=4}
        elseif($count -ge 3 -and $prefix[0] -eq 239 -and $prefix[1] -eq 187 -and $prefix[2] -eq 191){$offset=3}
        elseif($count -ge 2 -and $prefix[0] -eq 255 -and $prefix[1] -eq 254){$encoding=[Text.UnicodeEncoding]::new($false,$false,$true);$offset=2}
        elseif($count -ge 2 -and $prefix[0] -eq 254 -and $prefix[1] -eq 255){$encoding=[Text.UnicodeEncoding]::new($true,$false,$true);$offset=2}
        $stream.Position=$offset
        $bytes=New-Object byte[] ([int]($stream.Length-$offset));$read=0
        while($read -lt $bytes.Length){$received=$stream.Read($bytes,$read,$bytes.Length-$read);if(-not $received){throw [IO.EndOfStreamException]::new('Snapshot ended before all bytes could be read. Retry the import.')};$read+=$received}
        # Decode the complete buffer so incomplete trailing characters fail on .NET Framework too.
        return $encoding.GetString($bytes)
    }finally{if($null -ne $stream){$stream.Dispose()}}
}
function Read-SavedReport($Path) {
    if(-not (Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue)){throw 'JSON import is unavailable: repair the Microsoft.PowerShell.Utility module for this runtime.'}
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Report file not found. Choose an existing JSON report.'}
    try {$json=Read-ReportJsonText (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName}
    catch{$failure=Get-SnapshotFailureInfo $_;throw [Exception]::new(($failure.Code+' / '+$failure.Reason+'. '+$failure.Action),$_.Exception)}
    try {
        Assert-UniqueJsonProperties $json
        $previous=Convert-ReportJson $json
    }
    catch {
        if($_.Exception.Message -match 'Duplicate JSON property'){throw [IO.InvalidDataException]::new($_.Exception.Message,$_.Exception)}
        throw [IO.InvalidDataException]::new('Cannot read this JSON report. Choose the .json file, not the TXT report; the file may be incomplete or damaged.',$_.Exception)
    }
    if ($json -notmatch '^\s*\{' -or $previous -isnot [pscustomobject] -or $previous.'Report info' -isnot [pscustomobject] -or $previous.'Report info'.Version -isnot [string] -or $previous.'Report info'.Version -notmatch '^[23]\.\d+(\.\d+)?$') {
        throw 'This file is not a supported HWID v2 or v3 report.'
    }
    foreach($field in @('Computer','Generated','SavedAt')) {
        $value=$previous.'Report info'.$field
        $legacyDate=$field -in @('Generated','SavedAt') -and ($value -is [datetime] -or $value -is [datetimeoffset])
        if($null -ne $value -and $value -isnot [string] -and -not $legacyDate){throw "Invalid report metadata: $field"}
    }
    $knownSections = @($sectionGroups.Values | ForEach-Object { $_ }) + @('PnP hardware IDs','Extended device inventory')
    $found = 0
    foreach ($property in $previous.PSObject.Properties) {
        if ($property.Name -notin $knownSections) { continue }
        $found++
        foreach ($record in @($property.Value)) {
            if ($null -eq $record -or $record -isnot [pscustomobject]) { throw "Invalid data in section: $($property.Name)" }
            foreach($field in $record.PSObject.Properties) {
                if(-not (Test-IdentityFieldValue $field.Name $field.Value)){throw "Invalid identifier or device-key value: $($property.Name) / $($field.Name)"}
            }
        }
    }
    if (-not $found) { throw 'This report has no recognized hardware sections.' }
    return $previous
}
function Test-ReportFileContent($Path,[string]$Expected) {
    $stream=$null;$reader=$null
    try{
        $encoding=[Text.UTF8Encoding]::new($false,$true)
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if($stream.Length -ne $encoding.GetByteCount($Expected)){return $false}
        $reader=[IO.StreamReader]::new($stream,$encoding,$false,4096)
        $buffer=New-Object char[] 4096;$position=0
        while(($count=$reader.Read($buffer,0,$buffer.Length)) -gt 0){
            if($position+$count -gt $Expected.Length -or -not [string]::Equals([string]::new($buffer,0,$count),$Expected.Substring($position,$count),[StringComparison]::Ordinal)){return $false}
            $position+=$count
        }
        return $position -eq $Expected.Length
    }finally{if($null -ne $reader){$reader.Dispose()};if($null -ne $stream){$stream.Dispose()}}
}
function Write-ReportPair($Stem,$Text,$Json,[scriptblock]$Publisher) {
    $txtFinal=$Stem+'.txt';$jsonFinal=$Stem+'.json'
    $suffix='.pending-'+[guid]::NewGuid().ToString('N')
    $txtTemp=$txtFinal+$suffix;$jsonTemp=$jsonFinal+$suffix
    $published=New-Object 'System.Collections.Generic.List[string]'
    $complete=$false
    try {
        $encoding=New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($txtTemp,$Text,$encoding)
        [IO.File]::WriteAllText($jsonTemp,$Json,$encoding)
        Read-SavedReport $jsonTemp | Out-Null
        foreach($pair in @(@($txtTemp,$txtFinal),@($jsonTemp,$jsonFinal))) {
            if($Publisher){& $Publisher $pair[0] $pair[1]}else{[IO.File]::Move($pair[0],$pair[1])}
            $published.Add($pair[1])
        }
        if(-not (Test-ReportFileContent $txtFinal $Text) -or -not (Test-ReportFileContent $jsonFinal $Json)){throw [IO.InvalidDataException]::new('Snapshot verification failed: the published TXT or JSON changed. No successful save was recorded.')}
        $complete=$true
    } finally {
        $cleanup=@($txtTemp,$jsonTemp)
        if(-not $complete){$cleanup+=@($published.ToArray())}
        foreach($file in $cleanup) {
            try {if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}catch{Write-PnpValue 'SAVE-02 / cleanup needed' $file $palette.Error}
        }
    }
}
function Get-RecentReports($Folder) {
    if(Test-Path -LiteralPath $Folder -PathType Container) {
        Get-ChildItem -LiteralPath $Folder -Filter 'HWID-*.json' -File | Sort-Object LastWriteTimeUtc,Name -Descending | Select-Object -First 5
    }
}
function Get-ReportLocations([string]$ScriptPath=$env:HWID_SCRIPT,[string]$LocalRoot=$env:LOCALAPPDATA) {
    $base=Split-Path -Parent ([IO.Path]::GetFullPath($ScriptPath))
    $primary=Join-Path $base 'HWID-Reports'
    if(-not $LocalRoot){$LocalRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)}
    $fallback=if($LocalRoot){Join-Path $LocalRoot 'HWID Checker\HWID-Reports'}else{$null}
    $folders=New-Object 'System.Collections.Generic.List[string]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $parent=Split-Path -Parent $base
    $adjacent=$null
    try {if($parent -and (Test-Path -LiteralPath (Join-Path $parent 'hwid.bat') -PathType Leaf)){$adjacent=Join-Path $parent 'HWID-Reports'}}catch{}
    foreach($folder in @($primary,$fallback,$adjacent)) {
        if($folder -and $seen.Add([IO.Path]::GetFullPath($folder))){$folders.Add([IO.Path]::GetFullPath($folder))}
    }
    [pscustomobject]@{Primary=$primary;Fallback=$fallback;Search=@($folders.ToArray())}
}
function Get-ReportCaptureTime($Info) {
    $stamp=[datetimeoffset]::MinValue
    if([datetimeoffset]::TryParse([string]$Info.Generated,[cultureinfo]::InvariantCulture,([Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeUniversal),[ref]$stamp)){return $stamp.ToUniversalTime()}
    return $null
}
function Get-SavedSnapshotCatalog([string[]]$Folders,$Current) {
    $entries=New-Object 'System.Collections.Generic.List[object]'
    $skipped=New-Object 'System.Collections.Generic.List[object]'
    $textOnly=New-Object 'System.Collections.Generic.List[object]'
    $textSeen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $currentInfo=$Current.'Report info';$now=Get-ReportCaptureTime $currentInfo
    foreach($folder in $Folders) {
        try {
            if(-not (Test-Path -LiteralPath $folder -PathType Container)){continue}
            $all=@(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)
            $files=@($all | Where-Object Extension -eq '.json')
            foreach($textFile in $all | Where-Object Extension -eq '.txt') {
                if($textSeen.Add($textFile.FullName) -and -not [IO.File]::Exists([IO.Path]::ChangeExtension($textFile.FullName,'.json'))){$textOnly.Add([pscustomobject]@{FullName=$textFile.FullName;Name=$textFile.Name})}
            }
        }catch{$failure=Get-SnapshotFailureInfo $_;$skipped.Add([pscustomobject]@{Path=$folder;Reason=$failure.Reason;Code=$failure.Code;Action=$failure.Action;Color=$failure.Color});continue}
        foreach($file in $files) {
            if(-not $seen.Add($file.FullName)){continue}
            try {
                $saved=Read-SavedReport $file.FullName
                $info=$saved.'Report info';$captured=Get-ReportCaptureTime $info
                $samePc=-not [string]::IsNullOrWhiteSpace([string]$info.Computer) -and [string]::Equals([string]$info.Computer,[string]$currentInfo.Computer,[StringComparison]::OrdinalIgnoreCase)
                $usable=@(Get-IdentifierRows $saved | Where-Object Quality -eq 'Reported').Count
                $rank=4;$relation='TIME UNKNOWN'
                if($null -ne $captured -and $null -ne $now) {
                    if($captured -lt $now){$relation='OLDER';$rank=if($samePc){0}else{2}}
                    elseif($captured -eq $now){$relation='SAME CAPTURE TIME';$rank=1}
                    else{$relation='NEWER';$rank=3}
                }
                if(-not $samePc){$relation+=' / OTHER OR UNKNOWN PC';$rank=[math]::Max(2,$rank)}
                if(-not $usable){$relation+=' / NO USABLE IDs';$rank=5}
                $txtPath=[IO.Path]::ChangeExtension($file.FullName,'.txt')
                $entries.Add([pscustomobject]@{FullName=$file.FullName;Name=$file.Name;Computer=[string]$info.Computer;Generated=$info.Generated;Relation=$relation;SamePc=$samePc;Older=($null -ne $captured -and $null -ne $now -and $captured -lt $now);UsableIds=$usable;Rank=$rank;TextAvailable=[IO.File]::Exists($txtPath);SortTicks=$(if($null -ne $captured){$captured.UtcDateTime.Ticks}else{$file.LastWriteTimeUtc.Ticks})})
            }catch{$failure=Get-SnapshotFailureInfo $_;$skipped.Add([pscustomobject]@{Path=$file.FullName;Reason=$failure.Reason;Code=$failure.Code;Action=$failure.Action;Color=$failure.Color})}
        }
    }
    [pscustomobject]@{Entries=@($entries.ToArray() | Sort-Object Rank,@{Expression='SortTicks';Descending=$true},FullName);Skipped=@($skipped.ToArray());TextOnly=@($textOnly.ToArray())}
}
function Get-SnapshotDisplayInfo($Entry) {
    if($Entry.Relation -match 'NO USABLE IDs'){return [pscustomobject]@{Color='Warn';Hint='No usable ID fields; choose another baseline.'}}
    if($Entry.Relation -match 'OTHER OR UNKNOWN PC'){return [pscustomobject]@{Color='Warn';Hint='Verify the computer before comparing.'}}
    if($Entry.Relation -eq 'OLDER'){return [pscustomobject]@{Color='Good';Hint='Older capture from this PC; suitable baseline.'}}
    if($Entry.Relation -eq 'SAME CAPTURE TIME'){return [pscustomobject]@{Color='Muted';Hint='Same capture time; this does not prove the IDs match.'}}
    if($Entry.Relation -eq 'NEWER'){return [pscustomobject]@{Color='Warn';Hint='Newer than the active scan; check the comparison direction.'}}
    return [pscustomobject]@{Color='Warn';Hint='Capture time is unknown; check the file before comparing.'}
}
function Show-SnapshotStorage([switch]$OpenFolder) {
    Reset-UiPage;Start-UiReport;Add-ReportBookmark '1'
    Write-Heading 'SAVED SNAPSHOTS / STORAGE'
    Write-PnpValue 'Jump' '1 Summary / 2 Folders / 3 Files not read / 4 TXT only. 0 or Enter = menu.' $palette.Muted
    $locations=Get-ReportLocations
    $catalog=Get-SavedSnapshotCatalog $locations.Search $report
    $older=@($catalog.Entries | Where-Object {$_.SamePc -and $_.Older -and $_.UsableIds -gt 0}).Count
    $paired=@($catalog.Entries | Where-Object TextAvailable -eq $true).Count
    Write-PnpValue 'JSON snapshots' ("$($catalog.Entries.Count) readable / $older older usable baselines from this PC") $(if($catalog.Entries.Count){$palette.Good}else{$palette.Muted})
    Write-PnpValue 'Report pairs' ("$paired TXT + JSON / $($catalog.Entries.Count-$paired) JSON only") $palette.Text
    $checkColor=if(@($catalog.Skipped | Where-Object Color -eq 'Error').Count){$palette.Error}elseif($catalog.Skipped.Count -or $catalog.TextOnly.Count){$palette.Warn}else{$palette.Good}
    Write-PnpValue 'Storage check' ("$($catalog.Skipped.Count) files/folders not read / $($catalog.TextOnly.Count) TXT only") $checkColor
    Write-PnpValue 'Meaning' 'JSON alone supports comparison. TXT alone is a readable report and needs its JSON to compare.' $palette.Muted
    if($OpenFolder) {
        $folder=$locations.Primary;$selected=$false
        if($lastSavedReportPath){try{if(Test-Path -LiteralPath (Split-Path -Parent $lastSavedReportPath) -PathType Container){$folder=Split-Path -Parent $lastSavedReportPath;$selected=$true}}catch{}}
        if(-not $selected){foreach($candidate in $locations.Search){try{if(Test-Path -LiteralPath $candidate -PathType Container){$folder=$candidate;break}}catch{}}}
        try {
            if(Test-Path -LiteralPath $folder -PathType Container){Start-Process explorer.exe -ArgumentList ('"'+$folder+'"');Write-PnpValue 'Opened folder' $folder $palette.Good}
            else{Write-PnpValue 'No report folder yet' 'Main [6] saves your first snapshot.' $palette.Muted}
        }catch{Write-PnpValue 'STORE-08 / folder not opened' $_.Exception.Message $palette.Warn}
    }
    Add-ReportBookmark '2';Write-Heading 'REPORT LOCATIONS'
    foreach($folder in $locations.Search){
        $state='Not created';$color=$palette.Muted
        try{if(Test-Path -LiteralPath $folder -PathType Container){$state='Folder'}}catch{$state='Access unavailable';$color=$palette.Warn}
        Write-PnpValue $state $folder $color
    }
    Add-ReportBookmark '3';Write-Heading ('FILES NOT READ / '+$catalog.Skipped.Count)
    if(-not $catalog.Skipped.Count){Write-PnpValue 'Result' 'No unreadable or unsupported snapshots detected.' $palette.Good}
    foreach($item in $catalog.Skipped){Write-PnpValue ($item.Code+' / '+[IO.Path]::GetFileName($item.Path)) $item.Reason $palette[$item.Color];Write-PnpValue 'Path' $item.Path $palette.Muted;Write-PnpValue 'Next' $item.Action $palette.Muted}
    Add-ReportBookmark '4';Write-Heading ('TXT WITHOUT JSON / '+$catalog.TextOnly.Count)
    if(-not $catalog.TextOnly.Count){Write-PnpValue 'Result' 'No TXT-only files detected.' $palette.Muted}
    foreach($item in $catalog.TextOnly){Write-PnpValue 'TXT only' $item.FullName $palette.Warn}
    Write-PnpValue 'Keep using files' 'Main [7] chooses a baseline. Main [6] saves a new pair. Existing reports are preserved.' $palette.Muted
}
function Test-ReportWriteFailure($Failure) {
    if($Failure -is [System.Management.Automation.ErrorRecord] -and $Failure.CategoryInfo.Category -eq 'PermissionDenied'){return $true}
    $exception=if($Failure -is [System.Management.Automation.ErrorRecord]){$Failure.Exception}else{$Failure}
    for($depth=0;$null -ne $exception -and $depth -lt 16;$depth++) {
        if($exception -is [UnauthorizedAccessException] -or ($exception -is [IO.IOException] -and $exception -isnot [IO.InvalidDataException])){return $true}
        $exception=$exception.InnerException
    }
    return $false
}
function Write-SnapshotWithFallback($Primary,$Fallback,$Name,$Text,$Json,[scriptblock]$Writer) {
    $primaryFailure=$null
    $folders=@($Primary)
    if($Fallback -and -not [string]::Equals([IO.Path]::GetFullPath($Primary),[IO.Path]::GetFullPath($Fallback),[StringComparison]::OrdinalIgnoreCase)){$folders+=@($Fallback)}
    foreach($folder in $folders) {
        try {
            [void][IO.Directory]::CreateDirectory($folder)
            $stem=Join-Path $folder $Name
            if($Writer){& $Writer $stem $Text $Json | Out-Null}else{Write-ReportPair $stem $Text $Json}
            return [pscustomobject]@{Folder=$folder;Stem=$stem;UsedFallback=($null -ne $primaryFailure);PrimaryFailure=$primaryFailure}
        }catch {
            if(-not (Test-ReportWriteFailure $_)){throw}
            if($folder -eq $Primary -and $folders.Count -gt 1){$primaryFailure=$_.Exception.Message;continue}
            if($primaryFailure){throw [IO.IOException]::new(('Snapshot save failed. Primary: '+$primaryFailure+' / Fallback: '+$_.Exception.Message),$_.Exception)}
            throw
        }
    }
}
function Resolve-ComparisonReportPath($Path) {
    if([IO.Path]::GetExtension($Path) -ieq '.txt') {
        $json=[IO.Path]::ChangeExtension($Path,'.json')
        if(Test-Path -LiteralPath $json -PathType Leaf){Write-PnpValue 'JSON companion' 'Using the matching JSON snapshot for this TXT report.' $palette.Muted;return $json}
        throw 'This TXT report has no matching JSON snapshot. Compare requires the JSON saved by [6].'
    }
    return $Path
}
function Resolve-CompareInput($Value,$Recent) {
    $text=([string]$Value).Trim()
    if(-not $text -or $text -eq '0'){return $null}
    if($text -match '\A[1-9]\z') {
        $index=[int]$text-1
        if($index -ge @($Recent).Count){throw 'That recent-report number is not listed. Paste a JSON path or select a listed number.'}
        return $Recent[$index].FullName
    }
    # Only remove one matching pair; preserve apostrophes and literal path characters.
    $first=$text[0];$last=$text[$text.Length-1]
    if($first -eq [char]34 -or $first -eq [char]39) {
        if($text.Length -lt 2 -or $last -ne $first){throw 'Report path has an unmatched quote. Paste the path again.'}
        $text=$text.Substring(1,$text.Length-2)
    } elseif($last -eq [char]34 -or $last -eq [char]39) {
        throw 'Report path has an unmatched quote. Paste the path again.'
    }
    if([string]::IsNullOrWhiteSpace($text)){throw 'Report path is empty. Choose a listed number, paste a JSON path, or use 0 to go back.'}
    if($text -match '[\x00-\x1f\x7f]'){throw 'Report path contains a control character. Paste a single JSON file path.'}
    return $text
}
function Read-CompareReportPath {
    $locations=Get-ReportLocations
    $catalog=Get-SavedSnapshotCatalog $locations.Search $report
    $page=0
    while($true) {
        Reset-UiPage;Start-UiReport
        Write-Heading 'COMPARE / CHOOSE A SAVED BASELINE'
        Write-PnpValue 'Current scan' ($report.'Report info'.Computer+' / '+(Format-ScanTime $report.'Report info'.Generated)) $palette.Text
        $pages=[math]::Max(1,[math]::Ceiling($catalog.Entries.Count/5.0))
        $page=[math]::Max(0,[math]::Min($page,$pages-1))
        $recent=@($catalog.Entries | Select-Object -Skip ($page*5) -First 5)
        Write-PnpValue 'Saved snapshots' ("$($catalog.Entries.Count) detected / page $($page+1) of $pages / older captures from this PC first") $palette.Muted
        for($i=0;$i -lt $recent.Count;$i++) {
            $style=Get-SnapshotDisplayInfo $recent[$i]
            Write-PnpValue ('['+($i+1)+'] '+$recent[$i].Relation) ($recent[$i].Computer+' / '+(Format-ScanTime $recent[$i].Generated)) $palette[$style.Color]
            Write-PnpValue 'File' $recent[$i].Name $palette.Text
        }
        if(-not $recent.Count){Write-PnpValue 'No snapshots found' 'Save with [6], or use [9] to choose a report elsewhere.' $palette.Muted}
        if($catalog.Skipped.Count){Write-PnpValue 'Not listed' ("$($catalog.Skipped.Count) unreadable/unsupported files or folders. Main [8] explains why.") $(if(@($catalog.Skipped | Where-Object Color -eq 'Error').Count){$palette.Error}else{$palette.Warn})}
        Write-PnpValue 'Colors' 'Green = older baseline / gray = same capture / yellow = check context / red = invalid file.' $palette.Muted
        Write-PnpValue 'Controls' '[1-5] Select / [6] Next page / [7] Previous / [8] Refresh / [9] Path / [0] Back' $palette.Muted
        Write-PnpValue 'Path' 'You can also paste a JSON path directly. TXT uses its matching JSON. Blank = Back.' $palette.Muted
        Complete-UiReport
        $value=Read-CheckerLine 'Report'
        $command=([string]$value).Trim()
        if($command -eq '6'){$page++;continue}
        if($command -eq '7'){$page--;continue}
        if($command -eq '8'){$catalog=Get-SavedSnapshotCatalog $locations.Search $report;continue}
        if($command -eq '9'){$value=Read-CheckerLine 'JSON or TXT report path (0 = Back)'}
        $path=Resolve-CompareInput $value $recent
        if(-not $path){return $null}
        return (Resolve-ComparisonReportPath $path)
    }
}
function Get-ComparisonDetails($Comparison) {
    $groups=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach($change in $Comparison.Changes) {
        $parts=Convert-ReportJson $change.InputObject
        $key=ConvertTo-Json -InputObject @($parts[0],$parts[1],$parts[2]) -Compress
        if(-not $groups.ContainsKey($key)){$groups[$key]=[pscustomobject]@{Section=$parts[0];Device=$parts[1];Field=$parts[2];Old=(New-Object 'System.Collections.Generic.List[string]');New=(New-Object 'System.Collections.Generic.List[string]')}}
        if($change.SideIndicator -eq '=>'){$groups[$key].New.Add($parts[3])}else{$groups[$key].Old.Add($parts[3])}
    }
    foreach($group in ($groups.Values | Sort-Object Section,Device,Field)) {
        if($group.Old.Count -eq 1 -and $group.New.Count -eq 1) {
            [pscustomobject]@{Section=$group.Section;Device=$group.Device;Field=$group.Field;Kind='Changed';Previous=$group.Old[0];Current=$group.New[0]}
        } else {
            foreach($value in $group.Old){[pscustomobject]@{Section=$group.Section;Device=$group.Device;Field=$group.Field;Kind='Previous only';Previous=$value;Current=$null}}
            foreach($value in $group.New){[pscustomobject]@{Section=$group.Section;Device=$group.Device;Field=$group.Field;Kind='Current only';Previous=$null;Current=$value}}
        }
    }
}
function Get-IdentifierChangeText($Before,$After) {
    $old=[string]$Before;$new=[string]$After
    if($old -ceq $new){return 'No characters changed.'}
    if($old.Length -eq $new.Length) {
        $positions=New-Object 'System.Collections.Generic.List[int]'
        for($i=0;$i -lt $old.Length;$i++){if($old[$i] -cne $new[$i]){$positions.Add($i+1)}}
        if($positions.Count -eq 1){$position=$positions[0];return ("1 character changed at position ${position}: "+$old[$position-1]+' -> '+$new[$position-1])}
        if($positions[-1]-$positions[0]+1 -eq $positions.Count) {
            $first=$positions[0];$last=$positions[-1]
            return ("$($positions.Count) characters changed at positions ${first}-${last}: "+$old.Substring($first-1,$positions.Count)+' -> '+$new.Substring($first-1,$positions.Count))
        }
        return ("$($positions.Count) characters changed at positions "+($positions -join ', ')+'.')
    }
    $prefix=0;$suffix=0
    while($prefix -lt [math]::Min($old.Length,$new.Length) -and $old[$prefix] -ceq $new[$prefix]){$prefix++}
    while($suffix -lt ($old.Length-$prefix) -and $suffix -lt ($new.Length-$prefix) -and $old[$old.Length-1-$suffix] -ceq $new[$new.Length-1-$suffix]){$suffix++}
    $oldPart=$old.Substring($prefix,$old.Length-$prefix-$suffix)
    $newPart=$new.Substring($prefix,$new.Length-$prefix-$suffix)
    $position=$prefix+1
    if(-not $oldPart.Length){return ('Inserted "'+$newPart+'" at position '+$position+'.')}
    if(-not $newPart.Length){return ('Removed "'+$oldPart+'" at position '+$position+'.')}
    return ('Replaced "'+$oldPart+'" with "'+$newPart+'" starting at position '+$position+'.')
}
function Show-ComparisonResult($Previous,$Current,$Comparison,$SourcePath) {
    if($null -eq $Comparison){$Comparison=Compare-Inventories $Previous $Current}
    Reset-UiPage;Start-UiReport
    Add-ReportBookmark '1'
    Write-Heading 'COMPARE RESULTS / PREVIOUS -> CURRENT'
    Write-PnpValue 'Controls' '1 Summary / 2 ID changes / 3 Not compared. 0 or Enter = menu.' $palette.Muted
    if($SourcePath){Write-PnpValue 'Baseline file' $SourcePath $palette.Muted}
    Write-PnpValue 'Previous' ($Previous.'Report info'.Computer+' / '+(Format-ScanTime $Previous.'Report info'.Generated)) $palette.Muted
    Write-PnpValue 'Current' ($Current['Report info'].Computer+' / '+(Format-ScanTime $Current['Report info'].Generated)) $palette.Text
    if($Previous.'Report info'.Computer -ne $Current['Report info'].Computer){Write-PnpValue 'REVIEW' 'These reports have different computer names; verify that this is the intended comparison.' $palette.Warn}
    $oldTime=Get-ReportCaptureTime $Previous.'Report info';$newTime=Get-ReportCaptureTime $Current.'Report info'
    if($null -ne $oldTime -and $null -ne $newTime) {
        if($oldTime -eq $newTime){Write-PnpValue 'Same capture time' 'This may be a save of the active scan. Choose an OLDER snapshot to check changes over time.' $palette.Warn}
        elseif($oldTime -gt $newTime){Write-PnpValue 'Time order' 'The selected baseline is newer than this active scan. OLD means selected file; NEW means active scan.' $palette.Warn}
    }
    if($Comparison.AmbiguousDevices.Count){
        Write-PnpValue 'SCAN CONFLICT' ("$($Comparison.AmbiguousDevices.Count) device matches are ambiguous; these IDs are not compared.") $palette.Warn
        foreach($conflict in $Comparison.AmbiguousDevices){$keyLabel=if($conflict.DeviceKey){$conflict.DeviceKey}else{'no reliable device key'};Write-PnpValue 'Skipped device' ($conflict.Section+' / '+$keyLabel+' / '+($conflict.Sources -join ' + ')+' report') $palette.Warn}
    }
    Write-PnpValue 'Comparable fields' ("$($Comparison.PreviousCount) previous / $($Comparison.CurrentCount) current") $palette.Text
    if($Comparison.UnkeyedSections.Count){Write-PnpValue 'Missing device keys' (($Comparison.UnkeyedSections -join ', ')+'. Records cannot be matched reliably; these sections are skipped.') $palette.Warn}
    if(-not $Comparison.PreviousCount -and -not $Comparison.CurrentCount){throw 'No usable IDs in sections readable in both reports.'}
    $details=@(Get-ComparisonDetails $Comparison)
    $incomplete=$Comparison.SkippedSections.Count -or $Comparison.SkippedFields
    Add-ReportBookmark '2'
    if(-not $details.Count) {
        if($incomplete){Write-PnpValue 'RESULT' 'No differences found in available data. Some IDs could not be checked.' $palette.Warn}
        else {Write-PnpValue 'RESULT' 'No identifier differences found in the saved scan.' $palette.Good}
    } else {
        $changed=@($details | Where-Object Kind -eq 'Changed').Count
        $added=@($details | Where-Object Kind -eq 'Current only').Count
        $removed=@($details | Where-Object Kind -eq 'Previous only').Count
        Write-PnpValue 'RESULT' ("$changed changed / $added current only / $removed previous only") $palette.Warn
        $changeNumber=0
        foreach($group in ($details | Group-Object Section)) {
            Write-Heading $group.Name
            foreach($item in $group.Group) {
                $changeNumber++
                Write-PnpValue ('#'+$changeNumber+' / '+$item.Kind) ((Get-FieldLabel $item.Field)+$(if($item.Device){' / '+$item.Device})) $palette.Text
                if($null -ne $item.Previous){Write-PnpValue 'OLD ID / saved' $item.Previous $palette.Warn}
                if($null -ne $item.Current){Write-PnpValue 'NEW ID / now' $item.Current $palette.Heading}
                if($item.Kind -eq 'Changed'){Write-PnpValue 'Exact difference' (Get-IdentifierChangeText $item.Previous $item.Current) $palette.Text}
            }
        }
    }
    Add-ReportBookmark '3'
    Write-Heading 'NOT COMPARED'
    if($incomplete) {
        if($Comparison.SkippedSections.Count){Write-PnpValue 'Sections' ($Comparison.SkippedSections -join ', ') $palette.Warn}
        if($Comparison.UnkeyedSections.Count){Write-PnpValue 'Reason / device keys' 'Slot or instance keys were missing; no device match was guessed.' $palette.Warn}
        if($Comparison.SkippedFields){Write-PnpValue 'Fields' ("$($Comparison.SkippedFields) missing/default or absent in one report schema") $palette.Warn}
    }else{Write-PnpValue 'Coverage' 'No identifier fields were skipped by this comparison.' $palette.Good}
    Write-PnpValue 'Scope' 'Basic identifier fields, including monitor serials. Full PnP lists and partition paths are inventory details.' $palette.Muted
    Write-PnpValue 'Positions' 'Character positions start at 1. IDs keep leading zeros and letter case.' $palette.Muted
    Write-PnpValue 'Note' 'Moving devices between slots or ports can produce differences; current/previous-only does not prove a physical device was added or removed.' $palette.Muted
}
function Copy-InventorySnapshot($Value) {
    if($null -eq $Value){return $null}
    if($Value -is [System.Collections.IDictionary]) {
        $copy=[ordered]@{}
        foreach($key in $Value.Keys){$copy[$key]=Copy-InventorySnapshot $Value[$key]}
        return $copy
    }
    if($Value -is [array]) {
        $copy=[object[]]::new($Value.Count)
        for($i=0;$i -lt $Value.Count;$i++){$copy[$i]=Copy-InventorySnapshot $Value[$i]}
        return ,$copy
    }
    if($Value -is [System.Management.Automation.PSCustomObject]) {
        $copy=[ordered]@{}
        foreach($property in $Value.PSObject.Properties){$copy[$property.Name]=Copy-InventorySnapshot $property.Value}
        return [pscustomobject]$copy
    }
    return $Value
}
function Get-PnpNodeChanges($Previous,$Current) {
    $before=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $after=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $reason=''
    foreach($side in @('Before','After')) {
        $records=if($side -eq 'Before'){$Previous}else{$Current}
        if(-not (Test-SectionReadable $records)){$reason='Device nodes were not readable in both snapshots.';break}
        $map=if($side -eq 'Before'){$before}else{$after}
        foreach($record in $records) {
            $key=Normalize-IdentifierText $record.DeviceInstanceId
            if(-not $key -or $map.ContainsKey($key)){$reason='Missing or duplicate instance IDs prevent reliable matching.';break}
            $map[$key]=$record
        }
        if($reason){break}
    }
    $added=@();$removed=@()
    if(-not $reason) {
        $added=@(foreach($key in $after.Keys){if(-not $before.ContainsKey($key)){$after[$key]}})
        $removed=@(foreach($key in $before.Keys){if(-not $after.ContainsKey($key)){$before[$key]}})
    }
    [pscustomobject]@{Comparable=(-not $reason);Reason=$reason;Added=$added;Removed=$removed}
}
function Show-RescanResult($Previous,$Current) {
    Reset-UiPage;Start-UiReport
    Add-ReportBookmark '1'
    Write-Heading 'RESCAN RESULTS / PREVIOUS -> CURRENT'
    Write-PnpValue 'Controls' '1 Summary / 2 ID changes / 3 Device arrivals and removals. 0 or Enter = menu.' $palette.Muted
    $coverage=@(Get-ScanCoverage $Current)
    $read=($coverage | Measure-Object Read -Sum).Sum
    Write-PnpValue 'Snapshot' ("#$($Current['Report info'].ScanNumber) / $read of $scanTotal sections read / $($Current['Report info'].ScanSeconds)s") $(if($read -eq $scanTotal){$palette.Good}else{$palette.Warn})
    Write-PnpValue 'Previous capture' (Format-ScanTime $Previous['Report info'].Generated) $palette.Muted
    Write-PnpValue 'New capture' (Format-ScanTime $Current['Report info'].Generated) $palette.Text
    if($Current['Report info'].ExtendedStatus) {
        Write-PnpValue 'Extended catalog' $Current['Report info'].ExtendedStatus $(if($Current['Report info'].ExtendedStatus -eq 'Refreshed'){$palette.Good}else{$palette.Warn})
    }
    foreach($row in $coverage | Where-Object Status -ne 'OK') {
        Write-PnpValue 'Not fully read' ($row.Area+" / $($row.Read) of $($row.Total). See [4] from the main menu.") $palette.Warn
    }
    $oldPnp=$Previous['PnP hardware IDs'];$newPnp=$Current['PnP hardware IDs']
    if((Test-SectionReadable $oldPnp) -and (Test-SectionReadable $newPnp)) {
        Write-PnpValue 'Present device nodes' ("$(@($oldPnp).Count) previous -> $(@($newPnp).Count) current") $palette.Text
    }else{Write-PnpValue 'Device node counts' 'Unavailable in one snapshot; no device count change inferred.' $palette.Warn}
    $comparison=Compare-Inventories $Previous $Current
    $details=@(Get-ComparisonDetails $comparison)
    Add-ReportBookmark '2'
    Write-Heading 'IDENTIFIER CHANGES'
    if(-not $comparison.PreviousCount -and -not $comparison.CurrentCount) {
        Write-PnpValue 'Not compared' 'No usable identifier fields were available in both snapshots.' $palette.Warn
    }elseif(-not $details.Count) {
        Write-PnpValue 'Result' 'No changes in comparable identifier fields.' $(if($comparison.SkippedSections.Count -or $comparison.SkippedFields){$palette.Warn}else{$palette.Good})
    }else {
        $changed=@($details | Where-Object Kind -eq 'Changed').Count
        $added=@($details | Where-Object Kind -eq 'Current only').Count
        $removed=@($details | Where-Object Kind -eq 'Previous only').Count
        Write-PnpValue 'Result' ("$changed changed / $added current only / $removed previous only") $palette.Warn
        foreach($item in $details) {
            Write-PnpValue $item.Kind ($item.Section+' / '+(Get-FieldLabel $item.Field)+' / '+$item.Device) $palette.Text
            if($null -ne $item.Previous){Write-PnpValue 'OLD ID' $item.Previous $palette.Warn}
            if($null -ne $item.Current){Write-PnpValue 'NEW ID' $item.Current $palette.Heading}
            if($item.Kind -eq 'Changed'){Write-PnpValue 'Exact difference' (Get-IdentifierChangeText $item.Previous $item.Current) $palette.Text}
        }
    }
    if($comparison.SkippedSections.Count){Write-PnpValue 'Not compared / sections' ($comparison.SkippedSections -join ', ') $palette.Warn}
    if($comparison.SkippedFields){Write-PnpValue 'Not compared / fields' ("$($comparison.SkippedFields) missing, default, ambiguous, or absent in one schema") $palette.Warn}
    Add-ReportBookmark '3'
    Write-Heading 'DEVICE ARRIVALS AND REMOVALS'
    $nodes=Get-PnpNodeChanges $oldPnp $newPnp
    if(-not $nodes.Comparable){Write-PnpValue 'Not compared' $nodes.Reason $palette.Warn}
    else {
        Write-PnpValue 'Present records' ("$($nodes.Added.Count) arrived / $($nodes.Removed.Count) no longer present") $(if($nodes.Added.Count -or $nodes.Removed.Count){$palette.Warn}else{$palette.Good})
        foreach($node in $nodes.Added | Sort-Object Name,DeviceInstanceId){Write-PnpValue 'ARRIVED' $node.Name $palette.Heading;Write-PnpValue 'Instance' $node.DeviceInstanceId $palette.Muted}
        foreach($node in $nodes.Removed | Sort-Object Name,DeviceInstanceId){Write-PnpValue 'NO LONGER PRESENT' $node.Name $palette.Warn;Write-PnpValue 'Previous instance' $node.DeviceInstanceId $palette.Muted}
    }
    Write-PnpValue 'Meaning' 'Node changes include virtual devices, port moves and Windows records; they do not prove physical hardware replacement.' $palette.Muted
    Write-PnpValue 'Scope' 'Basic ID fields; full PnP lists and partition paths are inventory details. Device counts include virtual nodes.' $palette.Muted
    Write-PnpValue 'Save this scan' 'Main [6] saves the current snapshot. Saved reports are never overwritten by a rescan.' $palette.Text
}
function Start-HardwareRescan([bool]$UseWorker=($ownedConsole -and -not $redirected),[scriptblock]$ContinueReader) {
    try {
        $next=1+[int]$report['Report info'].ScanNumber
        $snapshot=Invoke-HardwareScan $next -UseWorker $UseWorker -IncludeExtended ($report.Contains('Extended scan info') -or $report['Report info'].ExtendedStatus -eq 'Unavailable')
        if(-not $snapshot.Completed -or $snapshot.Inventory -isnot [System.Collections.IDictionary] -or $snapshot.Inventory['Report info'].ScanNumber -ne $next -or @($snapshot.Inventory['Scan timing']).Count -ne $scanTotal){throw 'The scan did not return a complete snapshot.'}
        foreach($name in @($sectionGroups.Values | ForEach-Object {$_})+@('PnP hardware IDs')) {
            if(-not $snapshot.Inventory.Contains($name)){throw ('The scan did not return section: '+$name)}
        }
        if($snapshot.Warnings -isnot [System.Collections.Generic.List[string]] -or $snapshot.Identifiers -isnot [array]){throw 'The scan returned inconsistent warning or identifier data.'}
        $previous=Copy-InventorySnapshot $report
        $current=Copy-InventorySnapshot $snapshot.Inventory
        # Assign all live state from the same finished snapshot.
        $script:lastScanPrevious=$previous
        $script:lastScanCurrent=$current
        $script:report=$snapshot.Inventory
        $script:warnings=$snapshot.Warnings
        $script:identifiers=$snapshot.Identifiers
    }catch {
        Reset-UiPage;Start-UiReport
        Write-Heading 'RESCAN / NOT COMPLETED'
        Write-PnpValue 'SCAN-01' $_.Exception.Message $palette.Error
        Write-PnpValue 'Previous snapshot kept' 'The earlier scan is still active. Try [9] > [1] again.' $palette.Warn
        return
    }
    try {Wait-ScanContinue 'snapshot changes' -KeyReader $ContinueReader;Show-RescanResult $lastScanPrevious $lastScanCurrent}
    catch {Write-PnpValue 'RESCAN-02 / summary unavailable' ($_.Exception.Message+' The new snapshot is active; use [1] or [5] from the main menu.') $palette.Warn}
}
function Show-ScanTools {
    Write-Heading 'RESCAN & HELP'
    Write-PnpValue 'Active snapshot' ("#$($report['Report info'].ScanNumber) / "+(Format-ScanTime $report['Report info'].Generated)) $palette.Text
    Show-MenuItem '1' 'Rescan entire PC' 'Refresh 17 sections plus any previously scanned extended catalog; compare results.'
    Show-MenuItem '2' 'Help / explain IDs and colors' ''
    Show-MenuItem '3' 'Review last rescan changes' ''
    Show-MenuItem '4' 'Extended device scan / hidden & disconnected' ''
    Show-MenuItem '0' 'Back to main menu' ''
    Write-PnpValue 'Before rescanning' 'Use main [6] to keep the current snapshot as TXT + JSON. Rescanning does not save automatically.' $palette.Muted
    Write-PnpValue 'Scope' 'Reads devices currently exposed by Windows; some IDs require administrator access or are not supplied.' $palette.Muted
    Complete-UiReport
    $selection=Read-MenuChoice -Maximum 4
    if($null -eq $selection -or $selection -eq '0'){return $false}
    Show-UiTransition 'Next' $(if($selection -eq '1'){'Rescan PC'}elseif($selection -eq '2'){'Help'}elseif($selection -eq '4'){'Extended device scan'}else{'Last rescan changes'})
    Reset-UiPage;Start-UiReport
    switch($selection) {
        '1' {Start-HardwareRescan}
        '2' {Show-Help}
        '4' {Start-ExtendedDeviceScan}
        '3' {
            if($null -ne $lastScanPrevious -and $null -ne $lastScanCurrent){Show-RescanResult $lastScanPrevious $lastScanCurrent}
            else {Write-Heading 'NO RESCAN YET';Write-PnpValue 'Next' 'Choose main [9] > [1] to rescan first.' $palette.Muted}
        }
    }
    return $true
}
function Save-Reports {
    Write-Heading 'SAVE REPORTS / TXT + JSON'
    try {
        foreach($command in @('ConvertTo-Json','ConvertFrom-Json')) {
            if(-not (Get-Command $command -ErrorAction SilentlyContinue)){throw ('JSON reports are unavailable: missing '+$command+'. Repair Microsoft.PowerShell.Utility for this runtime.')}
        }
        # Add save metadata to an independent copy; the active scan keeps its capture identity.
        $report=Copy-InventorySnapshot $report
        $info=[ordered]@{}
        $properties=if($report['Report info'] -is [System.Collections.IDictionary]){foreach($key in $report['Report info'].Keys){[pscustomobject]@{Name=$key;Value=$report['Report info'][$key]}}}else{$report['Report info'].PSObject.Properties}
        foreach($property in $properties){$info[$property.Name]=$property.Value}
        $info['SavedAt']=(Get-Date).ToString('o');$report['Report info']=$info
        $locations=Get-ReportLocations
        $name='HWID-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $lines = @(
            'HWID CHECKER - HARDWARE REPORT'
            '========== Report info =========='
            (Get-PlainRecords $report['Report info'])
            if($report.Contains('Compatibility')){'========== Runtime compatibility ==========';Get-PlainRecords $report['Compatibility']}
            foreach ($group in $sectionGroups.Keys) {
                "`n========== $group =========="
                foreach ($key in $sectionGroups[$group]) {
                    if ($report.Contains($key)) {
                        "--- $key ---"
                        Get-PlainRecords $report[$key]
                    }
                }
            }
            if($report.Contains('PnP hardware IDs')) {
                '========== PnP hardware IDs =========='
                Get-PlainRecords $report['PnP hardware IDs']
            }
            if($report.Contains('Extended scan info')) {
                '========== Extended scan / separate capture =========='
                Get-PlainRecords $report['Extended scan info']
                Get-PlainRecords $report['Extended device inventory']
            }
            if($report.Contains('Scan timing')){'========== Scan timing / seconds ==========';Get-PlainRecords $report['Scan timing']}
            '========== Inventory record conflicts =========='
            foreach($conflict in (Get-InventoryConflicts $report)){('  {0} / {1}: {2}' -f $conflict.Section,$conflict.DeviceKey,$conflict.Message)}
            '========== Warnings =========='
            $report['Warnings']
        )
        $json=$report | ConvertTo-Json -Depth 12 -ErrorAction Stop -WarningAction Stop
        $text=($lines -join [Environment]::NewLine)+[Environment]::NewLine
        $saved=Write-SnapshotWithFallback $locations.Primary $locations.Fallback $name $text $json
        $folder=$saved.Folder;$stem=$saved.Stem
        $script:lastSavedReportPath=$stem+'.json'
        Write-PnpValue 'SAVED' 'TXT + JSON created; both final files verified.' $palette.Good
        if($saved.UsedFallback){Write-PnpValue 'Fallback location' 'The normal report folder could not be written. The snapshot was saved in your local app-data folder.' $palette.Warn;Write-PnpValue 'Primary save issue' $saved.PrimaryFailure $palette.Muted}
        Write-PnpValue 'Computer / scan' ($report['Report info'].Computer+' / '+(Format-ScanTime $report['Report info'].Generated)) $palette.Text
        Write-PnpValue 'Saved at' (Format-ScanTime $report['Report info'].SavedAt) $palette.Text
        $coverage=@(Get-ScanCoverage $report);$read=($coverage | Measure-Object Read -Sum).Sum;$total=($coverage | Measure-Object Total -Sum).Sum
        Write-PnpValue 'Scan coverage' ("$read/$total normal sections readable in this saved capture. Saving does not rescan.") $(if($read -eq $total){$palette.Good}else{$palette.Warn})
        Write-PnpValue 'Folder' $folder $palette.Muted
        Write-PnpValue 'TXT / read' ([IO.Path]::GetFileName($stem)+'.txt') $palette.Text
        Write-PnpValue 'JSON / compare' ([IO.Path]::GetFileName($stem)+'.json') $palette.Heading
        try {
            $catalog=Get-SavedSnapshotCatalog $locations.Search $report
            $older=@($catalog.Entries | Where-Object {$_.SamePc -and $_.Older -and $_.UsableIds -gt 0}).Count
            Write-PnpValue 'Older snapshots' ("$older usable baselines from this PC detected / $($catalog.Entries.Count) saved JSON snapshots total") $(if($older){$palette.Good}else{$palette.Muted})
            if($catalog.Skipped.Count){Write-PnpValue 'Not listed' ("$($catalog.Skipped.Count) unreadable/unsupported files or folders; Main [8] explains why.") $(if(@($catalog.Skipped | Where-Object Color -eq 'Error').Count){$palette.Error}else{$palette.Warn})}
        }catch{Write-PnpValue 'Snapshot lookup' 'Save succeeded. Automatic lookup was unavailable; [7] also accepts a path.' $palette.Warn}
        Write-PnpValue 'Next' '[7] Choose an older snapshot to compare IDs / [8] Saved reports and storage status' $palette.Heading
    } catch {
        Write-PnpValue 'SAVE-01 / not completed' $_.Exception.Message $palette.Error
    }
}
$script:lastScanPrevious=$null
$script:lastScanCurrent=$null
$script:lastSavedReportPath=$null
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$initialScan=Invoke-HardwareScan
$script:report=$initialScan.Inventory
$script:warnings=$initialScan.Warnings
$script:identifiers=$initialScan.Identifiers
$initialScan=$null
if ($redirected -or -not $ownedConsole) { Show-Overview }
Wait-ScanContinue 'main menu'
:MainMenu while ($true) {
    Show-ControlDeck
    $choice = Read-MenuChoice
    if ($null -eq $choice) { return }
    if ($choice -match '^[1-9]$') { Show-UiTransition 'Next' (Get-MenuDestination $choice); Reset-UiPage; Start-UiReport }
    switch ($choice) {
        '2' {
            Show-QuickIds
            if($ownedConsole -and -not $redirected){Wait-UiPage}else{Read-CheckerLine 'Press Enter to return to the menu' | Out-Null}
        }
        '5' {
            Show-FullReport
        }
        '6' { Save-Reports }
        '3' { if(-not (Show-Categories)){Show-UiTransition 'Back';continue MainMenu} }
        '4' { Show-Attention }
        '9' { if(-not (Show-ScanTools)){Show-UiTransition 'Back';continue MainMenu} }
        '1' { Show-Overview }
        '7' {
            try {
                $previousPath=Read-CompareReportPath
                if (-not $previousPath) { Show-UiTransition 'Back'; continue MainMenu }
                $previous=Read-SavedReport $previousPath
                Show-ComparisonResult $previous $report -SourcePath $previousPath
            } catch { Write-PnpValue 'COMPARE-01 / unavailable' $_.Exception.Message $palette.Warn }
        }
        '8' {Show-SnapshotStorage -OpenFolder}
        '0' { Show-UiTransition 'Exit'; return }
        default { Show-MenuInputError; continue }
    }
    if ($choice -ne '2') { Wait-UiPage }
    Show-UiTransition 'Back'
}
