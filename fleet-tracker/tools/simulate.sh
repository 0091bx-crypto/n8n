#!/bin/sh
# Sends test check-ins for a few fake laptops. Use it to try the workflows before you install agents.
# Usage: FLEET_URL=https://n8n.example.com/webhook-test/fleet/checkin FLEET_TOKEN=... ./simulate.sh
set -eu
: "${FLEET_URL:?set FLEET_URL}"
: "${FLEET_TOKEN:?set FLEET_TOKEN}"

send() {
	printf 'X-Fleet-Token: %s\n' "$FLEET_TOKEN" | curl -fsS -H 'Content-Type: application/json' -H @- \
		-d "{\"deviceId\":\"$1\",\"event\":\"$2\",\"hostname\":\"$3\",\"serialNumber\":\"$1\",\"os\":\"Windows 11 Pro\",\"osUser\":\"RENTAL\\\\guest\",\"agentVersion\":\"sim\"}" \
		"$FLEET_URL"
	echo
}

send SIM-0001 boot LT-RENT-01
send SIM-0002 boot LT-RENT-02
send SIM-0002 logon LT-RENT-02
send SIM-0003 heartbeat LT-RENT-03
send SIM-0003 shutdown LT-RENT-03
