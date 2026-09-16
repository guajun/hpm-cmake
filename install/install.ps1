#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$Version = 'latest',
    [string]$SdkRevision
)
$ErrorActionPreference = 'Stop'
$repository = 'guajun/hpm-cmake'
$projectPath = (Resolve-Path -LiteralPath $Project).Path
$buildPath = (Resolve-Path -LiteralPath $BuildDirectory).Path
if ($Version -eq 'latest') {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest"
    $Version = $release.tag_name
}
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.-]+)?$') { throw 'Invalid release version.' }
$base = "https://github.com/$repository/releases/download/$Version"
$staging = Join-Path $projectPath ('.hpm-cmake-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $archive = Join-Path $staging 'hpm-cmake.zip'
    $checksums = Join-Path $staging 'checksums.txt'
    Invoke-WebRequest -UseBasicParsing "$base/hpm-cmake.zip" -OutFile $archive
    Invoke-WebRequest -UseBasicParsing "$base/checksums.txt" -OutFile $checksums
    $lines = @(Get-Content -LiteralPath $checksums | Where-Object { $_ -match '^[0-9a-fA-F]{64}\s+\*?hpm-cmake\.zip$' })
    if ($lines.Count -ne 1) { throw 'Release must contain one exact hpm-cmake.zip checksum.' }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne ($lines[0] -split '\s+')[0]) {
        throw 'Release archive checksum verification failed.'
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $staging
    $entry = Join-Path $staging 'hpm-cmake/hpm-cmake.ps1'
    & $entry import -Project $projectPath -BuildDirectory $buildPath -SdkRevision $SdkRevision
    Write-Host "Installed hpm-cmake $Version into the existing application."
} finally {
    # Only delete the unique staging directory created inside this application.
    $absolute = [IO.Path]::GetFullPath($staging)
    $prefix = [IO.Path]::GetFullPath($projectPath).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($absolute) -notmatch '^\.hpm-cmake-install-[0-9a-f]{32}$') {
        throw 'Unexpected release staging path; refusing cleanup.'
    }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
