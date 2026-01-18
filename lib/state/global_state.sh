#!/bin/bash
#
# Global state operations
# Handles rate limiting, restart tracking, and state validation
#
# Version: 0.6.0
#

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

# Check rate limiting
#
# Verifies if the maximum number of Tier 3 restarts within the configured window has been exceeded,
# and checks if minimum restart interval has elapsed since the last restart.
# Prevents restart loops by limiting how frequently Tier 3 recovery actions (full IPsec restarts)
# can occur. Uses a sliding window to count restart timestamps in RESTART_COUNT_FILE.
#
# During system-wide failures, the coordinator location bypasses the window limit (but still
# enforces minimum interval) to allow necessary recovery attempts during infrastructure outages.
#
# Arguments:
#   $1: Optional location name (used to check if this location is the coordinator during system-wide failures)
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Rate limit exceeded or minimum interval not met (restart blocked)
#
# Side effects:
#   - Logs warning if rate limit exceeded (includes reset time, countdown, and restart list)
#   - Logs warning if minimum interval not met
#   - Logs info if coordinator bypasses window limit during system-wide failure
#   - Reads RESTART_COUNT_FILE to count recent restarts
#
# Examples:
#   if ! check_rate_limit; then
#       echo "Rate limit exceeded, skipping restart"
#       return 1
#   fi
#   if ! check_rate_limit "NYC"; then
#       echo "Rate limit exceeded for NYC"
#       return 1
#   fi
#
# Note:
#   Checks RESTART_COUNT_FILE for timestamps within the configured window
#   Requires RESTART_COUNT_FILE, MAX_RESTARTS_PER_WINDOW, RATE_LIMIT_WINDOW_MINUTES,
#   MIN_RESTART_INTERVAL_SECONDS, SECONDS_PER_MINUTE, get_formatted_timestamp,
#   safe_timestamp_add, safe_timestamp_diff, and handle_error to be set
#   Uses awk to filter timestamps > (now - window_seconds)
#   Counts filtered lines with wc -l
#   When rate limit is exceeded, logs detailed information including:
#   - Reset timestamp (when oldest restart will expire)
#   - Countdown (time remaining until reset)
#   - List of restart timestamps that count toward the limit
#   Coordinator bypass: If location is coordinator during system-wide failure, window limit is bypassed
#   but minimum interval is still enforced to protect system stability
check_rate_limit() {
	local location_name="${1:-}"
	local now
	now=$(get_unix_timestamp)

	# Get configured window size in seconds
	local window_minutes="${RATE_LIMIT_WINDOW_MINUTES:-60}"
	# Validate window size (defensive check)
	if [[ ! "$window_minutes" =~ ^[0-9]+$ ]] || [[ "$window_minutes" -lt 5 ]] || [[ "$window_minutes" -gt 1440 ]]; then
		handle_error "WARNING" "SYSTEM" "Invalid RATE_LIMIT_WINDOW_MINUTES=$window_minutes (range: 5-1440), using default 60"
		window_minutes=60
	fi
	local window_seconds=$((window_minutes * SECONDS_PER_MINUTE))
	local window_start
	window_start=$(safe_timestamp_subtract "$now" "$window_seconds" 2>/dev/null || echo "0")

	# Check minimum restart interval first (simpler check, clearer error message)
	local min_interval="${MIN_RESTART_INTERVAL_SECONDS:-30}"
	if [[ $min_interval -gt 0 ]]; then
		# Get restart count file (format: timestamp per line)
		if [[ -f "$RESTART_COUNT_FILE" ]] && file_exists_and_readable "$RESTART_COUNT_FILE"; then
			# Get most recent restart timestamp (maximum timestamp, handles unsorted files)
			# Sort numerically and take the last (highest) value to handle unsorted timestamps
			# Defensive timeout wrapper: file_exists_and_readable should prevent hangs, but this adds
			# extra protection for edge cases (race conditions, test suite timing issues, etc.)
			# Use helper function to standardize timeout command availability check
			local last_restart
			last_restart=$(run_with_timeout 1 sh -c "grep -E '^[0-9]+$' \"$RESTART_COUNT_FILE\" 2>/dev/null | sort -n | tail -n 1" || echo "0")
			if [[ "$last_restart" != "0" ]] && [[ "$last_restart" =~ ^[0-9]+$ ]]; then
				local time_since_last
				time_since_last=$(safe_timestamp_diff "$now" "$last_restart" 2>/dev/null || echo "0")
				if [[ "$time_since_last" -lt "$min_interval" ]]; then
					local remaining=$((min_interval - time_since_last))
					handle_error "WARNING" "SYSTEM" "Minimum restart interval not met: ${remaining} seconds remaining (minimum: ${min_interval}s, last restart: $(date -d "@$last_restart" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$last_restart"))"
					return 1 # Blocked by minimum interval
				fi
			fi
		fi
	fi

	# Get restart count file (format: timestamp per line)
	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	# Check if file is readable before attempting to read
	if ! file_exists_and_readable "$RESTART_COUNT_FILE"; then
		handle_error "WARNING" "SYSTEM" "Restart count file is not readable, treating as empty: $RESTART_COUNT_FILE" 0
		return 0 # Allow restart (file unreadable, treat as no previous restarts)
	fi

	# Check if coordinator should bypass window limit during system-wide failure
	# Coordinator bypasses window limit but still enforces minimum interval to protect system stability
	local bypass_window_limit=0
	if [[ -n "$location_name" ]]; then
		# Check if system-wide failure is detected and this location is the coordinator
		if command -v get_system_wide_failure_state >/dev/null 2>&1 &&
			command -v should_location_attempt_recovery >/dev/null 2>&1; then
			local failure_state
			failure_state=$(get_system_wide_failure_state 2>/dev/null || echo "0")
			if [[ "$failure_state" -eq 1 ]]; then
				# System-wide failure detected, check if this location is the coordinator
				if should_location_attempt_recovery "$location_name" 2>/dev/null; then
					# This location is the coordinator during system-wide failure
					# Bypass window limit but keep minimum interval enforcement
					bypass_window_limit=1
					log_message "INFO" "SYSTEM" "Coordinator $location_name bypassing rate limit window during system-wide failure (minimum interval still enforced)"
				fi
			fi
		fi
	fi

	# If coordinator bypass is active, skip window limit check
	if [[ $bypass_window_limit -eq 1 ]]; then
		return 0 # Allow restart (window limit bypassed, minimum interval already checked)
	fi

	# Get all restart timestamps within the configured window (sorted)
	# awk filters timestamps > window_start, sort -n sorts numerically
	local recent_timestamps
	recent_timestamps=$(awk -v cutoff="$window_start" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | sort -n)

	# Count recent restarts
	local recent_restarts
	recent_restarts=$(echo "$recent_timestamps" | grep -c . || echo "0")

	local max_restarts="${MAX_RESTARTS_PER_WINDOW:-3}"
	if [[ "$recent_restarts" -ge "$max_restarts" ]]; then
		# Find oldest restart timestamp (first in sorted list)
		local oldest_restart
		oldest_restart=$(echo "$recent_timestamps" | head -n 1)
		# Defensive check: if oldest_restart is empty or invalid, allow restart
		if [[ -z "$oldest_restart" ]] || [[ ! "$oldest_restart" =~ ^[0-9]+$ ]]; then
			handle_error "WARNING" "SYSTEM" "Cannot determine oldest restart timestamp, allowing restart"
			return 0
		fi

		# Calculate when rate limit will reset (oldest restart + window duration)
		local reset_timestamp
		reset_timestamp=$(safe_timestamp_add "$oldest_restart" "$window_seconds" 2>/dev/null || echo "0")

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
		local error_msg="Rate limit exceeded: $recent_restarts restarts in last ${window_minutes} minute(s) (max: $max_restarts)"
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
# Arguments:
#   None
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
	if ! filtered_content=$(echo "$updated_content" | awk -v cutoff="$one_day_ago" '$1 > cutoff' 2>/dev/null); then
		handle_error "WARNING" "SYSTEM" "Failed to filter old restart timestamps"
		return 0 # Continue even if filtering fails
	fi

	# Atomic write: write entire file atomically with error checking
	if ! atomic_write_file "$RESTART_COUNT_FILE" "$filtered_content"; then
		handle_error "WARNING" "SYSTEM" "Failed to record restart timestamp in $RESTART_COUNT_FILE"
		return 0 # Continue even if write fails
	fi
}

# Get network partition state
#
# Retrieves the current network partition state (0 = healthy, 1 = partitioned).
# Network partition state is global (not per-peer) since network issues affect all peers.
# Validates file format, recovering corrupted files automatically.
#
# Arguments:
#   None
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

	# Check if destination directory is writable before attempting backup
	# This prevents cp from hanging when directory is read-only
	local backup_dir
	backup_dir=$(dirname "$backup_file")
	if [[ ! -w "$backup_dir" ]] 2>/dev/null; then
		handle_error "WARNING" "SYSTEM" "Cannot backup state file - destination directory is not writable (skipping backup): $backup_dir" 0
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
	# Use run_with_timeout helper for consistency: file_exists_and_readable should prevent hangs,
	# but this adds extra protection for edge cases (race conditions, test suite timing issues, etc.)
	# Standardized timeout pattern: use run_with_timeout() helper instead of explicit timeout checks
	case "$expected_format" in
	integer)
		# Should contain only digits (0-9), possibly with newlines
		local grep_result=1
		run_with_timeout 1 grep -qE '^[0-9]+$' "$file" && grep_result=0 || grep_result=1
		if [[ $grep_result -ne 0 ]]; then
			handle_error "WARNING" "SYSTEM" "State file corrupted (expected integer): $file"
			return 1
		fi
		;;
	timestamp)
		# Should contain a single Unix timestamp (digits only)
		local grep_result=1
		local line_count=0
		run_with_timeout 1 grep -qE '^[0-9]+$' "$file" && grep_result=0 || grep_result=1
		line_count=$(run_with_timeout 1 wc -l <"$file" || echo "0")
		if [[ $grep_result -ne 0 ]] || [[ "$line_count" -ne 1 ]]; then
			handle_error "WARNING" "SYSTEM" "State file corrupted (expected single timestamp): $file"
			return 1
		fi
		;;
	timestamp_list)
		# Should contain one or more Unix timestamps (one per line)
		# Empty file is valid (no restarts recorded)
		if [[ -s "$file" ]]; then
			local grep_result=1
			run_with_timeout 1 grep -qE '^[0-9]+$' "$file" && grep_result=0 || grep_result=1
			if [[ $grep_result -ne 0 ]]; then
				handle_error "WARNING" "SYSTEM" "State file corrupted (expected timestamp list): $file"
				return 1
			fi
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
#   Uses a temporary file with timeout wrapper to prevent hangs when find encounters unreadable files
#   Sets an EXIT trap for temp file cleanup and clears it before returning (intentional behavior)
#   The trap ensures cleanup even on error, but is removed before function return to avoid interfering
#   with caller's traps
validate_state_files_by_pattern() {
	local pattern="$1"
	local expected_format="$2"
	local default_value="${3:-0}"
	local description="${4:-State file}"
	local validation_failed=0

	if ! directory_exists "$STATE_DIR"; then
		return 0
	fi

	# Use find to safely enumerate files matching the pattern
	# This avoids glob expansion issues with unreadable files
	# Use -readable to skip unreadable files entirely, preventing hangs when find tries to stat files with 000 permissions
	# This is more efficient and prevents hangs on some filesystems where find can block on unreadable files
	# Add timeout wrapper as additional protection (defensive programming)
	local state_file
	# Use timeout wrapper around find to prevent hangs (5 seconds should be more than enough)
	# Use a temporary file to store find output to avoid process substitution issues with timeout
	# This ensures timeout is properly applied and prevents hangs
	local find_temp_file
	find_temp_file=$(mktemp 2>/dev/null || echo "/tmp/find_output_$$")
	# Set up cleanup trap for temp file and file descriptor
	# This trap ensures cleanup even if function exits early due to error
	# Closes file descriptor 3 if opened, then removes temp file
	# Note: We clear this trap before returning (see line 756) to avoid interfering with caller's traps
	# shellcheck disable=SC2064 # We want variable expansion at trap definition time
	trap "exec 3<&- 2>/dev/null || true; rm -f \"$find_temp_file\" 2>/dev/null || true" EXIT
	# Use timeout with --kill-after to ensure find is killed if it hangs
	# Use -readable to skip unreadable files entirely (prevents hangs on files with 000 permissions)
	# Redirect output to temp file to avoid process substitution issues
	# Use helper function to standardize timeout command availability check
	run_with_timeout_kill_after 5 1 find "$STATE_DIR" -maxdepth 1 -type f -readable -name "$pattern" -print0 >"$find_temp_file" 2>/dev/null || true
	# Read from temp file using null delimiter
	# Open file descriptor 3 for reading to avoid issues with stdin
	exec 3<"$find_temp_file"
	while IFS= read -r -d '' state_file <&3 || [[ -n "$state_file" ]]; do
		[[ -z "$state_file" ]] && continue
		# File is already known to be readable (from find -readable), but double-check for safety
		if ! file_exists_and_readable "$state_file"; then
			handle_error "WARNING" "SYSTEM" "$description is unreadable (skipping validation): $state_file" 0
			continue
		fi

		if ! validate_state_file "$state_file" "$expected_format"; then
			handle_error "WARNING" "SYSTEM" "$description corrupted, recovering: $state_file" 0
			recover_corrupted_state_file "$state_file" "$default_value" "$expected_format"
			validation_failed=1
		fi
	done
	exec 3<&-
	# Clean up temp file and remove trap
	# Explicit cleanup ensures temp file is removed even if trap wasn't set
	# Clearing trap prevents interference with caller's EXIT trap handlers
	rm -f "$find_temp_file" 2>/dev/null || true
	trap - EXIT

	return $validation_failed
}

# Validate all state files
#
# Validates all state files used by the VPN monitor for readability and format.
# Checks restart count file, network partition state file, and per-peer failure counters.
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
# Arguments:
#   None
#
# Note:
#   Requires RESTART_COUNT_FILE, LOGS_DIR, STATE_DIR, and log_message
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

	# Cooldown file validation removed - cooldown functionality replaced by MIN_RESTART_INTERVAL_SECONDS

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
