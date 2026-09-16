#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][ValidateSet('init')][string]$Command,
    [Parameter(Mandatory)][string]$Project
)
$ErrorActionPreference = 'Stop'
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Project)
if (Test-Path -LiteralPath $destination) {
    if (@(Get-ChildItem -LiteralPath $destination -Force).Count) {
        throw 'The destination must be empty. Existing firmware projects are not overwritten.'
    }
} else { New-Item -ItemType Directory -Path $destination -Force | Out-Null }
foreach ($name in @('.gitignore', '.gitattributes', 'CMakeLists.txt', 'CMakePresets.json', 'hpm-cmake.ps1', 'hpm-lock.json', 'README.md', 'LICENSE', 'cmake', 'scripts', 'src')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $destination -Recurse
}
Write-Host "Created standalone HPM6E00EVK blink project at $destination"
Write-Host 'Run ./scripts/sync.ps1 from the new project, then cmake --preset debug.'
