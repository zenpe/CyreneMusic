[CmdletBinding()]
param(
    [ValidateSet('android', 'windows', 'all')]
    [string]$Target = 'android',

    [ValidateSet('debug', 'profile')]
    [string]$AndroidMode = 'debug',

    [ValidateSet('debug', 'release')]
    [string]$WindowsMode = 'release',

    [string]$OutputDirectory = 'artifacts/test',

    [switch]$SkipQualityChecks
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Initialize-CyreneToolchain -RepositoryRoot $repoRoot
Set-Location $repoRoot

$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([^\s]+)') {
    throw 'Unable to read the application version from pubspec.yaml.'
}
$version = $Matches[1]

$commit = 'local'
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitCommit = & git -c "safe.directory=$($repoRoot.Replace('\', '/'))" rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitCommit) {
        $commit = $gitCommit.Trim()
    }
}

$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
}
$repoPrefix = $repoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedOutput.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be inside the repository.'
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

if ($SkipQualityChecks) {
    Write-Warning 'Quality checks were skipped.'
    Invoke-CyreneFlutter -Arguments @('pub', 'get', '--enforce-lockfile')
} else {
    & (Join-Path $PSScriptRoot 'quality_check.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "Quality checks failed with exit code $LASTEXITCODE"
    }
}

$artifacts = [System.Collections.Generic.List[object]]::new()
$safeVersion = $version.Replace('+', '-')

if ($Target -in @('android', 'all')) {
    Write-Host "Building Android $AndroidMode APK..."
    Invoke-CyreneFlutter -Arguments @('build', 'apk', "--$AndroidMode")
    $sourceApk = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-$AndroidMode.apk"
    if (-not (Test-Path $sourceApk)) {
        throw "Expected Android artifact was not found: $sourceApk"
    }
    $apkName = "cyrene-music_${safeVersion}_test_android-$AndroidMode`_$commit.apk"
    $apkPath = Join-Path $resolvedOutput $apkName
    Copy-Item -LiteralPath $sourceApk -Destination $apkPath -Force
    $artifacts.Add([pscustomobject]@{
        platform = 'android'
        mode = $AndroidMode
        file = $apkName
        sha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

if ($Target -in @('windows', 'all')) {
    if (-not $IsWindows) {
        throw 'Windows builds must run on Windows.'
    }
    Write-Host "Building Windows $WindowsMode bundle..."
    Invoke-CyreneFlutter -Arguments @('config', '--enable-windows-desktop')
    Invoke-CyreneFlutter -Arguments @('build', 'windows', "--$WindowsMode")
    $configuration = (Get-Culture).TextInfo.ToTitleCase($WindowsMode)
    $sourceDirectory = Join-Path $repoRoot "build/windows/x64/runner/$configuration"
    if (-not (Test-Path $sourceDirectory)) {
        throw "Expected Windows bundle was not found: $sourceDirectory"
    }
    $zipName = "cyrene-music_${safeVersion}_test_windows-x64-$WindowsMode`_$commit.zip"
    $zipPath = Join-Path $resolvedOutput $zipName
    Compress-Archive -Path (Join-Path $sourceDirectory '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
    $artifacts.Add([pscustomobject]@{
        platform = 'windows'
        mode = $WindowsMode
        file = $zipName
        sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

$flutterVersion = if ($script:CyreneUsePuro) {
    & puro flutter --version --machine | ConvertFrom-Json
} else {
    & flutter --version --machine | ConvertFrom-Json
}
$manifest = [ordered]@{
    application = 'Cyrene Music'
    version = $version
    commit = $commit
    branch = 'just_audio'
    flutter = $flutterVersion.frameworkVersion
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    artifacts = $artifacts
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $resolvedOutput 'build-info.json') -Encoding utf8

Write-Host "Test artifacts are ready in $resolvedOutput" -ForegroundColor Green
$artifacts | Format-Table platform, mode, file, sha256 -AutoSize
