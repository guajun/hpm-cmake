Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:PrivateRoot = Join-Path $script:ProjectRoot '.hpm'

function Get-HpmLock {
    Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'hpm-lock.json') -Raw | ConvertFrom-Json
}

function Get-HpmLockHash {
    (Get-FileHash -LiteralPath (Join-Path $script:ProjectRoot 'hpm-lock.json') -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-HpmSdkChanges {
    param([string]$Sdk)
    $changes = @(& git -C $Sdk status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect SDK checkout.' }
    # Official IDE generation imports Python helpers and writes bytecode caches.
    $changes | Where-Object { $_ -notmatch '^\?\? (?:.*/)?__pycache__/[^/]+\.pyc$' }
}

function Invoke-HpmNative {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable exited with code $LASTEXITCODE" }
}

function Assert-HpmHost {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess) {
        throw 'This lock supports 64-bit Windows. Use 64-bit PowerShell 5.1 or newer.'
    }
    foreach ($name in @('git', 'cmake', 'ninja')) {
        if (-not (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "Missing host tool: $name. See README.md prerequisites."
        }
    }
    $versionText = & cmake --version
    if ($LASTEXITCODE -ne 0 -or $versionText[0] -notmatch 'cmake version (\d+\.\d+\.\d+)') {
        throw 'Cannot determine CMake version.'
    }
    if ([version]$Matches[1] -lt [version](Get-HpmLock).hostTools.cmakeMinimum) {
        throw 'CMake 3.24 or newer is required.'
    }
}

function Get-HpmArtifact {
    param($Artifact, [switch]$Offline)
    $cache = Join-Path $script:PrivateRoot 'downloads'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $name = [IO.Path]::GetFileName(([Uri]$Artifact.url).AbsolutePath)
    $path = Join-Path $cache ($Artifact.sha256.Substring(0, 12) + '-' + $name)
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Offline) { throw "Missing cached artifact: $path" }
        Write-Host "Downloading $name"
        $oldProgress = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -Uri $Artifact.url -OutFile "$path.part"
        } finally { $ProgressPreference = $oldProgress }
        if ((Get-FileHash -LiteralPath "$path.part" -Algorithm SHA256).Hash -ne $Artifact.sha256) {
            throw "SHA-256 mismatch for $name. The partial download was not installed."
        }
        Move-Item -LiteralPath "$path.part" -Destination $path -Force
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Artifact.sha256) {
        throw "Cached artifact checksum mismatch: $path"
    }
    return $path
}

function New-HpmStage {
    $path = Join-Path $script:PrivateRoot ('staging/' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Expand-HpmArchive {
    param([string]$Archive, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}

function Assert-HpmManagedPath {
    param([string]$Path)
    $base = [IO.Path]::GetFullPath($script:PrivateRoot).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project dependency directory: $resolved"
    }
}

function Move-HpmInstall {
    param([string]$Source, [string]$Destination)
    Assert-HpmManagedPath $Source
    Assert-HpmManagedPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Refusing to replace existing directory: $Destination" }
    Move-Item -LiteralPath $Source -Destination $Destination
}

function Assert-HpmReady {
    $stamp = Join-Path $script:PrivateRoot 'synced-lock.sha256'
    if (-not (Test-Path -LiteralPath $stamp) -or
        (Get-Content -LiteralPath $stamp -Raw).Trim() -ne (Get-HpmLockHash)) {
        throw 'Dependencies are missing or the lock changed. Run the project hpm-cmake sync.ps1.'
    }
}
