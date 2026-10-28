[CmdletBinding()]
param(
    [string]$Executable = (Join-Path $env:LOCALAPPDATA 'Programs\FluidVoice Local\FluidVoice Local.exe')
)

$ErrorActionPreference = 'Stop'
$executablePath = [IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $executablePath)) { throw "Executable not found: $executablePath" }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $powerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Executable `"$executablePath`""
    try {
        $elevated = Start-Process -FilePath $powerShell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru
    }
    catch {
        throw 'Administrator elevation was declined or could not be started. No firewall rule was changed.'
    }
    if ($elevated.ExitCode -ne 0) {
        throw "The elevated firewall configuration failed with exit code $($elevated.ExitCode)."
    }
    Write-Output 'FIREWALL_ELEVATION=PASS'
    exit 0
}

$rules = @(
    @{ Name = 'FluidVoice Local - Block Outbound'; Direction = 'Outbound' },
    @{ Name = 'FluidVoice Local - Block Inbound'; Direction = 'Inbound' }
)
foreach ($rule in $rules) {
    Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
    New-NetFirewallRule -DisplayName $rule.Name -Direction $rule.Direction -Action Block -Program $executablePath -Profile Any -Enabled True -ErrorAction Stop | Out-Null
}

Get-NetFirewallRule -DisplayName 'FluidVoice Local - Block *' |
    Get-NetFirewallApplicationFilter |
    Select-Object InstanceID, Program
