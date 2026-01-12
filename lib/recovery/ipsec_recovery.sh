#!/bin/bash
#
# IPsec-based recovery functions for UDM VPN Monitor
# Implements IPsec reload and restart recovery actions
#
# Version: 0.6.0
#

# Source recovery constants for magic numbers
# shellcheck source=lib/recovery/constants.sh
# Determine recovery directory (where this file is located)
RECOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
# Source recovery-specific constants
if ! source "${RECOVERY_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if recovery constants not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	[[ -z "${XFRM_RECOVERY_SLEEP_SECONDS:-}" ]] && readonly XFRM_RECOVERY_SLEEP_SECONDS=3
fi

# Source recovery verification functions
# shellcheck source=lib/recovery/recovery_verification.sh
# RECOVERY_DIR already defined above
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || {
	# Fallback stubs if recovery_verification.sh not available
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

# Source recovery state functions
# shellcheck source=lib/recovery/recovery_state.sh
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || {
	# Fallback stubs if recovery_state.sh not available
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
#   Uses verify_ipsec_connections_active for verification
execute_ipsec_reload() {
	local peer_ip="$1"
	local location_name="$2"
	local reload_start_time
	reload_start_time=$(get_unix_timestamp)
	local command_succeeded=0
	local reload_exit_code=""
	local restart_exit_code=""
	# Use full path to ipsec if available, otherwise rely on PATH
	local ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"

	# Store recovery method before attempting recovery
	local recovery_method_used="ipsec_reload"
	store_recovery_method "$location_name" "$peer_ip" "$recovery_method_used"

	log_message "INFO" "$location_name" "Attempting ipsec reload for $location_name ($peer_ip) (affects all tunnels)"
	if "$ipsec_cmd" reload >/dev/null 2>&1; then
		command_succeeded=1
		log_message "INFO" "$location_name" "Successfully reloaded IPsec connections via ipsec reload for $location_name ($peer_ip)"
	else
		reload_exit_code=$?
		handle_error "WARNING" "$location_name" "ipsec reload failed for $location_name ($peer_ip) (exit code: ${reload_exit_code}), attempting ipsec restart"
		# Update recovery method if fallback to restart
		recovery_method_used="ipsec_restart"
		store_recovery_method "$location_name" "$peer_ip" "$recovery_method_used"
		if "$ipsec_cmd" restart >/dev/null 2>&1; then
			command_succeeded=1
			log_message "INFO" "$location_name" "Successfully restarted IPsec service via ipsec restart for $location_name ($peer_ip)"
		else
			restart_exit_code=$?
			handle_error "ERROR" "$location_name" "ipsec restart also failed for $location_name ($peer_ip) (exit code: ${restart_exit_code})" 0
			command_succeeded=0
		fi
	fi

	# Verify connections are active after reload/restart
	if [[ $command_succeeded -eq 1 ]]; then
		# Wait a moment for connections to re-establish
		sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

		# Verify connections are active (not just that command succeeded)
		if verify_ipsec_connections_active; then
			local current_time
			current_time=$(get_unix_timestamp)
			local reload_duration
			reload_duration=$(safe_timestamp_diff "$current_time" "$reload_start_time" 2>/dev/null || echo "0")
			if [[ $reload_duration -lt 0 ]]; then
				reload_duration=0
			fi
			log_message "INFO" "$location_name" "Recovery completed for $location_name ($peer_ip) (via ipsec fallback, verification: connections active, duration: ${reload_duration}s)"
			return 0
		else
			local current_time
			current_time=$(get_unix_timestamp)
			local reload_duration
			reload_duration=$(safe_timestamp_diff "$current_time" "$reload_start_time" 2>/dev/null || echo "0")
			if [[ $reload_duration -lt 0 ]]; then
				reload_duration=0
			fi
			handle_error "WARNING" "$location_name" "Recovery completed for $location_name ($peer_ip) (via ipsec fallback, verification: some connections not active, duration: ${reload_duration}s)"
			return 1
		fi
	else
		handle_error "WARNING" "$location_name" "Surgical cleanup failed for $location_name ($peer_ip) (ipsec commands failed, exit codes: reload=${reload_exit_code:-unknown}, restart=${restart_exit_code:-unknown})"
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
#   0: Restart successful (command executed successfully)
#   1: Restart failed (command error)
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
	local peer_ip="${1:-}"
	local location_name="$2"

	# Store recovery method before attempting recovery
	if [[ -n "$peer_ip" ]]; then
		store_recovery_method "$location_name" "$peer_ip" "ipsec_restart"
	fi

	log_message "INFO" "$location_name" "Executing ipsec restart for $location_name (affects all tunnels)"
	local restart_start_time
	restart_start_time=$(get_unix_timestamp)
	# Use full path to ipsec if available, otherwise rely on PATH
	local ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"
	# Capture exit code explicitly to avoid PIPESTATUS being cleared
	# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
	"$ipsec_cmd" restart 2>&1 | tee -a "$LOG_FILE"
	local ipsec_exit_code=${PIPESTATUS[0]}
	if [[ $ipsec_exit_code -ne 0 ]]; then
		handle_error "ERROR" "$location_name" "Failed to restart IPsec service for $location_name (exit code: $ipsec_exit_code)" 0
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
		handle_error "WARNING" "$location_name" "Tier 3: Some connections not active after ipsec restart for $location_name"
	fi

	# Verify byte counters resume for all configured locations
	# Parse location configuration to get all external IPs
	if command -v parse_location_config >/dev/null 2>&1; then
		declare -A LOCATIONS
		if parse_location_config; then
			local peers_with_bytes=0
			local total_peers=0

			# Count total peers and verify byte counters
			# Use a different variable name to avoid overwriting the function parameter
			local iter_location_name
			for iter_location_name in "${!LOCATIONS[@]}"; do
				# Extract external IP from location data format: "external:IP|internal:IPs"
				local external_ip=""
				if command -v get_location_external_ip >/dev/null 2>&1; then
					external_ip=$(get_location_external_ip "$iter_location_name" 2>/dev/null || echo "")
				else
					# Fallback: extract from LOCATIONS format directly
					local location_data="${LOCATIONS[$iter_location_name]:-}"
					if [[ "$location_data" =~ external:([^|]+) ]]; then
						external_ip="${BASH_REMATCH[1]:-}"
					fi
				fi
				if [[ -n "$external_ip" ]]; then
					((total_peers++))
					if verify_byte_counters_resume "$external_ip" "$iter_location_name" 2>/dev/null; then
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

	local current_time
	current_time=$(get_unix_timestamp)
	local restart_duration
	restart_duration=$(safe_timestamp_diff "$current_time" "$restart_start_time" 2>/dev/null || echo "0")
	if [[ $restart_duration -lt 0 ]]; then
		restart_duration=0
	fi
	local verify_duration
	verify_duration=$(safe_timestamp_diff "$current_time" "$verify_start_time" 2>/dev/null || echo "0")
	if [[ $verify_duration -lt 0 ]]; then
		verify_duration=0
	fi
	log_message "INFO" "$location_name" "Tier 3: Full IPsec restart completed for $location_name (duration: ${restart_duration}s, verification: ${verify_duration}s, connections: ${connections_verified}, byte counters: ${byte_counters_verified})"
	return 0
}
