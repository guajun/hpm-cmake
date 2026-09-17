#Requires -Version 5.1
[CmdletBinding()]
param([string]$Project='.',[string]$SdkRoot,[string]$ToolchainRoot,[string]$PythonExecutable,[string]$SdkEnvRoot,[switch]$NonInteractive,[ValidateSet('en','zh')][string]$Language='en')
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$projectPath=(Resolve-Path -LiteralPath $Project).Path
$candidates=@($PythonExecutable)
$settings=Join-Path $projectPath '.hpm-venv/settings.json'
if(Test-Path -LiteralPath $settings){$local=Get-Content -LiteralPath $settings -Raw -Encoding UTF8|ConvertFrom-Json;$candidates+=$local.python}
if($SdkEnvRoot){$candidates+=Join-Path $SdkEnvRoot 'tools/python3/python.exe'}
$candidates+=$env:HPM_PYTHON
foreach($name in @('python.exe','python3.exe')){$command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command -and $command.Source -notmatch 'WindowsApps'){$candidates+=$command.Source}}
$runner=$null
foreach($candidate in $candidates){if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){$runner=$candidate;break}}
if(-not $runner){if($NonInteractive){throw 'Provide -PythonExecutable for an existing Python 3.9+. No interpreter is installed automatically.'};$runner=Read-Host 'Python executable (-PythonExecutable)'}
& $runner -c 'import sys; assert sys.version_info >= (3, 9)'
if($LASTEXITCODE -ne 0){throw 'An existing Python 3.9+ is required to generate activation scripts.'}
$arguments=@((Join-Path $repository 'scripts/hpm.py'),'--project',$projectPath,'--language',$Language)
foreach($pair in @(@('sdk-root',$SdkRoot),@('toolchain-root',$ToolchainRoot),@('python-executable',$PythonExecutable),@('sdk-env-root',$SdkEnvRoot))){if($pair[1]){$arguments+=@("--$($pair[0])",$pair[1])}}
if($NonInteractive){$arguments+='--non-interactive'}
& $runner @arguments
if($LASTEXITCODE -ne 0){throw "hpm-venv setup failed ($LASTEXITCODE)."}
