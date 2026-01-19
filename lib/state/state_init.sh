#!/bin/bash
#
# State initialization
# Handles initialization of state files and directories
#
# Version: 0.6.0
#

# Initialize state files if they don't exist
#
# Creates required state files (restart_count) if they don't exist.
# Per-peer failure counter and byte counter files are created on-demand when needed.
# This ensures state files exist before they are accessed.
#
# State files:
#   - RESTART_COUNT_FILE: Tracks restart timestamps for rate limiting (created here)
#   - Network partition state file: Tracks network partition status (path from get_network_partition_state_file())
#   - System-wide failure state file: Tracks system-wide failure status (path from get_system_wide_failure_state_file(), created if function available)
#   - Per-peer failure counters: Created on-demand as failure_counter_<peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<peer_ip>
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   - Creates RESTART_COUNT_FILE with default value "0" if it doesn't exist
#   - Creates network partition state file with default value "0" if it doesn't exist (path from get_network_partition_state_file())
#   - Creates system-wide failure state file with default value "0" if it doesn't exist and function is available (path from get_system_wide_failure_state_file())
#   - Logs warning if file creation fails (but doesn't exit)
#
# Examples:
#   init_state
#   # Ensures restart count file exists before use
#
# Note:
#   Requires RESTART_COUNT_FILE, STATE_DIR, LOGS_DIR, ensure_file_exists, try_ensure_directory_exists,
#   get_network_partition_state_file, handle_error, and log_message to be set
#   get_system_wide_failure_state_file is optional (checked with command -v)
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
	# Initialize system-wide failure state file (0 = no failure, 1 = system-wide failure detected)
	if command -v get_system_wide_failure_state_file >/dev/null 2>&1; then
		local system_wide_failure_file
		system_wide_failure_file=$(get_system_wide_failure_state_file)
		if ! ensure_file_exists "$system_wide_failure_file" "0"; then
			handle_error "WARNING" "SYSTEM" "Failed to create system-wide failure state file"
		fi
	fi
	# Per-peer failure counters and byte counters are created on-demand
}
