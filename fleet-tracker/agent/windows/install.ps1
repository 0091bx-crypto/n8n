<#
.SYNOPSIS
  Installs the fleet tracker agent on this laptop. Run in an elevated PowerShell.
.EXAMPLE
  .\install.ps1 -Url https://n8n.example.com/webhook/fleet/checkin -Token (Get-Content .\token.txt)
#>
param(
	[Parameter(Mandatory)] [string]$Url,
	[Parameter(Mandatory)] [string]$Token,
	[int]$HeartbeatMinutes = 5,
	# Turn on precise GPS/Wi-Fi location. Only use it when your rental
	# agreement discloses location tracking and Location Services are allowed.
	[switch]$Location
)

$ErrorActionPreference = 'Stop'
$InstallDir = Join-Path $env:ProgramData 'FleetTracker'
$TaskFolder = '\FleetTracker\'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole]::Administrator)) {
	throw 'Run this script in an elevated PowerShell.'
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fleet-agent.ps1') $InstallDir -Force
@{ url = $Url; token = $Token; location = [bool]$Location } | ConvertTo-Json |
	Set-Content (Join-Path $InstallDir 'config.json') -Encoding UTF8
if ($Location) { Write-Host 'Precise location is ON. Make sure renters are told and Location Services are enabled.' }

# The config holds the token. Only SYSTEM and administrators can read the folder.
icacls $InstallDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

$script = Join-Path $InstallDir 'fleet-agent.ps1'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
	-ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew

function New-AgentAction([string]$EventName) {
	New-ScheduledTaskAction -Execute 'powershell.exe' `
		-Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -EventName $EventName"
}

function Register-AgentTask([string]$Name, $Trigger, [string]$EventName) {
	Register-ScheduledTask -TaskPath $TaskFolder -TaskName $Name -Trigger $Trigger -Action (New-AgentAction $EventName) `
		-Principal $principal -Settings $settings -Force | Out-Null
	Write-Host "Registered task $TaskFolder$Name"
}

Register-AgentTask 'Boot' (New-ScheduledTaskTrigger -AtStartup) 'boot'
Register-AgentTask 'Logon' (New-ScheduledTaskTrigger -AtLogOn) 'logon'

$heartbeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
	-RepetitionInterval (New-TimeSpan -Minutes $HeartbeatMinutes)
Register-AgentTask 'Heartbeat' $heartbeat 'heartbeat'

# Wake from sleep: Power-Troubleshooter writes event ID 1 to the System log.
$eventTriggerClass = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskEventTrigger'
$wake = New-CimInstance -CimClass $eventTriggerClass -ClientOnly
$wake.Enabled = $true
$wake.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">' +
	"*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]" +
	'</Select></Query></QueryList>'
Register-AgentTask 'Wake' $wake 'wake'

# Shutdown: event ID 1074 is written when a user or a program starts a shutdown or restart.
$shutdown = New-CimInstance -CimClass $eventTriggerClass -ClientOnly
$shutdown.Enabled = $true
$shutdown.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">' +
	"*[System[Provider[@Name='User32'] and EventID=1074]]" +
	'</Select></Query></QueryList>'
Register-AgentTask 'Shutdown' $shutdown 'shutdown'

# Send a first check-in now so the laptop shows on the status page.
Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'Boot'
Write-Host "Installed. Logs: $InstallDir\agent.log"
