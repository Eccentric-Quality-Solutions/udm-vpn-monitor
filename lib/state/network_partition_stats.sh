#!/bin/bash
#
# Network partition check statistics tracking
# Handles success/failure counting and hourly summary logging for network partition checks
#
# Version: 0.8.3
#

# Track network partition check result
#
# Increments the appropriate success or failure counter for a specific check type.
# Used to track statistics for DNS resolution, default route, and interface state checks.
#
# Arguments:
#   $1: Check type ("dns", "route", or "interface")
#   $2: Success flag (0 = failure, 1 = success)
#
# Returns:
#   0: Always succeeds (tracking failures are non-fatal)
#
# Side effects:
#   - Increments appropriate counter in state file using atomic writes
#   - Creates state file if it doesn't exist
#
# Examples:
#   track_network_partition_check "dns" 1    # Track DNS success
#   track_network_partition_check "route" 0  # Track route failure
#
# Note:
#   Requires STATE_DIR, increment_counter_file (lib/common.sh)
#   Uses atomic writes per ADR-0012 for state file integrity
track_network_partition_check() {
	local check_type="$1"
	local success="$2"

	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Validate check type
	case "$check_type" in
	dns | route | interface)
		# Valid check type
		;;
	*)
		# Invalid check type - silently ignore (non-fatal)
		return 0
		;;
	esac

	# Determine which counter file to update
	local counter_file
	if [[ $success -eq 1 ]]; then
		counter_file="${STATE_DIR}/network_partition_${check_type}_success_count"
	else
		counter_file="${STATE_DIR}/network_partition_${check_type}_fail_count"
	fi

	increment_counter_file "$counter_file"

	return 0
}

# Log network partition check summary if hour has elapsed
#
# Logs a summary of network partition check statistics to the main log file
# if one hour has elapsed since the last summary. Tracks successes and failures
# for DNS resolution, default route, and interface state checks separately.
#
# Returns:
#   0: Always succeeds (logging failures are non-fatal)
#
# Side effects:
#   - Creates/updates ${STATE_DIR}/network_partition_summary_last_time with timestamp
#   - Resets all counters to 0 after logging summary
#   - Logs summary message at INFO level when hour has elapsed
#
# Configuration:
#   Uses fixed 1-hour interval (3600 seconds)
#
# Examples:
#   log_network_partition_summary_if_due
#   # Logs: "Network partition check summary (past hour): DNS resolution succeeded 60 times, failed 0 times; Default route check succeeded 60 times, failed 0 times; Interface state check succeeded 60 times, failed 0 times"
#
# Note:
#   Requires STATE_DIR, SECONDS_PER_HOUR, get_unix_timestamp, log_message, ensure_file_exists, atomic_write_state_file_or_warn, read_unix_timestamp_from_file, read_counter_file, and summary_interval_is_due
#   Uses atomic writes per ADR-0012 for state file integrity
log_network_partition_summary_if_due() {
	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Configurable 1-hour interval (defaults to 3600 seconds if SECONDS_PER_HOUR not set)
	local summary_interval_seconds="${SECONDS_PER_HOUR:-3600}"

	# State files for tracking
	local last_time_file="${STATE_DIR}/network_partition_summary_last_time"
	local dns_success_file="${STATE_DIR}/network_partition_dns_success_count"
	local dns_fail_file="${STATE_DIR}/network_partition_dns_fail_count"
	local route_success_file="${STATE_DIR}/network_partition_route_success_count"
	local route_fail_file="${STATE_DIR}/network_partition_route_fail_count"
	local interface_success_file="${STATE_DIR}/network_partition_interface_success_count"
	local interface_fail_file="${STATE_DIR}/network_partition_interface_fail_count"

	# Get current timestamp
	local current_time
	current_time=$(get_unix_timestamp 2>/dev/null || echo "0")

	# Initialize state files if they don't exist
	ensure_file_exists "$last_time_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$dns_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$dns_fail_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$route_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$route_fail_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$interface_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$interface_fail_file" "0" 2>/dev/null || return 0

	# Read last summary time (validated digits; unreadable/non-numeric -> 0)
	local last_time
	last_time=$(read_unix_timestamp_from_file "$last_time_file")

	if summary_interval_is_due "$current_time" "$last_time" "$summary_interval_seconds"; then
		# Time to log summary - read all counters using shared helper
		local dns_success=$(read_counter_file "$dns_success_file")
		local dns_fail=$(read_counter_file "$dns_fail_file")
		local route_success=$(read_counter_file "$route_success_file")
		local route_fail=$(read_counter_file "$route_fail_file")
		local interface_success=$(read_counter_file "$interface_success_file")
		local interface_fail=$(read_counter_file "$interface_fail_file")

		# Only log if there were any checks in the past hour
		if [[ $dns_success -gt 0 ]] || [[ $dns_fail -gt 0 ]] || [[ $route_success -gt 0 ]] || [[ $route_fail -gt 0 ]] || [[ $interface_success -gt 0 ]] || [[ $interface_fail -gt 0 ]]; then
			# Build summary message
			local summary_msg="Network partition check summary (past hour): DNS resolution succeeded ${dns_success} times, failed ${dns_fail} times; Default route check succeeded ${route_success} times, failed ${route_fail} times; Interface state check succeeded ${interface_success} times, failed ${interface_fail} times"

			log_message "INFO" "SYSTEM" "$summary_msg"
		fi

		# Reset all counters and update last time (use atomic writes per ADR-0012)
		atomic_write_state_file_or_warn "$dns_success_file" "0"
		atomic_write_state_file_or_warn "$dns_fail_file" "0"
		atomic_write_state_file_or_warn "$route_success_file" "0"
		atomic_write_state_file_or_warn "$route_fail_file" "0"
		atomic_write_state_file_or_warn "$interface_success_file" "0"
		atomic_write_state_file_or_warn "$interface_fail_file" "0"
		atomic_write_state_file_or_warn "$last_time_file" "$current_time"
	fi

	return 0
}
