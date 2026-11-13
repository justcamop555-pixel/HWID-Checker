param([string]$Source=(Join-Path $PSScriptRoot '..\hwid.bat'))
$ErrorActionPreference='Stop'
$body=([IO.File]::ReadAllText($Source) -split '(?m)^# POWERSHELL_START\r?$',2)[1]
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$fn=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ScanDisplayLines'},$false)|Select-Object -First 1
. ([scriptblock]::Create($fn.Extent.Text))
$checks=0
function Assert($value,$name){if(-not $value){throw ('FAILED: '+$name)};$script:checks++;[Console]::WriteLine('PASS: '+$name)}
function SameLines($actual,$expected){return $actual.Count -eq $expected.Count -and -not (Compare-Object $actual $expected -SyncWindow 0 -CaseSensitive)}
$entry=[pscustomobject]@{Text='ABCDEFGHIJK';Value=$false;LayoutCache=$null}
$lines=@(Get-ScanDisplayLines $entry 8)
Assert (SameLines $lines @('ABCDEFG','HIJK')) 'Initial wrapping retains the supported column margin'
$first=$entry.LayoutCache
$again=@(Get-ScanDisplayLines $entry 8)
Assert ([object]::ReferenceEquals($first,$entry.LayoutCache) -and (SameLines $again $lines)) 'Unchanged text reuses its existing layout instead of wrapping again'
$entry.Text='abcdefghijk';$lines=@(Get-ScanDisplayLines $entry 8)
Assert (-not [object]::ReferenceEquals($first,$entry.LayoutCache) -and (SameLines $lines @('abcdefg','hijk'))) 'A case-only text change invalidates the layout'
$prior=$entry.LayoutCache;$entry.Text='ABCDEFGHIJK';$lines=@(Get-ScanDisplayLines $entry 20)
Assert (-not [object]::ReferenceEquals($prior,$entry.LayoutCache) -and (SameLines $lines @('ABCDEFGHIJK'))) 'Widening the console rebuilds from the full authoritative text'
$lines=@(Get-ScanDisplayLines $entry 8)
Assert (SameLines $lines @('ABCDEFG','HIJK')) 'A shrink-grow round trip retains every character'
$entry.Text='ABCDEFGHIJKLMNOPQRSTUVWXYZ';$entry.Value=$false;$null=@(Get-ScanDisplayLines $entry 21);$prior=$entry.LayoutCache
$entry.Value=$true;$lines=@(Get-ScanDisplayLines $entry 21)
Assert (-not [object]::ReferenceEquals($prior,$entry.LayoutCache) -and (SameLines $lines @('ABCDEFGHIJKLMNOPQRST','    UVWXYZ'))) 'Switching value indentation invalidates a prior plain-text layout'
$entry.Text="Alpha`tBeta`n`nGamma";$lines=@(Get-ScanDisplayLines $entry 80)
Assert (SameLines $lines @('Alpha Beta','','Gamma')) 'Control normalization preserves embedded empty lines'
$rocket=[string][char]0xd83d+[string][char]0xde80;$entry.Text='abc'+$rocket+'DEFG';$entry.Value=$false
$lines=@(Get-ScanDisplayLines $entry 5)
Assert (SameLines $lines @('abc',($rocket+'DE'),'FG')) 'Supported wrapping boundaries retain complete surrogate pairs'
$external=[pscustomobject]@{Text='ABCDEFGHIJK';Value=$false};$lines=@(Get-ScanDisplayLines $external 8)
Assert ((SameLines $lines @('ABCDEFG','HIJK')) -and $null -eq $external.PSObject.Properties['LayoutCache']) 'Legacy caller objects remain usable without cache metadata'
$entry.Text='e'+[char]0x301;$null=@(Get-ScanDisplayLines $entry 80);$prior=$entry.LayoutCache
$entry.Text=[string][char]0xe9;$lines=@(Get-ScanDisplayLines $entry 80)
Assert (-not [object]::ReferenceEquals($prior,$entry.LayoutCache) -and [string]::Equals($lines[0],$entry.Text,[StringComparison]::Ordinal)) 'Canonically equivalent Unicode text still retains its exact original characters'
$entry.Text='';$lines=@(Get-ScanDisplayLines $entry 80)
Assert ($lines.Count -eq 1 -and $lines[0] -eq '') 'An empty entry retains its blank display row'
Assert (@(Get-ScanDisplayLines $null 80).Count -eq 1) 'Null legacy entries retain a blank row instead of crashing'
$text=('SYNTHETIC-DEVICE-0123456789 '*70)
$cached=[pscustomobject]@{Text=$text;Value=$true;LayoutCache=$null};$plain=[pscustomobject]@{Text=$text;Value=$true}
$null=@(Get-ScanDisplayLines $cached 80)
$watch=[Diagnostics.Stopwatch]::StartNew();for($i=0;$i -lt 300;$i++){$null=@(Get-ScanDisplayLines $cached 80)};$cachedMs=$watch.ElapsedMilliseconds
$watch.Restart();for($i=0;$i -lt 300;$i++){$null=@(Get-ScanDisplayLines $plain 80)};$plainMs=$watch.ElapsedMilliseconds
Assert (SameLines @(Get-ScanDisplayLines $cached 80) @(Get-ScanDisplayLines $plain 80)) 'The cache optimization preserves full output for long retained values'
[Console]::WriteLine("Synthetic wrapping benchmark: 300 reads / cached ${cachedMs}ms / uncached ${plainMs}ms. No timing threshold enforced.")
[Console]::WriteLine("All $checks scan-display cache checks passed under PowerShell $($PSVersionTable.PSVersion).")
