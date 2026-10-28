[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\FluidVoice Hardened')
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$publish = Join-Path $repositoryRoot '.artifacts\publish'
$model = Join-Path $repositoryRoot 'vendor\models\ggml-large-v3-turbo-q5_0.bin'
$expectedModelHash = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'
$expectedFileVersion = '1.2.0.14'
$installPath = [IO.Path]::GetFullPath($InstallDirectory)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs'))

if (-not $installPath.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Install path must remain under $allowedRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $publish 'FluidVoice Hardened.exe'))) { throw 'Published application is missing.' }
if (-not (Test-Path -LiteralPath $model)) { throw 'Approved model is missing.' }
$modelHash = (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash.ToLowerInvariant()
if ($modelHash -ne $expectedModelHash) { throw 'Approved model SHA-256 mismatch.' }
$publishedFileVersion = (Get-Item -LiteralPath (Join-Path $publish 'FluidVoice Hardened.exe')).VersionInfo.FileVersion
if ($publishedFileVersion -ne $expectedFileVersion) {
    throw "Published file version mismatch: expected $expectedFileVersion, found $publishedFileVersion."
}

$backup = $null
$newInstallCreated = $false
try {
    Get-Process -Name 'FluidVoice Hardened' -ErrorAction SilentlyContinue | Stop-Process -ErrorAction Stop

    if (Test-Path -LiteralPath $installPath) {
        $backup = "$installPath.rollback-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -LiteralPath $installPath -Destination $backup
        Write-Output "ROLLBACK_PATH=$backup"
    }

    New-Item -ItemType Directory -Force -Path $installPath | Out-Null
    $newInstallCreated = $true
    Get-ChildItem -LiteralPath $publish -Force | Copy-Item -Destination $installPath -Recurse -Force
    $models = Join-Path $installPath 'Models'
    New-Item -ItemType Directory -Force -Path $models | Out-Null
    Copy-Item -LiteralPath $model -Destination (Join-Path $models 'ggml-large-v3-turbo-q5_0.bin')

    $policy = [ordered]@{
        Product = 'FluidVoice Hardened for Windows'
        Version = '1.2.0-win11'
        SpeechRecognition = 'local-whisper-large-v3-turbo-q5_0'
        ModelRevision = '98aa99a0a9db05ae2342309f5096248665f7cba3'
        ModelSha256 = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'
        ShareAnonymousAnalytics = $false
        AutoUpdateCheckEnabled = $false
        EnableDebugLogs = $false
        SaveTranscriptionHistory = $false
        SaveAudioWithTranscriptionHistory = $false
        CommandModeShortcutEnabled = $false
        LocalAPIEnabled = $false
        AllowCloudProviders = $false
        DictationPromptOff = $true
        SecondaryDictationPromptOff = $true
        ClipboardUsed = $false
    }
    $policy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installPath 'secure-policy.json') -Encoding UTF8

    $manifest = Get-ChildItem -LiteralPath $installPath -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            Path = $_.FullName.Substring($installPath.Length + 1).Replace('\', '/')
            Bytes = $_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    [ordered]@{
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Files = @($manifest)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $installPath 'integrity-manifest.json') -Encoding UTF8

    $executable = Join-Path $installPath 'FluidVoice Hardened.exe'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    Set-ItemProperty -LiteralPath $runKey -Name 'FluidVoiceHardened' -Value ('"' + $executable + '"') -Type String

    Write-Output "INSTALL_PATH=$installPath"
    Write-Output "EXECUTABLE=$executable"
    Write-Output "START_AT_LOGIN=ENABLED"
}
catch {
    if ($newInstallCreated -and (Test-Path -LiteralPath $installPath)) {
        Remove-Item -LiteralPath $installPath -Recurse -Force
    }
    if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        Move-Item -LiteralPath $backup -Destination $installPath
        Write-Output "ROLLBACK_RESTORED=$installPath"
    }
    throw
}
