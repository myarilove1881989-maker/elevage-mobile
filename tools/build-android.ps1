param([Parameter(Mandatory=$true)][int]$VersionCode,[string]$VersionName='1.0.0')
$ErrorActionPreference='Stop'
if($VersionCode -le 113){throw 'A new build number greater than 113 is required; do not replace delivery 113'}
$repo=Split-Path $PSScriptRoot -Parent
$root=Split-Path $repo -Parent
$env:TEMP=Join-Path $root 'tmp'; $env:TMP=$env:TEMP
$env:GRADLE_USER_HOME=Join-Path $root '.cache/gradle'
$env:ANDROID_USER_HOME=Join-Path $root '.cache/android-user'
$env:PUB_CACHE=if($env:ELEVAGE_PUB_CACHE){$env:ELEVAGE_PUB_CACHE}else{'D:/ElevAge-Android-Validation-20261023-01/operation-20261025/pub-cache'}
$sdk=if($env:ELEVAGE_FLUTTER_SDK){$env:ELEVAGE_FLUTTER_SDK}else{'D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk'}
$revision=(& git.exe -c "safe.directory=$sdk" -C $sdk rev-parse HEAD)
if($LASTEXITCODE -or $revision -ne (Get-Content (Join-Path $PSScriptRoot 'flutter-revision.txt') -Raw).Trim()){throw 'Flutter SDK revision mismatch'}
foreach($name in @('ELEVAGE_KEYSTORE_PATH','ELEVAGE_KEYSTORE_PASSWORD','ELEVAGE_KEY_ALIAS','ELEVAGE_KEY_PASSWORD')){if(![Environment]::GetEnvironmentVariable($name)){throw "Signing environment variable required: $name"}}
# Existing Gradle checks verify the permanent certificate. Never echo secret values.
Set-Location $repo
& (Join-Path $sdk 'bin/flutter.bat') build apk --release --no-pub --flavor production --target-platform android-arm64 --build-number=$VersionCode --build-name=$VersionName --dart-define=APP_ENV=production --dart-define=API_URL=https://backend-elevage.onrender.com/api
if($LASTEXITCODE){throw 'Android build failed'}
Write-Output 'Build produced locally. No distribution or tablet installation performed. Verify APK signature/version before release.'
