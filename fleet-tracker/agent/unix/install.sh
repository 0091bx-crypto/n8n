#!/bin/sh
# Installs the fleet tracker agent on a Linux (systemd) or macOS laptop. Run as root.
# Usage: FLEET_URL=https://n8n.example.com/webhook/fleet/checkin FLEET_TOKEN=... sudo -E ./install.sh
set -eu

: "${FLEET_URL:?set FLEET_URL}"
: "${FLEET_TOKEN:?set FLEET_TOKEN}"
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/local/bin/fleet-agent

install -d /usr/local/bin
install -m 0755 "$HERE/fleet-agent.sh" "$BIN"
umask 077
printf 'FLEET_URL=%s\nFLEET_TOKEN=%s\n' "'$FLEET_URL'" "'$FLEET_TOKEN'" > /etc/fleet-agent.conf
chmod 0600 /etc/fleet-agent.conf
umask 022

if [ "$(uname -s)" = "Darwin" ]; then
	# RunAtLoad sends the boot check-in. StartInterval sends heartbeats and catches wake from sleep.
	cat > /Library/LaunchDaemons/com.fleettracker.agent.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.fleettracker.agent</string>
	<key>ProgramArguments</key><array><string>$BIN</string><string>heartbeat</string></array>
	<key>StartInterval</key><integer>300</integer>
	<key>StandardErrorPath</key><string>/var/log/fleet-agent.log</string>
	<key>StandardOutPath</key><string>/var/log/fleet-agent.log</string>
</dict>
</plist>
PLIST
	cat > /Library/LaunchDaemons/com.fleettracker.boot.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.fleettracker.boot</string>
	<key>ProgramArguments</key><array><string>$BIN</string><string>boot</string></array>
	<key>RunAtLoad</key><true/>
	<key>StandardErrorPath</key><string>/var/log/fleet-agent.log</string>
	<key>StandardOutPath</key><string>/var/log/fleet-agent.log</string>
</dict>
</plist>
PLIST
	for name in agent boot; do
		launchctl bootout system "/Library/LaunchDaemons/com.fleettracker.$name.plist" 2>/dev/null || true
		launchctl bootstrap system "/Library/LaunchDaemons/com.fleettracker.$name.plist"
	done
	echo "Installed. Logs: /var/log/fleet-agent.log"
	exit 0
fi

# Linux with systemd.
cat > /etc/systemd/system/fleet-agent-session.service <<UNIT
[Unit]
Description=Fleet tracker: report boot and shutdown
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN boot
ExecStop=$BIN shutdown
TimeoutStartSec=6min

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/fleet-agent-heartbeat.service <<UNIT
[Unit]
Description=Fleet tracker: heartbeat
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN heartbeat
UNIT

cat > /etc/systemd/system/fleet-agent-heartbeat.timer <<UNIT
[Unit]
Description=Fleet tracker: heartbeat every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

# Report wake from sleep.
cat > /etc/systemd/system/fleet-agent-wake.service <<UNIT
[Unit]
Description=Fleet tracker: report wake from sleep
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=$BIN wake

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
UNIT

systemctl daemon-reload
systemctl enable --now fleet-agent-session.service fleet-agent-heartbeat.timer
systemctl enable fleet-agent-wake.service
echo "Installed. Logs: journalctl -u 'fleet-agent-*'"
