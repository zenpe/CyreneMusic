[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Initialize-CyreneToolchain -RepositoryRoot $repoRoot
Set-Location $repoRoot

Write-Host 'Resolving locked dependencies...'
Invoke-CyreneFlutter -Arguments @('pub', 'get', '--enforce-lockfile')

Write-Host 'Running static analysis...'
if ($Strict) {
    Invoke-CyreneFlutter -Arguments @('analyze')
} else {
    Invoke-CyreneDart -Arguments @('run', 'tool/check_analyzer_baseline.dart')
}

Write-Host 'Checking test formatting...'
Invoke-CyreneDart -Arguments @('format', '--output=none', '--set-exit-if-changed', 'test')

Write-Host 'Running tests...'
Invoke-CyreneFlutter -Arguments @('test')

Write-Host 'Quality checks passed.' -ForegroundColor Green
