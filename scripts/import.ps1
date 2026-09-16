#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$SdkRevision
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
$repository = Split-Path -Parent $PSScriptRoot
$destination = (Resolve-Path -LiteralPath $Project).Path
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$cachePath = Join-Path $build 'CMakeCache.txt'
$sourceFile = Join-Path $destination 'CMakeLists.txt'
if (-not (Test-Path -LiteralPath $sourceFile) -or -not (Test-Path -LiteralPath $cachePath)) {
    throw 'Generate the application with the official HPM tools first; provide its source and build directories.'
}
$cache = @{}
foreach ($line in Get-Content -LiteralPath $cachePath) {
    if ($line -match '^([^/#][^:]*):([^=]+)=(.*)$') {
        $cache[$Matches[1]] = @{ type = $Matches[2]; value = $Matches[3] }
    }
}
function Read-Cache([string]$Name) {
    if (-not $cache.ContainsKey($Name)) { throw "Official build cache does not contain $Name" }
    return $cache[$Name].value
}
if ([IO.Path]::GetFullPath((Read-Cache 'CMAKE_HOME_DIRECTORY')) -ne [IO.Path]::GetFullPath($destination)) {
    throw 'The selected build directory belongs to a different application.'
}
foreach ($name in @('CMakePresets.json', 'hpm-lock.json', '.hpm-cmake')) {
    if (Test-Path -LiteralPath (Join-Path $destination $name)) {
        throw "Existing $name is preserved. Review or move the previous integration before importing again."
    }
}
foreach ($name in @('CMAKE_PROJECT_INCLUDE', 'CMAKE_PROJECT_INCLUDE_BEFORE', 'CMAKE_PROJECT_TOP_LEVEL_INCLUDES', 'CMAKE_TOOLCHAIN_FILE')) {
    if ($cache.ContainsKey($name) -and $cache[$name].value) {
        throw "The original project uses $name. Automatic hook composition is not supported; preserve and integrate it explicitly."
    }
}
$board = Read-Cache 'BOARD'
if ($board -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid BOARD in original cache.' }
$sdk = Split-Path -Parent (Read-Cache 'hpm-sdk_DIR')
if (-not (Test-Path -LiteralPath (Join-Path $sdk 'cmake/hpm-sdk-config.cmake'))) { throw 'Original SDK cannot be located from the build cache.' }
$lock = Get-Content -LiteralPath (Join-Path $repository 'hpm-lock.json') -Raw | ConvertFrom-Json
if (Test-Path -LiteralPath (Join-Path $sdk '.git')) {
    $sdkCommit = & git -C $sdk rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read SDK commit.' }
    $dirty = @(Get-HpmSdkChanges $sdk)
    if ($dirty.Count) { throw 'SDK has local changes. Keep a clean SDK and put board/application changes in your own project.' }
    if ($SdkRevision) { throw 'SdkRevision is only needed for SDK archives without Git metadata.' }
} else {
    if (-not $SdkRevision) { throw 'SDK archive has no Git metadata. Supply -SdkRevision with its official release tag or full commit.' }
    if ($SdkRevision -match '^[0-9a-fA-F]{40}$') { $sdkCommit = $SdkRevision.ToLowerInvariant() }
    elseif ($SdkRevision -match '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        $refs = @(& git ls-remote $lock.sdk.url "refs/tags/$SdkRevision" "refs/tags/$SdkRevision^{}")
        if ($LASTEXITCODE -ne 0 -or -not $refs.Count) { throw "Official SDK tag not found: $SdkRevision" }
        $selected = @($refs | Where-Object { $_ -match '\^\{\}$' })
        if (-not $selected.Count) { $selected = $refs }
        $sdkCommit = ($selected[0] -split '\s+')[0]
    } else { throw 'SdkRevision must be an official tag or a full commit.' }
}
$requirements = @(Get-Content -LiteralPath (Join-Path $sdk 'scripts/requirements.txt') |
    ForEach-Object { ($_ -split '#')[0].Trim().ToLowerInvariant() } | Where-Object { $_ })
if (($requirements | Sort-Object) -join ',' -ne 'jinja2,pyyaml') {
    throw 'This SDK has different Python requirements. Update and validate the dependency profile before import.'
}
$compiler = Read-Cache 'CMAKE_C_COMPILER'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The original compiler is missing.' }
$version = & $compiler -dumpfullversion
if ($LASTEXITCODE -ne 0 -or $version -ne $lock.toolchain.version) {
    throw "Original compiler is not the supported HPM GCC $($lock.toolchain.version). Import must not change compiler versions silently."
}
# Validate the actual compiler, not merely its banner (other RISC-V distributions
# can carry the same version while using different patches or multilibs).
if ((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ne 'ae5c103862ed011d63c4db6108b3411536745c4e774946256daada5dea9fb7b2') {
    throw 'Original compiler differs from the locked official HPM GCC package.'
}
$toolchainRoot = Split-Path -Parent (Split-Path -Parent $compiler)
function Rebase-Value([string]$Value) {
    $value = $Value -replace '\\', '/'
    $sdkPrefix = ($sdk -replace '\\','/').TrimEnd('/')
    $gccPrefix = ($toolchainRoot -replace '\\','/').TrimEnd('/')
    foreach ($mapping in @(@($sdkPrefix, '${sourceDir}/.hpm/sdk'), @($gccPrefix, '${sourceDir}/.hpm/toolchain'))) {
        $value = [regex]::Replace($value, [regex]::Escape($mapping[0]) + '(?=/|$|;)', $mapping[1].Replace('$','$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if ($value -match '^[A-Za-z]:/') {
        $baseUri = [Uri](($destination -replace '\\','/').TrimEnd('/') + '/')
        $relative = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]$value).ToString())
        if ($relative -match '^[A-Za-z]:') { throw 'Custom board/linker paths on another drive cannot be made portable. Keep them with the application.' }
        $value = '${sourceDir}/' + $relative
    }
    return $value
}
$variables = [ordered]@{}
foreach ($key in @($cache.Keys | Sort-Object)) {
    $entry = $cache[$key]
    if ($entry.type -in @('INTERNAL','STATIC')) { continue }
    $selected = $key -match '^(BOARD|BOARD_SEARCH_PATH|HPM_BUILD_TYPE|CMAKE_BUILD_TYPE|HEAP_SIZE|STACK_SIZE|BUILD_FOR_SECONDARY_CORE|USE_LINKER_TEMPLATE)$' -or
        $key -match '^(CONFIG_|CUSTOM_|EXTRA_|HPM_SDK_LD_|CMAKE_(C|CXX|ASM|EXE_LINKER|STATIC_LINKER)_FLAGS)' -or
        ($entry.type -eq 'UNINITIALIZED' -and $key -notmatch '^(CMAKE_|python|Python|USE_CCACHE|GNURISCV_|HPM_SDK_|OPENOCD)')
    if (-not $selected) { continue }
    $kind = if ($entry.type -eq 'UNINITIALIZED') { 'STRING' } else { $entry.type }
    $variables[$key] = @{ type = $kind; value = Rebase-Value $entry.value }
}
$variables['USE_CCACHE'] = '0'
$variables['CMAKE_EXPORT_COMPILE_COMMANDS'] = $true
$variables['python_exec'] = @{type='FILEPATH';value='${sourceDir}/.hpm/python/python.exe'}
$variables['CMAKE_PROJECT_INCLUDE'] = '${sourceDir}/.hpm-cmake/cmake/hpm-project-hook.cmake'
$presets = [ordered]@{
    version = 5
    cmakeMinimumRequired = @{major=3;minor=24;patch=0}
    configurePresets = @(@{
        name='default';displayName="Imported HPM build ($board)";generator='Ninja'
        binaryDir='${sourceDir}/build/hpm-default'
        environment=@{HPM_SDK_BASE='${sourceDir}/.hpm/sdk';GNURISCV_TOOLCHAIN_PATH='${sourceDir}/.hpm/toolchain';HPM_SDK_TOOLCHAIN_VARIANT='gcc'}
        cacheVariables=$variables
    })
    buildPresets = @(@{name='default';configurePreset='default';inheritConfigureEnvironment=$true})
}
$lock.sdk.commit = $sdkCommit
$lock.sdk.description = 'SDK revision selected by the imported official build'
$metadata = [ordered]@{
    wrapperVersion=(Get-Content -LiteralPath (Join-Path $repository 'VERSION') -Raw).Trim()
    board=$board
    sdkCommit=$sdkCommit
    sdkRevisionSource=$(if ($SdkRevision) { 'explicit archive revision; original archive content not verified' } else { 'clean Git checkout' })
    originalCacheSha256=(Get-FileHash -LiteralPath $cachePath -Algorithm SHA256).Hash.ToLowerInvariant()
    originalCMakeSha256=(Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()
    importedVariables=$variables
}
$utf8 = New-Object Text.UTF8Encoding($false)
$payload = Join-Path $destination '.hpm-cmake'
New-Item -ItemType Directory -Path (Join-Path $payload 'cmake') -Force | Out-Null
foreach ($name in @('common.ps1','sync.ps1','doctor.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $payload
}
foreach ($name in @('hpm-project-hook.cmake','hpm-sdk-compat.cmake')) {
    Copy-Item -LiteralPath (Join-Path $repository "cmake/$name") -Destination (Join-Path $payload 'cmake')
}
Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $payload 'LICENSE')
[IO.File]::WriteAllText((Join-Path $payload 'import.json'), ($metadata | ConvertTo-Json -Depth 12) + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $destination 'hpm-lock.json'), ($lock | ConvertTo-Json -Depth 12) + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $destination 'CMakePresets.json'), ($presets | ConvertTo-Json -Depth 12) + "`n", $utf8)
$ignorePath = Join-Path $destination '.gitignore'
$ignore = if (Test-Path -LiteralPath $ignorePath) { [IO.File]::ReadAllText($ignorePath) } else { '' }
$addition = @('/.hpm/', '/build/hpm-*/', '/.hpm-cmake-install-*/', '/CMakeUserPresets.json') | Where-Object { ($ignore -split '\r?\n') -notcontains $_ }
if ($addition) { [IO.File]::AppendAllText($ignorePath, "`n# hpm-cmake local dependencies and build output`n" + ($addition -join "`n") + "`n", $utf8) }
Write-Host "Imported official build for $board. Application CMake, source, and BSP files were preserved."
Write-Host 'Next: ./.hpm-cmake/sync.ps1; cmake --preset default; cmake --build --preset default'
