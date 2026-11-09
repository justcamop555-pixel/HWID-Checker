param($Mode,$InstallDirectory,$CurrentVersion,$Component,$ResultPath,$StageDirectory,$WaitProcessId,$WaitProcessStartTicks,[switch]$Relaunch)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Mode -eq 'Apply'){
    [IO.File]::WriteAllText((Join-Path $InstallDirectory 'applied.json'),(@{component=$Component;process=$WaitProcessId;ticks=$WaitProcessStartTicks;relaunch=$Relaunch.IsPresent;source=$CurrentVersion}|ConvertTo-Json))
    return
}
if(Test-Path -LiteralPath (Join-Path $InstallDirectory 'bad.flag')){[Console]::WriteLine('invalid JSON');return}
if(Test-Path -LiteralPath (Join-Path $InstallDirectory 'slow.flag')){Start-Sleep -Seconds 15}
$state=if($Mode -eq 'Check'){'available'}else{'ready'}
$current=[version]$CurrentVersion
$previous=if($current.Build -gt 0){[version]::new($current.Major,$current.Minor,$current.Build-1)}elseif($current.Minor -gt 0){[version]::new($current.Major,$current.Minor-1,0)}else{[version]::new($current.Major-1,0,0)}
$version=if(Test-Path -LiteralPath (Join-Path $InstallDirectory 'older.flag')){$previous.ToString(3)}else{([version]::new($current.Major,$current.Minor,$current.Build+1)).ToString(3)}
if(Test-Path -LiteralPath (Join-Path $InstallDirectory 'equal.flag')){$version=$CurrentVersion;$CurrentVersion=$previous.ToString(3)}
$result=@{state=$state;currentVersion=$CurrentVersion;latestVersion=$version;message='Synthetic update';component=$Component;installDirectory=$InstallDirectory;stageDirectory=(Join-Path $InstallDirectory 'stage')}
$json=$result|ConvertTo-Json
if($ResultPath){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $ResultPath));[IO.File]::WriteAllText($ResultPath,$json)}
[Console]::WriteLine($json)
