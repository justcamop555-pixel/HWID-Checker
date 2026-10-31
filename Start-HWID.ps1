param([switch]$CurrentWindow)
$ErrorActionPreference='Stop'
try {
    Write-Host '[START] Preparing HWID Checker...' -ForegroundColor Cyan
    # This small loader runs before parsing the modern embedded checker.
    if($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)){throw 'Use Windows PowerShell 5.1 or PowerShell 7 compatible with this Windows version.'}
    if($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){throw 'Restricted PowerShell language mode. Ask your administrator about approved execution; policy was not changed.'}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'HWID Checker requires Windows.'}
    $env:HWID_SCRIPT=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'hwid.bat'
    $env:HWID_CURRENT_WINDOW=if($CurrentWindow){'--current-window'}else{''}
    if(-not (Test-Path -LiteralPath $env:HWID_SCRIPT -PathType Leaf)){throw 'Keep Start-HWID.ps1 beside hwid.bat.'}
    $raw=[IO.File]::ReadAllText($env:HWID_SCRIPT)
    $parts=$raw -split '(?m)^# POWERSHELL_START\r?$',2
    if($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])){throw 'The companion hwid.bat is incomplete or incompatible. Download a complete copy.'}
    & ([scriptblock]::Create($parts[1]))
}catch{
    $message='[COMPAT-03] '+$_.Exception.Message
    try {Write-Host $message}catch{[Console]::Error.WriteLine($message)}
    exit 1
}
