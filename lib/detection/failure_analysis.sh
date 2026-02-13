#!/bin/bash
#
# Failure analysis functions for UDM VPN Monitor
# Handles failure type classification and VPN status determination
#
# Version: 0.7.0
#

# shellcheck source=lib/constants.sh
# Determine lib directory (parent directory of detection/)
# If LIB_DIR is already set (from parent), use it; otherwise determine from this file's location
if [[ -z "${LIB_DIR:-}" ]]; then
	LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	[[ -z "${MAX_IPV6_SEGMENTS:-}" ]] && readonly MAX_IPV6_SEGMENTS=8
	[[ -z "${MIN_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MIN_IPV6_SEGMENT_HEX_DIGITS=1
	[[ -z "${MAX_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MAX_IPV6_SEGMENT_HEX_DIGITS=4
	[[ -z "${MAX_IPV4_OCTET:-}" ]] && readonly MAX_IPV4_OCTET=255
	[[ -z "${IPV4_OCTET_COUNT:-}" ]] && readonly IPV4_OCTET_COUNT=4
	[[ -z "${IPV4_CIDR_SINGLE_HOST:-}" ]] && readonly IPV4_CIDR_SINGLE_HOST=32
	[[ -z "${PING_PACKET_LOSS_THRESHOLD:-}" ]] && readonly PING_PACKET_LOSS_THRESHOLD=100
	[[ -z "${PING_SUCCESS_THRESHOLD:-}" ]] && readonly PING_SUCCESS_THRESHOLD=0.3
	[[ -z "${PING_CEIL_ADJUSTMENT:-}" ]] && readonly PING_CEIL_ADJUSTMENT=0.999
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
	[[ -z "${STATE_FILE_READ_TIMEOUT:-}" ]] && readonly STATE_FILE_READ_TIMEOUT=1
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source logging functions (required for log_message and handle_error)
# shellcheck source=lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=lib/detection/network_validation.sh
source "${LIB_DIR}/detection/network_validation.sh"
# shellcheck source=lib/detection/xfrm_detection.sh
source "${LIB_DIR}/detection/xfrm_detection.sh"
# shellcheck source=lib/detection/ping_detection.sh
source "${LIB_DIR}/detection/ping_detection.sh"

# Check SA existence for failure type detection
#
# Determines if IPsec Phase 2 SA exists using primary_check_passed as single source of truth.
# If primary_check_passed=1, SA exists (invariant). Otherwise, checks SA existence directly.
#
# Arguments:
#   $1: External peer IP address (used for SA checks)
#   $2: Primary check status (0 = primary check failed, 1 = primary check passed)
#   $3: XFRM output (optional, for optimization - avoids duplicate ip xfrm state calls)
#
# Returns:
#   0: SA exists
#   1: SA does not exist
#
# Note:
#   Uses primary_check_passed as single source of truth. If primary_check_passed=1,
#   SA MUST exist (fundamental invariant). If primary_check_passed=0, checks in order:
#   1. xfrm_output if provided (extracts SPI to verify SA exists)
#   2. Direct SA check via check_ipsec_phase2() as fallback
check_sa_existence_for_failure_type() {
	local external_peer_ip="$1"
	local primary_check_passed="$2"
	local xfrm_output="${3:-}"

	# CRITICAL: If primary_check_passed=1, SA MUST exist (fundamental invariant)
	# This is true whether SA was detected via xfrm or ipsec fallback
	if [[ $primary_check_passed -eq 1 ]]; then
		# Primary check passed - SA exists (either from xfrm or ipsec fallback)
		# Trust the primary check result - this is a fundamental invariant
		return 0
	fi

	# primary_check_passed=0 - need to determine if SA exists
	# First check if xfrm_output is available and contains valid SA data
	# This handles the case where check_xfrm_primary failed due to byte counter validation
	# but the SA actually exists in xfrm state (xfrm_output was populated by check_xfrm_status)
	# Optimization: If xfrm_output was provided, check it first to avoid duplicate calls
	# Only call check_ipsec_phase2() if xfrm_output was not provided as a parameter
	if [[ "${3+set}" == "set" ]]; then
		# xfrm_output parameter was provided (even if empty) - check it first
		if [[ -n "$xfrm_output" ]]; then
			# Try to extract SPI to verify xfrm_output contains valid SA data
			local test_spi
			test_spi=$(extract_spi "$xfrm_output" 2>/dev/null || echo "")
			if [[ -n "$test_spi" ]]; then
				# xfrm_output contains valid SA data - SA exists
				return 0
			fi
		fi
		# xfrm_output was provided but is empty or doesn't contain valid SPI
		# Don't call check_ipsec_phase2() to avoid duplicate calls when xfrm_output was provided
		# Return 1 (SA doesn't exist) since xfrm_output was provided but doesn't contain valid SA data
		return 1
	fi

	# xfrm_output parameter was not provided - check SA existence directly
	if check_ipsec_phase2 "$external_peer_ip"; then
		return 0
	fi

	return 1
}

# Check for SA rekey for failure type detection
#
# Checks if SA rekey occurred by comparing current SPI with stored baseline SPI.
# Rekey is detected when SPI changes, indicating SA was renegotiated.
#
# Arguments:
#   $1: Current SPI (from xfrm output)
#   $2: External peer IP address
#   $3: Location name (required, used for state file naming)
#
# Returns:
#   0: Rekey detected
#   1: No rekey detected or SPI unavailable
#
# Note:
#   This is a read-only check. The actual rekey handling (baseline reset)
#   should have happened in check_byte_counters during the check.
check_rekey_for_failure_type() {
	local current_spi="$1"
	local external_peer_ip="$2"
	local location_name="$3"

	if [[ -z "$current_spi" ]]; then
		return 1
	fi

	# Check for SA rekey by comparing SPI
	if check_sa_rekey_occurred "$current_spi" "$external_peer_ip" "$location_name" 2>/dev/null; then
		# Rekey detected - not a failure, but log for monitoring
		# Note: We use read-only check here since detect_failure_type is called
		# after VPN check failed. The actual rekey handling (baseline reset)
		# should have happened in check_byte_counters during the check.
		return 0
	fi

	return 1
}

# Check for routing issues for failure type detection
#
# Detects routing issues by checking byte counters and ping connectivity.
# Routing issues occur when SA exists but traffic isn't flowing properly.
#
# Arguments:
#   $1: Current byte counter value (from xfrm output)
#   $2: Location name (required, used for state file operations)
#   $3: External peer IP address (used for state file operations)
#   $4: Internal peer IP address (optional, used for ping checks)
#
# Returns:
#   0: Routing issue detected
#   1: No routing issue detected
#
# Output:
#   Prints space-separated values to stdout: "byte_counters_available ping_checked ping_failed"
#   where each value is 0 or 1
#
# Note:
#   Caller MUST capture stdout to get flags, even if only return code is needed.
#   Example: flags=$(check_routing_issue_for_failure_type "$bytes" "$loc" "$ip" "$int_ip")
#            read -r byte_counters_available ping_checked ping_failed <<< "$flags"
#   WARNING: If stdout is not captured, flags will be lost and subsequent parsing will fail.
check_routing_issue_for_failure_type() {
	local current_bytes="$1"
	local location_name="$2"
	local external_peer_ip="$3"
	local internal_peer_ip="${4:-}"
	local byte_counters_available=0
	local ping_checked=0
	local ping_failed=0
	local has_routing_issue=0

	# Check byte counters using abstraction layer (peer IP is available)
	if [[ -n "$current_bytes" ]] && [[ "$current_bytes" =~ ^[0-9]+$ ]]; then
		byte_counters_available=1
		local last_bytes
		last_bytes=$(get_peer_state "$location_name" "$external_peer_ip" "last_bytes" "0")

		# If bytes exist but aren't increasing (and it's not the first check), it's a routing issue
		if [[ "$current_bytes" -gt 0 ]] && [[ "$current_bytes" -le "$last_bytes" ]] && [[ "$last_bytes" -gt 0 ]]; then
			has_routing_issue=1
		elif [[ "$current_bytes" -eq 0 ]] && [[ "$last_bytes" -gt 0 ]]; then
			# Bytes dropped to zero after previously having traffic - routing issue
			has_routing_issue=1
		fi
	fi

	# Check ping if enabled and internal IP provided
	# Check ping even if byte counters are unavailable to help diagnose routing issues
	# If byte counters unavailable and ping check enabled and fails: definitely routing_issue
	if [[ $has_routing_issue -eq 0 ]] && [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		ping_checked=1
		local local_ip
		local_ip=$(get_local_ip_for_ping)
		if ! check_ping_connectivity "$internal_peer_ip" "$local_ip" 2>/dev/null; then
			ping_failed=1
			has_routing_issue=1
		fi
	fi

	# Output flags for caller
	echo "$byte_counters_available $ping_checked $ping_failed"

	# Return routing issue status
	if [[ $has_routing_issue -eq 1 ]]; then
		return 0
	fi
	return 1
}

# Build failure diagnostic message
#
# Constructs a diagnostic message explaining why failure type detection was unable
# to determine a specific failure type. Used when SA exists but diagnostic data is unavailable.
#
# Arguments:
#   $1: XFRM output (optional, may be empty)
#   $2: Byte counters available flag (0 or 1)
#   $3: Current byte counter value (optional)
#   $4: Last byte counter value (optional)
#   $5: Internal peer IP address (optional)
#   $6: Ping checked flag (0 or 1)
#   $7: Ping failed flag (0 or 1)
#   $8: Diagnostic context (optional, e.g., "VPN check failed - unable to determine specific failure type without diagnostic data")
#
# Returns:
#   Prints diagnostic message to stdout
#
# Note:
#   This function handles two similar diagnostic message building scenarios:
#   1. When byte counters unavailable and ping check disabled (lines 215-239 in original)
#   2. When SA exists but no routing issue detected (lines 254-290 in original)
build_failure_diagnostic_message() {
	local xfrm_output="$1"
	local byte_counters_available="$2"
	local current_bytes="${3:-}"
	local last_bytes="${4:-}"
	local internal_peer_ip="${5:-}"
	local ping_checked="$6"
	local ping_failed="$7"
	local diagnostic_context="${8:-}"

	local diagnostic_parts=()
	diagnostic_parts+=("Phase 2 SA exists")

	if [[ -z "$xfrm_output" ]]; then
		diagnostic_parts+=("xfrm output unavailable")
	elif [[ $byte_counters_available -eq 1 ]]; then
		diagnostic_parts+=("byte counters available (current=$current_bytes, last=$last_bytes) but no routing issue detected")
	else
		diagnostic_parts+=("byte counter extraction failed")
	fi

	if [[ -z "$internal_peer_ip" ]]; then
		diagnostic_parts+=("internal IP not provided")
	fi

	if [[ $ping_checked -eq 1 ]]; then
		if [[ $ping_failed -eq 0 ]]; then
			diagnostic_parts+=("ping check enabled and succeeded")
		else
			# This shouldn't happen here since ping failure should set has_routing_issue=1
			diagnostic_parts+=("ping check enabled but result unclear")
		fi
	elif [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		diagnostic_parts+=("ping check disabled")
	fi

	# Add diagnostic context if provided
	if [[ -n "$diagnostic_context" ]]; then
		diagnostic_parts+=("$diagnostic_context")
	fi

	# Join parts with commas
	local IFS=', '
	local diagnostic_msg="${diagnostic_parts[*]}"

	echo "$diagnostic_msg"
}

# Detect VPN failure type
#
# Determines the specific type of VPN failure by checking IPsec Phase 2 SAs and traffic flow.
# Categorizes failures into main types:
#   - "tunnel_down": IPsec Phase 2 SA doesn't exist (tunnel not established)
#   - "routing_issue": Phase 2 SA exists but traffic isn't flowing (byte counters/ping issues)
#   - "rekey": SA rekey detected (SPI changed, not a failure but logged for monitoring)
#   - "unknown": Unable to determine failure type (fallback)
#
# Note:
#   If Phase 2 SA doesn't exist, the tunnel is down (could be Phase 1 or Phase 2 issue, but we can't distinguish).
#   SA rekey is detected by SPI changes and is not treated as a failure.
#   When byte counters are unavailable and ping check is disabled, if primary check failed (primary_check_passed=0),
#   the function returns "unknown" since SA exists but diagnostic data is unavailable.
#
# Arguments:
#   $1: External peer IP address (used for SA checks)
#   $2: Internal peer IP address (optional, used for ping checks)
#   $3: Location name (required, used for state file naming)
#   $4: Primary check status (required, 0 = primary check failed, 1 = primary check passed)
#   $5: XFRM output (optional, xfrm state output for reuse, if not provided will fetch if needed)
#
# Returns:
#   0: Failure type detected and printed to stdout
#   1: Unable to determine failure type
#
# Output:
#   Prints failure type to stdout: "tunnel_down", "routing_issue", "rekey", or "unknown"
#
# Side effects:
#   - Logs debug messages about failure type detection
#   - Only logs warnings when primary check failed (primary_check_passed=0) to avoid false positives for healthy VPNs
#
# Examples:
#   failure_type=$(detect_failure_type "203.0.113.1" "192.168.1.1" "NYC" "0" "$xfrm_output")
#   case "$failure_type" in
#       "tunnel_down") echo "VPN tunnel is down" ;;
#       "routing_issue") echo "Routing issue detected" ;;
#       "rekey") echo "SA rekey detected" ;;
#   esac
#
# Note:
#   Requires check_ipsec_phase2, check_byte_counters, check_ping_connectivity, detect_sa_rekey
#   External IP is used for SA checks, internal IP is used for ping checks
#   When primary_check_passed=1 (primary check passed), warnings are suppressed to avoid false positives
#   When xfrm_output is provided, reuses it to avoid duplicate ip xfrm state calls (optimization)
#   Uses primary_check_passed as single source of truth: if primary_check_passed=1, SA exists (invariant);
#   if primary_check_passed=0, check_sa_existence_for_failure_type() checks xfrm_output if available,
#   otherwise checks SA existence directly when needed
detect_failure_type() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local location_name="$3"
	local primary_check_passed="$4"
	local xfrm_output="${5:-}"

	# Validate location_name is provided
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "detect_failure_type: location_name is required" 0
		echo "unknown"
		return 1
	fi

	# Check if ip command is available (required for Phase 2 SA detection)
	# If ip command is unavailable, we cannot determine failure type
	if ! check_command_or_warn "ip" "Detecting failure type"; then
		local ip_display
		ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
		log_message "WARNING" "$location_name" "Failure type detection: 'ip' command unavailable, cannot determine failure type for $ip_display"
		echo "unknown"
		return 1
	fi

	# Determine SA existence using primary_check_passed as single source of truth
	# CRITICAL: If primary_check_passed=1, SA MUST exist (fundamental invariant)
	# This is true whether SA was detected via xfrm or ipsec fallback
	local ipsec_phase2_up=0
	if check_sa_existence_for_failure_type "$external_peer_ip" "$primary_check_passed" "$xfrm_output"; then
		ipsec_phase2_up=1
	fi

	# Determine failure type based on SA state
	if [[ $ipsec_phase2_up -eq 0 ]]; then
		# No Phase 2 SA found - tunnel is down
		echo "tunnel_down"
		return 0
	elif [[ $ipsec_phase2_up -eq 1 ]]; then
		# Phase 2 SA exists - tunnel is established
		local current_spi=""
		local current_bytes=""
		# Only fetch xfrm_output if not already provided (optimization: reuse output from check_xfrm_primary)
		# If xfrm_output parameter was provided (even if empty), don't refetch to avoid duplicate calls
		# The check_xfrm_primary function should have populated xfrm_output if SA exists
		local xfrm_output_provided=0
		if [[ "${5+set}" == "set" ]]; then
			# Parameter $5 (xfrm_output) was provided (even if empty)
			xfrm_output_provided=1
		fi
		# Refetch xfrm_output if it's empty (even if parameter was provided, it might be empty)
		# This handles the case where check_xfrm_primary failed but we still need SA data for failure type detection
		if [[ -z "$xfrm_output" ]] && [[ -n "$external_peer_ip" ]]; then
			# xfrm_output is empty - fetch it
			# Use fixed-string matching to prevent regex pattern injection
			# Match on "dst $external_peer_ip" pattern which appears at the start of each SA entry
			# This ensures we capture the complete SA block including SPI and lifetime information
			xfrm_output=$(get_xfrm_state_for_peer "$external_peer_ip")
		fi
		if [[ -n "$xfrm_output" ]]; then
			current_spi=$(extract_spi "$xfrm_output" 2>/dev/null || echo "")
			current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null || echo "")
		fi

		# Check for SA rekey by comparing SPI
		if check_rekey_for_failure_type "$current_spi" "$external_peer_ip" "$location_name"; then
			# Rekey detected - not a failure, but log for monitoring
			# Note: We use read-only check here since detect_failure_type is called
			# after VPN check failed. The actual rekey handling (baseline reset)
			# should have happened in check_byte_counters during the check.
			echo "rekey"
			return 0
		fi

		# Phase 2 SA exists and no rekey detected - check for routing issues
		# Check byte counters and ping if available
		local routing_flags
		local has_routing_issue=0
		if routing_flags=$(check_routing_issue_for_failure_type "$current_bytes" "$location_name" "$external_peer_ip" "$internal_peer_ip"); then
			has_routing_issue=1
		fi
		local byte_counters_available ping_checked ping_failed
		read -r byte_counters_available ping_checked ping_failed <<<"$routing_flags"

		if [[ $has_routing_issue -eq 1 ]]; then
			echo "routing_issue"
			return 0
		fi

		# If byte counters unavailable and ping check disabled, cannot determine failure type
		# This handles the case where SA exists but we can't determine failure type definitively
		# Return "unknown" since we lack diagnostic data to determine specific failure type
		if [[ $byte_counters_available -eq 0 ]] && [[ $ping_checked -eq 0 ]] && [[ $primary_check_passed -eq 0 ]]; then
			# SA exists, byte counters unavailable, ping check disabled, but VPN check failed
			# Cannot determine specific failure type without diagnostic data
			local diagnostic_msg
			diagnostic_msg=$(build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "" "" "$internal_peer_ip" "$ping_checked" "$ping_failed" "VPN check failed - unable to determine specific failure type without diagnostic data")
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
			log_message "WARNING" "$location_name" "Failure type detection: Unable to determine specific failure type for $ip_display - $diagnostic_msg"
			echo "unknown"
			return 0
		fi
		# Phase 2 SA exists but no routing issue detected
		# This can happen when:
		#   - Byte counters are available and show traffic is flowing
		#   - Ping check is enabled and succeeds
		#   - VPN check failed for another reason (e.g., byte counter validation in check_xfrm_status)
		# In this case, we return "unknown" since we can't definitively determine the failure type
		# without additional diagnostic information
		local last_bytes=""
		if [[ $byte_counters_available -eq 1 ]]; then
			last_bytes=$(get_peer_state "$location_name" "$external_peer_ip" "last_bytes" "0")
		fi
		local diagnostic_msg
		diagnostic_msg=$(build_failure_diagnostic_message "$xfrm_output" "$byte_counters_available" "$current_bytes" "$last_bytes" "$internal_peer_ip" "$ping_checked" "$ping_failed")
		# Only log warning if primary check failed (primary_check_passed=0)
		# When primary check passed (primary_check_passed=1), returning "unknown" is expected behavior
		# and should not generate warnings to avoid false positives
		if [[ $primary_check_passed -eq 0 ]]; then
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
			log_message "WARNING" "$location_name" "Failure type detection: Unable to determine specific failure type for $ip_display - Detection method: Phase 2 SA check (SA exists), Reasons: $diagnostic_msg"
		fi
		# Return "unknown" when SA exists but we can't determine specific failure type
		# This handles cases where byte counters are available but show traffic flowing,
		# or ping check is enabled and succeeds, but VPN check failed for another reason
		echo "unknown"
		return 0
	fi

	# Unable to determine failure type (fallback)
	# This should be unreachable in normal operation since:
	#   - If ipsec_phase2_up=0, we return "tunnel_down" at line 380
	#   - If ipsec_phase2_up=1, we enter the elif block at line 382 and return one of:
	#     "rekey" (line 414), "routing_issue" (line 429), or "unknown" (line 444 or 471)
	# This fallback exists as a defensive guard for unexpected code paths (e.g., if
	# check_sa_existence_for_failure_type() has a bug or ipsec_phase2_up is corrupted).
	# If this code is reached, it indicates a logic error that should be investigated.
	echo "unknown"
	return 1
}

# Get last detected failure type for a peer
#
# Retrieves the last detected failure type from the state file.
# This allows recovery actions to use failure-specific recovery strategies.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address
#
# Returns:
#   0: Failure type found and printed to stdout
#   1: No failure type stored (or file doesn't exist)
#
# Output:
#   Prints failure type to stdout: "tunnel_down", "routing_issue", "rekey", or "unknown"
#
# Examples:
#   failure_type=$(get_failure_type "NYC" "203.0.113.1")
#   if [[ "$failure_type" == "tunnel_down" ]]; then
#       echo "VPN tunnel is down"
#   fi
#
# Note:
#   Requires get_peer_state_file_path, file_exists_and_readable and STATE_DIR to be set
#   Failure type is stored using the abstraction layer: get_peer_state_file_path() with "failure_type" key
#   Note: "rekey" is not a failure type but is stored for monitoring purposes
get_failure_type() {
	local location_name="$1"
	local external_peer_ip="$2"
	local failure_type_file

	# Use abstraction layer to ensure consistent path format
	failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")

	# Validate path was generated successfully
	if [[ -z "$failure_type_file" ]]; then
		# Error already logged by get_peer_state_file_path
		echo "unknown"
		return 1
	fi

	if file_exists_and_readable "$failure_type_file"; then
		local failure_type
		# Defensive timeout wrapper: file_exists_and_readable should prevent hangs, but this adds
		# extra protection for edge cases (race conditions, test suite timing issues, etc.)
		# Use helper function to standardize timeout command availability check
		# Pipeline needs to be wrapped in sh -c for timeout to apply to entire pipeline
		failure_type=$(run_with_timeout "$STATE_FILE_READ_TIMEOUT" sh -c "cat \"$failure_type_file\" 2>/dev/null | head -1 | tr -d '\n\r '" || echo "unknown")
		if [[ -n "$failure_type" ]]; then
			echo "$failure_type"
			return 0
		fi
	fi

	echo "unknown"
	return 1
}

# Determine VPN status based on failure type detection
#
# When initial VPN checks fail, this function detects the specific failure type
# and determines the final VPN status. Handles special cases like rekey events
# which are not failures but should be logged.
#
# Arguments:
#   $1: Current VPN status (0 = failed, 1 = OK)
#   $2: External peer IP address (external/public IP of remote VPN gateway)
#   $3: Internal peer IP address (optional, used for failure type detection)
#   $4: Location name (required, used for state file naming)
#   $5: XFRM output (optional, xfrm state output for reuse, if not provided will fetch if needed)
#
# Returns:
#   Outputs final VPN status (0 or 1) to stdout
#   Returns 0 on success
#
# Side effects:
#   - Creates/updates per-peer failure_type state file
#   - Logs failure type and status messages
determine_vpn_status() {
	local primary_check_passed="$1"
	local external_peer_ip="$2"
	local internal_peer_ip="${3:-}"
	local location_name="$4"
	local xfrm_output="${5:-}"

	# Format IP display once for reuse throughout function
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")

	# Always check failure type to detect:
	# 1. Rekey events (SPI changes) - always checked regardless of primary check status
	# 2. Routing issues via ping - if ping check is enabled and internal IP provided
	# 3. Tunnel down - when primary check failed
	# Note: Even when primary check passed, we need to check for rekey events and routing issues.
	#       The detect_failure_type() function handles the logic for what to check based on
	#       the current state (primary_check_passed, ping check enabled, etc.).
	local check_failure_type=1

	if [[ $check_failure_type -eq 1 ]]; then
		local failure_type
		# Capture output and return code separately to avoid duplicate "unknown"
		# Note: stderr is not redirected so diagnostic log messages from detect_failure_type are visible
		# Pass primary_check_passed status so detect_failure_type can use it as single source of truth
		# Pass xfrm_output to detect_failure_type to avoid duplicate ip xfrm state call (optimization)
		failure_type=$(detect_failure_type "$external_peer_ip" "$internal_peer_ip" "$location_name" "$primary_check_passed" "$xfrm_output")
		# If detect_failure_type failed or returned empty, use "unknown"
		if [[ -z "$failure_type" ]]; then
			failure_type="unknown"
		fi

		# Store failure type in state file for recovery actions
		# Use abstraction layer to ensure consistent path format with location component
		local failure_type_file
		failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		# Validate path was generated successfully before writing
		if [[ -n "$failure_type_file" ]]; then
			atomic_write_file "$failure_type_file" "$failure_type" 2>/dev/null || true
		fi

		case "$failure_type" in
		"rekey")
			# Rekey detected - not a failure, but log for monitoring
			# Rekey is already logged in detect_sa_rekey, but we mark primary check as passed
			log_message "INFO" "$location_name" "SA rekey detected for $ip_display (not a failure)"
			primary_check_passed=1
			;;
		"tunnel_down")
			handle_error "WARNING" "$location_name" "VPN failure type: Tunnel down (no Phase 2 SA found) for $ip_display"
			;;
		"routing_issue")
			# Log routing issue warning only when primary check failed
			# When primary_check_passed=0: Primary check failed, routing issue is the cause
			# When primary_check_passed=1: Primary check passed (SA exists, bytes increasing) but routing issue detected from ping failure
			#   In this case, silently ignore since ping is supplementary and primary check is authoritative
			#   This prevents log noise from transient ping failures when VPN is actually healthy
			if [[ $primary_check_passed -eq 0 ]]; then
				handle_error "WARNING" "$location_name" "VPN failure type: Routing issue (tunnel established but traffic not flowing) for $ip_display"
			fi
			# Note: If primary_check_passed was 1, we keep it as 1 and don't log routing_issue warning
			# since ping check is supplementary and primary check (SA + byte counters) is authoritative
			;;
		*)
			# "unknown" failure type
			# If primary_check_passed was 1, this means primary check passed but we couldn't determine a specific failure type
			# This is normal when VPN is healthy (e.g., bytes increasing, no rekey, ping check disabled)
			# Only log "unknown" if primary check actually failed (primary_check_passed was 0)
			if [[ $primary_check_passed -eq 0 ]]; then
				# Detailed diagnostic information was already logged by detect_failure_type()
				handle_error "WARNING" "$location_name" "VPN failure type: Unknown (unable to determine specific failure type) for $ip_display - see previous diagnostic messages for detection method details"
			fi
			# If primary_check_passed was 1, silently ignore "unknown" since primary check passed
			;;
		esac
	fi

	# Output the final primary check status
	echo "$primary_check_passed"
	return 0
}

# Check VPN status using ip xfrm state
#
# Verifies VPN tunnel health by checking IPsec Security Association (SA) state and byte counters.
# Uses multiple methods in order: ip xfrm state (primary), ipsec status (fallback).
# If ping checks are enabled, also verifies end-to-end connectivity.
#
# Arguments:
#   $1: External peer IP address (external/public IP of remote VPN gateway, used for xfrm state checks)
#   $2: Internal peer IP address(es) (optional, can be single IP string or space-separated string of multiple IPs, falls back to external if not provided)
#   $3: Location name (required, used for state file naming)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Detection logic:
#   1. Checks ip xfrm state for SA matching external peer IP
#   2. Validates byte counters are > 0 and increasing (if available)
#   3. Falls back to ipsec status if xfrm doesn't confirm
#   4. Optionally performs ping check if ENABLE_PING_CHECK=1 (uses internal IP(s) if provided)
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
#   - When both xfrm and ipsec status checks fail, logs a single combined diagnostic message
#     that includes which detection methods were attempted and why each failed
#
# Note:
#   Requires validate_ip_address, sanitize_peer_ip, sanitize_location_name, log_message, STATE_DIR, ENABLE_PING_CHECK to be set
#   External IP is used for xfrm checks, internal IP(s) are used for ping checks
#   For multiple internal IPs, ping check succeeds if ≥30% respond
#   Diagnostic messages are combined when both primary (xfrm) and fallback (ipsec status) methods fail
check_vpn_status() {
	local external_peer_ip="$1"
	local internal_peer_ips="${2:-}"
	local location_name="$3"
	local primary_check_passed=0

	# Validate external peer IP format using proper validation function
	if ! validate_ip_address "$external_peer_ip"; then
		handle_error "ERROR" "SYSTEM" "Invalid external peer IP format: $external_peer_ip" 0
		return 1
	fi

	# Validate location_name is provided
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "check_vpn_status: location_name is required" 0
		return 1
	fi

	# Per-peer state tracking (use location name + external IP for state management)
	local peer_sanitized
	local location_sanitized=""

	# Use location-based naming: sanitize location name and combine with IP
	if command -v sanitize_location_name >/dev/null 2>&1; then
		location_sanitized=$(sanitize_location_name "$location_name")
	else
		# Fallback if sanitize_location_name not available (shouldn't happen)
		location_sanitized="${location_name//[^A-Za-z0-9_]/_}"
	fi
	local ip_sanitized
	ip_sanitized=$(sanitize_peer_ip "$external_peer_ip")
	peer_sanitized="${location_sanitized}_${ip_sanitized}"

	# Try detection methods in order of reliability
	# For xfrm check, use first internal IP if multiple provided (or empty if single/external)
	local first_internal_ip=""
	if [[ -n "$internal_peer_ips" ]]; then
		local IFS=' '
		local -a ips_array
		read -ra ips_array <<<"$internal_peer_ips"
		if [[ ${#ips_array[@]} -gt 0 ]]; then
			first_internal_ip="${ips_array[0]}"
		fi
	fi

	# Collect diagnostic information from both methods to combine warnings when both fail
	local xfrm_diagnostic=""
	local ipsec_diagnostic=""
	# Capture xfrm_output from xfrm check to eliminate duplicate ip xfrm state calls
	local xfrm_output=""
	# Note: sa_exists_var is kept for internal optimization in check_xfrm_primary but not used upstream
	local sa_exists_var=""

	if check_xfrm_primary "$external_peer_ip" "$first_internal_ip" "$location_name" "xfrm_diagnostic" "sa_exists_var" "xfrm_output"; then
		primary_check_passed=1
	else
		# xfrm check failed - try ipsec fallback
		if check_ipsec_fallback "$external_peer_ip" "$location_name" "ipsec_diagnostic"; then
			primary_check_passed=1
		else
			# Both methods failed - check IPsec daemon status for diagnostics
			local ipsec_daemon_status="unknown"
			if check_command_available "systemctl"; then
				# Try systemctl first (more reliable on UDM OS)
				# Get full path to systemctl for reliable execution in PATH-restricted environments (cron/systemd)
				local systemctl_cmd
				systemctl_cmd=$(get_command_path "systemctl")
				# Capture both stdout and stderr, handle exit code properly
				# systemctl is-active returns: "active", "inactive", "activating", "deactivating", "failed", "unknown", or exit code 3 for unknown
				local systemctl_output
				systemctl_output=$("$systemctl_cmd" is-active ipsec 2>&1)
				local systemctl_exit=$?

				if [[ $systemctl_exit -eq 0 ]]; then
					# Command succeeded - output should be service state
					# Normalize output (trim whitespace, handle case)
					ipsec_daemon_status=$(echo "$systemctl_output" | tr -d '\n\r ' | tr '[:upper:]' '[:lower:]')
					# Map systemctl states to our status values
					case "$ipsec_daemon_status" in
					"active")
						ipsec_daemon_status="running"
						;;
					"inactive" | "failed")
						ipsec_daemon_status="inactive"
						;;
					"activating" | "deactivating")
						ipsec_daemon_status="transitioning"
						;;
					*)
						# Unknown state from systemctl
						ipsec_daemon_status="unknown_state"
						log_message "DEBUG" "$location_name" "systemctl is-active ipsec returned unexpected state: $systemctl_output"
						;;
					esac
				elif [[ $systemctl_exit -eq 3 ]]; then
					# Exit code 3 means service is in unknown state (not loaded/not found)
					ipsec_daemon_status="not_found"
				else
					# Command failed for other reason
					ipsec_daemon_status="check_failed"
					log_message "DEBUG" "$location_name" "systemctl is-active ipsec failed (exit: $systemctl_exit, output: $systemctl_output)"
				fi
			elif check_command_available "pgrep"; then
				# Fallback to pgrep if systemctl unavailable
				# Get full path to pgrep for reliable execution in PATH-restricted environments (cron/systemd)
				local pgrep_cmd
				pgrep_cmd=$(get_command_path "pgrep")
				if "$pgrep_cmd" -x ipsec >/dev/null 2>&1; then
					ipsec_daemon_status="running"
				else
					ipsec_daemon_status="not_running"
				fi
			fi

			# Log IPsec daemon status for diagnostics
			log_message "DEBUG" "$location_name" "Both xfrm and ipsec status checks failed - IPsec daemon status: $ipsec_daemon_status"

			# Both methods failed - log combined diagnostic message
			local combined_diagnostics=()
			if [[ -n "$xfrm_diagnostic" ]]; then
				combined_diagnostics+=("$xfrm_diagnostic")
			fi
			if [[ -n "$ipsec_diagnostic" ]]; then
				combined_diagnostics+=("$ipsec_diagnostic")
			fi

			if [[ ${#combined_diagnostics[@]} -gt 0 ]]; then
				# Join diagnostics with semicolon and space
				local diagnostic_msg=""
				local first=1
				for diag in "${combined_diagnostics[@]}"; do
					if [[ $first -eq 1 ]]; then
						diagnostic_msg="$diag"
						first=0
					else
						diagnostic_msg="$diagnostic_msg; $diag"
					fi
				done
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")
				handle_error "WARNING" "$location_name" "VPN suspect for $ip_display - $diagnostic_msg"
			else
				# Fallback if diagnostics weren't collected (shouldn't happen)
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")
				handle_error "WARNING" "$location_name" "VPN suspect: Both xfrm and ipsec status checks failed for $ip_display"
			fi
		fi
	fi

	# Perform optional ping check if enabled (pass all internal IPs for multiple IP support)
	# check_ping_optional will derive SA existence from primary_check_passed
	check_ping_optional "$primary_check_passed" "$external_peer_ip" "$internal_peer_ips" "$location_name"

	# Determine final primary check status based on failure type detection
	# Pass location_name, first internal IP, and xfrm_output for failure type detection
	primary_check_passed=$(determine_vpn_status "$primary_check_passed" "$external_peer_ip" "$first_internal_ip" "$location_name" "$xfrm_output")

	# Return 0 if OK, 1 if failed (invert primary_check_passed: 1 becomes 0, 0 becomes 1)
	return $((1 - primary_check_passed))
}

# Check for network partition
#
# Performs multiple checks to detect network partition:
# 1. Default route exists
# 2. DNS resolution works
# 3. Critical interfaces are UP
#
# If any check fails, network is considered partitioned.
#
# Arguments:
#   $1: DNS server to use for DNS check (optional, defaults to 8.8.8.8)
#   $2: Hostname to resolve for DNS check (optional, defaults to google.com)
#   $3: DNS timeout in seconds (optional, defaults to 2)
#   $4: Comma-separated list of interfaces to check (optional, defaults to "br0,eth0")
#
# Returns:
#   0: Network is healthy (all checks passed)
#   1: Network is partitioned (one or more checks failed)
#
# Side effects:
#   - Logs debug messages about which checks passed/failed
#
# Note:
#   Requires check_default_route, check_dns_resolution, check_interface_state,
#   log_message to be set
#   All checks must pass for network to be considered healthy
check_network_partition() {
	local dns_server="${1:-8.8.8.8}"
	local hostname="${2:-google.com}"
	local dns_timeout="${3:-2}"
	local interfaces="${4:-br0,eth0}"
	local partition_detected=0

	# Check default route
	local route_check_result
	if ! check_default_route; then
		route_check_result=1
		handle_error "WARNING" "SYSTEM" "Network partition detected: default route not found" 0
		partition_detected=1
		# Track statistics: route check failed
		track_network_partition_check "route" 0
	else
		route_check_result=0
		# Track statistics: route check succeeded
		track_network_partition_check "route" 1
	fi

	# Check DNS resolution
	local dns_check_result
	if ! check_dns_resolution "$dns_server" "$hostname" "$dns_timeout"; then
		dns_check_result=1
		handle_error "WARNING" "SYSTEM" "Network partition detected: DNS resolution failed (server: $dns_server, hostname: $hostname)" 0
		partition_detected=1
		# Track statistics: DNS check failed
		track_network_partition_check "dns" 0
	else
		dns_check_result=0
		# Track statistics: DNS check succeeded
		track_network_partition_check "dns" 1
	fi

	# Check interface state
	local interface_check_result
	if ! check_interface_state "$interfaces"; then
		interface_check_result=1
		handle_error "WARNING" "SYSTEM" "Network partition detected: one or more critical interfaces are DOWN (checked: $interfaces)" 0
		partition_detected=1
		# Track statistics: interface check failed
		track_network_partition_check "interface" 0
	else
		interface_check_result=0
		# Track statistics: interface check succeeded
		track_network_partition_check "interface" 1
	fi

	# If all checks passed, network is healthy
	if [[ $partition_detected -eq 0 ]]; then
		return 0
	fi

	return 1
}
