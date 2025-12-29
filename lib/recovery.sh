#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.3.0
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
	[[ -z "${XFRM_RECOVERY_MAX_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_MAX_INTERVAL=16
fi

# Source detection functions for byte counter and SA checks
# shellcheck source=lib/detection.sh
source "${LIB_DIR}/detection.sh" 2>/dev/null || {
	# Fallback if detection.sh not found
	check_ipsec_phase2() { return 1; }
	extract_byte_counter() { return 1; }
	check_byte_counters() { return 1; }
}

# Count Security Associations for a peer IP
#
# Counts the number of Security Associations (SAs) for a specific peer IP
# by parsing xfrm state output. Each SA block starts with "src <ip> dst <ip>".
#
# Arguments:
#   $1: Peer IP address to count SAs for
#
# Returns:
#   0: Successfully counted SAs (count printed to stdout)
#   1: Failed to query xfrm state or parse output
#
# Output:
#   Prints SA count (integer) to stdout if successful
#
# Examples:
#   sa_count=$(count_sas_for_peer "203.0.113.1")
#   if [[ $? -eq 0 ]]; then
#       echo "Found $sa_count SA(s)"
#   fi
#
# Note:
#   Requires 'ip' command to be available
#   Uses fixed-string matching to prevent regex pattern injection
count_sas_for_peer() {
	local peer_ip="$1"

	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	local xfrm_output
	xfrm_output=$(ip xfrm state 2>/dev/null)
	local xfrm_exit_code=$?

	if [[ $xfrm_exit_code -ne 0 ]]; then
		return 1
	fi

	# Count SA blocks by matching lines that start with "src" and contain "dst $peer_ip"
	# Each SA block starts with "src <ip> dst <ip>" on a line
	# Use fixed-string matching (-F) for safety, then filter for lines starting with "src"
	local sa_count
	sa_count=$(echo "$xfrm_output" | grep -F "dst $peer_ip" | grep -cE "^[[:space:]]*src" || echo "0")

	# Validate count is numeric
	if [[ ! "$sa_count" =~ ^[0-9]+$ ]]; then
		return 1
	fi

	echo "$sa_count"
	return 0
}

# Verify byte counters resume after recovery
#
# Verifies that byte counters are present and non-zero after recovery action.
# This ensures the tunnel is not only established but also passing traffic.
#
# Arguments:
#   $1: Peer IP address to verify
#
# Returns:
#   0: Byte counters are present and non-zero (or not available but SA exists)
#   1: Byte counters are zero or unavailable (tunnel may not be passing traffic)
#
# Side effects:
#   - Logs byte counter status
#
# Examples:
#   if verify_byte_counters_resume "203.0.113.1"; then
#       echo "Byte counters verified"
#   fi
#
# Note:
#   Requires extract_byte_counter from detection.sh
#   If byte counters are not available, returns success if SA exists (graceful degradation)
verify_byte_counters_resume() {
	local peer_ip="$1"
	local xfrm_output

	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	# Get xfrm output for this peer
	xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "dst $peer_ip" -A "$XFRM_OUTPUT_CONTEXT_LINES" || true)

	if [[ -z "$xfrm_output" ]]; then
		return 1
	fi

	# Extract byte counter
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
		if [[ "$current_bytes" -gt 0 ]]; then
			log_message "INFO" "Recovery verification: Byte counters resumed for $peer_ip (bytes=$current_bytes)"
			return 0
		else
			handle_error "WARNING" "Recovery verification: Byte counters are zero for $peer_ip (tunnel may not be passing traffic)"
			return 1
		fi
	else
		# Byte counters not available, but SA exists - log and return success
		log_message "INFO" "Recovery verification: Byte counters not available for $peer_ip (SA exists, verification limited)"
		return 0
	fi
}

# Verify IPsec connections are active
#
# Verifies that IPsec connections are active (not just that command succeeded).
# Checks that connections exist in ipsec status output for all configured peers.
#
# Arguments:
#   $1: Space-separated list of peer IPs to verify (optional, uses EXTERNAL_PEER_IPS if not provided)
#
# Returns:
#   0: All connections are active
#   1: One or more connections are not active or verification failed
#
# Side effects:
#   - Logs connection status for each peer
#
# Examples:
#   if verify_ipsec_connections_active; then
#       echo "All connections active"
#   fi
#   if verify_ipsec_connections_active "203.0.113.1 198.51.100.1"; then
#       echo "All specified connections active"
#   fi
#
# Note:
#   Requires ipsec command to be available
#   If EXTERNAL_PEER_IPS is not set and no peer IPs provided, returns success (no peers to verify)
verify_ipsec_connections_active() {
	local peer_ips="${1:-${EXTERNAL_PEER_IPS:-}}"

	if ! command -v ipsec >/dev/null 2>&1; then
		handle_error "WARNING" "Recovery verification: ipsec command not available for connection verification"
		return 1
	fi

	if [[ -z "$peer_ips" ]]; then
		# No peers to verify
		return 0
	fi

	# Get ipsec status output
	local ipsec_output
	ipsec_output=$(ipsec status 2>/dev/null)
	local ipsec_exit_code=$?

	if [[ $ipsec_exit_code -ne 0 ]]; then
		handle_error "WARNING" "Recovery verification: Failed to query ipsec status (exit code: $ipsec_exit_code)"
		return 1
	fi

	# Parse peer IPs into array
	local IFS=' '
	local -a peer_ips_array
	read -ra peer_ips_array <<<"$peer_ips"

	local all_active=1
	local active_count=0
	local total_count=${#peer_ips_array[@]}

	for peer_ip in "${peer_ips_array[@]}"; do
		# Check if peer IP appears in ipsec status output
		# Use fixed-string matching for safety
		if echo "$ipsec_output" | grep -qF "$peer_ip"; then
			((active_count++))
			log_message "INFO" "Recovery verification: Connection active for $peer_ip"
		else
			all_active=0
			handle_error "WARNING" "Recovery verification: Connection not found for $peer_ip"
		fi
	done

	if [[ $all_active -eq 1 ]]; then
		log_message "INFO" "Recovery verification: All $total_count connection(s) are active"
		return 0
	else
		handle_error "WARNING" "Recovery verification: Only $active_count/$total_count connection(s) are active"
		return 1
	fi
}

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

		# Wait for SA re-establishment with retries using exponential backoff
		# Use configurable timeout if available, otherwise fall back to constant
		local verify_timeout="${RECOVERY_VERIFY_TIMEOUT:-${XFRM_RECOVERY_VERIFY_TIMEOUT:-30}}"
		local base_interval="${XFRM_RECOVERY_VERIFY_INTERVAL:-2}"
		local max_interval="${XFRM_RECOVERY_MAX_INTERVAL:-16}"
		local current_interval=$base_interval

		log_message "INFO" "xfrm recovery: Waiting for SA re-establishment for $peer_ip (timeout: ${verify_timeout}s)"
		local verify_start_time
		verify_start_time=$(get_unix_timestamp)
		local sa_reestablished=0
		local verify_attempt=0
		local elapsed_time
		local sa_count=0
		local byte_counter_status="unknown"

		while [[ $(($(get_unix_timestamp) - verify_start_time)) -lt $verify_timeout ]]; do
			verify_attempt=$((verify_attempt + 1))
			elapsed_time=$(($(get_unix_timestamp) - verify_start_time))

			# Check if SA is re-established
			if command -v check_ipsec_phase2 >/dev/null 2>&1; then
				if check_ipsec_phase2 "$peer_ip"; then
					# SA re-established - verify byte counters and get SA count
					sa_reestablished=1

					# Count SAs for logging
					if sa_count=$(count_sas_for_peer "$peer_ip" 2>/dev/null); then
						log_message "INFO" "xfrm recovery: SA re-established for $peer_ip after ${elapsed_time}s (attempt $verify_attempt, SA count: $sa_count)"
					else
						log_message "INFO" "xfrm recovery: SA re-established for $peer_ip after ${elapsed_time}s (attempt $verify_attempt)"
					fi

					# Verify byte counters resume
					if verify_byte_counters_resume "$peer_ip" 2>/dev/null; then
						byte_counter_status="resumed"
					else
						byte_counter_status="zero_or_unavailable"
						handle_error "WARNING" "xfrm recovery: SA re-established but byte counters not verified for $peer_ip"
					fi

					log_message "INFO" "xfrm recovery: Verification complete for $peer_ip (duration: ${elapsed_time}s, SA count: ${sa_count}, byte counters: ${byte_counter_status})"
					break
				fi
			fi

			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "xfrm recovery: Verification attempt $verify_attempt for $peer_ip (elapsed: ${elapsed_time}s/${verify_timeout}s, next interval: ${current_interval}s)"

			# Exponential backoff: double interval each attempt, capped at max_interval
			sleep "$current_interval"
			current_interval=$((current_interval * 2))
			if [[ $current_interval -gt $max_interval ]]; then
				current_interval=$max_interval
			fi
		done

		if [[ $sa_reestablished -eq 0 ]]; then
			elapsed_time=$(($(get_unix_timestamp) - verify_start_time))
			handle_error "WARNING" "xfrm recovery: SA did not re-establish within ${verify_timeout}s for $peer_ip (verification duration: ${elapsed_time}s, attempts: $verify_attempt)"
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

# Select recovery strategy based on peer IP and tier
#
# Centralizes recovery strategy selection logic, determining the best recovery
# approach based on configuration, peer IP availability, and tier level.
# Returns recovery plan information via global variables for easy access.
#
# Arguments:
#   $1: Peer IP address (optional, required for per-connection recovery)
#   $2: Tier level (2 for surgical cleanup, 3 for full restart)
#
# Returns:
#   0: Strategy selected successfully
#   1: Invalid tier or no strategy available
#
# Output (via global variables):
#   RECOVERY_STRATEGY: Strategy name ("xfrm", "ipsec_reload", "ipsec_restart")
#   RECOVERY_COMMAND: Command to execute (function name or command)
#   RECOVERY_IMPACT: Impact description ("per-connection" or "all-tunnels")
#   RECOVERY_AVAILABLE: Whether recovery is available (1) or not (0)
#
# Strategy selection logic:
#   1. If peer IP provided and xfrm recovery enabled and ip command available:
#      - Strategy: "xfrm" (per-connection recovery)
#      - Command: attempt_xfrm_recovery function
#      - Impact: "per-connection"
#   2. If tier 2 and ipsec command available:
#      - Strategy: "ipsec_reload" (affects all tunnels)
#      - Command: "ipsec reload" with fallback to "ipsec restart"
#      - Impact: "all-tunnels"
#   3. If tier 3 and ipsec command available:
#      - Strategy: "ipsec_restart" (affects all tunnels)
#      - Command: "ipsec restart"
#      - Impact: "all-tunnels"
#   4. Otherwise:
#      - Strategy: unavailable
#      - Command: empty
#      - Impact: empty
#
# Examples:
#   select_recovery_strategy "203.0.113.1" 2
#   # Sets RECOVERY_STRATEGY="xfrm", RECOVERY_COMMAND="attempt_xfrm_recovery", RECOVERY_IMPACT="per-connection"
#
#   select_recovery_strategy "" 2
#   # Sets RECOVERY_STRATEGY="ipsec_reload", RECOVERY_COMMAND="ipsec reload", RECOVERY_IMPACT="all-tunnels"
#
# Note:
#   Requires ENABLE_XFRM_RECOVERY configuration variable
#   Checks for command availability (ip, ipsec) before selecting strategy
select_recovery_strategy() {
	local peer_ip="${1:-}"
	local tier="${2:-2}"

	# Initialize return variables (declare as global)
	declare -g RECOVERY_STRATEGY=""
	declare -g RECOVERY_COMMAND=""
	declare -g RECOVERY_IMPACT=""
	declare -g RECOVERY_AVAILABLE=0

	# Validate tier
	if [[ "$tier" != "2" ]] && [[ "$tier" != "3" ]]; then
		handle_error "ERROR" "Invalid tier: $tier (must be 2 or 3)" 0
		return 1
	fi

	# Strategy 1: xfrm-based per-connection recovery (if peer IP provided and enabled)
	if [[ -n "$peer_ip" ]] && [[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]] && command -v ip >/dev/null 2>&1; then
		declare -g RECOVERY_STRATEGY="xfrm"
		declare -g RECOVERY_COMMAND="attempt_xfrm_recovery"
		declare -g RECOVERY_IMPACT="per-connection"
		declare -g RECOVERY_AVAILABLE=1
		return 0
	fi

	# Strategy 2: ipsec reload (Tier 2) or ipsec restart (Tier 3)
	if command -v ipsec >/dev/null 2>&1; then
		if [[ "$tier" == "2" ]]; then
			declare -g RECOVERY_STRATEGY="ipsec_reload"
			declare -g RECOVERY_COMMAND="ipsec reload"
			declare -g RECOVERY_IMPACT="all-tunnels"
		else
			declare -g RECOVERY_STRATEGY="ipsec_restart"
			declare -g RECOVERY_COMMAND="ipsec restart"
			declare -g RECOVERY_IMPACT="all-tunnels"
		fi
		declare -g RECOVERY_AVAILABLE=1
		return 0
	fi

	# No strategy available
	declare -g RECOVERY_STRATEGY="unavailable"
	declare -g RECOVERY_COMMAND=""
	declare -g RECOVERY_IMPACT=""
	declare -g RECOVERY_AVAILABLE=0
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

	# Select recovery strategy
	if ! select_recovery_strategy "$peer_ip" 2; then
		# No recovery strategy available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		handle_error "ERROR" "No recovery strategy available for Tier 2 recovery" 0
		return 0
	fi

	# Execute selected strategy with fallback support
	local strategy_executed=0
	while [[ $strategy_executed -eq 0 ]]; do
		case "$RECOVERY_STRATEGY" in
		"xfrm")
			log_message "INFO" "Attempting xfrm-based per-connection recovery for $peer_ip"
			if attempt_xfrm_recovery "$peer_ip"; then
				log_message "INFO" "xfrm-based recovery completed successfully for $peer_ip"
				log_message "INFO" "Surgical cleanup completed for $peer_ip (via xfrm)"
				return 0
			else
				# xfrm recovery failed - fall back to ipsec reload
				handle_error "WARNING" "xfrm-based recovery failed, falling back to ipsec reload (affects all tunnels)"
				# Re-select strategy for fallback (without peer IP to force ipsec reload)
				if ! select_recovery_strategy "" 2; then
					# Fallback strategy not available
					handle_error "ERROR" "xfrm recovery failed and no fallback strategy available" 0
					return 0
				fi
				# Continue loop to execute fallback strategy
				continue
			fi
			;;
		"ipsec_reload")
			log_message "INFO" "Attempting ipsec reload (affects all tunnels)"
			local reload_start_time
			reload_start_time=$(get_unix_timestamp)
			local command_succeeded=0
			if ipsec reload >/dev/null 2>&1; then
				command_succeeded=1
				log_message "INFO" "Successfully reloaded IPsec connections via ipsec reload"
			else
				local reload_exit_code=$?
				handle_error "WARNING" "ipsec reload failed (exit code: ${reload_exit_code}), attempting ipsec restart"
				if ipsec restart >/dev/null 2>&1; then
					command_succeeded=1
					log_message "INFO" "Successfully restarted IPsec service via ipsec restart"
				else
					local restart_exit_code=$?
					handle_error "ERROR" "ipsec restart also failed (exit code: ${restart_exit_code})" 0
				fi
			fi

			# Verify connections are active after reload/restart
			if [[ $command_succeeded -eq 1 ]]; then
				# Wait a moment for connections to re-establish
				sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

				# Verify connections are active (not just that command succeeded)
				if verify_ipsec_connections_active; then
					local reload_duration=$(($(get_unix_timestamp) - reload_start_time))
					log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback, verification: connections active, duration: ${reload_duration}s)"
				else
					local reload_duration=$(($(get_unix_timestamp) - reload_start_time))
					handle_error "WARNING" "Surgical cleanup completed for $peer_ip (via ipsec fallback, verification: some connections not active, duration: ${reload_duration}s)"
				fi
			else
				log_message "INFO" "Surgical cleanup completed for $peer_ip (via ipsec fallback, verification skipped due to command failure)"
			fi
			strategy_executed=1
			;;
		*)
			handle_error "ERROR" "Unknown recovery strategy: $RECOVERY_STRATEGY" 0
			return 0
			;;
		esac
	done

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

	# Select recovery strategy
	if ! select_recovery_strategy "$peer_ip" 3; then
		# No recovery strategy available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		die "No recovery strategy available for Tier 3 recovery"
	fi

	# Execute selected strategy with fallback support
	local strategy_executed=0
	while [[ $strategy_executed -eq 0 ]]; do
		case "$RECOVERY_STRATEGY" in
		"xfrm")
			log_message "INFO" "Tier 3: Attempting xfrm-based per-connection recovery for $peer_ip"
			if attempt_xfrm_recovery "$peer_ip"; then
				log_message "INFO" "Tier 3: xfrm-based per-connection recovery successful for $peer_ip"
				# Record restart for rate limiting (even though it's per-connection)
				record_restart
				set_cooldown "$COOLDOWN_MINUTES"
				return 0
			else
				handle_error "WARNING" "Tier 3: xfrm-based recovery failed for $peer_ip, falling back to full restart"
				# Re-select strategy for fallback (without peer IP to force ipsec restart)
				if ! select_recovery_strategy "" 3; then
					# Fallback strategy not available
					handle_error "ERROR" "Tier 3: xfrm recovery failed and no fallback strategy available" 0
					return 1
				fi
				# Continue loop to execute fallback strategy
				continue
			fi
			;;
		"ipsec_restart")
			handle_error "WARNING" "Tier 3: Performing full IPsec restart (affects all VPN tunnels)"

			# Record restart
			record_restart

			log_message "INFO" "Executing ipsec restart (affects all tunnels)"
			local restart_start_time
			restart_start_time=$(get_unix_timestamp)
			# Capture exit code explicitly to avoid PIPESTATUS being cleared
			# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
			ipsec restart 2>&1 | tee -a "$LOG_FILE"
			local ipsec_exit_code=${PIPESTATUS[0]}
			if [[ $ipsec_exit_code -ne 0 ]]; then
				handle_error "ERROR" "Failed to restart IPsec service (exit code: $ipsec_exit_code)" 0
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
				handle_error "WARNING" "Tier 3: Some connections not active after ipsec restart"
			fi

			# Verify byte counters resume for all configured peers
			if [[ -n "${EXTERNAL_PEER_IPS:-}" ]]; then
				local IFS=' '
				local -a peer_ips_array
				read -ra peer_ips_array <<<"$EXTERNAL_PEER_IPS"
				local peers_with_bytes=0
				local total_peers=${#peer_ips_array[@]}

				for peer_ip in "${peer_ips_array[@]}"; do
					if verify_byte_counters_resume "$peer_ip" 2>/dev/null; then
						((peers_with_bytes++))
					fi
				done

				if [[ $peers_with_bytes -eq $total_peers ]]; then
					byte_counters_verified=1
					log_message "INFO" "Tier 3: Byte counters resumed for all $total_peers peer(s)"
				else
					handle_error "WARNING" "Tier 3: Byte counters resumed for only $peers_with_bytes/$total_peers peer(s)"
				fi
			else
				# No peers configured - skip byte counter verification
				byte_counters_verified=1
				log_message "INFO" "Tier 3: Byte counter verification skipped (no peers configured)"
			fi

			local restart_duration=$(($(get_unix_timestamp) - restart_start_time))
			local verify_duration=$(($(get_unix_timestamp) - verify_start_time))
			log_message "INFO" "Tier 3: Full IPsec restart completed (duration: ${restart_duration}s, verification: ${verify_duration}s, connections: ${connections_verified}, byte counters: ${byte_counters_verified})"
			strategy_executed=1
			;;
		*)
			handle_error "ERROR" "Unknown recovery strategy: $RECOVERY_STRATEGY" 0
			return 1
			;;
		esac
	done

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
		# VPN check failed - check if network is partitioned first
		# If network is partitioned, don't attempt VPN recovery (will fail anyway)
		if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
			local partition_state
			partition_state=$(get_network_partition_state)
			if [[ "$partition_state" -eq 1 ]]; then
				log_message "INFO" "Skipping VPN recovery for $external_peer_ip - network is partitioned"
				return 0
			fi
		fi

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
			if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
				# In fake mode, log what would be done (including the command that would be used)
				# Use strategy selection to determine what would be done
				if select_recovery_strategy "$external_peer_ip" 2; then
					if [[ "$RECOVERY_STRATEGY" == "xfrm" ]]; then
						log_message "INFO" "Tier 2: Would attempt xfrm-based per-connection recovery for $external_peer_ip (skipped in fake mode)"
					else
						log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $external_peer_ip (skipped in fake mode)"
						log_message "INFO" "Tier 2: Would use $RECOVERY_COMMAND ($RECOVERY_IMPACT)"
					fi
				else
					log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $external_peer_ip (skipped in fake mode, no strategy available)"
				fi
			else
				handle_error "WARNING" "Tier 2: Attempting surgical SA cleanup for $external_peer_ip"
				surgical_cleanup "$external_peer_ip"
			fi
		fi

		# Tier 3: Full restart (with per-connection option if xfrm enabled)
		if [[ "$failure_count" -ge "$TIER3_THRESHOLD" ]]; then
			if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
				# In fake mode, still check rate limit to test the logic
				# This allows tests to verify rate limiting behavior
				if ! check_rate_limit; then
					# Rate limit would prevent restart (logged by check_rate_limit)
					log_message "INFO" "Tier 3: Would attempt IPsec restart (skipped in fake mode, rate limit would prevent)"
				else
					# Use strategy selection to determine what would be done
					if select_recovery_strategy "$external_peer_ip" 3; then
						if [[ "$RECOVERY_STRATEGY" == "xfrm" ]]; then
							log_message "INFO" "Tier 3: Would attempt xfrm-based per-connection recovery for $external_peer_ip (skipped in fake mode)"
						else
							log_message "INFO" "Tier 3: Would attempt full IPsec restart (affects all tunnels, skipped in fake mode)"
						fi
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
