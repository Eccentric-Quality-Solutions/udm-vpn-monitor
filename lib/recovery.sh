#!/bin/bash
#
# Recovery actions for UDM VPN Monitor
# Implements tiered recovery: logging → surgical cleanup → full restart
#
# Version: 0.5.0
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	[[ -z "${XFRM_RECOVERY_SLEEP_SECONDS:-}" ]] && readonly XFRM_RECOVERY_SLEEP_SECONDS=3
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${XFRM_RECOVERY_VERIFY_TIMEOUT:-}" ]] && readonly XFRM_RECOVERY_VERIFY_TIMEOUT=30
	[[ -z "${XFRM_RECOVERY_VERIFY_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_VERIFY_INTERVAL=2
	[[ -z "${XFRM_RECOVERY_MAX_INTERVAL:-}" ]] && readonly XFRM_RECOVERY_MAX_INTERVAL=16
	[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
fi

# Source detection functions for byte counter and SA checks
# shellcheck source=lib/detection.sh
# Note: safe_source_lib not available here since common.sh hasn't been sourced yet
# Using direct source pattern since detection.sh is sourced before common.sh
source "${LIB_DIR}/detection.sh" 2>/dev/null || {
	# Fallback if detection.sh not found
	# Check for IPsec Phase 2 Security Association (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: Peer IP address to check (ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection.sh.
	check_ipsec_phase2() { return 1; }
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
	# Check byte counters for VPN status (fallback stub)
	#
	# Fallback stub function when detection.sh cannot be sourced.
	# Always returns failure since detection functionality is unavailable.
	#
	# Arguments:
	#   $1: Location name (ignored in fallback)
	#   $2: Current byte count (ignored in fallback)
	#   $3: Peer IP address (ignored in fallback)
	#   $4: Current SPI value (optional, ignored in fallback)
	#   $5: Internal peer IP address (optional, ignored in fallback)
	#
	# Returns:
	#   1: Always returns failure (detection.sh unavailable)
	#
	# Note:
	#   This is a fallback stub. The real implementation is in detection.sh.
	check_byte_counters() { return 1; }
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
	local peer_ip="$1"
	local location_name="${2:-}"

	if ! check_command_or_warn "ip" "Counting SAs for peer"; then
		return 1
	fi

	local xfrm_output
	xfrm_output=$(ip xfrm state 2>/dev/null)
	local xfrm_exit_code=$?

	if [[ $xfrm_exit_code -ne 0 ]]; then
		return 1
	fi

	# Extract all SA header lines (src ... dst ...) for this peer
	# This helps diagnose bidirectional SA state
	# Find both forward SAs (dst=$peer_ip) and reverse SAs (src=$peer_ip)
	# Forward SAs: "src <local_ip> dst $peer_ip"
	# Reverse SAs: "src $peer_ip dst <local_ip>"
	local forward_headers
	local reverse_headers
	forward_headers=$(echo "$xfrm_output" | grep -F "dst $peer_ip" | grep -E "^[[:space:]]*src" || true)
	reverse_headers=$(echo "$xfrm_output" | grep -E "^[[:space:]]*src ${peer_ip}[[:space:]]" || true)

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

	# Count SA blocks - sa_headers already contains only lines starting with "src"
	# Each SA block starts with "src <ip> dst <ip>" on a line
	# Count lines directly since we've already filtered for lines starting with "src"
	local sa_count
	if [[ -z "$sa_headers" ]]; then
		sa_count=0
	else
		# Count non-empty lines (sa_headers already filtered for "src" lines)
		sa_count=$(echo "$sa_headers" | grep -c . || echo "0")
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
				if [[ "$sa_src" == "$peer_ip" ]]; then
					direction="reverse (peer→local)"
				elif [[ "$sa_dst" == "$peer_ip" ]]; then
					direction="forward (local→peer)"
				fi
				sa_details="${sa_details}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction]; "
			fi
		done <<<"$sa_headers"
		if [[ -n "$sa_details" ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: SA count diagnostic for $location_name ($peer_ip): count=$sa_count, details: ${sa_details% }"
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
	local peer_ip="$1"
	local location_name="$2"
	local xfrm_output

	if ! check_command_or_warn "ip" "Verifying byte counters"; then
		return 1
	fi

	# Get xfrm output for this peer
	xfrm_output=$(get_xfrm_state_for_peer "$peer_ip")

	if [[ -z "$xfrm_output" ]]; then
		return 1
	fi

	# Extract byte counter
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
		if [[ "$current_bytes" -gt 0 ]]; then
			log_message "INFO" "$location_name" "Recovery verification: Byte counters resumed for $location_name ($peer_ip) (bytes=$current_bytes)"
			return 0
		else
			handle_error "WARNING" "$location_name" "Recovery verification: Byte counters are zero for $location_name ($peer_ip) (tunnel may not be passing traffic)"
			return 1
		fi
	else
		# Byte counters not available, but SA exists - log and return success
		log_message "INFO" "$location_name" "Recovery verification: Byte counters not available for $location_name ($peer_ip) (SA exists, verification limited)"
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
	local peer_ip="$1"
	local initial_bytes="$2"
	local location_name="$3"
	local xfrm_output

	if ! check_command_or_warn "ip" "Verifying byte counter increment"; then
		return 1
	fi

	# Get xfrm output for this peer
	xfrm_output=$(get_xfrm_state_for_peer "$peer_ip")

	if [[ -z "$xfrm_output" ]]; then
		return 1
	fi

	# Extract byte counter
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
		# Validate initial_bytes is numeric (default to 0 if not)
		if [[ ! "$initial_bytes" =~ ^[0-9]+$ ]]; then
			initial_bytes=0
		fi
		# Validate current_bytes is numeric
		if [[ ! "$current_bytes" =~ ^[0-9]+$ ]]; then
			handle_error "WARNING" "$location_name" "Recovery verification: Invalid byte counter value for $location_name ($peer_ip) (current=$current_bytes)"
			return 1
		fi
		# Check if counters have increased from initial value
		if [[ "$current_bytes" -gt "$initial_bytes" ]]; then
			local increment=$((current_bytes - initial_bytes))
			log_message "INFO" "$location_name" "Recovery verification: Byte counters incrementing for $location_name ($peer_ip) (initial=$initial_bytes, current=$current_bytes, increment=$increment)"
			return 0
		else
			# Counters haven't increased yet - log status but don't fail immediately
			# This allows the verification loop to continue waiting
			if [[ "$current_bytes" -eq 0 ]] && [[ "$initial_bytes" -eq 0 ]]; then
				# Both are zero - counters reset but haven't started incrementing yet
				handle_error "WARNING" "$location_name" "Recovery verification: Byte counters are zero for $location_name ($peer_ip) (waiting for traffic to resume)"
			else
				# Counters haven't increased (may have decreased or stayed same)
				handle_error "WARNING" "$location_name" "Recovery verification: Byte counters not incrementing for $location_name ($peer_ip) (initial=$initial_bytes, current=$current_bytes)"
			fi
			return 1
		fi
	else
		# Byte counters not available, but SA exists - log and return success
		log_message "INFO" "$location_name" "Recovery verification: Byte counters not available for $location_name ($peer_ip) (SA exists, verification limited)"
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
	if [[ -z "$peer_ips" ]] && command -v parse_location_config >/dev/null 2>&1; then
		declare -A LOCATIONS
		if parse_location_config; then
			local external_ips=()
			local location_name
			for location_name in "${!LOCATIONS[@]}"; do
				# Extract external IP from location data format: "external:IP|internal:IPs"
				local external_ip=""
				if command -v get_location_external_ip >/dev/null 2>&1; then
					external_ip=$(get_location_external_ip "$location_name" 2>/dev/null || echo "")
				else
					# Fallback: extract from LOCATIONS format directly
					local location_data="${LOCATIONS[$location_name]:-}"
					if [[ "$location_data" =~ external:([^|]+) ]]; then
						external_ip="${BASH_REMATCH[1]:-}"
					fi
				fi
				if [[ -n "$external_ip" ]]; then
					external_ips+=("$external_ip")
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

	local peer_ip
	for peer_ip in "${peer_ips_array[@]}"; do
		# Check if peer IP appears in ipsec status output
		# Use fixed-string matching for safety
		if echo "$ipsec_output" | grep -qF "$peer_ip"; then
			((active_count++))
			log_message "INFO" "SYSTEM" "Recovery verification: Connection active for $peer_ip"
		else
			all_active=0
			handle_error "WARNING" "SYSTEM" "Recovery verification: Connection not found for $peer_ip"
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
#   $2: Location name (required for logging context)
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
# Algorithm Overview:
#   This function implements a multi-phase recovery process:
#   1. Query Phase: Retrieve all xfrm state entries from the kernel
#   2. Filter Phase: Extract only entries matching the target peer IP
#   3. Parse Phase: Extract SA selectors (src, dst, proto, spi) from filtered output
#   4. Delete Phase: Delete each parsed SA using ip xfrm state delete
#   5. Verify Phase: Wait for SA re-establishment with exponential backoff
#
# Parsing Algorithm Details:
#   The xfrm state output format on UDM OS 4.3+ follows this structure:
#     src <source_ip> dst <dest_ip>
#       proto <protocol> spi <spi_value>
#       [additional SA attributes...]
#
#   Parsing assumptions:
#   - Each SA block starts with a line matching: "^src <ip> dst <ip>"
#   - The proto and spi values appear on continuation lines (may be indented)
#   - Proto can appear on the same line as spi: "proto esp spi 0x12345678"
#   - Proto and spi can also appear on separate lines
#   - Valid protocols: "esp" or "ah" (case-insensitive, normalized to lowercase)
#   - Valid SPI formats: hex (0x12345678) or decimal (12345678)
#
#   Parsing state machine:
#   - State: in_sa_block (boolean) - tracks if we're currently parsing an SA block
#   - State: current_src, current_dst, current_proto, current_spi - current SA selectors
#   - Transition: When we see "^src ... dst ..." line:
#       * If in_sa_block=1 and all selectors complete, save previous SA to list
#       * Start new SA block, extract src and dst from regex match
#       * Reset proto and spi to empty
#   - Transition: When in_sa_block=1 and line matches "proto ...":
#       * Extract protocol name, normalize to lowercase
#       * Check if "spi" appears on same line, extract if present
#   - Transition: When in_sa_block=1 and line matches "spi ...":
#       * Extract SPI value (overwrites any previously extracted SPI)
#   - Finalization: After processing all lines, save last SA if complete
#
#   Edge cases handled:
#   - Empty xfrm output: Returns success if no SAs exist (may already be down)
#   - Partial SA blocks: Only saves SAs with all four selectors (src, dst, proto, spi)
#   - Invalid selectors: Validates proto (esp/ah) and spi (hex/decimal) before saving
#   - Parse errors: Tracks parse_errors count, fails if errors exist and no valid SAs found
#   - Multiple SAs: Processes all matching SAs, deletes each individually
#
# Filtering Algorithm:
#   Uses grep -F (fixed-string matching) with "dst $peer_ip" pattern to:
#   - Prevent regex pattern injection (treats IP as literal string)
#   - Provide natural word boundaries (exact match prevents partial IP matches)
#   - Example: "dst 192.168.1.1" won't match "dst 192.168.1.10" due to exact matching
#   - Includes context lines (-A) to capture complete SA blocks after match line
#
# Verification Algorithm:
#   After deletion, waits for SA re-establishment using exponential backoff:
#   - Initial interval: XFRM_RECOVERY_VERIFY_INTERVAL (default: 2 seconds)
#   - Backoff: Doubles interval each attempt (2s → 4s → 8s → 16s)
#   - Maximum interval: XFRM_RECOVERY_MAX_INTERVAL (default: 16 seconds)
#   - Timeout: RECOVERY_VERIFY_TIMEOUT or XFRM_RECOVERY_VERIFY_TIMEOUT (default: 30 seconds)
#   - Verification checks:
#     * SA existence via check_ipsec_phase2()
#     * SA count via count_sas_for_peer()
#     * Byte counter increment via verify_byte_counters_increment()
#       - Captures initial byte counter value when SA is first re-established (may be zero)
#       - Checks for counter increment from initial value (indicates traffic is flowing)
#       - Handles case where counters reset to zero after SA deletion/re-establishment
#
# Assumptions:
#   - UDM OS 4.3+ uses consistent xfrm output format (tested format)
#   - strongSwan will automatically re-establish SAs after deletion
#   - Re-establishment typically occurs within 30 seconds
#   - Byte counters may reset to zero after SA deletion/re-establishment (handled by increment check)
#   - Verification checks for counter increment rather than absolute non-zero value
#   - Multiple SAs may exist for a single peer (common with multiple subnets)
#
# Error Handling:
#   - Query failure: Returns error immediately (can't proceed without xfrm state)
#   - Empty output: Returns failure if no SAs exist (xfrm recovery cannot help, triggers fallback)
#     * If no SAs exist, xfrm recovery cannot recover the VPN, so fallback to ipsec reload/restart is needed
#   - Parse errors: Fails only if no valid SAs found (partial success allowed)
#   - Delete failures: Tracks failed_count, fails if all deletions failed
#   - Re-establishment timeout: Returns error to trigger fallback recovery strategy
#   - Byte counter verification failure: Returns error if SA re-established but byte counters don't increment within timeout
#
# Examples:
#   # Delete and re-establish SAs for peer 203.0.113.1
#   if attempt_xfrm_recovery "203.0.113.1" "NYC"; then
#       echo "Recovery successful"
#   else
#       echo "Recovery failed, will fall back to ipsec reload"
#   fi
#
#   # Example xfrm output format being parsed:
#   # src 192.168.1.1 dst 203.0.113.1
#   #   proto esp spi 0x12345678
#   #   mode tunnel
#   #   ...
#
# Note:
#   This function parses 'ip xfrm state' output to extract SA selectors (src, dst, proto, spi, mark).
#   Mark selector is optional - when present, it must be included in deletion commands for successful deletion.
#   Parsing is optimized for UDM OS 4.3+ format. Supports both IPv4 and IPv6 addresses.
#   Requires 'ip' command and root privileges.
#   Uses check_ipsec_phase2() from detection.sh to verify SA re-establishment.
attempt_xfrm_recovery() {
	local peer_ip="$1"
	local location_name="$2"
	local deleted_count=0
	local failed_count=0
	local parse_errors=0

	if ! check_command_or_warn "ip" "xfrm recovery"; then
		return 1
	fi

	# Validate peer IP before proceeding
	if [[ -z "$peer_ip" ]]; then
		handle_error "ERROR" "$location_name" "xfrm recovery: Peer IP not provided" 0
		return 1
	fi

	# Enhanced diagnostics: Log system/kernel information that may affect xfrm operations
	# This helps identify version-specific issues or permission problems
	local kernel_version=""
	local ip_version=""
	if kernel_version=$(uname -r 2>/dev/null); then
		log_message "INFO" "$location_name" "xfrm recovery: Starting recovery for $location_name ($peer_ip) - kernel: $kernel_version"
	fi
	if ip_version=$(ip -Version 2>&1 | head -1); then
		log_message "INFO" "$location_name" "xfrm recovery: ip command version: $ip_version"
	fi

	# Get all xfrm state entries for this peer IP
	# Match on "dst $peer_ip" pattern which appears at the start of each SA entry
	# This ensures we capture complete SA blocks for proper deletion
	# Use fixed-string matching to prevent regex pattern injection
	# Word boundary protection: The "dst " prefix and space after IP provide natural boundaries
	# (e.g., "dst 192.168.1.1" won't match "dst 192.168.1.10" due to exact string matching)
	local xfrm_output
	local xfrm_result
	xfrm_output=$(get_xfrm_state_for_peer "$peer_ip")
	xfrm_result=$?

	# Check if helper function failed (ip command not available - should not happen since we check above)
	if [[ $xfrm_result -ne 0 ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: Failed to query xfrm state for $location_name ($peer_ip)"
		return 1
	fi

	if [[ -z "$xfrm_output" ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: No SAs found for $location_name ($peer_ip) in xfrm state (may already be down)"
		# If no SAs exist, verify they're actually gone (not a parsing issue)
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if ! check_ipsec_phase2 "$peer_ip"; then
				log_message "INFO" "$location_name" "xfrm recovery: Confirmed no SAs exist for $location_name ($peer_ip)"
				# No SAs exist - while we've successfully confirmed the state, xfrm recovery cannot
				# accomplish the recovery goal (bringing the VPN back up) since there's nothing to
				# delete/re-establish. Return failure to trigger fallback to ipsec reload/restart.
				return 1
			else
				handle_error "WARNING" "$location_name" "xfrm recovery: SAs exist but parsing failed for $location_name ($peer_ip)"
				return 1
			fi
		fi
		# No SAs exist and no check_ipsec_phase2 available - xfrm recovery cannot help, return failure to trigger fallback
		return 1
	fi

	# Parse xfrm output to extract and delete SAs
	# Format: Each SA block starts with "src <ip> dst <ip>" followed by "proto <proto> spi <spi>"
	# UDM OS 4.3+ uses consistent format: src and dst on first line, proto and spi on continuation lines
	# Mark attribute (optional): "mark 0x<value>/0x<mask>" appears on continuation lines
	#
	# Parsing state variables:
	#   current_src, current_dst: Source and destination IPs (extracted from SA header line)
	#   current_proto, current_spi: Protocol and SPI (extracted from continuation lines)
	#   current_mark: Mark selector (extracted from continuation lines, optional)
	#   in_sa_block: Boolean flag indicating we're currently parsing an SA block
	#   sa_list: Array of complete SA entries in format "src|dst|proto|spi|mark" (mark may be empty)
	local current_src=""
	local current_dst=""
	local current_proto=""
	local current_spi=""
	local current_mark=""
	local in_sa_block=0
	local sa_list=()

	[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Parsing xfrm output for $location_name ($peer_ip)"
	# Track if we've logged raw xfrm output (to avoid excessive logging on multiple failures)
	local raw_xfrm_output_logged=0

	# Parse loop: Process each line of xfrm output
	# State machine transitions:
	#   1. New SA block detected (line starts with "src ... dst ..."):
	#      - Save previous SA if complete (all selectors present)
	#      - Start new SA block, extract src and dst
	#      - Reset proto, spi, and mark (will be extracted from continuation lines)
	#   2. Continuation line (within SA block):
	#      - Extract proto if present (may be on same line as spi)
	#      - Extract spi if present (may be on same line as proto or separate line)
	#      - Extract mark if present (format: "mark 0x<value>/0x<mask>")
	#      - Note: Later spi match overwrites earlier one (handles both formats)
	local line_count=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_count=$((line_count + 1))
		# Skip empty lines (don't affect parsing state)
		[[ -z "$line" ]] && continue

		# State transition: New SA block detected
		# Regex matches: "src <ipv4_or_ipv6> dst <ipv4_or_ipv6>"
		# Try IPv4 first (more specific pattern to avoid matching hex digits from SPI values)
		# Then fall back to IPv6 pattern if IPv4 doesn't match
		local sa_header_match=0
		local extracted_src=""
		local extracted_dst=""
		if [[ "$line" =~ ^src[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[[:space:]]+dst[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
			# IPv4 addresses matched
			extracted_src="${BASH_REMATCH[1]:-}"
			extracted_dst="${BASH_REMATCH[2]:-}"
			sa_header_match=1
		elif [[ "$line" =~ ^src[[:space:]]+([0-9a-fA-F:]+)[[:space:]]+dst[[:space:]]+([0-9a-fA-F:]+) ]]; then
			# IPv6 addresses matched (fallback)
			extracted_src="${BASH_REMATCH[1]:-}"
			extracted_dst="${BASH_REMATCH[2]:-}"
			sa_header_match=1
		fi

		if [[ $sa_header_match -eq 1 ]]; then
			# Before starting new SA, save previous SA if it's complete
			# Complete SA requires: src, dst, proto, and spi all present
			# This handles the case where we've finished parsing one SA and found the next
			if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
				# CRITICAL: Verify that the SA matches the target peer IP (forward SA: dst=$peer_ip, reverse SA: src=$peer_ip)
				# This prevents deleting SAs for wrong locations when grep -A includes subsequent SA blocks
				# Accept both forward SAs (dst=$peer_ip) and reverse SAs (src=$peer_ip) to handle asymmetric SA state
				if [[ "$current_dst" == "$peer_ip" ]] || [[ "$current_src" == "$peer_ip" ]]; then
					# Validate selectors before adding to list
					# Proto must be "esp" or "ah" (case-insensitive, already normalized)
					# SPI must be hex (0x...) or decimal format
					if [[ "$current_proto" =~ ^(esp|ah)$ ]] && [[ "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
						# Store complete SA as delimited string for later processing
						# Format: "src|dst|proto|spi|mark" (pipe separator avoids IP address conflicts)
						# Mark may be empty (backward compatibility with SAs without marks)
						sa_list+=("$current_src|$current_dst|$current_proto|$current_spi|${current_mark:-}")
						[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi mark=${current_mark:-<none>} for $location_name ($peer_ip)"
					else
						# Invalid selectors: log warning but continue parsing (may have valid SAs later)
						handle_error "WARNING" "$location_name" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi for $location_name ($peer_ip)"
						((parse_errors++))
					fi
				else
					# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA
					# This can happen when grep -A includes subsequent SA blocks from other locations
					[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Skipping SA with src=$current_src dst=$current_dst (does not match target peer_ip=$peer_ip)"
				fi
			fi

			# CRITICAL: Only start parsing this SA block if it matches target peer IP (forward SA: dst=$peer_ip, reverse SA: src=$peer_ip)
			# This prevents parsing SAs for wrong locations when grep -A includes subsequent SA blocks
			# Accept both forward SAs (dst=$peer_ip) and reverse SAs (src=$peer_ip) to handle asymmetric SA state
			if [[ "$extracted_dst" == "$peer_ip" ]] || [[ "$extracted_src" == "$peer_ip" ]]; then
				# Start new SA block: extract src and dst from regex match
				current_src="$extracted_src"
				current_dst="$extracted_dst"
				current_proto="" # Will be extracted from continuation lines
				current_spi=""   # Will be extracted from continuation lines
				current_mark=""  # Will be extracted from continuation lines (optional)
				in_sa_block=1    # Mark that we're now parsing an SA block
			else
				# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA block entirely
				# Reset parsing state to skip all continuation lines for this SA
				in_sa_block=0
				current_src=""
				current_dst=""
				current_proto=""
				current_spi=""
				current_mark=""
				[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Skipping SA block with src=$extracted_src dst=$extracted_dst (does not match target peer_ip=$peer_ip)"
			fi

		# State: Continuation line (within an SA block)
		# Extract proto and spi from indented continuation lines
		elif [[ $in_sa_block -eq 1 ]]; then
			# Look for "proto <protocol>" line (may be indented with spaces/tabs)
			# Regex allows optional leading whitespace, captures protocol name
			# Also handles case where "spi" appears on same line: "proto esp spi 0x12345678"
			if [[ "$line" =~ ^[[:space:]]*proto[[:space:]]+([a-zA-Z0-9]+) ]]; then
				# Use default empty string to handle set -u safely (shouldn't happen if regex matches, but defensive)
				current_proto="${BASH_REMATCH[1]:-}"
				# Normalize to lowercase for consistency (xfrm uses lowercase internally)
				current_proto=$(echo "$current_proto" | tr '[:upper:]' '[:lower:]')
				# Check if "spi" is on the same line as "proto" (common format)
				# If found, extract SPI immediately (avoids needing separate line)
				if [[ "$line" =~ [[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
					current_spi="${BASH_REMATCH[1]:-}"
				fi
			fi
			# Look for "spi <spi_value>" on its own line (alternative format)
			# This regex runs after proto check, so it will overwrite SPI if proto line had SPI
			# This is intentional: handles both "proto esp spi 0x123" and separate "spi 0x123" lines
			# Supports hex (0x12345678) and decimal (12345678) formats
			if [[ "$line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
				current_spi="${BASH_REMATCH[1]:-}"
			fi
			# Look for "mark <value>/<mask>" line (optional selector, format: "mark 0x<value>/0x<mask>")
			# Mark is a required selector when present - must be included in deletion commands
			# Format examples: "mark 0x12000000/0xfe000000" or "mark 0x12345678/0xffffffff"
			if [[ "$line" =~ ^[[:space:]]*mark[[:space:]]+(0x[0-9a-fA-F]+/0x[0-9a-fA-F]+) ]]; then
				current_mark="${BASH_REMATCH[1]:-}"
			fi
		fi
	done <<<"$xfrm_output"

	# Finalization: Process the last SA block if parsing ended mid-block
	# This handles the case where the last SA in the output doesn't have a following "src ... dst ..." line
	# to trigger the save logic in the main loop
	if [[ $in_sa_block -eq 1 ]] && [[ -n "$current_src" ]] && [[ -n "$current_dst" ]] && [[ -n "$current_proto" ]] && [[ -n "$current_spi" ]]; then
		# CRITICAL: Verify that the SA matches the target peer IP (forward SA: dst=$peer_ip, reverse SA: src=$peer_ip)
		# This prevents deleting SAs for wrong locations when grep -A includes subsequent SA blocks
		# Accept both forward SAs (dst=$peer_ip) and reverse SAs (src=$peer_ip) to handle asymmetric SA state
		if [[ "$current_dst" == "$peer_ip" ]] || [[ "$current_src" == "$peer_ip" ]]; then
			# Validate selectors before adding to list (same validation as in main loop)
			if [[ "$current_proto" =~ ^(esp|ah)$ ]] && [[ "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
				sa_list+=("$current_src|$current_dst|$current_proto|$current_spi|${current_mark:-}")
				[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Parsed SA: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi mark=${current_mark:-<none>} for $location_name ($peer_ip)"
			else
				handle_error "WARNING" "$location_name" "xfrm recovery: Invalid SA selectors: src=$current_src dst=$current_dst proto=$current_proto spi=$current_spi for $location_name ($peer_ip)"
				((parse_errors++))
			fi
		else
			# SA doesn't match target peer IP (neither dst nor src matches) - skip this SA
			# This can happen when grep -A includes subsequent SA blocks from other locations
			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Skipping final SA with src=$current_src dst=$current_dst (does not match target peer_ip=$peer_ip)"
		fi
	fi

	# Error handling: If parsing produced errors but no valid SAs, fail immediately
	# This indicates a fundamental parsing problem (e.g., format changed, corrupted output)
	# If we have some valid SAs, we continue (partial success is acceptable)
	if [[ $parse_errors -gt 0 ]] && [[ ${#sa_list[@]} -eq 0 ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: Parsing failed for $location_name ($peer_ip) (found $parse_errors invalid SA(s))"
		return 1
	fi

	# Enhanced diagnostics: Log summary of all SAs found before attempting deletion
	# This provides visibility into what we're about to delete and helps identify parsing issues
	# Includes direction information to diagnose asymmetric SA state (only one direction present)
	log_message "INFO" "$location_name" "xfrm recovery: Found ${#sa_list[@]} SA(s) to delete for $location_name ($peer_ip)"
	if [[ ${#sa_list[@]} -gt 0 ]]; then
		local sa_summary=""
		local sa_idx=0
		local forward_count=0
		local reverse_count=0
		for sa_entry in "${sa_list[@]}"; do
			IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
			sa_idx=$((sa_idx + 1))
			# Determine direction for diagnostic clarity (helps identify asymmetric SA state)
			local direction="unknown"
			if [[ "$sa_src" == "$peer_ip" ]]; then
				direction="reverse (peer→local)"
				reverse_count=$((reverse_count + 1))
			elif [[ "$sa_dst" == "$peer_ip" ]]; then
				direction="forward (local→peer)"
				forward_count=$((forward_count + 1))
			fi
			if [[ -n "$sa_mark" ]]; then
				sa_summary="${sa_summary}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction] proto=$sa_proto spi=$sa_spi mark=$sa_mark; "
			else
				sa_summary="${sa_summary}SA${sa_idx}: src=$sa_src dst=$sa_dst [$direction] proto=$sa_proto spi=$sa_spi (no mark); "
			fi
		done
		log_message "INFO" "$location_name" "xfrm recovery: SA summary: ${sa_summary% }"
		# Log bidirectional state diagnostic (helps identify asymmetric SA state)
		if [[ $forward_count -eq 0 ]] || [[ $reverse_count -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: SA bidirectional state diagnostic for $location_name ($peer_ip): forward=$forward_count, reverse=$reverse_count (expected: 1 each for bidirectional tunnel)"
		fi
	fi

	# Delete each parsed SA
	for sa_entry in "${sa_list[@]}"; do
		IFS='|' read -r sa_src sa_dst sa_proto sa_spi sa_mark <<<"$sa_entry"
		[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Processing SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}"

		# Parse mark value and mask if present (format: "0x<value>/0x<mask>")
		# Mark format: ip xfrm expects "mark <value> mask <mask>"
		local mark_value=""
		local mark_mask=""
		if [[ -n "$sa_mark" ]]; then
			if [[ "$sa_mark" =~ ^(0x[0-9a-fA-F]+)/(0x[0-9a-fA-F]+)$ ]]; then
				mark_value="${BASH_REMATCH[1]}"
				mark_mask="${BASH_REMATCH[2]}"
				# Enhanced diagnostics: Log mark parsing details
				log_message "INFO" "$location_name" "xfrm recovery: Parsed mark for SA src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi: raw=$sa_mark, value=$mark_value, mask=$mark_mask"
			else
				# Fallback: if format doesn't match expected pattern, log warning
				handle_error "WARNING" "$location_name" "xfrm recovery: Invalid mark format: $sa_mark (expected format: 0x<value>/0x<mask>) for SA src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi"
			fi
		fi

		# Enhanced diagnostics: Query xfrm state right before deletion to check for race conditions
		# and to capture the exact format the kernel sees
		local pre_delete_xfrm_output
		local pre_delete_query_success=0
		if pre_delete_xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "dst $sa_dst" -A 20 2>/dev/null); then
			pre_delete_query_success=1
			# Check if this specific SA (with all selectors) appears in the output
			# Include mark in check if present (mark is a required selector when present)
			local sa_match=1
			if [[ "$pre_delete_xfrm_output" == *"src $sa_src"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"dst $sa_dst"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"proto $sa_proto"* ]] &&
				[[ "$pre_delete_xfrm_output" == *"spi $sa_spi"* ]]; then
				# If mark is present, verify it matches too
				if [[ -n "$sa_mark" ]]; then
					# Mark format in output: "mark 0x<value>/0x<mask>"
					if [[ ! "$pre_delete_xfrm_output" == *"mark $sa_mark"* ]]; then
						sa_match=0
					fi
				fi
				if [[ $sa_match -eq 1 ]]; then
					# Extract the exact SA block for this specific SA to see what the kernel sees
					# This helps identify if there are additional attributes we're missing
					local exact_sa_block
					exact_sa_block=$(echo "$pre_delete_xfrm_output" | awk '
						/^src '"$sa_src"'[[:space:]]+dst '"$sa_dst"'/ {found=1; print; next}
						found && /^src/ {found=0}
						found {print}
					' | head -20)
					# Enhanced diagnostics: Always log full SA block (not just DEBUG mode)
					# This is critical for debugging deletion failures
					if [[ -n "$sa_mark" ]]; then
						log_message "INFO" "$location_name" "xfrm recovery: Pre-delete SA block for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=$sa_mark:\n$exact_sa_block"
					else
						log_message "INFO" "$location_name" "xfrm recovery: Pre-delete SA block for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi:\n$exact_sa_block"
					fi
					# Enhanced diagnostics: Extract and log all attributes found in SA block
					# This helps identify any selectors we might be missing (e.g., reqid, mode, etc.)
					local all_attrs=""
					if [[ "$exact_sa_block" =~ reqid[[:space:]]+([0-9]+) ]]; then
						all_attrs="${all_attrs}reqid=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ mode[[:space:]]+([a-z]+) ]]; then
						all_attrs="${all_attrs}mode=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ replay-window[[:space:]]+([0-9]+) ]]; then
						all_attrs="${all_attrs}replay-window=${BASH_REMATCH[1]}; "
					fi
					if [[ "$exact_sa_block" =~ flag[[:space:]]+([a-z-]+) ]]; then
						all_attrs="${all_attrs}flag=${BASH_REMATCH[1]}; "
					fi
					if [[ -n "$all_attrs" ]]; then
						log_message "INFO" "$location_name" "xfrm recovery: Additional SA attributes found: ${all_attrs% }"
					fi
				fi
			fi
		fi

		# Build deletion command with all selectors (including mark if present)
		# Mark is a required selector when present - must be included for successful deletion
		local delete_cmd="ip xfrm state delete src \"$sa_src\" dst \"$sa_dst\" proto \"$sa_proto\" spi \"$sa_spi\""
		if [[ -n "$mark_value" ]] && [[ -n "$mark_mask" ]]; then
			delete_cmd="$delete_cmd mark \"$mark_value\" mask \"$mark_mask\""
		fi

		# Try to query the exact SA using ip xfrm state get to see what the kernel expects
		# This helps identify if we need additional selectors
		# Note: We capture output with 2>&1 - on success (exit 0), output is stdout (SA details)
		# On failure (non-zero exit), output is stderr (error message)
		local get_sa_cmd="ip xfrm state get src \"$sa_src\" dst \"$sa_dst\" proto \"$sa_proto\" spi \"$sa_spi\""
		if [[ -n "$mark_value" ]] && [[ -n "$mark_mask" ]]; then
			get_sa_cmd="$get_sa_cmd mark \"$mark_value\" mask \"$mark_mask\""
		fi
		local get_sa_output
		local get_sa_stderr=""
		local get_sa_exit_code
		local get_sa_start_time
		get_sa_start_time=$(get_unix_timestamp 2>/dev/null || echo "0")
		get_sa_output=$(eval "$get_sa_cmd" 2>&1)
		get_sa_exit_code=$?
		local get_sa_duration=0
		if [[ "$get_sa_start_time" != "0" ]]; then
			local get_sa_end_time
			get_sa_end_time=$(get_unix_timestamp 2>/dev/null || echo "0")
			if [[ "$get_sa_end_time" != "0" ]]; then
				get_sa_duration=$(safe_timestamp_diff "$get_sa_end_time" "$get_sa_start_time" 2>/dev/null || echo "0")
				# Ensure non-negative duration
				if [[ $get_sa_duration -lt 0 ]]; then
					get_sa_duration=0
				fi
			fi
		fi
		# Separate stdout from stderr based on exit code
		if [[ $get_sa_exit_code -ne 0 ]]; then
			# On failure, the captured output is stderr
			get_sa_stderr="$get_sa_output"
			get_sa_output=""
		fi
		# Enhanced diagnostics: Always log the exact commands we're executing (not just DEBUG mode)
		# This is critical for debugging deletion failures
		log_message "INFO" "$location_name" "xfrm recovery: Executing delete command: $delete_cmd"
		if [[ $get_sa_exit_code -eq 0 ]] && [[ -n "$get_sa_output" ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Kernel SA get succeeded (${get_sa_duration}s) for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}:\n$get_sa_output"
			# Enhanced diagnostics: Compare parsed selectors vs what kernel returns
			# Extract all attributes from kernel output to identify any we're missing
			local kernel_attrs=""
			if [[ "$get_sa_output" =~ mark[[:space:]]+(0x[0-9a-fA-F]+/0x[0-9a-fA-F]+) ]]; then
				kernel_attrs="${kernel_attrs}mark=${BASH_REMATCH[1]}; "
			fi
			if [[ -n "$kernel_attrs" ]]; then
				log_message "INFO" "$location_name" "xfrm recovery: Kernel SA attributes: ${kernel_attrs% }"
			fi
		elif [[ -n "$get_sa_stderr" ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Kernel SA get failed (exit_code=$get_sa_exit_code, ${get_sa_duration}s) for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=${sa_mark:-<none>}: $get_sa_stderr"
		fi

		# Capture stderr and exit code for diagnostic purposes
		# Enhanced diagnostics: Add timing information for deletion operations
		local delete_stderr
		local delete_exit_code
		local delete_start_time
		delete_start_time=$(get_unix_timestamp 2>/dev/null || echo "0")
		delete_stderr=$(eval "$delete_cmd" 2>&1)
		delete_exit_code=$?
		local delete_duration=0
		if [[ "$delete_start_time" != "0" ]]; then
			local delete_end_time
			delete_end_time=$(get_unix_timestamp 2>/dev/null || echo "0")
			if [[ "$delete_end_time" != "0" ]]; then
				delete_duration=$(safe_timestamp_diff "$delete_end_time" "$delete_start_time" 2>/dev/null || echo "0")
				# Ensure non-negative duration
				if [[ $delete_duration -lt 0 ]]; then
					delete_duration=0
				fi
			fi
		fi

		if [[ $delete_exit_code -eq 0 ]]; then
			# Enhanced diagnostics: Include timing information in success messages
			if [[ -n "$sa_mark" ]]; then
				log_message "INFO" "$location_name" "xfrm recovery: Deleted SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=$sa_mark for $location_name ($peer_ip) (duration: ${delete_duration}s)"
			else
				log_message "INFO" "$location_name" "xfrm recovery: Deleted SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi for $location_name ($peer_ip) (duration: ${delete_duration}s)"
			fi
			((deleted_count++))
		else
			# Deletion failed - gather comprehensive diagnostic information
			# Enhanced diagnostics: Include timing information in failure diagnostics
			local diagnostic_info="exit_code=$delete_exit_code, duration=${delete_duration}s"

			# Add stderr output if present
			if [[ -n "$delete_stderr" ]]; then
				diagnostic_info="$diagnostic_info, stderr=\"$delete_stderr\""
			fi

			# Add mark information if present
			if [[ -n "$sa_mark" ]]; then
				diagnostic_info="$diagnostic_info, mark=$sa_mark"
			fi

			# Add information about pre-delete query
			if [[ $pre_delete_query_success -eq 1 ]]; then
				# Check if SA still exists (could indicate race condition or permissions issue)
				# Query xfrm state for this peer and check if the specific SA (src+dst+proto+spi) still exists
				# Use get_xfrm_state_for_peer to get full SA blocks, then check if all selectors appear together
				local peer_xfrm_output
				if peer_xfrm_output=$(get_xfrm_state_for_peer "$sa_dst" 2>/dev/null); then
					# Check if all selectors appear in the output (they may be on different lines)
					# This is a simple check - if all selectors are present, the SA likely still exists
					# Include mark in check if present (mark is a required selector when present)
					local sa_exists_check=1
					if [[ "$peer_xfrm_output" == *"src $sa_src"* ]] &&
						[[ "$peer_xfrm_output" == *"dst $sa_dst"* ]] &&
						[[ "$peer_xfrm_output" == *"proto $sa_proto"* ]] &&
						[[ "$peer_xfrm_output" == *"spi $sa_spi"* ]]; then
						# If mark is present, verify it matches too
						if [[ -n "$sa_mark" ]]; then
							# Mark format in output: "mark 0x<value>/0x<mask>"
							if [[ ! "$peer_xfrm_output" == *"mark $sa_mark"* ]]; then
								sa_exists_check=0
							fi
						fi
						if [[ $sa_exists_check -eq 1 ]]; then
							diagnostic_info="$diagnostic_info, sa_still_exists=true"
							# If SA exists but deletion failed, extract the exact SA block for detailed logging
							# This helps identify if there are additional attributes we're missing
							local sa_block_details
							sa_block_details=$(echo "$peer_xfrm_output" | awk '
								/^src '"$sa_src"'[[:space:]]+dst '"$sa_dst"'/ {found=1; print; next}
								found && /^src/ {found=0}
								found {print}
							' | head -15)
							# Log the exact SA block separately to avoid breaking log message formatting
							# Only log if we have block details (avoids empty logs)
							if [[ -n "$sa_block_details" ]]; then
								if [[ -n "$sa_mark" ]]; then
									log_message "INFO" "$location_name" "xfrm recovery: SA block that exists but couldn't be deleted for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=$sa_mark:\n$sa_block_details"
								else
									log_message "INFO" "$location_name" "xfrm recovery: SA block that exists but couldn't be deleted for src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi:\n$sa_block_details"
								fi
							fi
						else
							diagnostic_info="$diagnostic_info, sa_still_exists=false"
						fi
					else
						diagnostic_info="$diagnostic_info, sa_still_exists=false"
					fi
				else
					# Failed to query xfrm state - can't determine if SA exists
					diagnostic_info="$diagnostic_info, sa_still_exists=unknown"
				fi
			else
				diagnostic_info="$diagnostic_info, pre_delete_query_failed=true"
			fi

			# Add information about get command attempt
			if [[ $get_sa_exit_code -eq 0 ]] && [[ -n "$get_sa_output" ]]; then
				diagnostic_info="$diagnostic_info, get_sa_succeeded=true"
			elif [[ -n "$get_sa_stderr" ]]; then
				diagnostic_info="$diagnostic_info, get_sa_failed=\"$get_sa_stderr\""
			fi

			# Log comprehensive diagnostic information
			if [[ -n "$sa_mark" ]]; then
				handle_error "WARNING" "$location_name" "xfrm recovery: Failed to delete SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi mark=$sa_mark for $location_name ($peer_ip) ($diagnostic_info)"
			else
				handle_error "WARNING" "$location_name" "xfrm recovery: Failed to delete SA: src=$sa_src dst=$sa_dst proto=$sa_proto spi=$sa_spi for $location_name ($peer_ip) ($diagnostic_info)"
			fi

			# Log the raw xfrm output we parsed (helps identify parsing issues vs kernel state)
			# Only log once per recovery attempt to avoid excessive logging
			if [[ $raw_xfrm_output_logged -eq 0 ]]; then
				# Truncate very long output to avoid log bloat (first 50 lines should be enough)
				local truncated_xfrm_output
				truncated_xfrm_output=$(echo "$xfrm_output" | head -50)
				log_message "INFO" "$location_name" "xfrm recovery: Raw xfrm output parsed (first 50 lines):\n$truncated_xfrm_output"
				raw_xfrm_output_logged=1
			fi

			((failed_count++))
		fi
	done

	# Enhanced diagnostics: Log summary of deletion results
	if [[ $deleted_count -gt 0 ]] || [[ $failed_count -gt 0 ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Deletion summary for $location_name ($peer_ip): ${deleted_count} succeeded, ${failed_count} failed out of ${#sa_list[@]} total SA(s)"
	fi

	# Also delete policies for this peer (less critical, but helps cleanup)
	# Policies require DIR (direction) parameter for deletion: in, out, or fwd
	# Query existing policies first to determine which directions exist, then delete each
	# Enhanced diagnostics: Add timing and more detailed policy deletion diagnostics
	#
	# Safety: Policy deletion is scoped to ONLY the failing peer IP:
	#   - Uses fixed-string matching (grep -F) to prevent regex injection
	#   - Matches exact "dst $peer_ip" pattern (space after "dst " provides natural boundary)
	#   - Only deletes policies for the specific peer IP that triggered recovery
	#   - Policies are automatically recreated by strongSwan when SAs re-establish
	#   - Policy deletion failures are non-fatal and don't affect recovery success
	#
	# When policies are deleted:
	#   - Only during xfrm recovery for a specific failing peer IP
	#   - Only after SAs for that peer IP have been deleted
	#   - Only policies matching dst=$peer_ip (exact match, not partial)
	#   - Policies for other peer IPs are never touched
	#
	# Note: peer_ip is the external IP of remote locations (from LOCATION_*_EXTERNAL config)
	local existing_policies
	existing_policies=$(ip xfrm policy 2>/dev/null | grep -F "dst $peer_ip" -A 5 2>/dev/null || echo "")

	local policy_deleted_count=0
	local policy_failed_count=0
	local policy_directions=()

	# Parse directions from existing policies
	# Policy format: "src <ip> dst <ip> dir <direction> ..."
	# Directions can be: in, out, fwd
	if [[ -n "$existing_policies" ]]; then
		while IFS= read -r policy_line || [[ -n "$policy_line" ]]; do
			# Extract direction from policy line (format: "dir <direction>")
			if [[ "$policy_line" =~ dir[[:space:]]+([a-z]+) ]]; then
				local dir="${BASH_REMATCH[1]}"
				# Validate direction is one of the expected values
				if [[ "$dir" == "in" ]] || [[ "$dir" == "out" ]] || [[ "$dir" == "fwd" ]]; then
					# Add to array if not already present (avoid duplicates)
					local dir_exists=0
					for existing_dir in "${policy_directions[@]}"; do
						if [[ "$existing_dir" == "$dir" ]]; then
							dir_exists=1
							break
						fi
					done
					if [[ $dir_exists -eq 0 ]]; then
						policy_directions+=("$dir")
					fi
				fi
			fi
		done <<<"$existing_policies"
	fi

	# If no directions found in existing policies, try deleting for all common directions
	# This handles cases where policy format may differ or policies exist but weren't parsed
	if [[ ${#policy_directions[@]} -eq 0 ]]; then
		# Try common directions: fwd (most common for VPN tunnels), out, in
		policy_directions=("fwd" "out" "in")
		log_message "INFO" "$location_name" "xfrm recovery: No policy directions parsed for dst=$peer_ip, attempting deletion for common directions (fwd, out, in)"
	else
		log_message "INFO" "$location_name" "xfrm recovery: Found policy directions for dst=$peer_ip: ${policy_directions[*]}"
	fi

	# Delete policies for each direction found
	for policy_dir in "${policy_directions[@]}"; do
		local policy_stderr
		local policy_exit_code
		local policy_start_time
		policy_start_time=$(get_unix_timestamp 2>/dev/null || echo "0")
		local policy_cmd="ip xfrm policy delete dst \"$peer_ip\" dir \"$policy_dir\""
		log_message "INFO" "$location_name" "xfrm recovery: Executing policy deletion command: $policy_cmd"
		policy_stderr=$(eval "$policy_cmd" 2>&1)
		policy_exit_code=$?
		local policy_duration=0
		if [[ "$policy_start_time" != "0" ]]; then
			local policy_end_time
			policy_end_time=$(get_unix_timestamp 2>/dev/null || echo "0")
			if [[ "$policy_end_time" != "0" ]]; then
				policy_duration=$(safe_timestamp_diff "$policy_end_time" "$policy_start_time" 2>/dev/null || echo "0")
				# Ensure non-negative duration
				if [[ $policy_duration -lt 0 ]]; then
					policy_duration=0
				fi
			fi
		fi

		if [[ $policy_exit_code -eq 0 ]]; then
			((policy_deleted_count++))
			log_message "INFO" "$location_name" "xfrm recovery: Deleted xfrm policy for dst=$peer_ip dir=$policy_dir ($location_name) (duration: ${policy_duration}s)"
		else
			# Policy deletion failed - log diagnostic info (non-fatal, so use INFO level)
			# Enhanced diagnostics: Always log policy deletion failures (not just DEBUG mode)
			((policy_failed_count++))
			local policy_diagnostic="exit_code=$policy_exit_code, duration=${policy_duration}s"
			if [[ -n "$policy_stderr" ]]; then
				policy_diagnostic="$policy_diagnostic, stderr=\"$policy_stderr\""
			fi
			log_message "INFO" "$location_name" "xfrm recovery: Failed to delete xfrm policy for dst=$peer_ip dir=$policy_dir ($location_name) ($policy_diagnostic) - non-fatal, continuing"
		fi
	done

	# Log summary of policy deletion results
	if [[ $policy_deleted_count -gt 0 ]] || [[ $policy_failed_count -gt 0 ]]; then
		if [[ $policy_deleted_count -gt 0 ]] && [[ $policy_failed_count -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$peer_ip ($location_name): ${policy_deleted_count} succeeded, 0 failed"
		elif [[ $policy_deleted_count -eq 0 ]] && [[ $policy_failed_count -gt 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$peer_ip ($location_name): 0 succeeded, ${policy_failed_count} failed (non-fatal)"
		else
			log_message "INFO" "$location_name" "xfrm recovery: Policy deletion summary for dst=$peer_ip ($location_name): ${policy_deleted_count} succeeded, ${policy_failed_count} failed (non-fatal)"
		fi
	fi

	# Enhanced diagnostics: Log existing policies if deletion failed for all directions
	if [[ $policy_deleted_count -eq 0 ]] && [[ -n "$existing_policies" ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Existing policies for dst=$peer_ip:\n$existing_policies"
	fi

	# If no SAs were deleted, check if any existed
	if [[ $deleted_count -eq 0 ]] && [[ $failed_count -eq 0 ]]; then
		if [[ ${#sa_list[@]} -eq 0 ]]; then
			log_message "INFO" "$location_name" "xfrm recovery: No SAs found to delete for $location_name ($peer_ip)"
			return 0
		else
			handle_error "WARNING" "$location_name" "xfrm recovery: Parsed ${#sa_list[@]} SA(s) but failed to delete any for $location_name ($peer_ip)"
			return 1
		fi
	fi

	# If we deleted SAs, verify they're gone and wait for re-establishment
	if [[ $deleted_count -gt 0 ]]; then
		log_message "INFO" "$location_name" "xfrm recovery: Deleted $deleted_count SA(s) for $location_name ($peer_ip)"
		# Wait a moment for strongSwan to detect SA deletion
		sleep "$XFRM_RECOVERY_SLEEP_SECONDS"

		# Verify SAs were deleted
		if command -v check_ipsec_phase2 >/dev/null 2>&1; then
			if check_ipsec_phase2 "$peer_ip"; then
				handle_error "WARNING" "$location_name" "xfrm recovery: SAs still exist after deletion attempt for $location_name ($peer_ip)"
				# Continue anyway - may have deleted some but not all
			fi
		fi

		# Verification Phase: Wait for SA re-establishment with exponential backoff
		# After deletion, strongSwan needs time to detect SA removal and re-establish new SAs
		# We poll periodically using exponential backoff to balance responsiveness and efficiency
		#
		# Backoff algorithm:
		#   - Start with base_interval (default: 2 seconds)
		#   - Double interval each attempt: 2s → 4s → 8s → 16s
		#   - Cap at max_interval (default: 16 seconds) to prevent excessive delays
		#   - Continue until timeout reached or SA re-established
		#
		# Rationale: Early checks are frequent (quick detection), later checks are spaced out
		# (reduces CPU usage for slow re-establishments)
		local verify_timeout="${RECOVERY_VERIFY_TIMEOUT:-${XFRM_RECOVERY_VERIFY_TIMEOUT:-30}}"
		local base_interval="${XFRM_RECOVERY_VERIFY_INTERVAL:-2}"
		local max_interval="${XFRM_RECOVERY_MAX_INTERVAL:-16}"
		local current_interval=$base_interval

		log_message "INFO" "$location_name" "xfrm recovery: Waiting for SA re-establishment for $location_name ($peer_ip) (timeout: ${verify_timeout}s)"
		local verify_start_time
		verify_start_time=$(get_unix_timestamp)
		local sa_reestablished=0
		local verify_attempt=0
		local elapsed_time
		local sa_count=0
		local initial_sa_count=0
		local initial_sa_count_set=0
		local sa_count_checks_after_reestablish=0
		local max_sa_count_checks=3
		local byte_counter_status="unknown"
		local initial_byte_counter=""
		local initial_byte_counter_set=0
		local ping_skip_logged=0

		# Verification loop: Poll until SA re-established or timeout
		# Timeout check: Compare elapsed time against configured timeout
		while true; do
			# Calculate elapsed time at start of each iteration
			local current_time
			current_time=$(get_unix_timestamp)
			elapsed_time=$(safe_timestamp_diff "$current_time" "$verify_start_time" 2>/dev/null || echo "0")
			# Ensure elapsed_time is non-negative (should be if current_time >= verify_start_time)
			if [[ $elapsed_time -lt 0 ]]; then
				elapsed_time=0
			fi

			# Check timeout condition
			if [[ $elapsed_time -ge $verify_timeout ]]; then
				break
			fi

			verify_attempt=$((verify_attempt + 1))

			# Check if SA is re-established using detection function
			# This checks both xfrm state and ipsec status for comprehensive verification
			if command -v check_ipsec_phase2 >/dev/null 2>&1; then
				if check_ipsec_phase2 "$peer_ip"; then
					# SA re-established - perform additional verification checks
					sa_reestablished=1

					# Count SAs for logging (may have multiple SAs for one peer)
					# This provides visibility into how many SAs were re-established
					# Pass location_name for enhanced diagnostic logging
					if sa_count=$(count_sas_for_peer "$peer_ip" "$location_name" 2>/dev/null); then
						# Track initial SA count when first re-established (helps detect timing issues)
						if [[ $initial_sa_count_set -eq 0 ]]; then
							initial_sa_count=$sa_count
							initial_sa_count_set=1
							log_message "INFO" "$location_name" "xfrm recovery: SA re-established for $location_name ($peer_ip) after ${elapsed_time}s (attempt $verify_attempt, SA count: $sa_count, deleted: $deleted_count)"
							# Check if SA count mismatch (deleted more than re-established)
							if [[ $deleted_count -gt 0 ]] && [[ $sa_count -lt $deleted_count ]]; then
								log_message "INFO" "$location_name" "xfrm recovery: SA count mismatch detected for $location_name ($peer_ip): deleted=$deleted_count, re-established=$sa_count (will continue checking for additional SAs)"
							fi
						else
							# SA already re-established - check if count has increased (second SA appeared)
							if [[ $sa_count -gt $initial_sa_count ]]; then
								log_message "INFO" "$location_name" "xfrm recovery: SA count increased for $location_name ($peer_ip): initial=$initial_sa_count, current=$sa_count (second SA appeared after ${elapsed_time}s)"
								initial_sa_count=$sa_count
							elif [[ $sa_count_checks_after_reestablish -lt $max_sa_count_checks ]]; then
								# Continue checking SA count for a few more iterations to catch second SA
								sa_count_checks_after_reestablish=$((sa_count_checks_after_reestablish + 1))
								[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Checking SA count again for $location_name ($peer_ip) (check $sa_count_checks_after_reestablish/$max_sa_count_checks, current=$sa_count, deleted=$deleted_count)"
							fi
						fi
					else
						if [[ $initial_sa_count_set -eq 0 ]]; then
							log_message "INFO" "$location_name" "xfrm recovery: SA re-established for $location_name ($peer_ip) after ${elapsed_time}s (attempt $verify_attempt, SA count unavailable)"
						fi
					fi

					# Capture initial byte counter value when SA is first re-established
					# Byte counters may reset to zero after SA deletion/re-establishment, so we
					# need to track the baseline and check for increment rather than absolute value
					if [[ $initial_byte_counter_set -eq 0 ]]; then
						local xfrm_output
						xfrm_output=$(get_xfrm_state_for_peer "$peer_ip" 2>/dev/null)
						if [[ -n "$xfrm_output" ]] && command -v extract_byte_counter >/dev/null 2>&1; then
							if initial_byte_counter=$(extract_byte_counter "$xfrm_output" 2>/dev/null); then
								# Validate initial_byte_counter is numeric (default to 0 if not)
								if [[ ! "$initial_byte_counter" =~ ^[0-9]+$ ]]; then
									initial_byte_counter=0
								fi
								initial_byte_counter_set=1
								log_message "INFO" "$location_name" "xfrm recovery: Captured initial byte counter for $location_name ($peer_ip) (initial=$initial_byte_counter)"
							else
								# Byte counters not available - set to 0 and mark as set
								initial_byte_counter=0
								initial_byte_counter_set=1
								log_message "INFO" "$location_name" "xfrm recovery: Byte counters not available for $location_name ($peer_ip) (using initial=0)"
							fi
						else
							# Failed to get xfrm output - set to 0 and mark as set
							initial_byte_counter=0
							initial_byte_counter_set=1
							log_message "INFO" "$location_name" "xfrm recovery: Failed to get initial byte counter for $location_name ($peer_ip) (using initial=0)"
						fi
					fi

					# Verify byte counters increment from initial value (indicates tunnel is passing traffic)
					# This handles the case where byte counters reset to zero after SA deletion/re-establishment
					# We check for increment rather than absolute non-zero value to verify traffic is flowing
					#
					# Enhancement: If counters are zero, ping internal IP to generate traffic, then check again
					# This actively verifies the tunnel can pass traffic rather than waiting passively
					if [[ "$initial_byte_counter" -eq 0 ]]; then
						if [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
							# Get internal IPs for this location to ping
							local internal_ips=""
							if command -v get_location_internal_ips >/dev/null 2>&1 && command -v parse_location_config >/dev/null 2>&1; then
								# Ensure location config is parsed (may not be if called directly)
								if ! declare -p LOCATIONS &>/dev/null 2>&1; then
									parse_location_config 2>/dev/null || true
								fi
								internal_ips=$(get_location_internal_ips "$location_name" 2>/dev/null || echo "")
							fi

							# If we have internal IPs, ping the first one to generate traffic
							if [[ -n "$internal_ips" ]]; then
								local first_internal_ip
								first_internal_ip=$(echo "$internal_ips" | awk '{print $1}')
								if [[ -n "$first_internal_ip" ]] && command -v check_ping_connectivity >/dev/null 2>&1; then
									local local_ip
									local_ip=$(get_local_ip_for_ping 2>/dev/null || echo "")
									log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero, pinging internal IP $first_internal_ip to generate traffic for $location_name ($peer_ip)"
									# Ping to generate traffic (ignore ping result - we only care about byte counter increment)
									check_ping_connectivity "$first_internal_ip" "$local_ip" "$location_name" >/dev/null 2>&1 || true
									# Small delay to allow counters to update
									sleep 1
								else
									# Ping function not available - log at debug level (non-critical)
									[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Ping function not available, skipping ping-based traffic generation for $location_name ($peer_ip)"
								fi
							else
								# No internal IPs configured - log at info level (helpful for debugging, only once)
								if [[ $ping_skip_logged -eq 0 ]]; then
									log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero but no internal IPs configured for $location_name ($peer_ip), waiting for natural traffic flow"
									ping_skip_logged=1
								fi
							fi
						else
							# Ping check disabled - log at info level (helpful for debugging, only once)
							if [[ $ping_skip_logged -eq 0 ]]; then
								log_message "INFO" "$location_name" "xfrm recovery: Byte counters are zero but ping check is disabled (ENABLE_PING_CHECK=0) for $location_name ($peer_ip), waiting for natural traffic flow"
								ping_skip_logged=1
							fi
						fi
					fi

					if verify_byte_counters_increment "$peer_ip" "$initial_byte_counter" "$location_name" 2>/dev/null; then
						byte_counter_status="resumed"
						log_message "INFO" "$location_name" "xfrm recovery: Verification complete for $location_name ($peer_ip) (duration: ${elapsed_time}s, SA count: ${sa_count}, byte counters: ${byte_counter_status})"
						break # Exit verification loop on success (SA re-established AND byte counters verified)
					else
						byte_counter_status="zero_or_unavailable"
						# Log warning but continue waiting - byte counters may resume shortly
						# Only break if timeout occurs (handled by timeout check at start of loop)
						handle_error "WARNING" "$location_name" "xfrm recovery: SA re-established but byte counters not verified for $location_name ($peer_ip) (will continue waiting)"
					fi
				fi
			fi

			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "$location_name" "xfrm recovery: Verification attempt $verify_attempt for $location_name ($peer_ip) (elapsed: ${elapsed_time}s/${verify_timeout}s, next interval: ${current_interval}s)"

			# Exponential backoff: Sleep before next check
			# Interval doubles each attempt, capped at max_interval
			# This reduces CPU usage for slow re-establishments while maintaining responsiveness
			sleep "$current_interval"
			current_interval=$((current_interval * 2))
			if [[ $current_interval -gt $max_interval ]]; then
				current_interval=$max_interval # Cap at maximum to prevent excessive delays
			fi
		done

		# Final SA count check: Log warning if we deleted multiple SAs but only one re-established
		# This helps diagnose asymmetric SA state or timing issues where second SA takes longer
		if [[ $sa_reestablished -eq 1 ]] && [[ $deleted_count -gt 1 ]] && [[ $initial_sa_count_set -eq 1 ]]; then
			# Get final SA count for comparison
			local final_sa_count
			if final_sa_count=$(count_sas_for_peer "$peer_ip" "$location_name" 2>/dev/null); then
				if [[ $final_sa_count -lt $deleted_count ]]; then
					log_message "INFO" "$location_name" "xfrm recovery: SA count mismatch persists for $location_name ($peer_ip): deleted=$deleted_count, final_count=$final_sa_count (may indicate asymmetric SA state or incomplete re-establishment)"
				fi
			fi
		fi

		if [[ $sa_reestablished -eq 0 ]]; then
			current_time=$(get_unix_timestamp)
			elapsed_time=$(safe_timestamp_diff "$current_time" "$verify_start_time" 2>/dev/null || echo "0")
			if [[ $elapsed_time -lt 0 ]]; then
				elapsed_time=0
			fi
			handle_error "WARNING" "$location_name" "xfrm recovery: SA did not re-establish within ${verify_timeout}s for $location_name ($peer_ip) (verification duration: ${elapsed_time}s, attempts: $verify_attempt)"
			handle_error "WARNING" "$location_name" "xfrm recovery: Partial success - deleted SAs but re-establishment timeout for $location_name ($peer_ip), will fall back to alternative recovery"
			return 1
		fi

		# SA was re-established - check if byte counters were verified
		if [[ "$byte_counter_status" != "resumed" ]]; then
			current_time=$(get_unix_timestamp)
			elapsed_time=$(safe_timestamp_diff "$current_time" "$verify_start_time" 2>/dev/null || echo "0")
			if [[ $elapsed_time -lt 0 ]]; then
				elapsed_time=0
			fi
			handle_error "WARNING" "$location_name" "xfrm recovery: SA re-established but byte counter verification failed within ${verify_timeout}s for $location_name ($peer_ip) (verification duration: ${elapsed_time}s, attempts: $verify_attempt)"
			# Byte counter verification failed - return error to trigger fallback recovery
			return 1
		fi

		return 0
	elif [[ $failed_count -gt 0 ]]; then
		handle_error "WARNING" "$location_name" "xfrm recovery: Failed to delete $failed_count SA(s) for $location_name ($peer_ip)"
		return 1
	fi

	# Should not reach here, but handle gracefully
	return 1
}

# Check availability of recovery commands
#
# Checks which recovery commands are available and stores results in global variables.
# This centralizes command availability checks to simplify strategy selection logic.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (results stored in global variables)
#
# Output (via global variables):
#   _RECOVERY_IP_AVAILABLE: 1 if ip command available, 0 otherwise
#   _RECOVERY_IPSEC_AVAILABLE: 1 if ipsec command available, 0 otherwise
#   _RECOVERY_IPSEC_PATH: Full path to ipsec command if found, or "ipsec" if relying on PATH
#
# Note:
#   This is a helper function for select_recovery_strategy()
#   Uses global variables with underscore prefix to indicate internal use
#   Stores full path to ipsec command to ensure reliable execution even when PATH is restricted
_check_recovery_command_availability() {
	declare -g _RECOVERY_IP_AVAILABLE=0
	declare -g _RECOVERY_IPSEC_AVAILABLE=0
	declare -g _RECOVERY_IPSEC_PATH=""

	if check_command_available "ip"; then
		_RECOVERY_IP_AVAILABLE=1
	fi

	if check_command_available "ipsec"; then
		_RECOVERY_IPSEC_AVAILABLE=1
		# Get full path to ipsec command for reliable execution
		# Uses get_command_path() helper which handles PATH restrictions
		if command -v get_command_path >/dev/null 2>&1; then
			_RECOVERY_IPSEC_PATH=$(get_command_path "ipsec")
		else
			# Fallback if get_command_path not available (shouldn't happen)
			_RECOVERY_IPSEC_PATH="ipsec"
		fi
	fi
}

# Check if a recovery strategy is applicable
#
# Determines if a recovery strategy can be used based on peer IP, tier,
# configuration, and command availability.
#
# Arguments:
#   $1: Strategy name ("xfrm", "ipsec_reload", "ipsec_restart")
#   $2: Peer IP address (optional, required for per-connection recovery)
#   $3: Tier level (2 for surgical cleanup, 3 for full restart)
#
# Returns:
#   0: Strategy is applicable
#   1: Strategy is not applicable
#
# Note:
#   Uses global variables _RECOVERY_IP_AVAILABLE and _RECOVERY_IPSEC_AVAILABLE
#   Requires ENABLE_XFRM_RECOVERY configuration variable
_is_strategy_applicable() {
	local strategy="$1"
	local peer_ip="${2:-}"
	local tier="${3:-2}"

	case "$strategy" in
	"xfrm")
		# Requires peer IP, xfrm recovery enabled, and ip command available
		[[ -n "$peer_ip" ]] &&
			[[ "${ENABLE_XFRM_RECOVERY:-1}" -eq 1 ]] &&
			[[ "${_RECOVERY_IP_AVAILABLE:-0}" -eq 1 ]]
		;;
	"ipsec_reload")
		# Requires tier 2 and ipsec command available
		[[ "$tier" == "2" ]] &&
			[[ "${_RECOVERY_IPSEC_AVAILABLE:-0}" -eq 1 ]]
		;;
	"ipsec_restart")
		# Requires tier 3 and ipsec command available
		[[ "$tier" == "3" ]] &&
			[[ "${_RECOVERY_IPSEC_AVAILABLE:-0}" -eq 1 ]]
		;;
	*)
		return 1
		;;
	esac
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
#   RECOVERY_STRATEGY: Strategy name ("xfrm", "ipsec_reload", "ipsec_restart", or "unavailable")
#   RECOVERY_COMMAND: Command to execute (function name or command string)
#   RECOVERY_IMPACT: Impact description ("per-connection" or "all-tunnels")
#   RECOVERY_AVAILABLE: Whether recovery is available (1) or not (0)
#
# Strategy Selection Algorithm:
#   Implements a priority-based selection system using a lookup table approach.
#   Strategies are evaluated in priority order, and the first applicable strategy is selected.
#
#   Priority order (highest to lowest):
#   1. "xfrm" - Per-connection recovery (surgical, least disruptive)
#   2. "ipsec_reload" - Tier 2 recovery (affects all tunnels, moderate disruption)
#   3. "ipsec_restart" - Tier 3 recovery (affects all tunnels, most disruptive)
#
#   Strategy applicability conditions:
#   - "xfrm": Requires peer IP, ENABLE_XFRM_RECOVERY=1, and 'ip' command available
#   - "ipsec_reload": Requires tier=2 and 'ipsec' command available
#   - "ipsec_restart": Requires tier=3 and 'ipsec' command available
#
#   Selection process:
#   1. Validate tier parameter (must be 2 or 3)
#   2. Check command availability (ip, ipsec) via _check_recovery_command_availability()
#   3. Iterate through strategies in priority order
#   4. For each strategy, check applicability via _is_strategy_applicable()
#   5. Select first applicable strategy and set global variables
#   6. If no strategy applicable, set RECOVERY_STRATEGY="unavailable" and return error
#
# Edge Cases and Assumptions:
#   - Empty peer IP: xfrm strategy not applicable, falls back to ipsec_reload/restart
#   - ENABLE_XFRM_RECOVERY=0: xfrm strategy not applicable, even with peer IP
#   - Missing 'ip' command: xfrm strategy not applicable, falls back to ipsec strategies
#   - Missing 'ipsec' command: All strategies unavailable, returns error
#   - Invalid tier: Returns error immediately (doesn't check strategies)
#   - Tier 2 with peer IP: Prefers xfrm, falls back to ipsec_reload if xfrm unavailable
#   - Tier 3 with peer IP: Prefers xfrm, falls back to ipsec_restart if xfrm unavailable
#
#   Assumptions:
#   - Command availability doesn't change during function execution
#   - Configuration variables (ENABLE_XFRM_RECOVERY) are set before calling
#   - Tier 2 is for surgical cleanup, Tier 3 is for full restart
#   - Per-connection recovery (xfrm) is always preferred when available
#   - All-tunnels recovery (ipsec_reload/restart) is acceptable fallback
#
# Strategy Details:
#   1. "xfrm" - Per-connection recovery
#      - Command: attempt_xfrm_recovery function
#      - Impact: "per-connection" (only affects specified peer)
#      - Use case: Targeted recovery when peer IP is known
#      - Advantages: Minimal disruption, fast recovery
#      - Requirements: Peer IP, xfrm recovery enabled, ip command
#
#   2. "ipsec_reload" - Tier 2 recovery
#      - Command: "ipsec reload" (shell command string)
#      - Impact: "all-tunnels" (affects all VPN connections)
#      - Use case: Surgical cleanup when xfrm unavailable or failed
#      - Advantages: Less disruptive than restart, reloads config
#      - Requirements: Tier 2, ipsec command
#
#   3. "ipsec_restart" - Tier 3 recovery
#      - Command: "ipsec restart" (shell command string)
#      - Impact: "all-tunnels" (affects all VPN connections)
#      - Use case: Full restart when other strategies unavailable or failed
#      - Advantages: Most thorough recovery, resets all state
#      - Requirements: Tier 3, ipsec command
#
# Implementation Notes:
#   - Uses _check_recovery_command_availability() to cache command availability
#   - Uses _is_strategy_applicable() to evaluate strategy conditions
#   - Strategy lookup table format: "strategy_name:command:impact"
#   - Global variables are declared with declare -g for proper scoping
#   - Returns immediately after finding first applicable strategy
#
# Examples:
#   # Tier 2 recovery with peer IP (prefers xfrm)
#   select_recovery_strategy "203.0.113.1" 2
#   # Result: RECOVERY_STRATEGY="xfrm", RECOVERY_COMMAND="attempt_xfrm_recovery"
#   #         RECOVERY_IMPACT="per-connection", RECOVERY_AVAILABLE=1
#
#   # Tier 2 recovery without peer IP (uses ipsec_reload)
#   select_recovery_strategy "" 2
#   # Result: RECOVERY_STRATEGY="ipsec_reload", RECOVERY_COMMAND="ipsec reload"
#   #         RECOVERY_IMPACT="all-tunnels", RECOVERY_AVAILABLE=1
#
#   # Tier 3 recovery (uses ipsec_restart)
#   select_recovery_strategy "" 3
#   # Result: RECOVERY_STRATEGY="ipsec_restart", RECOVERY_COMMAND="ipsec restart"
#   #         RECOVERY_IMPACT="all-tunnels", RECOVERY_AVAILABLE=1
#
#   # Invalid tier (returns error)
#   select_recovery_strategy "203.0.113.1" 1
#   # Result: Error logged, returns 1, RECOVERY_AVAILABLE=0
#
#   # No strategies available (missing commands)
#   select_recovery_strategy "203.0.113.1" 2
#   # Result: RECOVERY_STRATEGY="unavailable", returns 1, RECOVERY_AVAILABLE=0
#
# Note:
#   Requires ENABLE_XFRM_RECOVERY configuration variable
#   Checks for command availability (ip, ipsec) before selecting strategy
#   Uses helper function _is_strategy_applicable() to evaluate strategy conditions
#   Command availability is checked once per function call (cached in global variables)
select_recovery_strategy() {
	local peer_ip="${1:-}"
	local tier="${2:-2}"

	# Initialize return variables (declare as global)
	declare -g RECOVERY_STRATEGY=""
	declare -g RECOVERY_COMMAND=""
	declare -g RECOVERY_IMPACT=""
	declare -g RECOVERY_AVAILABLE=0

	# Step 1: Validate tier parameter
	# Tier must be 2 (surgical cleanup) or 3 (full restart)
	# Invalid tier is a critical error - fail immediately without checking strategies
	if [[ "$tier" != "2" ]] && [[ "$tier" != "3" ]]; then
		handle_error "ERROR" "SYSTEM" "Invalid tier: $tier (must be 2 or 3)" 0
		return 1
	fi

	# Step 2: Check command availability
	# This populates global variables _RECOVERY_IP_AVAILABLE and _RECOVERY_IPSEC_AVAILABLE
	# These are cached for use by _is_strategy_applicable() to avoid repeated checks
	_check_recovery_command_availability

	# Step 3: Define strategy lookup table (in priority order)
	# Format: "strategy_name:command:impact"
	# Priority: xfrm (highest) → ipsec_reload → ipsec_restart (lowest)
	# First applicable strategy in this order will be selected
	local -a strategies=(
		"xfrm:attempt_xfrm_recovery:per-connection"
		"ipsec_reload:ipsec reload:all-tunnels"
		"ipsec_restart:ipsec restart:all-tunnels"
	)

	# Step 4: Iterate through strategies in priority order
	# Parse each strategy entry and check applicability
	# Return immediately when first applicable strategy is found
	local strategy_entry
	for strategy_entry in "${strategies[@]}"; do
		# Parse strategy entry: split by colon to extract name, command, and impact
		IFS=':' read -r strategy_name strategy_command strategy_impact <<<"$strategy_entry"

		# Check if this strategy is applicable given current conditions
		# _is_strategy_applicable() checks: peer IP, tier, config, and command availability
		if _is_strategy_applicable "$strategy_name" "$peer_ip" "$tier"; then
			# Strategy is applicable - set global variables and return success
			# These variables are used by calling code to execute the selected strategy
			declare -g RECOVERY_STRATEGY="$strategy_name"
			declare -g RECOVERY_COMMAND="$strategy_command"
			declare -g RECOVERY_IMPACT="$strategy_impact"
			declare -g RECOVERY_AVAILABLE=1
			return 0
		fi
		# Strategy not applicable - continue to next strategy in priority order
	done

	# Step 5: No strategy available (fallback case)
	# This occurs when:
	#   - No commands available (ip and ipsec both missing)
	#   - xfrm disabled and no peer IP provided
	#   - Other conditions prevent all strategies
	# Set variables to indicate unavailability and return error
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
#   $2: Location name (required, used for recovery method tracking)
#
# Returns:
#   0: Recovery succeeded (recovery actions completed successfully)
#   1: Recovery failed (recovery actions failed or could not be attempted)
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
#   - Stores recovery method used for later inclusion in "VPN restored" message
#   - Logs all actions and results
#
# Examples:
#   surgical_cleanup "203.0.113.1" "NYC"
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
	local location_name="$2"
	local peer_display
	peer_display=$(format_peer_display "$peer_ip")
	log_message "INFO" "$location_name" "Attempting surgical SA cleanup for $location_name ($peer_display)"

	# Select recovery strategy
	if ! select_recovery_strategy "$peer_ip" 2; then
		# No recovery strategy available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		handle_error "WARNING" "${location_name:-SYSTEM}" "No recovery strategy available for Tier 2 recovery${location_name:+ for $location_name}"
		return 1
	fi

	# Execute selected strategy with fallback support
	local strategy_executed=0
	local recovery_succeeded=0
	while [[ $strategy_executed -eq 0 ]]; do
		case "$RECOVERY_STRATEGY" in
		"xfrm")
			log_message "INFO" "$location_name" "Attempting xfrm-based per-connection recovery for $location_name ($peer_ip)"
			# Store recovery method before attempting recovery
			store_recovery_method "$location_name" "$peer_ip" "xfrm"
			if attempt_xfrm_recovery "$peer_ip" "$location_name"; then
				log_message "INFO" "$location_name" "xfrm-based recovery completed successfully for $location_name ($peer_ip)"
				log_message "INFO" "$location_name" "Surgical cleanup completed for $location_name ($peer_ip) (via xfrm)"
				return 0
			else
				# xfrm recovery failed - fall back to ipsec reload
				handle_error "WARNING" "$location_name" "xfrm-based recovery failed for $location_name ($peer_ip), falling back to ipsec reload (affects all tunnels)"
				# Re-select strategy for fallback (without peer IP to force ipsec reload)
				if ! select_recovery_strategy "" 2; then
					# Fallback strategy not available
					handle_error "ERROR" "$location_name" "xfrm recovery failed and no fallback strategy available for $location_name ($peer_ip)" 0
					return 1
				fi
				# Continue loop to execute fallback strategy
				continue
			fi
			;;
		"ipsec_reload")
			log_message "INFO" "$location_name" "Attempting ipsec reload for $location_name ($peer_ip) (affects all tunnels)"
			# Store recovery method before attempting recovery
			local recovery_method_used="ipsec_reload"
			store_recovery_method "$location_name" "$peer_ip" "$recovery_method_used"
			local reload_start_time
			reload_start_time=$(get_unix_timestamp)
			local command_succeeded=0
			local reload_exit_code=""
			local restart_exit_code=""
			# Use full path to ipsec if available, otherwise rely on PATH
			local ipsec_cmd="${_RECOVERY_IPSEC_PATH:-ipsec}"
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
					recovery_succeeded=1
				else
					local current_time
					current_time=$(get_unix_timestamp)
					local reload_duration
					reload_duration=$(safe_timestamp_diff "$current_time" "$reload_start_time" 2>/dev/null || echo "0")
					if [[ $reload_duration -lt 0 ]]; then
						reload_duration=0
					fi
					handle_error "WARNING" "$location_name" "Recovery completed for $location_name ($peer_ip) (via ipsec fallback, verification: some connections not active, duration: ${reload_duration}s)"
					recovery_succeeded=0
				fi
			else
				handle_error "WARNING" "$location_name" "Surgical cleanup failed for $location_name ($peer_ip) (ipsec commands failed, exit codes: reload=${reload_exit_code:-unknown}, restart=${restart_exit_code:-unknown})"
				recovery_succeeded=0
			fi
			strategy_executed=1
			;;
		*)
			handle_error "ERROR" "$location_name" "Unknown recovery strategy: $RECOVERY_STRATEGY for $location_name ($peer_ip)" 0
			return 1
			;;
		esac
	done

	# Return based on whether recovery actually succeeded
	if [[ $recovery_succeeded -eq 1 ]]; then
		return 0
	else
		return 1
	fi
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
#   $2: Location name (optional, used for recovery method tracking)
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
#   - Stores recovery method used for later inclusion in "VPN restored" message
#   - Appends command output to LOG_FILE (for full restart only)
#   - Logs all actions and results
#
# Examples:
#   if full_restart "" "NYC"; then
#       echo "VPN restarted successfully"
#   fi
#   if full_restart "203.0.113.1" "NYC"; then
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
	local location_name="$2"

	if ! check_rate_limit; then
		# check_rate_limit() already logs detailed warning with reset time, countdown, and restart list
		handle_error "ERROR" "$location_name" "Rate limit exceeded, skipping Tier 3 recovery for $location_name (see previous warning for reset time and details)" 0
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
			log_message "INFO" "$location_name" "Tier 3: Attempting xfrm-based per-connection recovery for $location_name ($peer_ip)"
			# Store recovery method before attempting recovery
			if [[ -n "$peer_ip" ]]; then
				store_recovery_method "$location_name" "$peer_ip" "xfrm"
			fi
			if attempt_xfrm_recovery "$peer_ip" "$location_name"; then
				log_message "INFO" "$location_name" "Tier 3: xfrm-based per-connection recovery successful for $location_name ($peer_ip)"
				# Record restart for rate limiting (even though it's per-connection)
				record_restart
				set_cooldown "$COOLDOWN_MINUTES"
				return 0
			else
				handle_error "WARNING" "$location_name" "Tier 3: xfrm-based recovery failed for $location_name ($peer_ip), falling back to full restart"
				# Re-select strategy for fallback (without peer IP to force ipsec restart)
				if ! select_recovery_strategy "" 3; then
					# Fallback strategy not available
					handle_error "ERROR" "$location_name" "Tier 3: xfrm recovery failed and no fallback strategy available for $location_name ($peer_ip)" 0
					return 1
				fi
				# Continue loop to execute fallback strategy
				continue
			fi
			;;
		"ipsec_restart")
			handle_error "WARNING" "$location_name" "Tier 3: Performing full IPsec restart for $location_name (affects all VPN tunnels)"

			# Store recovery method before attempting recovery
			if [[ -n "$peer_ip" ]]; then
				store_recovery_method "$location_name" "$peer_ip" "ipsec_restart"
			fi

			# Record restart
			record_restart

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
			strategy_executed=1
			;;
		*)
			handle_error "ERROR" "$location_name" "Unknown recovery strategy: $RECOVERY_STRATEGY for $location_name ($peer_ip)" 0
			return 1
			;;
		esac
	done

	log_message "INFO" "$location_name" "Full IPsec restart completed for $location_name"
	set_cooldown "$COOLDOWN_MINUTES"
	return 0
}

# Store recovery method used for a location
#
# Stores the recovery method that was used when recovery was attempted.
# This allows the "VPN restored" message to include which recovery method succeeded.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#   $3: Recovery method name ("xfrm", "ipsec_reload", "ipsec_restart")
#
# Returns:
#   0: Always succeeds (errors are non-critical)
#
# Side effects:
#   - Creates/updates recovery method state file using abstraction layer
#
# Examples:
#   store_recovery_method "NYC" "203.0.113.1" "xfrm"
#   store_recovery_method "NYC" "203.0.113.1" "ipsec_reload"
#
# Note:
#   Requires set_peer_state_non_critical from state.sh
#   Uses "recovery_method" as the state key
store_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"
	local recovery_method="$3"

	# Validate recovery method
	if [[ -z "$recovery_method" ]]; then
		return 0
	fi

	# Store using abstraction layer (non-critical - failures are logged but don't interrupt)
	if command -v set_peer_state_non_critical >/dev/null 2>&1; then
		set_peer_state_non_critical "$location_name" "$peer_ip" "recovery_method" "$recovery_method"
	fi

	return 0
}

# Get recovery method used for a location
#
# Retrieves the recovery method that was stored when recovery was attempted.
# Returns empty string if no recovery method was stored.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints recovery method to stdout if found, empty string otherwise
#
# Examples:
#   method=$(get_recovery_method "NYC" "203.0.113.1")
#   if [[ -n "$method" ]]; then
#       echo "Recovery method: $method"
#   fi
#
# Note:
#   Requires get_peer_state from state.sh
#   Uses "recovery_method" as the state key
get_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"
	local recovery_method=""

	if command -v get_peer_state >/dev/null 2>&1; then
		recovery_method=$(get_peer_state "$location_name" "$peer_ip" "recovery_method" "")
	fi

	echo "$recovery_method"
	return 0
}

# Clear recovery method for a location
#
# Removes the stored recovery method after it has been logged.
# This prevents stale recovery method information from being displayed.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address
#
# Returns:
#   0: Always succeeds (errors are non-critical)
#
# Side effects:
#   - Deletes recovery method state file using abstraction layer
#
# Examples:
#   clear_recovery_method "NYC" "203.0.113.1"
#
# Note:
#   Requires delete_peer_state from state.sh
#   Uses "recovery_method" as the state key
clear_recovery_method() {
	local location_name="$1"
	local peer_ip="$2"

	if command -v delete_peer_state >/dev/null 2>&1; then
		delete_peer_state "$location_name" "$peer_ip" "recovery_method" || true
	fi

	return 0
}

# Format recovery method for display
#
# Formats a recovery method name for display in log messages.
# Converts internal method names to user-friendly descriptions.
#
# Arguments:
#   $1: Recovery method name ("xfrm", "ipsec_reload", "ipsec_restart")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted recovery method description to stdout
#
# Examples:
#   display=$(format_recovery_method "xfrm")
#   # Returns: "xfrm-based recovery"
#
# Note:
#   Returns "unknown recovery method" for unrecognized methods
format_recovery_method() {
	local method="$1"

	case "$method" in
	"xfrm")
		echo "xfrm-based recovery"
		;;
	"ipsec_reload")
		echo "ipsec reload"
		;;
	"ipsec_restart")
		echo "ipsec restart"
		;;
	*)
		if [[ -n "$method" ]]; then
			echo "$method"
		else
			echo "unknown recovery method"
		fi
		;;
	esac

	return 0
}

# Format peer display name with optional connection name
#
# Formats a peer IP address for display, optionally including the connection name
# if discoverable. This provides consistent formatting across logging statements.
#
# Arguments:
#   $1: External peer IP address
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted peer display string to stdout
#
# Examples:
#   display=$(format_peer_display "203.0.113.1")
#   # Returns: "203.0.113.1" or "203.0.113.1 (conn: site-a)" if connection name found
#
# Note:
#   Requires discover_connection_name to be available (from detection.sh)
#   Falls back to just the IP address if connection name cannot be discovered
format_peer_display() {
	local external_peer_ip="$1"
	local conn_name=""
	local peer_display="$external_peer_ip"

	# Try to discover connection name for better logging (optional, for debugging)
	if command -v discover_connection_name >/dev/null 2>&1; then
		conn_name=$(discover_connection_name "$external_peer_ip" 2>/dev/null || echo "")
	fi

	if [[ -n "$conn_name" ]]; then
		peer_display="$external_peer_ip (conn: $conn_name)"
	fi

	echo "$peer_display"
}

# Monitor VPN location
#
# Monitors a VPN location by checking VPN status and managing failure counters.
# Implements tiered recovery: logging → surgical cleanup → full restart.
# Each location has its own independent failure counter tracked separately.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: External peer IP address (external/public IP of remote VPN gateway)
#   $3: Internal peer IP addresses (space-separated string, can be empty)
#
# Returns:
#   0: VPN is healthy, or recovery was attempted (Tier 2 or Tier 3) even if recovery failed,
#      or network partition detected (VPN checks skipped)
#      Script completes successfully when recovery is attempted, as recovery failures are logged
#      but don't prevent successful completion of the monitoring task
#   1: VPN check failed and no recovery was attempted (Tier 1 or below threshold)
#
# Side effects:
#   - Updates per-location failure counters
#   - Logs recovery actions and status updates
#   - Triggers tiered recovery actions based on failure count
#   - Skips VPN checks when network partition is detected (performance optimization)
#
# Examples:
#   monitor_location "NYC" "203.0.113.1" "192.168.1.1 192.168.1.88"
#
# Note:
#   Requires check_vpn_status, get_failure_count, increment_failure, reset_failure_count,
#   TIER1_THRESHOLD, TIER2_THRESHOLD, TIER3_THRESHOLD, NO_ESCALATE to be set
#   Network partition check uses cached state from validate_monitor_state() for efficiency
monitor_location() {
	local location_name="$1"
	local external_peer_ip="$2"
	local internal_peer_ips="${3:-}"
	local failure_count

	# Optimize: Skip VPN checks if network partition is detected
	# This avoids unnecessary work when network connectivity is down
	# Re-check partition state if it was previously partitioned (to detect when partition clears)
	if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
		local partition_state
		partition_state=$(get_network_partition_state)
		if [[ "$partition_state" -eq 1 ]]; then
			# Network was previously partitioned - re-check to detect if partition cleared
			# Use same parameters as validate_monitor_state for consistency
			local dns_server="${NETWORK_PARTITION_DNS_SERVER:-8.8.8.8}"
			local dns_hostname="${NETWORK_PARTITION_DNS_HOSTNAME:-google.com}"
			local dns_timeout="${NETWORK_PARTITION_DNS_TIMEOUT:-2}"
			local interfaces="${NETWORK_PARTITION_INTERFACES:-br0,eth0}"
			if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
				# Network is still partitioned - skip VPN checks entirely
				# This is a performance optimization: VPN checks would fail anyway without network connectivity
				log_message "INFO" "$location_name" "Skipping VPN checks for $location_name ($external_peer_ip) - network partition detected"
				return 0
			else
				# Network partition cleared - update state and continue with VPN checks
				# We know partition_state was 1 (from line 2372), so we can use that directly
				log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $location_name ($external_peer_ip)"
				set_network_partition_state 0
				# Continue with VPN checks below
			fi
		fi
	fi

	# Check VPN status (uses external IP for xfrm, internal IPs for ping)
	# Pass location name for state file naming
	if check_vpn_status "$external_peer_ip" "$internal_peer_ips" "$location_name"; then
		# VPN is OK
		failure_count=$(get_failure_count "$location_name" "$external_peer_ip")

		# Check if failure type file exists (indicates previous failure)
		local failure_type_file=""
		if command -v get_peer_state_file_path >/dev/null 2>&1; then
			failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		fi
		local had_failure_type=0
		if [[ -n "$failure_type_file" ]] && [[ -f "$failure_type_file" ]]; then
			had_failure_type=1
		fi

		if [[ "$failure_count" -gt 0 ]] || [[ $had_failure_type -eq 1 ]]; then
			# Check if a recovery method was used (stored when recovery was attempted)
			local recovery_method=""
			recovery_method=$(get_recovery_method "$location_name" "$external_peer_ip")
			local recovery_method_display=""
			if [[ -n "$recovery_method" ]]; then
				recovery_method_display=$(format_recovery_method "$recovery_method")
			fi

			# Log recovery success with method if available
			if [[ "$failure_count" -gt 0 ]]; then
				if [[ -n "$recovery_method_display" ]]; then
					log_message "INFO" "$location_name" "${VPN_NAME:-VPN} restored for $location_name ($external_peer_ip) after $failure_count failures (recovery method: $recovery_method_display)"
				else
					log_message "INFO" "$location_name" "${VPN_NAME:-VPN} recovered for $location_name ($external_peer_ip) after $failure_count failures"
				fi
				reset_failure_count "$location_name" "$external_peer_ip"
			else
				if [[ -n "$recovery_method_display" ]]; then
					log_message "INFO" "$location_name" "${VPN_NAME:-VPN} restored for $location_name ($external_peer_ip) (recovery method: $recovery_method_display)"
				else
					log_message "INFO" "$location_name" "${VPN_NAME:-VPN} recovered for $location_name ($external_peer_ip)"
				fi
			fi

			# Clear failure type file on recovery
			# Use abstraction layer to ensure consistent path format
			if [[ -n "$failure_type_file" ]] && [[ -f "$failure_type_file" ]]; then
				rm -f "$failure_type_file" 2>/dev/null || true
			fi

			# Clear recovery method after logging (prevents stale information)
			if [[ -n "$recovery_method" ]]; then
				clear_recovery_method "$location_name" "$external_peer_ip"
			fi
		else
			# VPN is healthy with no previous failures - log periodic status update
			local status_log_interval="${STATUS_LOG_INTERVAL_SECONDS:-300}"
			if [[ $status_log_interval -gt 0 ]]; then
				local last_status_log
				last_status_log=$(get_peer_state "$location_name" "$external_peer_ip" "last_status_log" "0")
				local current_time
				current_time=$(get_unix_timestamp)
				if [[ -z "$current_time" ]] || [[ ! "$current_time" =~ ^[0-9]+$ ]]; then
					handle_error "WARNING" "SYSTEM" "Invalid timestamp from get_unix_timestamp, skipping periodic status log" 0
				else
					local time_diff
					time_diff=$(safe_timestamp_diff "$current_time" "$last_status_log" 2>/dev/null || echo "0")
					if [[ $time_diff -lt 0 ]]; then
						time_diff=0
					fi
					if [[ $time_diff -ge $status_log_interval ]] || [[ "$last_status_log" -eq 0 ]]; then
						log_message "INFO" "$location_name" "${VPN_NAME:-VPN} check OK for $location_name ($external_peer_ip)"
						set_peer_state_non_critical "$location_name" "$external_peer_ip" "last_status_log" "$current_time"
					fi
				fi
			fi
		fi
		return 0
	else
		# VPN check failed - increment failure count first
		# This ensures failure count increments even when recovery is skipped due to network partition
		failure_count=$(increment_failure "$location_name" "$external_peer_ip")

		# Check network partition - always re-check (don't rely on cached state)
		# This ensures we detect partition state changes (e.g., network just recovered)
		if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
			# Use same parameters as validate_monitor_state for consistency
			local dns_server="${NETWORK_PARTITION_DNS_SERVER:-8.8.8.8}"
			local dns_hostname="${NETWORK_PARTITION_DNS_HOSTNAME:-google.com}"
			local dns_timeout="${NETWORK_PARTITION_DNS_TIMEOUT:-2}"
			local interfaces="${NETWORK_PARTITION_INTERFACES:-br0,eth0}"
			if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
				# Network is partitioned - skip recovery but update state
				local prev_partition_state
				prev_partition_state=$(get_network_partition_state)
				set_network_partition_state 1
				if [[ "$prev_partition_state" -eq 0 ]]; then
					log_message "WARNING" "$location_name" "Network partition detected - skipping VPN recovery for $location_name ($external_peer_ip) until connectivity restored"
				else
					log_message "INFO" "$location_name" "Skipping VPN recovery for $location_name ($external_peer_ip) - network is still partitioned (failure count: $failure_count)"
				fi
				return 0
			else
				# Network is healthy - check if it was previously partitioned
				local prev_partition_state
				prev_partition_state=$(get_network_partition_state)
				if [[ "$prev_partition_state" -eq 1 ]]; then
					log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $location_name ($external_peer_ip)"
					set_network_partition_state 0
				fi
				# Continue with recovery below
			fi
		fi

		# VPN check failed - continue with recovery
		local failure_type="unknown"
		if command -v get_failure_type >/dev/null 2>&1; then
			failure_type=$(get_failure_type "$location_name" "$external_peer_ip" 2>/dev/null || echo "unknown")
		fi
		local failure_type_display=""
		case "$failure_type" in
		"tunnel_down") failure_type_display=" (tunnel down)" ;;
		"routing_issue") failure_type_display=" (routing issue)" ;;
		esac
		handle_error "WARNING" "$location_name" "${VPN_NAME:-VPN} check failed for $location_name ($external_peer_ip) (failure count: $failure_count)$failure_type_display"

		# Safety check: Don't escalate recovery if detection is unreliable
		# If failure type is "unknown" and required detection tools are unavailable,
		# we cannot reliably determine if VPN is actually down, so skip recovery escalation
		if [[ "$failure_type" == "unknown" ]]; then
			# Check if required detection tools are available
			# If both ip and ipsec are unavailable, detection is unreliable
			local ip_available=0
			local ipsec_available=0
			if check_command_available "ip"; then
				ip_available=1
			fi
			if check_command_available "ipsec"; then
				ipsec_available=1
			fi

			# If neither tool is available, detection is unreliable - don't escalate recovery
			if [[ $ip_available -eq 0 ]] && [[ $ipsec_available -eq 0 ]]; then
				handle_error "ERROR" "$location_name" "Detection unreliable: Both 'ip' and 'ipsec' commands unavailable - skipping recovery escalation for $location_name ($external_peer_ip) to prevent false recovery actions" 0
				# Still log the failure but don't escalate recovery
				if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
					log_message "INFO" "$location_name" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $location_name ($external_peer_ip)$failure_type_display (recovery skipped - detection unreliable)"
				fi
				return 0
			fi
		fi

		# Tier 1: Logging
		if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
			log_message "INFO" "$location_name" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $location_name ($external_peer_ip)$failure_type_display"
		fi

		# Tier 2: Surgical cleanup
		local recovery_attempted=0
		if [[ "$failure_count" -ge "$TIER2_THRESHOLD" ]] && [[ "$failure_count" -lt "$TIER3_THRESHOLD" ]]; then
			recovery_attempted=1
			if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
				if select_recovery_strategy "$external_peer_ip" 2; then
					if [[ "$RECOVERY_STRATEGY" == "xfrm" ]]; then
						log_message "INFO" "$location_name" "Tier 2: Would attempt xfrm-based per-connection recovery for $location_name ($external_peer_ip) (skipped in fake mode)"
					else
						# Log the specific command that would be executed
						local command_display="${RECOVERY_COMMAND:-ipsec reload}"
						log_message "INFO" "$location_name" "Tier 2: Would attempt surgical SA cleanup for $location_name ($external_peer_ip) via $command_display (skipped in fake mode)"
					fi
				fi
			else
				handle_error "WARNING" "$location_name" "Tier 2: Attempting surgical SA cleanup for $location_name ($external_peer_ip)"
				surgical_cleanup "$external_peer_ip" "$location_name"
			fi
		fi

		# Tier 3: Full restart
		if [[ "$failure_count" -ge "$TIER3_THRESHOLD" ]]; then
			recovery_attempted=1
			if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
				if ! check_rate_limit; then
					# check_rate_limit() already logs "Rate limit exceeded" via handle_error
					# location_name should always be provided in production code
					log_message "INFO" "${location_name:-SYSTEM}" "Tier 3: Would attempt IPsec restart${location_name:+ for $location_name} (skipped in fake mode, rate limit would prevent)"
				else
					# In fake mode, still record restart for cleanup purposes (prevents restart count file from growing)
					# but skip the actual restart command
					record_restart
					if select_recovery_strategy "$external_peer_ip" 3; then
						if [[ "$RECOVERY_STRATEGY" == "xfrm" ]]; then
							log_message "INFO" "$location_name" "Tier 3: Would attempt xfrm-based per-connection recovery for $location_name ($external_peer_ip) (skipped in fake mode)"
						else
							log_message "INFO" "$location_name" "Tier 3: Would attempt full IPsec restart (affects all tunnels, skipped in fake mode)"
						fi
					else
						# No recovery strategy available - log Tier 3 reached but no strategy available
						log_message "WARNING" "$location_name" "Tier 3: Recovery threshold reached for $location_name ($external_peer_ip) but no recovery strategy available (skipped in fake mode)"
					fi
				fi
			else
				handle_error "ERROR" "$location_name" "Tier 3: Attempting IPsec restart for $location_name ($external_peer_ip)" 0
				if full_restart "$external_peer_ip" "$location_name"; then
					reset_failure_count "$location_name" "$external_peer_ip"
				fi
			fi
		fi

		# If recovery was attempted (Tier 2 or Tier 3), return 0 to indicate script completed successfully
		# even if recovery failed. The script should only return 1 if there's an actual script execution error,
		# not if the VPN is down or recovery fails. Recovery failures are logged but don't prevent successful
		# completion of the monitoring task.
		if [[ $recovery_attempted -eq 1 ]]; then
			return 0
		fi

		# Tier 1 or below threshold - no recovery attempted, return 1 to indicate VPN check failed
		return 1
	fi
}
