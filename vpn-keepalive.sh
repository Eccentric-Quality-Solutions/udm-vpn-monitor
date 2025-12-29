#!/bin/bash
#
# UDM VPN Keepalive Daemon
# Sends periodic ping traffic through VPN tunnels to keep them alive
# Runs as a background daemon process
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.4.2
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
SCRIPT_VERSION="0.4.2"

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
if ! ensure_directory_exists "$STATE_DIR" "state"; then
	exit 1
fi
if ! ensure_directory_exists "$LOGS_DIR" "logs"; then
	exit 1
fi

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

	# Validate we have at least one peer (before daemon starts)
	local IFS=' '
	local -a validate_ips
	read -ra validate_ips <<<"$EXTERNAL_PEER_IPS"
	if [[ ${#validate_ips[@]} -eq 0 ]]; then
		die "No VPN peers configured - cannot start keepalive"
	fi

	log_message "INFO" "Starting VPN keepalive daemon..."

	# Start daemon in background and capture PID
	# For systemd Type=forking: parent must write PID file and exit immediately
	(
		# Disable strict error handling in daemon (errors should not kill daemon)
		set +e
		set +u
		set +o pipefail

		# Detach from terminal
		exec >/dev/null 2>&1

		# Set up cleanup trap
		trap 'rm -f "$PIDFILE"; exit 0' EXIT INT TERM

		# Keepalive interval (default: 30 seconds)
		local keepalive_interval="${KEEPALIVE_INTERVAL:-30}"
		local keepalive_ping_count="${KEEPALIVE_PING_COUNT:-1}"

		# Config reload interval: reload config every 10 iterations (or every 5 minutes, whichever is longer)
		# This allows the daemon to pick up config changes without reloading too frequently
		local config_reload_interval=10
		local iteration_count=0

		# Declare peer arrays in daemon scope (so they can be updated by reload function)
		local -a external_ips
		local -a internal_ips

		# Function to load/parse peer configuration from current config variables
		parse_peer_config() {
			local IFS=' '
			read -ra external_ips <<<"${EXTERNAL_PEER_IPS:-}" || true

			if [[ -n "${INTERNAL_PEER_IPS:-}" ]]; then
				read -ra internal_ips <<<"${INTERNAL_PEER_IPS:-}" || true
			else
				# Use external IPs as fallback
				internal_ips=("${external_ips[@]}")
			fi
		}

		# Function to reload configuration and update peer arrays
		# This allows the daemon to pick up config changes automatically
		# Note: We call load_config directly (not in subshell) so variables persist.
		# With set +e, most errors won't kill the daemon. If config is so broken that
		# load_config calls exit/die, the daemon will restart via systemd (Restart=on-failure).
		reload_peer_config() {
			# Log that we're reloading config
			log_message "INFO" "Reloading configuration from $CONFIG_FILE" || true

			# Reload config (suppress output, errors won't kill daemon due to set +e)
			# If config is invalid, load_config may call exit, which will kill the daemon.
			# This is acceptable - systemd will restart it, and the admin can fix the config.
			load_config "$CONFIG_FILE" >/dev/null 2>&1 || true

			# Reparse peer IPs from reloaded config
			parse_peer_config

			# Check if we have any peers configured after reload
			if [[ ${#external_ips[@]} -eq 0 ]]; then
				log_message "WARNING" "No VPN peers configured after config reload - keepalive will not send pings until peers are configured" || true
			else
				# Log successful reload with peer count
				log_message "INFO" "Configuration reloaded successfully (${#external_ips[@]} peer(s) configured)" || true
			fi

			# Update keepalive interval if changed
			local old_interval="$keepalive_interval"
			keepalive_interval="${KEEPALIVE_INTERVAL:-30}"
			keepalive_ping_count="${KEEPALIVE_PING_COUNT:-1}"

			# Log if interval changed
			if [[ "$old_interval" != "$keepalive_interval" ]]; then
				log_message "INFO" "Keepalive interval changed from ${old_interval}s to ${keepalive_interval}s" || true
			fi
		}

		# Initial parse of peer config
		parse_peer_config

		# Log startup (errors ignored to prevent daemon exit)
		log_message "INFO" "VPN keepalive daemon started (PID: $$, interval: ${keepalive_interval}s)" || true

		# Main keepalive loop
		while true; do
			# Reload config periodically to pick up changes
			if [[ $iteration_count -ge $config_reload_interval ]]; then
				reload_peer_config
				iteration_count=0
			fi

			# Get LOCAL_UDM_IP for ping source (if configured)
			# This is needed when using INTERNAL_PEER_IPS to ensure ping goes through the VPN tunnel
			local local_udm_ip
			local_udm_ip=$(get_local_ip_for_ping 2>/dev/null || echo "")

			# If LOCAL_UDM_IP is configured and we're using internal IPs, ensure route exists on br0
			# This matches the behavior of vpn-monitor.sh ping checks
			if [[ -n "$local_udm_ip" ]] && [[ ${#internal_ips[@]} -gt 0 ]]; then
				# Check if route exists, add if needed (errors ignored to prevent daemon exit)
				if ! check_route_exists "$local_udm_ip" 2>/dev/null; then
					add_route_if_needed "$local_udm_ip" >/dev/null 2>&1 || true
				fi
			fi

			# Ping each configured peer
			local i=0
			for external_ip in "${external_ips[@]}"; do
				# Get corresponding internal IP if available
				# Handle case where internal_ips array might be shorter than external_ips
				local internal_ip
				local using_fallback=false
				if [[ $i -lt ${#internal_ips[@]} ]]; then
					internal_ip="${internal_ips[$i]}"
					# Check if internal IP is empty (fallback case)
					if [[ -z "$internal_ip" ]]; then
						internal_ip="$external_ip"
						using_fallback=true
					fi
				else
					internal_ip="$external_ip"
					using_fallback=true
				fi

				# Use internal IP for ping (better for keepalive)
				local ping_target="$internal_ip"

				# Skip if IP is empty
				if [[ -z "$ping_target" ]]; then
					continue
				fi

				# Perform keepalive ping (quiet, minimal logging)
				# Use LOCAL_UDM_IP as source if configured (matches vpn-monitor.sh behavior)
				local ping_cmd="ping"
				local ping_args=()

				# Determine if we should use source IP (LOCAL_UDM_IP configured and using internal IP)
				local use_source_ip=false
				if [[ -n "$local_udm_ip" ]] && [[ "$internal_ip" != "$external_ip" ]]; then
					use_source_ip=true
				fi

				# Determine if IPv6
				if [[ ! "$ping_target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
					# IPv6
					if command -v ping6 >/dev/null 2>&1; then
						ping_cmd="ping6"
						if [[ "$use_source_ip" == "true" ]]; then
							ping_args=(-I "$local_udm_ip")
						fi
					elif ping -6 >/dev/null 2>&1; then
						ping_cmd="ping"
						ping_args=(-6)
						if [[ "$use_source_ip" == "true" ]]; then
							ping_args=(-6 -I "$local_udm_ip")
						fi
					else
						# IPv6 ping not available, skip this peer
						continue
					fi
				else
					# IPv4 - add source IP if needed
					if [[ "$use_source_ip" == "true" ]]; then
						ping_args=(-I "$local_udm_ip")
					fi
				fi

				# Perform quiet ping (suppress all output)
				# Only log failures, not successes (to reduce log noise)
				# UDM runs Linux, so we use Linux-style ping (-W flag)
				if ! "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -W "${PING_TIMEOUT:-2}" -q "$ping_target" >/dev/null 2>&1; then
					# Log failure but continue (don't exit daemon)
					# Errors in log_message are ignored to prevent daemon exit
					# Show internal IP if different from external, otherwise just show external
					if [[ "$using_fallback" == "true" ]] || [[ "$internal_ip" == "$external_ip" ]]; then
						log_message "WARNING" "Keepalive ping failed for $external_ip" || true
					else
						log_message "WARNING" "Keepalive ping failed for $internal_ip (external: $external_ip)" || true
					fi
				fi

				((i++)) || true
			done

			((iteration_count++)) || true

			# Sleep until next interval (errors ignored)
			sleep "$keepalive_interval" || sleep 30
		done
	) &
	local daemon_pid=$!

	# For systemd Type=forking: parent must write PID file immediately after forking
	# Write PID file from parent process (not child)
	if ! echo "$daemon_pid" >"$PIDFILE" 2>/dev/null; then
		# Failed to write PID file, kill the daemon
		kill "$daemon_pid" 2>/dev/null || true
		handle_error "ERROR" "Failed to write PID file: $PIDFILE" 1
	fi

	# Verify the process is still running (quick check)
	if ! kill -0 "$daemon_pid" 2>/dev/null; then
		# Process died immediately, remove PID file
		rm -f "$PIDFILE"
		handle_error "ERROR" "VPN keepalive daemon process died immediately after start" 1
	fi

	# For systemd Type=forking: parent must exit immediately after writing PID file
	# Systemd will read the PID file and track the child process
	log_message "INFO" "VPN keepalive daemon started successfully (PID: $daemon_pid)"
	return 0
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
