#!/bin/bash
#
# UDM VPN Keepalive Daemon
# Sends periodic ping traffic through VPN tunnels to keep them alive
# Runs as a background daemon process
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.8.1
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}/state"
LOGS_DIR="${SCRIPT_DIR}/logs"
PIDFILE="${STATE_DIR}/vpn-keepalive.pid"
# Set keepalive log file before load_config() - load_config() will preserve it
LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"

# Script version
SCRIPT_VERSION="0.8.1"

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
	exit "${EXIT_SUCCESS:-0}"
	;;
--version | -v)
	echo "UDM VPN Keepalive Daemon v${SCRIPT_VERSION}"
	exit "${EXIT_SUCCESS:-0}"
	;;
"")
	echo "Usage: $0 {start|stop|status|restart}"
	echo "Run '$0 --help' for more information"
	exit "${EXIT_GENERAL_ERROR:-1}"
	;;
*)
	echo "Unknown command: $COMMAND"
	echo "Usage: $0 {start|stop|status|restart}"
	exit "${EXIT_GENERAL_ERROR:-1}"
	;;
esac

# Ensure directories exist
if ! ensure_directory_exists "$STATE_DIR" "state"; then
	exit "${EXIT_GENERAL_ERROR:-1}"
fi
if ! ensure_directory_exists "$LOGS_DIR" "logs"; then
	exit "${EXIT_GENERAL_ERROR:-1}"
fi

# Test log file write capability
if ! touch "$LOG_FILE" 2>/dev/null; then
	die "Cannot write to log file: $LOG_FILE (check permissions on directory: $(dirname "$LOG_FILE"))"
fi

# Load configuration
# Note: Path recalculation (log paths and state paths) is now handled inside load_config()
# Note: load_config() will preserve LOG_FILE since it's a custom log file (vpn-keepalive.log, not vpn-monitor.log)
#       and will update its directory if LOGS_DIR changed
if ! load_config "$CONFIG_FILE"; then
	die "Failed to load configuration from $CONFIG_FILE"
fi

# Check if keepalive is enabled
if [[ "${ENABLE_KEEPALIVE:-0}" -ne 1 ]]; then
	if [[ "$COMMAND" == "start" ]]; then
		log_message "INFO" "SYSTEM" "VPN keepalive is disabled (ENABLE_KEEPALIVE=0), not starting"
		exit "${EXIT_SUCCESS:-0}"
	fi
	# For other commands, continue (may need to stop disabled daemon)
fi

# Check if PID file exists and process is running
#
# Checks if the VPN keepalive daemon is currently running by verifying PID file and process.
#
# Arguments:
#   None
#
# Returns:
#   0: Daemon is running
#   1: Daemon is not running (PID file doesn't exist, is unreadable, or process is not running)
#
is_running() {
	if [[ ! -f "$PIDFILE" ]]; then
		return 1
	fi

	# Check file readability before cat operation (prevents hangs on unreadable files)
	# Function is available via lib/config.sh which sources lib/common.sh
	if ! file_exists_and_readable "$PIDFILE"; then
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
#
# Starts the VPN keepalive daemon in the background.
# Validates configuration and ensures at least one location is configured before starting.
#
# Arguments:
#   None
#
# Returns:
#   0: Daemon started successfully
#   1: Failed to start daemon (exits script)
#
start_daemon() {
	if is_running; then
		local pid
		# Check file readability before cat operation (prevents hangs on unreadable files)
		if file_exists_and_readable "$PIDFILE"; then
			pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
		else
			pid=""
		fi
		local pid_suffix=""
		[[ -n "$pid" ]] && pid_suffix=" (PID: $pid)"
		log_message "INFO" "SYSTEM" "VPN keepalive daemon is already running${pid_suffix}"
		return 0
	fi

	# Validate configuration - load and validate location-based config
	# This ensures at least one location is configured before starting daemon
	# Set LOG_FILE before load_config() so it's preserved (load_config() preserves custom log files)
	LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"
	if ! load_config "$CONFIG_FILE"; then
		die "Failed to load configuration from $CONFIG_FILE"
	fi

	if ! validate_config; then
		die "Configuration validation failed - cannot start keepalive"
	fi

	# Ensure at least one location is configured
	if [[ ${#LOCATIONS[@]} -eq 0 ]]; then
		die "No VPN locations configured - cannot start keepalive. At least one LOCATION_*_EXTERNAL variable is required."
	fi

	log_message "INFO" "SYSTEM" "Starting VPN keepalive daemon..."

	# Start daemon in background and capture PID
	# For systemd Type=forking: parent must write PID file and exit immediately
	(
		# Disable strict error handling in daemon (errors should not kill daemon)
		set +e
		set +u
		set +o pipefail

		# Ensure keepalive log file is set correctly in daemon
		# LOG_FILE should already be set correctly by load_config() above, but ensure it's set
		LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"

		# Detach from terminal: discard stdout; redirect stderr to error log so uncaught
		# errors (e.g. command failures, write failures) are not silently lost
		exec >/dev/null 2>>"${LOGS_DIR}/vpn-keepalive-errors.log"

		# Set up cleanup trap
		trap 'rm -f "$PIDFILE"; exit 0' EXIT INT TERM

		# Keepalive interval (default: 30 seconds)
		local keepalive_interval="${KEEPALIVE_INTERVAL:-30}"
		local keepalive_ping_count="${KEEPALIVE_PING_COUNT:-1}"

		# Config reload interval: reload config every 10 iterations (or every 5 minutes, whichever is longer)
		# This allows the daemon to pick up config changes without reloading too frequently
		local config_reload_interval=10
		local iteration_count=0

		# Declare location arrays in daemon scope (so they can be updated by reload function)
		# Structure: locations["<name>"]["external"] and locations["<name>"]["internal"]
		declare -A locations=()

		# Function to load/parse location configuration from current config variables
		#
		# Parses location-based configuration and populates local locations array.
		# Clears and repopulates locations array from global LOCATIONS array.
		#
		# Arguments:
		#   None
		#
		# Returns:
		#   None (populates local locations array)
		#
		parse_peer_config() {
			# Clear locations array
			locations=()

			# Parse location-based configuration
			# parse_location_config() populates global LOCATIONS array
			if ! parse_location_config 2>/dev/null; then
				# parse_location_config failed - log warning but don't exit daemon
				log_message "WARNING" "SYSTEM" "Failed to parse location configuration - keepalive will not send pings until locations are configured" || true
				return
			fi

			# Copy location names to local locations array (for daemon scope)
			# We only need the keys for iteration; values are read from global LOCATIONS via helper functions
			for loc_name in "${!LOCATIONS[@]}"; do
				locations["$loc_name"]=1
			done
		}

		# Function to reload configuration and update peer arrays
		#
		# Reloads configuration from config file and updates peer arrays.
		# This allows the daemon to pick up config changes automatically.
		# Note: We call load_config directly (not in subshell) so variables persist.
		# With set +e, most errors won't kill the daemon. If config is so broken that
		# load_config calls exit/die, the daemon will restart via systemd (Restart=on-failure).
		#
		# Arguments:
		#   None
		#
		# Returns:
		#   None
		#
		reload_peer_config() {
			# Log that we're reloading config
			log_message "INFO" "SYSTEM" "Reloading configuration from $CONFIG_FILE" || true

			# Reload config (suppress output, errors won't kill daemon due to set +e)
			# If config is invalid, load_config may call exit, which will kill the daemon.
			# This is acceptable - systemd will restart it, and the admin can fix the config.
			local load_result
			if ! load_config "$CONFIG_FILE" >/dev/null 2>&1; then
				load_result=$?
				# load_config failed but didn't exit - log explicit error
				log_message "ERROR" "SYSTEM" "Failed to reload configuration from $CONFIG_FILE (exit code: $load_result)" || true
				# Continue with existing configuration rather than failing completely
			fi

			# Set LOG_FILE before load_config() so it's preserved (load_config() preserves custom log files)
			LOG_FILE="${LOGS_DIR}/vpn-keepalive.log"

			# Reparse peer IPs from reloaded config
			parse_peer_config

			# Check if we have any locations configured after reload
			if [[ ${#locations[@]} -eq 0 ]]; then
				log_message "WARNING" "SYSTEM" "No VPN locations configured after config reload - keepalive will not send pings until locations are configured" || true
			else
				# Log successful reload with location count
				log_message "INFO" "SYSTEM" "Configuration reloaded successfully (${#locations[@]} location(s) configured)" || true
			fi

			# Update keepalive interval if changed
			local old_interval="$keepalive_interval"
			keepalive_interval="${KEEPALIVE_INTERVAL:-30}"
			keepalive_ping_count="${KEEPALIVE_PING_COUNT:-1}"

			# Log if interval changed
			if [[ "$old_interval" != "$keepalive_interval" ]]; then
				log_message "INFO" "SYSTEM" "Keepalive interval changed from ${old_interval}s to ${keepalive_interval}s" || true
			fi
		}

		# Initial parse of peer config
		parse_peer_config

		# Log startup (errors ignored to prevent daemon exit)
		log_message "INFO" "SYSTEM" "VPN keepalive daemon started (PID: $$, interval: ${keepalive_interval}s)" || true

		# Main keepalive loop
		while true; do
			# Reload config periodically to pick up changes
			if [[ $iteration_count -ge $config_reload_interval ]]; then
				reload_peer_config
				iteration_count=0
			fi

			# Get LOCAL_UDM_IP for ping source (if configured)
			# This is needed when using internal IPs to ensure ping goes through the VPN tunnel
			local local_udm_ip
			local_udm_ip=$(get_local_ip_for_ping 2>/dev/null || echo "")

			# If LOCAL_UDM_IP is configured and we have locations with internal IPs, ensure route exists on br0
			# This matches the behavior of vpn-monitor.sh ping checks
			if [[ -n "$local_udm_ip" ]] && [[ ${#locations[@]} -gt 0 ]]; then
				# Check if route exists, add if needed (errors ignored to prevent daemon exit)
				if ! check_route_exists "$local_udm_ip" 2>/dev/null; then
					add_route_if_needed "$local_udm_ip" >/dev/null 2>&1 || true
				fi
			fi

			# Ping each configured location
			for location_name in "${!locations[@]}"; do
				# Get external IP for this location (resolved from DNS if needed)
				local external_peer_ip
				if ! external_peer_ip=$(get_location_external_ip_resolved "$location_name"); then
					log_message "WARNING" "$location_name" "Keepalive: failed to get or resolve external IP (skipping)" || true
					continue
				fi

				# Get internal IPs for this location (resolved from DNS if needed, may be empty)
				local internal_ips
				internal_ips=$(get_location_internal_ips_resolved "$location_name" 2>/dev/null || echo "")

				# Determine ping target(s)
				local ping_target
				if [[ -n "$internal_ips" ]]; then
					ping_target="$internal_ips"
				else
					ping_target="$external_peer_ip"
				fi

				# Skip if ping target is empty
				if [[ -z "$ping_target" ]]; then
					continue
				fi

				# Check if multiple internal IPs (has spaces)
				if [[ "$ping_target" =~ [[:space:]] ]]; then
					# Multiple IPs - use check_ping_multiple_ips with 30% threshold
					if ! check_ping_multiple_ips "$ping_target" "$local_udm_ip" >/dev/null 2>&1; then
						log_message "WARNING" "$location_name" "Keepalive: ping check failed (<30% of internal IPs responded)" || true
					fi
				else
					# Single IP - use build_ping_command function
					# Determine if we should use source IP (LOCAL_UDM_IP configured and using internal IP)
					local source_ip_for_ping=""
					if [[ -n "$local_udm_ip" ]] && [[ "$ping_target" != "$external_peer_ip" ]]; then
						source_ip_for_ping="$local_udm_ip"
					fi

					# Build ping command and arguments
					local ping_cmd
					local ping_args=()
					if ! build_ping_command "$ping_target" "$source_ip_for_ping"; then
						# IPv6 ping not available, skip this location
						continue
					fi

					# Perform quiet ping (suppress all output)
					# Only log failures, not successes (to reduce log noise)
					# UDM runs Linux, so we use Linux-style ping (-W flag)
					# Wrap ping commands with timeout to prevent hanging
					# Calculate timeout wrapper: min(ping_timeout + 1, min(ping_count * ping_timeout + 1, 5))
					# This ensures we catch hanging commands quickly while allowing normal pings to complete
					local ping_timeout="${PING_TIMEOUT:-2}"
					local quick_timeout=$((ping_timeout + 1))
					local normal_timeout=$((keepalive_ping_count * ping_timeout + 1))
					# Cap normal timeout at 5 seconds for responsiveness
					if [[ $normal_timeout -gt 5 ]]; then
						normal_timeout=5
					fi
					# Use the smaller timeout to catch hangs quickly
					local ping_wrapper_timeout
					if [[ $quick_timeout -lt $normal_timeout ]]; then
						ping_wrapper_timeout=$quick_timeout
					else
						ping_wrapper_timeout=$normal_timeout
					fi

					local ping_success=0
					# Use Linux-style ping with timeout wrapper
					if check_command_available "timeout"; then
						# Try Linux-style ping with timeout wrapper
						if timeout "$ping_wrapper_timeout" "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -W "$ping_timeout" -q "$ping_target" >/dev/null 2>&1; then
							ping_success=1
						else
							local ping_exit_code=$?
							# If timeout occurred (exit code 124), don't try fallbacks
							if [[ $ping_exit_code -ne 124 ]]; then
								# Try without timeout flag as fallback (only if not timeout)
								if timeout "$ping_wrapper_timeout" "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -q "$ping_target" >/dev/null 2>&1; then
									ping_success=1
								fi
							fi
						fi
					else
						# Fallback if timeout command not available (shouldn't happen on UDM)
						if "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -W "$ping_timeout" -q "$ping_target" >/dev/null 2>&1; then
							ping_success=1
						# Try without timeout flag as fallback
						elif "$ping_cmd" "${ping_args[@]}" -c "$keepalive_ping_count" -q "$ping_target" >/dev/null 2>&1; then
							ping_success=1
						fi
					fi

					if [[ $ping_success -eq 0 ]]; then
						# Log failure but continue (don't exit daemon)
						# Errors in log_message are ignored to prevent daemon exit
						if [[ "$ping_target" == "$external_peer_ip" ]]; then
							log_message "WARNING" "$location_name" "Keepalive: ping failed for $external_peer_ip" || true
						else
							log_message "WARNING" "$location_name" "Keepalive: ping failed for $ping_target (external: $external_peer_ip)" || true
						fi
					fi
				fi
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
		handle_error "ERROR" "SYSTEM" "Failed to write PID file: $PIDFILE" 1
	fi

	# Verify the process is still running (quick check)
	if ! kill -0 "$daemon_pid" 2>/dev/null; then
		# Process died immediately, remove PID file
		rm -f "$PIDFILE"
		handle_error "ERROR" "SYSTEM" "VPN keepalive daemon process died immediately after start" 1
	fi

	# For systemd Type=forking: parent must exit immediately after writing PID file
	# Systemd will read the PID file and track the child process
	log_message "INFO" "SYSTEM" "VPN keepalive daemon started successfully (PID: $daemon_pid)"
	return 0
}

# Stop the keepalive daemon
#
# Stops the VPN keepalive daemon gracefully by sending TERM signal.
# Force kills if daemon doesn't exit within 10 seconds.
#
# Arguments:
#   None
#
# Returns:
#   0: Daemon stopped successfully
#   1: Failed to stop daemon (exits script)
#
stop_daemon() {
	if ! is_running; then
		log_message "INFO" "SYSTEM" "VPN keepalive daemon is not running"
		return 0
	fi

	local pid
	# Check file readability before cat operation (prevents hangs on unreadable files)
	if file_exists_and_readable "$PIDFILE"; then
		pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
	else
		pid=""
	fi
	if [[ -z "$pid" ]]; then
		log_message "ERROR" "SYSTEM" "Failed to read PID file: $PIDFILE"
		return 1
	fi

	log_message "INFO" "SYSTEM" "Stopping VPN keepalive daemon (PID: $pid)..."

	# Send TERM signal
	if kill -TERM "$pid" 2>/dev/null; then
		# Wait for process to exit (max 10 seconds)
		local count=0
		while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
			sleep 1
			((count++)) || true
		done

		# Force kill if still running
		if kill -0 "$pid" 2>/dev/null; then
			log_message "WARNING" "SYSTEM" "Daemon did not exit gracefully, forcing termination"
			kill -KILL "$pid" 2>/dev/null || true
			sleep 1
		fi

		# Remove PID file
		rm -f "$PIDFILE"

		log_message "INFO" "SYSTEM" "VPN keepalive daemon stopped"
		return 0
	else
		# kill -TERM failed - check if process is still running
		# If process already exited, that's fine - just clean up PID file
		if ! kill -0 "$pid" 2>/dev/null; then
			# Process already exited, clean up PID file
			log_message "INFO" "SYSTEM" "VPN keepalive daemon process already exited (PID: $pid), cleaning up PID file"
			rm -f "$PIDFILE"
			return 0
		else
			# Process is still running but we couldn't send TERM signal
			# This is an error (permission issue, etc.)
			handle_error "ERROR" "SYSTEM" "Failed to stop VPN keepalive daemon (PID: $pid)" 1
		fi
	fi
}

# Check daemon status
#
# Checks and displays the current status of the VPN keepalive daemon.
#
# Arguments:
#   None
#
# Returns:
#   0: Daemon is running
#   1: Daemon is not running
#
check_status() {
	if is_running; then
		local pid
		# Check file readability before cat operation (prevents hangs on unreadable files)
		if file_exists_and_readable "$PIDFILE"; then
			pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
		else
			pid=""
		fi
		if [[ -n "$pid" ]]; then
			echo "VPN keepalive daemon is running (PID: $pid)"
		else
			echo "VPN keepalive daemon is running"
		fi
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

exit "${EXIT_SUCCESS:-0}"
