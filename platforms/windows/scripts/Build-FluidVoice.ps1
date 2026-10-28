[CmdletBinding()]
param(
    [switch]$NoRestore
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dotnet = Join-Path $repositoryRoot '.tools\dotnet\dotnet.exe'
$project = Join-Path $repositoryRoot 'src\FluidVoice.App\FluidVoice.App.csproj'
$verifyProject = Join-Path $repositoryRoot 'src\FluidVoice.Verify\FluidVoice.Verify.csproj'
$publish = Join-Path $repositoryRoot '.artifacts\publish'
$verifyPublish = Join-Path $repositoryRoot '.artifacts\verify'
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.artifacts'))

if (-not (Test-Path -LiteralPath $dotnet)) { throw 'Local .NET SDK is missing. Run Get-BuildDependencies.ps1 first.' }
foreach ($outputPath in @($publish, $verifyPublish)) {
    $resolvedOutput = [IO.Path]::GetFullPath($outputPath)
    if (-not $resolvedOutput.StartsWith($artifactsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe build output path: $resolvedOutput"
    }
    if (Test-Path -LiteralPath $resolvedOutput) {
        Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
    }
}

if (-not $NoRestore) {
    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $project) 'packages.lock.json')) {
        & $dotnet restore $project --locked-mode
    } else {
        & $dotnet restore $project --use-lock-file
    }
    if ($LASTEXITCODE -ne 0) { throw 'Package restore failed.' }
}
& $dotnet publish $project -c Release --no-restore -o $publish
if ($LASTEXITCODE -ne 0) { throw 'Application publish failed.' }

if (-not $NoRestore) {
    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $verifyProject) 'packages.lock.json')) {
        & $dotnet restore $verifyProject --locked-mode
    } else {
        & $dotnet restore $verifyProject --use-lock-file
    }
    if ($LASTEXITCODE -ne 0) { throw 'Verifier restore failed.' }
}
& $dotnet publish $verifyProject -c Release --no-restore -o $verifyPublish
if ($LASTEXITCODE -ne 0) { throw 'Verifier publish failed.' }

Write-Output "APP_PUBLISH=$publish"
Write-Output "VERIFY_PUBLISH=$verifyPublish"
