#Requires -Version 5.1
[CmdletBinding()]
param()
. "$PSScriptRoot/common.ps1"
Assert-HpmHost
Assert-HpmReady
$lock = Get-HpmLock
$sdk = Join-Path $script:PrivateRoot 'sdk'
Assert-HpmSdk $sdk $lock
$python = Join-Path $script:PrivateRoot 'python/python.exe'
Assert-HpmPython $python $lock
$compiler = Join-Path $script:PrivateRoot 'toolchain/bin/riscv32-unknown-elf-gcc.exe'
Assert-HpmCompiler $compiler $lock
Write-Host "SDK:    $($lock.sdk.commit)"
Write-Host "GCC:    $($lock.toolchain.version)"
Write-Host "Python: $($lock.python.version) (isolated SDK runtime)"
Invoke-HpmNative cmake @('--version')
Invoke-HpmNative ninja @('--version')
Write-Host 'Ready. These checks do not connect to a debug probe.'
