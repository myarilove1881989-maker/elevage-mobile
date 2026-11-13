param([ValidateSet('test','analyze')][string]$Mode='test',[string[]]$Targets=@('test'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$root=Split-Path $repo -Parent
if($root -notlike 'D:*'){throw 'D: required'}
$env:TEMP="$root/qualification/tmp";$env:TMP=$env:TEMP;$env:TMPDIR=$env:TEMP
$env:PUB_CACHE='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\pub-cache'
$env:USERPROFILE="$root/qualification/cache/profile";$env:APPDATA="$env:USERPROFILE\AppData\Roaming";$env:LOCALAPPDATA="$env:USERPROFILE\AppData\Local"
$env:GRADLE_USER_HOME="$root\cache\gradle";$env:ANDROID_USER_HOME="$root\cache\android"
$env:FLUTTER_ROOT='D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk'
$env:CI='true';$env:FLUTTER_SUPPRESS_ANALYTICS='true';$env:DART_SUPPRESS_ANALYTICS='true'
$env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='safe.directory';$env:GIT_CONFIG_VALUE_0='D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk'
$env:ELEVAGE_AQUATIC_PROOF_DIR="$root/qualification/captures/phase1"
$env:ELEVAGE_PHASE3D_CAPTURES="$root/qualification/captures/phase3d"
foreach($phase in @('1','2A','2B','2C','3A','3B','3C','3D')) {
 [Environment]::SetEnvironmentVariable("ELEVAGE_PHASE${phase}_CAPTURES","$root/qualification/captures/phase$($phase.ToLower())")
 New-Item -ItemType Directory -Force -Path "$root/qualification/captures/phase$($phase.ToLower())" | Out-Null
}
New-Item -ItemType Directory -Force -Path $env:ELEVAGE_PHASE3D_CAPTURES,"$root/qualification/captures/evidence" | Out-Null
New-Item -ItemType Directory -Force -Path $env:TEMP,$env:USERPROFILE,$env:APPDATA,$env:LOCALAPPDATA | Out-Null
Set-Location "$root/flutter"
$dart='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\flutter-sdk\bin\cache\dart-sdk\bin\dart.exe'
$tool='D:\ElevAge-Android-Validation-20261023-01\operation-20261025\flutter-sdk\bin\cache\flutter_tools.snapshot'
if($Mode -eq 'analyze'){& $dart analyze lib/pisciculture lib/services/invoice_pdf_service.dart test/aquatic_phase3d_test.dart}
else{& $dart $tool test --no-pub --concurrency=1 @Targets}
exit $LASTEXITCODE
