#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path $output ([Guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'hpm-venv'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
foreach ($name in @('hpm-venv.ps1','hpm-venv.sh','VERSION','README.md','README.zh-CN.md','LICENSE','scripts','install','templates')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $payload -Recurse
}
$archive = Join-Path $output 'hpm-venv.zip'
Compress-Archive -LiteralPath $payload -DestinationPath $archive -Force
Copy-Item -LiteralPath (Join-Path $root 'install/install.ps1') -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $root 'install/install.sh') -Destination $output -Force
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $output 'checksums.txt') -Value "$hash  hpm-venv.zip" -Encoding ASCII
$absoluteStage = [IO.Path]::GetFullPath($stage)
if (-not $absoluteStage.StartsWith([IO.Path]::GetFullPath($output).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($absoluteStage) -notmatch '^[0-9a-f]{32}$') { throw 'Unexpected packaging stage.' }
Remove-Item -LiteralPath $absoluteStage -Recurse -Force
Write-Host "Packaged $archive"
