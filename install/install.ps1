#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Project = '.',
    [string]$SdkRoot,
    [string]$ToolchainRoot,
    [string]$SdkEnvRoot,
    [string]$Version = 'latest',
    [string]$PythonExecutable,
    [switch]$NonInteractive,
    [ValidateSet('en','zh')][string]$Language = 'en'
)
$ErrorActionPreference = 'Stop'
$repository = 'guajun/hpm-venv'
$projectPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Project)
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) { throw '-Project must be an existing directory.' }
if ($Version -eq 'latest') {
    $release = Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest"
    $Version = $release.tag_name
}
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.-]+)?$') { throw 'Invalid release version.' }
$base = "https://github.com/$repository/releases/download/$Version"
$staging = Join-Path $projectPath ('.hpm-venv-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $archive = Join-Path $staging 'hpm-venv.zip'
    $checksums = Join-Path $staging 'checksums.txt'
    Invoke-WebRequest -UseBasicParsing "$base/hpm-venv.zip" -OutFile $archive
    Invoke-WebRequest -UseBasicParsing "$base/checksums.txt" -OutFile $checksums
    $lines = @(Get-Content -LiteralPath $checksums | Where-Object { $_ -match '^[0-9a-fA-F]{64}\s+\*?hpm-venv\.zip$' })
    if ($lines.Count -ne 1) { throw 'Release must contain one exact hpm-venv.zip checksum.' }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne ($lines[0] -split '\s+')[0]) {
        throw 'Release archive checksum verification failed.'
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $staging
    $entry = Join-Path $staging 'hpm-venv/scripts/setup.ps1'
    & $entry -Project $projectPath -SdkRoot $SdkRoot -ToolchainRoot $ToolchainRoot -SdkEnvRoot $SdkEnvRoot -PythonExecutable $PythonExecutable -NonInteractive:$NonInteractive -Language $Language
    Write-Host "Installed hpm-venv $Version into the existing application."
} finally {
    # Only delete the unique staging directory created inside this application.
    $absolute = [IO.Path]::GetFullPath($staging)
    $prefix = [IO.Path]::GetFullPath($projectPath).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($absolute) -notmatch '^\.hpm-venv-install-[0-9a-f]{32}$') {
        throw 'Unexpected release staging path; refusing cleanup.'
    }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
