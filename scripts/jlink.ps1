#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('ram', 'flash')][string]$Mode,
    [Parameter(Mandatory)][ValidatePattern('^\d+$')][string]$Serial,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$Device = 'HPM6E80XVMX',
    [ValidateRange(1, 50000)][int]$Speed = 4000,
    [string]$JLinkPath = 'C:\Program Files\SEGGER\JLink\JLink.exe',
    [switch]$DryRun
)
. "$PSScriptRoot/common.ps1"
Assert-HpmReady
if (-not (Test-Path -LiteralPath $JLinkPath -PathType Leaf)) { throw "J-Link Commander not found: $JLinkPath" }
$preset = if ($Mode -eq 'ram') { 'debug' } else { 'flash-debug' }
$image = Join-Path $script:ProjectRoot "build/$preset/output/demo.elf"
if (-not (Test-Path -LiteralPath $image)) { throw "Build first: cmake --preset $preset; cmake --build --preset $preset" }
$readelf = Join-Path $script:PrivateRoot 'toolchain/bin/riscv32-unknown-elf-readelf.exe'
$header = & $readelf -h $image
if ($LASTEXITCODE -ne 0) { throw 'Cannot read ELF header.' }
$entry = [regex]::Match(($header -join "`n"), 'Entry point address:\s+(0x[0-9a-fA-F]+)')
if (-not $entry.Success) { throw 'ELF entry point was not found.' }
$commands = @('ExitOnError 1', "Device $Device", 'SelectInterface JTAG', "Speed $Speed", 'JTAGConf -1,-1', 'connect', 'r', 'h', ('loadfile "' + ($image -replace '\\','/') + '"'))
if ($Mode -eq 'ram') { $commands += 'SetPC ' + $entry.Groups[1].Value } else { $commands += 'r' }
$commands += @('g', 'q')
$logDirectory = Join-Path $script:PrivateRoot 'sessions'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$sessionName = $Mode + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$commandFile = Join-Path $logDirectory ($sessionName + '.jlink')
$logFile = Join-Path $logDirectory ($sessionName + '.log')
Set-Content -LiteralPath $commandFile -Value $commands -Encoding ASCII
$jlinkArgs = @('-NoGui', '1', '-ExitOnError', '1', '-SelectEmuBySN', $Serial, '-CommanderScript', $commandFile)
Write-Host ($commands -join "`n")
Write-Host "J-Link: $JLinkPath"
Write-Host "Probe: $Serial; script: $commandFile"
if ($DryRun) { Write-Host 'Dry run: no probe or target was accessed.'; return }
& $JLinkPath @jlinkArgs 2>&1 | Tee-Object -FilePath $logFile
if ($LASTEXITCODE -ne 0) { throw "J-Link failed with code $LASTEXITCODE. See $logFile" }
Write-Host "J-Link session completed. Log: $logFile"
