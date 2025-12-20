#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.0.1
#

# Delete Security Associations for a specific peer using xfrm
#
# Attempts per-connection recovery by deleting SAs for a specific peer IP using the Linux kernel's
# xfrm framework. This provides surgical recovery without requiring swanctl.
#
# ⚠️ WARNING: This is an EXPERIMENTAL feature with known risks:
#   - xfrm output format varies across kernel versions (parsing may fail)
#   - May not trigger IKE re-establishment automatically in all cases
#   - Risk of leaving orphaned SAs/policies if parsing fails
#   - Different behavior across kernel versions and UDM models
#   - Requires extensive testing (not yet fully validated)
#
# This function should only be used when:
#   1. ENABLE_XFRM_RECOVERY=1 is explicitly set in configuration
#   2. swanctl is not available (otherwise swanctl is preferred)
#   3. User understands the risks and has tested on their system
#
# Arguments:
#   $1: Peer IP address to clean up
#
# Returns:
#   0: SAs deleted successfully (or no SAs found for this peer)
#   1: Failed to delete SAs (parsing error, permission issue, etc.)
#
# Side effects:
#   - Deletes xfrm state entries (SAs) for the peer IP
#   - Deletes xfrm policies for the peer IP
#   - Logs all actions and results
#
# Note:
#   This function parses 'ip xfrm state' output to extract SA selectors (src, dst, proto, spi).
#   Format variations across kernel versions may affect reliability. Falls back gracefully if parsing fails.
#   Requires 'ip' command and root privileges.
#   See architecture-docs/SWANCTL_ALTERNATIVES.md for detailed risk analysis.
attempt_xfrm_recovery() {
	local peer_ip="$1"
	local deleted_count=0
	local failed_count=0

	if ! command -v ip >/dev/null 2>&1; then
		log_message "WARNING" "ip command not available for xfrm recovery"
		return 1
	fi

	log_message "INFO" "Attempting xfrm-based per-connection recovery for $peer_ip"

	# Get all xfrm state entries for this peer IP
	# Use word boundaries to avoid partial IP matches
	local xfrm_output
	xfrm_output=$(ip xfrm state 2>/dev/null | grep -E "(^|[^0-9a-fA-F:])${peer_ip}([^0-9a-fA-F:]|$)" -A 20 || true)

	if [[ -z "$xfrm_output" ]]; then
		log_message "INFO" "No SAs found for $peer_ip in xfrm state (may already be down)"
		return 0
	fi

	# Parse xfrm output to extract and delete SAs
	# Format: Each SA block starts with "src <ip> dst <ip>" followed by "proto <proto> spi <spi>"
	local current_src=""
	local current_dst=""
	local current_proto=""
	local current_spi=""
	local in_sa_block=0

	while IFS= read -r line; do
		# Check if this is a new SA block (starts with "src")
		if [[ "$line" =~ ^src[[:space:]]+([0-9.]+|[0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9.]+|[0-9a-fA-F:]+) ]]; then
			# Save previous SA if we have all selectors
			if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
				# Delete this SA
				if ip xfrm state delete src "$current_src" dst "$current_dst" proto "$current_proto" spi "$current_spi" 2>/dev/null; then
					log_message "INFO" "Deleted SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
					((deleted_count++))
				else
					log_message "WARNING" "Failed to delete SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
					((failed_count++))
				fi
			fi

			# Start new SA block
			current_src="${BASH_REMATCH[1]}"
			current_dst="${BASH_REMATCH[2]}"
			current_proto=""
			current_spi=""
			in_sa_block=1

		# Extract proto and spi from continuation lines
		elif [[ $in_sa_block -eq 1 ]]; then
			# Look for "proto <proto>" (may be indented)
			if [[ "$line" =~ proto[[:space:]]+([a-zA-Z0-9]+) ]]; then
				current_proto="${BASH_REMATCH[1]}"
			fi
			# Look for "spi <spi>" (may be indented, hex format like 0x12345678)
			if [[ "$line" =~ spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
				current_spi="${BASH_REMATCH[1]}"
			fi
		fi
	done <<<"$xfrm_output"

	# Delete the last SA if we have all selectors
	if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
		if ip xfrm state delete src "$current_src" dst "$current_dst" proto "$current_proto" spi "$current_spi" 2>/dev/null; then
			log_message "INFO" "Deleted SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
			((deleted_count++))
		else
			log_message "WARNING" "Failed to delete SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
			((failed_count++))
		fi
	fi

	# Also delete policies for this peer (less critical, but helps cleanup)
	# Policies use different format, try to delete by destination
	if ip xfrm policy delete dst "$peer_ip" 2>/dev/null; then
		log_message "INFO" "Deleted xfrm policy for dst=$peer_ip"
	fi

	if [[ $deleted_count -gt 0 ]]; then
		log_message "INFO" "xfrm recovery: Deleted $deleted_count SA(s) for $peer_ip"
		# Wait a moment for strongSwan to detect SA deletion and re-establish
		sleep 3
		return 0
	elif [[ $failed_count -gt 0 ]]; then
		log_message "WARNING" "xfrm recovery: Failed to delete $failed_count SA(s) for $peer_ip"
		return 1
	else
		log_message "INFO" "xfrm recovery: No SAs found to delete for $peer_ip"
		return 0
	fi
}

# Surgical SA cleanup (Tier 2 recovery)
#
# Attempts to clean up specific Security Associations for a peer by reloading IPsec configuration.
# Uses a tiered approach: swanctl (per-connection) → xfrm (per-connection) → ipsec reload (all connections).
# If a connection name is configured for the peer and swanctl is available, attempts per-connection reload (surgical).
# Otherwise attempts xfrm-based per-connection recovery, falling back to ipsec reload if that fails.
# This is less disruptive than full restart but more aggressive than logging.
#
# Arguments:
#   $1: Peer IP address to clean up (used to find connection name)
#
# Returns:
#   0: Always succeeds (cleanup commands attempted, errors are logged if they fail)
#
# Actions:
#   Reloads IPsec configuration to clean up and re-establish SAs:
#   - If swanctl available and CONNECTION_NAME_<peer_ip> is configured: uses swanctl --reload-conn <name> (per-connection)
#   - If swanctl available but no connection name: uses swanctl --reload (affects all connections)
#   - If swanctl unavailable: attempts xfrm-based per-connection recovery (surgical)
#   - If xfrm recovery fails: falls back to ipsec reload (affects all connections)
#   - If ipsec reload fails: attempts ipsec restart as last resort
#
# Side effects:
#   - If swanctl available and connection name configured: Calls swanctl --reload-conn (surgical, per-connection)
#   - If swanctl available but no connection name: Calls swanctl --reload (affects all connections)
#   - If swanctl unavailable: Attempts xfrm-based recovery (surgical, per-connection)
#   - If xfrm recovery fails: Calls ipsec reload (affects all connections, not surgical)
#   - May temporarily disrupt VPN connections (scope depends on tool availability and connection name configuration)
#   - Logs all actions and results
#
# Examples:
#   surgical_cleanup "203.0.113.1"
#   # If swanctl available and CONNECTION_NAME_203_0_113_1="site-to-site-1" is configured:
#   #   Runs: swanctl --reload-conn site-to-site-1
#   # If swanctl available but no connection name:
#   #   Runs: swanctl --reload (affects all tunnels)
#   # If swanctl unavailable:
#   #   Attempts: xfrm-based per-connection recovery (surgical)
#   #   If xfrm fails: Runs ipsec reload (affects all tunnels)
#
# Note:
#   This function prefers swanctl for per-connection reloads when available.
#   Falls back to xfrm-based recovery for per-connection recovery when swanctl is unavailable.
#   Falls back to ipsec reload if xfrm recovery fails (many UDMs use ipsec instead of swanctl).
#   To enable per-connection reload with swanctl, configure CONNECTION_NAME_<sanitized_peer_ip> in config file.
#   Example: CONNECTION_NAME_203_0_113_1="site-to-site-1"
#   Requires get_connection_name, warn_if_missing, log_message, and attempt_xfrm_recovery to be set
surgical_cleanup() {
	local peer_ip="$1"
	log_message "INFO" "Attempting surgical SA cleanup for $peer_ip"

	# Reload connection using swanctl to clean up and re-establish SAs
	# Falls back to xfrm-based recovery if swanctl is not available
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
			if ! swanctl --reload 2>&1; then
				local reload_exit_code=$?
				log_message "ERROR" "swanctl --reload failed (exit code: ${reload_exit_code})"
			else
				log_message "INFO" "Successfully reloaded all connections via swanctl --reload"
			fi
		fi
		log_message "INFO" "Surgical cleanup completed for $peer_ip"
	elif command -v ip >/dev/null 2>&1; then
		# swanctl not available - try xfrm-based per-connection recovery (if enabled)
		if [[ "${ENABLE_XFRM_RECOVERY:-0}" -eq 1 ]]; then
			log_message "INFO" "swanctl not available, attempting xfrm-based per-connection recovery for $peer_ip (EXPERIMENTAL)"
			if attempt_xfrm_recovery "$peer_ip"; then
				log_message "INFO" "xfrm-based recovery completed for $peer_ip"
			else
				# xfrm recovery failed - fall back to ipsec reload
				log_message "WARNING" "xfrm-based recovery failed, falling back to ipsec reload (affects all tunnels)"
				if command -v ipsec >/dev/null 2>&1; then
					if ipsec reload 2>&1; then
						log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
					else
						local reload_exit_code=$?
						log_message "WARNING" "ipsec reload failed (exit code: ${reload_exit_code}), attempting ipsec restart"
						if ! ipsec restart 2>&1; then
							local restart_exit_code=$?
							log_message "ERROR" "ipsec restart also failed (exit code: ${restart_exit_code})"
						else
							log_message "INFO" "Successfully restarted IPsec service via ipsec restart"
						fi
					fi
				else
					log_message "ERROR" "Neither ipsec command available for fallback recovery"
				fi
			fi
			log_message "INFO" "Surgical cleanup completed for $peer_ip (via xfrm/ipsec fallback)"
		else
			# xfrm recovery disabled - skip directly to ipsec reload
			log_message "INFO" "swanctl not available, xfrm recovery disabled (ENABLE_XFRM_RECOVERY=0), using ipsec reload fallback (affects all tunnels)"
			if command -v ipsec >/dev/null 2>&1; then
				if ipsec reload 2>&1; then
					log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
				else
					local reload_exit_code=$?
					log_message "WARNING" "ipsec reload failed (exit code: ${reload_exit_code}), attempting ipsec restart"
					if ! ipsec restart 2>&1; then
						local restart_exit_code=$?
						log_message "ERROR" "ipsec restart also failed (exit code: ${restart_exit_code})"
					else
						log_message "INFO" "Successfully restarted IPsec service via ipsec restart"
					fi
				fi
			else
				log_message "ERROR" "Neither ipsec command available for fallback recovery"
			fi
			log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback, xfrm disabled)"
		fi
	elif command -v ipsec >/dev/null 2>&1; then
		# Neither swanctl nor ip available - fall back to ipsec reload
		log_message "INFO" "swanctl and ip commands not available, using ipsec reload fallback (affects all tunnels)"
		if ipsec reload 2>&1; then
			log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
		else
			local reload_exit_code=$?
			log_message "WARNING" "ipsec reload failed (exit code: ${reload_exit_code}), attempting ipsec restart"
			if ! ipsec restart 2>&1; then
				local restart_exit_code=$?
				log_message "ERROR" "ipsec restart also failed (exit code: ${restart_exit_code})"
			else
				log_message "INFO" "Successfully restarted IPsec service via ipsec restart"
			fi
		fi
		log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback)"
	else
		# Neither command available
		warn_if_missing "swanctl"
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		log_message "ERROR" "Neither swanctl, ip, nor ipsec command available for Tier 2 recovery"
	fi

	# Always return 0 (function always succeeds - cleanup commands attempted, errors are logged)
	return 0
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
#   $1: External peer IP address to monitor (used for xfrm state checks)
#   $2: Internal peer IP address (optional, used for ping checks, falls back to external if not provided)
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
#   External IP is used for xfrm/swanctl checks, internal IP is used for ping checks.
#
#   Requires check_vpn_status, get_failure_count, increment_failure, reset_failure_count,
#   surgical_cleanup, full_restart, log_message, VPN_NAME, TIER1_THRESHOLD, TIER2_THRESHOLD,
#   TIER3_THRESHOLD, NO_ESCALATE to be set
monitor_peer() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local failure_count

	# Check VPN status (uses external IP for xfrm, internal IP for ping)
	if check_vpn_status "$external_peer_ip" "$internal_peer_ip"; then
		# VPN is OK
		failure_count=$(get_failure_count "$external_peer_ip")
		if [[ "$failure_count" -gt 0 ]]; then
			log_message "INFO" "${VPN_NAME:-VPN} recovered for $external_peer_ip after $failure_count failures"
			reset_failure_count "$external_peer_ip"

			# Clear failure type file on recovery
			if command -v sanitize_peer_ip >/dev/null 2>&1; then
				local peer_sanitized
				peer_sanitized=$(sanitize_peer_ip "$external_peer_ip")
				local failure_type_file="${STATE_DIR}/failure_type_${peer_sanitized}"
				if [[ -f "$failure_type_file" ]]; then
					rm -f "$failure_type_file" 2>/dev/null || true
				fi
			fi
		fi
		return 0
	else
		# VPN check failed
		failure_count=$(increment_failure "$external_peer_ip")

		# Get failure type for more detailed logging
		local failure_type="unknown"
		if command -v get_failure_type >/dev/null 2>&1; then
			failure_type=$(get_failure_type "$external_peer_ip" 2>/dev/null || echo "unknown")
		fi

		# Format failure type for display
		local failure_type_display=""
		case "$failure_type" in
		"ike_phase1_down")
			failure_type_display=" (IKE Phase 1 down)"
			;;
		"ipsec_phase2_down")
			failure_type_display=" (IPsec Phase 2 down)"
			;;
		"routing_issue")
			failure_type_display=" (routing issue)"
			;;
		esac

		log_message "WARNING" "${VPN_NAME:-VPN} check failed for $external_peer_ip (failure count: $failure_count)$failure_type_display"

		# Tier 1: Logging (triggers when failure_count >= TIER1_THRESHOLD)
		if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
			log_message "INFO" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $external_peer_ip$failure_type_display"
		fi

		# Tier 2: Surgical cleanup
		if [[ "$failure_count" -ge "$TIER2_THRESHOLD" ]] && [[ "$failure_count" -lt "$TIER3_THRESHOLD" ]]; then
			if [[ "$NO_ESCALATE" -eq 1 ]]; then
				log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $external_peer_ip (skipped in fake mode)"
			else
				log_message "WARNING" "Tier 2: Attempting surgical SA cleanup for $external_peer_ip"
				surgical_cleanup "$external_peer_ip"
			fi
		fi

		# Tier 3: Full restart
		if [[ "$failure_count" -ge "$TIER3_THRESHOLD" ]]; then
			if [[ "$NO_ESCALATE" -eq 1 ]]; then
				log_message "INFO" "Tier 3: Would attempt full IPsec restart (skipped in fake mode)"
			else
				log_message "ERROR" "Tier 3: Attempting full IPsec restart"
				if full_restart; then
					reset_failure_count "$external_peer_ip"
				fi
			fi
		fi

		return 1
	fi
}
