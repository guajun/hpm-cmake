#Requires -Version 5.1
[CmdletBinding()]
param()
. "$PSScriptRoot/common.ps1"
Assert-HpmHost
Assert-HpmReady
$lock = Get-HpmLock
$sdk = Join-Path $script:PrivateRoot 'sdk'
$sdkHead = & git -C $sdk rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $sdkHead -ne $lock.sdk.commit) { throw 'SDK commit differs from lock.' }
$dirty = @(Get-HpmSdkChanges $sdk)
if ($dirty.Count) { throw 'SDK checkout has local changes.' }
$python = Join-Path $script:PrivateRoot 'python/python.exe'
$code = "import json,sys,importlib.metadata as m; print(json.dumps({'version':sys.version.split()[0],'isolated':sys.flags.isolated,'packages':{p:m.version(p) for p in ['PyYAML','Jinja2','MarkupSafe']}}))"
$details = & $python -c $code
if ($LASTEXITCODE -ne 0) { throw 'SDK Python failed.' }
$details = $details | ConvertFrom-Json
if ($details.version -ne $lock.python.version -or $details.isolated -ne 1) { throw 'SDK Python version or isolation differs from lock.' }
foreach ($package in $lock.python.packages) {
    if ($details.packages.($package.name) -ne $package.version) { throw "Python package mismatch: $($package.name)" }
}
$compiler = Join-Path $script:PrivateRoot 'toolchain/bin/riscv32-unknown-elf-gcc.exe'
$gccVersion = & $compiler -dumpfullversion
if ($LASTEXITCODE -ne 0 -or $gccVersion -ne $lock.toolchain.version) { throw 'Compiler version differs from lock.' }
Write-Host "SDK:    $sdkHead (clean)"
Write-Host "GCC:    $gccVersion"
Write-Host "Python: $($details.version) (isolated SDK runtime)"
Invoke-HpmNative cmake @('--version')
Invoke-HpmNative ninja @('--version')
Write-Host 'Ready. These checks do not connect to a debug probe.'
