#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][ValidateSet('import')][string]$Command,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$BuildDirectory,
    [string]$SdkRevision
)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/scripts/import.ps1" -Project $Project -BuildDirectory $BuildDirectory -SdkRevision $SdkRevision
