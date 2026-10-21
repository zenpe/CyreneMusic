#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('android', 'windows', 'all')]
    [string]$Target = 'all',
    [switch]$SkipQualityChecks
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Initialize-CyreneToolchain -RepositoryRoot $repoRoot

if ($Target -in @('windows', 'all') -and -not $IsWindows) {
    throw 'Windows releases must be built on Windows.'
}

Push-Location $repoRoot
try {
    $pubspec = Get-Content pubspec.yaml -Raw
    if ($pubspec -notmatch '(?m)^version:\s*([^\s]+)') {
        throw 'Unable to read the application version.'
    }
    $version = $Matches[1]
    $commit = (& git rev-parse --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Git commit.' }
    $dirty = @(& git status --porcelain).Count -gt 0
    $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    $output = Join-Path $repoRoot "build/releases/$runId"
    New-Item -ItemType Directory -Path $output | Out-Null
    $steps = [System.Collections.Generic.List[object]]::new()
    $artifacts = [System.Collections.Generic.List[object]]::new()
    $manifest = [ordered]@{
        version = $version
        commit = $commit
        dirty = $dirty
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
        success = $false
        qualityChecksSkipped = [bool]$SkipQualityChecks
        steps = $steps
        artifacts = $artifacts
    }

    function Invoke-ReleaseStep([string]$Name, [scriptblock]$Action) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $false
        Write-Host "Starting $Name..."
        try {
            & $Action 2>&1 | Tee-Object -FilePath (Join-Path $output "$Name.log") | Out-Host
            $ok = $true
        } finally {
            $timer.Stop()
            $steps.Add([ordered]@{
                name = $Name
                seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
                success = $ok
            })
            Write-Host "$Name finished in $([Math]::Round($timer.Elapsed.TotalSeconds, 1)) s (success=$ok)"
        }
    }

    function Add-ReleaseArtifact([string]$Platform, [string]$Path) {
        $artifacts.Add([ordered]@{
            platform = $Platform
            file = Split-Path -Leaf $Path
            bytes = (Get-Item -LiteralPath $Path).Length
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }

    try {
        Invoke-ReleaseStep 'toolchain' {
            Invoke-CyreneFlutter -Arguments @('--version')
            Write-Host "GRADLE_USER_HOME=$env:GRADLE_USER_HOME"
            Write-Host "PUB_CACHE=$env:PUB_CACHE"
            Write-Host "JAVA_HOME=$env:JAVA_HOME"
        }
        if ($SkipQualityChecks) {
            Invoke-ReleaseStep 'dependencies' {
                Invoke-CyreneFlutter -Arguments @('pub', 'get', '--enforce-lockfile')
            }
        } else {
            Invoke-ReleaseStep 'quality-checks' {
                & (Join-Path $PSScriptRoot 'quality_check.ps1')
            }
        }
        $suffix = "$($version.Replace('+', '-'))-$commit"
        if ($dirty) { $suffix += '-dirty' }

        if ($Target -in @('android', 'all')) {
            $taskTimings = Join-Path $output 'android-tasks.json'
            Invoke-ReleaseStep 'android-build' {
                Invoke-CyreneFlutter -Arguments @(
                    'build', 'apk', '--release', '--no-pub',
                    '--target-platform', 'android-arm64',
                    "--android-project-arg=cyreneBuildTimingFile=$taskTimings"
                )
            }
            Invoke-ReleaseStep 'android-package' {
                $apk = Join-Path $output "CyreneMusic-android-$suffix.apk"
                Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $apk
                Add-ReleaseArtifact 'android-arm64' $apk
            }
            if (Test-Path -LiteralPath $taskTimings) {
                (Get-Content -LiteralPath $taskTimings -Raw | ConvertFrom-Json).tasks |
                    Select-Object -First 10 task, durationMs, outcome | Format-Table | Out-Host
            }
        }
        if ($Target -in @('windows', 'all')) {
            Invoke-ReleaseStep 'windows-build' {
                Invoke-CyreneFlutter -Arguments @('build', 'windows', '--release', '--no-pub')
            }
            Invoke-ReleaseStep 'windows-package' {
                $zip = Join-Path $output "CyreneMusic-windows-$suffix.zip"
                Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath $zip -CompressionLevel Optimal
                Add-ReleaseArtifact 'windows-x64' $zip
            }
        }
        $manifest.success = $true
    } finally {
        $manifest['finishedAtUtc'] = [DateTime]::UtcNow.ToString('o')
        $manifest | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $output 'build-info.json') -Encoding utf8
        Write-Host "Build reports and artifacts: $output"
    }
} finally {
    Pop-Location
}
