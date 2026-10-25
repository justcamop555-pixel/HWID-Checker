
@echo off
setlocal
title Simple HWID Checker
color 0A
cls

echo ==============================
echo       SIMPLE HWID CHECKER
echo ==============================
echo.

echo [CPU]
powershell -NoProfile -Command "Get-CimInstance Win32_Processor | Format-List Name,Manufacturer,ProcessorId"
echo.

echo [MOTHERBOARD]
powershell -NoProfile -Command "Get-CimInstance Win32_BaseBoard | Format-List Manufacturer,Product,SerialNumber"
echo.

echo [BIOS]
powershell -NoProfile -Command "Get-CimInstance Win32_BIOS | Format-List Manufacturer,SMBIOSBIOSVersion,SerialNumber"
echo.

echo [DISK]
powershell -NoProfile -Command "Get-CimInstance Win32_DiskDrive | Format-List Model,SerialNumber"
echo.

echo [MAC ADDRESS]
powershell -NoProfile -Command "Get-NetAdapter | Format-Table Name,MacAddress,Status -AutoSize"
echo.

echo [WINDOWS MACHINE GUID]
reg query "HKLM\SOFTWARE\Microsoft\Cryptography" /v MachineGuid
echo.

pause
