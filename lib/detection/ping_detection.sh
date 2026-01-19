#!/bin/bash
#
# Ping detection functions for UDM VPN Monitor
# Handles ping-based connectivity checks (single and multiple IPs)
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

# shellcheck source=lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=lib/detection/network_validation.sh
source "${LIB_DIR}/detection/network_validation.sh"

# Log periodic ping summary at configured interval
#
# Logs a summary of successful ping checks at INFO level at the interval specified by
# PING_SUMMARY_INTERVAL_MINUTES (default: 7 minutes). Tracks the last summary timestamp
# and ping count in a state file.
#
# Arguments:
#   $1: Target IP address (for logging context)
#   $2: Local IP address (optional, for logging context)
#
# Returns:
#   0: Always succeeds (logging failures are non-fatal)
#
# Side effects:
#   - Creates/updates ${STATE_DIR}/ping_summary_last_time with timestamp
#   - Creates/updates ${STATE_DIR}/ping_summary_count with ping count
#   - Logs summary message at INFO level when configured interval has elapsed
#
# Configuration:
#   Uses PING_SUMMARY_INTERVAL_MINUTES from config (default: 7 minutes)
#
# Note:
#   Requires STATE_DIR, SECONDS_PER_MINUTE, PING_SUMMARY_INTERVAL_MINUTES, get_unix_timestamp, log_message, and ensure_file_exists
log_ping_summary_if_due() {
	local target_ip="$1"
	local local_ip="${2:-}"

	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Get summary interval from config (default: 7 minutes)
	local summary_interval_minutes="${PING_SUMMARY_INTERVAL_MINUTES:-7}"
	local summary_interval_seconds=$((summary_interval_minutes * ${SECONDS_PER_MINUTE:-60}))

	# State files for tracking
	local last_time_file="${STATE_DIR}/ping_summary_last_time"
	local count_file="${STATE_DIR}/ping_summary_count"

	# Get current timestamp
	local current_time
	current_time=$(get_unix_timestamp 2>/dev/null || echo "0")

	# Initialize state files if they don't exist
	ensure_file_exists "$last_time_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$count_file" "0" 2>/dev/null || return 0

	# Read last summary time and current count
	# Check readability before reading to prevent hangs on unreadable files
	local last_time
	if file_exists_and_readable "$last_time_file"; then
		last_time=$(cat "$last_time_file" 2>/dev/null || echo "0")
	else
		last_time="0"
	fi
	local ping_count
	ping_count=$(read_counter_file "$count_file")

	# Increment ping count
	ping_count=$((ping_count + 1))
	# Use atomic write for state file (per ADR-0012)
	atomic_write_file "$count_file" "$ping_count" 2>/dev/null || true

	# Check if configured interval has elapsed since last summary
	local time_since_last=$((current_time - last_time))

	if [[ $time_since_last -ge $summary_interval_seconds ]] || [[ $last_time -eq 0 ]]; then
		# Time to log summary
		if [[ $ping_count -gt 0 ]]; then
			if [[ -n "$local_ip" ]]; then
				log_message "INFO" "SYSTEM" "Ping check summary: $ping_count successful checks in the last ${summary_interval_minutes} minutes (target: $target_ip from $local_ip)"
			else
				log_message "INFO" "SYSTEM" "Ping check summary: $ping_count successful checks in the last ${summary_interval_minutes} minutes (target: $target_ip)"
			fi
		fi

		# Reset count and update last time (use atomic writes per ADR-0012)
		atomic_write_file "$count_file" "0" 2>/dev/null || true
		atomic_write_file "$last_time_file" "$current_time" 2>/dev/null || true
	fi

	return 0
}

# Build ping command and arguments for target IP
#
# Determines the appropriate ping command (ping, ping6, or ping -6) and builds
# the command arguments based on the target IP version (IPv4 or IPv6) and
# optional source IP address.
#
# Arguments:
#   $1: Target IP address to ping (required)
#   $2: Local source IP address (optional, for ping -I flag)
#
# Output:
#   Sets the following variables in caller's scope (caller must declare them):
#   - ping_cmd: The ping command to use ("ping" or "ping6")
#   - ping_args: Array of ping arguments (e.g., (-I "192.168.1.1") or (-6 -I "192.168.1.1"))
#
# Returns:
#   0: Successfully determined ping command and arguments
#   1: IPv6 ping not available (only for IPv6 targets)
#
# Examples:
#   local ping_cmd ping_args=()
#   if build_ping_command "192.168.1.1" "192.168.1.100"; then
#       "$ping_cmd" "${ping_args[@]}" -c 3 "192.168.1.1"
#   fi
#
# Note:
#   - Uses validate_ipv4() for IP version detection (more accurate than regex)
#   - Prefers ping6 for IPv6 if available, falls back to ping -6
#   - Caller is responsible for error handling and logging
build_ping_command() {
	local target_ip="$1"
	local local_ip="${2:-}"

	# Validate input
	if [[ -z "$target_ip" ]]; then
		return 1
	fi

	# Determine ping command based on IP version
	# Some systems have separate ping6, others use ping -6
	if validate_ipv4 "$target_ip"; then
		# IPv4
		ping_cmd="ping"
		# Add -I flag if local_ip is provided
		if [[ -n "$local_ip" ]]; then
			ping_args=(-I "$local_ip")
		else
			ping_args=()
		fi
	else
		# IPv6
		if check_command_available "ping6"; then
			ping_cmd="ping6"
			# Add -I flag if local_ip is provided (ping6 uses -I for source interface/IP)
			if [[ -n "$local_ip" ]]; then
				ping_args=(-I "$local_ip")
			else
				ping_args=()
			fi
		elif check_command_available "ping" && ping -6 >/dev/null 2>&1; then
			ping_cmd="ping"
			# Add -I flag if local_ip is provided
			if [[ -n "$local_ip" ]]; then
				ping_args=(-6 -I "$local_ip")
			else
				ping_args=(-6)
			fi
		else
			# IPv6 ping not available
			return 1
		fi
	fi

	return 0
}

# Check ping connectivity to target IP
#
# Performs a ping connectivity check to the specified target IP address.
# Optionally uses a local source IP for the ping. Manages routes on br0 interface
# if local_ip is provided. Supports both IPv4 and IPv6 addresses.
#
# Arguments:
#   $1: Target IP address to ping (required)
#   $2: Local source IP address (optional, for ping -I flag)
#   $3: Location name for logging (optional)
#
# Returns:
#   0: Ping successful (packet loss below threshold)
#   1: Ping failed (packet loss above threshold, command error, or timeout)
#
# Side effects:
#   - Adds route to br0 interface if local_ip provided and route doesn't exist
#   - Logs ping results at DEBUG/INFO/WARNING levels
check_ping_connectivity() {
	local target_ip="$1"
	local local_ip="${2:-}"
	local location_name="${3:-}"
	local ping_count="${PING_COUNT:-3}"
	local ping_timeout="${PING_TIMEOUT:-2}"

	# Validate ping target
	if [[ -z "$target_ip" ]]; then
		handle_error "WARNING" "${location_name:-SYSTEM}" "Ping check enabled but target IP not configured"
		return 1
	fi

	# Check if ping command is available
	if ! check_command_or_warn "ping" "Ping check enabled"; then
		return 1
	fi

	# If local_ip is provided, manage route on br0 before pinging
	if [[ -n "$local_ip" ]]; then
		# Check if route exists, add if needed
		if ! check_route_exists "$local_ip"; then
			log_message "INFO" "${location_name:-SYSTEM}" "Route not found on br0, attempting to add: $local_ip/${IPV4_CIDR_SINGLE_HOST}"
			if ! add_route_if_needed "$local_ip"; then
				handle_error "WARNING" "${location_name:-SYSTEM}" "Failed to add route for ping check, continuing anyway"
				# Continue with ping attempt - it may still work or fail naturally
			fi
		fi
	fi

	# Build ping command and arguments
	local ping_cmd
	local ping_args=()
	if ! build_ping_command "$target_ip" "$local_ip"; then
		handle_error "WARNING" "${location_name:-SYSTEM}" "IPv6 ping not available"
		return 1
	fi

	# Perform ping check
	# Uses Linux-style ping (-W for timeout)
	# -c: count of packets, -q: quiet (summary only), -W: timeout per packet
	# -I: source IP address (if local_ip provided)
	# Wrap ping commands with timeout to prevent hanging
	# Calculate timeout wrapper: min(ping_timeout + 1, min(ping_count * ping_timeout + 1, 5))
	# This ensures we catch hanging commands quickly while allowing normal pings to complete
	local quick_timeout=$((ping_timeout + 1))
	local normal_timeout=$((ping_count * ping_timeout + 1))
	# Cap normal timeout at 5 seconds for responsiveness
	if [[ $normal_timeout -gt 5 ]]; then
		normal_timeout=5
	fi
	# Use the smaller timeout to catch hangs quickly
	local ping_wrapper_timeout
	if [[ $quick_timeout -lt $normal_timeout ]]; then
		ping_wrapper_timeout=$quick_timeout
	else
		ping_wrapper_timeout=$normal_timeout
	fi
	local ping_result
	local ping_success=0
	local ping_exit_code=0

	# Use Linux-style ping with timeout wrapper
	if check_command_available "timeout"; then
		# Try with -W flag first (Linux-style timeout per packet)
		if ping_result=$(timeout "$ping_wrapper_timeout" "$ping_cmd" "${ping_args[@]}" -c "$ping_count" -W "$ping_timeout" -q "$target_ip" 2>&1); then
			ping_success=1
		else
			ping_exit_code=$?
			# If timeout wrapper triggered (exit 124), ping hung - don't try fallbacks
			if [[ $ping_exit_code -eq 124 ]]; then
				ping_success=0
			# Try without -W flag as fallback (some ping implementations don't support -W)
			# Still use timeout wrapper to prevent hanging
			elif ping_result=$(timeout "$ping_wrapper_timeout" "$ping_cmd" "${ping_args[@]}" -c "$ping_count" -q "$target_ip" 2>&1); then
				ping_success=1
				ping_exit_code=0
			fi
		fi
	else
		# Fallback if timeout command not available (shouldn't happen on UDM)
		if ping_result=$("$ping_cmd" "${ping_args[@]}" -c "$ping_count" -W "$ping_timeout" -q "$target_ip" 2>&1); then
			ping_success=1
		# Try without -W flag as fallback
		elif ping_result=$("$ping_cmd" "${ping_args[@]}" -c "$ping_count" -q "$target_ip" 2>&1); then
			ping_success=1
		fi
	fi

	if [[ $ping_success -eq 1 ]]; then
		# Extract packet loss percentage
		local packet_loss
		packet_loss=$(echo "$ping_result" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' || echo "0")

		if [[ "$packet_loss" -lt $PING_PACKET_LOSS_THRESHOLD ]]; then
			# Log successful ping at DEBUG level
			if [[ -n "$local_ip" ]]; then
				log_message "DEBUG" "${location_name:-SYSTEM}" "Ping check OK: $target_ip from $local_ip (${packet_loss}% packet loss)"
			else
				log_message "DEBUG" "${location_name:-SYSTEM}" "Ping check OK: $target_ip (${packet_loss}% packet loss)"
			fi
			# Log periodic summary at configured interval at INFO level
			log_ping_summary_if_due "$target_ip" "$local_ip"
			return 0
		else
			if [[ -n "$local_ip" ]]; then
				handle_error "WARNING" "${location_name:-SYSTEM}" "Ping check failed: $target_ip from $local_ip (${packet_loss}% packet loss)"
			else
				handle_error "WARNING" "${location_name:-SYSTEM}" "Ping check failed: $target_ip (${packet_loss}% packet loss)"
			fi
			return 1
		fi
	else
		# Ping command failed
		# If route was added but ping still failed, this indicates a tunnel issue
		local error_msg
		# Check for timeout (exit code 124) only if timeout wrapper was used
		if [[ $ping_exit_code -eq 124 ]] && check_command_available "timeout"; then
			# Timeout occurred (exit code 124 from timeout command)
			if [[ -n "$local_ip" ]]; then
				error_msg="Ping check timed out: $target_ip from $local_ip (command hung after ${ping_wrapper_timeout}s)"
			else
				error_msg="Ping check timed out: $target_ip (command hung after ${ping_wrapper_timeout}s)"
			fi
		else
			# Other error
			if [[ -n "$local_ip" ]]; then
				error_msg="Ping check failed: $target_ip from $local_ip (ping command error or timeout)"
			else
				error_msg="Ping check failed: $target_ip (ping command error or timeout)"
			fi
		fi
		handle_error "WARNING" "${location_name:-SYSTEM}" "$error_msg"
		return 1
	fi
}

# Check ping connectivity for multiple internal IPs
#
# Pings multiple internal IPs sequentially and considers the check successful
# if at least 30% of the IPs respond successfully (rounded up using ceil).
# For a single IP, requires 100% success.
#
# Arguments:
#   $1: Array of internal IP addresses (space-separated string or array reference)
#   $2: Local IP address (for source IP, optional)
#   $3: Location name (optional, used for logging)
#
# Returns:
#   0: Success threshold met (≥30% of IPs responded)
#   1: Success threshold not met (<30% of IPs responded)
#
# Output:
#   Logs detailed ping results including success count and percentage
#
# Examples:
#   check_ping_multiple_ips "192.168.1.1 192.168.1.88" "192.168.1.1" "NYC"
#   # Pings both IPs, succeeds if at least 1 responds (30% of 2 = 0.6, ceil = 1)
#
# Note:
#   - Uses awk for floating-point math (UDM OS doesn't have bc)
#   - Sequential ping execution (no parallel - UDM OS limitation)
#   - Single IP requires 100% success (not 30%)
#   - Empty array falls back to external IP (handled by caller)
check_ping_multiple_ips() {
	local internal_ips_input="$1"
	local local_ip="${2:-}"
	local location_name="${3:-}"
	local IFS=' '
	local -a internal_ips_array
	local ping_success_count=0
	local ping_total_count=0
	local ping_result

	# Convert input to array
	if [[ -z "$internal_ips_input" ]]; then
		# Empty array - return failure (caller should handle fallback)
		return 1
	fi

	read -ra internal_ips_array <<<"$internal_ips_input"
	ping_total_count=${#internal_ips_array[@]}

	# Edge case: single IP requires 100% success
	if [[ $ping_total_count -eq 1 ]]; then
		local single_ip="${internal_ips_array[0]}"
		if check_ping_connectivity "$single_ip" "$local_ip" "$location_name"; then
			log_message "INFO" "${location_name:-SYSTEM}" "Ping check: 1/1 internal IP responded (100% success)"
			return 0
		else
			handle_error "WARNING" "${location_name:-SYSTEM}" "Ping check: 0/1 internal IP responded (0% success)"
			return 1
		fi
	fi

	# Ping all IPs sequentially
	for internal_ip in "${internal_ips_array[@]}"; do
		# Skip empty IPs
		if [[ -z "$internal_ip" ]]; then
			continue
		fi

		if check_ping_connectivity "$internal_ip" "$local_ip" "$location_name"; then
			((ping_success_count++))
		fi
	done

	# Calculate success threshold: ceil(PING_SUCCESS_THRESHOLD * count) using awk
	local threshold
	threshold=$(awk "BEGIN {print int(($ping_total_count * $PING_SUCCESS_THRESHOLD) + $PING_CEIL_ADJUSTMENT)}")

	# Calculate percentage for logging
	local success_percent=0
	if [[ $ping_total_count -gt 0 ]]; then
		success_percent=$(awk "BEGIN {printf \"%.0f\", ($ping_success_count * 100) / $ping_total_count}")
	fi

	# Check if threshold met
	if [[ $ping_success_count -ge $threshold ]]; then
		log_message "INFO" "${location_name:-SYSTEM}" "Ping check: $ping_success_count/$ping_total_count internal IPs responded (${success_percent}% >= 30% threshold)"
		return 0
	else
		handle_error "WARNING" "${location_name:-SYSTEM}" "Ping check: $ping_success_count/$ping_total_count internal IPs responded (${success_percent}% < 30% threshold)"
		return 1
	fi
}

# Check ping connectivity if enabled
#
# Performs ping check if enabled, regardless of VPN status.
# Used to verify end-to-end connectivity or diagnose issues.
# Supports both single IP (legacy) and multiple IPs (array).
#
# Arguments:
#   $1: SA existence status (1 = SA exists, 0 = SA does not exist)
#   $2: Ping target IP address or array (internal IP(s) if provided, otherwise external IP)
#   $3: Local IP address (for source IP, optional)
#   $4: Location name (optional, used for logging)
#
# Returns:
#   0: Always succeeds (ping check is informational)
#
# Side effects:
#   - Logs warning/debug messages about ping results
#
# Note:
#   The provided IP should be the internal IP if available, falling back to external IP
#   If $2 contains spaces (multiple IPs), calls check_ping_multiple_ips()
#   SA existence status should be determined by the caller to ensure accurate messages
check_ping_if_enabled() {
	local sa_exists="$1"
	local ping_target="$2"
	local local_ip_param="${3:-}"
	local location_name="${4:-}"

	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	local local_ip="${local_ip_param:-$(get_local_ip_for_ping)}"

	if [[ "$ping_target" =~ [[:space:]] ]]; then
		handle_ping_multiple_targets "$sa_exists" "$ping_target" "$local_ip" "$location_name"
		return 0
	fi

	handle_ping_single_target "$sa_exists" "$ping_target" "$local_ip" "$location_name"
	return 0
}

# Handle ping checks when multiple targets are supplied (space-delimited list)
#
# Processes ping checks for multiple target IPs (space-delimited string).
# Handles both cases where SA exists and where it doesn't, logging appropriate
# messages based on connectivity results.
#
# Arguments:
#   $1: SA existence status (1 = SA exists, 0 = SA does not exist)
#   $2: Space-delimited list of ping target IP addresses
#   $3: Local IP address (for source IP, optional)
#   $4: Location name (optional, used for logging)
#
# Returns:
#   0: Always succeeds (function logs results but doesn't affect return code)
#
# Side effects:
#   - Logs INFO messages when ping succeeds and SA exists
#   - Logs WARNING messages when connectivity issues are detected
#
# Note:
#   This function is called by check_ping_if_enabled() when multiple targets
#   are detected (space-delimited string). Uses check_ping_multiple_ips() for
#   actual ping execution.
handle_ping_multiple_targets() {
	local sa_exists="$1"
	local ping_target="$2"
	local local_ip="$3"
	local location_name="$4"

	if [[ $sa_exists -ne 1 ]]; then
		if check_ping_multiple_ips "$ping_target" "$local_ip" "$location_name"; then
			local first_ip
			first_ip=$(echo "$ping_target" | awk '{print $1}')
			local route_msg
			route_msg=$(build_route_message "$first_ip" "$local_ip")
			handle_error "WARNING" "${location_name:-SYSTEM}" "VPN tunnel is down (no SA found), but connectivity exists via alternative route${route_msg}"
		fi
		return
	fi

	if check_ping_multiple_ips "$ping_target" "$local_ip" "$location_name"; then
		log_message "INFO" "${location_name:-SYSTEM}" "VPN connectivity verified: ping check passed for multiple internal IPs"
		return
	fi

	handle_error "WARNING" "${location_name:-SYSTEM}" "VPN SA exists but ping check failed for multiple internal IPs - tunnel may not be routing traffic"
}

# Handle ping checks for a single target
#
# Processes ping check for a single target IP address.
# Handles both cases where SA exists and where it doesn't, logging appropriate
# messages based on connectivity results.
#
# Arguments:
#   $1: SA existence status (1 = SA exists, 0 = SA does not exist)
#   $2: Ping target IP address
#   $3: Local IP address (for source IP, optional)
#   $4: Location name (optional, used for logging)
#
# Returns:
#   0: Always succeeds (function logs results but doesn't affect return code)
#
# Side effects:
#   - Logs INFO messages when ping succeeds and SA exists
#   - Logs WARNING messages when connectivity issues are detected
#
# Note:
#   This function is called by check_ping_if_enabled() when a single target
#   is detected. Uses check_ping_connectivity() for actual ping execution.
handle_ping_single_target() {
	local sa_exists="$1"
	local ping_target="$2"
	local local_ip="$3"
	local location_name="$4"

	if [[ $sa_exists -ne 1 ]]; then
		if check_ping_connectivity "$ping_target" "$local_ip" "$location_name"; then
			local route_msg
			route_msg=$(build_route_message "$ping_target" "$local_ip")
			handle_error "WARNING" "${location_name:-SYSTEM}" "VPN tunnel is down (no SA found), but connectivity exists via alternative route${route_msg}"
		fi
		return
	fi

	if check_ping_connectivity "$ping_target" "$local_ip" "$location_name"; then
		log_message "INFO" "${location_name:-SYSTEM}" "VPN connectivity verified: ping check passed for $ping_target"
		return
	fi

	handle_error "WARNING" "${location_name:-SYSTEM}" "VPN SA exists but ping check failed for $ping_target - tunnel may not be routing traffic"
}

# Check ping connectivity if enabled (optional check)
#
# Performs ping check if enabled. This is informational and doesn't affect
# the VPN status determination, but provides additional connectivity verification.
# Uses provided SA existence state to ensure accurate log messages.
#
# Arguments:
#   $1: Current VPN status (0 = failed, 1 = OK)
#   $2: External peer IP address (external/public IP of remote VPN gateway)
#   $3: Internal peer IP address (optional, used for ping checks, falls back to external if not provided)
#   $4: Location name (optional, used for logging)
#
# Returns:
#   0: Always returns 0 (doesn't affect VPN status)
#
# Side effects:
#   - Logs ping check results
#   - Derives SA existence from primary_check_passed (if primary_check_passed=1, SA exists; otherwise checks directly)
check_ping_optional() {
	local primary_check_passed="$1"
	local external_peer_ip="$2"
	local internal_peer_ip="${3:-}"
	local location_name="${4:-}"

	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Derive SA existence from primary_check_passed as single source of truth
	# CRITICAL: If primary_check_passed=1, SA MUST exist (fundamental invariant)
	local sa_exists=0
	if [[ "$primary_check_passed" == "1" ]] || [[ $primary_check_passed -eq 1 ]]; then
		# Primary check passed - SA exists (either from xfrm or ipsec fallback)
		sa_exists=1
	else
		# primary_check_passed=0 - check SA existence directly when needed
		if check_ipsec_phase2 "$external_peer_ip" 2>/dev/null; then
			sa_exists=1
		fi
	fi

	# Perform ping check if enabled (informational, doesn't affect primary_check_passed)
	# Use internal IP if provided, otherwise fall back to external IP
	local ping_ip="${internal_peer_ip:-$external_peer_ip}"
	# Pass SA existence status to check_ping_if_enabled for accurate messaging
	check_ping_if_enabled "$sa_exists" "$ping_ip" "" "$location_name"

	return 0
}
