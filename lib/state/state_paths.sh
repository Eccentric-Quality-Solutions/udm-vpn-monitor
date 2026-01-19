#!/bin/bash
#
# State file path management
# Handles path generation and sanitization for state files
#
# Version: 0.6.0
#

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
#   Requires STATE_DIR, sanitize_location_name (from common.sh), and sanitize_peer_ip to be set
#   STATE_DIR must be set before this function is called (validated during module load and state initialization).
#   If STATE_DIR is unset, this function will produce invalid absolute paths starting with "/".
#   The module logs a warning if STATE_DIR is unset when state_paths.sh is sourced.
#   Used internally by get_peer_state and set_peer_state.
#   Location name is sanitized before use in filename.
#   For connection_name key, location name is ignored (per-peer only, no location).
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

# Get network partition state file path
#
# Returns the full file path for the network partition state file.
# Uses NETWORK_PARTITION_STATE_FILE if set, otherwise defaults to ${STATE_DIR}/network_partition_state.
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
#   state_file=$(get_network_partition_state_file)
#   # Returns: ${STATE_DIR}/network_partition_state (or NETWORK_PARTITION_STATE_FILE if set)
#
# Note:
#   Requires STATE_DIR to be set (validated during module load and state initialization).
#   If STATE_DIR is unset and NETWORK_PARTITION_STATE_FILE is also unset, this function will produce
#   an invalid absolute path starting with "/".
#   The module logs a warning if STATE_DIR is unset when state_paths.sh is sourced.
#   Used internally by get_network_partition_state and set_network_partition_state.
get_network_partition_state_file() {
	echo "${NETWORK_PARTITION_STATE_FILE:-${STATE_DIR}/network_partition_state}"
}

# Module-level validation: Check that STATE_DIR is set
# This provides fail-fast detection if STATE_DIR is unset when the module loads.
# In normal operation, STATE_DIR is set during config loading before state modules are sourced.
# This check logs a warning but does not exit, allowing the caller to decide how to handle it.
if [[ -z "${STATE_DIR:-}" ]]; then
	# Use handle_error if available (from logging.sh), otherwise fall back to echo
	# This allows the module to be sourced even if logging isn't fully initialized
	if type handle_error >/dev/null 2>&1; then
		handle_error "WARNING" "SYSTEM" "STATE_DIR is not set when loading state_paths.sh - state path functions may produce invalid paths" 0
	else
		echo "Warning: STATE_DIR is not set when loading state_paths.sh" >&2
	fi
fi
