#!/bin/bash
#
# Resource monitoring statistics tracking
# Handles success/failure counting and hourly summary logging for resource monitoring checks
#
# Version: 0.6.0
#

# Track resource check result
#
# Increments the appropriate success or failure counter for a specific resource check type.
# Used to track statistics for CPU, RAM, and disk checks.
#
# Arguments:
#   $1: Resource type ("cpu", "ram", or "disk")
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
#   track_resource_check "cpu" 1    # Track CPU check success
#   track_resource_check "ram" 0    # Track RAM check failure
#
# Note:
#   Requires STATE_DIR, atomic_write_file, and ensure_file_exists to be set
#   Uses atomic writes per ADR-0012 for state file integrity
track_resource_check() {
	local resource_type="$1"
	local success="$2"

	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Validate resource type
	case "$resource_type" in
	cpu | ram | disk)
		# Valid resource type
		;;
	*)
		# Invalid resource type - silently ignore (non-fatal)
		return 0
		;;
	esac

	# Determine which counter file to update
	local counter_file
	if [[ $success -eq 1 ]]; then
		counter_file="${STATE_DIR}/resource_${resource_type}_check_success_count"
	else
		counter_file="${STATE_DIR}/resource_${resource_type}_check_fail_count"
	fi

	# Initialize state file if it doesn't exist
	ensure_file_exists "$counter_file" "0" 2>/dev/null || return 0

	# Read current count
	local current_count
	current_count=$(cat "$counter_file" 2>/dev/null || echo "0")

	# Validate count is numeric (handle corruption)
	if ! [[ "$current_count" =~ ^[0-9]+$ ]]; then
		current_count=0
	fi

	# Increment count
	current_count=$((current_count + 1))

	# Use atomic write for state file (per ADR-0012)
	atomic_write_file "$counter_file" "$current_count" 2>/dev/null || true

	return 0
}

# Track resource constraint event
#
# Increments the counter for a specific resource constraint event.
# Used to track when resources are actually constrained (CPU constrained, RAM constrained, disk critical).
#
# Arguments:
#   $1: Constraint type ("cpu_constrained", "ram_constrained", or "disk_critical")
#
# Returns:
#   0: Always succeeds (tracking failures are non-fatal)
#
# Side effects:
#   - Increments appropriate counter in state file using atomic writes
#   - Creates state file if it doesn't exist
#
# Examples:
#   track_resource_constraint "cpu_constrained"    # Track CPU constraint event
#   track_resource_constraint "disk_critical"      # Track disk critical event
#
# Note:
#   Requires STATE_DIR, atomic_write_file, and ensure_file_exists to be set
#   Uses atomic writes per ADR-0012 for state file integrity
track_resource_constraint() {
	local constraint_type="$1"

	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Validate constraint type
	case "$constraint_type" in
	cpu_constrained | ram_constrained | disk_critical)
		# Valid constraint type
		;;
	*)
		# Invalid constraint type - silently ignore (non-fatal)
		return 0
		;;
	esac

	# Determine counter file
	local counter_file="${STATE_DIR}/resource_${constraint_type}_count"

	# Initialize state file if it doesn't exist
	ensure_file_exists "$counter_file" "0" 2>/dev/null || return 0

	# Read current count
	local current_count
	current_count=$(cat "$counter_file" 2>/dev/null || echo "0")

	# Validate count is numeric (handle corruption)
	if ! [[ "$current_count" =~ ^[0-9]+$ ]]; then
		current_count=0
	fi

	# Increment count
	current_count=$((current_count + 1))

	# Use atomic write for state file (per ADR-0012)
	atomic_write_file "$counter_file" "$current_count" 2>/dev/null || true

	return 0
}

# Log resource monitoring summary if hour has elapsed
#
# Logs a summary of resource monitoring statistics to the main log file
# if one hour has elapsed since the last summary. Tracks successes and failures
# for CPU, RAM, and disk checks separately, as well as constraint events.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (logging failures are non-fatal)
#
# Side effects:
#   - Creates/updates ${STATE_DIR}/resource_monitoring_summary_last_time with timestamp
#   - Resets all counters to 0 after logging summary
#   - Logs summary message at INFO level when hour has elapsed
#
# Configuration:
#   Uses fixed 1-hour interval (3600 seconds)
#
# Examples:
#   log_resource_monitoring_summary_if_due
#   # Logs: "Resource monitoring summary (past hour): CPU checks succeeded 60 times, failed 0 times; RAM checks succeeded 60 times, failed 0 times; Disk checks succeeded 60 times, failed 0 times; CPU constrained 0 times; RAM constrained 0 times; Disk critical 0 times"
#
# Note:
#   Requires STATE_DIR, SECONDS_PER_HOUR, get_unix_timestamp, log_message, ensure_file_exists, and atomic_write_file to be set
#   Uses atomic writes per ADR-0012 for state file integrity
log_resource_monitoring_summary_if_due() {
	# Only proceed if STATE_DIR is set
	if [[ -z "${STATE_DIR:-}" ]]; then
		return 0
	fi

	# Fixed 1-hour interval (3600 seconds)
	local summary_interval_seconds="${SECONDS_PER_HOUR:-3600}"

	# State files for tracking
	local last_time_file="${STATE_DIR}/resource_monitoring_summary_last_time"
	local cpu_success_file="${STATE_DIR}/resource_cpu_check_success_count"
	local cpu_fail_file="${STATE_DIR}/resource_cpu_check_fail_count"
	local ram_success_file="${STATE_DIR}/resource_ram_check_success_count"
	local ram_fail_file="${STATE_DIR}/resource_ram_check_fail_count"
	local disk_success_file="${STATE_DIR}/resource_disk_check_success_count"
	local disk_fail_file="${STATE_DIR}/resource_disk_check_fail_count"
	local cpu_constrained_file="${STATE_DIR}/resource_cpu_constrained_count"
	local ram_constrained_file="${STATE_DIR}/resource_ram_constrained_count"
	local disk_critical_file="${STATE_DIR}/resource_disk_critical_count"

	# Get current timestamp
	local current_time
	current_time=$(get_unix_timestamp 2>/dev/null || echo "0")

	# Initialize state files if they don't exist
	ensure_file_exists "$last_time_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$cpu_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$cpu_fail_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$ram_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$ram_fail_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$disk_success_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$disk_fail_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$cpu_constrained_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$ram_constrained_file" "0" 2>/dev/null || return 0
	ensure_file_exists "$disk_critical_file" "0" 2>/dev/null || return 0

	# Read last summary time
	local last_time
	last_time=$(cat "$last_time_file" 2>/dev/null || echo "0")

	# Validate last_time is numeric (handle corruption)
	if ! [[ "$last_time" =~ ^[0-9]+$ ]]; then
		last_time=0
	fi

	# Check if configured interval has elapsed since last summary
	local time_since_last=$((current_time - last_time))

	if [[ $time_since_last -ge $summary_interval_seconds ]] || [[ $last_time -eq 0 ]]; then
		# Time to log summary - read all counters
		local cpu_success
		cpu_success=$(cat "$cpu_success_file" 2>/dev/null || echo "0")
		local cpu_fail
		cpu_fail=$(cat "$cpu_fail_file" 2>/dev/null || echo "0")
		local ram_success
		ram_success=$(cat "$ram_success_file" 2>/dev/null || echo "0")
		local ram_fail
		ram_fail=$(cat "$ram_fail_file" 2>/dev/null || echo "0")
		local disk_success
		disk_success=$(cat "$disk_success_file" 2>/dev/null || echo "0")
		local disk_fail
		disk_fail=$(cat "$disk_fail_file" 2>/dev/null || echo "0")
		local cpu_constrained
		cpu_constrained=$(cat "$cpu_constrained_file" 2>/dev/null || echo "0")
		local ram_constrained
		ram_constrained=$(cat "$ram_constrained_file" 2>/dev/null || echo "0")
		local disk_critical
		disk_critical=$(cat "$disk_critical_file" 2>/dev/null || echo "0")

		# Validate all counts are numeric (handle corruption)
		[[ "$cpu_success" =~ ^[0-9]+$ ]] || cpu_success=0
		[[ "$cpu_fail" =~ ^[0-9]+$ ]] || cpu_fail=0
		[[ "$ram_success" =~ ^[0-9]+$ ]] || ram_success=0
		[[ "$ram_fail" =~ ^[0-9]+$ ]] || ram_fail=0
		[[ "$disk_success" =~ ^[0-9]+$ ]] || disk_success=0
		[[ "$disk_fail" =~ ^[0-9]+$ ]] || disk_fail=0
		[[ "$cpu_constrained" =~ ^[0-9]+$ ]] || cpu_constrained=0
		[[ "$ram_constrained" =~ ^[0-9]+$ ]] || ram_constrained=0
		[[ "$disk_critical" =~ ^[0-9]+$ ]] || disk_critical=0

		# Only log if there were any checks in the past hour
		if [[ $cpu_success -gt 0 ]] || [[ $cpu_fail -gt 0 ]] || [[ $ram_success -gt 0 ]] || [[ $ram_fail -gt 0 ]] || [[ $disk_success -gt 0 ]] || [[ $disk_fail -gt 0 ]] || [[ $cpu_constrained -gt 0 ]] || [[ $ram_constrained -gt 0 ]] || [[ $disk_critical -gt 0 ]]; then
			# Build summary message
			local summary_msg="Resource monitoring summary (past hour): CPU checks succeeded ${cpu_success} times, failed ${cpu_fail} times; RAM checks succeeded ${ram_success} times, failed ${ram_fail} times; Disk checks succeeded ${disk_success} times, failed ${disk_fail} times; CPU constrained ${cpu_constrained} times; RAM constrained ${ram_constrained} times; Disk critical ${disk_critical} times"

			log_message "INFO" "SYSTEM" "$summary_msg"
		fi

		# Reset all counters and update last time (use atomic writes per ADR-0012)
		atomic_write_file "$cpu_success_file" "0" 2>/dev/null || true
		atomic_write_file "$cpu_fail_file" "0" 2>/dev/null || true
		atomic_write_file "$ram_success_file" "0" 2>/dev/null || true
		atomic_write_file "$ram_fail_file" "0" 2>/dev/null || true
		atomic_write_file "$disk_success_file" "0" 2>/dev/null || true
		atomic_write_file "$disk_fail_file" "0" 2>/dev/null || true
		atomic_write_file "$cpu_constrained_file" "0" 2>/dev/null || true
		atomic_write_file "$ram_constrained_file" "0" 2>/dev/null || true
		atomic_write_file "$disk_critical_file" "0" 2>/dev/null || true
		atomic_write_file "$last_time_file" "$current_time" 2>/dev/null || true
	fi

	return 0
}
