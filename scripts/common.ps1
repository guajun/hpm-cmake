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

function Get-HpmLocalBinding {
    $file = Join-Path $script:PrivateRoot 'local.json'
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return $null
}

function Assert-HpmSdk {
    param([string]$Sdk, $Lock)
    if (Test-Path -LiteralPath (Join-Path $Sdk '.git')) {
        $head = & git -C $Sdk rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $head -ne $Lock.sdk.commit) { throw 'SDK commit differs from hpm-lock.json.' }
        if (@(Get-HpmSdkChanges $Sdk).Count) { throw 'SDK has source changes. Preserve them before synchronizing.' }
    } else {
        $binding = Get-HpmLocalBinding
        if (-not $binding -or $binding.sdkSourceKind -ne 'archive' -or $binding.sdkCommit -ne $Lock.sdk.commit) {
            throw 'SDK without Git metadata needs an explicit archive revision recorded by the installer.'
        }
        if ((Get-FileHash -LiteralPath (Join-Path $Sdk 'VERSION')).Hash -ne $binding.sdkVersionSha256) {
            throw 'Bound SDK VERSION changed; review the dependency lock and reinstall the binding.'
        }
    }
}

function Assert-HpmCompiler {
    param([string]$Compiler, $Lock)
    $version = & $Compiler -dumpfullversion
    if ($LASTEXITCODE -ne 0 -or $version -ne $Lock.toolchain.version) { throw 'Compiler version differs from lock.' }
    if ($Lock.toolchain.PSObject.Properties.Name -contains 'executableSha256' -and
        (Get-FileHash -LiteralPath $Compiler -Algorithm SHA256).Hash -ne $Lock.toolchain.executableSha256) {
        throw 'Compiler executable differs from the official locked HPM package.'
    }
}

function Assert-HpmPython {
    param([string]$Python, $Lock)
    $code = "import json,sys,importlib.metadata as m; print(json.dumps({'version':sys.version.split()[0],'isolated':sys.flags.isolated,'packages':{p:m.version(p) for p in ['PyYAML','Jinja2','MarkupSafe']}}))"
    $details = & $Python -c $code
    if ($LASTEXITCODE -ne 0) { throw 'SDK Python failed.' }
    $details = $details | ConvertFrom-Json
    if ($details.version -ne $Lock.python.version -or $details.isolated -ne 1) { throw 'SDK Python version or isolation differs from lock.' }
    foreach ($package in $Lock.python.packages) {
        if ($details.packages.($package.name) -ne $package.version) { throw "Python package mismatch: $($package.name)" }
    }
}

function Get-HpmPythonHash {
    $bytes = [Text.Encoding]::UTF8.GetBytes(((Get-HpmLock).python | ConvertTo-Json -Depth 10 -Compress))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
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
