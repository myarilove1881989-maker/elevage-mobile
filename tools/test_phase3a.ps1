param([string]$Mode='test',[string[]]$Targets=@('test/aquatic_phase3a_test.dart'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$root=Split-Path $repo -Parent
if($root -notlike 'D:*'){throw 'D: required'}
$env:TEMP="$root/phase3a/tmp";$env:TMP=$env:TEMP;$env:TMPDIR=$env:TEMP
$env:PUB_CACHE='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\pub-cache'
$env:USERPROFILE="$root/phase3a/cache/profile";$env:APPDATA="$env:USERPROFILE\AppData\Roaming";$env:LOCALAPPDATA="$env:USERPROFILE\AppData\Local"
$env:GRADLE_USER_HOME="$root\cache\gradle";$env:ANDROID_USER_HOME="$root\cache\android"
$env:FLUTTER_ROOT='D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk'
$env:CI='true';$env:FLUTTER_SUPPRESS_ANALYTICS='true';$env:DART_SUPPRESS_ANALYTICS='true'
$env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='safe.directory';$env:GIT_CONFIG_VALUE_0='D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk'
$env:ELEVAGE_PHASE3A_CAPTURES="$root/phase3a/captures"
New-Item -ItemType Directory -Force -Path $env:ELEVAGE_PHASE3A_CAPTURES | Out-Null
New-Item -ItemType Directory -Force -Path $env:TEMP,$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA | Out-Null
Set-Location "$root/flutter"
$dart='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\flutter-sdk\bin\cache\dart-sdk\bin\dart.exe'
$tool='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\flutter-sdk\bin\cache\flutter_tools.snapshot'
if($Mode -eq 'analyze'){& $dart analyze lib/pisciculture test/aquatic_phase3a_test.dart}
elseif($Mode -eq 'format'){& $dart format lib/pisciculture/health_panel.dart lib/pisciculture/aquatic_workspace.dart test/aquatic_phase3a_test.dart}
else{& $dart $tool test --no-pub --concurrency=1 @Targets}
exit $LASTEXITCODE
