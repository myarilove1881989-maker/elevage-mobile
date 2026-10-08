param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9._:-]+$')][string]$Serial,
    [string]$OutputPath = (Join-Path $PSScriptRoot '../build/phase2k-device-inventory.json')
)
$ErrorActionPreference = 'Stop'
function Read-Adb([string[]]$Arguments) {
    $result = & adb -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'ADB read failed; no installation attempted.' }
    return ($result -join "`n").Trim()
}
$state = Read-Adb @('get-state')
if ($state -ne 'device') { throw 'USB authorization or device connection required.' }
$before = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$epoch = Read-Adb @('shell','date','+%s')
$after = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
if ($epoch -notmatch '^\d+$') { throw 'Invalid device clock response.' }
$apkPaths = & adb -s $Serial shell pm path com.elevage.app 2>&1
# pm path exits 1 with empty output when the package is not installed.
if ($LASTEXITCODE -ne 0 -and -not ($LASTEXITCODE -eq 1 -and -not $apkPaths)) {
    throw 'Cannot read installed package paths; no installation attempted.'
}
$proof = [ordered]@{
    read_only = $true
    manufacturer = Read-Adb @('shell','getprop','ro.product.manufacturer')
    model = Read-Adb @('shell','getprop','ro.product.model')
    android = Read-Adb @('shell','getprop','ro.build.version.release')
    sdk = Read-Adb @('shell','getprop','ro.build.version.sdk')
    abi = Read-Adb @('shell','getprop','ro.product.cpu.abilist')
    automatic_time = Read-Adb @('shell','settings','get','global','auto_time')
    automatic_timezone = Read-Adb @('shell','settings','get','global','auto_time_zone')
    timezone = Read-Adb @('shell','getprop','persist.sys.timezone')
    device_utc_epoch_seconds = [long]$epoch
    clock_delta_seconds = [math]::Round(([long]$epoch - (($before+$after)/2000)),3)
    round_trip_seconds = ($after-$before)/1000
    apk_paths = ($apkPaths -join "`n").Trim()
    measured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    keystore_pin_offline_validated = $false
}
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$proof | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$proof | ConvertTo-Json -Depth 3
