#!/bin/bash
#
# Failure analysis functions for UDM VPN Monitor
# Handles failure type classification and VPN status determination
#
# Version: 0.6.0
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
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# Source logging functions (required for log_message and handle_error)
# shellcheck source=lib/logging.sh
if ! source "${LIB_DIR}/logging.sh" 2>/dev/null; then
	# shellcheck source=lib/fallbacks.sh
	if [[ -n "${LIB_DIR:-}" ]] && [[ -f "${LIB_DIR}/fallbacks.sh" ]] && [[ -r "${LIB_DIR}/fallbacks.sh" ]]; then
		source "${LIB_DIR}/fallbacks.sh" 2>/dev/null && define_logging_fallbacks
	fi
fi

# shellcheck source=lib/detection/network_validation.sh
source "${LIB_DIR}/detection/network_validation.sh"
# shellcheck source=lib/detection/xfrm_detection.sh
source "${LIB_DIR}/detection/xfrm_detection.sh"
# shellcheck source=lib/detection/ping_detection.sh
source "${LIB_DIR}/detection/ping_detection.sh"

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
#
# Arguments:
#   $1: External peer IP address (used for SA checks)
#   $2: Internal peer IP address (optional, used for ping checks)
#   $3: Location name (required, used for state file naming)
#   $4: SA existence state (optional, 0 = no SA, 1 = SA exists, if not provided will check SA existence)
#   $5: VPN status (optional, 0 = VPN check failed, 1 = VPN check passed, defaults to 0 for backward compatibility)
#   $6: XFRM output (optional, xfrm state output for reuse, if not provided will fetch if needed)
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
#   - Only logs warnings when VPN check failed (vpn_ok=0) to avoid false positives for healthy VPNs
#
# Examples:
#   failure_type=$(detect_failure_type "203.0.113.1" "192.168.1.1" "NYC" "1" "0" "$xfrm_output")
#   case "$failure_type" in
#       "tunnel_down") echo "VPN tunnel is down" ;;
#       "routing_issue") echo "Routing issue detected" ;;
#       "rekey") echo "SA rekey detected" ;;
#   esac
#
# Note:
#   Requires check_ipsec_phase2, check_byte_counters, check_ping_connectivity, detect_sa_rekey
#   External IP is used for SA checks, internal IP is used for ping checks
#   When vpn_ok=1 (VPN is healthy), warnings are suppressed to avoid false positives
#   When xfrm_output is provided, reuses it to avoid duplicate ip xfrm state calls (optimization)
detect_failure_type() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local location_name="$3"
	local sa_exists="${4:-}"
	local vpn_ok="${5:-0}"
	local xfrm_output="${6:-}"

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

	# Use provided SA existence state if available, otherwise check SA existence
	# This optimization eliminates duplicate SA checks by reusing state from check_xfrm_status()
	local ipsec_phase2_up=0
	if [[ -n "$sa_exists" ]]; then
		ipsec_phase2_up=$sa_exists
	else
		if check_ipsec_phase2 "$external_peer_ip"; then
			ipsec_phase2_up=1
		fi
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
		if [[ -z "$xfrm_output" ]] && [[ -n "$external_peer_ip" ]]; then
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
		if [[ -n "$current_spi" ]]; then
			if check_sa_rekey_occurred "$current_spi" "$external_peer_ip" "$location_name" 2>/dev/null; then
				# Rekey detected - not a failure, but log for monitoring
				# Note: We use read-only check here since detect_failure_type is called
				# after VPN check failed. The actual rekey handling (baseline reset)
				# should have happened in check_byte_counters during the check.
				echo "rekey"
				return 0
			fi
		fi

		# Phase 2 SA exists and no rekey detected - check for routing issues
		# Check byte counters if available
		local has_routing_issue=0

		# Check byte counters using abstraction layer (peer IP is available)
		if [[ -n "$current_bytes" ]] && [[ "$current_bytes" =~ ^[0-9]+$ ]]; then
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
		# Only check ping if we haven't already detected a routing issue from byte counters
		if [[ $has_routing_issue -eq 0 ]] && [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			if ! check_ping_connectivity "$internal_peer_ip" "$local_ip" 2>/dev/null; then
				has_routing_issue=1
			fi
		fi

		if [[ $has_routing_issue -eq 1 ]]; then
			echo "routing_issue"
			return 0
		fi
		# Phase 2 SA exists but no routing issue detected
		# This can happen when:
		#   - Byte counters are not available (extraction failed)
		#   - Ping check is disabled or internal IP not provided
		#   - VPN check failed for another reason (e.g., byte counter validation in check_xfrm_status)
		# In this case, we return "unknown" since we can't definitively determine the failure type
		# without additional diagnostic information

		local diagnostic_parts=()
		diagnostic_parts+=("Phase 2 SA exists")
		if [[ -z "$xfrm_output" ]]; then
			diagnostic_parts+=("xfrm output unavailable")
		elif [[ -z "$current_bytes" ]] || [[ ! "$current_bytes" =~ ^[0-9]+$ ]]; then
			diagnostic_parts+=("byte counter extraction failed")
		else
			local last_bytes
			last_bytes=$(get_peer_state "$location_name" "$external_peer_ip" "last_bytes" "0")
			diagnostic_parts+=("byte counters available (current=$current_bytes, last=$last_bytes) but no routing issue detected")
		fi

		if [[ -z "$internal_peer_ip" ]]; then
			diagnostic_parts+=("internal IP not provided")
		fi

		if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
			diagnostic_parts+=("ping check disabled")
		elif [[ -n "$internal_peer_ip" ]]; then
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			diagnostic_parts+=("ping check enabled but routing issue not confirmed")
		fi

		local diagnostic_msg=""
		local first=1
		for part in "${diagnostic_parts[@]}"; do
			if [[ $first -eq 1 ]]; then
				diagnostic_msg="$part"
				first=0
			else
				diagnostic_msg="$diagnostic_msg, $part"
			fi
		done
		# Only log warning if VPN check failed (vpn_ok=0)
		# When VPN is healthy (vpn_ok=1), returning "unknown" is expected behavior
		# and should not generate warnings to avoid false positives
		if [[ $vpn_ok -eq 0 ]]; then
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
			log_message "WARNING" "$location_name" "Failure type detection: Unable to determine specific failure type for $ip_display - Detection method: Phase 2 SA check (SA exists), Reasons: $diagnostic_msg"
		fi
	fi

	# Unable to determine failure type (fallback)
	# This occurs when:
	#   - Phase 2 SA doesn't exist (handled above as "tunnel_down")
	#   - Phase 2 SA exists but we can't determine if it's a routing issue (see comment above)
	#   - Detection methods are unavailable or failed
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
	local peer_ip="$2"
	local failure_type_file

	# Use abstraction layer to ensure consistent path format
	failure_type_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_type")

	if file_exists_and_readable "$failure_type_file"; then
		local failure_type
		failure_type=$(cat "$failure_type_file" 2>/dev/null | head -1 | tr -d '\n\r ' || echo "unknown")
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
#   $4: Sanitized peer IP (for state file operations)
#   $5: Location name (required, used for state file naming)
#   $6: SA existence state (optional, 0 = no SA, 1 = SA exists, if not provided will check SA existence)
#   $7: XFRM output (optional, xfrm state output for reuse, if not provided will fetch if needed)
#
# Returns:
#   Outputs final VPN status (0 or 1) to stdout
#   Returns 0 on success
#
# Side effects:
#   - Creates/updates per-peer failure_type state file
#   - Logs failure type and status messages
determine_vpn_status() {
	local vpn_ok="$1"
	local external_peer_ip="$2"
	local internal_peer_ip="${3:-}"
	local peer_sanitized="$4"
	local location_name="$5"
	local sa_exists="${6:-}"
	local xfrm_output="${7:-}"

	# Validate location_name is provided
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "determine_vpn_status: location_name is required" 0
		echo "0"
		return 1
	fi

	# If VPN check failed, detect and log the failure type
	# Also check for rekey events (which are not failures but should be logged)
	# Additionally, if VPN appears OK, check for rekey events and routing issues via ping (if enabled)
	local check_failure_type=0
	if [[ $vpn_ok -eq 0 ]]; then
		check_failure_type=1
	elif [[ $vpn_ok -eq 1 ]]; then
		# VPN appears OK, but we should still check for:
		# 1. Rekey events (SPI changes) - always check
		# 2. Routing issues via ping - only if ping check is enabled and internal IP provided
		# Use provided SA existence state if available, otherwise check SA existence
		if [[ -z "$sa_exists" ]]; then
			# Fallback: check SA existence if not provided (for backward compatibility)
			sa_exists=0
			if check_ipsec_phase2 "$external_peer_ip" 2>/dev/null; then
				sa_exists=1
			fi
		fi
		if [[ $sa_exists -eq 1 ]]; then
			# Always check for rekey events when VPN is OK
			# Also check for routing issues via ping if ping check is enabled
			if [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
				# Check for routing issues via ping when ping check is enabled
				check_failure_type=1
			else
				# Even if ping check is disabled, we should check for rekey events
				# We'll call detect_failure_type which will check for rekey first
				# If no rekey and no routing issue to check, it will return "unknown" which we'll ignore
				check_failure_type=1
			fi
		fi
	fi

	if [[ $check_failure_type -eq 1 ]]; then
		local failure_type
		# Capture output and return code separately to avoid duplicate "unknown"
		# Note: stderr is not redirected so diagnostic log messages from detect_failure_type are visible
		# Pass SA existence state to detect_failure_type to avoid duplicate check
		# Pass vpn_ok status so detect_failure_type can suppress warnings for healthy VPNs
		# Pass xfrm_output to detect_failure_type to avoid duplicate ip xfrm state call (optimization)
		failure_type=$(detect_failure_type "$external_peer_ip" "$internal_peer_ip" "$location_name" "$sa_exists" "$vpn_ok" "$xfrm_output")
		# If detect_failure_type failed or returned empty, use "unknown"
		if [[ -z "$failure_type" ]]; then
			failure_type="unknown"
		fi

		# Store failure type in state file for recovery actions
		# Use abstraction layer to ensure consistent path format with location component
		local failure_type_file
		failure_type_file=$(get_peer_state_file_path "$location_name" "$external_peer_ip" "failure_type")
		atomic_write_file "$failure_type_file" "$failure_type" 2>/dev/null || true

		case "$failure_type" in
		"rekey")
			# Rekey detected - not a failure, but log for monitoring
			# Rekey is already logged in detect_sa_rekey, but we mark VPN as OK
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
			log_message "INFO" "$location_name" "SA rekey detected for $ip_display (not a failure)"
			vpn_ok=1
			;;
		"tunnel_down")
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
			handle_error "WARNING" "$location_name" "VPN failure type: Tunnel down (no Phase 2 SA found) for $ip_display"
			;;
		"routing_issue")
			# Only log warning if VPN check actually failed (vpn_ok=0)
			# When vpn_ok=1, ping check failure is supplementary diagnostic and doesn't indicate a real problem
			if [[ $vpn_ok -eq 0 ]]; then
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
				handle_error "WARNING" "$location_name" "VPN failure type: Routing issue (tunnel established but traffic not flowing) for $ip_display"
			fi
			# Note: If vpn_ok was 1 (VPN appeared OK), we keep it as 1 since ping is supplementary
			# The routing_issue is detected for diagnostic purposes but doesn't change VPN status or generate warnings
			;;
		*)
			# "unknown" failure type
			# If vpn_ok was 1, this means VPN check passed but we couldn't determine a specific failure type
			# This is normal when VPN is healthy (e.g., bytes increasing, no rekey, ping check disabled)
			# Only log "unknown" if VPN check actually failed (vpn_ok was 0)
			if [[ $vpn_ok -eq 0 ]]; then
				# Detailed diagnostic information was already logged by detect_failure_type()
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ip")
				handle_error "WARNING" "$location_name" "VPN failure type: Unknown (unable to determine specific failure type) for $ip_display - see previous diagnostic messages for detection method details"
			fi
			# If vpn_ok was 1, silently ignore "unknown" since VPN is healthy
			;;
		esac
	fi

	# Output the final VPN status
	echo "$vpn_ok"
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
	local vpn_ok=0

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
	# Capture SA existence state from xfrm check to eliminate duplicate checks
	local sa_exists=""
	# Capture xfrm_output from xfrm check to eliminate duplicate ip xfrm state calls
	local xfrm_output=""

	if check_xfrm_primary "$external_peer_ip" "$first_internal_ip" "$location_name" "xfrm_diagnostic" "sa_exists" "xfrm_output"; then
		vpn_ok=1
	else
		# xfrm check failed - try ipsec fallback
		# Note: If xfrm check failed, sa_exists may still be set (SA exists but validation failed)
		# If sa_exists is empty, we'll fall back to checking SA existence in downstream functions
		if check_ipsec_fallback "$external_peer_ip" "$location_name" "ipsec_diagnostic"; then
			vpn_ok=1
			# If ipsec fallback succeeded, SA exists (set sa_exists if not already set)
			if [[ -z "$sa_exists" ]]; then
				sa_exists=1
			fi
		else
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
			# If both methods failed and sa_exists is not set, assume no SA exists
			if [[ -z "$sa_exists" ]]; then
				sa_exists=0
			fi
		fi
	fi

	# Perform optional ping check if enabled (pass all internal IPs for multiple IP support)
	# Pass SA existence state to eliminate duplicate check
	check_ping_optional "$vpn_ok" "$external_peer_ip" "$internal_peer_ips" "$location_name" "$sa_exists"

	# Determine final VPN status based on failure type detection
	# Pass location_name, first internal IP, peer_sanitized, SA existence state, and xfrm_output for failure type detection
	vpn_ok=$(determine_vpn_status "$vpn_ok" "$external_peer_ip" "$first_internal_ip" "$peer_sanitized" "$location_name" "$sa_exists" "$xfrm_output")

	# Return 0 if OK, 1 if failed (invert vpn_ok: 1 becomes 0, 0 becomes 1)
	return $((1 - vpn_ok))
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
