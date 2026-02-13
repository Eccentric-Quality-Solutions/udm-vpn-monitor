#!/bin/bash
#
# UDM VPN Monitor Wrapper
# Runs vpn-monitor.sh at configurable sub-minute intervals (e.g., every 30 seconds)
# Uses cron to start the wrapper; wrapper runs in a loop with PID file to prevent duplicates
#
# When ENABLE_MONITOR_WRAPPER=1, the installer configures cron to run this script
# instead of vpn-monitor.sh directly. Cron runs every minute; this wrapper handles
# sub-minute execution (e.g., checks at :00 and :30 within each minute).
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.7.0
#

set -euo pipefail

# Get script directory (install dir when deployed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="${SCRIPT_DIR}/vpn-monitor.sh"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}/state"
LOGS_DIR="${SCRIPT_DIR}/logs"
CRON_LOG="${LOGS_DIR}/cron.log"
PIDFILE="${STATE_DIR}/vpn-monitor-wrapper.pid"

# Read MONITOR_INTERVAL from config (default: 20 seconds)
#
# Parses vpn-monitor.conf for MONITOR_INTERVAL, clamping to 10-60 second range.
# Range: 10-60 seconds per docs/research/SUB_MINUTE_EXECUTION_OPTIONS.md
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints interval in seconds to stdout
get_monitor_interval() {
	local interval=20
	if [[ -f "$CONFIG_FILE" ]]; then
		local val
		val=$(grep "^MONITOR_INTERVAL=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
		if [[ -n "$val" ]] && [[ "$val" =~ ^[0-9]+$ ]]; then
			interval="$val"
			# Clamp to valid range
			[[ $interval -lt 10 ]] && interval=10
			[[ $interval -gt 60 ]] && interval=60
		fi
	fi
	echo "$interval"
}

# Check if wrapper is already running
#
# Arguments:
#   None
#
# Returns:
#   0: Wrapper is running
#   1: Wrapper is not running
is_running() {
	if [[ ! -f "$PIDFILE" ]]; then
		return 1
	fi

	local pid
	pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
	if [[ -z "$pid" ]]; then
		rm -f "$PIDFILE"
		return 1
	fi

	if ! kill -0 "$pid" 2>/dev/null; then
		rm -f "$PIDFILE"
		return 1
	fi

	return 0
}

# Main loop: run vpn-monitor.sh, sleep, repeat
#
# Runs vpn-monitor.sh at configured interval. Exits immediately if another
# instance is already running. Does not return (runs until interrupted).
#
# Arguments:
#   None
#
# Returns:
#   Does not return; exits 0 on SIGINT/SIGTERM
run_loop() {
	local interval
	interval=$(get_monitor_interval)

	# Ensure directories exist
	mkdir -p "$STATE_DIR" "$LOGS_DIR"

	# Exit if already running (cron may start us every minute)
	if is_running; then
		exit 0
	fi

	echo $$ >"$PIDFILE"
	trap 'rm -f "$PIDFILE"; exit 0' EXIT INT TERM

	while true; do
		if [[ -x "$MONITOR_SCRIPT" ]]; then
			"$MONITOR_SCRIPT" >>"$CRON_LOG" 2>&1 || true
		fi
		sleep "$interval"
	done
}

# When invoked by cron: run in background, exit immediately
# Cron runs: * * * * * /data/vpn-monitor/vpn-monitor-wrapper.sh &
# The & backgrounds us; we run the loop in foreground (of our process)
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
	cat <<EOF
Usage: $0 [&]

UDM VPN Monitor Wrapper - runs vpn-monitor.sh at sub-minute intervals.

When ENABLE_MONITOR_WRAPPER=1, cron runs this script every minute with &
to ensure the wrapper stays running. The wrapper runs vpn-monitor.sh
every MONITOR_INTERVAL seconds (default: 20, range: 10-60).

Configuration (in vpn-monitor.conf):
  ENABLE_MONITOR_WRAPPER=1   Use wrapper instead of direct cron (set by installer)
  MONITOR_INTERVAL=20        Seconds between checks (default: 20)

EOF
	exit 0
fi

run_loop
