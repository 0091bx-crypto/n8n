#!/bin/sh
# Sends one check-in from this laptop to the n8n fleet tracker.
# Usage: fleet-agent.sh [boot|logon|wake|heartbeat|shutdown]
# Reads FLEET_URL and FLEET_TOKEN from /etc/fleet-agent.conf.
set -eu

EVENT="${1:-heartbeat}"
AGENT_VERSION="1.0.0"
CONFIG="${FLEET_CONFIG:-/etc/fleet-agent.conf}"

case "$EVENT" in
	boot | logon | wake | heartbeat | shutdown) ;;
	*) echo "unknown event: $EVENT" >&2; exit 2 ;;
esac

# shellcheck disable=SC1090
. "$CONFIG"
: "${FLEET_URL:?FLEET_URL is not set in $CONFIG}"
: "${FLEET_TOKEN:?FLEET_TOKEN is not set in $CONFIG}"

# Escape a value for a JSON string.
json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }

HOSTNAME_VALUE="$(hostname)"
if [ "$(uname -s)" = "Darwin" ]; then
	SERIAL="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/ {print $4}')"
	FALLBACK_ID="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ {print $4}')"
	OS="macOS $(sw_vers -productVersion)"
	OS_USER="$(stat -f %Su /dev/console 2>/dev/null || true)"
	LOCAL_IP="$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')" 2>/dev/null || true)"
	BOOT_TIME="$(date -u -r "$(sysctl -n kern.boottime | sed 's/.*sec = \([0-9]*\).*/\1/')" +%Y-%m-%dT%H:%M:%SZ)"
else
	SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
	FALLBACK_ID="$(cat /etc/machine-id 2>/dev/null || true)"
	OS="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Linux}" || uname -sr)"
	OS_USER="$(who | awk '$2 ~ /^(:|tty|seat)/ {print $1; exit}')"
	LOCAL_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
	BOOT_TIME="$(date -u -d "@$(awk '/^btime/ {print $2}' /proc/stat)" +%Y-%m-%dT%H:%M:%SZ)"
fi

SERIAL="$(printf '%s' "$SERIAL" | tr -d '[:space:]')"
case "$SERIAL" in
	"" | "0" | "None" | "Default string" | "To be filled by O.E.M.") DEVICE_ID="$FALLBACK_ID" ;;
	*) DEVICE_ID="$SERIAL" ;;
esac

PAYLOAD=$(printf '{"deviceId":"%s","event":"%s","hostname":"%s","serialNumber":"%s","os":"%s","osUser":"%s","localIp":"%s","bootTime":"%s","agentVersion":"%s"}' \
	"$(json "$DEVICE_ID")" "$EVENT" "$(json "$HOSTNAME_VALUE")" "$(json "$SERIAL")" "$(json "$OS")" \
	"$(json "$OS_USER")" "$(json "$LOCAL_IP")" "$BOOT_TIME" "$AGENT_VERSION")

# The network is often not ready right after boot or wake, so retry for about 5 minutes.
# A shutdown gets one quick try so it does not delay the shutdown.
if [ "$EVENT" = "shutdown" ]; then ATTEMPTS=1; TIMEOUT=5; else ATTEMPTS=10; TIMEOUT=20; fi

i=1
while [ "$i" -le "$ATTEMPTS" ]; do
	# Pass the token through a header file so it does not show in the process list.
	if printf 'X-Fleet-Token: %s\n' "$FLEET_TOKEN" | curl -fsS -o /dev/null --max-time "$TIMEOUT" \
		-H 'Content-Type: application/json' -H @- -d "$PAYLOAD" "$FLEET_URL"; then
		echo "fleet-agent: $EVENT sent (attempt $i)"
		exit 0
	fi
	echo "fleet-agent: $EVENT attempt $i failed" >&2
	[ "$i" -lt "$ATTEMPTS" ] && sleep 30
	i=$((i + 1))
done
exit 1
