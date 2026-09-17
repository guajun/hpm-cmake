#Requires -Version 5.1
[CmdletBinding()]
param([string]$Project='.',[string]$BuildDirectory,[string]$SdkRoot,[string]$ToolchainRoot,[string]$PythonExecutable,[string]$SdkEnvRoot,[switch]$NonInteractive,[ValidateSet('en','zh')][string]$Language='en')
& "$PSScriptRoot/scripts/setup.ps1" @PSBoundParameters
