#!/bin/bash
#
# Per-peer state operations
# Handles state management for individual VPN peers
#
# Version: 0.6.0
#

# Get peer state value
#
# Unified getter for per-peer state values (failure_count, last_bytes, etc.).
# Returns default value (0 for numeric, empty for others) if file doesn't exist.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address
#   $3: State key name (e.g., "failure_count", "last_bytes")
#   $4: Default value (optional, defaults to "0" for numeric keys)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the state value to stdout (or default if not found)
#
# Examples:
#   count=$(get_peer_state "NYC" "203.0.113.1" "failure_count")
#   bytes=$(get_peer_state "NYC" "203.0.113.1" "last_bytes")
#
# Note:
#   Requires get_peer_state_file_path to be set
#   Validates numeric values and returns default if corrupted
#   Uses timeout wrapper around cat as a defensive measure for this high-risk path
#   (file_exists_and_readable should prevent hangs, but this adds extra protection for edge cases
#    such as race conditions where file becomes unreadable between check and cat, or test suite
#    timing issues. This is specific to this function and not necessarily a pattern to follow
#    everywhere - other similar code paths rely on file_exists_and_readable checks alone.)
get_peer_state() {
	local location_name="$1"
	local peer_ip="$2"
	local key="$3"
	# Handle default value: if 4th arg is provided (even if empty), use it; otherwise default to "0"
	# This allows empty string defaults for non-numeric keys like "recovery_method" and "spi"
	if [[ $# -ge 4 ]]; then
		local default_value="$4"
	else
		local default_value="0"
	fi
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$key")

	if file_exists_and_readable "$state_file"; then
		local value
		# Defensive timeout wrapper: file_exists_and_readable should prevent hangs, but this adds
		# extra protection for edge cases (race conditions, test suite timing issues, etc.)
		# Note: This is specific to this high-risk path - other similar code paths rely on
		# file_exists_and_readable checks alone. If test suite timing issues persist, investigate
		# test execution environment separately rather than adding timeouts everywhere.
		# Use helper function to standardize timeout command availability check
		value=$(run_with_timeout "$STATE_FILE_READ_TIMEOUT" cat "$state_file" 2>/dev/null || echo "$default_value")
		# Validate numeric keys
		case "$key" in
		failure_count | last_bytes | last_status_log)
			if [[ ! "$value" =~ ^[0-9]+$ ]]; then
				handle_error "WARNING" "SYSTEM" "Corrupted peer state file (recovering): $state_file" 0
				recover_corrupted_state_file "$state_file" "$default_value" "integer"
				echo "$default_value"
				return 0
			fi
			;;
		spi)
			# SPI can be hex (0x...) or decimal format
			if [[ ! "$value" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
				handle_error "WARNING" "SYSTEM" "Corrupted peer state file (recovering): $state_file" 0
				recover_corrupted_state_file "$state_file" "$default_value" "integer"
				echo "$default_value"
				return 0
			fi
			;;
		esac
		echo "$value"
	else
		echo "$default_value"
	fi
}

# Set peer state value
#
# Unified setter for per-peer state values with atomic writes.
# Uses temporary file and mv for atomic write to prevent corruption.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address
#   $3: State key name (e.g., "failure_count", "last_bytes")
#   $4: Value to set
#
# Returns:
#   0: Success
#   1: Failed to write (logged but doesn't exit)
#
# Side effects:
#   - Creates or updates per-peer state file (atomic write)
#   - Logs errors if write fails
#
# Examples:
#   set_peer_state "NYC" "203.0.113.1" "failure_count" "5"
#   set_peer_state "NYC" "203.0.113.1" "last_bytes" "123456"
#
# Note:
#   Requires get_peer_state_file_path to be set
#   Uses temporary file and mv for atomic write to prevent corruption on interruption
#   Validates numeric keys before writing
set_peer_state() {
	local location_name="$1"
	local peer_ip="$2"
	local key="$3"
	local value="$4"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$key")

	# Validate numeric keys
	case "$key" in
	failure_count | last_bytes | last_status_log)
		if [[ ! "$value" =~ ^[0-9]+$ ]]; then
			handle_error "ERROR" "SYSTEM" "Invalid value for $key (expected integer): $value" 0
			return 1
		fi
		;;
	spi)
		# SPI can be hex (0x...) or decimal format
		if [[ ! "$value" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]] && [[ -n "$value" ]]; then
			handle_error "ERROR" "SYSTEM" "Invalid value for $key (expected SPI format): $value" 0
			return 1
		fi
		;;
	esac

	# Ensure directory exists before writing file
	# Extract directory from the file path to avoid duplicating logic from get_peer_state_file_path()
	local state_dir
	state_dir=$(dirname "$state_file")
	if ! try_ensure_directory_exists "$state_dir"; then
		handle_error "ERROR" "SYSTEM" "Failed to create directory for peer state: $state_dir" 0
		return 1
	fi

	# Atomic write: write to temp file first, then rename
	if ! atomic_write_file "$state_file" "$value"; then
		handle_error "ERROR" "SYSTEM" "Failed to update peer state for $peer_ip (key: $key, file: $state_file)" 0
		return 1
	fi

	return 0
}

# Set peer state value with non-critical error handling
#
# Wrapper around set_peer_state that handles errors gracefully.
# State update failures are non-critical and already logged by set_peer_state,
# so this function allows execution to continue even if state update fails.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address
#   $3: State key name (e.g., "failure_count", "last_bytes")
#   $4: Value to set
#
# Returns:
#   0: Always succeeds (continues execution even if state update fails)
#
# Side effects:
#   - Calls set_peer_state which logs errors on failure
#   - Execution continues regardless of success/failure
#
# Examples:
#   set_peer_state_non_critical "NYC" "203.0.113.1" "spi" "$current_spi"
#   set_peer_state_non_critical "NYC" "203.0.113.1" "last_bytes" "$current_bytes"
#
# Note:
#   Use this when state updates are non-critical and failures should not
#   interrupt execution. Errors are already logged by set_peer_state.
set_peer_state_non_critical() {
	local location_name="$1"
	local peer_ip="$2"
	local key="$3"
	local value="$4"
	# State update failure is non-critical (already logged by set_peer_state)
	if ! set_peer_state "$location_name" "$peer_ip" "$key" "$value"; then
		# Error already logged by set_peer_state, continue execution
		:
	fi
}

# Delete peer state value
#
# Removes a per-peer state file (for cleanup when peer is removed).
#
# Arguments:
#   $1: Location name (required)
#   $2: Peer IP address
#   $3: State key name (e.g., "failure_count", "last_bytes")
#
# Returns:
#   0: Success (or file didn't exist)
#   1: Failed to delete
#
# Side effects:
#   - Removes per-peer state file if it exists
#
# Examples:
#   delete_peer_state "NYC" "203.0.113.1" "failure_count"
#   delete_peer_state "NYC" "203.0.113.1" "last_bytes"
#
# Note:
#   Requires get_peer_state_file_path to be set
#   Safe to call if file doesn't exist (returns 0)
delete_peer_state() {
	local location_name="$1"
	local peer_ip="$2"
	local key="$3"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$key")

	if file_exists_and_readable "$state_file"; then
		if ! rm -f "$state_file"; then
			handle_error "WARNING" "SYSTEM" "Failed to delete peer state file: $state_file" 0
			return 1
		fi
	fi

	return 0
}

# Clean up state files for a removed peer
#
# Removes all state files associated with a peer (failure_count, last_bytes, etc.).
# Useful when a peer is removed from configuration.
#
# Arguments:
#   $1: Location name (required)
#   $2: Peer IP address
#
# Returns:
#   0: Always succeeds (logs warnings but continues)
#
# Side effects:
#   - Removes all per-peer state files
#   - Logs warnings for any failures
#
# Examples:
#   cleanup_peer_state "NYC" "203.0.113.1"
#
# Note:
#   Requires delete_peer_state to be set
#   Safe to call even if no state files exist
cleanup_peer_state() {
	local location_name="$1"
	local peer_ip="$2"
	delete_peer_state "$location_name" "$peer_ip" "failure_count"
	delete_peer_state "$location_name" "$peer_ip" "last_bytes"
	delete_peer_state "$location_name" "$peer_ip" "spi"
	delete_peer_state "$location_name" "$peer_ip" "idle_detected"
	# Add other state keys here as needed
}

# Get current failure counter for a specific peer
#
# Reads the current consecutive failure count from the per-peer state file.
# Each peer has its own independent failure counter tracked separately.
# Returns 0 if file doesn't exist (first failure) or is empty/corrupted.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the failure count (integer) to stdout (0 if file doesn't exist)
#
# Examples:
#   count=$(get_failure_count "NYC" "203.0.113.1")
#   echo "Failure count: $count"
#
# Note:
#   Uses get_peer_state() abstraction layer internally
#   Counter file: ${STATE_DIR}/failure_counter_<location>_<sanitized_peer_ip>
#   Returns 0 if file doesn't exist (cat fails) or is empty
get_failure_count() {
	local location_name="$1"
	local peer_ip="$2"
	get_peer_state "$location_name" "$peer_ip" "failure_count" "0"
}

# Increment failure counter for a specific peer
#
# Increments the consecutive failure counter by 1 and saves it to the per-peer state file.
# Used to track how many times in a row the VPN check has failed for this specific peer.
# Each peer has its own independent failure counter tracked separately.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the new failure count (integer) to stdout
#
# Side effects:
#   - Creates or updates per-peer counter file with new count (atomic write)
#   - Counter file: ${STATE_DIR}/failure_counter_<location>_<sanitized_peer_ip>
#
# Examples:
#   new_count=$(increment_failure "NYC" "203.0.113.1")
#   echo "Failure count incremented to: $new_count"
#
# Note:
#   Uses get_peer_state() and set_peer_state() abstraction layer internally
#   Reads current count, increments by 1, writes back atomically
increment_failure() {
	local location_name="$1"
	local peer_ip="$2"
	local count
	count=$(get_peer_state "$location_name" "$peer_ip" "failure_count" "0")
	local new_count=$((count + 1))
	if set_peer_state "$location_name" "$peer_ip" "failure_count" "$new_count"; then
		echo "$new_count"
	else
		# If set failed, return current count (already logged error)
		echo "$count"
	fi
}

# Reset failure counter for a specific peer
#
# Resets the consecutive failure counter to 0 for the specified peer.
# Called when VPN check succeeds after previous failures for this peer.
# Each peer has its own independent failure counter tracked separately.
#
# Arguments:
#   $1: Location name (required, sanitized)
#   $2: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Writes "0" to per-peer counter file (atomic write)
#   - Counter file: ${STATE_DIR}/failure_counter_<location>_<sanitized_peer_ip>
#
# Examples:
#   reset_failure_count "NYC" "203.0.113.1"
#   # Resets counter to 0 for this peer
#
# Note:
#   Uses set_peer_state() abstraction layer internally
#   Called when VPN recovers after failures
reset_failure_count() {
	local location_name="$1"
	local peer_ip="$2"
	set_peer_state_non_critical "$location_name" "$peer_ip" "failure_count" "0"
}
