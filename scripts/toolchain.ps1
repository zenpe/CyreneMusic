Set-StrictMode -Version Latest

function Initialize-CyreneToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    $repositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $repositoryDrive = [System.IO.Path]::GetPathRoot($repositoryRoot)
    $devRoot = if ([string]::IsNullOrWhiteSpace($env:CYRENE_DEV_ROOT)) {
        Join-Path $repositoryDrive 'DevTools'
    } else {
        [System.IO.Path]::GetFullPath($env:CYRENE_DEV_ROOT)
    }

    $cachePaths = [ordered]@{
        PURO_ROOT = Join-Path $devRoot 'Puro'
        PUB_CACHE = Join-Path $devRoot 'PubCache'
        GRADLE_USER_HOME = Join-Path $devRoot 'Gradle'
        ANDROID_HOME = Join-Path $devRoot 'Android\Sdk'
        ANDROID_SDK_ROOT = Join-Path $devRoot 'Android\Sdk'
        ANDROID_USER_HOME = Join-Path $devRoot 'Android\UserHome'
        ANDROID_AVD_HOME = Join-Path $devRoot 'Android\UserHome\avd'
    }

    foreach ($entry in $cachePaths.GetEnumerator()) {
        $currentValue = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        $isOnSystemDrive = -not [string]::IsNullOrWhiteSpace($currentValue) -and
            ([System.IO.Path]::GetPathRoot($currentValue) -eq $env:SystemDrive + '\')
        if ([string]::IsNullOrWhiteSpace($currentValue) -or $isOnSystemDrive) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }

    $script:CyreneUsePuro = $null -ne (Get-Command puro -ErrorAction SilentlyContinue)
    if (-not $script:CyreneUsePuro -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter was not found. Install Puro or Flutter 3.41.3 before continuing.'
    }
}

function Invoke-CyreneFlutter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    if ($script:CyreneUsePuro) {
        & puro flutter @Arguments
    } else {
        & flutter @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-CyreneDart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    if ($script:CyreneUsePuro) {
        & puro dart @Arguments
    } else {
        & dart @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "dart $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}
