<#
.SYNOPSIS
  Sends one check-in from this laptop to the n8n fleet tracker.
.DESCRIPTION
  Scheduled tasks created by install.ps1 run this script as SYSTEM.
  The script reads the webhook URL and token from config.json in the same folder.
.PARAMETER EventName
  boot, logon, wake, heartbeat or shutdown.
#>
param(
	[ValidateSet('boot', 'logon', 'wake', 'heartbeat', 'shutdown')]
	[string]$EventName = 'heartbeat'
)

$ErrorActionPreference = 'Stop'
$AgentVersion = '1.0.0'
$ConfigPath = Join-Path $PSScriptRoot 'config.json'
$LogPath = Join-Path $PSScriptRoot 'agent.log'

function Write-AgentLog([string]$Message) {
	$line = '{0:u} [{1}] {2}' -f (Get-Date), $EventName, $Message
	Add-Content -Path $LogPath -Value $line
	# Keep the log small.
	if ((Get-Item $LogPath).Length -gt 512KB) {
		Get-Content $LogPath -Tail 500 | Set-Content $LogPath
	}
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$bios = Get-CimInstance Win32_BIOS
$system = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem

# Use the BIOS serial number as the stable ID. Use the Windows machine GUID when the serial is missing.
$serial = "$($bios.SerialNumber)".Trim()
$deviceId = $serial
if (-not $deviceId -or $deviceId -in @('To be filled by O.E.M.', 'Default string', '0', 'System Serial Number')) {
	$deviceId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
}

$localIp = $null
try {
	$localIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
		Select-Object -First 1).IPv4Address.IPAddress
} catch { }

$payload = [ordered]@{
	deviceId     = $deviceId
	event        = $EventName
	hostname     = $env:COMPUTERNAME
	serialNumber = $serial
	os           = "$($os.Caption) $($os.Version)"
	osUser       = $system.UserName
	localIp      = $localIp
	bootTime     = $os.LastBootUpTime.ToUniversalTime().ToString('o')
	agentVersion = $AgentVersion
} | ConvertTo-Json -Compress

# The network is often not ready right after boot or wake, so retry for about 5 minutes.
# A shutdown gets one quick try so it does not delay the shutdown.
$attempts = if ($EventName -eq 'shutdown') { 1 } else { 10 }
$timeout = if ($EventName -eq 'shutdown') { 5 } else { 20 }

for ($i = 1; $i -le $attempts; $i++) {
	try {
		Invoke-RestMethod -Method Post -Uri $config.url -Body $payload -ContentType 'application/json' `
			-Headers @{ 'X-Fleet-Token' = $config.token } -TimeoutSec $timeout -UseBasicParsing | Out-Null
		Write-AgentLog "sent (attempt $i)"
		exit 0
	} catch {
		Write-AgentLog "attempt $i failed: $($_.Exception.Message)"
		if ($i -lt $attempts) { Start-Sleep -Seconds 30 }
	}
}
exit 1
