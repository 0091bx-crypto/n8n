#!/bin/sh
# Removes the fleet tracker agent. Run as root.
set -u
if [ "$(uname -s)" = "Darwin" ]; then
	for name in agent boot; do
		launchctl bootout system "/Library/LaunchDaemons/com.fleettracker.$name.plist" 2>/dev/null
		rm -f "/Library/LaunchDaemons/com.fleettracker.$name.plist"
	done
else
	# Stop without a shutdown check-in: removing the agent is not a shutdown.
	systemctl disable fleet-agent-heartbeat.timer fleet-agent-wake.service 2>/dev/null
	systemctl disable fleet-agent-session.service 2>/dev/null
	systemctl stop fleet-agent-heartbeat.timer 2>/dev/null
	rm -f /etc/systemd/system/fleet-agent-*.service /etc/systemd/system/fleet-agent-*.timer
	systemctl daemon-reload
fi
rm -f /usr/local/bin/fleet-agent /etc/fleet-agent.conf
echo "Fleet tracker agent removed."
