#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Offline)

. "$PSScriptRoot/common.ps1"
Assert-HpmHost
$lock = Get-HpmLock
New-Item -ItemType Directory -Path $script:PrivateRoot -Force | Out-Null
$stamp = Join-Path $script:PrivateRoot 'synced-lock.sha256'
if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp }

$sdk = Join-Path $script:PrivateRoot 'sdk'
if (-not (Test-Path -LiteralPath $sdk)) {
    if ($Offline) { throw 'SDK checkout is missing; initial setup needs network access.' }
    $stage = New-HpmStage
    $checkout = Join-Path $stage 'sdk'
    Invoke-HpmNative git @('init', '-q', $checkout)
    Invoke-HpmNative git @('-C', $checkout, 'config', '--local', 'core.longpaths', 'true')
    Invoke-HpmNative git @('-C', $checkout, 'config', '--local', 'core.autocrlf', 'false')
    Invoke-HpmNative git @('-C', $checkout, 'remote', 'add', 'origin', $lock.sdk.url)
    Invoke-HpmNative git @('-C', $checkout, 'fetch', '--depth', '1', 'origin', $lock.sdk.commit)
    Invoke-HpmNative git @('-C', $checkout, 'checkout', '--detach', $lock.sdk.commit)
    Move-HpmInstall $checkout $sdk
}
Assert-HpmSdk $sdk $lock

$toolchain = Join-Path $script:PrivateRoot 'toolchain'
if (-not (Test-Path -LiteralPath $toolchain)) {
    $archive = Get-HpmArtifact $lock.toolchain -Offline:$Offline
    $stage = New-HpmStage
    Expand-HpmArchive $archive $stage
    $payload = Join-Path $stage $lock.toolchain.archiveRoot
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'bin/riscv32-unknown-elf-gcc.exe'))) {
        throw 'Compiler archive layout differs from the lock.'
    }
    Set-Content -LiteralPath (Join-Path $payload '.hpm-artifact.sha256') -Value $lock.toolchain.sha256 -Encoding ASCII
    Move-HpmInstall $payload $toolchain
}
$compilerStamp = Join-Path $toolchain '.hpm-artifact.sha256'
$binding = Get-HpmLocalBinding
if (-not $binding -and (-not (Test-Path -LiteralPath $compilerStamp) -or
    (Get-Content -LiteralPath $compilerStamp -Raw).Trim() -ne $lock.toolchain.sha256)) {
    throw 'Existing compiler does not match the lock. Move .hpm/toolchain aside, then sync again.'
}
Assert-HpmCompiler (Join-Path $toolchain 'bin/riscv32-unknown-elf-gcc.exe') $lock

$python = Join-Path $script:PrivateRoot 'python'
if (-not (Test-Path -LiteralPath $python)) {
    $archive = Get-HpmArtifact $lock.python -Offline:$Offline
    $stage = New-HpmStage
    $payload = Join-Path $stage 'python'
    Expand-HpmArchive $archive $payload
    $sitePackages = Join-Path $payload 'Lib/site-packages'
    New-Item -ItemType Directory -Path $sitePackages -Force | Out-Null
    foreach ($package in $lock.python.packages) {
        $wheel = Get-HpmArtifact $package -Offline:$Offline
        Expand-HpmArchive $wheel $sitePackages
    }
    # The pinned wheels need no installation hooks or .data relocation. Keep the
    # embeddable runtime isolated: no site import, user packages, or PYTHONPATH.
    $paths = @($lock.python.stdlib, '.', 'Lib/site-packages')
    Set-Content -LiteralPath (Join-Path $payload $lock.python.pth) -Value $paths -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $payload '.hpm-python.sha256') -Value (Get-HpmPythonHash) -Encoding ASCII
    Move-HpmInstall $payload $python
}
$pythonStamp = Join-Path $python '.hpm-python.sha256'
if ((Test-Path -LiteralPath $pythonStamp) -and
    (Get-Content -LiteralPath $pythonStamp -Raw).Trim() -ne (Get-HpmPythonHash)) {
    throw 'Existing Python environment does not match the lock. Move .hpm/python aside, then sync again.'
}
Assert-HpmPython (Join-Path $python 'python.exe') $lock
# The official generator searches for python3 before python. Provide both names
# so an activated terminal cannot fall through to a Windows Store alias.
if (-not (Test-Path -LiteralPath (Join-Path $python 'python3.exe'))) {
    Copy-Item -LiteralPath (Join-Path $python 'python.exe') -Destination (Join-Path $python 'python3.exe')
}
Assert-HpmPython (Join-Path $python 'python3.exe') $lock
Set-Content -LiteralPath $pythonStamp -Value (Get-HpmPythonHash) -Encoding ASCII
Invoke-HpmNative (Join-Path $python 'python.exe') @('-c', "import sys, yaml, jinja2, markupsafe; print('SDK Python:', sys.version.split()[0]); assert sys.flags.isolated")
Invoke-HpmNative (Join-Path $toolchain 'bin/riscv32-unknown-elf-gcc.exe') @('-dumpfullversion')
Set-Content -LiteralPath $stamp -Value (Get-HpmLockHash) -Encoding ASCII
Write-Host 'Project dependencies are ready. Use the imported CMake preset: default.'
