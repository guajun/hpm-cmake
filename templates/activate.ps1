#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Deactivate)
& "$PSScriptRoot/.hpm-cmake/activate.ps1" -Deactivate:$Deactivate
