#!/bin/bash
#
# State file management for UDM VPN Monitor
# Handles failure counters, cooldown periods, rate limiting, and restart tracking
#
# Version: 0.0.1
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	# Fallback if constants.sh not found (shouldn't happen in normal operation)
	# Only set if not already set (to avoid readonly variable errors)
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
}

# Initialize state files if they don't exist
#
# Creates required state files (restart_count) if they don't exist.
# Per-peer failure counter and byte counter files are created on-demand when needed.
# This ensures state files exist before they are accessed.
#
# State files:
#   - RESTART_COUNT_FILE: Tracks restart timestamps for rate limiting (created here)
#   - Per-peer failure counters: Created on-demand as failure_counter_<peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<peer_ip>
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   - Creates RESTART_COUNT_FILE with default value "0" if it doesn't exist
#   - Logs warning if file creation fails (but doesn't exit)
#
# Examples:
#   init_state
#   # Ensures restart count file exists before use
#
# Note:
#   Requires RESTART_COUNT_FILE, ensure_file_exists, and log_message to be set
#   Per-peer files are created on-demand by increment_failure and check_byte_counters
init_state() {
	if ! ensure_file_exists "$RESTART_COUNT_FILE" "0"; then
		handle_error "WARNING" "Failed to create restart count file"
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

# Get current failure counter for a specific peer
#
# Reads the current consecutive failure count from the per-peer state file.
# Each peer has its own independent failure counter tracked separately.
# Returns 0 if file doesn't exist (first failure) or is empty/corrupted.
#
# Arguments:
#   $1: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the failure count (integer) to stdout (0 if file doesn't exist)
#
# Examples:
#   count=$(get_failure_count "203.0.113.1")
#   echo "Failure count: $count"
#
# Note:
#   Requires LOGS_DIR and sanitize_peer_ip to be set (from config.sh and state.sh)
#   Counter file: ${LOGS_DIR}/failure_counter_<sanitized_peer_ip>
#   Returns 0 if file doesn't exist (cat fails) or is empty
get_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"

	if [[ -f "$counter_file" ]]; then
		cat "$counter_file"
	else
		echo "0"
	fi
}

# Increment failure counter for a specific peer
#
# Increments the consecutive failure counter by 1 and saves it to the per-peer state file.
# Used to track how many times in a row the VPN check has failed for this specific peer.
# Each peer has its own independent failure counter tracked separately.
#
# Arguments:
#   $1: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the new failure count (integer) to stdout
#
# Side effects:
#   - Creates or updates per-peer counter file with new count (atomic write)
#   - Counter file: ${LOGS_DIR}/failure_counter_<sanitized_peer_ip>
#
# Examples:
#   new_count=$(increment_failure "203.0.113.1")
#   echo "Failure count incremented to: $new_count"
#
# Note:
#   Requires LOGS_DIR and get_failure_count to be set (from config.sh and state.sh)
#   Reads current count, increments by 1, writes back to file atomically
#   Uses temporary file and mv for atomic write to prevent corruption on interruption
increment_failure() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	local count
	count=$(get_failure_count "$peer_ip")
	local new_count=$((count + 1))
	# Atomic write: write to temp file first, then rename
	if ! (echo "$new_count" >"${counter_file}.tmp" && mv "${counter_file}.tmp" "$counter_file"); then
		handle_error "ERROR" "Failed to update failure counter for $peer_ip" 0
		# Continue execution but log the error
	fi
	echo "$new_count"
}

# Reset failure counter for a specific peer
#
# Resets the consecutive failure counter to 0 for the specified peer.
# Called when VPN check succeeds after previous failures for this peer.
# Each peer has its own independent failure counter tracked separately.
#
# Arguments:
#   $1: Peer IP address (used to locate per-peer counter file)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Writes "0" to per-peer counter file (atomic write)
#   - Counter file: ${LOGS_DIR}/failure_counter_<sanitized_peer_ip>
#
# Examples:
#   reset_failure_count "203.0.113.1"
#   # Resets counter to 0 for this peer
#
# Note:
#   Requires LOGS_DIR and sanitize_peer_ip to be set (from config.sh and state.sh)
#   Called when VPN recovers after failures
#   Uses temporary file and mv for atomic write to prevent corruption on interruption
reset_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	# Atomic write: write to temp file first, then rename
	if ! (echo "0" >"${counter_file}.tmp" && mv "${counter_file}.tmp" "$counter_file"); then
		handle_error "ERROR" "Failed to reset failure counter for $peer_ip" 0
		# Continue execution but log the error
	fi
}

# Get timestamp plus N minutes
#
# Returns a Unix timestamp (seconds since epoch) that is N minutes in the future.
# Handles Linux and BSD/macOS date command differences with fallbacks.
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
#   Tries Linux date format first (-d "+N minutes"), then BSD/macOS (-v+"N"M)
#   Falls back to manual calculation if both fail: $(date +%s) + minutes * 60
get_timestamp_plus_minutes() {
	local minutes="$1"
	# Try Linux date format first, then BSD/macOS, fallback to manual calculation
	# +%s: output as seconds since epoch
	date -d "+${minutes} minutes" +%s 2>/dev/null || date -v+"${minutes}"M +%s 2>/dev/null || echo $(($(date +%s) + minutes * 60))
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

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ "$now" -lt "$cooldown_until" ]]; then
		local remaining
		remaining=$((cooldown_until - now))
		log_message "INFO" "In cooldown period, $remaining seconds remaining"
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
	if ! (echo "$cooldown_until" >"${COOLDOWN_UNTIL_FILE}.tmp" && mv "${COOLDOWN_UNTIL_FILE}.tmp" "$COOLDOWN_UNTIL_FILE"); then
		handle_error "ERROR" "Failed to set cooldown period (file: $COOLDOWN_UNTIL_FILE)" 0
		# Continue execution but log the error
	fi
	log_message "INFO" "Cooldown period set for $minutes minutes"
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
#   - Logs warning if rate limit exceeded
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
#   Requires RESTART_COUNT_FILE, MAX_RESTARTS_PER_HOUR, SECONDS_PER_HOUR, and log_message to be set
#   Uses awk to filter timestamps > (now - SECONDS_PER_HOUR)
#   Counts filtered lines with wc -l
check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - SECONDS_PER_HOUR))

	# Get restart count file (format: timestamp per line)
	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	# Count restarts in the last hour
	# awk filters timestamps > one_hour_ago, wc -l counts lines, tr removes whitespace
	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ "$recent_restarts" -ge "$MAX_RESTARTS_PER_HOUR" ]]; then
		handle_error "WARNING" "Rate limit exceeded: $recent_restarts restarts in last hour (max: $MAX_RESTARTS_PER_HOUR)"
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
#   0: Always succeeds
#
# Side effects:
#   - Appends current Unix timestamp to RESTART_COUNT_FILE
#   - Removes entries older than 24 hours from RESTART_COUNT_FILE (cleanup)
#   - Uses temporary file for atomic update during cleanup
#   - Logs warnings if cleanup operations fail
#
# Examples:
#   record_restart
#   # Adds current timestamp to restart count file
#
# Note:
#   Requires RESTART_COUNT_FILE, SECONDS_PER_DAY, and log_message to be set (from config.sh, constants.sh, and logging.sh)
#   File format: one Unix timestamp per line
#   Cleanup uses awk to filter timestamps > (now - SECONDS_PER_DAY)
#   Atomic update via temp file and mv with error handling
record_restart() {
	local timestamp
	timestamp=$(date +%s)
	echo "$timestamp" >>"$RESTART_COUNT_FILE"

	# Keep only last 24 hours of timestamps (cleanup old entries)
	# Prevents restart count file from growing indefinitely
	local one_day_ago
	one_day_ago=$((timestamp - SECONDS_PER_DAY))
	# awk filters lines where first field (timestamp) > cutoff, writes to temp file
	if ! awk -v cutoff="$one_day_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" >"${RESTART_COUNT_FILE}.tmp" 2>/dev/null; then
		handle_error "WARNING" "Failed to filter old restart timestamps from $RESTART_COUNT_FILE"
		rm -f "${RESTART_COUNT_FILE}.tmp" 2>/dev/null || true
		return 0 # Continue even if cleanup fails
	fi

	# Atomic move: replace original file with filtered version
	if ! mv "${RESTART_COUNT_FILE}.tmp" "$RESTART_COUNT_FILE" 2>/dev/null; then
		handle_error "WARNING" "Failed to update restart count file $RESTART_COUNT_FILE (cleanup skipped, file may grow)"
		rm -f "${RESTART_COUNT_FILE}.tmp" 2>/dev/null || true
		return 0 # Continue even if cleanup fails
	fi
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

	# Check file exists
	if [[ ! -f "$file" ]]; then
		return 1
	fi

	# Check file is readable
	if [[ ! -r "$file" ]]; then
		handle_error "WARNING" "State file is not readable: $file"
		return 1
	fi

	# Validate format based on expected type
	case "$expected_format" in
	integer)
		# Should contain only digits (0-9), possibly with newlines
		if ! grep -qE '^[0-9]+$' "$file" 2>/dev/null; then
			handle_error "WARNING" "State file corrupted (expected integer): $file"
			return 1
		fi
		;;
	timestamp)
		# Should contain a single Unix timestamp (digits only)
		if ! grep -qE '^[0-9]+$' "$file" 2>/dev/null || [[ $(wc -l <"$file" 2>/dev/null || echo "0") -ne 1 ]]; then
			handle_error "WARNING" "State file corrupted (expected single timestamp): $file"
			return 1
		fi
		;;
	timestamp_list)
		# Should contain one or more Unix timestamps (one per line)
		# Empty file is valid (no restarts recorded)
		if [[ -s "$file" ]] && ! grep -qE '^[0-9]+$' "$file" 2>/dev/null; then
			handle_error "WARNING" "State file corrupted (expected timestamp list): $file"
			return 1
		fi
		;;
	*)
		handle_error "WARNING" "Unknown state file format: $expected_format"
		return 1
		;;
	esac

	return 0
}

# Validate all state files
#
# Validates all state files used by the VPN monitor for readability and format.
# Checks restart count file, cooldown file, and per-peer failure counters.
#
# Returns:
#   0: All state files are valid
#   1: One or more state files are invalid
#
# Side effects:
#   Logs warnings for corrupted state files
#
# Note:
#   Requires RESTART_COUNT_FILE, COOLDOWN_UNTIL_FILE, LOGS_DIR, and log_message
validate_state() {
	local validation_failed=0

	# Validate restart count file (timestamp list)
	if [[ -f "$RESTART_COUNT_FILE" ]]; then
		if ! validate_state_file "$RESTART_COUNT_FILE" "timestamp_list"; then
			validation_failed=1
		fi
	fi

	# Validate cooldown file (single timestamp)
	if [[ -f "$COOLDOWN_UNTIL_FILE" ]]; then
		if ! validate_state_file "$COOLDOWN_UNTIL_FILE" "timestamp"; then
			validation_failed=1
		fi
	fi

	# Validate per-peer failure counter files (if any exist)
	if [[ -d "$LOGS_DIR" ]]; then
		local counter_file
		for counter_file in "${LOGS_DIR}"/failure_counter_*; do
			# Check if glob matched actual files
			[[ -f "$counter_file" ]] || continue

			if ! validate_state_file "$counter_file" "integer"; then
				validation_failed=1
			fi
		done
	fi

	return $validation_failed
}
