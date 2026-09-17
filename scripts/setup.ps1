#Requires -Version 5.1
[CmdletBinding()]
param([string]$Project='.',[string]$BuildDirectory,[string]$SdkRoot,[string]$ToolchainRoot,[string]$SdkEnvRoot,[string]$SdkRevision,[switch]$NonInteractive,[ValidateSet('en','zh')][string]$Language='en')
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$projectPath=(Resolve-Path -LiteralPath $Project).Path
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'CMakeLists.txt'))) { throw 'Project must contain CMakeLists.txt.' }
$lockPath=Join-Path $projectPath 'hpm-lock.json'
$lock=Get-Content -LiteralPath $(if (Test-Path $lockPath) {$lockPath} else {Join-Path $repository 'hpm-lock.json'}) -Raw -Encoding UTF8|ConvertFrom-Json
$python=if ($lock.schema -eq 1) {$lock.python} else {$lock.platforms.'windows-x86_64'.python}
$private=Join-Path $projectPath '.hpm'
$runtime=Join-Path $private 'python'
$executable=Join-Path $runtime 'python.exe'
if (-not (Test-Path -LiteralPath $executable)) {
 $downloads=Join-Path $private 'downloads'
 New-Item -ItemType Directory -Path $downloads -Force|Out-Null
 $archive=Join-Path $downloads ($python.sha256.Substring(0,12)+'-'+[IO.Path]::GetFileName(([Uri]$python.url).AbsolutePath))
 if (-not (Test-Path -LiteralPath $archive)) { Invoke-WebRequest -UseBasicParsing $python.url -OutFile $archive }
 if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $python.sha256) {throw 'Python archive checksum mismatch.'}
 Expand-Archive -LiteralPath $archive -DestinationPath $runtime
}
$version=& $executable -I -c 'import platform; print(platform.python_version())'
if ($LASTEXITCODE -ne 0 -or $version -ne $python.version) {throw 'Private Python runtime differs from lock.'}
if ($SdkEnvRoot) {
 if (-not $SdkRoot) {$SdkRoot=Join-Path $SdkEnvRoot 'hpm_sdk'}
 if (-not $ToolchainRoot) {$ToolchainRoot=Join-Path $SdkEnvRoot 'toolchains/rv32imac_zicsr_zifencei_multilib_b_ext-win'}
}
$arguments=@('-I',(Join-Path $repository 'scripts/hpm.py'),'--project',$projectPath,'--language',$Language)
foreach ($pair in @(@('build-directory',$BuildDirectory),@('sdk-root',$SdkRoot),@('toolchain-root',$ToolchainRoot),@('sdk-revision',$SdkRevision))) {if ($pair[1]) {$arguments+=@("--$($pair[0])",$pair[1])}}
if ($NonInteractive) {$arguments+='--non-interactive'}
& $executable @arguments
if ($LASTEXITCODE -ne 0) {throw "HPM environment setup failed ($LASTEXITCODE)."}
