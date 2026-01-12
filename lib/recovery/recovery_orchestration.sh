#!/bin/bash
#
# Recovery orchestration functions for UDM VPN Monitor
# Coordinates recovery actions across xfrm and IPsec recovery methods
#
# Version: 0.6.0
#

# Source recovery modules
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
			# Use || true to prevent command substitution from failing if get_command_path returns non-zero
			_RECOVERY_IPSEC_PATH=$(get_command_path "ipsec" || true)
			# If get_command_path returns empty string, fall back to command name
			if [[ -z "$_RECOVERY_IPSEC_PATH" ]]; then
				_RECOVERY_IPSEC_PATH="ipsec"
			fi
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
			if execute_ipsec_reload "$peer_ip" "$location_name"; then
				recovery_succeeded=1
			else
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
			# Record restart before executing
			record_restart
			if execute_ipsec_restart "$peer_ip" "$location_name"; then
				set_cooldown "$COOLDOWN_MINUTES"
				strategy_executed=1
			else
				return 1
			fi
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
				log_message "INFO" "$location_name" "Skipping VPN checks for $location_name ($external_peer_ip) - network partition detected"
				return 2
			else
				# Network partition cleared - update state and continue with VPN checks
				# We know partition_state was 1 (from line 540), so we can use that directly
				log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $location_name ($external_peer_ip)"
				set_network_partition_state 0
				# Continue with VPN checks below
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
	local failure_count

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
				log_message "INFO" "$location_name" "${VPN_NAME:-VPN} restored for $location_name ($external_peer_ip) after $failure_count failures (recovery method: $recovery_method_display)"
			else
				log_message "INFO" "$location_name" "${VPN_NAME:-VPN} recovered for $location_name ($external_peer_ip) after $failure_count failures"
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
					log_message "WARNING" "$location_name" "Network partition detected - skipping VPN recovery for $location_name ($external_peer_ip) until connectivity restored"
				else
					log_message "INFO" "$location_name" "Skipping VPN recovery for $location_name ($external_peer_ip) - network is still partitioned (failure count: $failure_count)"
				fi
				# Return special code to indicate partition detected (after failure count increment)
				return 2
			else
				# Network is healthy - check if it was previously partitioned
				local prev_partition_state
				prev_partition_state=$(get_network_partition_state)
				if [[ "$prev_partition_state" -eq 1 ]]; then
					log_message "INFO" "$location_name" "Network connectivity restored - resuming VPN monitoring for $location_name ($external_peer_ip)"
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
		handle_error "WARNING" "$location_name" "${VPN_NAME:-VPN} check failed for $location_name ($external_peer_ip) (failure count: $failure_count)$failure_type_display"
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
		update_location_state "$location_name" "$external_peer_ip" "healthy"
		return 0
	else
		# VPN check failed - update state (increments failure count and checks partition)
		update_location_state "$location_name" "$external_peer_ip" "failed"
		local state_update_rc=$?

		# Handle network partition detected after failure count increment
		if [[ $state_update_rc -eq 2 ]]; then
			# Network partition detected - skip recovery
			return 0
		fi

		# Continue with recovery
		failure_count=$(get_failure_count "$location_name" "$external_peer_ip")
		determine_recovery_action "$location_name" "$external_peer_ip" "$failure_count"
		return $?
	fi
}
