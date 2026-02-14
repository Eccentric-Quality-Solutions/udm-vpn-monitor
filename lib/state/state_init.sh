#!/bin/bash
#
# State initialization
# Handles initialization of state files and directories
#
# Version: 0.8.1
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
#   - Per-peer failure counters: Created on-demand as failure_count_<location>_<external_peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<location>_<external_peer_ip>
#
# Arguments:
#   None
#
# Returns:
#   0: State initialization succeeded (warnings may be logged for non-critical failures)
#   Exits script with error code if required variables are unset (validation failure)
#
# Side effects:
#   - Creates RESTART_COUNT_FILE with default value "0" if it doesn't exist
#   - Creates network partition state file with default value "0" if it doesn't exist (path from get_network_partition_state_file())
#   - Creates system-wide failure state file with default value "0" if it doesn't exist and function is available (path from get_system_wide_failure_state_file())
#   - Logs warning if file creation fails (but doesn't exit for non-critical failures)
#   - Exits script if required variables (LOGS_DIR, STATE_DIR, RESTART_COUNT_FILE) are unset or empty
#
# Examples:
#   init_state
#   # Ensures restart count file exists before use
#
# Note:
#   Requires RESTART_COUNT_FILE, STATE_DIR, LOGS_DIR, ensure_file_exists, try_ensure_directory_exists,
#   get_network_partition_state_file, handle_error, handle_error_or_exit_fake_mode, and log_message to be set
#   get_system_wide_failure_state_file is optional (checked with command -v)
#   Per-peer files are created on-demand by increment_failure and check_byte_counters
#   Validation failures (unset required variables) cause the script to exit via handle_error_or_exit_fake_mode/die
init_state() {
	# Validate required variables (fail fast with clear errors)
	# Use handle_error_or_exit_fake_mode for consistency with codebase patterns
	# In fake mode, it returns 1; in normal mode it calls die() and never returns
	if [[ -z "${LOGS_DIR:-}" ]]; then
		if ! handle_error_or_exit_fake_mode "SYSTEM" "LOGS_DIR is not set - cannot initialize state" "${EXIT_STATE_ERROR:-6}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi
	if [[ -z "${STATE_DIR:-}" ]]; then
		if ! handle_error_or_exit_fake_mode "SYSTEM" "STATE_DIR is not set - cannot initialize state" "${EXIT_STATE_ERROR:-6}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi
	if [[ -z "${RESTART_COUNT_FILE:-}" ]]; then
		if ! handle_error_or_exit_fake_mode "SYSTEM" "RESTART_COUNT_FILE is not set - cannot initialize state" "${EXIT_STATE_ERROR:-6}"; then
			# In fake mode, handle_error_or_exit_fake_mode returns 1
			return 1
		fi
		# In normal mode, handle_error_or_exit_fake_mode calls die() and never returns
	fi

	# Ensure directories exist before creating files
	if ! try_ensure_directory_exists "$LOGS_DIR"; then
		handle_error "WARNING" "SYSTEM" "Failed to create logs directory: $LOGS_DIR" 0
	fi
	if ! try_ensure_directory_exists "$STATE_DIR"; then
		handle_error "WARNING" "SYSTEM" "Failed to create state directory: $STATE_DIR" 0
	fi

	if ! ensure_file_exists "$RESTART_COUNT_FILE" "0"; then
		handle_error "WARNING" "SYSTEM" "Failed to create restart count file: $RESTART_COUNT_FILE" 0
	fi
	# Initialize network partition state file (0 = healthy, 1 = partitioned)
	local network_partition_file
	network_partition_file=$(get_network_partition_state_file)
	if [[ -z "$network_partition_file" ]]; then
		handle_error "WARNING" "SYSTEM" "get_network_partition_state_file returned empty path (STATE_DIR may be unset)" 0
	else
		if ! ensure_file_exists "$network_partition_file" "0"; then
			handle_error "WARNING" "SYSTEM" "Failed to create network partition state file: $network_partition_file" 0
		fi
	fi
	# Initialize system-wide failure state file (0 = no failure, 1 = system-wide failure detected)
	if command -v get_system_wide_failure_state_file >/dev/null 2>&1; then
		local system_wide_failure_file
		system_wide_failure_file=$(get_system_wide_failure_state_file)
		if [[ -z "$system_wide_failure_file" ]]; then
			handle_error "WARNING" "SYSTEM" "get_system_wide_failure_state_file returned empty path (STATE_DIR may be unset)" 0
		else
			if ! ensure_file_exists "$system_wide_failure_file" "0"; then
				handle_error "WARNING" "SYSTEM" "Failed to create system-wide failure state file: $system_wide_failure_file" 0
			fi
		fi
	fi
	# Per-peer failure counters and byte counters are created on-demand
}
