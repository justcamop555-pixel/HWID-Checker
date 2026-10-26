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
function Get-HwidInstance {
    param([Parameter(Position=0)][string]$ClassName,[string]$Namespace='root/cimv2',[string]$Filter,[string[]]$Property,[int]$OperationTimeoutSec=20)
    $cim=Get-Command Get-CimInstance -ErrorAction SilentlyContinue
    if($null -ne $cim) {
        $arguments=@{ClassName=$ClassName;Namespace=$Namespace;OperationTimeoutSec=$OperationTimeoutSec;ErrorAction='Stop'}
        if($Filter){$arguments.Filter=$Filter}
        if($Property){$arguments.Property=$Property}
        return (& $cim @arguments)
    }
    $wmi=Get-Command Get-WmiObject -ErrorAction SilentlyContinue
    if($null -ne $wmi) {
        $arguments=@{Class=$ClassName;Namespace=$Namespace;ErrorAction='Stop'}
        if($Filter){$arguments.Filter=$Filter}
        if($Property){$arguments.Property=$Property}
        return (& $wmi @arguments)
    }
    throw 'No CIM or legacy WMI reader is available. Repair/install the approved Windows PowerShell/CimCmdlets component.'
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
    $bar=(' '*$cells).ToCharArray()
    $time=$step/17.0
    $progress=$time*$time*(3-2*$time)
    if($Direction -eq 'Exit') {
        $label=if($step -eq 17){'EXIT / Goodbye'}else{'EXIT / Closing console'}
        $edge=[int][math]::Ceiling(($cells/2.0)*$progress)
        for($i=$edge;$i -lt $cells-$edge;$i++){$bar[$i]='='}
        if($edge -gt 0 -and $edge -lt $cells-$edge){$bar[$edge]='>';$bar[$cells-$edge-1]='<'}
    } else {
        $label=if($Direction -eq 'Back'){'BACK / Main menu'}elseif($Destination){'NEXT / '+$Destination}else{'NEXT / Opening page'}
        $position=[int][math]::Round(($cells-2)*$progress)
        if($Direction -eq 'Back'){$position=$cells-2-$position}
        $arrow=if($Direction -eq 'Back'){'<'}else{'>'}
        $bar[$position]=$arrow; $bar[$position+1]=$arrow
        for($trail=1;$trail -le 4;$trail++) {
            $tail=if($Direction -eq 'Back'){$position+1+$trail}else{$position-$trail}
            if($tail -ge 0 -and $tail -lt $cells){$bar[$tail]='.'}
        }
    }
    $label=$label -replace '[\x00-\x1F\x7F]',' '
    return (Limit-TableText ('  ['+(-join $bar)+']  '+$label) ([math]::Max(0,$Width)))
}
function Get-UiTransitionDuration($Direction) {
    switch($Direction){'Back'{return 180};'Exit'{return 280};default{return 220}}
}
function Show-UiTransition([ValidateSet('Back','Next','Exit')]$Direction,$Destination) {
    if(-not $ownedConsole -or $redirected -or $env:HWID_NO_ANIMATION -eq '1'){return}
    $saved=$false
    $patch=$null
    try {
        if([Console]::IsOutputRedirected -or [Console]::IsInputRedirected){return}
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
        $edge='  +'+('-'*($width-5))+'+'
        $clock=[Diagnostics.Stopwatch]::StartNew()
        for($frame=0;$frame -le 17;$frame++) {
            if([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height -or [Console]::WindowTop -ne $viewTop -or [Console]::WindowLeft -ne $viewLeft){break}
            $step=[math]::Max($frame,[math]::Min(17,[int][math]::Floor(17*$clock.Elapsed.TotalMilliseconds/$duration)))
            $lines=[string[]]@($edge,(Get-UiTransitionFrame $Direction $step ($width-1) $Destination),$edge)
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
function Wait-UiPage([scriptblock]$KeyReader) {
    if ($ownedConsole -and -not $redirected) {
        Start-UiReport
        Write-Host '  Scroll: mouse wheel / Up Down / PgUp PgDn / Home End. Enter = menu.' -ForegroundColor $palette.Muted
        Complete-UiReport
        $bookmarked=$null -ne $script:reportBookmarks -and $script:reportBookmarks.Count -gt 0
        if($bookmarked){Move-UiReportView 'Home'}
        while($true) {
            $key=if($KeyReader){& $KeyReader}else{[Console]::ReadKey($true)}
            if($null -eq $key){return}
            if($key.Key -eq [ConsoleKey]::Enter){return}
            if($bookmarked) {
                if($key.KeyChar -eq '0'){return}
                Move-ReportBookmark ([string]$key.KeyChar)
            }
            Move-UiReportView ($key.Key.ToString())
        }
    } elseif(-not $redirected) {
        Read-CheckerLine 'Press Enter to return to the menu' | Out-Null
    }
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
    @('3','Browse hardware / devices','8','Open saved reports folder'), @('4','Check warnings / conflicts','9','Rescan / extended devices / help'),
    @('5','Full inventory report','0','Exit')
}
function Show-CompactDeck($Width) {
    $size=[math]::Max(8,$Width-1)
    Write-Host (Limit-TableText '  HWID / MAIN MENU' $size) -ForegroundColor $palette.Heading
    $found=@($identifiers | Where-Object Quality -eq 'Reported').Count
    $review=@($identifiers | Where-Object Quality -ne 'Reported').Count+$warnings.Count+@(Get-QuickDisks $report | Where-Object Quality -eq 'Conflict').Count+@(Get-PnpIssues $report['PnP hardware IDs']).Count
    $duplicateCount=@(Get-InventoryConflicts $report).Count
    $review+=$duplicateCount
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
    Write-Host '  HWID CHECKER  /  v3.40' -ForegroundColor $palette.Text
    $access=if($admin){'Administrator'}else{'Standard user'}
    Write-Host ("  "+$report['Report info'].Computer+"  /  $access  /  Read-only scan") -ForegroundColor $palette.Muted
    $found=@($identifiers | Where-Object Quality -eq 'Reported').Count
    $review=@($identifiers | Where-Object Quality -ne 'Reported').Count+$warnings.Count+@(Get-QuickDisks $report | Where-Object Quality -eq 'Conflict').Count+@(Get-PnpIssues $report['PnP hardware IDs']).Count+@(Get-InventoryConflicts $report).Count
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
function Test-SectionReadable($Records) {
    $items = @($Records | Where-Object { $null -ne $_ })
    return $items.Count -gt 0 -and @($items | Where-Object { $_.Unavailable }).Count -eq 0
}
function Get-FieldLabel($Name) {
    $labels = @{
        PartitionGuid='Unique GPT partition ID'; GptType='GPT partition type (shared category)'; MbrType='MBR partition type code'; AccessPaths='Volume GUID / access paths'; DiskNumber='Disk number'; PartitionNumber='Partition number'
        ScanSeconds='Total scan time (seconds)'; ScanCompleted='Scan completed'; ScanNumber='Session snapshot number'; QueryMode='Scan mode'; Seconds='Query time (seconds)'; Results='Records returned'
        PowerShellVersion='PowerShell version';WindowsVersion='Windows version';QueryBackend='Hardware query backend';MissingCommands='Unavailable commands (may be optional)';LanguageMode='PowerShell language mode'
        ProcessorId='CPU identifier'; UUID='System UUID'; SerialNumber='Serial number'
        DeviceInstanceId='Device instance ID'; HardwareID='Hardware IDs (driver match)'; CompatibleID='Compatible driver IDs'; ConfigManagerErrorCode='Windows device status code'
        IdentifyingNumber='System serial number'; MachineGuid='Windows installation ID'
        PNPDeviceID='Windows device ID'; SMBIOSAssetTag='Asset tag'
        SMBIOSBIOSVersion='BIOS version'; SMBIOSMajorVersion='SMBIOS major version'; SMBIOSMinorVersion='SMBIOS minor version'
        TotalRAM_GiB='Total memory (GiB)'; Capacity_GiB='Module size (GiB)'; Size_GiB='Size (GiB)'; Free_GiB='Free space (GiB)'
        MaxClockSpeed='Maximum CPU clock (MHz)'; Speed='Rated speed (MHz)'; ConfiguredClockSpeed='Configured speed (MHz)'
        MacAddress='Current MAC address'; PermanentAddress='Permanent MAC address'; InterfaceGuid='Network interface ID'
        CollectionSource='Read using'; UniqueIdFormat='Storage ID format (Windows code)'
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
    if ($Name -in @('PermanentAddress','MacAddress','PNPDeviceID') -and [string]::IsNullOrWhiteSpace([string]$Value) -and $null -ne $Record.HardwareInterface -and $Record.HardwareInterface -eq $false) { return 'Not applicable' }
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
        @('Motherboard','SerialNumber','Board serial'), @('BIOS','SerialNumber','BIOS serial'),
        @('CPU','ProcessorId','CPU'), @('Memory modules','SerialNumber','RAM'),
        @('Disk summary','',''), @('Volumes','VolumeSerialNumber','Volume'),
        @('Monitors','SerialNumber','Monitor'), @('Network adapters','MacAddress','Net'), @('Windows Machine GUID','MachineGuid','Windows ID')
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
                'Monitors' { " $index" }
                'CPU' { if (@($records).Count -gt 1) { " $index" } }
                'Memory modules' { if ($record.DeviceLocator) { " $index " + $record.DeviceLocator } else { " $index" } }
                'Physical disks' { if ($null -ne $record.Index) { ' ' + $record.Index } else { " $index" } }
                'Storage identifiers' { if ($null -ne $record.Number) { ' ' + $record.Number } else { " $index" } }
                'Volumes' { ' ' + $record.DeviceID }
                'Network adapters' { if ($record.Name) { " $index " + $record.Name } else { " $index" } }
                default { '' }
            }
            $value = Normalize-IdentifierText $record.$field
            $quality=Get-FieldQuality $field $value $record
            if($quality -eq 'Not applicable'){continue}
            [pscustomobject]@{Label=($label + $suffix);Value=$value;Quality=$quality}
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
        $value = Normalize-IdentifierText $disk.SerialNumber
        $quality = Get-Quality $value
        $note = ''
        if ($matches.Count -eq 1) {
            [void]$used.Add([int]$matches[0].Number)
            $other = Normalize-IdentifierText $matches[0].SerialNumber
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
        $value = Normalize-IdentifierText $disk.SerialNumber
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
    Start-UiReport
    Write-Heading 'DEVICE IDs / QUICK VIEW'
    $rows = @(Get-QuickIds $report)
    if (-not $rows.Count) { Write-Host '  No IDs available. Use [4] to check why.' -ForegroundColor $palette.Warn; return }
    $windowWidth = 72
    try { if ([Console]::WindowWidth -gt 0) { $windowWidth = [Console]::WindowWidth } } catch { }
    $stacked=$windowWidth -lt 45
    $layout = Get-QuickLayout $windowWidth
    $valueWidth = $layout.ValueWidth; $labelWidth=$layout.LabelWidth
    $format = '  {0,-' + $labelWidth + '}  {1,-' + $valueWidth + '}  {2}'
    if(-not $stacked){Write-Host ($format -f 'DEVICE', 'ID / SERIAL', 'STATUS') -ForegroundColor $palette.Muted}
    foreach ($row in $rows) {
        $status = switch ($row.Quality) { 'Reported' { if ($row.Note -eq 'Alternate source') { 'OK*' } else { 'OK' } }; 'Missing' { 'Missing' }; 'Conflict' { 'Clash' }; default { 'Default' } }
        $value = if ($row.Quality -eq 'Missing') { '-' } elseif ($row.Quality -eq 'Placeholder') { '(default value)' } else { $row.Value }
        $color = if ($row.Quality -eq 'Reported') { $palette.Good } else { $palette.Warn }
        if($stacked){Write-PnpValue ($row.Label+' ['+$status+']') $value $color;Write-Host '';continue}
        Write-Host (('  {0,-' + $labelWidth + '}  ') -f (Limit-TableText $row.Label $labelWidth)) -ForegroundColor $palette.Text -NoNewline
        Write-Host (('{0,-' + $valueWidth + '}  ') -f (Limit-TableText $value $valueWidth)) -ForegroundColor $color -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    Write-Host "`n  ... = shortened. [5] All details / full IDs   [6] Save report" -ForegroundColor $palette.Muted
    if (@($rows | Where-Object Note -eq 'Alternate source').Count) { Write-Host '  * Serial from the alternate Windows storage source.' -ForegroundColor $palette.Muted }
    if (@($rows | Where-Object Quality -eq 'Conflict').Count) { Write-Host '  Clash = Windows sources disagree. [4] Review / [5] Both sources' -ForegroundColor $palette.Warn }
    if ($warnings.Count) { Write-Host '  Some sections could not be read. [4] Review issues' -ForegroundColor $palette.Warn }
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
    $coverage=@(Get-ScanCoverage $Inventory)
    $read=($coverage | Measure-Object Read -Sum).Sum
    $total=($coverage | Measure-Object Total -Sum).Sum
    $deviceReadable=Test-SectionReadable $Inventory['PnP hardware IDs']
    $nodes=$null; $classes=$null; $models=$null
    if($deviceReadable) {
        $devices=@($Inventory['PnP hardware IDs'] | Where-Object {$null -ne $_})
        $nodes=$devices.Count
        $classes=@($devices | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.PNPClass)} | Select-Object -ExpandProperty PNPClass -Unique).Count
        $models=@($devices | Where-Object {@($_.HardwareID | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0}).Count
    }
    $extraState='NOT SCANNED'; $known=$null; $hidden=$null; $remembered=$null; $visibilityUnread=$null; $captured=$null
    if($Inventory.Contains('Extended scan info')) {
        $info=$Inventory['Extended scan info']; $captured=$info.Captured
        if($info.Error -or $Inventory['Report info'].ExtendedStatus -eq 'Unavailable' -or -not (Test-SectionReadable $Inventory['Extended device inventory'])) {
            $extraState='NOT READ'
        } else {
            $extraState='READ'
            $extra=@($Inventory['Extended device inventory'] | Where-Object {$null -ne $_})
            $known=$extra.Count
            $hidden=@($extra | Where-Object {$_.HiddenByNodeFlag -eq $true -or $_.HiddenByClass -eq $true}).Count
            $remembered=@($extra | Where-Object {$_.Present -is [bool] -and -not $_.Present}).Count
            $visibilityUnread=@($extra | Where-Object {$null -eq $_.HiddenByNodeFlag -or $null -eq $_.HiddenByClass}).Count
        }
    }
    [pscustomobject]@{
        Coverage=$coverage;Read=$read;Total=$total;Complete=($read -eq $total -and $extraState -ne 'NOT READ')
        Found=@($IdRows | Where-Object Quality -eq 'Reported').Count
        Missing=@($IdRows | Where-Object Quality -eq 'Missing').Count
        Default=@($IdRows | Where-Object Quality -eq 'Placeholder').Count
        DeviceReadable=$deviceReadable;Nodes=$nodes;Classes=$classes;Models=$models
        DeviceIssues=@(Get-PnpIssues $Inventory['PnP hardware IDs']).Count
        QueryWarnings=@($QueryWarnings | Where-Object {$null -ne $_}).Count
        Conflicts=(@(Get-QuickDisks $Inventory | Where-Object Quality -eq 'Conflict').Count+@(Get-InventoryConflicts $Inventory).Count)
        ExtendedState=$extraState;Known=$known;Hidden=$hidden;Remembered=$remembered;VisibilityUnread=$visibilityUnread;ExtendedCaptured=$captured
    }
}
function Show-Overview {
    Reset-UiPage
    Start-UiReport
    Add-ReportBookmark '1'
    $summary=Get-OverviewSummary $report $identifiers $warnings
    Write-Heading 'SCAN OVERVIEW'
    $status=if($summary.Complete){'COMPLETE'}else{'PARTIAL'}
    Write-PnpValue 'Result' ($status+' / '+$summary.Read+' of '+$summary.Total+' normal sections read') $(if($summary.Complete){$palette.Good}else{$palette.Warn})
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
        Write-PnpValue 'Present devices' ("$($summary.Nodes) nodes / $($summary.Classes) classes / $($summary.Models) with model IDs") $palette.Text
    } else {Write-PnpValue 'Present devices' 'Not read; device count unknown. See [4].' $palette.Warn}
    Write-PnpValue 'Review' ("$($summary.DeviceIssues) deep-device review / $($summary.QueryWarnings) query warnings / $($summary.Conflicts) conflicts") $(if($summary.DeviceIssues+$summary.QueryWarnings+$summary.Conflicts){$palette.Warn}else{$palette.Good})
    switch($summary.ExtendedState) {
        'READ' {
            Write-PnpValue 'Extended devices' ("$($summary.Known) known / $($summary.Hidden) hidden / $($summary.Remembered) remembered") $palette.Text
            Write-PnpValue 'Visibility' ("$($summary.VisibilityUnread) unread / groups can overlap") $(if($summary.VisibilityUnread){$palette.Warn}else{$palette.Muted})
            Write-PnpValue 'Extended capture' (Format-ScanTime $summary.ExtendedCaptured) $palette.Muted
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
    Write-PnpValue 'Scope' 'Identifier fields are not unique PC counts. Nodes include physical/virtual records.' $palette.Muted
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
            $count=@($report[$name] | Where-Object {$null -ne $_ -and -not $_.Unavailable}).Count
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
    Show-Attention
    Write-Heading 'STARTUP SCAN TIMING'
    Write-PnpValue 'Timing scope' 'Startup queries only; refreshed device views do not retime the original scan.' $palette.Muted
    Show-Records $report['Scan timing']
}
function Show-Attention {
    Start-UiReport
    Write-Heading 'ITEMS TO REVIEW'
    $issues = @($identifiers | Where-Object Quality -ne 'Reported')
    $conflicts = @(Get-QuickDisks $report | Where-Object Quality -eq 'Conflict')
    $pnpIssues=@(Get-PnpIssues $report['PnP hardware IDs'])
    $inventoryConflicts=@(Get-InventoryConflicts $report)
    if (-not $issues.Count -and -not $warnings.Count -and -not $conflicts.Count -and -not $pnpIssues.Count -and -not $inventoryConflicts.Count) {
        Write-Host '  [OK] No missing identifiers, placeholders, or failed sections detected.' -ForegroundColor $palette.Good
    }
    foreach($conflict in $inventoryConflicts){Write-PnpValue 'SCAN CONFLICT' ($conflict.Section+' / '+$conflict.DeviceKey+' / '+$conflict.Message) $palette.Warn}
    foreach($problem in $pnpIssues){Write-PnpValue 'DEVICE REVIEW' ($problem.Device+' / '+$problem.Message) $palette.Warn}
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
        Write-PnpValue $status ("$($row.Section)${device} / $(Get-FieldLabel $row.Field)") $palette.Warn
        if ($row.Quality -eq 'Placeholder') { Write-Host "      Windows returned '$($row.Value)' instead of a useful ID." -ForegroundColor $palette.Muted }
    }
    if ($warnings.Count) { Write-Host '  Access denied? Try Run as administrator. Some providers may still be unavailable.' -ForegroundColor $palette.Muted }
    if ($issues.Count) { Write-Host '  Missing or placeholder values can be normal firmware limitations.' -ForegroundColor $palette.Muted }
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
    $number=[int]$Code
    if($maps.ContainsKey($Kind) -and $maps[$Kind].ContainsKey($number)){return $maps[$Kind][$number]}
    return "Windows code $number"
}
function Get-StorageIdentifiers {
    Get-HwidInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Disk -OperationTimeoutSec 30 -Property Number,FriendlyName,SerialNumber,UniqueId,UniqueIdFormat,Guid,Signature,PartitionStyle,BusType,HealthStatus |
        Select-Object Number,FriendlyName,SerialNumber,UniqueId,UniqueIdFormat,Guid,Signature,
            @{n='PartitionStyle';e={Get-StorageCodeName 'PartitionStyle' $_.PartitionStyle}},
            @{n='BusType';e={Get-StorageCodeName 'BusType' $_.BusType}},
            @{n='HealthStatus';e={Get-StorageCodeName 'HealthStatus' $_.HealthStatus}}
}
function Get-PartitionIdentifiers {
    Get-HwidInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Partition -OperationTimeoutSec 30 -Property DiskNumber,PartitionNumber,DriveLetter,Guid,GptType,MbrType,AccessPaths,Size |
        Select-Object DiskNumber,PartitionNumber,@{n='DriveLetter';e={if(-not [string]::IsNullOrEmpty([string]$_.DriveLetter) -and [int][char]$_.DriveLetter -ne 0){[string][char]$_.DriveLetter}}},@{n='PartitionGuid';e={$_.Guid}},GptType,MbrType,AccessPaths,@{n='Size_GiB';e={GiB $_.Size}}
}
function Get-NetworkIdentifiers {
    try {
        $adapters=@(Get-NetAdapter -IncludeHidden)
        if(-not $adapters.Count){throw 'No adapters returned by Get-NetAdapter.'}
        $adapters | Select-Object Name,InterfaceDescription,InterfaceGuid,MacAddress,PermanentAddress,PNPDeviceID,Status,LinkSpeed,HardwareInterface,@{n='CollectionSource';e={'Get-NetAdapter'}}
        return
    } catch {$primaryError=$_.Exception.Message}
    try {
        $adapters=@(Get-HwidInstance -Namespace 'root/StandardCimv2' -ClassName MSFT_NetAdapter -OperationTimeoutSec 20 -Property Name,InterfaceDescription,InterfaceGuid,NetworkAddresses,PermanentAddress,PNPDeviceID,InterfaceOperationalStatus,ReceiveLinkSpeed,HardwareInterface)
        if(-not $adapters.Count){throw 'No adapters returned by the CIM fallback.'}
        $adapters | Select-Object Name,InterfaceDescription,InterfaceGuid,@{n='MacAddress';e={$addresses=@($_.NetworkAddresses | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)});if($addresses.Count){$addresses[0]}else{$_.MacAddress}}},PermanentAddress,PNPDeviceID,NetworkAddresses,
            @{n='Status';e={if($null -eq $_.InterfaceOperationalStatus){$null}elseif($_.InterfaceOperationalStatus -eq 1){'Up'}elseif($_.InterfaceOperationalStatus -eq 2){'Down'}else{'Windows status '+$_.InterfaceOperationalStatus}}},
            @{n='LinkSpeed';e={if($null -ne $_.ReceiveLinkSpeed){'{0:0.##} Mbps' -f ($_.ReceiveLinkSpeed/1000000.0)}}},HardwareInterface,@{n='CollectionSource';e={'MSFT_NetAdapter CIM fallback'}}
    } catch {throw ("Network identifiers unavailable. Primary: $primaryError / Fallback: "+$_.Exception.Message)}
}
function Get-DriverHardwareIds {
    # All present device classes, including physical, virtual, system and peripheral nodes.
    Get-HwidInstance -OperationTimeoutSec 20 Win32_PnPEntity -Filter 'Present = True' -Property Name,Manufacturer,PNPClass,ClassGuid,Service,Present,PNPDeviceID,HardwareID,CompatibleID,ConfigManagerErrorCode |
        Sort-Object PNPClass,Name,PNPDeviceID |
        Select-Object Name,Manufacturer,PNPClass,ClassGuid,Service,Present,@{n='DeviceInstanceId';e={$_.PNPDeviceID}},HardwareID,CompatibleID,ConfigManagerErrorCode
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
    try {$devices=@(Get-PnpDevice -ErrorAction Stop | Where-Object {$null -ne $_})}
    catch {
        $source='Win32_PnPEntity / unfiltered fallback'
        $devices=@(Get-HwidInstance -ClassName Win32_PnPEntity -OperationTimeoutSec 20 -Property Name,Manufacturer,PNPClass,ClassGuid,Service,Present,PNPDeviceID,HardwareID,CompatibleID,ConfigManagerErrorCode | Where-Object {$null -ne $_})
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
            Captured=(Get-Date).ToString('o');Source=$source;Records=$rows.Count
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
        for($i=$warnings.Count-1;$i -ge 0;$i--){if($warnings[$i].StartsWith('Extended device inventory: ')){$warnings.RemoveAt($i)}}
        $report['Warnings']=@($warnings.ToArray())
    }catch {
        Write-PnpValue 'EXTENDED-01 / not completed' (Get-ScanFailureHint $_.Exception.Message) $palette.Warn
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
        31 {'Driver cannot load'}; 43 {'Windows stopped this device'}
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
    if([string]$Device.DeviceInstanceId -match '^USB'){return 'USB'}
    switch([string]$Device.PNPClass) {
        'Keyboard' {return 'INPUT'}; 'Mouse' {return 'INPUT'}; 'HIDClass' {return 'INPUT'}
        'MEDIA' {return 'AUDIO'}; 'AudioEndpoint' {return 'AUDIO'}
        'Bluetooth' {return 'BLUETOOTH'}; 'Camera' {return 'CAMERAS'}; 'Image' {return 'CAMERAS'}
        'Monitor' {return 'MONITORS'}
        'System' {return 'SYSTEM & FIRMWARE'}; 'Computer' {return 'SYSTEM & FIRMWARE'}
        'Processor' {return 'SYSTEM & FIRMWARE'}; 'Firmware' {return 'SYSTEM & FIRMWARE'}
        'SecurityDevices' {return 'SYSTEM & FIRMWARE'}; 'Memory' {return 'SYSTEM & FIRMWARE'}
    }
    return 'OTHER DEVICES'
}
function Get-PnpIssues($Devices) {
    if(-not (Test-SectionReadable $Devices)){return}
    foreach($device in $Devices) {
        $status=Get-PnpStatus $device.ConfigManagerErrorCode
        if($status.Quality -eq 'Review') {
            [pscustomobject]@{Device=$device.Name;Message=$status.Text;Kind='Status'}
        }
    }
    # Hardware IDs describe models, so sharing them is expected. Only instance IDs
    # should identify a unique device node within this single scan.
    $duplicates=@($Devices | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.DeviceInstanceId)} |
        Group-Object -Property {([string]$_.DeviceInstanceId).Trim().ToUpperInvariant()} | Where-Object Count -gt 1)
    foreach($duplicate in $duplicates) {
        [pscustomobject]@{Device=$duplicate.Group[0].Name;Message=('Repeated instance ID in scan ('+$duplicate.Count+' records): '+$duplicate.Group[0].DeviceInstanceId);Kind='Duplicate'}
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
    $text=([string]$Value -replace '[\r\n\t\x00-\x1f]',' ')
    if([string]::IsNullOrWhiteSpace($text)){$text='(not supplied)'}
    $safeLabel=([string]$Label -replace '[\r\n\t\x00-\x1f]',' ')
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
        $report['PnP hardware IDs']=@{Unavailable=$message}
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
                $value='None assigned (normal for some system/recovery partitions)'
                $color=$palette.Muted
            }
            Write-PnpValue (Get-FieldLabel $property.Name) ($value+$status) $color
        }
        Write-Host ''
    }
}
function Get-SectionIdentifierInfo($Name,$Records) {
    if($Name -eq 'PnP hardware IDs') {
        $nodes=@($Records | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.DeviceInstanceId)}).Count
        $models=@($Records | Where-Object {@($_.HardwareID | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0}).Count
        $review=@(Get-PnpIssues $Records).Count
        $text="$nodes instance IDs; $models with model IDs"
        if($review){$text+="; $review review"}
        return [pscustomobject]@{Text=$text;Tag=$(if($review){'CHECK'}else{'READ'});Color=$(if($review){'Warn'}else{'Good'});Found=$nodes;Missing=0;Default=0}
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
        foreach($name in @('GiB','Convert-MonitorText','Get-StorageCodeName','Get-StorageIdentifiers','Get-PartitionIdentifiers','Get-NetworkIdentifiers','Get-DriverHardwareIds','Get-HwidInstance','Get-ClassHiddenState','Get-NativeNodeStatus','Get-ExtendedDeviceInventory','Get-CimInstance','Get-NetAdapter','Get-ItemProperty','Get-PnpDevice','Get-PnpDeviceProperty','Get-WmiObject')) {
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
    if($null -eq $script:scanQueryWorker){return (& $Query)}
    # Reuse the initialized session, but give every query its own output/error buffers.
    $worker=[PowerShell]::Create()
    $pending=$null
    try {
        $worker.Runspace=$script:scanQueryWorker.Runspace
        [void]$worker.AddScript('$ErrorActionPreference="Stop";'+$Query.ToString())
        $pending=$worker.BeginInvoke()
        while(-not $pending.IsCompleted) {
            if($pending.AsyncWaitHandle.WaitOne(100)){break}
            if($Pulse){& $Pulse | Out-Null}
        }
        return $worker.EndInvoke($pending)
    }finally{
        if($null -ne $pending -and $pending.IsCompleted){$pending.AsyncWaitHandle.Close()}
        $worker.Dispose()
    }
}
function Get-ScanFailureHint($Message) {
    if($Message -match 'access|denied|privilege|permission|authorized'){return 'Access blocked'}
    if($Message -match 'timed out|timeout|time-out'){return 'Provider timed out'}
    if($Message -match 'No data returned|No .* returned'){return 'No records returned'}
    if($Message -match 'Invalid class|Invalid namespace|not supported|not recognized|No CIM or legacy WMI'){return 'Provider unavailable'}
    return 'Windows read failed'
}
function Section($Name, [scriptblock]$Query) {
    $script:scanStep++
    $line=Start-ScanLine ('  [{0:00}/{2}] {1,-24} ' -f $script:scanStep, $Name, $scanTotal)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $status='UNAVAILABLE';$results=0;$summary='Not read'
    try {
        $data = @(Invoke-ScanQuery $Query {
            Update-ScanProgress ([math]::Max(0,$script:scanStep-1))
            Update-ScanWaiting $line $timer.Elapsed.TotalSeconds
        } | Where-Object {$null -ne $_})
        if ($data.Count -eq 0) { throw 'No data returned by Windows.' }
        # Normalize dates before export so JSON is consistent in Windows PowerShell 5.1 and 7.
        $data = @(foreach ($record in $data) {
            $normalized = [ordered]@{}
            $properties=if($record -is [System.Collections.IDictionary]){
                foreach($key in $record.Keys){[pscustomobject]@{Name=$key;Value=$record[$key]}}
            }else{$record.PSObject.Properties}
            foreach ($property in $properties) {
                if ($property.Value -is [datetime]) { $normalized[$property.Name]=$property.Value.ToString('o') }
                elseif ($property.Value -is [enum]) { $normalized[$property.Name]=$property.Value.ToString() }
                else { $normalized[$property.Name]=$property.Value }
            }
            [pscustomobject]$normalized
        })
        $report[$Name] = $data
        $info=Get-SectionIdentifierInfo $Name $data
        $unit=if($data.Count -eq 1){'result'}else{'results'}
        $timer.Stop();$status=$info.Tag;$results=$data.Count;$summary=$info.Text
        try {Complete-ScanLine $line $Name ("[$status] $results $unit | $summary | {0:0.0}s" -f $timer.Elapsed.TotalSeconds) $palette[$info.Color]}catch{}
    } catch {
        $message = $_.Exception.Message
        $summary=Get-ScanFailureHint $message
        $warnings.Add("${Name}: $message")
        $report[$Name] = @{ Unavailable = $message }
        $timer.Stop()
        try {Complete-ScanLine $line $Name ('[UNAVAILABLE] '+$summary+' / see [4] | '+('{0:0.0}s' -f $timer.Elapsed.TotalSeconds)) $palette.Warn}catch{}
    } finally {
        $timer.Stop()
        if($null -ne $script:scanTimings){$script:scanTimings.Add([pscustomobject]@{Section=$Name;Status=$status;Results=$results;Seconds=[math]::Round($timer.Elapsed.TotalSeconds,3);Summary=$summary})}
        Update-ScanProgress
    }
}
function Convert-MonitorText($Codes) {
    return ((@($Codes | Where-Object {$_ -gt 0 -and $_ -le 65535} | ForEach-Object {[char][int]$_}) -join '').Trim())
}
function GiB($Bytes) { if ($null -eq $Bytes) { return $null }; [math]::Round($Bytes / 1GB, 2) }
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
$report['Report info'] = [ordered]@{ Generated = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Administrator = $admin; Version = '3.40'; Display=$display.Mode; ScanNumber=$ScanNumber }
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
Write-Host '  READ = data read. CHECK = some IDs need review; the query still succeeded.' -ForegroundColor $palette.Muted
Write-Host '  Found = supplied by Windows. Missing = not supplied. Default = generic value.' -ForegroundColor $palette.Muted
Section 'System identity' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_ComputerSystemProduct -Property Vendor,Name,Version,IdentifyingNumber,UUID | Select-Object Vendor, Name, Version, IdentifyingNumber, UUID
}
Section 'System hardware' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_ComputerSystem -Property Manufacturer,Model,SystemType,TotalPhysicalMemory | Select-Object Manufacturer, Model, SystemType, @{n='TotalRAM_GiB';e={GiB $_.TotalPhysicalMemory}}
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
    Get-HwidInstance -OperationTimeoutSec 20 Win32_PhysicalMemory -Property DeviceLocator,BankLabel,Manufacturer,PartNumber,SerialNumber,Capacity,Speed,ConfiguredClockSpeed | Select-Object DeviceLocator, BankLabel, Manufacturer, PartNumber, SerialNumber, @{n='Capacity_GiB';e={GiB $_.Capacity}}, Speed, ConfiguredClockSpeed
}
Section 'Physical disks' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_DiskDrive -Property Index,Model,SerialNumber,FirmwareRevision,InterfaceType,MediaType,Size,PNPDeviceID | Select-Object Index, Model, SerialNumber, FirmwareRevision, InterfaceType, MediaType, @{n='Size_GiB';e={GiB $_.Size}}, PNPDeviceID
}
Section 'Storage identifiers' {
    Get-StorageIdentifiers
}
Section 'Volumes' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_LogicalDisk -Filter 'DriveType=2 OR DriveType=3 OR DriveType=5' -Property DeviceID,DriveType,VolumeName,VolumeSerialNumber,FileSystem,Size,FreeSpace | Select-Object DeviceID, DriveType, VolumeName, VolumeSerialNumber, FileSystem, @{n='Size_GiB';e={GiB $_.Size}}, @{n='Free_GiB';e={GiB $_.FreeSpace}}
}
Section 'Disk partitions' {
    Get-PartitionIdentifiers
}
Section 'Graphics adapters' {
    Get-HwidInstance -OperationTimeoutSec 20 Win32_VideoController -Property Name,VideoProcessor,PNPDeviceID,DriverVersion,DriverDate,CurrentHorizontalResolution,CurrentVerticalResolution | Select-Object Name, VideoProcessor, PNPDeviceID, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution
}
Section 'Monitors' {
    Get-HwidInstance -OperationTimeoutSec 20 -Namespace 'root\wmi' -ClassName WmiMonitorID -Property InstanceName,Active,ManufacturerName,UserFriendlyName,ProductCodeID,SerialNumberID,WeekOfManufacture,YearOfManufacture |
        Select-Object InstanceName, Active, @{n='Manufacturer';e={Convert-MonitorText $_.ManufacturerName}}, @{n='Name';e={Convert-MonitorText $_.UserFriendlyName}}, @{n='ProductCode';e={Convert-MonitorText $_.ProductCodeID}}, @{n='SerialNumber';e={Convert-MonitorText $_.SerialNumberID}}, WeekOfManufacture, YearOfManufacture
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
        $report['Extended scan info']=[ordered]@{Captured=(Get-Date).ToString('o');Source='Extended refresh failed';Records=0;Error=$message}
        $report['Report info']['ExtendedStatus']='Unavailable'
        try {Complete-ScanLine $extraLine 'Extended catalog' ('[UNAVAILABLE] '+(Get-ScanFailureHint $message)) $palette.Warn}catch{}
    }finally{$extraClock.Stop()}
}
$scanClock.Stop()
$report['Report info']['ScanSeconds']=[math]::Round($scanClock.Elapsed.TotalSeconds,2)
$report['Report info']['ScanCompleted']=(Get-Date).ToString('o')
$report['Scan timing']=@($scanTimings.ToArray())
$report['Warnings'] = @($warnings.ToArray())
    if($script:scanStep -ne $scanTotal -or $scanTimings.Count -ne $scanTotal){throw 'The scan did not finish every section.'}
    $read=@($scanTimings | Where-Object Status -ne 'UNAVAILABLE').Count
    Write-PnpValue 'Finished' ("$scanTotal/$scanTotal queries completed / $read sections read / $($report['Report info'].ScanSeconds)s") $(if($read -eq $scanTotal){$palette.Good}else{$palette.Warn})
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
    $names = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory.Keys } else { $Inventory.PSObject.Properties.Name }
    foreach ($name in $names) {
        if ($name -in @('Report info', 'Warnings','Compatibility','Extended scan info','Extended device inventory')) { continue }
        $records = if ($Inventory -is [System.Collections.IDictionary]) { $Inventory[$name] } else { $Inventory.$name }
        foreach ($record in $records) {
            $device = Get-DeviceKey $name $record
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Name -notmatch $identifierPattern) { continue }
                $value = Normalize-IdentifierText $property.Value
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
    foreach($section in @('CPU','Memory modules','Physical disks','Storage identifiers','Volumes','Graphics adapters','Network adapters','Monitors')) {
        $records=if($Inventory -is [System.Collections.IDictionary]){$Inventory[$section]}else{$Inventory.$section}
        if(-not (Test-SectionReadable $records)){continue}
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
    $keyedSections=@('CPU','Memory modules','Physical disks','Storage identifiers','Volumes','Graphics adapters','Network adapters','Monitors')
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
function Read-SavedReport($Path) {
    if(-not (Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue)){throw 'JSON import is unavailable: repair the Microsoft.PowerShell.Utility module for this runtime.'}
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Report file not found. Choose an existing JSON report.'}
    if((Get-Item -LiteralPath $Path).Length -gt 64MB){throw 'Report exceeds the 64 MB import limit.'}
    try {
        $json=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        Assert-UniqueJsonProperties $json
        $previous=Convert-ReportJson $json
    }
    catch {
        if($_.Exception.Message -match 'Duplicate JSON property'){throw $_.Exception.Message}
        throw 'Cannot read this JSON report. Choose the .json file, not the TXT report; the file may be incomplete or damaged.'
    }
    if ($json -notmatch '^\s*\{' -or $previous -isnot [pscustomobject] -or $previous.'Report info' -isnot [pscustomobject] -or $previous.'Report info'.Version -isnot [string] -or $previous.'Report info'.Version -notmatch '^[23]\.\d+(\.\d+)?$') {
        throw 'This file is not a supported HWID v2 or v3 report.'
    }
    foreach($field in @('Computer','Generated')) {
        $value=$previous.'Report info'.$field
        $legacyDate=$field -eq 'Generated' -and ($value -is [datetime] -or $value -is [datetimeoffset])
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
                if(($field.Name -match $identifierPattern -or $field.Name -in @('DeviceID','DeviceInstanceId','ClassGuid','Index','Number','DeviceLocator','BankLabel','InstanceName')) -and $null -ne $field.Value -and ($field.Value -is [array] -or $field.Value -is [pscustomobject] -or $field.Value -is [bool])){throw "Invalid identifier or device-key value: $($property.Name) / $($field.Name)"}
            }
        }
    }
    if (-not $found) { throw 'This report has no recognized hardware sections.' }
    return $previous
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
function Resolve-CompareInput($Value,$Recent) {
    $text=([string]$Value).Trim()
    if(-not $text -or $text -eq '0'){return $null}
    if($text -match '\A[1-9]\z') {
        $index=[int]$text-1
        if($index -ge @($Recent).Count){throw 'That recent-report number is not listed. Paste a JSON path or select a listed number.'}
        return $Recent[$index].FullName
    }
    return $text.Trim('"')
}
function Read-CompareReportPath {
    $folder=Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
    $recent=@(Get-RecentReports $folder)
    if($recent.Count) {
        Write-Host '  RECENT REPORTS / newest files first' -ForegroundColor $palette.Heading
        for($i=0;$i -lt $recent.Count;$i++){Write-PnpValue ("["+($i+1)+"]") $recent[$i].Name $palette.Text}
    } else {Write-Host '  No saved reports here yet. Paste a JSON report path.' -ForegroundColor $palette.Muted}
    Write-Host '  Choose a listed number or paste a JSON path. [0] / blank = Back.' -ForegroundColor $palette.Muted
    Complete-UiReport
    return (Resolve-CompareInput (Read-CheckerLine 'Report') $recent)
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
    Write-Heading 'COMPARE RESULTS / PREVIOUS -> CURRENT'
    if($SourcePath){Write-PnpValue 'Baseline file' $SourcePath $palette.Muted}
    Write-PnpValue 'Previous' ($Previous.'Report info'.Computer+' / '+(Format-ScanTime $Previous.'Report info'.Generated)) $palette.Muted
    Write-PnpValue 'Current' ($Current['Report info'].Computer+' / '+(Format-ScanTime $Current['Report info'].Generated)) $palette.Text
    if($Previous.'Report info'.Computer -ne $Current['Report info'].Computer){Write-PnpValue 'REVIEW' 'These reports have different computer names; verify that this is the intended comparison.' $palette.Warn}
    if($Comparison.AmbiguousDevices.Count){
        Write-PnpValue 'SCAN CONFLICT' ("$($Comparison.AmbiguousDevices.Count) duplicate device key(s); ambiguous IDs are not compared.") $palette.Warn
        foreach($conflict in $Comparison.AmbiguousDevices){Write-PnpValue 'Skipped device' ($conflict.Section+' / '+$conflict.DeviceKey+' / '+($conflict.Sources -join ' + ')+' report') $palette.Warn}
    }
    Write-PnpValue 'Comparable fields' ("$($Comparison.PreviousCount) previous / $($Comparison.CurrentCount) current") $palette.Text
    if($Comparison.UnkeyedSections.Count){Write-PnpValue 'Missing device keys' (($Comparison.UnkeyedSections -join ', ')+'. Records cannot be matched reliably; these sections are skipped.') $palette.Warn}
    if(-not $Comparison.PreviousCount -and -not $Comparison.CurrentCount){throw 'No usable IDs in sections readable in both reports.'}
    $details=@(Get-ComparisonDetails $Comparison)
    $incomplete=$Comparison.SkippedSections.Count -or $Comparison.SkippedFields
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
    if($incomplete) {
        Write-Heading 'NOT COMPARED'
        if($Comparison.SkippedSections.Count){Write-PnpValue 'Sections' ($Comparison.SkippedSections -join ', ') $palette.Warn}
        if($Comparison.UnkeyedSections.Count){Write-PnpValue 'Reason / device keys' 'Slot or instance keys were missing; no device match was guessed.' $palette.Warn}
        if($Comparison.SkippedFields){Write-PnpValue 'Fields' ("$($Comparison.SkippedFields) missing/default or absent in one report schema") $palette.Warn}
    }
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
        $copy=New-Object object[] $Value.Count
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
function Start-HardwareRescan([bool]$UseWorker=($ownedConsole -and -not $redirected)) {
    try {
        $next=1+[int]$report['Report info'].ScanNumber
        $snapshot=Invoke-HardwareScan $next -UseWorker $UseWorker -IncludeExtended ($report.Contains('Extended scan info'))
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
    try {Show-RescanResult $lastScanPrevious $lastScanCurrent}
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
        $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $stem = Join-Path $folder ('HWID-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
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
        Write-ReportPair $stem $text $json
        Write-PnpValue 'SAVED' 'TXT + JSON created; JSON verified.' $palette.Good
        Write-PnpValue 'Computer / scan' ($report['Report info'].Computer+' / '+(Format-ScanTime $report['Report info'].Generated)) $palette.Text
        Write-PnpValue 'Folder' $folder $palette.Muted
        Write-PnpValue 'TXT / read' ([IO.Path]::GetFileName($stem)+'.txt') $palette.Text
        Write-PnpValue 'JSON / compare' ([IO.Path]::GetFileName($stem)+'.json') $palette.Heading
        Write-PnpValue 'Next' '[7] Compare a JSON report / [8] Open reports folder' $palette.Muted
    } catch {
        Write-PnpValue 'SAVE-01 / not completed' $_.Exception.Message $palette.Error
    }
}
$script:lastScanPrevious=$null
$script:lastScanCurrent=$null
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$initialScan=Invoke-HardwareScan
$script:report=$initialScan.Inventory
$script:warnings=$initialScan.Warnings
$script:identifiers=$initialScan.Identifiers
$initialScan=$null
if ($redirected -or -not $ownedConsole) { Show-Overview }
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
            Write-Heading 'COMPARE REPORTS'
            Write-Host '  Compare a saved snapshot with this scan.' -ForegroundColor $palette.Muted
            Complete-UiReport
            try {
                $previousPath=Read-CompareReportPath
                if (-not $previousPath) { Show-UiTransition 'Back'; continue MainMenu }
                $previous=Read-SavedReport $previousPath
                Show-ComparisonResult $previous $report -SourcePath $previousPath
            } catch { Write-PnpValue 'COMPARE-01 / unavailable' $_.Exception.Message $palette.Warn }
        }
        '8' {
            Write-Heading 'REPORTS FOLDER'
            $folder = Join-Path (Split-Path -Parent $env:HWID_SCRIPT) 'HWID-Reports'
            try {
                if (Test-Path -LiteralPath $folder -PathType Container) { Start-Process explorer.exe -ArgumentList ('"' + $folder + '"'); Write-PnpValue 'Opened folder' $folder $palette.Good }
                else { Write-Host 'Save a report first to create the reports folder.' }
            } catch { Write-Host "Unable to open folder: $($_.Exception.Message)" -ForegroundColor $palette.Error }
        }
        '0' { Show-UiTransition 'Exit'; return }
        default { Show-MenuInputError; continue }
    }
    if ($choice -ne '2') { Wait-UiPage }
    Show-UiTransition 'Back'
}
