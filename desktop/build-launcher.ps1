#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$OutputDirectory,[Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if(-not [IO.File]::Exists($vswhere)){throw 'Install Visual Studio Build Tools with Desktop development with C++ to build the early startup launcher.'}
$vs=@(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
if(-not $vs.Count){throw 'MSVC x64 build tools were not found.'}
$vc=Join-Path $vs[0] 'VC\Auxiliary\Build\vcvars64.bat'
$source=Join-Path $PSScriptRoot 'launcher\launcher.c'
$icon=Join-Path $PSScriptRoot 'assets\Hwid.ico'
$manifest=Join-Path $PSScriptRoot 'app.manifest'
$versionResource=($Version.Replace('.',','))+',0'
$rc=@"
#include <windows.h>
101 ICON "$($icon.Replace('\','\\'))"
1 RT_MANIFEST "$($manifest.Replace('\','\\'))"
1 VERSIONINFO
FILEVERSION $versionResource
PRODUCTVERSION $versionResource
FILEOS VOS_NT_WINDOWS32
FILETYPE VFT_APP
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904b0"
  BEGIN
   VALUE "FileDescription", "HWID Checker startup launcher"
   VALUE "FileVersion", "$Version.0"
   VALUE "ProductName", "HWID Checker"
   VALUE "ProductVersion", "$Version"
   VALUE "OriginalFilename", "HWID Checker.exe"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x409, 1200
 END
END
"@
$rcPath=Join-Path $output 'launcher.rc'
[IO.File]::WriteAllText($rcPath,$rc,[Text.Encoding]::Unicode)
# The generated command file contains only validated absolute tool/source paths;
# no user input, commands or filesystem deletion is forwarded to a second shell.
foreach($value in @($vc,$source,$output)) {if($value -match '[%\r\n"]'){throw 'Choose a build path without percent signs, quotes or newlines.'}}
$commands=@"
@echo off
call "$vc" >nul
if errorlevel 1 exit /b 1
rc.exe /nologo /fo "$output\launcher.res" "$rcPath"
if errorlevel 1 exit /b 1
cl.exe /nologo /W4 /WX /O2 /MT /D_WIN32_WINNT=0x0A00 /Fo"$output\launcher.obj" /Fe"$output\HWID Checker.exe" "$source" "$output\launcher.res" /link /SUBSYSTEM:WINDOWS /MANIFEST:NO user32.lib gdi32.lib ole32.lib shell32.lib
exit /b %errorlevel%
"@
$cmdPath=Join-Path $output 'build-launcher.cmd'
[IO.File]::WriteAllText($cmdPath,$commands,[Text.Encoding]::Default)
& $env:ComSpec /d /v:off /c $cmdPath
if($LASTEXITCODE -ne 0){throw 'Early startup launcher build failed.'}
$exe=Join-Path $output 'HWID Checker.exe'
if(-not [IO.File]::Exists($exe)){throw 'The native launcher was not produced.'}
return $exe
