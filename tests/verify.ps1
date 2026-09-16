#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
function Get-EnvironmentSnapshot {
    $result = [ordered]@{}
    foreach ($scope in @('Process','User','Machine')) {
        $values = [Environment]::GetEnvironmentVariables($scope)
        $ordered = [ordered]@{}
        foreach ($key in @($values.Keys | Sort-Object)) { $ordered[$key] = $values[$key] }
        $result[$scope] = $ordered
    }
    $result | ConvertTo-Json -Depth 5 -Compress
}
$before = Get-EnvironmentSnapshot
$names = @('HPM_SDK_BASE','GNURISCV_TOOLCHAIN_PATH','HPM_SDK_TOOLCHAIN_VARIANT','PYTHONHOME','PYTHONPATH')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$scratch = Join-Path $root ('.hpm/tests/import-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$generator = Join-Path $scratch 'generate_project.cmd'
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/hpmicro/sdk_env/11078ef83504c53aa336649102c4e7d5c7671c39/tools/scripts/generate_project.cmd' -OutFile $generator
if ((Get-FileHash -LiteralPath $generator -Algorithm SHA256).Hash -ne 'ee3b50dc47df555694e2922eb32b656d59f99fde3edb073a03fc2d1450fff798') { throw 'Official generator checksum mismatch.' }
$sdk = Join-Path $root '.hpm/sdk'
$toolchain = Join-Path $root '.hpm/toolchain'
$toolPaths = @((Join-Path $root '.hpm/python'),(Split-Path (Get-Command cmake).Source),(Split-Path (Get-Command ninja).Source),(Split-Path (Get-Command git).Source),"$env:SystemRoot/System32",$env:SystemRoot) -join ';'
Push-Location $root
try {
    & ./scripts/package.ps1 -OutputDirectory (Join-Path $scratch 'release')
    Expand-Archive -LiteralPath (Join-Path $scratch 'release/hpm-cmake.zip') -DestinationPath (Join-Path $scratch 'unpacked')
    $cases = @(
        @{board='hpm6e00evk';type='flash_xip';entry=(Join-Path $root 'hpm-cmake.ps1')},
        @{board='hpm6750evkmini';type='debug';entry=(Join-Path $scratch 'unpacked/hpm-cmake/hpm-cmake.ps1')}
    )
    foreach ($case in $cases) {
        $app = Join-Path $scratch ($case.board + ' app with spaces')
        New-Item -ItemType Directory -Path $app | Out-Null
        Copy-Item -LiteralPath (Join-Path $sdk 'samples/hello_world/CMakeLists.txt') -Destination $app
        Copy-Item -LiteralPath (Join-Path $sdk 'samples/hello_world/src') -Destination $app -Recurse
        $cmakeBefore = (Get-FileHash -LiteralPath (Join-Path $app 'CMakeLists.txt')).Hash
        $sourceBefore = (Get-FileHash -LiteralPath (Join-Path $app 'src/hello_world.c')).Hash
        Push-Location $app
        try {
            # Run the vendor's unmodified CLI generator in a child environment.
            Invoke-Checked cmake @('-E','env',"HPM_SDK_BASE=$sdk","GNURISCV_TOOLCHAIN_PATH=$toolchain",'HPM_SDK_TOOLCHAIN_VARIANT=gcc',"PATH=$toolPaths",'--','cmd.exe','/d','/c',$generator,'-b',$case.board,'-t',$case.type)
            $vendorBuild = Join-Path $app ($case.board + '_build')
            if (-not (Test-Path -LiteralPath (Join-Path $vendorBuild 'build.ninja'))) { throw 'Official generation failed.' }
            if ($case.board -eq 'hpm6e00evk') {
                # Exercise options also exposed by the vendor GUI, including a
                # linker path that must follow the SDK into the new environment.
                Invoke-Checked cmake @('-E','env',"HPM_SDK_BASE=$sdk","GNURISCV_TOOLCHAIN_PATH=$toolchain",'HPM_SDK_TOOLCHAIN_VARIANT=gcc',"PATH=$toolPaths",'--','cmake','-S',$app,'-B',$vendorBuild,"-DCUSTOM_GCC_LINKER_FILE=$sdk/soc/HPM6E00/HPM6E80/toolchains/gcc/flash_xip.ld",'-DEXTRA_C_FLAGS=-fno-common','-DHEAP_SIZE=0x5000')
            }
            & $case.entry import -Project $app -BuildDirectory $vendorBuild
            $presets = Get-Content CMakePresets.json -Raw | ConvertFrom-Json
            if ($presets.configurePresets[0].cacheVariables.BOARD.value -ne $case.board -or
                $presets.configurePresets[0].cacheVariables.CMAKE_BUILD_TYPE.value -ne $case.type) { throw 'Original build selection was not preserved.' }
            if ($case.board -eq 'hpm6e00evk' -and
                ($presets.configurePresets[0].cacheVariables.CUSTOM_GCC_LINKER_FILE.value -ne '${sourceDir}/.hpm/sdk/soc/HPM6E00/HPM6E80/toolchains/gcc/flash_xip.ld' -or
                 $presets.configurePresets[0].cacheVariables.HEAP_SIZE.value -ne '0x5000' -or
                 $presets.configurePresets[0].cacheVariables.EXTRA_C_FLAGS.value -ne '-fno-common')) { throw 'Vendor custom options were lost or rebased incorrectly.' }
            if ((Get-FileHash CMakeLists.txt).Hash -ne $cmakeBefore -or
                (Get-FileHash src/hello_world.c).Hash -ne $sourceBefore) { throw 'Import modified vendor application files.' }
            $repeatRejected = $false
            try { & $case.entry import -Project $app -BuildDirectory $vendorBuild } catch { $repeatRejected = $true }
            if (-not $repeatRejected) { throw 'Repeated import must preserve the existing integration.' }
            New-Item -ItemType Directory -Path .hpm | Out-Null
            # Reuse downloaded test assets. Every application still installs its
            # own Python payload and sync stamp from its imported lock.
            foreach ($component in @('sdk','toolchain','downloads')) {
                New-Item -ItemType Junction -Path (Join-Path $app ".hpm/$component") -Target (Join-Path $root ".hpm/$component") | Out-Null
            }
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,'Z:/invalid-hpm-environment','Process') }
            & ./.hpm-cmake/sync.ps1 -Offline
            & ./.hpm-cmake/doctor.ps1
            Invoke-Checked cmake @('--preset','default')
            Invoke-Checked cmake @('--build','--preset','default','--parallel')
            foreach ($ext in @('elf','bin','map')) {
                if ((Get-Item -LiteralPath "build/hpm-default/output/demo.$ext").Length -le 0) { throw 'Empty build artifact.' }
            }
            $lockBytes = [IO.File]::ReadAllBytes((Join-Path $app 'hpm-lock.json'))
            try {
                [IO.File]::AppendAllText((Join-Path $app 'hpm-lock.json'),"`n")
                $ErrorActionPreference = 'Continue'
                $failure = & cmake --preset default 2>&1 | Out-String
                $ErrorActionPreference = 'Stop'
                if ($LASTEXITCODE -eq 0 -or $failure -notmatch 'lock changed') { throw 'Unsynchronized lock was accepted.' }
            } finally { [IO.File]::WriteAllBytes((Join-Path $app 'hpm-lock.json'),$lockBytes) }
            Invoke-Checked cmake @('--preset','default')
        } finally {
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
            Pop-Location
        }
    }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    Pop-Location
}
if ((Get-EnvironmentSnapshot) -ne $before) { throw 'Process, user, or machine environment changed.' }
Write-Host 'PASS: official generator, two boards, clone/release archive imports, unchanged application sources, isolated builds and unchanged environments.'
