[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot '..\vendor\models\ggml-large-v3-turbo-q5_0.bin')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$expectedBytes = 574041195
$expectedSha256 = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'
$revision = '98aa99a0a9db05ae2342309f5096248665f7cba3'
$source = "https://huggingface.co/ggerganov/whisper.cpp/resolve/$revision/ggml-large-v3-turbo-q5_0.bin?download=true"
$destinationPath = [IO.Path]::GetFullPath($Destination)
$destinationDirectory = Split-Path -Parent $destinationPath
$partial = "$destinationPath.partial"

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

if (Test-Path -LiteralPath $destinationPath) {
    $existing = Get-Item -LiteralPath $destinationPath
    $existingHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existing.Length -eq $expectedBytes -and $existingHash -eq $expectedSha256) {
        Write-Output "Approved model already present and verified: $destinationPath"
        exit 0
    }
    throw "An unapproved file already exists at $destinationPath. It was not overwritten."
}

if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
try {
    Invoke-WebRequest -UseBasicParsing -Uri $source -OutFile $partial
    $download = Get-Item -LiteralPath $partial
    if ($download.Length -ne $expectedBytes) {
        throw "Model size mismatch: expected $expectedBytes, received $($download.Length)."
    }
    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expectedSha256) {
        throw "Model SHA-256 mismatch: expected $expectedSha256, received $hash."
    }
    Move-Item -LiteralPath $partial -Destination $destinationPath
    Write-Output "MODEL_SHA256=PASS:$hash"
    Write-Output "MODEL_BYTES=PASS:$expectedBytes"
}
catch {
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    throw
}
