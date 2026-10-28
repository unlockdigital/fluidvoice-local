[CmdletBinding()]
param(
    [string]$DotnetDirectory = (Join-Path $PSScriptRoot '..\.tools\dotnet')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolsRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tools'))
$installer = Join-Path $toolsRoot 'dotnet-install.ps1'

New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $DotnetDirectory | Out-Null

if (-not (Test-Path -LiteralPath $installer)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
}

& $installer -Channel '9.0' -Quality 'GA' -InstallDir $DotnetDirectory -NoPath
$dotnet = Join-Path $DotnetDirectory 'dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet)) { throw 'The .NET SDK installer did not produce dotnet.exe.' }
& $dotnet --info
