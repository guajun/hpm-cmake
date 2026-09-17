#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Deactivate)
$ErrorActionPreference='Stop'
$state=Get-Variable HpmFirmwareEnvironment -Scope Global -ErrorAction SilentlyContinue
if ($Deactivate) {
 if ($state) {foreach ($key in $state.Value.Keys) {[Environment]::SetEnvironmentVariable($key,$state.Value[$key],'Process')};Remove-Variable HpmFirmwareEnvironment -Scope Global}
 return
}
$local=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local.json') -Raw -Encoding UTF8|ConvertFrom-Json
$project=Split-Path -Parent $PSScriptRoot
if ((Get-FileHash -LiteralPath (Join-Path $project 'hpm-lock.json')).Hash -ne $local.lockSha256) {throw 'Lock changed. Rerun the one-line installer.'}
if (-not (Test-Path -LiteralPath $local.python) -or -not (Test-Path -LiteralPath (Join-Path $local.toolchain 'bin/riscv32-unknown-elf-gcc.exe'))) {throw 'Local tools missing. Rerun the installer.'}
$keys=@('PATH','HPM_SDK_BASE','GNURISCV_TOOLCHAIN_PATH','HPM_SDK_TOOLCHAIN_VARIANT')
if ($state) {foreach ($key in $state.Value.Keys) {[Environment]::SetEnvironmentVariable($key,$state.Value[$key],'Process')}} else {$before=@{};foreach ($key in $keys) {$before[$key]=[Environment]::GetEnvironmentVariable($key,'Process')};Set-Variable HpmFirmwareEnvironment -Scope Global -Value $before}
$env:HPM_SDK_BASE=$local.sdk
$env:GNURISCV_TOOLCHAIN_PATH=$local.toolchain
$env:HPM_SDK_TOOLCHAIN_VARIANT='gcc'
$env:PATH=((Split-Path -Parent $local.python),(Join-Path $local.toolchain 'bin'),$env:PATH)-join ';'
Write-Host "Activated firmware environment: $project"
