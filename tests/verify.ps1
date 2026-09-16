#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-EnvironmentSnapshot {
    $result = [ordered]@{}
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $values = [Environment]::GetEnvironmentVariables($scope)
        $ordered = [ordered]@{}
        foreach ($key in @($values.Keys | Sort-Object)) { $ordered[$key] = $values[$key] }
        $result[$scope] = $ordered
    }
    return ($result | ConvertTo-Json -Depth 5 -Compress)
}

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}

$before = Get-EnvironmentSnapshot
$saved = @{}
$names = @('HPM_SDK_BASE', 'GNURISCV_TOOLCHAIN_PATH', 'HPM_SDK_TOOLCHAIN_VARIANT', 'PYTHONHOME', 'PYTHONPATH')
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
Push-Location $root
try {
    # A stale environment must not select a different SDK, compiler, or Python.
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, 'Z:/invalid-hpm-environment', 'Process') }
    & ./scripts/sync.ps1 -Offline
    & ./scripts/doctor.ps1
    foreach ($preset in @('debug', 'release', 'flash-debug')) {
        Invoke-Checked cmake @('--preset', $preset, '--fresh')
        Invoke-Checked cmake @('--build', '--preset', $preset, '--parallel')
        foreach ($suffix in @('elf', 'bin', 'map')) {
            $artifact = Join-Path $root "build/$preset/output/demo.$suffix"
            if (-not (Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).Length -eq 0) {
                throw "Missing build artifact: $artifact"
            }
        }
    }
    $scratch = Join-Path $root ('.hpm/tests/' + [Guid]::NewGuid().ToString('N') + ' spaced project')
    & ./hpm-cmake.ps1 init -Project $scratch
    Push-Location $scratch
    try {
        $ErrorActionPreference = 'Continue'
        $missing = & cmake --preset debug 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0 -or $missing -notmatch 'sync.ps1') { throw 'An unprepared project must fail with setup guidance.' }
    } finally { Pop-Location }
    $marker = Join-Path $scratch 'keep-user-file.txt'
    Set-Content -LiteralPath $marker -Value 'keep' -Encoding ASCII
    $rejected = $false
    try { & ./hpm-cmake.ps1 init -Project $scratch } catch { $rejected = $true }
    if (-not $rejected -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'keep') {
        throw 'Initializer must preserve nonempty destinations.'
    }
    # A changed lock must fail before SDK configuration and without fetching.
    $lockPath = Join-Path $root 'hpm-lock.json'
    $originalLock = [IO.File]::ReadAllBytes($lockPath)
    try {
        [IO.File]::AppendAllText($lockPath, "`n")
        $ErrorActionPreference = 'Continue'
        $stale = & cmake --preset debug 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0 -or $stale -notmatch 'lock changed') { throw 'CMake accepted an unsynchronized lock.' }
    } finally { [IO.File]::WriteAllBytes($lockPath, $originalLock) }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    Pop-Location
}
if ((Get-EnvironmentSnapshot) -ne $before) { throw 'Process, user, or machine environment changed.' }
Write-Host 'PASS: three native builds, stale environment isolation, missing/stale dependency rejection, safe initialization, unchanged environments.'
