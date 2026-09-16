#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Project = '.',
    [string]$BuildDirectory,
    [string]$SdkRoot,
    [string]$ToolchainRoot,
    [string]$SdkEnvRoot,
    [string]$SdkRevision,
    [switch]$NonInteractive,
    [ValidateSet('en','zh')][string]$Language = 'en'
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/paths.ps1"
$selection = Resolve-HpmInstallPaths -Project $Project -BuildDirectory $BuildDirectory -SdkRoot $SdkRoot -ToolchainRoot $ToolchainRoot -SdkEnvRoot $SdkEnvRoot -SdkRevision $SdkRevision -NonInteractive:$NonInteractive -Language $Language
# Import validates original inputs and rejects file conflicts before writing.
& "$PSScriptRoot/import.ps1" -Project $selection.Project -BuildDirectory $selection.BuildDirectory -SdkRoot $selection.SdkRoot -ToolchainRoot $selection.ToolchainRoot -SdkRevision $selection.SdkRevision
$private = Join-Path $selection.Project '.hpm'
New-Item -ItemType Directory -Path $private -Force | Out-Null
foreach ($item in @(@('sdk',$selection.SdkRoot), @('toolchain',$selection.ToolchainRoot))) {
    $link = Join-Path $private $item[0]
    if (Test-Path -LiteralPath $link) {
        if ([IO.Path]::GetFullPath($link) -ne [IO.Path]::GetFullPath($item[1])) {
            throw "Existing dependency location: $link. Preserve it, then bind the intended installation explicitly."
        }
    } else {
        New-Item -ItemType Junction -Path $link -Target $item[1] | Out-Null
    }
}
$lock = Get-Content -LiteralPath (Join-Path $selection.Project 'hpm-lock.json') -Raw | ConvertFrom-Json
$local = [ordered]@{
    sdkRoot=$selection.SdkRoot; toolchainRoot=$selection.ToolchainRoot; sdkEnvRoot=$selection.SdkEnvRoot
    sdkSourceKind=$(if (Test-Path -LiteralPath (Join-Path $selection.SdkRoot '.git')) { 'git' } else { 'archive' })
    sdkCommit=$lock.sdk.commit
    sdkVersionSha256=(Get-FileHash -LiteralPath (Join-Path $selection.SdkRoot 'VERSION')).Hash
}
[IO.File]::WriteAllText((Join-Path $private 'local.json'), ($local | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding($false)))
& (Join-Path $selection.Project '.hpm-cmake/sync.ps1')
& (Join-Path $selection.Project '.hpm-cmake/doctor.ps1')
Write-Host (Get-HpmMessage 'ready' $Language)
Write-Host ('  & ' + "'" + (Join-Path $selection.Project 'activate.ps1').Replace("'","''") + "'")
Write-Host '  cmake --preset default'
Write-Host '  cmake --build --preset default --parallel'
