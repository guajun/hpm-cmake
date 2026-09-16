#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. "$root/scripts/paths.ps1"
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
            # Stale cached machine paths can be supplied by process environment.
            $cacheFile=Join-Path $vendorBuild 'CMakeCache.txt'
            $cacheBytes=[IO.File]::ReadAllBytes($cacheFile)
            $savedSdk=$env:HPM_SDK_BASE; $savedGcc=$env:GNURISCV_TOOLCHAIN_PATH
            try {
                $staleCache=[IO.File]::ReadAllText($cacheFile) -replace '(?m)^hpm-sdk_DIR:PATH=.*$', 'hpm-sdk_DIR:PATH=Z:/missing-sdk/cmake' -replace '(?m)^CMAKE_C_COMPILER:STRING=.*$', 'CMAKE_C_COMPILER:STRING=Z:/missing-gcc/bin/riscv32-unknown-elf-gcc.exe'
                [IO.File]::WriteAllText($cacheFile,$staleCache)
                $env:HPM_SDK_BASE=$sdk; $env:GNURISCV_TOOLCHAIN_PATH=$toolchain
                $fallback=Resolve-HpmInstallPaths -Project $app -BuildDirectory $vendorBuild -NonInteractive
                if ($fallback.SdkRoot -ne $sdk -or $fallback.ToolchainRoot -ne $toolchain) { throw 'Environment path fallback failed.' }
            } finally { [IO.File]::WriteAllBytes($cacheFile,$cacheBytes); $env:HPM_SDK_BASE=$savedSdk; $env:GNURISCV_TOOLCHAIN_PATH=$savedGcc }
            if ($case.board -eq 'hpm6e00evk') {
                # Exercise options also exposed by the vendor GUI, including a
                # linker path that must follow the SDK into the new environment.
                Invoke-Checked cmake @('-E','env',"HPM_SDK_BASE=$sdk","GNURISCV_TOOLCHAIN_PATH=$toolchain",'HPM_SDK_TOOLCHAIN_VARIANT=gcc',"PATH=$toolPaths",'--','cmake','-S',$app,'-B',$vendorBuild,"-DCUSTOM_GCC_LINKER_FILE=$sdk/soc/HPM6E00/HPM6E80/toolchains/gcc/flash_xip.ld",'-DEXTRA_C_FLAGS=-fno-common','-DHEAP_SIZE=0x5000')
            }
            # Ambiguous discovery must fail without prompting; interactive mode
            # must explicitly select a build rather than silently taking one.
            $duplicate = Join-Path $app 'another_build'
            New-Item -ItemType Directory -Path $duplicate | Out-Null
            Copy-Item -LiteralPath (Join-Path $vendorBuild 'CMakeCache.txt') -Destination $duplicate
            $script:promptCount=0
            function Read-Host { param($Prompt); $script:promptCount++; return $vendorBuild }
            $ambiguousRejected=$false
            try { Resolve-HpmInstallPaths -Project $app -NonInteractive | Out-Null } catch { $ambiguousRejected=$_.Exception.Message -match 'BuildDirectory' }
            if (-not $ambiguousRejected -or $script:promptCount -ne 0) { throw 'NonInteractive prompted or accepted an ambiguous build.' }
            $selected=Resolve-HpmInstallPaths -Project $app -Language zh
            if ($selected.BuildDirectory -ne $vendorBuild -or $script:promptCount -ne 1) { throw 'Interactive build selection failed.' }
            Remove-Item Function:\Read-Host
            Remove-Item -LiteralPath (Join-Path $duplicate 'CMakeCache.txt')
            Remove-Item -LiteralPath $duplicate
            # Exercise the real installer using a local copy of its checksummed
            # release assets; vendor dependencies use the existing download cache.
            New-Item -ItemType Directory -Path (Join-Path $app '.hpm') | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $app '.hpm/downloads') -Target (Join-Path $root '.hpm/downloads') | Out-Null
            function Invoke-WebRequest {
                param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing)
                $asset=[IO.Path]::GetFileName(([Uri]$Uri).AbsolutePath)
                if ($asset -notin @('hpm-cmake.zip','checksums.txt')) { throw "Unexpected network access during cached install: $Uri" }
                Copy-Item -LiteralPath (Join-Path $scratch "release/$asset") -Destination $OutFile
            }
            try {
                if ($case.board -eq 'hpm6e00evk') {
                    & (Join-Path $scratch 'release/install.ps1') -Project $app -Version v0.2.0 -NonInteractive
                } else {
                    & (Join-Path $scratch 'release/install.ps1') -Project $app -BuildDirectory ($case.board + '_build') -SdkRoot $sdk -ToolchainRoot $toolchain -Version v0.2.0 -Language zh -NonInteractive
                }
            } finally { Remove-Item Function:\Invoke-WebRequest }
            if (@(Get-ChildItem -LiteralPath $app -Force -Filter '.hpm-cmake-install-*').Count) { throw 'Installer staging was not cleaned.' }
            if (-not (Test-Path -LiteralPath (Join-Path $app 'activate.ps1'))) { throw 'Install did not create root activate.ps1.' }
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
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,'Z:/invalid-hpm-environment','Process') }
            & ./.hpm-cmake/sync.ps1 -Offline
            & ./.hpm-cmake/doctor.ps1
            $activationBefore=Get-EnvironmentSnapshot
            & ./activate.ps1
            if ($env:HPM_CMAKE_ACTIVE_ROOT -ne $app -or
                (Get-Command riscv32-unknown-elf-gcc.exe).Source -ne (Join-Path $app '.hpm/toolchain/bin/riscv32-unknown-elf-gcc.exe') -or
                (Get-Command python3.exe).Source -ne (Join-Path $app '.hpm/python/python3.exe')) { throw 'Activation did not select the project compiler and Python.' }
            $activePath=$env:PATH
            & ./activate.ps1
            if ($env:PATH -ne $activePath) { throw 'Repeated activation changed PATH.' }
            & ./activate.ps1 -Deactivate
            if ((Get-EnvironmentSnapshot) -ne $activationBefore) { throw 'Activation/deactivation did not restore the process environment.' }
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
Write-Host 'PASS: official generator, two boards, release installer, interactive discovery, no-prompt mode, process-only activation and isolated builds.'
