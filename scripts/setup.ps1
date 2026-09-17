#Requires -Version 5.1
[CmdletBinding()]
param([string]$Project='.',[string]$BuildDirectory,[string]$SdkRoot,[string]$ToolchainRoot,[string]$PythonExecutable,[string]$SdkEnvRoot,[switch]$NonInteractive,[ValidateSet('en','zh')][string]$Language='en')
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$projectPath=(Resolve-Path -LiteralPath $Project).Path
$candidates=@($PythonExecutable)
if ($BuildDirectory) {
 $build=if([IO.Path]::IsPathRooted($BuildDirectory)){$BuildDirectory}else{Join-Path $projectPath $BuildDirectory}
 $cache=Join-Path $build 'CMakeCache.txt'
 if(Test-Path -LiteralPath $cache){foreach($line in Get-Content -LiteralPath $cache){if($line -match '^python_exec:[^=]+=(.*)$'){$candidates+=$Matches[1]}}}
}
$localFile=Join-Path $projectPath '.hpm/local.json'
if(Test-Path -LiteralPath $localFile){$local=Get-Content -LiteralPath $localFile -Raw -Encoding UTF8|ConvertFrom-Json;$candidates+=$local.python}
if($SdkEnvRoot){
 if(-not $SdkRoot){$SdkRoot=Join-Path $SdkEnvRoot 'hpm_sdk'}
 if(-not $ToolchainRoot){$ToolchainRoot=Join-Path $SdkEnvRoot 'toolchains/rv32imac_zicsr_zifencei_multilib_b_ext-win'}
 $candidates+=Join-Path $SdkEnvRoot 'tools/python3/python.exe'
}
foreach($name in @('python.exe','python3.exe')){$command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command -and $command.Source -notmatch 'WindowsApps'){$candidates+=$command.Source}}
$runner=$null
foreach($candidate in $candidates){
 if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){
  & $candidate -c 'import sys; assert sys.version_info >= (3, 9)' 2>$null
  if($LASTEXITCODE -eq 0){$runner=$candidate;break}
 }
 if($PythonExecutable -and $candidate -eq $PythonExecutable){throw 'Invalid -PythonExecutable. Provide an installed Python 3.9+ interpreter.'}
}
if(-not $runner){
 if($NonInteractive){throw 'Provide -PythonExecutable pointing to the existing SDK Python 3.9+. No runtimes are installed automatically.'}
 $runner=Read-Host 'SDK Python executable (-PythonExecutable)'
}
$arguments=@((Join-Path $repository 'scripts/hpm.py'),'--project',$projectPath,'--language',$Language)
foreach($pair in @(@('build-directory',$BuildDirectory),@('sdk-root',$SdkRoot),@('toolchain-root',$ToolchainRoot),@('python-executable',$PythonExecutable))){if($pair[1]){$arguments+=@("--$($pair[0])",$pair[1])}}
if($NonInteractive){$arguments+='--non-interactive'}
& $runner @arguments
if($LASTEXITCODE -ne 0){throw "HPM local setup failed ($LASTEXITCODE)."}
