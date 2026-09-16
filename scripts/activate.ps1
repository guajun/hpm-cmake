#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Deactivate)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$stateVariable = Get-Variable -Name HpmCmakeActivation -Scope Global -ErrorAction SilentlyContinue
if ($Deactivate) {
    if ($stateVariable) {
        foreach ($name in $stateVariable.Value.Keys) {
            [Environment]::SetEnvironmentVariable($name, $stateVariable.Value[$name], 'Process')
        }
        Remove-Variable -Name HpmCmakeActivation -Scope Global
        Write-Host 'HPM environment deactivated; previous terminal environment restored.'
    }
    return
}
# Validate before touching the caller's terminal.
. "$PSScriptRoot/common.ps1"
Assert-HpmReady
$sdk = Join-Path $project '.hpm/sdk'
$gcc = Join-Path $project '.hpm/toolchain/bin'
$python = Join-Path $project '.hpm/python'
foreach ($file in @((Join-Path $sdk 'cmake/hpm-sdk-config.cmake'),(Join-Path $gcc 'riscv32-unknown-elf-gcc.exe'),(Join-Path $python 'python.exe'))) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing dependency: $file. Run ./.hpm-cmake/sync.ps1." }
}
$lock = Get-HpmLock
Assert-HpmSdk $sdk $lock
Assert-HpmCompiler (Join-Path $gcc 'riscv32-unknown-elf-gcc.exe') $lock
Assert-HpmPython (Join-Path $python 'python.exe') $lock
$localFile = Join-Path $project '.hpm/local.json'
$paths = @($python, $gcc)
if (Test-Path -LiteralPath $localFile) {
    $local = Get-Content -LiteralPath $localFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($local.PSObject.Properties.Name -contains 'sdkEnvRoot' -and $local.sdkEnvRoot) {
        $generator = Join-Path $local.sdkEnvRoot 'tools/scripts'
        if (Test-Path -LiteralPath (Join-Path $generator 'generate_project.cmd')) { $paths += $generator }
        $openocd = Join-Path $local.sdkEnvRoot 'tools/openocd/bin'
        if (Test-Path -LiteralPath (Join-Path $openocd 'openocd.exe')) { $paths += $openocd }
    }
}
$names = @('PATH','HPM_SDK_BASE','GNURISCV_TOOLCHAIN_PATH','HPM_SDK_TOOLCHAIN_VARIANT','OPENOCD_SCRIPTS','HPM_CMAKE_ACTIVE_ROOT')
if ($stateVariable) {
    foreach ($name in $stateVariable.Value.Keys) { [Environment]::SetEnvironmentVariable($name,$stateVariable.Value[$name],'Process') }
} else {
    $snapshot = @{}
    foreach ($name in $names) { $snapshot[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
    Set-Variable -Name HpmCmakeActivation -Scope Global -Value $snapshot
}
$remaining = @($env:PATH -split ';' | Where-Object { $_ -and $paths -notcontains $_ })
$env:PATH = ($paths + $remaining) -join ';'
$env:HPM_SDK_BASE = $sdk
$env:GNURISCV_TOOLCHAIN_PATH = Split-Path -Parent $gcc
$env:HPM_SDK_TOOLCHAIN_VARIANT = 'gcc'
$env:OPENOCD_SCRIPTS = Join-Path $sdk 'boards/openocd'
$env:HPM_CMAKE_ACTIVE_ROOT = $project
Write-Host "Activated HPM project: $project"
Write-Host 'Current terminal only. Build: cmake --preset default; cmake --build --preset default'
Write-Host 'Restore this terminal: ./activate.ps1 -Deactivate'
