#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.0.1
#

# Surgical SA cleanup (Tier 2 recovery)
#
# Attempts to clean up specific Security Associations for a peer by reloading IPsec configuration.
# Prefers swanctl for per-connection reloads when available, falls back to ipsec reload if swanctl is unavailable.
# If a connection name is configured for the peer and swanctl is available, attempts per-connection reload (surgical).
# Otherwise falls back to reloading all IPsec connections (affects all tunnels).
# This is less disruptive than full restart but more aggressive than logging.
#
# Arguments:
#   $1: Peer IP address to clean up (used to find connection name)
#
# Returns:
#   0: Always succeeds (even if cleanup commands fail, errors are logged)
#
# Actions:
#   Reloads IPsec configuration to clean up and re-establish SAs:
#   - If swanctl available and CONNECTION_NAME_<peer_ip> is configured: uses swanctl --reload-conn <name> (per-connection)
#   - If swanctl available but no connection name: uses swanctl --reload (affects all connections)
#   - If swanctl unavailable but ipsec available: uses ipsec reload (affects all connections)
#   - If ipsec reload fails: attempts ipsec restart as last resort
#
# Side effects:
#   - If swanctl available and connection name configured: Calls swanctl --reload-conn (surgical, per-connection)
#   - If swanctl available but no connection name: Calls swanctl --reload (affects all connections)
#   - If swanctl unavailable: Calls ipsec reload (affects all connections, not surgical)
#   - May temporarily disrupt VPN connections (scope depends on tool availability and connection name configuration)
#   - Logs all actions and results
#
# Examples:
#   surgical_cleanup "203.0.113.1"
#   # If swanctl available and CONNECTION_NAME_203_0_113_1="site-to-site-1" is configured:
#   #   Runs: swanctl --reload-conn site-to-site-1
#   # If swanctl available but no connection name:
#   #   Runs: swanctl --reload (affects all tunnels)
#   # If swanctl unavailable but ipsec available:
#   #   Runs: ipsec reload (affects all tunnels)
#
# Note:
#   This function prefers swanctl for per-connection reloads when available.
#   Falls back to ipsec reload if swanctl is not available (many UDMs use ipsec instead of swanctl).
#   Direct xfrm state deletion is not attempted because it requires full selectors (src, dst, proto, spi)
#   which are not easily extractable. swanctl/ipsec reload handles SA cleanup and re-establishment correctly.
#   To enable per-connection reload, configure CONNECTION_NAME_<sanitized_peer_ip> in config file.
#   Example: CONNECTION_NAME_203_0_113_1="site-to-site-1"
#   Requires get_connection_name, warn_if_missing, and log_message to be set
surgical_cleanup() {
	local peer_ip="$1"
	log_message "INFO" "Attempting surgical SA cleanup for $peer_ip"

	# Reload connection using swanctl to clean up and re-establish SAs
	# Falls back to ipsec reload if swanctl is not available
	if command -v swanctl >/dev/null 2>&1; then
		local connection_name
		if connection_name=$(get_connection_name "$peer_ip" 2>/dev/null); then
			# Connection name configured - use per-connection reload
			log_message "INFO" "Using per-connection reload for $peer_ip (connection: $connection_name)"
			if swanctl --reload-conn "$connection_name" 2>/dev/null; then
				log_message "INFO" "Successfully reloaded connection: $connection_name"
			else
				local reload_exit_code=$?
				log_message "WARNING" "Per-connection reload failed for $connection_name (exit code: ${reload_exit_code}), falling back to full reload"
				if swanctl --reload 2>/dev/null; then
					log_message "INFO" "Full reload succeeded after per-connection reload failure"
				else
					local full_reload_exit_code=$?
					log_message "ERROR" "Full reload also failed (exit code: ${full_reload_exit_code})"
				fi
			fi
		else
			# No connection name configured - use full reload (affects all connections)
			log_message "INFO" "No connection name configured for $peer_ip, using full reload (affects all tunnels)"
			swanctl --reload 2>/dev/null || true
		fi
		log_message "INFO" "Surgical cleanup completed for $peer_ip"
	elif command -v ipsec >/dev/null 2>&1; then
		# Fallback to ipsec reload if swanctl is not available
		# Note: ipsec reload affects all connections (not per-connection)
		log_message "INFO" "swanctl not available, using ipsec reload fallback (affects all tunnels)"
		if ipsec reload 2>/dev/null; then
			log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
		else
			log_message "WARNING" "ipsec reload failed, attempting ipsec restart"
			ipsec restart 2>/dev/null || true
		fi
		log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback)"
	else
		# Neither command available
		warn_if_missing "swanctl"
		warn_if_missing "ipsec"
		log_message "ERROR" "Neither swanctl nor ipsec command available for Tier 2 recovery"
	fi
}

# Full VPN restart (Tier 3 recovery)
#
# Performs a full restart of the IPsec service, affecting all VPN tunnels.
# This is the most disruptive recovery action and should only be used after other methods fail.
# Checks rate limiting before proceeding to prevent restart loops.
#
# Returns:
#   0: Restart successful (command executed successfully)
#   1: Restart failed (rate limited or command error)
#
# Actions:
#   1. Checks rate limiting (prevents restart loops via check_rate_limit)
#   2. Records restart timestamp for rate limiting (record_restart)
#   3. Executes 'ipsec restart' or 'swanctl --reload' (prefers ipsec, falls back to swanctl)
#   4. Sets cooldown period to allow VPN to stabilize (set_cooldown)
#
# Side effects:
#   - Affects ALL IPsec tunnels (not just the failing peer)
#   - Temporarily disrupts all Site-to-Site and remote user VPNs
#   - Sets cooldown period (COOLDOWN_MINUTES) to prevent immediate re-restarts
#   - Appends command output to LOG_FILE
#   - Logs all actions and results
#
# Examples:
#   if full_restart; then
#       echo "VPN restarted successfully"
#   else
#       echo "Restart failed or rate limited"
#   fi
#
# Warning:
#   This is disruptive and should be a last resort. Consider adjusting thresholds
#   if this triggers too frequently. Affects all VPN tunnels, not just the failing peer.
#
# Note:
#   Requires check_rate_limit, record_restart, set_cooldown, log_message, LOG_FILE,
#   COOLDOWN_MINUTES, warn_if_missing, die to be set (from state.sh, logging.sh, config.sh)
#   Uses PIPESTATUS to capture command exit code (not tee exit code)
#   Command output is both displayed and appended to log file
full_restart() {
	log_message "WARNING" "Performing full IPsec restart (affects all VPN tunnels)"

	if ! check_rate_limit; then
		log_message "ERROR" "Rate limit exceeded, skipping full restart"
		return 1
	fi

	# Record restart
	record_restart

	# Perform restart
	# Check for commands silently first (we have fallbacks, so only warn if both are missing)
	if command -v ipsec >/dev/null 2>&1; then
		# Capture exit code explicitly to avoid PIPESTATUS being cleared
		# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
		ipsec restart 2>&1 | tee -a "$LOG_FILE"
		local ipsec_exit_code=${PIPESTATUS[0]}
		if [[ $ipsec_exit_code -ne 0 ]]; then
			log_message "ERROR" "Failed to restart IPsec service (exit code: $ipsec_exit_code)"
			return 1
		fi
	elif command -v swanctl >/dev/null 2>&1; then
		# Capture exit code explicitly to avoid PIPESTATUS being cleared
		# PIPESTATUS[0] = exit code of first command in pipe (swanctl), not tee
		swanctl --reload 2>&1 | tee -a "$LOG_FILE"
		local swanctl_exit_code=${PIPESTATUS[0]}
		if [[ $swanctl_exit_code -ne 0 ]]; then
			log_message "ERROR" "Failed to reload swanctl (exit code: $swanctl_exit_code)"
			return 1
		fi
	else
		# Both commands missing - warn about both
		warn_if_missing "ipsec"
		warn_if_missing "swanctl"
		die "Neither ipsec nor swanctl command available"
	fi

	log_message "INFO" "Full IPsec restart completed"
	set_cooldown "$COOLDOWN_MINUTES"
	return 0
}

# Main monitoring function
#
# Monitors a single VPN peer and implements tiered recovery escalation.
# Checks VPN status and escalates recovery actions based on failure count thresholds.
#
# Arguments:
#   $1: Peer IP address to monitor
#
# Returns:
#   0: VPN is healthy (or recovered)
#   1: VPN check failed (or recovery actions taken)
#
# Tier escalation:
#   - Tier 1 (TIER1_THRESHOLD): Logging only
#   - Tier 2 (TIER2_THRESHOLD): Surgical SA cleanup (affects all tunnels)
#   - Tier 3 (TIER3_THRESHOLD): Full IPsec restart (affects all tunnels)
#
# Side effects:
#   - Increments per-peer failure counter on VPN check failure
#   - Resets per-peer failure counter on VPN recovery
#   - Executes recovery actions based on failure count
#   - Logs all actions and status changes
#
# Note:
#   Each peer has its own independent failure counter tracked in:
#   ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
#   This allows independent failure tracking and recovery per peer.
#
#   Requires check_vpn_status, get_failure_count, increment_failure, reset_failure_count,
#   surgical_cleanup, full_restart, log_message, VPN_NAME, TIER1_THRESHOLD, TIER2_THRESHOLD,
#   TIER3_THRESHOLD, NO_ESCALATE to be set
monitor_peer() {
	local peer_ip="$1"
	local failure_count

	# Check VPN status
	if check_vpn_status "$peer_ip"; then
		# VPN is OK
		failure_count=$(get_failure_count "$peer_ip")
		if [[ $failure_count -gt 0 ]]; then
			log_message "INFO" "${VPN_NAME:-VPN} recovered for $peer_ip after $failure_count failures"
			reset_failure_count "$peer_ip"
		fi
		return 0
	else
		# VPN check failed
		failure_count=$(increment_failure "$peer_ip")
		log_message "WARNING" "${VPN_NAME:-VPN} check failed for $peer_ip (failure count: $failure_count)"

		# Tier 1: Logging (triggers when failure_count >= TIER1_THRESHOLD)
		if [[ $failure_count -ge $TIER1_THRESHOLD ]]; then
			log_message "INFO" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $peer_ip"
		fi

		# Tier 2: Surgical cleanup
		if [[ $failure_count -ge $TIER2_THRESHOLD ]] && [[ $failure_count -lt $TIER3_THRESHOLD ]]; then
			if [[ $NO_ESCALATE -eq 1 ]]; then
				log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $peer_ip (skipped in fake mode)"
			else
				log_message "WARNING" "Tier 2: Attempting surgical SA cleanup for $peer_ip"
				surgical_cleanup "$peer_ip"
			fi
		fi

		# Tier 3: Full restart
		if [[ $failure_count -ge $TIER3_THRESHOLD ]]; then
			if [[ $NO_ESCALATE -eq 1 ]]; then
				log_message "INFO" "Tier 3: Would attempt full IPsec restart (skipped in fake mode)"
			else
				log_message "ERROR" "Tier 3: Attempting full IPsec restart"
				if full_restart; then
					reset_failure_count "$peer_ip"
				fi
			fi
		fi

		return 1
	fi
}
