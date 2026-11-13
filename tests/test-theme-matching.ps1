param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$folder=Join-Path $PSScriptRoot ('test-output-theme-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
$resultPath=Join-Path $folder 'result.json'
$probe=@'
$ErrorActionPreference='Stop'
$checks=0
function Assert($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
try{
 $source='__SOURCE__'
 $text=([IO.File]::ReadAllText($source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors.Message -join '; ')}
 foreach($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($fn.Extent.Text))}
 $preference=Join-Path '__FOLDER__' "preferences ! & [1].json"
 Assert ((Get-CheckerTheme '' $preference) -eq 'Midnight') 'Missing settings did not fall back to Midnight.'
 Assert ((Get-CheckerTheme $null $preference) -eq 'Midnight') 'A missing theme environment value did not retain a readable default.'
 [IO.File]::WriteAllText($preference,'{"darkTheme":false}')
 Assert ((Get-CheckerTheme '' $preference) -eq 'Daylight') 'Saved Desktop Daylight did not reach the BAT.'
 Assert ((Get-CheckerTheme ' midnight ' $preference) -eq 'Midnight') 'An explicit session theme did not override saved settings.'
 Assert ((Get-CheckerTheme ' DAYLIGHT ' $preference) -eq 'Daylight') 'Theme override did not accept case/outer whitespace.'
 Assert ((Get-CheckerTheme 'unknown' $preference) -eq 'Daylight') 'An invalid override prevented valid saved settings.'
 foreach($invalid in @('{"darkTheme":"false"}','[{"darkTheme":false}]','null','{bad json','{"darkTheme":0}')){
  [IO.File]::WriteAllText($preference,$invalid)
  Assert ((Get-CheckerTheme '' $preference) -eq 'Midnight') 'Invalid settings did not retain a readable default.'
 }
 [IO.File]::WriteAllText($preference,(' '*262145))
 Assert ((Get-CheckerTheme '' $preference) -eq 'Midnight') 'Oversized theme settings were not ignored.'
 $desktop=[IO.File]::ReadAllText((Join-Path (Split-Path -Parent $source) 'desktop\MainWindow.xaml.cs'))
 $themes=@{}
 foreach($theme in @('Midnight','Daylight')){
  $block=[regex]::Match($desktop,('(?s)'+$theme+'Colors\s*=.*?\{(.*?)\r?\n    \};')).Groups[1].Value
  $colors=@{}
  foreach($match in [regex]::Matches($block,'\["([A-Za-z]+Brush)"\]\s*=\s*"#([a-fA-F0-9]{6})"')){
   $hex=$match.Groups[2].Value
   $colors[$match.Groups[1].Value]=[uint32]([Convert]::ToInt32($hex.Substring(0,2),16)+256*[Convert]::ToInt32($hex.Substring(2,2),16)+65536*[Convert]::ToInt32($hex.Substring(4,2),16))
  }
  if(-not $colors.CanvasBrush){throw 'Desktop theme fixture could not read its source colors.'}
  $themes[$theme]=$colors
 }
 $roles=@{0='CanvasBrush';1='PanelBrush';7='MutedBrush';8='BorderBrush';10='SuccessBrush';11='AccentBrush';12='ErrorBrush';14='WarningBrush';15='TextBrush'}
 foreach($theme in @('Midnight','Daylight')){
  $env:HWID_THEME=$theme
  $result=Initialize-ReadableConsole $true $false
  Assert ($result.Theme -eq $theme -and $result.ThemeApplied) 'The owned console did not apply its selected theme.'
  foreach($index in $roles.Keys){
   Assert ([HwidConsoleDisplay]::ReadThemeColor($index) -eq $themes[$theme][$roles[$index]]) ('BAT '+$theme+' color differs from Desktop '+$roles[$index])
  }
  if([Environment]::OSVersion.Version.Build -ge 22000){Assert $result.CaptionThemeApplied 'Supported Windows did not accept the console caption theme.'}
  Assert ([Console]::BackgroundColor -eq [ConsoleColor]::Black -and [Console]::ForegroundColor -eq [ConsoleColor]::White) 'Theme changes modified the logical text/background color indexes.'
 }
 $before=[HwidConsoleDisplay]::ReadBackground()
 $hostResult=Initialize-ReadableConsole $false $false
 Assert ($hostResult.Theme -eq 'Host' -and -not $hostResult.ThemeApplied -and [HwidConsoleDisplay]::ReadBackground() -eq $before) 'A current-window launch overwrote the inherited host theme.'
 $redirected=Initialize-ReadableConsole $true $true
 Assert ($redirected.Theme -eq 'Host' -and -not $redirected.ThemeApplied) 'Redirected execution tried to style a console.'
 [IO.File]::WriteAllText('__RESULT__',(@{Checks=$checks;Runtime=$PSVersionTable.PSVersion.ToString();RealHardwareRead=$false;Success=$true}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}catch{
 [IO.File]::WriteAllText('__RESULT__',(@{Checks=$checks;Error=$_.Exception.Message;Line=$_.InvocationInfo.ScriptLineNumber}|ConvertTo-Json),[Text.UTF8Encoding]::new($false));exit 1
}
'@
$probe=$probe.Replace('__SOURCE__',([IO.Path]::GetFullPath($Source)).Replace("'","''")).Replace('__FOLDER__',$folder.Replace("'","''")).Replace('__RESULT__',$resultPath.Replace("'","''"))
$scriptPath=Join-Path $folder 'probe.ps1'
[IO.File]::WriteAllText($scriptPath,$probe,[Text.UTF8Encoding]::new($true))
$engine=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList ('-ForceNoHandoff -- "'+$engine+'" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"') -WindowStyle Hidden -PassThru
try{if(-not $process.WaitForExit(30000)){throw 'Native theme matching checks exceeded 30 seconds.'}}finally{$process.Dispose()}
if(-not [IO.File]::Exists($resultPath)){throw 'Native theme matching checks did not return a result.'}
$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
if($result.Error){throw ($result.Error+' / line '+$result.Line+' / after '+$result.Checks+' checks')}
$result|ConvertTo-Json
Write-Output ("All $($result.Checks) theme-matching checks passed under PowerShell $($result.Runtime).")
