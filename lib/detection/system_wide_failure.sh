#!/bin/bash
#
# System-wide failure detection
# Detects when all (or majority of) VPNs fail simultaneously
# and triggers different recovery strategy for infrastructure-level issues
#
# Version: 0.6.0
#

# Get system-wide failure state file path
#
# Returns the full file path for the system-wide failure state file.
# Uses SYSTEM_WIDE_FAILURE_STATE_FILE if set, otherwise defaults to ${STATE_DIR}/system_wide_failure_state.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the full file path to stdout
#
# Examples:
#   state_file=$(get_system_wide_failure_state_file)
#   # Returns: ${STATE_DIR}/system_wide_failure_state (or SYSTEM_WIDE_FAILURE_STATE_FILE if set)
#
# Note:
#   Requires STATE_DIR to be set
#   Used internally by get_system_wide_failure_state and set_system_wide_failure_state
get_system_wide_failure_state_file() {
	echo "${SYSTEM_WIDE_FAILURE_STATE_FILE:-${STATE_DIR}/system_wide_failure_state}"
}

# Get system-wide failure state
#
# Retrieves the current system-wide failure state (0 = no system-wide failure, 1 = system-wide failure detected).
# System-wide failure state is global since infrastructure issues affect all peers.
# Validates file format, recovering corrupted files automatically.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints "0" if no system-wide failure, "1" if system-wide failure detected
#
# Examples:
#   failure_state=$(get_system_wide_failure_state)
#   if [[ "$failure_state" -eq 1 ]]; then
#       echo "System-wide failure detected"
#   fi
#
# Note:
#   Requires get_system_wide_failure_state_file to be set
#   Returns "0" (no failure) if file doesn't exist or is corrupted
#   Uses automatic recovery for corrupted files
get_system_wide_failure_state() {
	local state_file
	state_file=$(get_system_wide_failure_state_file)

	if file_exists_and_readable "$state_file"; then
		local value
		value=$(cat "$state_file" 2>/dev/null || echo "0")
		# Validate value (must be 0 or 1)
		if [[ "$value" =~ ^[01]$ ]]; then
			echo "$value"
		else
			# Corrupted file, backup and recover
			handle_error "WARNING" "SYSTEM" "System-wide failure state file corrupted (recovering): $state_file" 0
			recover_corrupted_state_file "$state_file" "0" "integer"
			echo "0"
		fi
	else
		echo "0"
	fi
}

# Set system-wide failure state
#
# Sets the system-wide failure state (0 = no system-wide failure, 1 = system-wide failure detected).
# System-wide failure state is global since infrastructure issues affect all peers.
# Uses atomic writes for safe file operations.
#
# Arguments:
#   $1: State value (0 = no failure, 1 = system-wide failure detected)
#
# Returns:
#   0: Success
#   1: Invalid value or write failed
#
# Side effects:
#   - Updates system-wide failure state file (atomic write)
#   - State file: ${STATE_DIR}/system_wide_failure_state
#   - When state is set to 0, automatically clears the recovery coordinator file
#     to ensure consistency (coordinator should not exist when state is 0)
#
# Examples:
#   set_system_wide_failure_state 1  # Mark system-wide failure detected
#   set_system_wide_failure_state 0  # Clear system-wide failure state (also clears coordinator)
#
# Note:
#   Requires get_system_wide_failure_state_file to be set
#   Validates value is 0 or 1 before writing
#   Coordinator clearing is automatic when state is set to 0 (non-fatal operation)
set_system_wide_failure_state() {
	local state_value="$1"
	local state_file
	state_file=$(get_system_wide_failure_state_file)

	# Validate value (must be 0 or 1)
	if [[ ! "$state_value" =~ ^[01]$ ]]; then
		handle_error "ERROR" "SYSTEM" "Invalid system-wide failure state value (expected 0 or 1): $state_value" 0
		return 1
	fi

	# Atomic write
	if ! atomic_write_file "$state_file" "$state_value"; then
		handle_error "ERROR" "SYSTEM" "Failed to update system-wide failure state file: $state_file" 0
		return 1
	fi

	# Clear coordinator when clearing system-wide failure state
	# This ensures consistency: coordinator should not exist when state is 0
	# Note: clear_system_wide_failure_coordinator is non-fatal, so we don't check return value
	if [[ "$state_value" -eq 0 ]]; then
		clear_system_wide_failure_coordinator
	fi

	return 0
}

# Get system-wide failure detection timestamp file path
#
# Returns the full file path for the system-wide failure detection timestamp file.
# This tracks when a system-wide failure was first detected.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the full file path to stdout
#
# Examples:
#   timestamp_file=$(get_system_wide_failure_timestamp_file)
#   # Returns: ${STATE_DIR}/system_wide_failure_timestamp
#
# Note:
#   Requires STATE_DIR to be set
get_system_wide_failure_timestamp_file() {
	echo "${SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE:-${STATE_DIR}/system_wide_failure_timestamp}"
}

# Get system-wide failure detection timestamp
#
# Retrieves the Unix timestamp when system-wide failure was first detected.
# Returns 0 if no timestamp is stored or file is corrupted.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints Unix timestamp (integer) to stdout, or "0" if unavailable
#
# Examples:
#   timestamp=$(get_system_wide_failure_timestamp)
#   if [[ "$timestamp" -gt 0 ]]; then
#       echo "System-wide failure detected at: $(date -d "@$timestamp")"
#   fi
#
# Note:
#   Requires get_system_wide_failure_timestamp_file to be set
#   Returns "0" if file doesn't exist or is corrupted
get_system_wide_failure_timestamp() {
	local timestamp_file
	timestamp_file=$(get_system_wide_failure_timestamp_file)

	if file_exists_and_readable "$timestamp_file"; then
		local value
		value=$(cat "$timestamp_file" 2>/dev/null || echo "0")
		# Validate value (must be numeric)
		if [[ "$value" =~ ^[0-9]+$ ]]; then
			echo "$value"
		else
			# Corrupted file, backup and recover
			handle_error "WARNING" "SYSTEM" "System-wide failure timestamp file corrupted (recovering): $timestamp_file" 0
			recover_corrupted_state_file "$timestamp_file" "0" "integer"
			echo "0"
		fi
	else
		echo "0"
	fi
}

# Set system-wide failure detection timestamp
#
# Sets the Unix timestamp when system-wide failure was first detected.
# Uses atomic writes for safe file operations.
#
# Arguments:
#   $1: Unix timestamp (integer, seconds since epoch)
#
# Returns:
#   0: Success
#   1: Invalid value or write failed
#
# Side effects:
#   - Updates system-wide failure timestamp file (atomic write)
#   - State file: ${STATE_DIR}/system_wide_failure_timestamp
#
# Examples:
#   now=$(get_unix_timestamp)
#   set_system_wide_failure_timestamp "$now"
#
# Note:
#   Requires get_system_wide_failure_timestamp_file to be set
#   Validates value is numeric before writing
set_system_wide_failure_timestamp() {
	local timestamp_value="$1"
	local timestamp_file
	timestamp_file=$(get_system_wide_failure_timestamp_file)

	# Validate value (must be numeric)
	if [[ ! "$timestamp_value" =~ ^[0-9]+$ ]]; then
		handle_error "ERROR" "SYSTEM" "Invalid system-wide failure timestamp value (expected numeric): $timestamp_value" 0
		return 1
	fi

	# Atomic write
	if ! atomic_write_file "$timestamp_file" "$timestamp_value"; then
		handle_error "ERROR" "SYSTEM" "Failed to update system-wide failure timestamp file: $timestamp_file" 0
		return 1
	fi

	return 0
}

# Detect system-wide failure
#
# Analyzes failure status across all locations to determine if a system-wide failure
# is occurring. A system-wide failure is detected when all (or a configured majority)
# of VPN locations are failing simultaneously.
#
# Arguments:
#   $1: Array of location names (associative array keys)
#   $2: Array of failure statuses (0 = healthy, 1 = failed) corresponding to locations
#
# Returns:
#   0: System-wide failure detected
#   1: No system-wide failure (individual failures only)
#
# Output (via global variables):
#   SYSTEM_WIDE_FAILURE_DETECTED: 1 if system-wide failure detected, 0 otherwise
#   FAILED_LOCATION_COUNT: Number of locations currently failing
#   TOTAL_LOCATION_COUNT: Total number of locations
#
# Examples:
#   declare -A location_status
#   location_status["NYC"]=1  # Failed
#   location_status["DC"]=1   # Failed
#   location_status["SF"]=0   # Healthy
#   if detect_system_wide_failure "location_status"; then
#       echo "System-wide failure detected"
#   fi
#
# Note:
#   Requires ENABLE_SYSTEM_WIDE_FAILURE_DETECTION configuration variable (default: 1)
#   Requires SYSTEM_WIDE_FAILURE_THRESHOLD configuration variable (default: 100, meaning all must fail)
#   Threshold is percentage (0-100): 100 = all must fail, 80 = 80% must fail, etc.
#   Receives failure statuses as parameters and iterates through them to count failures
detect_system_wide_failure() {
	local -n location_names_ref="$1"
	local -n failure_statuses_ref="$2"

	# Initialize return variables
	declare -g SYSTEM_WIDE_FAILURE_DETECTED=0
	declare -g FAILED_LOCATION_COUNT=0
	declare -g TOTAL_LOCATION_COUNT=0

	# Check if system-wide failure detection is enabled
	local enabled="${ENABLE_SYSTEM_WIDE_FAILURE_DETECTION:-1}"
	if [[ "$enabled" -ne 1 ]]; then
		return 1
	fi

	# Count total locations and failed locations
	# Both arrays should have the same keys (location names)
	local total_locations=0
	local failed_locations=0

	# Iterate through all locations (use location_names_ref keys)
	for location_name in "${!location_names_ref[@]}"; do
		total_locations=$((total_locations + 1))
		# Get failure status for this location (default to 0 if not found)
		local status="${failure_statuses_ref[$location_name]:-0}"
		if [[ "$status" -eq 1 ]]; then
			failed_locations=$((failed_locations + 1))
		fi
	done

	# Store counts in global variables (export for use in calling code)
	declare -g TOTAL_LOCATION_COUNT=$total_locations
	declare -g FAILED_LOCATION_COUNT=$failed_locations

	# Need at least 2 locations to detect system-wide failure
	# (single location failure is not "system-wide")
	if [[ $total_locations -lt 2 ]]; then
		return 1
	fi

	# Get threshold (percentage of locations that must fail)
	# Validation is handled by config validation layer (config_schema.sh)
	local threshold="${SYSTEM_WIDE_FAILURE_THRESHOLD:-100}"

	# Calculate percentage of failed locations
	local failed_percentage=0
	if [[ $total_locations -gt 0 ]]; then
		# Calculate percentage: (failed_locations * 100) / total_locations
		failed_percentage=$((failed_locations * 100 / total_locations))
	fi

	# Check if threshold is met
	if [[ $failed_percentage -ge $threshold ]]; then
		SYSTEM_WIDE_FAILURE_DETECTED=1
		return 0
	fi

	return 1
}

# Check if system-wide failure recovery should be coordinated
#
# Determines if recovery should be coordinated (only one location attempts recovery)
# when a system-wide failure is detected. This prevents recovery cascades and rate limiting.
#
# Arguments:
#   None
#
# Returns:
#   0: Recovery should be coordinated
#   1: Normal per-location recovery should proceed
#
# Examples:
#   if should_coordinate_recovery; then
#       # Only first location attempts recovery
#   fi
#
# Note:
#   Requires ENABLE_SYSTEM_WIDE_FAILURE_DETECTION and COORDINATE_SYSTEM_WIDE_RECOVERY
#   Returns 1 (no coordination) if system-wide failure detection is disabled
should_coordinate_recovery() {
	# Check if system-wide failure detection is enabled
	local enabled="${ENABLE_SYSTEM_WIDE_FAILURE_DETECTION:-1}"
	if [[ "$enabled" -ne 1 ]]; then
		return 1
	fi

	# Check if system-wide failure is currently detected
	local failure_state
	failure_state=$(get_system_wide_failure_state)
	if [[ "$failure_state" -ne 1 ]]; then
		return 1
	fi

	# Check if coordination is enabled
	local coordinate="${COORDINATE_SYSTEM_WIDE_RECOVERY:-1}"
	if [[ "$coordinate" -ne 1 ]]; then
		return 1
	fi

	return 0
}

# Get system-wide failure recovery coordinator file path
#
# Returns the full file path for the system-wide failure recovery coordinator file.
# This tracks which location is designated to attempt recovery during system-wide failures.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the full file path to stdout
#
# Examples:
#   coordinator_file=$(get_system_wide_failure_coordinator_file)
#   # Returns: ${STATE_DIR}/system_wide_failure_coordinator
#
# Note:
#   Requires STATE_DIR to be set
get_system_wide_failure_coordinator_file() {
	echo "${SYSTEM_WIDE_FAILURE_COORDINATOR_FILE:-${STATE_DIR}/system_wide_failure_coordinator}"
}

# Check if this location should attempt recovery during system-wide failure
#
# During system-wide failures, only one location should attempt recovery to prevent
# cascades and rate limiting. This function determines if the current location is
# designated as the coordinator for recovery attempts.
#
# Arguments:
#   $1: Location name to check
#
# Returns:
#   0: This location should attempt recovery
#   1: Another location is coordinating recovery, coordination not needed, or coordination setup failed
#
# Examples:
#   if should_location_attempt_recovery "NYC"; then
#       # This location should attempt recovery
#   fi
#
# Note:
#   Uses a coordinator file to track which location is designated
#   First location to check becomes the coordinator if none exists
#   Coordinator persists until system-wide failure is cleared
#   Uses atomic check-and-create pattern (noclobber mode) to prevent race conditions
#   If coordinator file creation fails (disk full, permissions, etc.), returns 1 to prevent
#   recovery attempts when coordination is broken (conservative approach)
should_location_attempt_recovery() {
	local location_name="$1"

	# Validate location_name is provided and non-empty
	# Empty location_name would cause issues with coordinator file and matching
	if [[ -z "$location_name" ]]; then
		handle_error "ERROR" "SYSTEM" "should_location_attempt_recovery called with empty location_name - cannot coordinate recovery" 0
		return 1
	fi

	# Check if coordination is needed
	if ! should_coordinate_recovery; then
		# No coordination needed, all locations can attempt recovery
		return 0
	fi

	# Get coordinator file
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)

	# Try to atomically create coordinator file (check-and-set pattern)
	# Uses noclobber mode (set -C) to prevent race condition: only first writer succeeds
	# set -C: noclobber mode - prevents overwriting existing file (atomic check-and-create)
	if (
		set -C
		echo "$location_name" >"$coordinator_file"
	) 2>/dev/null; then
		# Successfully created coordinator file - we are the coordinator
		log_message "INFO" "SYSTEM" "Location $location_name designated as recovery coordinator for system-wide failure"
		return 0
	fi

	# Coordinator file already exists (another location created it first)
	# Check if we are the coordinator
	if file_exists_and_readable "$coordinator_file"; then
		local coordinator
		coordinator=$(cat "$coordinator_file" 2>/dev/null || echo "")
		if [[ "$coordinator" == "$location_name" ]]; then
			# This location is the coordinator
			return 0
		else
			# Another location is coordinating
			return 1
		fi
	else
		# File doesn't exist but creation failed - coordination broken, be conservative
		# This could happen due to disk full, permissions, or other I/O errors
		handle_error "ERROR" "SYSTEM" "Failed to set recovery coordinator file: $coordinator_file. Coordination disabled for this cycle." 0
		# Conservative approach: don't attempt recovery if coordination is broken
		return 1
	fi
}

# Clear system-wide failure recovery coordinator
#
# Clears the recovery coordinator when system-wide failure is resolved.
# Should be called when system-wide failure state is cleared.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (non-fatal if file doesn't exist)
#
# Side effects:
#   - Removes coordinator file if it exists
#
# Examples:
#   clear_system_wide_failure_coordinator
#
# Note:
#   Non-fatal operation - returns 0 even if file doesn't exist
clear_system_wide_failure_coordinator() {
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)

	if [[ -f "$coordinator_file" ]]; then
		rm -f "$coordinator_file" 2>/dev/null || true
	fi

	return 0
}
