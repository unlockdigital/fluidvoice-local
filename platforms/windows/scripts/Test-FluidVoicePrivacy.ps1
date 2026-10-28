[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\FluidVoice Local')
)

$ErrorActionPreference = 'Stop'
$installPath = [IO.Path]::GetFullPath($InstallDirectory)
$executable = Join-Path $installPath 'FluidVoice Local.exe'
$model = Join-Path $installPath 'Models\ggml-large-v3-turbo-q5_0.bin'
$policyFile = Join-Path $installPath 'secure-policy.json'
$manifestFile = Join-Path $installPath 'integrity-manifest.json'
$expectedModelHash = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'
$expectedProductVersion = '1.2.0-win11'
$expectedFileVersion = '1.2.0.14'
$publishPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\.artifacts\publish'))
$publishedExecutable = Join-Path $publishPath 'FluidVoice Local.exe'
$failures = [Collections.Generic.List[string]]::new()

foreach ($required in @($executable, $model, $policyFile, $manifestFile)) {
    if (-not (Test-Path -LiteralPath $required)) { $failures.Add("Missing: $required") }
}
if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }

$modelHash = (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash.ToLowerInvariant()
if ($modelHash -ne $expectedModelHash) { $failures.Add('Installed model SHA-256 mismatch.') }

$integrity = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
$manifestPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $integrity.Files) {
    $relative = ([string]$entry.Path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    [void]$manifestPaths.Add($relative)
    $candidate = [IO.Path]::GetFullPath((Join-Path $installPath $relative))
    if (-not $candidate.StartsWith($installPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("Unsafe integrity-manifest path: $relative")
        continue
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        $failures.Add("Integrity-manifest file missing: $relative")
        continue
    }
    $file = Get-Item -LiteralPath $candidate
    $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne [long]$entry.Bytes -or $hash -ne [string]$entry.Sha256) {
        $failures.Add("Installed file integrity mismatch: $relative")
    }
}
$actualInstalledFiles = Get-ChildItem -LiteralPath $installPath -Recurse -File |
    Where-Object { $_.FullName -ne $manifestFile }
foreach ($file in $actualInstalledFiles) {
    $relative = $file.FullName.Substring($installPath.Length + 1)
    if (-not $manifestPaths.Contains($relative)) {
        $failures.Add("Unmanifested installed file: $relative")
    }
}

$policy = Get-Content -Raw -LiteralPath $policyFile | ConvertFrom-Json
if ($policy.Version -ne $expectedProductVersion) {
    $failures.Add("Installed policy version mismatch: expected $expectedProductVersion.")
}
$offKeys = @('ShareAnonymousAnalytics','AutoUpdateCheckEnabled','EnableDebugLogs','SaveTranscriptionHistory','SaveAudioWithTranscriptionHistory','CommandModeShortcutEnabled','LocalAPIEnabled','AllowCloudProviders')
foreach ($key in $offKeys) {
    if ($policy.$key -ne $false) { $failures.Add("Insecure policy value: $key") }
}
foreach ($key in @('DictationPromptOff','SecondaryDictationPromptOff')) {
    if ($policy.$key -ne $true) { $failures.Add("Insecure policy value: $key") }
}

$installedFileVersion = (Get-Item -LiteralPath $executable).VersionInfo.FileVersion
if ($installedFileVersion -ne $expectedFileVersion) {
    $failures.Add("Installed file version mismatch: expected $expectedFileVersion, found $installedFileVersion.")
}
if (Test-Path -LiteralPath $publishPath) {
    foreach ($publishedFile in (Get-ChildItem -LiteralPath $publishPath -Recurse -File)) {
        $relative = $publishedFile.FullName.Substring($publishPath.Length + 1)
        $installedFile = Join-Path $installPath $relative
        if (-not (Test-Path -LiteralPath $installedFile)) {
            $failures.Add("Published release file is not installed: $relative")
            continue
        }

        $installedHash = (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $publishedHash = (Get-FileHash -LiteralPath $publishedFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($installedHash -ne $publishedHash) {
            $failures.Add("Installed file does not match the current release publish: $relative")
        }
    }
}

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\src') -Recurse -File |
    Where-Object { $_.Extension -eq '.cs' -and $_.FullName -notmatch '\\(bin|obj)\\' }
$forbidden = 'HttpClient|HttpWebRequest|WebRequest|URLSession|PostHog|Process\.Start|TcpListener|NamedPipeServer|Clipboard\.Set|File\.Write|StreamWriter|EventLog'
$matches = $sourceFiles | Select-String -Pattern $forbidden -CaseSensitive
if ($matches) { $failures.Add('Forbidden network, server, process, clipboard, or persistence API found in production source.') }

# Compatibility: installation retains the existing startup value identity.
$runValue = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'FluidVoiceHardened' -ErrorAction SilentlyContinue).FluidVoiceHardened
if ($runValue -notlike "*$executable*") { $failures.Add('Launch-at-login entry is missing or points elsewhere.') }

$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object OwningProcess -in (Get-Process -Name 'FluidVoice Local' -ErrorAction SilentlyContinue).Id
if ($listeners) { $failures.Add('FluidVoice Local owns a TCP listening socket.') }
$port47733 = Get-NetTCPConnection -LocalPort 47733 -State Listen -ErrorAction SilentlyContinue
if ($port47733) { $failures.Add('TCP port 47733 is open.') }

$firewallRules = Get-NetFirewallRule -DisplayName 'FluidVoice Local - Block *' -ErrorAction SilentlyContinue
$validFirewallDirections = @($firewallRules | Where-Object {
    $application = $_ | Get-NetFirewallApplicationFilter
    $program = [string]$application.Program
    $_.Enabled -eq 'True' -and
    $_.Action -eq 'Block' -and
    $_.Profile -eq 'Any' -and
    -not [string]::IsNullOrWhiteSpace($program) -and
    [IO.Path]::GetFullPath($program) -eq $executable
} | ForEach-Object { [string]$_.Direction })
if ($validFirewallDirections -notcontains 'Inbound' -or $validFirewallDirections -notcontains 'Outbound') {
    $failures.Add('Exact inbound/outbound FluidVoice Local firewall block rules are missing.')
}

if ($modelHash -eq $expectedModelHash) { Write-Output "MODEL_SHA256=PASS:$modelHash" }
Write-Output "APP_SHA256=$((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant())"
if (-not ($failures | Where-Object { $_ -match 'Integrity|integrity' })) { Write-Output "INSTALL_MANIFEST_FILES=PASS:$($integrity.Files.Count)" }
if (-not ($failures | Where-Object { $_ -match 'policy value' })) { Write-Output 'SECURE_POLICY=PASS' }
if (-not ($failures | Where-Object { $_ -match 'version mismatch' })) { Write-Output "INSTALLED_VERSION=PASS:$expectedProductVersion" }
if ((Test-Path -LiteralPath $publishedExecutable) -and
    -not ($failures | Where-Object { $_ -match 'current release publish' })) {
    Write-Output 'INSTALLED_MATCHES_PUBLISH=PASS'
}
if (-not ($failures | Where-Object { $_ -match 'Forbidden' })) { Write-Output 'STATIC_NO_NETWORK_OR_PERSISTENCE_APIS=PASS' }
if (-not ($failures | Where-Object { $_ -match 'Launch-at-login' })) { Write-Output 'START_AT_LOGIN=PASS' }
if (-not ($failures | Where-Object { $_ -match '47733' })) { Write-Output 'PORT_47733_CLOSED=PASS' }
if (-not ($failures | Where-Object { $_ -match 'listening socket' })) { Write-Output 'FLUIDVOICE_LISTENING_SOCKETS=0' }
if (-not ($failures | Where-Object { $_ -match 'firewall' })) { Write-Output 'FIREWALL_BLOCK_RULES=PASS:INBOUND,OUTBOUND,ANY,EXACT_PATH' }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "PRIVACY_GATE_FAILURE=$_" }
    exit 1
}
