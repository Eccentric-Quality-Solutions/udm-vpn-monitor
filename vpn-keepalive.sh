#!/bin/bash
#
# UDM VPN Keepalive Daemon
# Sends periodic ping traffic through VPN tunnels to keep them alive
# Runs as a background daemon process
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.3.0
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}"
LOGS_DIR="${STATE_DIR}/logs"
PIDFILE="${STATE_DIR}/vpn-keepalive.pid"
LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"

# Script version
SCRIPT_VERSION="0.3.0"

# Source library modules
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/detection.sh
source "${SCRIPT_DIR}/lib/detection.sh"

# Parse command line arguments
COMMAND="${1:-}"
case "$COMMAND" in
start)
	# Will be handled below
	;;
stop)
	# Will be handled below
	;;
status)
	# Will be handled below
	;;
restart)
	# Will be handled below
	;;
--help | -h)
	echo "Usage: $0 {start|stop|status|restart}"
	echo ""
	echo "UDM VPN Keepalive Daemon v${SCRIPT_VERSION}"
	echo "Sends periodic ping traffic through VPN tunnels to keep them alive"
	echo ""
	echo "Commands:"
	echo "  start    Start the keepalive daemon"
	echo "  stop     Stop the keepalive daemon"
	echo "  status   Check if daemon is running"
	echo "  restart  Restart the keepalive daemon"
	echo ""
	exit 0
	;;
--version | -v)
	echo "UDM VPN Keepalive Daemon v${SCRIPT_VERSION}"
	exit 0
	;;
"")
	echo "Usage: $0 {start|stop|status|restart}"
	echo "Run '$0 --help' for more information"
	exit 1
	;;
*)
	echo "Unknown command: $COMMAND"
	echo "Usage: $0 {start|stop|status|restart}"
	exit 1
	;;
esac

# Ensure directories exist
ensure_directory_exists "$STATE_DIR" "state"
ensure_directory_exists "$LOGS_DIR" "logs"

# Test log file write capability
if ! touch "$LOG_FILE" 2>/dev/null; then
	die "Cannot write to log file: $LOG_FILE (check permissions on directory: $(dirname "$LOG_FILE"))"
fi

# Load configuration
load_config "$CONFIG_FILE"

# Update log file path if LOGS_DIR was overridden in config
LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"
PIDFILE="${STATE_DIR}/vpn-keepalive.pid"

# Check if keepalive is enabled
if [[ "${ENABLE_KEEPALIVE:-0}" -ne 1 ]]; then
	if [[ "$COMMAND" == "start" ]]; then
		log_message "INFO" "VPN keepalive is disabled (ENABLE_KEEPALIVE=0), not starting"
		exit 0
	fi
	# For other commands, continue (may need to stop disabled daemon)
fi

# Check if PID file exists and process is running
is_running() {
	if [[ ! -f "$PIDFILE" ]]; then
		return 1
	fi

	local pid
	pid=$(cat "$PIDFILE" 2>/dev/null || echo "")

	if [[ -z "$pid" ]]; then
		return 1
	fi

	if ! kill -0 "$pid" 2>/dev/null; then
		# PID file exists but process is dead
		rm -f "$PIDFILE"
		return 1
	fi

	return 0
}

# Start the keepalive daemon
start_daemon() {
	if is_running; then
		local pid
		pid=$(cat "$PIDFILE")
		log_message "INFO" "VPN keepalive daemon is already running (PID: $pid)"
		return 0
	fi

	# Validate configuration
	if [[ -z "${EXTERNAL_PEER_IPS:-}" ]]; then
		die "EXTERNAL_PEER_IPS not configured - cannot start keepalive"
	fi

	# Parse peer IPs (space-separated, consistent with vpn-monitor.sh)
	local IFS=' '
	local -a external_ips
	read -ra external_ips <<<"$EXTERNAL_PEER_IPS"

	local -a internal_ips
	if [[ -n "${INTERNAL_PEER_IPS:-}" ]]; then
		read -ra internal_ips <<<"$INTERNAL_PEER_IPS"
	else
		# Use external IPs as fallback
		internal_ips=("${external_ips[@]}")
	fi

	# Validate we have at least one peer
	if [[ ${#external_ips[@]} -eq 0 ]]; then
		die "No VPN peers configured - cannot start keepalive"
	fi

	log_message "INFO" "Starting VPN keepalive daemon..."

	# Start daemon in background
	(
		# Disable strict error handling in daemon (errors should not kill daemon)
		set +e
		set +u
		set +o pipefail

		# Detach from terminal
		exec >/dev/null 2>&1

		# Write PID file (errors handled by parent checking is_running)
		echo $$ >"$PIDFILE" 2>/dev/null || true

		# Set up cleanup trap
		trap 'rm -f "$PIDFILE"; exit 0' EXIT INT TERM

		# Keepalive interval (default: 30 seconds)
		local keepalive_interval="${KEEPALIVE_INTERVAL:-30}"
		local keepalive_ping_count="${KEEPALIVE_PING_COUNT:-1}"

		# Log startup (errors ignored to prevent daemon exit)
		log_message "INFO" "VPN keepalive daemon started (PID: $$, interval: ${keepalive_interval}s)" || true

		# Main keepalive loop
		while true; do
			# Ping each configured peer
			local i=0
			for external_ip in "${external_ips[@]}"; do
				# Get corresponding internal IP if available
				# Handle case where internal_ips array might be shorter than external_ips
				local internal_ip
				if [[ $i -lt ${#internal_ips[@]} ]]; then
					internal_ip="${internal_ips[$i]}"
				else
					internal_ip="$external_ip"
				fi

				# Fallback to external IP if internal IP is empty
				if [[ -z "$internal_ip" ]]; then
					internal_ip="$external_ip"
				fi

				# Use internal IP for ping (better for keepalive)
				local ping_target="$internal_ip"

				# Skip if IP is empty
				if [[ -z "$ping_target" ]]; then
					continue
				fi

				# Perform keepalive ping (quiet, minimal logging)
				# Use a simple ping command directly to avoid logging overhead
				local ping_cmd="ping"
				local ping_args=()

				# Determine if IPv6
				if [[ ! "$ping_target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
					# IPv6
					if command -v ping6 >/dev/null 2>&1; then
						ping_cmd="ping6"
					elif ping -6 >/dev/null 2>&1; then
						ping_cmd="ping"
						ping_args=(-6)
					else
						# IPv6 ping not available, skip this peer
						continue
					fi
				fi

				# Perform quiet ping (suppress all output)
				# Only log failures, not successes (to reduce log noise)
				# UDM runs Linux, so we use Linux-style ping (-W flag)
				if ! "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -W "${PING_TIMEOUT:-2}" -q "$ping_target" >/dev/null 2>&1; then
					# Log failure but continue (don't exit daemon)
					# Errors in log_message are ignored to prevent daemon exit
					log_message "WARNING" "Keepalive ping failed for $ping_target (external: $external_ip)" || true
				fi

				((i++)) || true
			done

			# Sleep until next interval (errors ignored)
			sleep "$keepalive_interval" || sleep 30
		done
	) &

	# Give daemon a moment to start
	sleep 1

	if is_running; then
		local pid
		pid=$(cat "$PIDFILE")
		log_message "INFO" "VPN keepalive daemon started successfully (PID: $pid)"
		return 0
	else
		handle_error "ERROR" "Failed to start VPN keepalive daemon" 1
	fi
}

# Stop the keepalive daemon
stop_daemon() {
	if ! is_running; then
		log_message "INFO" "VPN keepalive daemon is not running"
		return 0
	fi

	local pid
	pid=$(cat "$PIDFILE")

	log_message "INFO" "Stopping VPN keepalive daemon (PID: $pid)..."

	# Send TERM signal
	if kill -TERM "$pid" 2>/dev/null; then
		# Wait for process to exit (max 10 seconds)
		local count=0
		while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
			sleep 1
			((count++))
		done

		# Force kill if still running
		if kill -0 "$pid" 2>/dev/null; then
			log_message "WARNING" "Daemon did not exit gracefully, forcing termination"
			kill -KILL "$pid" 2>/dev/null || true
			sleep 1
		fi

		# Remove PID file
		rm -f "$PIDFILE"

		log_message "INFO" "VPN keepalive daemon stopped"
		return 0
	else
		handle_error "ERROR" "Failed to stop VPN keepalive daemon (PID: $pid)" 1
	fi
}

# Check daemon status
check_status() {
	if is_running; then
		local pid
		pid=$(cat "$PIDFILE")
		echo "VPN keepalive daemon is running (PID: $pid)"
		return 0
	else
		echo "VPN keepalive daemon is not running"
		return 1
	fi
}

# Handle commands
case "$COMMAND" in
start)
	start_daemon
	;;
stop)
	stop_daemon
	;;
status)
	check_status
	;;
restart)
	stop_daemon
	sleep 1
	start_daemon
	;;
*)
	die "Unknown command: $COMMAND"
	;;
esac

exit 0
