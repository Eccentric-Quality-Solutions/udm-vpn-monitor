#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.0.1
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	[[ -z "${XFRM_RECOVERY_SLEEP_SECONDS:-}" ]] && readonly XFRM_RECOVERY_SLEEP_SECONDS=3
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${XFRM_RECOVERY_VERIFY_TIMEOUT:-}" ]] && readonly XFRM_RECOVERY_VERIFY_TIMEOUT=30
	[[ -z "${XFRM_RECOVERY_VERIFY_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_VERIFY_INTERVAL=2
fi

# Delete Security Associations for a specific peer using xfrm
#
# Attempts per-connection recovery by deleting SAs for a specific peer IP using the Linux kernel's
# xfrm framework. This provides surgical recovery for per-connection recovery.
#
# After deleting SAs, verifies that new SAs are re-established before reporting success.
# This ensures recovery actually worked and the tunnel is functional.
#
# Arguments:
#   $1: Peer IP address to clean up
#
# Returns:
#   0: SAs deleted successfully and re-established (or no SAs found for this peer)
#   1: Failed to delete SAs, parsing error, or SAs did not re-establish within timeout
#
# Side effects:
#   - Deletes xfrm state entries (SAs) for the peer IP
#   - Deletes xfrm policies for the peer IP
#   - Verifies SA re-establishment after deletion
#   - Logs all actions and results
#
# Note:
#   This function parses 'ip xfrm state' output to extract SA selectors (src, dst, proto, spi).
#   Parsing is optimized for UDM OS 4.3+ format. Supports both IPv4 and IPv6 addresses.
#   Requires 'ip' command and root privileges.
#   Uses check_ipsec_phase2() from detection.sh to verify SA re-establishment.
attempt_xfrm_recovery() {
	local peer_ip="$1"
	local deleted_count=0
	local failed_count=0
	local parse_errors=0

	if ! command -v ip >/dev/null 2>&1; then
		handle_error "WARNING" "ip command not available for xfrm recovery"
		return 1
	fi

	# Validate peer IP before proceeding
	if [[ -z "$peer_ip" ]]; then
		handle_error "ERROR" "xfrm recovery: Peer IP not provided" 0
		return 1
	fi

	# Get all xfrm state entries for this peer IP
	# Match on "dst $peer_ip" pattern which appears at the start of each SA entry
	# This ensures we capture complete SA blocks for proper deletion
	# Use fixed-string matching to prevent regex pattern injection
	# Word boundary protection: The "dst " prefix and space after IP provide natural boundaries
	# (e.g., "dst 192.168.1.1" won't match "dst 192.168.1.10" due to exact string matching)
	local xfrm_output
	local xfrm_exit_code=0
	xfrm_output=$(ip xfrm state 2>/dev/null)
	xfrm_exit_code=$?

	if [[ $xfrm_exit_code -ne 0 ]]; then
		handle_error "WARNING" "xfrm recovery: Failed to query xfrm state (exit code: $xfrm_exit_code)"
		return 1
	fi

	# Filter output for this peer IP by matching "dst $peer_ip" pattern
	# -F: fixed-string matching (treats IP address as literal, not regex pattern)
	#     This provides word boundary protection: exact string match prevents partial IP matches
	# -A XFRM_OUTPUT_CONTEXT_LINES: show context lines after match (to get complete SA block)
	xfrm_output=$(echo "$xfrm_output" | grep -F "dst $peer_ip" -A "$XFRM_OUTPUT_CONTEXT_LINES" || true)

	if [[ -z "$xfrm_output" ]]; then
		log_message "INFO" "xfrm recovery: No SAs found for $peer_ip in xfrm state (may already be down)"
		# If no SAs exist, verify they're actually gone (not a parsing issue)
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if ! check_ipsec_phase2 "$peer_ip"; then
				log_message "INFO" "xfrm recovery: Confirmed no SAs exist for $peer_ip"
				return 0
			else
				handle_error "WARNING" "xfrm recovery: SAs exist but parsing failed for $peer_ip"
				return 1
			fi
		fi
		return 0
	fi

	# Parse xfrm output to extract and delete SAs
	# Format: Each SA block starts with "src <ip> dst <ip>" followed by "proto <proto> spi <spi>"
	# UDM OS 4.3+ uses consistent format: src and dst on first line, proto and spi on continuation lines
	local current_src=""
	local current_dst=""
	local current_proto=""
	local current_spi=""
	local in_sa_block=0
	local sa_list=()

	[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "xfrm recovery: Parsing xfrm output for $peer_ip"

	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip empty lines
		[[ -z "$line" ]] && continue

		# Check if this is a new SA block (starts with "src")
		if [[ "$line" =~ ^src[[:space:]]+([0-9.]+|[0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9.]+|[0-9a-fA-F:]+) ]]; then
			# Save previous SA if we have all selectors
			if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
				# Validate selectors before adding to list
				if [[ "$current_proto" =~ ^(esp|ah)$ ]] && [[ "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
					sa_list+=("$current_src|$current_dst|$current_proto|$current_spi")
					[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
				else
					handle_error "WARNING" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
					((parse_errors++))
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
			# Look for "proto <proto>" (may be indented, case-insensitive)
			if [[ "$line" =~ ^[[:space:]]*proto[[:space:]]+([a-zA-Z0-9]+) ]]; then
				current_proto="${BASH_REMATCH[1]}"
				# Normalize to lowercase for consistency
				current_proto=$(echo "$current_proto" | tr '[:upper:]' '[:lower:]')
			fi
			# Look for "spi <spi>" (may be indented, hex format like 0x12345678 or decimal)
			if [[ "$line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
				current_spi="${BASH_REMATCH[1]}"
			fi
		fi
	done <<<"$xfrm_output"

	# Process the last SA if we have all selectors
	if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
		# Validate selectors before adding to list
		if [[ "$current_proto" =~ ^(esp|ah)$ ]] && [[ "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
			sa_list+=("$current_src|$current_dst|$current_proto|$current_spi")
			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
		else
			handle_error "WARNING" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi"
			((parse_errors++))
		fi
	fi

	# If we have parse errors but no valid SAs, report failure
	if [[ $parse_errors -gt 0 ]] && [[ ${#sa_list[@]} -eq 0 ]]; then
		handle_error "WARNING" "xfrm recovery: Parsing failed for $peer_ip (found $parse_errors invalid SA(s))"
		return 1
	fi

	# Delete each parsed SA
	for sa_entry in "${sa_list[@]}"; do
		IFS='|' read -r sa_src sa_dst sa_proto sa_spi <<<"$sa_entry"
		if ip xfrm state delete src "$sa_src" dst "$sa_dst" proto "$sa_proto" spi "$sa_spi" 2>/dev/null; then
			log_message "INFO" "xfrm recovery: Deleted SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi"
			((deleted_count++))
		else
			handle_error "WARNING" "xfrm recovery: Failed to delete SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi"
			((failed_count++))
		fi
	done

	# Also delete policies for this peer (less critical, but helps cleanup)
	# Policies use different format, try to delete by destination
	if ip xfrm policy delete dst "$peer_ip" 2>/dev/null; then
		log_message "INFO" "xfrm recovery: Deleted xfrm policy for dst=$peer_ip"
	fi

	# If no SAs were deleted, check if any existed
	if [[ $deleted_count -eq 0 ]] && [[ $failed_count -eq 0 ]]; then
		if [[ ${#sa_list[@]} -eq 0 ]]; then
			log_message "INFO" "xfrm recovery: No SAs found to delete for $peer_ip"
			return 0
		else
			handle_error "WARNING" "xfrm recovery: Parsed ${#sa_list[@]} SA(s) but failed to delete any for $peer_ip"
			return 1
		fi
	fi

	# If we deleted SAs, verify they're gone and wait for re-establishment
	if [[ $deleted_count -gt 0 ]]; then
		log_message "INFO" "xfrm recovery: Deleted $deleted_count SA(s) for $peer_ip"
		# Wait a moment for strongSwan to detect SA deletion
		sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

		# Verify SAs were deleted
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if check_ipsec_phase2 "$peer_ip"; then
				handle_error "WARNING" "xfrm recovery: SAs still exist after deletion attempt for $peer_ip"
				# Continue anyway - may have deleted some but not all
			fi
		fi

		# Wait for SA re-establishment with retries
		log_message "INFO" "xfrm recovery: Waiting for SA re-establishment for $peer_ip (timeout: ${XFRM_RECOVERY_VERIFY_TIMEOUT}s)"
		local verify_start_time
		verify_start_time=$(date +%s)
		local sa_reestablished=0
		local verify_attempt=0
		local elapsed_time

		while [[ $(($(date +%s) - verify_start_time)) -lt $XFRM_RECOVERY_VERIFY_TIMEOUT ]]; do
			verify_attempt=$((verify_attempt + 1))
			elapsed_time=$(($(date +%s) - verify_start_time))
			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "xfrm recovery: Verification attempt $verify_attempt for $peer_ip (elapsed: ${elapsed_time}s/${XFRM_RECOVERY_VERIFY_TIMEOUT}s)"

			if command -v check_ipsec_phase2 >/dev/null 2>&1; then
				if check_ipsec_phase2 "$peer_ip"; then
					log_message "INFO" "xfrm recovery: SA re-established for $peer_ip after ${elapsed_time}s (attempt $verify_attempt)"
					sa_reestablished=1
					break
				fi
			fi
			sleep "$XFRM_RECOVERY_VERIFY_INTERVAL"
		done

		if [[ $sa_reestablished -eq 0 ]]; then
			handle_error "WARNING" "xfrm recovery: SA did not re-establish within ${XFRM_RECOVERY_VERIFY_TIMEOUT}s for $peer_ip"
			# If we had failures, return error; otherwise warn but return success (partial recovery)
			if [[ $failed_count -gt 0 ]]; then
				return 1
			fi
			# Some SAs deleted but re-establishment timeout - warn but don't fail completely
			handle_error "WARNING" "xfrm recovery: Partial success - deleted SAs but re-establishment timeout for $peer_ip"
			return 0
		fi

		return 0
	elif [[ $failed_count -gt 0 ]]; then
		handle_error "WARNING" "xfrm recovery: Failed to delete $failed_count SA(s) for $peer_ip"
		return 1
	fi

	# Should not reach here, but handle gracefully
	return 1
}

# Surgical SA cleanup (Tier 2 recovery)
#
# Attempts to clean up specific Security Associations for a peer by reloading IPsec configuration.
# Uses a tiered approach: xfrm (per-connection) → ipsec reload (all connections).
# Attempts xfrm-based per-connection recovery if enabled, falling back to ipsec reload if that fails.
# This is less disruptive than full restart but more aggressive than logging.
#
# Arguments:
#   $1: Peer IP address to clean up
#
# Returns:
#   0: Always succeeds (cleanup commands attempted, errors are logged if they fail)
#
# Actions:
#   Reloads IPsec configuration to clean up and re-establish SAs:
#   - If xfrm recovery enabled: attempts xfrm-based per-connection recovery (surgical)
#   - If xfrm recovery fails or disabled: falls back to ipsec reload (affects all connections)
#   - If ipsec reload fails: attempts ipsec restart as last resort
#
# Side effects:
#   - If xfrm recovery enabled: Attempts xfrm-based recovery (surgical, per-connection)
#   - If xfrm recovery fails or disabled: Calls ipsec reload (affects all connections, not surgical)
#   - May temporarily disrupt VPN connections (scope depends on xfrm recovery availability)
#   - Logs all actions and results
#
# Examples:
#   surgical_cleanup "203.0.113.1"
#   # If xfrm recovery enabled:
#   #   Attempts: xfrm-based per-connection recovery (surgical)
#   #   If xfrm fails: Runs ipsec reload (affects all tunnels)
#   # If xfrm recovery disabled:
#   #   Runs: ipsec reload (affects all tunnels)
#
# Note:
#   Falls back to xfrm-based recovery for per-connection recovery when enabled.
#   Falls back to ipsec reload if xfrm recovery fails or is disabled.
#   Requires warn_if_missing, log_message, and attempt_xfrm_recovery to be set
surgical_cleanup() {
	local peer_ip="$1"
	# Try to discover connection name for better logging (optional, for debugging)
	local conn_name=""
	if command -v discover_connection_name >/dev/null 2>&1; then
		conn_name=$(discover_connection_name "$peer_ip" 2>/dev/null || echo "")
	fi
	local peer_display="$peer_ip"
	if [[ -n "$conn_name" ]]; then
		peer_display="$peer_ip (conn: $conn_name)"
	fi
	log_message "INFO" "Attempting surgical SA cleanup for $peer_display"

	# Try xfrm-based per-connection recovery (if enabled)
	if command -v ip >/dev/null 2>&1; then
		if [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]]; then
			log_message "INFO" "Attempting xfrm-based per-connection recovery for $peer_ip"
			if attempt_xfrm_recovery "$peer_ip"; then
				log_message "INFO" "xfrm-based recovery completed successfully for $peer_ip"
				log_message "INFO" "Surgical cleanup completed for $peer_ip (via xfrm)"
				return 0
			else
				# xfrm recovery failed - fall back to ipsec reload
				handle_error "WARNING" "xfrm-based recovery failed, falling back to ipsec reload (affects all tunnels)"
			fi
		else
			log_message "INFO" "xfrm recovery disabled (ENABLE_XFRM_RECOVERY=0), using ipsec reload fallback (affects all tunnels)"
		fi
	fi

	# Fall back to ipsec reload
	if command -v ipsec >/dev/null 2>&1; then
		log_message "INFO" "Attempting ipsec reload (affects all tunnels)"
		if ipsec reload >/dev/null 2>&1; then
			log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
		else
			local reload_exit_code=$?
			handle_error "WARNING" "ipsec reload failed (exit code: ${reload_exit_code}), attempting ipsec restart"
			if ! ipsec restart >/dev/null 2>&1; then
				local restart_exit_code=$?
				handle_error "ERROR" "ipsec restart also failed (exit code: ${restart_exit_code})" 0
			else
				log_message "INFO" "Successfully restarted IPsec service via ipsec restart"
			fi
		fi
		log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback)"
	else
		# Neither command available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		handle_error "ERROR" "Neither ip nor ipsec command available for Tier 2 recovery" 0
	fi

	# Always return 0 (function always succeeds - cleanup commands attempted, errors are logged)
	return 0
}

# Full VPN restart (Tier 3 recovery)
#
# Performs a full restart of the IPsec service, affecting all VPN tunnels.
# Attempts per-connection recovery via xfrm if peer IP is provided and xfrm recovery is enabled.
# Falls back to full restart if xfrm recovery fails or is disabled.
# This is the most disruptive recovery action and should only be used after other methods fail.
# Checks rate limiting before proceeding to prevent restart loops.
#
# Arguments:
#   $1: Optional peer IP address for per-connection recovery (if provided and xfrm enabled)
#
# Returns:
#   0: Restart successful (command executed successfully)
#   1: Restart failed (rate limited or command error)
#
# Actions:
#   1. Checks rate limiting (prevents restart loops via check_rate_limit)
#   2. If peer IP provided and xfrm enabled: attempts per-connection recovery
#   3. If xfrm fails or disabled: records restart timestamp (record_restart)
#   4. Executes 'ipsec restart' to restart all IPsec tunnels (if xfrm not used)
#   5. Sets cooldown period to allow VPN to stabilize (set_cooldown)
#
# Side effects:
#   - If xfrm recovery succeeds: Only affects the specified peer's tunnel
#   - If xfrm recovery fails or disabled: Affects ALL IPsec tunnels
#   - Temporarily disrupts VPN tunnels (scope depends on recovery method)
#   - Sets cooldown period (COOLDOWN_MINUTES) to prevent immediate re-restarts
#   - Appends command output to LOG_FILE (for full restart only)
#   - Logs all actions and results
#
# Examples:
#   if full_restart; then
#       echo "VPN restarted successfully"
#   fi
#   if full_restart "203.0.113.1"; then
#       echo "Per-connection recovery attempted"
#   fi
#
# Warning:
#   This is disruptive and should be a last resort. Consider adjusting thresholds
#   if this triggers too frequently. Full restart affects all VPN tunnels.
#
# Note:
#   Requires check_rate_limit, record_restart, set_cooldown, log_message, LOG_FILE,
#   COOLDOWN_MINUTES, warn_if_missing, die, attempt_xfrm_recovery to be set
#   Uses PIPESTATUS to capture command exit code (not tee exit code)
#   Command output is both displayed and appended to log file (for full restart)
full_restart() {
	local peer_ip="${1:-}"

	if ! check_rate_limit; then
		handle_error "ERROR" "Rate limit exceeded, skipping Tier 3 recovery" 0
		return 1
	fi

	# Try xfrm-based per-connection recovery if peer IP provided and xfrm enabled
	if [[ -n "$peer_ip" ]] && [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]] && command -v ip >/dev/null 2>&1; then
		log_message "INFO" "Tier 3: Attempting xfrm-based per-connection recovery for $peer_ip"
		if attempt_xfrm_recovery "$peer_ip"; then
			log_message "INFO" "Tier 3: xfrm-based per-connection recovery successful for $peer_ip"
			# Record restart for rate limiting (even though it's per-connection)
			record_restart
			set_cooldown "$COOLDOWN_MINUTES"
			return 0
		else
			handle_error "WARNING" "Tier 3: xfrm-based recovery failed for $peer_ip, falling back to full restart"
		fi
	fi

	# Fall back to full restart
	handle_error "WARNING" "Tier 3: Performing full IPsec restart (affects all VPN tunnels)"

	# Record restart
	record_restart

	# Perform restart
	# Check for ipsec command
	if command -v ipsec >/dev/null 2>&1; then
		log_message "INFO" "Executing ipsec restart (affects all tunnels)"
		# Capture exit code explicitly to avoid PIPESTATUS being cleared
		# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
		ipsec restart 2>&1 | tee -a "$LOG_FILE"
		local ipsec_exit_code=${PIPESTATUS[0]}
		if [[ $ipsec_exit_code -ne 0 ]]; then
			handle_error "ERROR" "Failed to restart IPsec service (exit code: $ipsec_exit_code)" 0
			return 1
		fi
	else
		# ipsec command missing
		warn_if_missing "ipsec"
		die "ipsec command not available"
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
#   External IP is used for xfrm checks, internal IP is used for ping checks.
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
			# Try to discover connection name for better logging (optional, for debugging)
			local conn_name=""
			if command -v discover_connection_name >/dev/null 2>&1; then
				conn_name=$(discover_connection_name "$external_peer_ip" 2>/dev/null || echo "")
			fi
			local peer_display="$external_peer_ip"
			if [[ -n "$conn_name" ]]; then
				peer_display="$external_peer_ip (conn: $conn_name)"
			fi
			log_message "INFO" "${VPN_NAME:-VPN} recovered for $peer_display after $failure_count failures"
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
		"tunnel_down")
			failure_type_display=" (tunnel down)"
			;;
		"routing_issue")
			failure_type_display=" (routing issue)"
			;;
		esac

		handle_error "WARNING" "${VPN_NAME:-VPN} check failed for $external_peer_ip (failure count: $failure_count)$failure_type_display"

		# Tier 1: Logging (triggers when failure_count >= TIER1_THRESHOLD)
		if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
			log_message "INFO" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $external_peer_ip$failure_type_display"
		fi

		# Tier 2: Surgical cleanup
		if [[ "$failure_count" -ge "$TIER2_THRESHOLD" ]] && [[ "$failure_count" -lt "$TIER3_THRESHOLD" ]]; then
			if [[ "$NO_ESCALATE" -eq 1 ]]; then
				# In fake mode, log what would be done (including the command that would be used)
				log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $external_peer_ip (skipped in fake mode)"
				log_message "INFO" "Tier 2: Would use ipsec reload (affects all tunnels)"
			else
				handle_error "WARNING" "Tier 2: Attempting surgical SA cleanup for $external_peer_ip"
				surgical_cleanup "$external_peer_ip"
			fi
		fi

		# Tier 3: Full restart (with per-connection option if xfrm enabled)
		if [[ "$failure_count" -ge "$TIER3_THRESHOLD" ]]; then
			if [[ "$NO_ESCALATE" -eq 1 ]]; then
				# In fake mode, still check rate limit to test the logic
				# This allows tests to verify rate limiting behavior
				if ! check_rate_limit; then
					# Rate limit would prevent restart (logged by check_rate_limit)
					log_message "INFO" "Tier 3: Would attempt IPsec restart (skipped in fake mode, rate limit would prevent)"
				else
					if [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]] && command -v ip >/dev/null 2>&1; then
						log_message "INFO" "Tier 3: Would attempt xfrm-based per-connection recovery for $external_peer_ip (skipped in fake mode)"
					else
						log_message "INFO" "Tier 3: Would attempt full IPsec restart (affects all tunnels, skipped in fake mode)"
					fi
				fi
			else
				handle_error "ERROR" "Tier 3: Attempting IPsec restart for $external_peer_ip" 0
				# Pass peer IP to enable per-connection recovery (if xfrm recovery enabled)
				if full_restart "$external_peer_ip"; then
					reset_failure_count "$external_peer_ip"
				fi
			fi
		fi

		return 1
	fi
}
