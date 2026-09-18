[CmdletBinding()]
param(
    [string]$AvdName = 'Cyrene_Car_Tablet_API_36',

    [ValidateRange(5554, 5682)]
    [int]$Port = 5556,

    [switch]$ColdBoot,

    [switch]$NoResident
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Initialize-CyreneToolchain -RepositoryRoot $repoRoot
Set-Location $repoRoot

$emulator = Join-Path $env:ANDROID_HOME 'emulator\emulator.exe'
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
if (-not (Test-Path $emulator) -or -not (Test-Path $adb)) {
    throw 'Android Emulator or ADB is missing from ANDROID_HOME.'
}

$availableAvds = & $emulator -list-avds
if ($AvdName -notin $availableAvds) {
    throw "Android AVD '$AvdName' was not found in $env:ANDROID_AVD_HOME."
}

$serial = "emulator-$Port"
$connectedDevices = & $adb devices
if ($connectedDevices -notmatch "(?m)^$([regex]::Escape($serial))\s+device$") {
    $emulatorArguments = @(
        '-avd', $AvdName,
        '-port', $Port.ToString(),
        '-skin', '1920x1080',
        '-dpi-device', '240',
        '-memory', '4096',
        '-gpu', 'auto',
        '-no-boot-anim'
    )
    if ($ColdBoot) {
        $emulatorArguments += '-no-snapshot-load'
    }

    Write-Host "Starting $AvdName as $serial..."
    Start-Process -FilePath $emulator -ArgumentList $emulatorArguments | Out-Null
}

& $adb -s $serial wait-for-device
if ($LASTEXITCODE -ne 0) {
    throw "ADB could not connect to $serial."
}

$bootCompleted = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    $bootState = (& $adb -s $serial shell getprop sys.boot_completed 2>$null).Trim()
    if ($bootState -eq '1') {
        $bootCompleted = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $bootCompleted) {
    throw "$serial did not finish booting within four minutes."
}

& $adb -s $serial shell wm size 1920x1080 | Out-Null
& $adb -s $serial shell wm density 240 | Out-Null
& $adb -s $serial shell settings put system accelerometer_rotation 0 | Out-Null
# This AVD has a landscape-native display. Rotation 1 turns its logical
# viewport into 1080x1920, so keep the native orientation for car testing.
& $adb -s $serial shell settings put system user_rotation 0 | Out-Null

Write-Host "Running Cyrene Music on $serial (1920x1080 landscape, 240 dpi)..."
$runArguments = @('run', '-d', $serial)
if ($NoResident) {
    $runArguments += '--no-resident'
}
Invoke-CyreneFlutter -Arguments $runArguments
