#!/bin/bash
#
# Recovery verification functions for UDM VPN Monitor
# Verifies that recovery actions succeeded by checking SA state, byte counters, and IPsec connections
#
# Version: 0.7.0
#

# Source recovery constants for magic numbers
# shellcheck source=lib/recovery/constants.sh
RECOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${RECOVERY_DIR}/constants.sh"

# Source general constants for IPSEC_STATUS_TIMEOUT (used across detection and recovery)
# shellcheck source=lib/constants.sh
if [[ -z "${LIB_DIR:-}" ]]; then
	LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
fi

# shellcheck source=lib/detection.sh
source "${LIB_DIR}/detection.sh" 2>/dev/null || {
	# Extract byte counter from xfrm output (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: xfrm output text (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection.sh.
	extract_byte_counter() { return 1; }
	# Get xfrm state for peer (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection.sh.
	get_xfrm_state_for_peer() { return 1; }
}

# Count Security Associations for a peer IP
#
# Counts the number of Security Associations (SAs) for a specific peer IP
# by parsing xfrm state output. Each SA block starts with "src <ip> dst <ip>".
#
# Arguments:
#   $1: Peer IP address to count SAs for
#   $2: Location name (optional, for diagnostic logging)
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
#   When location_name is provided, logs detailed diagnostic information about SAs found
count_sas_for_peer() {
	local external_peer_ip="$1"
	local location_name="${2:-}"

	if ! check_command_or_warn "ip" "Counting SAs for peer"; then
		return 1
	fi

	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	# Use _RECOVERY_IP_PATH if available (set by recovery orchestration), otherwise resolve via get_command_path()
	local ip_cmd
	ip_cmd=$(get_ip_command_path)

	local xfrm_output
	xfrm_output=$("$ip_cmd" xfrm state 2>/dev/null)
	local xfrm_exit_code=$?

	if [[ $xfrm_exit_code -ne 0 ]]; then
		return 1
	fi

	# Extract all SA header lines (src ... dst ...) for this peer
	# This helps diagnose bidirectional SA state
	# Find both forward SAs (dst=$external_peer_ip) and reverse SAs (src=$external_peer_ip)
	# Forward SAs: "src <local_ip> dst $external_peer_ip"
	# Reverse SAs: "src $external_peer_ip dst <local_ip>"
	local forward_headers
	local reverse_headers
	forward_headers=$(echo "$xfrm_output" | grep -F "dst $external_peer_ip" | grep -E "^[[:space:]]*src" || true)
	reverse_headers=$(echo "$xfrm_output" | grep -E "^[[:space:]]*src ${external_peer_ip}[[:space:]]" || true)

	# Combine headers, deduplicating by SA header line (src ... dst ...)
	# Use awk to deduplicate since the same SA might appear in both if grep -A includes context
	local sa_headers
	if [[ -n "$forward_headers" ]] && [[ -n "$reverse_headers" ]]; then
		sa_headers=$(printf "%s\n%s" "$forward_headers" "$reverse_headers" | awk '!seen[$0]++')
	elif [[ -n "$forward_headers" ]]; then
		sa_headers="$forward_headers"
	elif [[ -n "$reverse_headers" ]]; then
		sa_headers="$reverse_headers"
	fi

	# Count SA blocks - validate format before counting
	# Each SA block starts with "src <ip> dst <ip>" on a line
	# Validate format matches expected SA header pattern to prevent incorrect counts
	# if xfrm output format changes unexpectedly
	local sa_count
	if [[ -z "$sa_headers" ]]; then
		sa_count=0
	else
		# Count only lines that match valid SA header format: "src <ip> dst <ip>"
		# This validates the format matches expected xfrm output structure
		# Pattern matches IPv4 (dotted decimal) or IPv6 (hex colon) addresses
		sa_count=$(echo "$sa_headers" | grep -cE '^[[:space:]]*src[[:space:]]+([0-9.]+|[0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9.]+|[0-9a-fA-F:]+)' || echo "0")
	fi

	# Enhanced diagnostic logging: Log detailed SA information when location_name provided
	# This helps diagnose SA count mismatches and asymmetric SA state
	if [[ -n "$location_name" ]] && [[ -n "$sa_headers" ]]; then
		local sa_details=""
		local sa_idx=0
		while IFS= read -r header_line || [[ -n "$header_line" ]]; do
			# Extract src and dst from header line (format: "src <ip> dst <ip>")
			if [[ "$header_line" =~ ^[[:space:]]*src[[:space:]]+([0-9.]+|[0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9.]+|[0-9a-fA-F:]+) ]]; then
				local sa_src="${BASH_REMATCH[1]}"
				local sa_dst="${BASH_REMATCH[2]}"
				sa_idx=$((sa_idx + 1))
				# Determine direction for diagnostic clarity
				local direction="unknown"
				if [[ "$sa_src" == "$external_peer_ip" ]]; then
					direction="reverse (peer→local)"
				elif [[ "$sa_dst" == "$external_peer_ip" ]]; then
					direction="forward (local→peer)"
				fi
				sa_details="${sa_details}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction]; "
			fi
		done <<<"$sa_headers"
		if [[ -n "$sa_details" ]]; then
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "")
			log_message "INFO" "$location_name" "xfrm recovery: SA count diagnostic for $ip_display: count=$sa_count, details: ${sa_details% }"
		fi
	fi

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
#   $2: Optional location name for logging context
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
#   if verify_byte_counters_resume "203.0.113.1" "NYC"; then
#       echo "Byte counters verified for NYC"
#   fi
#
# Note:
#   Requires extract_byte_counter from detection.sh
#   If byte counters are not available, returns success if SA exists (graceful degradation)
verify_byte_counters_resume() {
	local external_peer_ip="$1"
	local location_name="$2"
	local xfrm_output

	if ! check_command_or_warn "ip" "Verifying byte counters"; then
		return 1
	fi

	# Get xfrm output for this peer
	xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip")

	if [[ -z "$xfrm_output" ]]; then
		return 1
	fi

	# Format IP display once for reuse throughout function
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Extract byte counter
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
		if [[ "$current_bytes" -gt 0 ]]; then
			log_message "INFO" "$location_name" "Recovery verification: Byte counters resumed for $ip_display (bytes=$current_bytes)"
			return 0
		else
			handle_error "WARNING" "$location_name" "Recovery verification: Byte counters are zero for $ip_display (tunnel may not be passing traffic)"
			return 1
		fi
	else
		# Byte counters not available, but SA exists - log and return success
		log_message "INFO" "$location_name" "Recovery verification: Byte counters not available for $ip_display (SA exists, verification limited)"
		return 0
	fi
}

# Verify byte counters increment after SA re-establishment
#
# Verifies that byte counters have increased from an initial baseline value after SA re-establishment.
# This handles the case where byte counters reset to zero after SA deletion/re-establishment.
# Instead of checking for absolute non-zero values, this checks for counter increment which
# indicates traffic is flowing through the tunnel.
#
# Arguments:
#   $1: Peer IP address to verify
#   $2: Initial byte counter value (baseline, may be zero)
#   $3: Optional location name for logging context
#
# Returns:
#   0: Byte counters have increased from initial value (or not available but SA exists)
#   1: Byte counters have not increased or are unavailable
#
# Side effects:
#   - Logs byte counter status and increment
#
# Examples:
#   initial_bytes=0
#   if verify_byte_counters_increment "203.0.113.1" "$initial_bytes" "NYC"; then
#       echo "Byte counters incrementing"
#   fi
#
# Note:
#   Requires extract_byte_counter from detection.sh
#   If byte counters are not available, returns success if SA exists (graceful degradation)
#   This function is designed for post-recovery verification where counters may reset to zero
verify_byte_counters_increment() {
	local external_peer_ip="$1"
	local initial_bytes="$2"
	local location_name="$3"
	local xfrm_output

	if ! check_command_or_warn "ip" "Verifying byte counter increment"; then
		return 1
	fi

	# Get xfrm output for this peer
	xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip")

	if [[ -z "$xfrm_output" ]]; then
		return 1
	fi

	# Format IP display once for reuse throughout function
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")

	# Extract byte counter
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
		# Validate initial_bytes is numeric (default to 0 if not)
		if [[ ! "$initial_bytes" =~ ^[0-9]+$ ]]; then
			initial_bytes=0
		fi
		# Validate current_bytes is numeric
		if [[ ! "$current_bytes" =~ ^[0-9]+$ ]]; then
			handle_error "WARNING" "$location_name" "Recovery verification: Invalid byte counter value for $ip_display (current=$current_bytes)"
			return 1
		fi
		# Check if counters have increased from initial value
		if [[ "$current_bytes" -gt "$initial_bytes" ]]; then
			local increment=$((current_bytes - initial_bytes))
			log_message "INFO" "$location_name" "Recovery verification: Byte counters incrementing for $ip_display (initial=$initial_bytes, current=$current_bytes, increment=$increment)"
			return 0
		else
			# Counters haven't increased yet - log status but don't fail immediately
			# This allows the verification loop to continue waiting
			if [[ "$current_bytes" -eq 0 ]] && [[ "$initial_bytes" -eq 0 ]]; then
				# Both are zero - counters reset but haven't started incrementing yet
				handle_error "WARNING" "$location_name" "Recovery verification: Byte counters are zero for $ip_display (waiting for traffic to resume)"
			else
				# Counters haven't increased (may have decreased or stayed same)
				handle_error "WARNING" "$location_name" "Recovery verification: Byte counters not incrementing for $ip_display (initial=$initial_bytes, current=$current_bytes)"
			fi
			return 1
		fi
	else
		# Byte counters not available, but SA exists - log and return success
		log_message "INFO" "$location_name" "Recovery verification: Byte counters not available for $ip_display (SA exists, verification limited)"
		return 0
	fi
}

# Verify IPsec connections are active
#
# Verifies that IPsec connections are active (not just that command succeeded).
# Checks that connections exist in ipsec status output for all configured locations.
#
# Arguments:
#   $1: Space-separated list of peer IPs to verify (optional, uses parsed locations if not provided)
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
#   If no peer IPs provided, attempts to parse location config to get all external IPs
#   Returns success if no locations configured (no peers to verify)
#   Uses get_command_path() to resolve ipsec command path for reliable execution
#   in PATH-restricted environments (cron/systemd)
verify_ipsec_connections_active() {
	local peer_ips="${1:-}"

	# If no peer IPs provided, try to parse location config
	# Use global LOCATIONS array if available, otherwise parse config
	if [[ -z "$peer_ips" ]] && command -v parse_location_config >/dev/null 2>&1; then
		# Ensure location config is parsed (may not be if called directly)
		if ! declare -p LOCATIONS &>/dev/null 2>&1; then
			parse_location_config 2>/dev/null || true
		fi
		if [[ ${#LOCATIONS[@]} -gt 0 ]]; then
			local external_ips=()
			# Use iter_location_name to avoid overwriting location_name from parent scope
			local iter_location_name
			for iter_location_name in "${!LOCATIONS[@]}"; do
				# Extract external IP using helper function
				local external_peer_ip
				if external_peer_ip=$(get_location_external_ip "$iter_location_name" 2>/dev/null); then
					external_ips+=("$external_peer_ip")
				fi
			done
			if [[ ${#external_ips[@]} -gt 0 ]]; then
				peer_ips="${external_ips[*]}"
			fi
		fi
	fi

	if ! check_command_or_warn "ipsec" "Recovery verification"; then
		return 1
	fi

	# Get resolved path to ipsec command for reliable execution in PATH-restricted environments
	# Reuse _RECOVERY_IPSEC_PATH if available (set by recovery actions), otherwise resolve via get_command_path()
	# This ensures consistency with recovery actions and avoids redundant path resolution
	local ipsec_cmd="ipsec"
	if [[ -n "${_RECOVERY_IPSEC_PATH:-}" ]]; then
		# Reuse path already resolved by recovery actions
		ipsec_cmd="${_RECOVERY_IPSEC_PATH}"
	elif command -v get_command_path >/dev/null 2>&1; then
		# Resolve path independently (when called standalone)
		ipsec_cmd=$(get_command_path "ipsec")
	fi

	if [[ -z "$peer_ips" ]]; then
		# No peers to verify
		return 0
	fi

	# Get ipsec status output
	# Wrap ipsec status with timeout to prevent hanging
	# Use resolved path to ipsec command for reliable execution
	local ipsec_output
	local ipsec_exit_code=0
	if check_command_available "timeout"; then
		ipsec_output=$(timeout "$IPSEC_STATUS_TIMEOUT" "$ipsec_cmd" status 2>/dev/null)
		ipsec_exit_code=$?
	else
		# Fallback if timeout command not available (shouldn't happen on UDM)
		ipsec_output=$("$ipsec_cmd" status 2>/dev/null)
		ipsec_exit_code=$?
	fi

	if [[ $ipsec_exit_code -ne 0 ]]; then
		if [[ $ipsec_exit_code -eq 124 ]]; then
			handle_error "WARNING" "SYSTEM" "Recovery verification: ipsec status timed out after ${IPSEC_STATUS_TIMEOUT}s (unable to verify connections)"
		else
			handle_error "WARNING" "SYSTEM" "Recovery verification: Failed to query ipsec status (exit code: $ipsec_exit_code)"
		fi
		return 1
	fi

	# Parse peer IPs into array
	local IFS=' '
	local -a peer_ips_array
	read -ra peer_ips_array <<<"$peer_ips"

	local all_active=1
	local active_count=0
	local total_count=${#peer_ips_array[@]}

	local external_peer_ip
	for external_peer_ip in "${peer_ips_array[@]}"; do
		# Check if peer IP appears in ipsec status output (IKE connection check)
		# Use fixed-string matching for safety
		local ike_found=0
		if echo "$ipsec_output" | grep -qF "$external_peer_ip"; then
			ike_found=1
		fi

		# Also check if Phase 2 SAs are actually established (xfrm state check)
		# This is more reliable than just checking IKE connections
		local sa_count=0
		if command -v count_sas_for_peer >/dev/null 2>&1; then
			sa_count=$(count_sas_for_peer "$external_peer_ip" "" 2>/dev/null || echo "0")
			# Ensure sa_count is numeric
			if ! [[ "$sa_count" =~ ^[0-9]+$ ]]; then
				sa_count=0
			fi
		fi

		# Connection is considered active only if BOTH IKE connection exists AND Phase 2 SAs are established
		if [[ $ike_found -eq 1 ]] && [[ "$sa_count" -gt 0 ]]; then
			((active_count++))
			log_message "INFO" "SYSTEM" "Recovery verification: Connection active for $external_peer_ip (IKE: yes, Phase 2 SAs: $sa_count)"
		elif [[ $ike_found -eq 1 ]] && [[ "$sa_count" -eq 0 ]]; then
			all_active=0
			handle_error "WARNING" "SYSTEM" "Recovery verification: IKE connection exists but no Phase 2 SAs for $external_peer_ip (tunnel not fully established)"
		elif [[ $ike_found -eq 0 ]] && [[ "$sa_count" -gt 0 ]]; then
			# Edge case: SAs exist but IKE not showing in status (may be timing issue)
			((active_count++))
			log_message "INFO" "SYSTEM" "Recovery verification: Connection active for $external_peer_ip (IKE: not found in status, Phase 2 SAs: $sa_count - may be timing issue)"
		else
			all_active=0
			handle_error "WARNING" "SYSTEM" "Recovery verification: Connection not found for $external_peer_ip (IKE: no, Phase 2 SAs: $sa_count)"
		fi
	done

	if [[ $all_active -eq 1 ]]; then
		log_message "INFO" "SYSTEM" "Recovery verification: All $total_count connection(s) are active"
		return 0
	else
		handle_error "WARNING" "SYSTEM" "Recovery verification: Only $active_count/$total_count connection(s) are active"
		return 1
	fi
}
