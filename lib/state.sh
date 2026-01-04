#!/bin/bash
#
# State file management for UDM VPN Monitor
# Handles failure counters, cooldown periods, rate limiting, and restart tracking
#
# Version: 0.4.3
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: safe_source_lib not available here since constants.sh is sourced before common.sh
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
	[[ -z "${SECONDS_PER_MINUTE:-}" ]] && readonly SECONDS_PER_MINUTE=60
	[[ -z "${SECONDS_PER_HOUR:-}" ]] && readonly SECONDS_PER_HOUR=3600
	[[ -z "${SECONDS_PER_DAY:-}" ]] && readonly SECONDS_PER_DAY=86400
fi

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh" 2>/dev/null || {
	# Fallback if common.sh not found - define minimal versions
	ensure_file_exists() {
		local file="$1"
		local default_content="${2:-}"
		if [[ ! -f "$file" ]]; then
			echo "$default_content" >"$file" 2>/dev/null || return 1
		fi
		return 0
	}
	try_ensure_directory_exists() {
		local dir="$1"
		if [[ ! -d "$dir" ]]; then
			mkdir -p "$dir" 2>/dev/null || return 1
		fi
		return 0
	}
	safe_source_lib() {
		local lib_file="$1"
		source "$lib_file" 2>/dev/null
	}
}

# Initialize state files if they don't exist
#
# Creates required state files (restart_count) if they don't exist.
# Per-peer failure counter and byte counter files are created on-demand when needed.
# This ensures state files exist before they are accessed.
#
# State files:
#   - RESTART_COUNT_FILE: Tracks restart timestamps for rate limiting (created here)
#   - NETWORK_PARTITION_STATE_FILE: Tracks network partition status (created here)
#   - Per-peer failure counters: Created on-demand as failure_counter_<peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<peer_ip>
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   - Creates RESTART_COUNT_FILE with default value "0" if it doesn't exist
#   - Creates NETWORK_PARTITION_STATE_FILE with default value "0" if it doesn't exist
#   - Logs warning if file creation fails (but doesn't exit)
#
# Examples:
#   init_state
#   # Ensures restart count file exists before use
#
# Note:
#   Requires RESTART_COUNT_FILE, NETWORK_PARTITION_STATE_FILE, ensure_file_exists, and log_message to be set
#   Per-peer files are created on-demand by increment_failure and check_byte_counters
init_state() {
	# Ensure directories exist before creating files
	if ! try_ensure_directory_exists "$LOGS_DIR"; then
		# log_message() (called by handle_error) already handles logging failures gracefully
		# by outputting to stderr if the log directory can't be created
		handle_error "WARNING" "SYSTEM" "Failed to create logs directory: $LOGS_DIR" 0
	fi
	if ! try_ensure_directory_exists "$STATE_DIR"; then
		handle_error "WARNING" "SYSTEM" "Failed to create state directory: $STATE_DIR"
	fi

	if ! ensure_file_exists "$RESTART_COUNT_FILE" "0"; then
		handle_error "WARNING" "SYSTEM" "Failed to create restart count file"
	fi
	# Initialize network partition state file (0 = healthy, 1 = partitioned)
	local network_partition_file
	network_partition_file=$(get_network_partition_state_file)
	if ! ensure_file_exists "$network_partition_file" "0"; then
		handle_error "WARNING" "SYSTEM" "Failed to create network partition state file"
	fi
	# Per-peer failure counters and byte counters are created on-demand
}

# Sanitize peer IP for use in filenames
#
# Converts IP address characters that are unsafe for filenames to underscores.
# Used to create per-peer state files (e.g., last_bytes_192_168_1_1).
# Replaces dots (.) and colons (:) with underscores (_).
#
# Arguments:
#   $1: IP address (IPv4 or IPv6, may contain dots and colons)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints sanitized IP address to stdout (dots and colons replaced with underscores)
#
# Examples:
#   sanitized=$(sanitize_peer_ip "192.168.1.1")
#   # Returns: "192_168_1_1"
#   sanitized=$(sanitize_peer_ip "2001:db8::1")
#   # Returns: "2001_db8__1"
#
# Note:
#   Uses tr command to replace characters: tr '.' '_' | tr ':' '_'
#   Used for creating safe filenames from IP addresses
sanitize_peer_ip() {
	local ip="$1"
	echo "$ip" | tr '.' '_' | tr ':' '_'
}

# Get file path for a peer state key
#
# Returns the full file path for a per-peer state key.
# Handles different storage locations for different state types:
#   - failure_count: stored in STATE_DIR
#   - last_bytes: stored in STATE_DIR
#   - connection_name: stored in STATE_DIR (per-peer only, no location)
#
# Arguments:
#   $1: Location name (required for most keys, empty string for connection_name)
#   $2: Peer IP address
#   $3: State key name (e.g., "failure_count", "last_bytes", "connection_name")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the full file path to stdout
#
# Examples:
#   path=$(get_peer_state_file_path "NYC" "203.0.113.1" "failure_count")
#   # Returns: ${STATE_DIR}/failure_counter_NYC_203_0_113_1
#   path=$(get_peer_state_file_path "NYC" "203.0.113.1" "last_bytes")
#   # Returns: ${STATE_DIR}/last_bytes_NYC_203_0_113_1
#   path=$(get_peer_state_file_path "" "203.0.113.1" "connection_name")
#   # Returns: ${STATE_DIR}/connection_name_203_0_113_1
#
# Note:
#   Requires LOGS_DIR, STATE_DIR, sanitize_location_name (from common.sh), and sanitize_peer_ip to be set
#   Used internally by get_peer_state and set_peer_state
#   Location name is sanitized before use in filename
#   For connection_name key, location name is ignored (per-peer only, no location)
#
#   Files intentionally outside this abstraction layer (global state, not per-peer/location):
#   - RESTART_COUNT_FILE: Global restart tracking
#   - COOLDOWN_UNTIL_FILE: Global cooldown
#   - NETWORK_PARTITION_STATE_FILE: Global network partition state
#   - LOCKFILE: Global lockfile
#   - PIDFILE: Global PID file for keepalive daemon
#   See CODE_PATTERNS.md for details on when to use abstraction layer vs. global state files.
get_peer_state_file_path() {
	local location_name="$1"
	local peer_ip="$2"
	local key="$3"
	local location_sanitized
	local peer_sanitized

	# Sanitize peer IP
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")

	# Handle connection_name specially (per-peer only, no location)
	if [[ "$key" == "connection_name" ]]; then
		echo "${STATE_DIR}/connection_name_${peer_sanitized}"
		return 0
	fi

	# Sanitize location name for other keys
	location_sanitized=$(sanitize_location_name "$location_name")

	case "$key" in
	failure_count)
		echo "${STATE_DIR}/failure_counter_${location_sanitized}_${peer_sanitized}"
		;;
	last_bytes)
		echo "${STATE_DIR}/last_bytes_${location_sanitized}_${peer_sanitized}"
		;;
	spi)
		echo "${STATE_DIR}/spi_${location_sanitized}_${peer_sanitized}"
		;;
	idle_detected)
		echo "${STATE_DIR}/idle_detected_${location_sanitized}_${peer_sanitized}"
		;;
	last_status_log)
		echo "${STATE_DIR}/last_status_log_${location_sanitized}_${peer_sanitized}"
		;;
	failure_type)
		echo "${STATE_DIR}/failure_type_${location_sanitized}_${peer_sanitized}"
		;;
	recovery_method)
		echo "${STATE_DIR}/recovery_method_${location_sanitized}_${peer_sanitized}"
		;;
	*)
		handle_error "WARNING" "SYSTEM" "Unknown peer state key: $key" 0
		echo "${STATE_DIR}/${key}_${location_sanitized}_${peer_sanitized}"
		;;
	esac
}

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
		value=$(cat "$state_file" 2>/dev/null || echo "$default_value")
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
#   $1: Peer IP address
#   $2: State key name (e.g., "failure_count", "last_bytes")
#
# Returns:
#   0: Success (or file didn't exist)
#   1: Failed to delete
#
# Side effects:
#   - Removes per-peer state file if it exists
#
# Examples:
#   delete_peer_state "203.0.113.1" "failure_count"
#   delete_peer_state "203.0.113.1" "last_bytes"
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
#   $1: Peer IP address
#
# Returns:
#   0: Always succeeds (logs warnings but continues)
#
# Side effects:
#   - Removes all per-peer state files
#   - Logs warnings for any failures
#
# Examples:
#   cleanup_peer_state "203.0.113.1"
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

# Get network partition state file path
#
# Returns the full file path for the network partition state file.
# Uses NETWORK_PARTITION_STATE_FILE if set, otherwise defaults to ${STATE_DIR}/network_partition_state.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the full file path to stdout
#
# Examples:
#   state_file=$(get_network_partition_state_file)
#   # Returns: ${STATE_DIR}/network_partition_state (or NETWORK_PARTITION_STATE_FILE if set)
#
# Note:
#   Requires STATE_DIR to be set
#   Used internally by get_network_partition_state and set_network_partition_state
get_network_partition_state_file() {
	echo "${NETWORK_PARTITION_STATE_FILE:-${STATE_DIR}/network_partition_state}"
}

# Get network partition state
#
# Retrieves the current network partition state (0 = healthy, 1 = partitioned).
# Network partition state is global (not per-peer) since network issues affect all peers.
# Validates file format, recovering corrupted files automatically.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints "0" if network is healthy, "1" if partitioned
#
# Examples:
#   partition_state=$(get_network_partition_state)
#   if [[ "$partition_state" -eq 1 ]]; then
#       echo "Network is partitioned"
#   fi
#
# Note:
#   Requires get_network_partition_state_file to be set
#   Returns "0" (healthy) if file doesn't exist or is corrupted
#   Uses automatic recovery for corrupted files
get_network_partition_state() {
	local state_file
	state_file=$(get_network_partition_state_file)

	if file_exists_and_readable "$state_file"; then
		local value
		value=$(cat "$state_file" 2>/dev/null || echo "0")
		# Validate value (must be 0 or 1)
		if [[ "$value" =~ ^[01]$ ]]; then
			echo "$value"
		else
			# Corrupted file, backup and recover
			handle_error "WARNING" "SYSTEM" "Network partition state file corrupted (recovering): $state_file" 0
			recover_corrupted_state_file "$state_file" "0" "integer"
			echo "0"
		fi
	else
		echo "0"
	fi
}

# Set network partition state
#
# Sets the network partition state (0 = healthy, 1 = partitioned).
# Network partition state is global (not per-peer) since network issues affect all peers.
# Uses atomic writes for safe file operations.
#
# Arguments:
#   $1: State value (0 = healthy, 1 = partitioned)
#
# Returns:
#   0: Success
#   1: Invalid value or write failed
#
# Side effects:
#   - Updates network partition state file (atomic write)
#   - State file: ${STATE_DIR}/network_partition_state
#
# Examples:
#   set_network_partition_state 1  # Mark network as partitioned
#   set_network_partition_state 0  # Mark network as healthy
#
# Note:
#   Requires get_network_partition_state_file to be set
#   Validates value is 0 or 1 before writing
set_network_partition_state() {
	local state_value="$1"
	local state_file
	state_file=$(get_network_partition_state_file)

	# Validate value (must be 0 or 1)
	if [[ ! "$state_value" =~ ^[01]$ ]]; then
		handle_error "ERROR" "SYSTEM" "Invalid network partition state value (expected 0 or 1): $state_value" 0
		return 1
	fi

	# Atomic write
	if ! atomic_write_file "$state_file" "$state_value"; then
		handle_error "ERROR" "SYSTEM" "Failed to update network partition state file: $state_file" 0
		return 1
	fi

	return 0
}

# Get timestamp plus N minutes
#
# Returns a Unix timestamp (seconds since epoch) that is N minutes in the future.
# Used for calculating cooldown expiration times.
#
# Arguments:
#   $1: Number of minutes to add (integer)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the future timestamp (integer) to stdout
#
# Examples:
#   future_time=$(get_timestamp_plus_minutes 15)
#   echo "Cooldown expires at: $future_time"
#
# Note:
#   Uses Linux date format (-d "+N minutes")
#   Falls back to manual calculation if date fails: $(get_unix_timestamp) + minutes * SECONDS_PER_MINUTE
get_timestamp_plus_minutes() {
	local minutes="$1"
	local seconds_to_add=$((minutes * SECONDS_PER_MINUTE))
	# Use Linux date format, fallback to manual calculation
	# +%s: output as seconds since epoch
	date -d "+${minutes} minutes" +%s 2>/dev/null || safe_timestamp_add "$(get_unix_timestamp)" "$seconds_to_add" 2>/dev/null || {
		handle_error "ERROR" "SYSTEM" "Failed to calculate future timestamp (overflow or invalid input)" 0
		echo "$(get_unix_timestamp)" # Fallback to current time
	}
}

# Get file modification time as timestamp
#
# Returns the file modification time as a Unix timestamp (seconds since epoch).
# Handles Linux and BSD/macOS stat command differences with fallbacks.
# Used for checking lockfile age and stale file detection.
#
# Arguments:
#   $1: File path to get modification time for
#
# Returns:
#   0: Always succeeds (returns "0" if stat fails)
#
# Output:
#   Prints the modification timestamp (integer) to stdout, or "0" if unavailable
#
# Examples:
#   mtime=$(get_file_mtime "$lockfile")
#   age=$((now - mtime))
#
# Note:
#   Tries Linux stat format first (-c %Y), then BSD/macOS format (-f %m)
#   Returns "0" if both fail (file doesn't exist or stat unavailable)
get_file_mtime() {
	local file="$1"
	# Try Linux stat format first, then BSD/macOS format
	# -c %Y: Linux format, modification time as seconds since epoch
	# -f %m: BSD/macOS format, modification time as seconds since epoch
	stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
}

# Check if we're in cooldown period
#
# Verifies if the script is currently in a cooldown period after a restart.
# Cooldown periods prevent immediate re-restarts and allow VPN to stabilize.
# Compares current time to cooldown expiration timestamp.
#
# Returns:
#   0: Currently in cooldown period (should exit script)
#   1: Not in cooldown (cooldown expired or doesn't exist)
#
# Side effects:
#   - Removes cooldown file if it has expired
#   - Logs remaining cooldown time if still active
#
# Examples:
#   if check_cooldown; then
#       echo "In cooldown, exiting"
#       exit 0
#   fi
#
# Note:
#   Requires COOLDOWN_UNTIL_FILE and log_message to be set (from config.sh and logging.sh)
#   Cooldown file contains Unix timestamp of expiration time
#   Calculates remaining time and logs it if in cooldown
check_cooldown() {
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	# Check if file is readable before attempting to read
	if ! file_exists_and_readable "$COOLDOWN_UNTIL_FILE"; then
		handle_error "WARNING" "SYSTEM" "Cooldown file is not readable, removing: $COOLDOWN_UNTIL_FILE" 0
		rm -f "$COOLDOWN_UNTIL_FILE" 2>/dev/null || true
		return 1 # Not in cooldown (file unreadable, treat as no cooldown)
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE" 2>/dev/null || echo "0")
	local now
	now=$(get_unix_timestamp)

	if [[ "$now" -lt "$cooldown_until" ]]; then
		local remaining
		remaining=$(safe_timestamp_diff "$cooldown_until" "$now" 2>/dev/null || echo "0")
		# Ensure remaining is non-negative (should be if now < cooldown_until, but validate)
		if [[ $remaining -lt 0 ]]; then
			remaining=0
		fi
		log_message "INFO" "SYSTEM" "In cooldown period, $remaining seconds remaining"
		return 0 # In cooldown
	else
		# Cooldown expired, remove file
		rm -f "$COOLDOWN_UNTIL_FILE"
		return 1 # Not in cooldown
	fi
}

# Set cooldown period
#
# Sets a cooldown period to prevent immediate re-restarts after a full restart.
# The cooldown period is stored as a Unix timestamp in COOLDOWN_UNTIL_FILE.
# Calculates expiration time as current time + duration minutes.
#
# Arguments:
#   $1: Cooldown duration in minutes (integer)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Creates/updates COOLDOWN_UNTIL_FILE with expiration timestamp (atomic write)
#   - Logs cooldown period setting
#
# Examples:
#   set_cooldown 15
#   # Sets cooldown for 15 minutes from now
#
# Note:
#   Requires COOLDOWN_UNTIL_FILE, get_timestamp_plus_minutes, and log_message to be set
#   Cooldown file contains single Unix timestamp (seconds since epoch)
#   Uses temporary file and mv for atomic write to prevent corruption on interruption
set_cooldown() {
	local minutes="$1"
	local cooldown_until
	cooldown_until=$(get_timestamp_plus_minutes "$minutes")
	# Atomic write: write to temp file first, then rename
	if ! atomic_write_file "$COOLDOWN_UNTIL_FILE" "$cooldown_until"; then
		handle_error "ERROR" "SYSTEM" "Failed to set cooldown period (file: $COOLDOWN_UNTIL_FILE)" 0
		# Continue execution but log the error
		return 0
	fi

	log_message "INFO" "SYSTEM" "Cooldown period set for $minutes minutes"
}

# Check rate limiting
#
# Verifies if the maximum number of restarts per hour has been exceeded.
# Prevents restart loops by limiting how frequently full restarts can occur.
# Counts restart timestamps in RESTART_COUNT_FILE within the last hour.
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Rate limit exceeded (restart blocked)
#
# Side effects:
#   - Logs warning if rate limit exceeded (includes reset time, countdown, and restart list)
#   - Reads RESTART_COUNT_FILE to count recent restarts
#
# Examples:
#   if ! check_rate_limit; then
#       echo "Rate limit exceeded, skipping restart"
#       return 1
#   fi
#
# Note:
#   Checks RESTART_COUNT_FILE for timestamps within the last hour
#   Requires RESTART_COUNT_FILE, MAX_RESTARTS_PER_HOUR, SECONDS_PER_HOUR, get_formatted_timestamp,
#   safe_timestamp_add, safe_timestamp_diff, and handle_error to be set
#   Uses awk to filter timestamps > (now - SECONDS_PER_HOUR)
#   Counts filtered lines with wc -l
#   When rate limit is exceeded, logs detailed information including:
#   - Reset timestamp (when oldest restart will expire)
#   - Countdown (time remaining until reset)
#   - List of restart timestamps that count toward the limit
check_rate_limit() {
	local now
	now=$(get_unix_timestamp)
	local one_hour_ago
	one_hour_ago=$(safe_timestamp_subtract "$now" "$SECONDS_PER_HOUR" 2>/dev/null || echo "0")

	# Get restart count file (format: timestamp per line)
	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	# Check if file is readable before attempting to read
	if ! file_exists_and_readable "$RESTART_COUNT_FILE"; then
		handle_error "WARNING" "SYSTEM" "Restart count file is not readable, treating as empty: $RESTART_COUNT_FILE" 0
		return 0 # Allow restart (file unreadable, treat as no previous restarts)
	fi

	# Get all restart timestamps within the last hour (sorted)
	# awk filters timestamps > one_hour_ago, sort -n sorts numerically
	local recent_timestamps
	recent_timestamps=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | sort -n)

	# Count recent restarts
	local recent_restarts
	recent_restarts=$(echo "$recent_timestamps" | grep -c . || echo "0")

	if [[ "$recent_restarts" -ge "$MAX_RESTARTS_PER_HOUR" ]]; then
		# Find oldest restart timestamp (first in sorted list)
		local oldest_restart
		oldest_restart=$(echo "$recent_timestamps" | head -n 1)

		# Calculate when rate limit will reset (oldest restart + 1 hour)
		local reset_timestamp
		reset_timestamp=$(safe_timestamp_add "$oldest_restart" "$SECONDS_PER_HOUR" 2>/dev/null || echo "0")

		# Calculate countdown (time remaining until reset)
		local countdown_seconds
		countdown_seconds=$(safe_timestamp_diff "$reset_timestamp" "$now" 2>/dev/null || echo "0")
		# Clamp negative values to 0 (shouldn't happen, but handle edge cases like clock skew)
		if [[ "$countdown_seconds" -lt 0 ]]; then
			countdown_seconds=0
		fi

		# Format reset timestamp for human readability
		local reset_formatted
		if [[ "$reset_timestamp" != "0" ]] && validate_timestamp "$reset_timestamp"; then
			reset_formatted=$(date -d "@$reset_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
		else
			reset_formatted="unknown"
		fi

		# Format countdown as minutes:seconds or just seconds
		local countdown_formatted
		if [[ "$countdown_seconds" -gt 0 ]]; then
			local minutes=$((countdown_seconds / 60))
			local seconds=$((countdown_seconds % 60))
			if [[ $minutes -gt 0 ]]; then
				countdown_formatted="${minutes}m ${seconds}s"
			else
				countdown_formatted="${seconds}s"
			fi
		else
			countdown_formatted="0s"
		fi

		# Format restart timestamps for logging (limit to first 10 to avoid overly long messages)
		local restart_list=""
		local restart_count=0
		while IFS= read -r timestamp || [[ -n "$timestamp" ]]; do
			[[ -z "$timestamp" ]] && continue
			if [[ $restart_count -lt 10 ]]; then
				local formatted_ts
				formatted_ts=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")
				if [[ -n "$restart_list" ]]; then
					restart_list="${restart_list}, ${formatted_ts}"
				else
					restart_list="${formatted_ts}"
				fi
			fi
			restart_count=$((restart_count + 1))
		done <<<"$recent_timestamps"

		# Add indicator if there are more restarts
		if [[ $restart_count -gt 10 ]]; then
			restart_list="${restart_list} (and $((restart_count - 10)) more)"
		fi

		# Build detailed error message
		local error_msg="Rate limit exceeded: $recent_restarts restarts in last hour (max: $MAX_RESTARTS_PER_HOUR)"
		error_msg="${error_msg}. Reset at: $reset_formatted (in $countdown_formatted)"
		if [[ -n "$restart_list" ]]; then
			error_msg="${error_msg}. Recent restarts: $restart_list"
		fi

		handle_error "WARNING" "SYSTEM" "$error_msg"
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

# Record restart timestamp
#
# Records the current timestamp to RESTART_COUNT_FILE for rate limiting.
# Also cleans up old entries (older than 24 hours) to prevent file growth.
# Each restart adds a new line with Unix timestamp.
#
# Returns:
#   0: Always succeeds (logs warnings on errors but continues)
#
# Side effects:
#   - Reads current RESTART_COUNT_FILE content (if exists and readable)
#   - Appends current Unix timestamp to content in memory
#   - Filters content to keep only entries from last 24 hours
#   - Atomically writes updated content to RESTART_COUNT_FILE using atomic_write_file
#   - Logs warnings if read, filter, or write operations fail
#
# Examples:
#   record_restart
#   # Adds current timestamp to restart count file atomically
#
# Note:
#   Requires RESTART_COUNT_FILE, SECONDS_PER_DAY, file_exists_and_readable, atomic_write_file,
#   and handle_error to be set (from config.sh, constants.sh, common.sh, and logging.sh)
#   File format: one Unix timestamp per line
#   Cleanup uses awk to filter timestamps > (now - SECONDS_PER_DAY)
#   Fully atomic operation: read-modify-write pattern with error handling
record_restart() {
	local timestamp
	timestamp=$(get_unix_timestamp)

	# Read current file content (if it exists and is readable)
	# Append new timestamp to content in memory, then filter and write atomically
	local current_content
	if file_exists_and_readable "$RESTART_COUNT_FILE"; then
		current_content=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "")
		# Trim trailing newlines to avoid creating empty lines when appending
		# Remove all trailing newlines using parameter expansion
		while [[ "$current_content" == *$'\n' ]]; do
			current_content="${current_content%$'\n'}"
		done
	else
		current_content=""
	fi

	# Append new timestamp to content
	local updated_content
	if [[ -n "$current_content" ]]; then
		updated_content="${current_content}"$'\n'"${timestamp}"
	else
		updated_content="${timestamp}"
	fi

	# Keep only last 24 hours of timestamps (cleanup old entries)
	# Prevents restart count file from growing indefinitely
	local one_day_ago
	one_day_ago=$(safe_timestamp_subtract "$timestamp" "$SECONDS_PER_DAY" 2>/dev/null || echo "0")
	# awk filters lines where first field (timestamp) > cutoff
	local filtered_content
	filtered_content=$(echo "$updated_content" | awk -v cutoff="$one_day_ago" '$1 > cutoff' 2>/dev/null)
	if [[ $? -ne 0 ]]; then
		handle_error "WARNING" "SYSTEM" "Failed to filter old restart timestamps"
		return 0 # Continue even if filtering fails
	fi

	# Atomic write: write entire file atomically with error checking
	if ! atomic_write_file "$RESTART_COUNT_FILE" "$filtered_content"; then
		handle_error "WARNING" "SYSTEM" "Failed to record restart timestamp in $RESTART_COUNT_FILE"
		return 0 # Continue even if write fails
	fi
}

# Backup corrupted state file
#
# Creates a backup of a corrupted state file before resetting it.
# Backup file is named with pattern: ${state_file}.corrupted.<timestamp>
#
# Arguments:
#   $1: State file path to backup
#
# Returns:
#   0: Success (backup created or file doesn't exist)
#   1: Failed to create backup
#
# Side effects:
#   - Creates backup file: ${state_file}.corrupted.<timestamp>
#   - Logs backup creation
#
# Examples:
#   backup_corrupted_state_file "$state_file"
#   # Creates: state_file.corrupted.1703616000
#
# Note:
#   Uses get_unix_timestamp() for backup filename timestamp
#   Backup files can be used for forensic analysis or manual recovery
backup_corrupted_state_file() {
	local state_file="$1"
	local max_attempts="${2:-3}"
	local attempt=1
	local timestamp
	timestamp=$(get_unix_timestamp)
	local backup_file="${state_file}.corrupted.${timestamp}"

	# If file doesn't exist, nothing to backup
	if [[ ! -f "$state_file" ]]; then
		return 0
	fi

	# If file is not readable, skip backup but allow recovery to proceed
	# Recovery can still remove or overwrite unreadable files
	if ! file_exists_and_readable "$state_file"; then
		handle_error "WARNING" "SYSTEM" "Cannot backup unreadable state file (skipping backup): $state_file" 0
		return 1
	fi

	# Attempt backup with retries
	while [[ $attempt -le $max_attempts ]]; do
		# Create backup of state file
		if cp "$state_file" "$backup_file" 2>/dev/null; then
			handle_error "INFO" "SYSTEM" "Backed up corrupted state file: $state_file -> $backup_file" 0
			return 0
		fi

		# If this isn't the last attempt, try again with a new timestamp
		if [[ $attempt -lt $max_attempts ]]; then
			timestamp=$(get_unix_timestamp)
			backup_file="${state_file}.corrupted.${timestamp}"
			handle_error "WARNING" "SYSTEM" "Backup attempt $attempt failed, retrying: $state_file" 0
			attempt=$((attempt + 1))
		else
			handle_error "ERROR" "SYSTEM" "Failed to backup corrupted state file after $max_attempts attempts: $state_file" 0
			return 1
		fi
	done

	return 1
}

# Recover corrupted state file
#
# Backs up a corrupted state file and resets it to a default value.
# This function should be called when corruption is detected to preserve
# the corrupted file for analysis while resetting to a safe default.
#
# Arguments:
#   $1: State file path to recover
#   $2: Default value to set (optional, defaults to empty string which removes file)
#   $3: Expected format type for validation ("integer", "timestamp", "timestamp_list") (optional)
#
# Returns:
#   0: Success (file backed up and reset)
#   1: Failed to backup (preserves corrupted file) or reset
#
# Side effects:
#   - Creates backup of corrupted file (see backup_corrupted_state_file)
#   - Resets file to default value (or removes if default is empty)
#   - Logs recovery action
#
# Examples:
#   recover_corrupted_state_file "$counter_file" "0" "integer"
#   # Backs up corrupted file, then sets to "0"
#
#   recover_corrupted_state_file "$cooldown_file" ""
#   # Backs up corrupted file, then removes it
#
# Note:
#   If default value is empty string, file is removed instead of reset
#   If backup fails for a readable file, recovery is aborted to preserve corrupted file
#   If file is unreadable, recovery proceeds (cannot backup unreadable files)
recover_corrupted_state_file() {
	local state_file="$1"
	local default_value="${2:-}"
	local expected_format="${3:-integer}"

	# Check if file exists and is readable before attempting backup
	local file_is_readable=0
	if [[ -f "$state_file" ]] && file_exists_and_readable "$state_file"; then
		file_is_readable=1
	fi

	# Backup corrupted file first (with retry logic)
	# If file is readable and backup fails, abort recovery to preserve corrupted file
	if [[ $file_is_readable -eq 1 ]]; then
		if ! backup_corrupted_state_file "$state_file"; then
			handle_error "ERROR" "SYSTEM" "Failed to backup corrupted file before recovery (preserving corrupted file): $state_file" 0
			return 1
		fi
	fi

	# Reset file to default value
	if [[ -z "$default_value" ]]; then
		# Remove file if default is empty
		rm -f "$state_file" 2>/dev/null || true
		if [[ $file_is_readable -eq 1 ]]; then
			handle_error "INFO" "SYSTEM" "Recovered corrupted state file by removal: $state_file" 0
		else
			handle_error "INFO" "SYSTEM" "Recovered unreadable corrupted state file by removal: $state_file" 0
		fi
	else
		# If file is unreadable, remove it first before writing (atomic_write_file can overwrite, but this is safer)
		if [[ -f "$state_file" ]] && ! file_exists_and_readable "$state_file"; then
			rm -f "$state_file" 2>/dev/null || true
		fi
		# Set file to default value using atomic write
		if ! atomic_write_file "$state_file" "$default_value"; then
			handle_error "ERROR" "SYSTEM" "Failed to reset corrupted state file: $state_file" 0
			return 1
		fi

		if [[ $file_is_readable -eq 1 ]]; then
			handle_error "INFO" "SYSTEM" "Recovered corrupted state file by reset to default: $state_file (value: $default_value)" 0
		else
			handle_error "INFO" "SYSTEM" "Recovered unreadable corrupted state file by reset to default: $state_file (value: $default_value)" 0
		fi
	fi

	return 0
}

# Validate state file format
#
# Validates that a state file exists, is readable, and contains valid format.
# Checks for corruption and ensures file format matches expected type.
#
# Arguments:
#   $1: State file path to validate
#   $2: Expected format type ("integer", "timestamp", or "timestamp_list")
#
# Returns:
#   0: State file is valid
#   1: State file is invalid or corrupted
#
# Side effects:
#   Logs warnings if state file is corrupted
#
# Examples:
#   validate_state_file "$RESTART_COUNT_FILE" "timestamp_list"
#   validate_state_file "$counter_file" "integer"
#
# Note:
#   Requires log_message to be available (from logging.sh)
validate_state_file() {
	local file="$1"
	local expected_format="${2:-integer}"

	# Check file exists and is readable
	# Use file_exists_and_readable for consistency and to prevent hangs on unreadable files
	if ! file_exists_and_readable "$file"; then
		handle_error "WARNING" "SYSTEM" "State file is not readable (cannot validate): $file" 0
		return 1
	fi

	# Validate format based on expected type
	case "$expected_format" in
	integer)
		# Should contain only digits (0-9), possibly with newlines
		if ! grep -qE '^[0-9]+$' "$file" 2>/dev/null; then
			handle_error "WARNING" "SYSTEM" "State file corrupted (expected integer): $file"
			return 1
		fi
		;;
	timestamp)
		# Should contain a single Unix timestamp (digits only)
		if ! grep -qE '^[0-9]+$' "$file" 2>/dev/null || [[ $(wc -l <"$file" 2>/dev/null || echo "0") -ne 1 ]]; then
			handle_error "WARNING" "SYSTEM" "State file corrupted (expected single timestamp): $file"
			return 1
		fi
		;;
	timestamp_list)
		# Should contain one or more Unix timestamps (one per line)
		# Empty file is valid (no restarts recorded)
		if [[ -s "$file" ]] && ! grep -qE '^[0-9]+$' "$file" 2>/dev/null; then
			handle_error "WARNING" "SYSTEM" "State file corrupted (expected timestamp list): $file"
			return 1
		fi
		;;
	*)
		handle_error "WARNING" "SYSTEM" "Unknown state file format: $expected_format"
		return 1
		;;
	esac

	return 0
}

# Validate state files matching a pattern
#
# Validates all state files matching a glob pattern in STATE_DIR.
# Automatically recovers corrupted files.
#
# Arguments:
#   $1: Glob pattern to match (e.g., "failure_counter_*")
#   $2: Expected format type ("integer", "timestamp", "timestamp_list")
#   $3: Default value for recovery (optional, defaults to "0")
#   $4: Description for error messages (e.g., "Failure counter file")
#
# Returns:
#   0: All matching files are valid (or successfully recovered)
#   1: One or more files are invalid and recovery failed
#
# Side effects:
#   - Logs warnings for corrupted state files
#   - Backs up corrupted files before recovery
#   - Resets corrupted files to safe defaults
#
# Examples:
#   validate_state_files_by_pattern "failure_counter_*" "integer" "0" "Failure counter file"
#   validate_state_files_by_pattern "last_bytes_*" "integer" "0" "Byte counter file"
#
# Note:
#   Requires STATE_DIR, validate_state_file, recover_corrupted_state_file, and handle_error
validate_state_files_by_pattern() {
	local pattern="$1"
	local expected_format="$2"
	local default_value="${3:-0}"
	local description="${4:-State file}"
	local validation_failed=0

	if ! directory_exists "$STATE_DIR"; then
		return 0
	fi

	local state_file
	for state_file in "${STATE_DIR}"/${pattern}; do
		# Check if glob matched actual files
		file_exists_and_readable "$state_file" || continue

		if ! validate_state_file "$state_file" "$expected_format"; then
			handle_error "WARNING" "SYSTEM" "$description corrupted, recovering: $state_file" 0
			recover_corrupted_state_file "$state_file" "$default_value" "$expected_format"
			validation_failed=1
		fi
	done

	return $validation_failed
}

# Validate all state files
#
# Validates all state files used by the VPN monitor for readability and format.
# Checks restart count file, cooldown file, network partition state file, and per-peer failure counters.
# Automatically recovers corrupted files by backing them up and resetting to defaults.
#
# Returns:
#   0: All state files are valid (or successfully recovered)
#   1: One or more state files are invalid and recovery failed
#
# Side effects:
#   - Logs warnings for corrupted state files
#   - Backs up corrupted files before recovery
#   - Resets corrupted files to safe defaults
#
# Note:
#   Requires RESTART_COUNT_FILE, COOLDOWN_UNTIL_FILE, LOGS_DIR, STATE_DIR, and log_message
validate_state() {
	local validation_failed=0

	# Validate restart count file (timestamp list)
	if file_exists_and_readable "$RESTART_COUNT_FILE"; then
		if ! validate_state_file "$RESTART_COUNT_FILE" "timestamp_list"; then
			handle_error "WARNING" "SYSTEM" "Restart count file corrupted, recovering: $RESTART_COUNT_FILE" 0
			recover_corrupted_state_file "$RESTART_COUNT_FILE" "" "timestamp_list"
			validation_failed=1
		fi
	fi

	# Validate cooldown file (single timestamp)
	if file_exists_and_readable "$COOLDOWN_UNTIL_FILE"; then
		if ! validate_state_file "$COOLDOWN_UNTIL_FILE" "timestamp"; then
			handle_error "WARNING" "SYSTEM" "Cooldown file corrupted, recovering: $COOLDOWN_UNTIL_FILE" 0
			recover_corrupted_state_file "$COOLDOWN_UNTIL_FILE" "" "timestamp"
			validation_failed=1
		fi
	fi

	# Validate network partition state file
	local network_partition_file
	network_partition_file=$(get_network_partition_state_file)
	if file_exists_and_readable "$network_partition_file"; then
		if ! validate_state_file "$network_partition_file" "integer"; then
			handle_error "WARNING" "SYSTEM" "Network partition state file corrupted, recovering: $network_partition_file" 0
			recover_corrupted_state_file "$network_partition_file" "0" "integer"
			validation_failed=1
		fi
	fi

	# Validate per-peer failure counter files (if any exist)
	validate_state_files_by_pattern "failure_counter_*" "integer" "0" "Failure counter file" || validation_failed=1

	# Validate per-peer byte counter files (if any exist)
	validate_state_files_by_pattern "last_bytes_*" "integer" "0" "Byte counter file" || validation_failed=1

	return $validation_failed
}
