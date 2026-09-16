# Path discovery is shared by installation and its non-interactive tests.
function Get-HpmMessage {
    param([string]$Key,[string]$Language)
    $messages = Get-Content -LiteralPath "$PSScriptRoot/messages.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    return $messages.$Language.$Key
}

function Resolve-HpmInstallPaths {
    [CmdletBinding()]
    param([string]$Project='.',[string]$BuildDirectory,[string]$SdkRoot,[string]$ToolchainRoot,[string]$SdkEnvRoot,[string]$SdkRevision,[switch]$NonInteractive,[string]$Language='en')
    $projectPath = (Resolve-Path -LiteralPath $Project).Path
    if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'CMakeLists.txt'))) { throw "-Project must contain the official application's CMakeLists.txt: $projectPath" }
    function Read-HpmCache([string]$Path) {
        $result = @{}
        if (Test-Path -LiteralPath $Path) {
            foreach ($line in Get-Content -LiteralPath $Path) {
                if ($line -match '^([^/#][^:]*):[^=]+=(.*)$') { $result[$Matches[1]]=$Matches[2] }
            }
        }
        return $result
    }
    function Get-FullHpmPath([string]$Value,[string]$Base) {
        if (-not [IO.Path]::IsPathRooted($Value)) { $Value=Join-Path $Base $Value }
        return [IO.Path]::GetFullPath($Value)
    }
    function Test-HpmBuild([string]$Path) {
        $candidate=Read-HpmCache (Join-Path $Path 'CMakeCache.txt')
        return ($candidate.ContainsKey('CMAKE_HOME_DIRECTORY') -and
            [IO.Path]::GetFullPath($candidate.CMAKE_HOME_DIRECTORY) -eq [IO.Path]::GetFullPath($projectPath) -and
            $candidate.ContainsKey('BOARD') -and $candidate.ContainsKey('hpm-sdk_DIR') -and -not $candidate.ContainsKey('CMAKE_PROJECT_INCLUDE'))
    }
    if ($BuildDirectory) {
        $BuildDirectory=Get-FullHpmPath $BuildDirectory $projectPath
        if (-not (Test-HpmBuild $BuildDirectory)) { throw "-BuildDirectory is not an original HPM build for -Project: $BuildDirectory" }
    } else {
        $directories=@($projectPath)
        $children=@(Get-ChildItem -LiteralPath $projectPath -Directory -Force | Where-Object { $_.Name -notmatch '^\.' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
        foreach ($child in $children) {
            $directories += $child.FullName
            if ($child.Name -in @('build','out')) {
                $directories += @(Get-ChildItem -LiteralPath $child.FullName -Directory | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object FullName)
            }
        }
        $candidates=@($directories | Where-Object { Test-HpmBuild $_ } | Select-Object -Unique)
        if ($candidates.Count -eq 1) { $BuildDirectory=$candidates[0] }
        else {
            if ($NonInteractive) { throw "Supply -BuildDirectory. Found $($candidates.Count) matching official builds. NonInteractive never prompts. Candidates: $($candidates -join '; ')" }
            if ($candidates.Count) { for ($i=0;$i -lt $candidates.Count;$i++) { Write-Host "[$($i+1)] $($candidates[$i])" } }
            $answer=Read-Host (Get-HpmMessage 'build' $Language)
            if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $candidates.Count) { $BuildDirectory=$candidates[[int]$answer-1] }
            elseif ($answer) { $BuildDirectory=Get-FullHpmPath $answer $projectPath }
            else { throw 'A build directory is required. Supply -BuildDirectory.' }
            if (-not (Test-HpmBuild $BuildDirectory)) { throw 'Selected directory is not the official build of this application.' }
        }
    }
    $cache=Read-HpmCache (Join-Path $BuildDirectory 'CMakeCache.txt')
    $explicitEnvRoot = [bool]$SdkEnvRoot
    if ($SdkEnvRoot) {
        $SdkEnvRoot=(Resolve-Path -LiteralPath $SdkEnvRoot).Path
        if (-not (Test-Path -LiteralPath (Join-Path $SdkEnvRoot 'hpm_sdk/cmake/hpm-sdk-config.cmake'))) { throw 'SdkEnvRoot must be the official sdk_env directory containing hpm_sdk.' }
    } elseif ($env:SDK_ENV -and (Test-Path -LiteralPath ([IO.Path]::Combine($env:SDK_ENV,'hpm_sdk/cmake/hpm-sdk-config.cmake')))) { $SdkEnvRoot=(Resolve-Path -LiteralPath $env:SDK_ENV).Path }
    function Resolve-HpmDependency([string]$Explicit,[string[]]$Candidates,[string]$Marker,[string]$Parameter,[string]$Message) {
        if ($Explicit) {
            $path=(Resolve-Path -LiteralPath $Explicit).Path
            if (-not (Test-Path -LiteralPath (Join-Path $path $Marker))) { throw "Invalid -${Parameter}: expected $Marker inside $path" }
            return $path
        }
        foreach ($path in $Candidates) {
            if ($path -and (Test-Path -LiteralPath ([IO.Path]::Combine($path,$Marker)))) { return (Resolve-Path -LiteralPath $path).Path }
        }
        if ($NonInteractive) { throw "Missing -$Parameter. Pass it explicitly; NonInteractive never prompts." }
        $answer=Read-Host (Get-HpmMessage $Message $Language)
        if (-not $answer) { throw "Missing -$Parameter." }
        $path=(Resolve-Path -LiteralPath $answer).Path
        if (-not (Test-Path -LiteralPath (Join-Path $path $Marker))) { throw "Invalid -$Parameter directory." }
        return $path
    }
    $cachedSdk=if ($cache.ContainsKey('hpm-sdk_DIR')) { Split-Path -Parent $cache['hpm-sdk_DIR'] } else { $null }
    $sdkCandidates=@($(if ($explicitEnvRoot) { Join-Path $SdkEnvRoot 'hpm_sdk' }),$cachedSdk,$env:HPM_SDK_BASE,$(if ($SdkEnvRoot) { Join-Path $SdkEnvRoot 'hpm_sdk' }),'C:\HPMicro\sdk_env\hpm_sdk')
    $SdkRoot=Resolve-HpmDependency $SdkRoot $sdkCandidates 'cmake/hpm-sdk-config.cmake' 'SdkRoot' 'sdk'
    if (-not $SdkEnvRoot) {
        $parent=Split-Path -Parent $SdkRoot
        if (Test-Path -LiteralPath (Join-Path $parent 'tools/scripts/generate_project.cmd')) { $SdkEnvRoot=$parent }
    }
    $cachedToolchain=if ($cache.ContainsKey('CMAKE_C_COMPILER')) { Split-Path -Parent (Split-Path -Parent $cache.CMAKE_C_COMPILER) } else { $null }
    $gccCommand=Get-Command riscv32-unknown-elf-gcc.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gccCandidates=@($(if ($explicitEnvRoot) { Join-Path $SdkEnvRoot 'toolchains/rv32imac_zicsr_zifencei_multilib_b_ext-win' }),$cachedToolchain,$env:GNURISCV_TOOLCHAIN_PATH,$(if ($SdkEnvRoot) { Join-Path $SdkEnvRoot 'toolchains/rv32imac_zicsr_zifencei_multilib_b_ext-win' }),$(if ($gccCommand) { Split-Path -Parent (Split-Path -Parent $gccCommand.Source) }))
    $ToolchainRoot=Resolve-HpmDependency $ToolchainRoot $gccCandidates 'bin/riscv32-unknown-elf-gcc.exe' 'ToolchainRoot' 'gcc'
    if (-not (Test-Path -LiteralPath (Join-Path $SdkRoot '.git')) -and -not $SdkRevision) {
        if ($NonInteractive) { throw 'SDK archive has no Git metadata. Supply -SdkRevision (official tag or full commit). NonInteractive never prompts.' }
        $SdkRevision=Read-Host (Get-HpmMessage 'revision' $Language)
        if (-not $SdkRevision) { throw 'Missing -SdkRevision for SDK archive.' }
    }
    [PSCustomObject]@{Project=$projectPath;BuildDirectory=$BuildDirectory;SdkRoot=$SdkRoot;ToolchainRoot=$ToolchainRoot;SdkEnvRoot=$SdkEnvRoot;SdkRevision=$SdkRevision}
}
