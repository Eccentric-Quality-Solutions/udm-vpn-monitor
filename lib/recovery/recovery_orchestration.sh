#!/bin/bash
#
# Recovery orchestration functions for UDM VPN Monitor
# Coordinates recovery actions across xfrm and IPsec recovery methods
#
# Version: 0.7.0
#

# shellcheck source=lib/recovery/recovery_verification.sh
# shellcheck source=lib/recovery/recovery_state.sh
# shellcheck source=lib/recovery/xfrm_recovery.sh
# shellcheck source=lib/recovery/ipsec_recovery.sh
RECOVERY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${RECOVERY_DIR}/recovery_verification.sh" 2>/dev/null || true
source "${RECOVERY_DIR}/recovery_state.sh" 2>/dev/null || true
source "${RECOVERY_DIR}/xfrm_recovery.sh" 2>/dev/null || true
source "${RECOVERY_DIR}/ipsec_recovery.sh" 2>/dev/null || true

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
#   Stores full path to ip and ipsec commands to ensure reliable execution even when PATH is restricted
_check_recovery_command_availability() {
	declare -g _RECOVERY_IP_AVAILABLE=0
	declare -g _RECOVERY_IPSEC_AVAILABLE=0
	declare -g _RECOVERY_IP_PATH=""
	declare -g _RECOVERY_IPSEC_PATH=""

	if check_command_available "ip"; then
		_RECOVERY_IP_AVAILABLE=1
		# Get full path to ip command for reliable execution
		# get_command_path() checks standard system directories first (works in PATH-restricted cron/systemd)
		_RECOVERY_IP_PATH=$(get_command_path "ip" || true)
		# If get_command_path returns empty, fall back to command name
		if [[ -z "$_RECOVERY_IP_PATH" ]]; then
			_RECOVERY_IP_PATH="ip"
		fi
	fi

	if check_command_available "ipsec"; then
		_RECOVERY_IPSEC_AVAILABLE=1
		# Get full path to ipsec command for reliable execution
		# get_command_path() checks standard system directories first (works in PATH-restricted cron/systemd)
		_RECOVERY_IPSEC_PATH=$(get_command_path "ipsec" || true)
		# If get_command_path returns empty, fall back to command name
		if [[ -z "$_RECOVERY_IPSEC_PATH" ]]; then
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
	local external_peer_ip="${2:-}"
	local tier="${3:-2}"

	case "$strategy" in
	"xfrm")
		# Requires peer IP, xfrm recovery enabled, and ip command available
		[[ -n "$external_peer_ip" ]] &&
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

# Validate recovery tier parameter
#
# Validates that the tier parameter is a valid recovery tier value.
# Tier must be 2 (surgical cleanup) or 3 (full restart).
#
# Arguments:
#   $1: Tier level to validate
#
# Returns:
#   0: Tier is valid
#   1: Tier is invalid
#
# Note:
#   This is a helper function for select_recovery_strategy()
_validate_recovery_tier() {
	local tier="${1:-}"
	[[ "$tier" == "2" ]] || [[ "$tier" == "3" ]]
}

# Find applicable recovery strategy
#
# Searches through recovery strategies in priority order and returns the first
# applicable strategy entry based on peer IP, tier, and command availability.
#
# Arguments:
#   $1: Peer IP address (optional, required for per-connection recovery)
#   $2: Tier level (2 for surgical cleanup, 3 for full restart)
#
# Returns:
#   0: Applicable strategy found (strategy entry returned via stdout)
#   1: No applicable strategy found (empty string returned via stdout)
#
# Output (via stdout):
#   Strategy entry in format "name:command:impact" if found, empty string if not found
#
# Note:
#   This is a helper function for select_recovery_strategy()
#   Assumes _check_recovery_command_availability() has been called first
#   Strategies are evaluated in priority order: xfrm → ipsec_reload → ipsec_restart
_find_applicable_strategy() {
	local external_peer_ip="${1:-}"
	local tier="${2:-2}"

	# Define strategy lookup table (in priority order)
	# Format: "strategy_name:command:impact"
	# Priority: xfrm (highest) → ipsec_reload → ipsec_restart (lowest)
	# First applicable strategy in this order will be selected
	local -a strategies=(
		"xfrm:attempt_xfrm_recovery:per-connection"
		"ipsec_reload:ipsec reload:all-tunnels"
		"ipsec_restart:ipsec restart:all-tunnels"
	)

	# Iterate through strategies in priority order
	# Parse each strategy entry and check applicability
	# Return immediately when first applicable strategy is found
	local strategy_entry
	for strategy_entry in "${strategies[@]}"; do
		# Parse strategy entry: split by colon to extract name, command, and impact
		IFS=':' read -r strategy_name strategy_command strategy_impact <<<"$strategy_entry"

		# Check if this strategy is applicable given current conditions
		# _is_strategy_applicable() checks: peer IP, tier, config, and command availability
		if _is_strategy_applicable "$strategy_name" "$external_peer_ip" "$tier"; then
			# Strategy is applicable - return full strategy entry
			echo "$strategy_entry"
			return 0
		fi
		# Strategy not applicable - continue to next strategy in priority order
	done

	# No strategy available
	echo ""
	return 1
}

# Select recovery strategy based on peer IP and tier
#
# Centralizes recovery strategy selection logic, determining the best recovery
# approach based on configuration, peer IP availability, and tier level.
# Returns recovery plan information via nameref associative array.
#
# Arguments:
#   $1: Peer IP address (optional, required for per-connection recovery)
#   $2: Tier level (2 for surgical cleanup, 3 for full restart)
#   $3: Nameref to associative array to store strategy information (required)
#
# Returns:
#   0: Strategy selected successfully
#   1: Invalid tier or no strategy available
#
# Output (via nameref associative array):
#   result["strategy"]: Strategy name ("xfrm", "ipsec_reload", "ipsec_restart", or "unavailable")
#   result["command"]: Command to execute (function name or command string)
#   result["impact"]: Impact description ("per-connection" or "all-tunnels")
#   result["available"]: Whether recovery is available (1) or not (0)
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
#   5. Select first applicable strategy and set nameref array values
#   6. If no strategy applicable, set result["strategy"]="unavailable" and return error
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
#   - Uses nameref associative array for return values (improves testability)
#   - Returns immediately after finding first applicable strategy
#
# Examples:
#   # Tier 2 recovery with peer IP (prefers xfrm)
#   declare -A recovery_info
#   select_recovery_strategy "203.0.113.1" 2 "recovery_info"
#   # Result: recovery_info["strategy"]="xfrm", recovery_info["command"]="attempt_xfrm_recovery"
#   #         recovery_info["impact"]="per-connection", recovery_info["available"]=1
#
#   # Tier 2 recovery without peer IP (uses ipsec_reload)
#   declare -A recovery_info
#   select_recovery_strategy "" 2 "recovery_info"
#   # Result: recovery_info["strategy"]="ipsec_reload", recovery_info["command"]="ipsec reload"
#   #         recovery_info["impact"]="all-tunnels", recovery_info["available"]=1
#
#   # Tier 3 recovery (uses ipsec_restart)
#   declare -A recovery_info
#   select_recovery_strategy "" 3 "recovery_info"
#   # Result: recovery_info["strategy"]="ipsec_restart", recovery_info["command"]="ipsec restart"
#   #         recovery_info["impact"]="all-tunnels", recovery_info["available"]=1
#
#   # Invalid tier (returns error)
#   declare -A recovery_info
#   select_recovery_strategy "203.0.113.1" 1 "recovery_info"
#   # Result: Error logged, returns 1, recovery_info["available"]=0
#
#   # No strategies available (missing commands)
#   declare -A recovery_info
#   select_recovery_strategy "203.0.113.1" 2 "recovery_info"
#   # Result: recovery_info["strategy"]="unavailable", returns 1, recovery_info["available"]=0
#
# Note:
#   Requires ENABLE_XFRM_RECOVERY configuration variable
#   Checks for command availability (ip, ipsec) before selecting strategy
#   Uses helper function _is_strategy_applicable() to evaluate strategy conditions
#   Command availability is checked once per function call (cached in global variables)
#   Uses nameref associative array for return values (improves testability, avoids global state)
select_recovery_strategy() {
	local external_peer_ip="${1:-}"
	local tier="${2:-2}"
	local result_ref_name="${3:-}"

	# Validate nameref parameter (must be done before declaring nameref)
	if [[ -z "$result_ref_name" ]]; then
		handle_error "ERROR" "SYSTEM" "select_recovery_strategy: nameref parameter is required" 0
		return 1
	fi

	local -n result="$result_ref_name"

	# Initialize return variables in nameref array
	result["strategy"]=""
	result["command"]=""
	result["impact"]=""
	result["available"]=0

	# Step 1: Validate tier parameter
	# Tier must be 2 (surgical cleanup) or 3 (full restart)
	# Invalid tier is a critical error - fail immediately without checking strategies
	if ! _validate_recovery_tier "$tier"; then
		handle_error "ERROR" "SYSTEM" "Invalid tier: $tier (must be 2 or 3)" 0
		return 1
	fi

	# Step 2: Check command availability
	# This populates global variables _RECOVERY_IP_AVAILABLE and _RECOVERY_IPSEC_AVAILABLE
	# These are cached for use by _is_strategy_applicable() to avoid repeated checks
	_check_recovery_command_availability

	# Step 3: Find applicable strategy
	# This searches through strategies in priority order and returns the first applicable one
	local strategy_entry
	strategy_entry=$(_find_applicable_strategy "$external_peer_ip" "$tier")

	# Step 4: Set nameref array values based on selected strategy
	if [[ -n "$strategy_entry" ]]; then
		# Strategy found - parse strategy entry to extract name, command, and impact
		IFS=':' read -r strategy_name strategy_command strategy_impact <<<"$strategy_entry"

		# Set nameref array values and return success
		# These values are used by calling code to execute the selected strategy
		result["strategy"]="$strategy_name"
		result["command"]="$strategy_command"
		result["impact"]="$strategy_impact"
		result["available"]=1
		return 0
	fi

	# Step 5: No strategy available (fallback case)
	# This occurs when:
	#   - No commands available (ip and ipsec both missing)
	#   - xfrm disabled and no peer IP provided
	#   - Other conditions prevent all strategies
	# Set array values to indicate unavailability and return error
	result["strategy"]="unavailable"
	result["command"]=""
	result["impact"]=""
	result["available"]=0
	return 1
}

# Execute xfrm recovery with fallback support
#
# Attempts xfrm-based per-connection recovery and handles fallback to
# all-tunnels recovery if xfrm recovery fails. This centralizes the
# duplicate fallback logic used in both surgical_cleanup() and full_restart().
#
# Arguments:
#   $1: Peer IP address
#   $2: Location name
#   $3: Tier level (2 for surgical cleanup, 3 for full restart)
#   $4: Nameref to associative array containing recovery strategy information (will be updated on fallback)
#   $5: Log prefix (optional, e.g., "Tier 3: " for full_restart)
#   $6: Fallback action description (e.g., "ipsec reload" or "full restart")
#
# Returns:
#   0: xfrm recovery succeeded
#   1: xfrm recovery failed and fallback strategy selected (caller should continue loop)
#   2: xfrm recovery failed and no fallback strategy available (caller should return error)
#
# Output (via nameref array):
#   result["strategy"]: Updated to fallback strategy if xfrm fails
#   result["command"]: Updated to fallback command if xfrm fails
#   result["impact"]: Updated to fallback impact if xfrm fails
#
# Note:
#   This is a helper function for surgical_cleanup() and full_restart()
#   Updates nameref array with fallback strategy information from select_recovery_strategy()
_execute_xfrm_recovery_with_fallback() {
	local external_peer_ip="$1"
	local location_name="$2"
	local tier="$3"
	local result_ref_name="$4"
	local -n result="$result_ref_name"
	local log_prefix="${5:-}"
	local fallback_action="${6:-ipsec recovery}"

	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "")
	log_message "INFO" "$location_name" "${log_prefix}Attempting xfrm-based per-connection recovery for $ip_display"

	# Store recovery method before attempting recovery
	# For Tier 3, only store if external_peer_ip is provided (full_restart allows empty external_peer_ip)
	if [[ "$tier" == "3" ]]; then
		if [[ -n "$external_peer_ip" ]]; then
			store_recovery_method "$location_name" "$external_peer_ip" "xfrm"
		fi
	else
		# Tier 2 always stores recovery method
		store_recovery_method "$location_name" "$external_peer_ip" "xfrm"
	fi

	# Attempt xfrm recovery
	if attempt_xfrm_recovery "$external_peer_ip" "$location_name"; then
		# xfrm recovery succeeded
		if [[ "$tier" == "3" ]]; then
			log_message "INFO" "$location_name" "${log_prefix}xfrm-based per-connection recovery successful for $ip_display"
			# Record restart for rate limiting (even though it's per-connection)
			record_restart
		else
			log_message "INFO" "$location_name" "xfrm-based recovery completed successfully for $ip_display"
			log_message "INFO" "$location_name" "Surgical cleanup completed for $ip_display (via xfrm)"
		fi
		return 0
	else
		# xfrm recovery failed - fall back to all-tunnels recovery
		handle_error "WARNING" "$location_name" "${log_prefix}xfrm-based recovery failed for $ip_display, falling back to $fallback_action"
		# Re-select strategy for fallback (without peer IP to force all-tunnels recovery)
		if ! select_recovery_strategy "" "$tier" "$result_ref_name"; then
			# Fallback strategy not available
			handle_error "ERROR" "$location_name" "${log_prefix}xfrm recovery failed and no fallback strategy available for $ip_display" 0
			return 2
		fi
		# Return 1 to indicate fallback strategy selected (caller should continue loop)
		return 1
	fi
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
	local external_peer_ip="$1"
	local location_name="$2"

	# Validate required parameters
	if [[ -z "$external_peer_ip" ]] || [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "surgical_cleanup: external_peer_ip and location_name are required" 0
		return 1
	fi

	local peer_display
	peer_display=$(format_peer_display "$external_peer_ip")
	# Note: surgical_cleanup doesn't have access to internal_peer_ip, so we only show external IP
	log_message "INFO" "$location_name" "Attempting surgical SA cleanup for ($peer_display)"

	# Select recovery strategy
	declare -A recovery_info
	if ! select_recovery_strategy "$external_peer_ip" 2 "recovery_info"; then
		# No recovery strategy available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		handle_error "WARNING" "${location_name:-SYSTEM}" "No recovery strategy available for Tier 2 recovery"
		return 1
	fi

	# Execute selected strategy with fallback support
	local strategy_executed=0
	local recovery_succeeded=0
	local max_attempts=3
	local attempt=0
	while [[ $strategy_executed -eq 0 ]] && [[ $attempt -lt $max_attempts ]]; do
		((++attempt))
		case "${recovery_info[strategy]}" in
		"xfrm")
			# Call helper and capture return code (not stdout - function uses return, not echo)
			_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" 2 "recovery_info" "" "ipsec reload (affects all tunnels)"
			local xfrm_result=$?
			case $xfrm_result in
			0)
				# xfrm recovery succeeded
				return 0
				;;
			1)
				# Fallback strategy selected - continue loop to execute it
				continue
				;;
			2)
				# No fallback strategy available
				return 1
				;;
			*)
				# Unexpected return code - log error and fail immediately
				# Without this, loop would continue until max_attempts, wasting time
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "")
				handle_error "ERROR" "$location_name" "Unexpected return code from xfrm recovery: $xfrm_result for $ip_display (expected 0, 1, or 2)" 0
				return 1
				;;
			esac
			;;
		"ipsec_reload")
			recovery_succeeded=0
			if execute_ipsec_reload "$external_peer_ip" "$location_name"; then
				recovery_succeeded=1
			fi
			strategy_executed=1
			;;
		*)
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "")
			handle_error "ERROR" "$location_name" "Unknown recovery strategy: ${recovery_info[strategy]} for $ip_display" 0
			return 1
			;;
		esac
	done
	# Check if we exited the loop without executing a strategy (hit max attempts)
	if [[ $strategy_executed -eq 0 ]]; then
		local ip_display
		ip_display=$(format_peer_ip_display "$external_peer_ip" "")
		handle_error "ERROR" "$location_name" "Recovery failed after $max_attempts attempts for $ip_display" 0
		return 1
	fi

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
#   5. Records restart timestamp for rate limiting (record_restart)
#
# Side effects:
#   - If xfrm recovery succeeds: Only affects the specified peer's tunnel
#   - If xfrm recovery fails or disabled: Affects ALL IPsec tunnels
#   - Temporarily disrupts VPN tunnels (scope depends on recovery method)
#   - Records restart timestamp for rate limiting (prevents restart loops via MIN_RESTART_INTERVAL_SECONDS)
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
#   Requires check_rate_limit, record_restart, log_message, LOG_FILE,
#   warn_if_missing, handle_error_or_exit_fake_mode, attempt_xfrm_recovery to be set
#   Uses PIPESTATUS to capture command exit code (not tee exit code)
#   Command output is both displayed and appended to log file (for full restart)
full_restart() {
	local external_peer_ip="${1:-}"
	local location_name="$2"

	if ! check_rate_limit "$location_name"; then
		# check_rate_limit() already logs detailed warning with reset time, countdown, and restart list
		# Note: full_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
		handle_error "ERROR" "$location_name" "Rate limit exceeded, skipping Tier 3 recovery (see previous warning for reset time and details)" 0
		return 1
	fi

	# Select recovery strategy
	declare -A recovery_info
	if ! select_recovery_strategy "$external_peer_ip" 3 "recovery_info"; then
		# No recovery strategy available
		warn_if_missing "ip"
		warn_if_missing "ipsec"
		handle_error_or_exit_fake_mode "$location_name" "No recovery strategy available for Tier 3 recovery"
		return 1
	fi

	# Execute selected strategy with fallback support
	local strategy_executed=0
	local max_attempts=3
	local attempt=0
	while [[ $strategy_executed -eq 0 ]] && [[ $attempt -lt $max_attempts ]]; do
		((++attempt))
		case "${recovery_info[strategy]}" in
		"xfrm")
			# Call helper and capture return code (not stdout - function uses return, not echo)
			_execute_xfrm_recovery_with_fallback "$external_peer_ip" "$location_name" 3 "recovery_info" "Tier 3: " "full restart"
			local xfrm_result=$?
			case $xfrm_result in
			0)
				# xfrm recovery succeeded
				return 0
				;;
			1)
				# Fallback strategy selected - continue loop to execute it
				continue
				;;
			2)
				# No fallback strategy available
				return 1
				;;
			*)
				# Unexpected return code - log error and fail immediately
				# Without this, loop would continue until max_attempts, wasting time
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "")
				handle_error "ERROR" "$location_name" "Unexpected return code from xfrm recovery: $xfrm_result for $ip_display (expected 0, 1, or 2)" 0
				return 1
				;;
			esac
			;;
		"ipsec_restart")
			# Record restart before executing
			record_restart
			if execute_ipsec_restart "$external_peer_ip" "$location_name"; then
				strategy_executed=1
			else
				return 1
			fi
			;;
		*)
			local ip_display
			ip_display=$(format_peer_ip_display "$external_peer_ip" "")
			handle_error "ERROR" "$location_name" "Unknown recovery strategy: ${recovery_info[strategy]} for $ip_display" 0
			return 1
			;;
		esac
	done
	# Check if we exited the loop without executing a strategy (hit max attempts)
	if [[ $strategy_executed -eq 0 ]]; then
		local ip_display
		ip_display=$(format_peer_ip_display "$external_peer_ip" "")
		handle_error "ERROR" "$location_name" "Recovery failed after $max_attempts attempts for $ip_display" 0
		return 1
	fi

	# Note: full_restart doesn't have access to internal_peer_ip, and location_name is already in log prefix
	log_message "INFO" "$location_name" "Full IPsec restart completed"
	return 0
}

# Check VPN status for a location
#
# Handles network partition checks and VPN status detection for a location.
# Returns early if network is partitioned to avoid unnecessary work.
#
# Arguments:
#   $1: Location name
#   $2: External peer IP address
#   $3: Internal peer IPs (optional, space-separated)
#
# Returns:
#   0: VPN is healthy
#   1: VPN check failed
#   2: Network partition detected (early exit, no VPN check performed)
#
# Side effects:
#   - Updates network partition state if partition cleared
#   - Logs partition state changes
check_vpn_status_for_location() {
	local location_name="$1"
	local external_peer_ip="$2"
	local internal_peer_ips="${3:-}"

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
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")
				log_message "INFO" "$location_name" "Skipping VPN checks for $ip_display - network partition detected"
				# Log summary if hour has elapsed (tracks statistics for all three checks)
				log_network_partition_summary_if_due
				return 2
			else
				# Network partition cleared - update state and continue with VPN checks
				# We know partition_state was 1 (from line 540), so we can use that directly
				local ip_display
				ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")
				log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $ip_display"
				set_network_partition_state 0
				# Continue with VPN checks below
				# Log summary if hour has elapsed (tracks statistics for all three checks)
				log_network_partition_summary_if_due
			fi
		fi
	fi

	# Check VPN status (uses external IP for xfrm, internal IPs for ping)
	# Pass location name for state file naming
	if check_vpn_status "$external_peer_ip" "$internal_peer_ips" "$location_name"; then
		return 0
	else
		# VPN check failed - return 1 (partition check happens after failure count increment)
		return 1
	fi
}

# Update location state based on VPN status
#
# Handles state file updates for both healthy and failed VPN cases.
# For healthy VPNs: handles recovery logging, periodic status updates, and cleanup.
# For failed VPNs: increments failure count, checks network partition, and handles failure type.
#
# Arguments:
#   $1: Location name
#   $2: External peer IP address
#   $3: Status ("healthy" or "failed")
#   $4: Internal peer IPs (optional, space-separated)
#
# Returns:
#   0: State updated successfully
#   2: Network partition detected (only for "failed" status, after failure count increment)
#
# Side effects:
#   - Updates failure count, recovery method, failure type files
#   - Logs recovery messages and periodic status updates
#   - Cleans up stale state files
#   - Updates network partition state
update_location_state() {
	local location_name="$1"
	local external_peer_ip="$2"
	local status="$3"
	local internal_peer_ips="${4:-}"
	local failure_count

	# Format IP display once for reuse throughout function
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")

	if [[ "$status" == "healthy" ]]; then
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

		if [[ "$failure_count" -gt 0 ]]; then
			# Actual failures occurred - log recovery message
			# Check if a recovery method was used (stored when recovery was attempted)
			local recovery_method=""
			recovery_method=$(get_recovery_method "$location_name" "$external_peer_ip")
			local recovery_method_display=""
			if [[ -n "$recovery_method" ]]; then
				recovery_method_display=$(format_recovery_method "$recovery_method")
			fi

			# Log recovery success with method if available
			if [[ -n "$recovery_method_display" ]]; then
				log_message "INFO" "$location_name" "VPN restored for $ip_display after $failure_count failures (recovery method: $recovery_method_display)"
			else
				log_message "INFO" "$location_name" "VPN recovered for $ip_display after $failure_count failures"
			fi
			reset_failure_count "$location_name" "$external_peer_ip"

			# Clear failure type file on recovery
			# Use abstraction layer to ensure consistent path format
			if [[ -n "$failure_type_file" ]] && [[ -f "$failure_type_file" ]]; then
				rm -f "$failure_type_file" 2>/dev/null || true
			fi

			# Clear recovery method after logging (prevents stale information)
			if [[ -n "$recovery_method" ]]; then
				clear_recovery_method "$location_name" "$external_peer_ip"
			fi
		elif [[ $had_failure_type -eq 1 ]]; then
			# Failure type file exists but no actual failures (false positive case)
			# Clear the stale failure_type file silently without logging recovery
			# This prevents false positive recovery messages when VPN was already healthy
			if [[ -n "$failure_type_file" ]] && [[ -f "$failure_type_file" ]]; then
				rm -f "$failure_type_file" 2>/dev/null || true
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
					time_diff=$(calculate_duration "$last_status_log" "$current_time" 2>/dev/null || echo "0")
					if [[ $time_diff -ge $status_log_interval ]] || [[ "$last_status_log" -eq 0 ]]; then
						log_message "INFO" "$location_name" "VPN check OK for $ip_display"
						set_peer_state_non_critical "$location_name" "$external_peer_ip" "last_status_log" "$current_time"
					fi
				fi
			fi
		fi
	else
		# VPN check failed - increment failure count first
		# This ensures failure count increments even when recovery is skipped due to network partition
		failure_count=$(increment_failure "$location_name" "$external_peer_ip")

		# Check network partition - always re-check (don't rely on cached state)
		# This ensures we detect partition state changes (e.g., network just recovered)
		# Note: This check happens AFTER incrementing failure count to match original behavior
		if [[ "${ENABLE_NETWORK_PARTITION_CHECK:-1}" -eq 1 ]]; then
			# Use same parameters as validate_monitor_state for consistency
			local dns_server="${NETWORK_PARTITION_DNS_SERVER:-8.8.8.8}"
			local dns_hostname="${NETWORK_PARTITION_DNS_HOSTNAME:-google.com}"
			local dns_timeout="${NETWORK_PARTITION_DNS_TIMEOUT:-2}"
			local interfaces="${NETWORK_PARTITION_INTERFACES:-br0,eth0}"
			if ! check_network_partition "$dns_server" "$dns_hostname" "$dns_timeout" "$interfaces"; then
				# Network is partitioned - update state and indicate partition detected
				local prev_partition_state
				prev_partition_state=$(get_network_partition_state)
				set_network_partition_state 1
				if [[ "$prev_partition_state" -eq 0 ]]; then
					log_message "WARNING" "$location_name" "Network partition detected - skipping VPN recovery for $ip_display until connectivity restored"
				else
					log_message "INFO" "$location_name" "Skipping VPN recovery for $ip_display - network is still partitioned (failure count: $failure_count)"
				fi
				# Return special code to indicate partition detected (after failure count increment)
				return 2
			else
				# Network is healthy - check if it was previously partitioned
				local prev_partition_state
				prev_partition_state=$(get_network_partition_state)
				if [[ "$prev_partition_state" -eq 1 ]]; then
					log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $ip_display"
					set_network_partition_state 0
				fi
			fi
		fi

		# VPN check failed - handle failure type
		local failure_type="unknown"
		if command -v get_failure_type >/dev/null 2>&1; then
			failure_type=$(get_failure_type "$location_name" "$external_peer_ip" 2>/dev/null || echo "unknown")
		fi
		local failure_type_display=""
		case "$failure_type" in
		"tunnel_down") failure_type_display=" (tunnel down)" ;;
		"routing_issue") failure_type_display=" (routing issue)" ;;
		esac
		handle_error "WARNING" "$location_name" "VPN check failed for $ip_display (failure count: $failure_count)$failure_type_display"
	fi
	return 0
}

# Determine and execute recovery action based on failure count
#
# Handles recovery tier selection and execution based on failure count thresholds.
# Implements safety checks to prevent recovery escalation when detection is unreliable.
#
# Arguments:
#   $1: Location name
#   $2: External peer IP address
#   $3: Failure count
#   $4: Internal peer IPs (optional, space-separated)
#
# Returns:
#   0: Recovery attempted or no recovery needed
#   1: VPN check failed but no recovery attempted (below threshold)
#
# Side effects:
#   - Executes recovery actions (Tier 2 or Tier 3)
#   - Logs recovery attempts and results
#   - May reset failure count on successful Tier 3 recovery
determine_recovery_action() {
	local location_name="$1"
	local external_peer_ip="$2"
	local failure_count="$3"
	local internal_peer_ips="${4:-}"

	# Format IP display once for reuse throughout function
	local ip_display
	ip_display=$(format_peer_ip_display "$external_peer_ip" "$internal_peer_ips")

	# Get failure type for safety checks and logging
	local failure_type="unknown"
	if command -v get_failure_type >/dev/null 2>&1; then
		failure_type=$(get_failure_type "$location_name" "$external_peer_ip" 2>/dev/null || echo "unknown")
	fi
	local failure_type_display=""
	case "$failure_type" in
	"tunnel_down") failure_type_display=" (tunnel down)" ;;
	"routing_issue") failure_type_display=" (routing issue)" ;;
	esac

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
			handle_error "ERROR" "$location_name" "Detection unreliable: Both 'ip' and 'ipsec' commands unavailable - skipping recovery escalation for $ip_display to prevent false recovery actions" 0
			# Still log the failure but don't escalate recovery
			if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
				log_message "INFO" "$location_name" "Tier 1: Logging VPN failure for $ip_display$failure_type_display (recovery skipped - detection unreliable)"
			fi
			return 0
		fi
	fi

	# Tier 1: Logging
	if [[ "$failure_count" -ge "$TIER1_THRESHOLD" ]]; then
		log_message "INFO" "$location_name" "Tier 1: Logging VPN failure for $ip_display$failure_type_display"
	fi

	# Check if recovery should be coordinated (system-wide failure mode)
	# During system-wide failures, only the coordinator location should attempt recovery
	if command -v should_location_attempt_recovery >/dev/null 2>&1; then
		if ! should_location_attempt_recovery "$location_name"; then
			# System-wide failure detected and another location is coordinating recovery
			# Log that this location is skipping recovery to avoid cascades
			if [[ "$failure_count" -ge "$TIER2_THRESHOLD" ]]; then
				log_message "INFO" "$location_name" "Skipping recovery for $location_name ($ip_display) - recovery coordinated by another location during system-wide failure"
			fi
			return 0
		fi
	fi

	# Tier 2: Surgical cleanup
	local recovery_attempted=0
	if [[ "$failure_count" -ge "$TIER2_THRESHOLD" ]] && [[ "$failure_count" -lt "$TIER3_THRESHOLD" ]]; then
		recovery_attempted=1
		if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
			declare -A recovery_info
			if ! select_recovery_strategy "$external_peer_ip" 2 "recovery_info"; then
				# No recovery strategy available - log Tier 2 reached but no strategy available
				log_message "WARNING" "$location_name" "Tier 2: Recovery threshold reached for $ip_display but no recovery strategy available (skipped in fake mode)"
			elif [[ "${recovery_info[strategy]}" == "xfrm" ]]; then
				log_message "INFO" "$location_name" "Tier 2: Would attempt xfrm-based per-connection recovery for $ip_display (skipped in fake mode)"
			else
				# Log the specific command that would be executed
				local command_display="${recovery_info[command]:-ipsec reload}"
				log_message "INFO" "$location_name" "Tier 2: Would attempt surgical SA cleanup for $ip_display via $command_display (skipped in fake mode)"
			fi
		else
			log_message "INFO" "$location_name" "Tier 2: Attempting surgical SA cleanup for $ip_display"
			surgical_cleanup "$external_peer_ip" "$location_name"
		fi
	fi

	# Tier 3: Full restart
	if [[ "$failure_count" -ge "$TIER3_THRESHOLD" ]]; then
		recovery_attempted=1
		if [[ "${NO_ESCALATE:-0}" -eq 1 ]]; then
			if ! check_rate_limit "$location_name"; then
				# check_rate_limit() already logs "Rate limit exceeded" via handle_error
				# location_name should always be provided in production code
				log_message "INFO" "${location_name:-SYSTEM}" "Tier 3: Would attempt IPsec restart (skipped in fake mode, rate limit would prevent)"
			else
				# In fake mode, still record restart for cleanup purposes (prevents restart count file from growing)
				# but skip the actual restart command
				record_restart
				declare -A recovery_info
				if ! select_recovery_strategy "$external_peer_ip" 3 "recovery_info"; then
					# No recovery strategy available - log Tier 3 reached but no strategy available
					log_message "WARNING" "$location_name" "Tier 3: Recovery threshold reached for $ip_display but no recovery strategy available (skipped in fake mode)"
				elif [[ "${recovery_info[strategy]}" == "xfrm" ]]; then
					log_message "INFO" "$location_name" "Tier 3: Would attempt xfrm-based per-connection recovery for $ip_display (skipped in fake mode)"
				else
					log_message "INFO" "$location_name" "Tier 3: Would attempt full IPsec restart (affects all tunnels, skipped in fake mode)"
				fi
			fi
		else
			log_message "INFO" "$location_name" "Tier 3: Attempting IPsec restart for $ip_display"
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
}

# Monitor VPN status for a location and handle recovery
#
# Orchestrates VPN monitoring for a location by coordinating detection, state management,
# and recovery actions. This is the main entry point for location-based monitoring.
#
# Arguments:
#   $1: Location name
#   $2: External peer IP address
#   $3: Internal peer IPs (optional, space-separated)
#
# Returns:
#   0: Monitoring completed successfully (VPN healthy, recovery attempted, or network partitioned)
#   1: VPN check failed but no recovery attempted (below threshold)
#
# Side effects:
#   - Updates state files for location/peer
#   - Executes recovery actions if thresholds exceeded
#   - Logs status updates and recovery attempts
monitor_location() {
	local location_name="$1"
	local external_peer_ip="$2"
	local internal_peer_ips="${3:-}"
	local failure_count

	# Check VPN status (handles network partition checks before VPN check)
	check_vpn_status_for_location "$location_name" "$external_peer_ip" "$internal_peer_ips"
	local vpn_status_rc=$?

	# Handle network partition early exit (before VPN check)
	if [[ $vpn_status_rc -eq 2 ]]; then
		# Network partition detected - skip VPN checks entirely
		return 0
	fi

	if [[ $vpn_status_rc -eq 0 ]]; then
		# VPN is healthy
		update_location_state "$location_name" "$external_peer_ip" "healthy" "$internal_peer_ips"
		return 0
	else
		# VPN check failed - update state (increments failure count and checks partition)
		update_location_state "$location_name" "$external_peer_ip" "failed" "$internal_peer_ips"
		local state_update_rc=$?

		# Handle network partition detected after failure count increment
		if [[ $state_update_rc -eq 2 ]]; then
			# Network partition detected - skip recovery
			return 0
		fi

		# Continue with recovery
		failure_count=$(get_failure_count "$location_name" "$external_peer_ip")
		determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count" "$internal_peer_ips"
		local recovery_rc=$?
		return $recovery_rc
	fi
}
