#!/bin/bash
#
# IPsec-based recovery functions for UDM VPN Monitor
# Implements IPsec reload and restart recovery actions
#
# Version: 0.7.0
#

# shellcheck source=lib/recovery/constants.sh
RECOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${RECOVERY_DIR}/constants.sh"

# shellcheck source=lib/recovery/recovery_verification.sh
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || {
	# Verify IPsec connections are active (fallback stub)
	#
	# Fallback stub function when recovery_verification.sh cannot be sourced.
	# Always returns failure since verification functionality is unavailable.
	#
	# Arguments:
	#   $1: Space-separated list of peer IPs to verify (optional, ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (recovery_verification.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_verification.sh.
	verify_ipsec_connections_active() { return 1; }
	# Verify byte counters resume after recovery (fallback stub)
	#
	# Fallback stub function when recovery_verification.sh cannot be sourced.
	# Always returns failure since verification functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address to verify (ignored in fallback)
	#   $2: Optional location name for logging context (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (recovery_verification.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_verification.sh.
	verify_byte_counters_resume() { return 1; }
}

# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || {
	# Store recovery method used for a location (fallback stub)
	#
	# Fallback stub function when recovery_state.sh cannot be sourced.
	# Always succeeds silently since state storage is non-critical.
	#
	# Arguments:
	#   $1: Location name (ignored in fallback)
	#   $2: External peer IP address (ignored in fallback)
	#   $3: Recovery method name (ignored in fallback)
	#
	# Returns:
	#   0: Always succeeds (recovery_state.sh unavailable, but non-critical)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in recovery_state.sh.
	store_recovery_method() { return 0; }
}

# Execute IPsec reload recovery
#
# Executes ipsec reload command and verifies connections are active.
# Falls back to ipsec restart if reload fails.
#
# Arguments:
#   $1: Peer IP address (for logging context)
#   $2: Location name (for logging context)
#
# Returns:
#   0: Recovery succeeded (reload or restart completed successfully)
#   1: Recovery failed (both reload and restart failed)
#
# Side effects:
#   - Executes ipsec reload (or restart if reload fails)
#   - Stores recovery method used
#   - Logs all actions and results
#
# Examples:
#   if execute_ipsec_reload "203.0.113.1" "NYC"; then
#       echo "IPsec reload succeeded"
#   fi
#
# Note:
#   Requires _RECOVERY_IPSEC_PATH to be set (from recovery orchestration)
#   Falls back to 'ipsec' command if _RECOVERY_IPSEC_PATH is unset
#   Uses verify_ipsec_connections_active for verification
execute_ipsec_reload() {
	local external_peer_ip="$1"
	local location_name="$2"

	# Validate required parameters
	if [[ -z "$external_peer_ip" ]] || [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "execute_ipsec_reload: external_peer_ip and location_name are required" 0
		return 1
	fi

	# Calculate once, reuse throughout
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	local reload_start_time
	reload_start_time=$(get_unix_timestamp)
	local command_succeeded=0
	local reload_exit_code=""
	local restart_exit_code=""
	# Use full path to ipsec if available, otherwise rely on PATH
	local ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"

	# Store recovery method before attempting recovery
	local recovery_method_used="ipsec_reload"
	store_recovery_method "$location_name" "$external_peer_ip" "$recovery_method_used"

	log_message "INFO" "$location_name" "Attempting ipsec reload for $ip_display (affects all tunnels)"
	if "$ipsec_cmd" reload >/dev/null 2>&1; then
		command_succeeded=1
		log_message "INFO" "$location_name" "Successfully reloaded IPsec connections via ipsec reload for $ip_display"
	else
		reload_exit_code=$?
		handle_error "WARNING" "$location_name" "ipsec reload failed for $ip_display (exit code: ${reload_exit_code}), attempting ipsec restart"
		# Update recovery method if fallback to restart
		recovery_method_used="ipsec_restart"
		store_recovery_method "$location_name" "$external_peer_ip" "$recovery_method_used"
		if "$ipsec_cmd" restart >/dev/null 2>&1; then
			command_succeeded=1
			log_message "INFO" "$location_name" "Successfully restarted IPsec service via ipsec restart for $ip_display"
		else
			restart_exit_code=$?
			handle_error "ERROR" "$location_name" "ipsec restart also failed for $ip_display (exit code: ${restart_exit_code})" 0
			command_succeeded=0
		fi
	fi

	# Verify connections are active after reload/restart
	if [[ $command_succeeded -eq 1 ]]; then
		# Wait a moment for connections to re-establish
		sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

		# Calculate duration once for use in both success and failure paths
		local reload_duration
		reload_duration=$(calculate_duration "$reload_start_time")

		# Verify connections are active (not just that command succeeded)
		# Note: ipsec reload/restart affects ALL tunnels, so we verify all locations
		# to ensure we didn't break other working tunnels while fixing this one
		if verify_ipsec_connections_active; then
			log_message "INFO" "$location_name" "Recovery completed for $ip_display (via $recovery_method_used, verification: connections active, duration: ${reload_duration}s)"
			return 0
		else
			handle_error "WARNING" "$location_name" "Recovery completed for $ip_display (via $recovery_method_used, verification: some connections not active, duration: ${reload_duration}s)"
			# Clear recovery method since verification failed (prevents stale recovery method from being logged if VPN recovers naturally later)
			if command -v clear_recovery_method >/dev/null 2>&1; then
				clear_recovery_method "$location_name" "$external_peer_ip"
			fi
			return 1
		fi
	else
		handle_error "WARNING" "$location_name" "IPsec recovery failed for $ip_display (ipsec commands failed, exit codes: reload=${reload_exit_code:-unknown}, restart=${restart_exit_code:-unknown})"
		# Clear recovery method since recovery failed (prevents stale recovery method from being logged if VPN recovers naturally later)
		if command -v clear_recovery_method >/dev/null 2>&1; then
			clear_recovery_method "$location_name" "$external_peer_ip"
		fi
		return 1
	fi
}

# Execute IPsec restart recovery
#
# Executes ipsec restart command and verifies connections and byte counters are active.
# This is the most disruptive recovery action affecting all VPN tunnels.
#
# Arguments:
#   $1: Peer IP address (for logging context, optional)
#   $2: Location name (for logging context)
#
# Returns:
#   0: Restart successful (command executed successfully and verification passed)
#   1: Restart failed (command error or verification failed)
#
# Side effects:
#   - Executes ipsec restart (affects all VPN tunnels)
#   - Stores recovery method used
#   - Appends command output to LOG_FILE
#   - Logs all actions and results
#
# Examples:
#   if execute_ipsec_restart "203.0.113.1" "NYC"; then
#       echo "IPsec restart succeeded"
#   fi
#
# Note:
#   Requires _RECOVERY_IPSEC_PATH and LOG_FILE to be set (from recovery orchestration)
#   Uses verify_ipsec_connections_active and verify_byte_counters_resume for verification
execute_ipsec_restart() {
	local external_peer_ip="${1:-}"
	local location_name="$2"

	# Validate required parameters
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "execute_ipsec_restart: location_name is required" 0
		return 1
	fi

	# Validate LOG_FILE is set (required for tee output)
	if [[ -z "${LOG_FILE:-}" ]]; then
		handle_error "ERROR" "$location_name" "LOG_FILE not set, cannot log ipsec restart output" 0
		return 1
	fi

	# Store recovery method before attempting recovery
	if [[ -n "$external_peer_ip" ]]; then
		store_recovery_method "$location_name" "$external_peer_ip" "ipsec_restart"
	fi

	# Note: execute_ipsec_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
	log_message "INFO" "$location_name" "Executing ipsec restart (affects all tunnels)"
	local restart_start_time
	restart_start_time=$(get_unix_timestamp)
	# Use full path to ipsec if available, otherwise rely on PATH
	local ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"
	# Capture exit code explicitly to avoid PIPESTATUS being cleared
	# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
	"$ipsec_cmd" restart 2>&1 | tee -a "$LOG_FILE"
	local ipsec_exit_code=${PIPESTATUS[0]}
	if [[ $ipsec_exit_code -ne 0 ]]; then
		# Note: execute_ipsec_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
		handle_error "ERROR" "$location_name" "Failed to restart IPsec service (exit code: $ipsec_exit_code)" 0
		return 1
	fi

	# Wait a moment for connections to re-establish
	sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

	# Verify all connections restored and byte counters resume
	local verify_start_time
	verify_start_time=$(get_unix_timestamp)
	local connections_verified=0
	local byte_counters_verified=0

	# Verify connections are active (not just that command succeeded)
	if verify_ipsec_connections_active; then
		connections_verified=1
	else
		# Note: execute_ipsec_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
		handle_error "WARNING" "$location_name" "Tier 3: Some connections not active after ipsec restart"
	fi

	# Verify byte counters resume for all configured locations
	# Parse location configuration to get all external IPs
	# Use global LOCATIONS array if available, otherwise parse config
	if command -v parse_location_config >/dev/null 2>&1; then
		# Ensure location config is parsed (may not be if called directly)
		if ! declare -p LOCATIONS &>/dev/null 2>&1; then
			parse_location_config 2>/dev/null || true
		fi
		if [[ ${#LOCATIONS[@]} -gt 0 ]]; then
			local peers_with_bytes=0
			local total_peers=0

			# Count total peers and verify byte counters
			# Use a different variable name to avoid overwriting the function parameter
			local iter_location_name
			for iter_location_name in "${!LOCATIONS[@]}"; do
				# Extract external IP using helper function
				local external_peer_ip
				if external_peer_ip=$(get_location_external_ip "$iter_location_name" 2>/dev/null); then
					((total_peers++))
					if verify_byte_counters_resume "$external_peer_ip" "$iter_location_name" 2>/dev/null; then
						((peers_with_bytes++))
					fi
				fi
			done

			if [[ $total_peers -gt 0 ]]; then
				if [[ $peers_with_bytes -eq $total_peers ]]; then
					byte_counters_verified=1
					log_message "INFO" "SYSTEM" "Tier 3: Byte counters resumed for all $total_peers location(s)"
				else
					handle_error "WARNING" "SYSTEM" "Tier 3: Byte counters resumed for only $peers_with_bytes/$total_peers location(s)"
				fi
			else
				# No locations configured - skip byte counter verification
				byte_counters_verified=1
				log_message "INFO" "SYSTEM" "Tier 3: Byte counter verification skipped (no locations configured)"
			fi
		else
			# Failed to parse locations - skip byte counter verification
			byte_counters_verified=1
			log_message "INFO" "SYSTEM" "Tier 3: Byte counter verification skipped (failed to parse location config)"
		fi
	else
		# parse_location_config not available - skip byte counter verification
		byte_counters_verified=1
		log_message "INFO" "SYSTEM" "Tier 3: Byte counter verification skipped (location parsing not available)"
	fi

	local restart_duration
	restart_duration=$(calculate_duration "$restart_start_time")
	local verify_duration
	verify_duration=$(calculate_duration "$verify_start_time")
	# Note: execute_ipsec_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
	log_message "INFO" "$location_name" "Tier 3: Full IPsec restart completed (duration: ${restart_duration}s, verification: ${verify_duration}s, connections: ${connections_verified}, byte counters: ${byte_counters_verified})"
	if [[ $connections_verified -eq 1 ]] && [[ $byte_counters_verified -eq 1 ]]; then
		return 0
	else
		# Clear recovery method since verification failed (prevents stale recovery method from being logged if VPN recovers naturally later)
		if [[ -n "$external_peer_ip" ]] && command -v clear_recovery_method >/dev/null 2>&1; then
			clear_recovery_method "$location_name" "$external_peer_ip"
		fi
		return 1
	fi
}
