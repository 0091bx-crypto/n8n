# Removes the fleet tracker agent from this laptop. Run in an elevated PowerShell.
$ErrorActionPreference = 'Stop'
Get-ScheduledTask -TaskPath '\FleetTracker\' -ErrorAction SilentlyContinue |
	Unregister-ScheduledTask -Confirm:$false
Remove-Item (Join-Path $env:ProgramData 'FleetTracker') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Fleet tracker agent removed.'
