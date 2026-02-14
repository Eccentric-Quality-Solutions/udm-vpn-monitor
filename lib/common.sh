#!/bin/bash
#
# Common functions for UDM VPN Monitor
# Shared logging and utility functions for installation/uninstallation scripts and main monitor
#
# Version: 0.8.0
#
# This module provides shared utility functions used throughout the codebase to reduce duplication:
# - File operations: file_exists_and_readable(), ensure_file_exists(), atomic_write_file(), read_counter_file()
# - Directory operations: directory_exists(), directory_writable()
# - Timestamp operations: get_unix_timestamp(), validate_timestamp(), safe_timestamp_subtract(), safe_timestamp_add(), safe_timestamp_diff(), calculate_duration(), start_timer(), stop_timer()
# - String escaping: escape_sed_replacement(), escape_sed_regex()
# - String sanitization: sanitize_location_name()
# - String trimming: trim()
# - Validation: validate_spi_format()
# - Config file operations: update_config_value()
# - Logging: log_info(), log_warn(), log_error()
# - System checks: check_root()
# - Path resolution: resolve_lib_dir()
#
# All modules should use these shared functions instead of duplicating logic.
# See ARCHITECTURAL_REVIEW.md section 8.3 for code duplication reduction guidelines.
#

# Colors for output (only set if not already defined to allow re-sourcing)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

# Log an informational message
#
# Logs an informational message with green [INFO] prefix to stdout.
# Used for normal operation messages and status updates.
#
# Arguments:
#   $@: Message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints colored message to stdout: "[INFO] <message>"
#
# Examples:
#   log_info "Installation started"
#   log_info "Processing file:" "$filename"
#
# Note:
#   Requires RED, GREEN, YELLOW, NC color variables to be defined
log_info() {
	echo -e "${GREEN}[INFO]${NC} $*"
}

# Log a warning message
#
# Logs a warning message with yellow [WARN] prefix to stdout.
# Used for non-critical issues that should be noted but don't stop execution.
#
# Arguments:
#   $@: Message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints colored message to stdout: "[WARN] <message>"
#
# Examples:
#   log_warn "Config file not found, using defaults"
#   log_warn "Cron job already exists, skipping"
#
# Note:
#   Requires YELLOW and NC color variables to be defined
log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $*"
}

# Log an error message
#
# Logs an error message with red [ERROR] prefix to stdout.
# Used for critical errors that may prevent normal operation.
#
# Arguments:
#   $@: Message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints colored message to stdout: "[ERROR] <message>"
#
# Examples:
#   log_error "Cannot create directory:" "$dir"
#   log_error "Script must be run as root"
#
# Note:
#   Requires RED and NC color variables to be defined
log_error() {
	echo -e "${RED}[ERROR]${NC} $*"
}

# Print debug message if DEBUG is enabled
#
# Prints a debug message to stderr if the DEBUG environment variable is set to 1.
# Uses the same format as log_message() with DEBUG level for consistency:
# [YYYY-MM-DD HH:MM:SS] [DEBUG] SYSTEM: <message>
#
# Arguments:
#   $@: Debug message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints to stderr if DEBUG=1: "[timestamp] [DEBUG] SYSTEM: <message>"
#
# Examples:
#   debug_log "Starting main() function, PID: $$"
#   debug_log "After log_message call"
#   debug_log "Validating EXTERNAL_PEER_IPS (value: '${EXTERNAL_PEER_IPS}')"
#
# Note:
#   Only outputs if DEBUG environment variable is set to 1
#   Output goes to stderr (>&2) to avoid interfering with stdout
#   Format matches log_message "DEBUG" "SYSTEM" "..." for consistent debug output
debug_log() {
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		local timestamp
		timestamp=$(date '+%Y-%m-%d %H:%M:%S')
		echo "[$timestamp] [DEBUG] SYSTEM: $*" >&2
	fi
}

# Check if running as root
#
# Verifies that the script is running with root privileges (EUID = 0).
# Required for installing to /data/ and modifying crontab.
# Exits script with error code 1 if not running as root.
#
# Arguments:
#   None
#
# Returns:
#   0: Running as root (continues execution)
#   1: Not running as root (exits script with error)
#
# Side effects:
#   Exits script with code 1 if not running as root
#
# Examples:
#   check_root  # Will exit if not root
#
# Note:
#   Uses $EUID to check effective user ID
#   Requires log_error function to be available
check_root() {
	if [[ $EUID -ne 0 ]]; then
		log_error "This script must be run as root"
		exit "${EXIT_PERMISSION_ERROR:-4}"
	fi
}

# Check if file exists and is readable
#
# Verifies that a file exists and is readable. This is a common pattern
# used throughout the codebase to check file accessibility before operations.
# Uses timeout wrapper to prevent hangs when checking files with restrictive
# permissions (e.g., 000) on some systems.
#
# Arguments:
#   $1: File path to check
#
# Returns:
#   0: File exists and is readable
#   1: File does not exist or is not readable
#
# Examples:
#   if file_exists_and_readable "$config_file"; then
#       safe_parse_config_file "$config_file"  # Use safe parser, not source
#   fi
#
# Note:
#   Uses timeout wrapper (if available) to prevent hangs on unreadable files.
#   On systems without timeout command, falls back to standard test (may hang
#   on some filesystems with restrictive permissions).
file_exists_and_readable() {
	local file="$1"
	# Check file exists first (fast check)
	if [[ ! -f "$file" ]]; then
		return 1
	fi
	# Check readability with timeout wrapper to prevent hangs on unreadable files
	# This is especially important for files with 000 permissions on some systems
	# where the readability check might hang due to filesystem or NFS issues
	# Use --kill-after with timeout to ensure the process is killed if it hangs
	# This is more reliable than timeout alone on some systems
	if command -v timeout >/dev/null 2>&1; then
		# Use timeout with --kill-after to ensure test -r is killed if it hangs
		# --kill-after=0.5 sends SIGKILL 0.5 seconds after SIGTERM if process doesn't exit
		# This ensures the check completes quickly even if test -r hangs
		timeout --kill-after=0.5 1 test -r "$file" 2>/dev/null && return 0 || return 1
	else
		# Fallback without timeout (may hang on some systems with restrictive permissions)
		[[ -r "$file" ]]
	fi
}

# Run command with timeout wrapper
#
# Executes a command with timeout protection if the timeout command is available.
# Falls back to executing without timeout if timeout is not available.
# This consolidates the common pattern of checking for timeout availability
# before executing commands that might hang.
#
# Arguments:
#   $1: Timeout duration in seconds (default: 1)
#   $2-$N: Command and arguments to execute (or command string if using -c flag)
#
# Returns:
#   Exit code of the executed command (or timeout exit code if command times out)
#
# Output:
#   Captures and returns stdout/stderr of the command (for use in command substitution)
#
# Examples:
#   # Simple command
#   if run_with_timeout 1 grep -qE '^[0-9]+$' "$file"; then
#       echo "File contains only digits"
#   fi
#
#   # Command with pipes (wrap in sh -c)
#   result=$(run_with_timeout 1 sh -c "grep -E '^[0-9]+$' \"$file\" | sort -n | tail -n 1")
#
#   # Capture output
#   output=$(run_with_timeout 1 cat "$file")
#
# Note:
#   For commands with pipes or complex redirections, wrap in sh -c.
#   Timeout exit code is 124 if command times out.
#   Stderr is redirected to /dev/null to match existing patterns.
run_with_timeout() {
	local timeout_duration="${1:-1}"
	shift # Remove timeout_duration from arguments, leaving command

	# Check if timeout command is available
	if command -v timeout >/dev/null 2>&1; then
		# Execute with timeout
		timeout "$timeout_duration" "$@" 2>/dev/null
		return $?
	else
		# Fallback without timeout
		"$@" 2>/dev/null
		return $?
	fi
}

# Run command with timeout wrapper and kill-after option
#
# Executes a command with timeout protection and --kill-after option if the timeout command is available.
# Falls back to executing without timeout if timeout is not available.
# This consolidates the common pattern of checking for timeout availability before executing
# commands that might hang and need aggressive termination (e.g., find on unreadable files).
#
# Arguments:
#   $1: Timeout duration in seconds (default: 1)
#   $2: Kill-after duration in seconds (default: 0.5)
#   $3-$N: Command and arguments to execute
#
# Returns:
#   Exit code of the executed command (or timeout exit code if command times out)
#
# Output:
#   Captures and returns stdout/stderr of the command (for use in command substitution)
#
# Examples:
#   # Find command with kill-after
#   run_with_timeout_kill_after 5 1 find "$dir" -name "*.txt" -print0 >"$output_file" 2>/dev/null || true
#
# Note:
#   For commands with pipes or complex redirections, wrap in sh -c.
#   Timeout exit code is 124 if command times out.
#   Stderr is redirected to /dev/null to match existing patterns.
#   Use this helper for commands that need aggressive termination (e.g., find on unreadable files).
run_with_timeout_kill_after() {
	local timeout_duration="${1:-1}"
	local kill_after="${2:-0.5}"
	shift 2 # Remove timeout_duration and kill_after from arguments, leaving command

	# Check if timeout command is available
	if command -v timeout >/dev/null 2>&1; then
		# Execute with timeout and --kill-after
		timeout --kill-after="$kill_after" "$timeout_duration" "$@" 2>/dev/null
		return $?
	else
		# Fallback without timeout
		"$@" 2>/dev/null
		return $?
	fi
}

# Ensure file exists with optional default content
#
# Creates a file if it doesn't exist, optionally writing default content.
# Automatically creates parent directories if they don't exist.
# This reduces code duplication for file initialization patterns.
#
# Arguments:
#   $1: File path to ensure exists
#   $2: Optional default content to write if file doesn't exist (default: empty)
#
# Returns:
#   0: File exists or was created successfully
#   1: Failed to create file or parent directories
#
# Side effects:
#   Creates parent directories and file with default content if they don't exist
#
# Examples:
#   ensure_file_exists "$counter_file" "0"
#   ensure_file_exists "$log_file"
#   # Callers should handle errors:
#   if ! ensure_file_exists "$file" "0"; then
#       handle_error "WARNING" "Failed to create file: $file" 0
#   fi
#
# Note:
#   Returns error code on failure - callers should handle errors appropriately.
#   Some callers may want to log and continue, others may want to die().
#   Automatically creates parent directories using mkdir -p if they don't exist.
ensure_file_exists() {
	local file="$1"
	local default_content="${2:-}"

	if [[ ! -f "$file" ]]; then
		# Ensure parent directory exists
		local parent_dir
		parent_dir=$(dirname "$file")
		if [[ ! -d "$parent_dir" ]]; then
			if ! mkdir -p "$parent_dir" 2>/dev/null; then
				return 1
			fi
		fi
		if ! atomic_write_file "$file" "$default_content"; then
			return 1
		fi
	fi
	return 0
}

# Get current Unix timestamp
#
# Returns the current Unix timestamp (seconds since epoch).
# This provides a consistent way to get timestamps throughout the codebase,
# replacing direct calls to 'date +%s'.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints Unix timestamp (integer) to stdout
#
# Examples:
#   timestamp=$(get_unix_timestamp)
#   if [[ $timestamp -gt $last_check ]]; then
#       # do something
#   fi
#
# Note:
#   Uses 'date +%s' command internally
#   May fail if date command is unavailable (returns error, caller should handle)
get_unix_timestamp() {
	date +%s
}

# Validate timestamp is reasonable
#
# Validates that a Unix timestamp is within reasonable bounds to prevent
# arithmetic overflow/underflow issues. Checks that timestamp is:
# - Not negative
# - Not too far in the future (reasonable upper bound)
# - A valid integer
#
# Arguments:
#   $1: Timestamp to validate (Unix timestamp in seconds)
#
# Returns:
#   0: Timestamp is valid
#   1: Timestamp is invalid (negative, too large, or not a number)
#
# Examples:
#   if validate_timestamp "$timestamp"; then
#       # use timestamp safely
#   fi
#
# Note:
#   Upper bound is set to year 2100 (4102444800) to allow reasonable future dates
#   while preventing arithmetic overflow issues
validate_timestamp() {
	local timestamp="$1"

	# Check if timestamp is a valid integer
	if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
		return 1
	fi

	# Check if timestamp is too far in the future (year 2100 = 4102444800)
	# This prevents arithmetic overflow while allowing reasonable future dates
	local max_timestamp=4102444800
	if [[ $timestamp -gt $max_timestamp ]]; then
		return 1
	fi

	return 0
}

# Safely subtract seconds from a timestamp
#
# Performs timestamp subtraction with bounds checking to prevent underflow.
# Validates both input timestamp and result before returning.
#
# Arguments:
#   $1: Base timestamp (Unix timestamp in seconds)
#   $2: Seconds to subtract (positive integer)
#
# Returns:
#   0: Success (result printed to stdout)
#   1: Invalid input timestamp
#   2: Invalid seconds value (negative or not a number)
#   3: Result would be negative (underflow)
#
# Output:
#   Prints the result timestamp to stdout if successful
#
# Examples:
#   result=$(safe_timestamp_subtract "$now" "$SECONDS_PER_HOUR")
#   one_day_ago=$(safe_timestamp_subtract "$timestamp" "$SECONDS_PER_DAY" 2>/dev/null || echo "0")
#
# Note:
#   If subtraction would result in negative value, returns error code 3
#   Caller should handle this case appropriately (e.g., use 0 or current time)
safe_timestamp_subtract() {
	local base_timestamp="$1"
	local seconds_to_subtract="$2"

	# Validate base timestamp
	if ! validate_timestamp "$base_timestamp"; then
		return 1
	fi

	# Validate seconds_to_subtract is a non-negative integer
	# Note: Negative check is redundant since ^[0-9]+ won't match negatives
	if [[ ! "$seconds_to_subtract" =~ ^[0-9]+$ ]]; then
		return 2
	fi

	# Perform subtraction
	local result=$((base_timestamp - seconds_to_subtract))

	# Check for underflow (negative result)
	if [[ $result -lt 0 ]]; then
		return 3
	fi

	# Validate result is still reasonable
	if ! validate_timestamp "$result"; then
		return 1
	fi

	# Output result
	echo "$result"
	return 0
}

# Safely add seconds to a timestamp
#
# Performs timestamp addition with bounds checking to prevent overflow.
# Validates both input timestamp and result before returning.
#
# Arguments:
#   $1: Base timestamp (Unix timestamp in seconds)
#   $2: Seconds to add (positive integer)
#
# Returns:
#   0: Success (result printed to stdout)
#   1: Invalid input timestamp
#   2: Invalid seconds value (negative or not a number)
#   3: Result would exceed maximum (overflow)
#
# Output:
#   Prints the result timestamp to stdout if successful
#
# Examples:
#   future_time=$(safe_timestamp_add "$now" "$SECONDS_PER_HOUR")
#   if result=$(safe_timestamp_add "$timestamp" 3600); then
#       future_timestamp=$result
#   fi
#
# Note:
#   If addition would result in value exceeding maximum timestamp, returns error code 3
#   Caller should handle this case appropriately
safe_timestamp_add() {
	local base_timestamp="$1"
	local seconds_to_add="$2"

	# Validate base timestamp
	if ! validate_timestamp "$base_timestamp"; then
		return 1
	fi

	# Validate seconds_to_add is a non-negative integer
	if [[ ! "$seconds_to_add" =~ ^[0-9]+$ ]]; then
		return 2
	fi

	# Perform addition
	local result=$((base_timestamp + seconds_to_add))

	# Validate result is still reasonable (check for overflow)
	if ! validate_timestamp "$result"; then
		return 3
	fi

	# Output result
	echo "$result"
	return 0
}

# Safely calculate difference between two timestamps
#
# Calculates the difference (timestamp1 - timestamp2) with bounds checking.
# Validates both input timestamps before calculation.
#
# Arguments:
#   $1: First timestamp (Unix timestamp in seconds)
#   $2: Second timestamp (Unix timestamp in seconds)
#
# Returns:
#   0: Success (result printed to stdout, may be negative)
#   1: Invalid first timestamp
#   2: Invalid second timestamp
#
# Output:
#   Prints the difference (timestamp1 - timestamp2) to stdout if successful
#   Result may be negative if timestamp2 > timestamp1
#
# Examples:
#   elapsed=$(safe_timestamp_diff "$end_time" "$start_time")
#   remaining=$(safe_timestamp_diff "$cooldown_until" "$now")
#
# Note:
#   Returns the raw difference, which may be negative
#   Caller should handle negative results appropriately
safe_timestamp_diff() {
	local timestamp1="$1"
	local timestamp2="$2"

	# Validate both timestamps
	if ! validate_timestamp "$timestamp1"; then
		return 1
	fi

	if ! validate_timestamp "$timestamp2"; then
		return 2
	fi

	# Perform subtraction (may be negative)
	local result=$((timestamp1 - timestamp2))

	# Output result (even if negative, as this is valid for duration calculations)
	echo "$result"
	return 0
}

# Calculate duration between two timestamps
#
# Calculates the duration between a start time and an end time (defaults to now).
# Ensures the result is non-negative (clamps to 0 if negative).
# This is a convenience wrapper around safe_timestamp_diff that handles
# common error cases and ensures non-negative durations.
#
# Arguments:
#   $1: Start timestamp (required)
#   $2: End timestamp (optional, defaults to current time)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints duration in seconds (non-negative integer) to stdout
#
# Examples:
#   duration=$(calculate_duration "$start_time")
#   duration=$(calculate_duration "$start_time" "$end_time")
#
# Note:
#   Requires get_unix_timestamp() and safe_timestamp_diff() to be available
#   Negative durations are clamped to 0
calculate_duration() {
	local start_time="$1"
	local end_time="${2:-$(get_unix_timestamp)}"
	local duration
	duration=$(safe_timestamp_diff "$end_time" "$start_time" 2>/dev/null || echo "0")
	if [[ $duration -lt 0 ]]; then
		duration=0
	fi
	echo "$duration"
	return 0
}

# Start a timer
#
# Returns a timer identifier (timestamp) that can be used with stop_timer()
# to measure command execution duration. Handles errors gracefully by
# returning "0" if timestamp retrieval fails.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints timer identifier (Unix timestamp) to stdout, or "0" if measurement failed
#
# Example:
#   timer=$(start_timer)
#   # ... execute command ...
#   duration=$(stop_timer "$timer")
#
# Note:
#   Requires get_unix_timestamp() to be available
#   Returns "0" on failure, which stop_timer() handles gracefully
start_timer() {
	get_unix_timestamp 2>/dev/null || echo "0"
}

# Stop a timer and calculate duration
#
# Calculates the duration between a timer start time (from start_timer())
# and the current time. Handles errors gracefully by returning "0" if
# measurement fails.
#
# Arguments:
#   $1: Timer identifier from start_timer() (Unix timestamp)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints duration in seconds to stdout, or "0" if measurement failed
#
# Example:
#   timer=$(start_timer)
#   # ... execute command ...
#   duration=$(stop_timer "$timer")
#
# Note:
#   Requires get_unix_timestamp() and calculate_duration() to be available
#   Returns "0" if start_time is "0" or if measurement fails
stop_timer() {
	local start_time="$1"
	local end_time
	end_time=$(get_unix_timestamp 2>/dev/null || echo "0")

	if [[ "$start_time" != "0" ]] && [[ "$end_time" != "0" ]]; then
		calculate_duration "$start_time" "$end_time" 2>/dev/null || echo "0"
	else
		echo "0"
	fi
	return 0
}

# Check if directory exists
#
# Verifies that a directory exists. This is a common pattern used throughout
# the codebase to check directory existence before operations.
#
# Arguments:
#   $1: Directory path to check
#
# Returns:
#   0: Directory exists
#   1: Directory does not exist
#
# Examples:
#   if directory_exists "$STATE_DIR"; then
#       # process directory
#   fi
#
# Note:
#   Uses [[ -d "$1" ]] test internally
directory_exists() {
	[[ -d "$1" ]]
}

# Check if directory exists and is writable
#
# Verifies that a directory exists and is writable. This is a common pattern
# used throughout the codebase to validate directory permissions before writing.
# Only checks writability if the directory exists (returns 1 if directory doesn't exist).
#
# Arguments:
#   $1: Directory path to check
#
# Returns:
#   0: Directory exists and is writable
#   1: Directory does not exist or is not writable
#
# Examples:
#   if directory_writable "$STATE_DIR"; then
#       # write to directory
#   fi
#
# Note:
#   Uses [[ -d "$1" ]] && [[ -w "$1" ]] test internally
#   Returns 1 if directory doesn't exist (doesn't check writability of non-existent dirs)
directory_writable() {
	[[ -d "$1" ]] && [[ -w "$1" ]]
}

# Try to ensure directory exists (non-fatal)
#
# Creates a directory if it doesn't exist, but returns an error code instead of exiting.
# This is useful in contexts where the script should not exit on failure (e.g., logging).
# For contexts where failure should be fatal, use ensure_directory_exists() from config.sh.
#
# Arguments:
#   $1: Directory path to ensure exists
#
# Returns:
#   0: Directory exists or was created successfully
#   1: Failed to create directory
#
# Side effects:
#   Creates directory with mkdir -p if it doesn't exist
#
# Examples:
#   if try_ensure_directory_exists "$log_dir"; then
#       # directory exists or was created
#   else
#       # handle error without exiting
#   fi
#
# Note:
#   Returns error code on failure - callers should handle errors appropriately.
#   This is a non-fatal version for use in contexts like log_message() where
#   the script must not exit even if directory creation fails.
try_ensure_directory_exists() {
	local dir="$1"

	if [[ ! -d "$dir" ]]; then
		if ! mkdir -p "$dir" 2>/dev/null; then
			return 1
		fi
	fi
	return 0
}

# Atomic file write
#
# Writes content to a file atomically using a temporary file pattern.
# This ensures file integrity by writing to a temp file first, then renaming.
# Prevents partial writes from being visible if the operation is interrupted.
#
# Arguments:
#   $1: Target file path
#   $2: Content to write (can be multi-line)
#
# Returns:
#   0: File written successfully
#   1: Failed to write file
#
# Side effects:
#   Creates temporary file ${file}.tmp, then renames it to target file
#   Removes temporary file on success
#
# Examples:
#   if atomic_write_file "$state_file" "$value"; then
#       echo "State updated successfully"
#   fi
#
# Note:
#   Uses pattern: echo "$content" >"${file}.tmp" && mv "${file}.tmp" "$file"
#   This ensures atomic operation - either full write succeeds or file remains unchanged
#   Sets explicit permissions (chmod 600) after successful write for security
atomic_write_file() {
	local file="$1"
	local content="$2"

	# If target file exists but is unreadable or unwritable, remove it first to avoid potential hangs
	# This can happen if file permissions were changed (e.g., chmod 000 or chmod 444)
	# Removing unwritable files prevents mv from hanging when trying to overwrite them
	if [[ -f "$file" ]] && (! file_exists_and_readable "$file" || ! [[ -w "$file" ]]); then
		rm -f "$file" 2>/dev/null || true
	fi

	# Clean up any leftover .tmp file from previous failed attempts
	# This prevents hangs when directory becomes unwritable but .tmp file exists
	# Also ensures we start with a clean slate for the atomic write
	if [[ -f "${file}.tmp" ]]; then
		# Remove .tmp file if unreadable (prevents mv from hanging)
		# or if readable (ensures clean start)
		rm -f "${file}.tmp" 2>/dev/null || true
	fi

	if ! (echo "$content" >"${file}.tmp" && mv "${file}.tmp" "$file"); then
		return 1
	fi

	# Set explicit permissions for state files (security best practice)
	# chmod 600 ensures only owner can read/write, preventing information leakage
	chmod 600 "$file" 2>/dev/null || true

	return 0
}

# Read counter value from file safely
#
# Safely reads a counter file with proper error handling and corruption recovery.
# This function consolidates the common pattern of reading counter files used
# throughout the codebase for statistics tracking.
#
# Arguments:
#   $1: Counter file path to read
#
# Returns:
#   0: Always succeeds (read failures default to 0)
#
# Output:
#   Prints counter value (0 if file doesn't exist, is unreadable, or corrupted)
#
# Side effects:
#   None
#
# Examples:
#   local count=$(read_counter_file "$counter_file")
#   local dns_success=$(read_counter_file "$dns_success_file")
#
# Note:
#   Handles file corruption by returning 0
#   Uses file_exists_and_readable() to prevent hangs on unreadable files
#   Validates that the value is numeric before returning it
read_counter_file() {
	local counter_file="$1"
	local value

	if file_exists_and_readable "$counter_file"; then
		value=$(cat "$counter_file" 2>/dev/null || echo "0")
	else
		value="0"
	fi

	# Validate value is numeric (handle corruption)
	[[ "$value" =~ ^[0-9]+$ ]] || value=0

	echo "$value"
}

# Escape string for sed replacement
#
# Escapes special characters in a string for use in sed replacement strings.
# This prevents command injection and ensures proper sed behavior when replacing
# text that may contain special characters.
#
# Arguments:
#   $1: Value to escape
#   $2: Optional delimiter character used in sed command (default: |)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints escaped string to stdout
#
# Examples:
#   escaped=$(escape_sed_replacement "$peer_ips")
#   sed -i "s|^EXTERNAL_PEER_IPS=.*|EXTERNAL_PEER_IPS=\"${escaped}\"|" "$config_file"
#
#   # With custom delimiter
#   escaped=$(escape_sed_replacement "$value" "/")
#   sed -i "s/^KEY=.*/KEY=\"${escaped}\"/" "$file"
#
# Note:
#   Escapes: \ (backslash), & (matched text), and delimiter character
#   Uses printf '%s\n' to handle multi-line values safely
escape_sed_replacement() {
	local value="$1"
	local delimiter="${2:-|}"
	# Use a different delimiter for the sed command that escapes the delimiter character
	# This avoids issues when delimiter is | (which would create invalid s||| syntax)
	if [[ "$delimiter" == "|" ]]; then
		printf '%s\n' "$value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e "s#|#\\\\|#g"
	else
		printf '%s\n' "$value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e "s|${delimiter}|\\\\${delimiter}|g"
	fi
}

# Escape string for sed regex pattern
#
# Escapes special regex characters in a string for use in sed pattern matching.
# This ensures that literal strings are matched correctly in sed regex patterns
# rather than being interpreted as regex metacharacters.
#
# Arguments:
#   $1: Value to escape
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints escaped string to stdout
#
# Examples:
#   escaped=$(escape_sed_regex "$config_file")
#   sed -i "s|^CONFIG_FILE=.*|CONFIG_FILE=\"${escaped}\"|" "$file"
#
# Note:
#   Escapes regex special characters: [ \ . * ^ $ ( ) + ? { |
#   Uses echo instead of printf as regex patterns are typically single-line
escape_sed_regex() {
	local value="$1"
	echo "$value" | sed 's/[[\.*^$()+?{|]/\\&/g'
}

# Sanitize location name for filename safety
#
# Sanitizes a location name to be safe for use in filenames.
# Replaces invalid characters with underscores and ensures valid identifier format.
#
# Arguments:
#   $1: Location name to sanitize
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints sanitized location name to stdout
#
# Examples:
#   sanitized=$(sanitize_location_name "NYC-Office")
#   # Returns: "NYC_Office"
#
# Note:
#   - Replaces invalid chars (non-alphanumeric, non-underscore) with underscore
#   - Ensures max length of 64 chars for filename safety
#   - Ensures result is valid identifier (alphanumeric + underscore)
sanitize_location_name() {
	local location_name="$1"
	local sanitized

	# Replace invalid chars with underscore (keep alphanumeric and underscore)
	# Use bash parameter expansion instead of sed for better performance
	sanitized="${location_name//[^A-Za-z0-9_]/_}"

	# Ensure max length (64 chars for filename safety)
	if [[ ${#sanitized} -gt 64 ]]; then
		sanitized="${sanitized:0:64}"
	fi

	# Ensure it starts with alphanumeric (not underscore)
	if [[ "$sanitized" =~ ^_ ]]; then
		sanitized="LOC${sanitized}"
	fi

	# If empty after sanitization, use default
	if [[ -z "$sanitized" ]]; then
		sanitized="LOCATION"
	fi

	echo "$sanitized"
	return 0
}

# Validate SPI format (hex or decimal)
#
# Validates that a Security Parameter Index (SPI) value is in a valid format.
# SPI values can be in hex format (0x12345678) or decimal format (305419896).
# This function provides a single source of truth for SPI format validation
# across the codebase.
#
# Arguments:
#   $1: SPI value to validate
#
# Returns:
#   0: Valid SPI format (hex or decimal)
#   1: Invalid SPI format (empty, malformed, or contains invalid characters)
#
# Examples:
#   if validate_spi_format "$spi"; then
#       echo "SPI is valid"
#   fi
#
#   if ! validate_spi_format "$current_spi"; then
#       return 1
#   fi
#
# Note:
#   - Accepts hex format: 0x[0-9a-fA-F]+ (e.g., "0x12345678", "0xABC")
#   - Accepts decimal format: [0-9]+ (e.g., "305419896", "123")
#   - Empty strings are considered invalid (return 1)
#   - This function only validates format, not value ranges or semantics
validate_spi_format() {
	local spi="$1"
	[[ "$spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]
}

# Trim leading and trailing whitespace from a string
#
# Removes all leading and trailing whitespace characters (spaces, tabs, newlines)
# from the input string using efficient bash parameter expansion.
#
# Arguments:
#   $1: String to trim
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints trimmed string to stdout
#
# Examples:
#   trimmed=$(trim "  hello world  ")
#   # Returns: "hello world"
#
#   value=$(trim "$input_value")
#   if [[ -z "$value" ]]; then
#       echo "Empty after trimming"
#   fi
#
# Note:
#   - Uses bash parameter expansion for performance (faster than sed)
#   - Handles all POSIX whitespace characters: space, tab, newline, etc.
#   - Returns empty string if input is all whitespace or empty
#   - Accepts empty or missing arguments (treats as empty string)
trim() {
	local str="$1"

	# Remove leading whitespace: ${str#"${str%%[![:space:]]*}"}
	#   ${str%%[![:space:]]*} - removes everything from first non-space to end
	#   ${str#...} - removes that leading whitespace prefix
	str="${str#"${str%%[![:space:]]*}"}"

	# Remove trailing whitespace: ${str%"${str##*[![:space:]]}"}
	#   ${str##*[![:space:]]} - removes everything up to last non-space
	#   ${str%...} - removes that trailing whitespace suffix
	str="${str%"${str##*[![:space:]]}"}"

	echo "$str"
	return 0
}

# Update or add a configuration variable in config file
#
# Updates an existing configuration variable or adds it if it doesn't exist.
# Escapes special characters for safe sed replacement to prevent command injection.
#
# Arguments:
#   $1: Config file path
#   $2: Variable name
#   $3: Variable value (will be quoted in config file)
#   $4: Optional insertion point pattern (e.g., "^ENABLE_PING_CHECK=")
#       If provided and variable doesn't exist, inserts after this pattern.
#       If not provided, appends to end of file.
#
# Returns:
#   0: Success
#   1: Failed to update config file (file doesn't exist, unreadable, or write failed)
#
# Examples:
#   update_config_value "$config_file" "LOCAL_UDM_IP" "$local_udm_ip"
#   update_config_value "$config_file" "EXTERNAL_PEER_IPS" "$peer_ips"
#   update_config_value "$config_file" "LOCAL_UDM_IP" "$ip" "^ENABLE_PING_CHECK="
#
# Note:
#   Uses escape_sed_regex() to safely escape variable names for regex matching
#   Uses escape_sed_replacement() to safely escape values for sed replacement
#   Uses | as delimiter in sed to avoid conflicts with / in paths/IPs
#   Variable names should be valid shell identifiers (alphanumeric + underscore, starting with letter/underscore)
#   Variable names containing regex special characters are properly escaped
update_config_value() {
	local config_file="$1"
	local var_name="$2"
	local var_value="$3"
	local insert_after="${4:-}"

	# Validate variable name format (must be valid shell identifier)
	# Shell variable names: start with letter/underscore, followed by alphanumeric/underscore
	if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		return 1
	fi

	# Validate config file exists
	if [[ ! -f "$config_file" ]]; then
		return 1
	fi

	# Check file readability before grep operation (prevents hangs on unreadable files)
	if ! file_exists_and_readable "$config_file"; then
		return 1
	fi

	# Escape variable name for regex matching
	local escaped_var_name
	escaped_var_name=$(escape_sed_regex "$var_name")

	# Escape value for sed replacement
	local escaped_value
	escaped_value=$(escape_sed_replacement "$var_value" "|")

	if grep -q "^${escaped_var_name}=" "$config_file"; then
		# Update existing line (use original var_name in replacement, escaped in pattern)
		sed -i "s|^${escaped_var_name}=.*|${var_name}=\"${escaped_value}\"|" "$config_file"
	else
		# Add new line
		if [[ -n "$insert_after" ]]; then
			# Insert after specified pattern
			# Note: insert_after is used as a regex pattern in sed, so special regex
			# characters should be escaped by the caller if literal matching is desired
			sed -i "/${insert_after}/a ${var_name}=\"${escaped_value}\"" "$config_file"
		else
			# Append to end of file
			echo "${var_name}=\"${escaped_value}\"" >>"$config_file"
		fi
	fi

	return 0
}

# Safely assign a variable value using indirect assignment
#
# This prevents code injection by using printf -v instead of eval.
# Uses declare -g to ensure the variable is in global scope, then
# printf -v for safe assignment without code execution.
#
# Arguments:
#   $1: Variable name to assign
#   $2: Value to assign
#
# Returns:
#   0: Success
#   1: Invalid variable name format
#
# Side effects:
#   Sets global variable via declare -g + printf -v
#
# Examples:
#   safe_set_variable "PING_COUNT" "5"
#   safe_set_variable "$var_name" "$var_value"
#
# Note:
#   This function is used throughout config.sh to safely set configuration
#   variables without risk of code injection. It replaces the repeated pattern
#   of "declare -g \"$var_name\"; printf -v \"$var_name\" '%s' \"$var_value\""
#   Variable names must be valid shell identifiers (alphanumeric + underscore,
#   starting with letter or underscore)
safe_set_variable() {
	local var_name="$1"
	local var_value="$2"

	# Validate variable name format (must be valid shell identifier)
	if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		return 1
	fi

	declare -g "$var_name"
	printf -v "$var_name" '%s' "$var_value"
}

# Check if command is available
#
# Checks if a command is available in the system PATH using command -v.
# Falls back to checking if command can be executed directly if command -v fails.
# This handles cases where command exists but isn't found by command -v
# (e.g., functions, aliases, or commands in non-standard PATH locations).
# Returns error code if command is not found.
# This is useful for checking command availability before use (both required and optional commands).
#
# Arguments:
#   $1: Command name to check (e.g., "ip", "ipsec", "ping6")
#
# Returns:
#   0: Command is available (found in PATH or executable)
#   1: Command is not available
#
# Examples:
#   if ! check_command_available "ip"; then
#       return 1
#   fi
#   if check_command_available "ping6"; then
#       ping_cmd="ping6"
#   fi
#
# Note:
#   Uses command -v to check command availability (POSIX compliant)
#   Falls back to trying to execute command with --help/--version flags if command -v fails
#   This function can be used for both required and optional commands
#
# When to use check_command_available() vs check_command_or_warn():
#   - Use check_command_available() for:
#     * Optional commands that enhance functionality but aren't critical (e.g., readlink, ping6)
#     * Commands where you handle the missing case gracefully without logging
#     * Early initialization code where logging may not be set up yet
#   - Use check_command_or_warn() for:
#     * Required commands that are critical for functionality (e.g., ip, ipsec, ping)
#     * Commands where missing should be logged as a warning to help with debugging
#     * When you want standardized warning messages across the codebase
check_command_available() {
	local cmd="$1"

	# First try command -v (POSIX compliant, checks PATH)
	if command -v "$cmd" >/dev/null 2>&1; then
		return 0
	fi

	# Fallback 1: Check common system directories
	# This handles cases where PATH doesn't include /usr/sbin or /sbin
	# (common in cron/systemd environments on UDM systems)
	local system_dirs=("/usr/sbin" "/usr/bin" "/sbin" "/bin")
	for dir in "${system_dirs[@]}"; do
		if [[ -x "${dir}/${cmd}" ]]; then
			return 0
		fi
	done

	# Fallback 2: try to execute the command with --help or --version flag
	# This handles cases where command exists but command -v doesn't find it
	# (e.g., functions, aliases, or commands in non-standard locations)
	# Exit code 127 means "command not found", any other exit code means command exists
	# Use timeout to prevent hanging, and redirect output to avoid side effects
	local exit_code=127
	if command -v timeout >/dev/null 2>&1; then
		# Try --help first
		timeout 1 "$cmd" --help >/dev/null 2>&1
		exit_code=$?
		# If --help fails with "command not found" (127), try --version
		if [[ $exit_code -eq 127 ]]; then
			timeout 1 "$cmd" --version >/dev/null 2>&1
			exit_code=$?
		fi
	else
		# If timeout not available, try without timeout (should be quick for --help)
		"$cmd" --help >/dev/null 2>&1
		exit_code=$?
		# If --help fails with "command not found" (127), try --version
		if [[ $exit_code -eq 127 ]]; then
			"$cmd" --version >/dev/null 2>&1
			exit_code=$?
		fi
	fi

	# Exit code 127 means "command not found", any other exit code means command exists
	if [[ $exit_code -eq 127 ]]; then
		return 1
	else
		return 0
	fi
}

# Get full path to a command
#
# Attempts to find the full path to a command by checking standard system
# directories directly. This avoids relying on PATH or command -v, which don't
# work reliably in cron/systemd environments with restricted PATH.
#
# Arguments:
#   $1: Command name to find (e.g., "ip", "ipsec", "ping")
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints full path to stdout if found, or command name if not found
#
# Examples:
#   ip_path=$(get_command_path "ip")
#   # Returns: "/usr/sbin/ip" or "ip" if not found
#
#   ipsec_cmd=$(get_command_path "ipsec")
#   "$ipsec_cmd" reload
#
# Note:
#   Since this script always runs in cron/systemd with restricted PATH,
#   we check standard system directories first without relying on command -v.
#   Falls back to command name if path cannot be determined.
#   Useful for executing commands in PATH-restricted environments (cron/systemd)
get_command_path() {
	local cmd="$1"
	local cmd_path=""

	# First try PATH lookup via command -v
	# This allows:
	# - Tests: Mock commands in PATH override system commands
	# - Production: Commands in PATH are found
	# - Restricted PATH (cron/systemd): Falls through to system directory check
	cmd_path=$(command -v "$cmd" 2>/dev/null || echo "")
	if [[ -n "$cmd_path" ]]; then
		echo "$cmd_path"
		return 0
	fi

	# Check common system directories directly if not found in PATH
	# This handles PATH-restricted environments (cron/systemd) where PATH doesn't include
	# standard system directories like /usr/sbin and /sbin
	# Order matters: check /usr/sbin and /sbin first (where ip, ipsec typically live)
	local system_dirs=("/usr/sbin" "/sbin" "/usr/bin" "/bin")
	for dir in "${system_dirs[@]}"; do
		if [[ -x "${dir}/${cmd}" ]]; then
			echo "${dir}/${cmd}"
			return 0
		fi
	done

	# Path not found - return command name (will rely on PATH at execution time)
	# This should be rare since we check both PATH and standard directories
	# Caller should have checked availability with check_command_available first
	echo "$cmd"
	return 0
}

# Get IP command path with recovery context support
#
# Returns the full path to the 'ip' command, preferring _RECOVERY_IP_PATH
# if available (set by recovery orchestration), otherwise resolving via
# get_command_path(). Falls back to "ip" if resolution fails.
#
# This function consolidates the common pattern of resolving the IP command
# path used throughout the codebase, especially in recovery and detection code.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints command path to stdout (full path or "ip" as fallback)
#
# Examples:
#   ip_cmd=$(get_ip_command_path)
#   "$ip_cmd" xfrm state delete ...
#
# Note:
#   Uses _RECOVERY_IP_PATH if available (set by recovery orchestration for
#   consistency in PATH-restricted environments like cron/systemd).
#   Falls back to get_command_path() if _RECOVERY_IP_PATH is not set.
#   Final fallback is "ip" command name (relies on PATH at execution time).
get_ip_command_path() {
	local ip_cmd="${_RECOVERY_IP_PATH:-}"
	if [[ -z "$ip_cmd" ]] && command -v get_command_path >/dev/null 2>&1; then
		ip_cmd=$(get_command_path "ip")
	fi
	if [[ -z "$ip_cmd" ]]; then
		ip_cmd="ip" # Fallback to command name
	fi
	echo "$ip_cmd"
	return 0
}

# Check command availability and log warning if missing
#
# Checks if a command is available in PATH and logs a standardized warning
# message if it is not. This function standardizes the pattern of checking
# command availability and logging warnings, replacing the duplicate patterns
# of check_command_available() + handle_error() or warn_if_missing() + handle_error().
#
# Arguments:
#   $1: Command name to check
#   $2: Optional context message for the warning (e.g., "Cannot add route", "Ping check enabled")
#
# Returns:
#   0: Command is available (found in PATH)
#   1: Command is not available (warning logged)
#
# Side effects:
#   - Logs a warning message via handle_error() if command is not available
#   - Warning message format: "<context> but <command> command not available"
#     or "<command> command not available" if no context provided
#
# Examples:
#   if ! check_command_or_warn "ip" "Cannot add route"; then
#       return 1
#   fi
#   if ! check_command_or_warn "ping"; then
#       return 1
#   fi
#
# Note:
#   Requires handle_error() function to be available (from logging.sh)
#   Use check_command_available() if you need silent checks without logging
#   This function standardizes error messages across the codebase
#
# When to use check_command_or_warn() vs check_command_available():
#   - Use check_command_or_warn() for:
#     * Required commands that are critical for functionality (e.g., ip, ipsec, ping)
#     * Commands where missing should be logged as a warning to help with debugging
#     * When you want standardized warning messages across the codebase
#   - Use check_command_available() for:
#     * Optional commands that enhance functionality but aren't critical (e.g., readlink, ping6)
#     * Commands where you handle the missing case gracefully without logging
#     * Early initialization code where logging may not be set up yet
check_command_or_warn() {
	local cmd="$1"
	local context="${2:-}"

	if ! check_command_available "$cmd"; then
		if [[ -n "$context" ]]; then
			handle_error "WARNING" "SYSTEM" "$context but $cmd command not available"
		else
			handle_error "WARNING" "SYSTEM" "$cmd command not available"
		fi
		return 1
	fi

	return 0
}

# Format peer IP display for log messages
#
# Formats peer IP addresses for consistent display in log messages.
# Shows both internal and external IPs when available, otherwise just external IP.
# For multiple internal IPs (space-separated), uses the first one.
#
# Arguments:
#   $1: External peer IP address (external/public IP of remote VPN gateway, required)
#   $2: Internal peer IP address(es) (optional, can be single IP or space-separated string)
#
# Returns:
#   Prints formatted IP string to stdout: "($internal_peer_ip, $external_peer_ip)" or "($external_peer_ip)"
#
# Examples:
#   ip_display=$(format_peer_ip_display "203.0.113.1" "192.168.1.1")
#   # Output: "(192.168.1.1, 203.0.113.1)"
#   ip_display=$(format_peer_ip_display "203.0.113.1" "")
#   # Output: "(203.0.113.1)"
#
# Note:
#   This function is used throughout the codebase to ensure consistent IP display
#   in log messages. It removes redundant location names and shows both IPs when available.
format_peer_ip_display() {
	local external_peer_ip="$1"
	local internal_peer_ips="${2:-}"

	# Extract first internal IP if multiple provided (space-separated)
	local internal_peer_ip=""
	if [[ -n "$internal_peer_ips" ]]; then
		local IFS=' '
		local -a ips_array
		read -ra ips_array <<<"$internal_peer_ips"
		if [[ ${#ips_array[@]} -gt 0 ]]; then
			internal_peer_ip="${ips_array[0]}"
		fi
	fi

	# Format IPs: include internal IP if available, otherwise just external IP
	if [[ -n "$internal_peer_ip" ]]; then
		echo "($internal_peer_ip, $external_peer_ip)"
	else
		echo "($external_peer_ip)"
	fi
}

# Safely source a library file with error suppression
#
# Sources a library file with error suppression (2>/dev/null) and returns
# success/failure status. This provides a consistent pattern for sourcing
# library files with fallback handling throughout the codebase.
#
# Arguments:
#   $1: Path to library file to source
#
# Returns:
#   0: File was sourced successfully
#   1: File could not be sourced (doesn't exist or has errors)
#
# Examples:
#   if ! safe_source_lib "${LIB_DIR}/constants.sh"; then
#       # Fallback constants
#       readonly SECONDS_PER_MINUTE=60
#   fi
#
#   safe_source_lib "${LIB_DIR}/common.sh" || {
#       # Fallback functions
#       get_unix_timestamp() { date +%s; }
#   }
#
# Note:
#   Suppresses stderr output (2>/dev/null) to avoid error messages when
#   files are intentionally optional with fallback handling.
#   Callers should provide fallback code using if/else or || operator.
safe_source_lib() {
	local lib_file="$1"
	# Check if file exists and is readable before sourcing
	if [[ ! -f "$lib_file" ]] || [[ ! -r "$lib_file" ]]; then
		return 1
	fi
	# Source the file
	# Note: We suppress stderr to avoid cluttering output, but the file must source successfully
	# The array/variable declarations in the sourced file will be available in the current shell
	if source "$lib_file" 2>/dev/null; then
		# File sourced successfully
		return 0
	else
		# Source failed
		return 1
	fi
}

# Resolve lib directory path
#
# Determines the absolute path to the lib directory based on the location of a source file.
# This function centralizes LIB_DIR resolution logic to eliminate duplication across modules.
#
# Arguments:
#   $1: Optional source file path (defaults to BASH_SOURCE[0] if not provided)
#   $2: Optional number of directory levels to go up from source file's directory (defaults to 0)
#       For example, if source file is in lib/config/, use 1 to get lib/
#
# Returns:
#   0: Success (LIB_DIR resolved and set)
#   1: Failure (could not resolve LIB_DIR)
#
# Side effects:
#   Sets global variable LIB_DIR to the resolved path
#   In fake mode (NO_ESCALATE=1), continues execution even if resolution fails
#
# Examples:
#   # Resolve lib/ directory from lib/config/config_loading.sh (go up one level)
#   resolve_lib_dir "${BASH_SOURCE[0]}" 1
#
#   # Resolve lib/ directory from lib/config.sh (no levels up needed)
#   resolve_lib_dir "${BASH_SOURCE[0]}" 0
#
#   # Use default (BASH_SOURCE[0], 0 levels)
#   resolve_lib_dir
#
# Note:
#   - Uses readlink -f if available for better symlink resolution
#   - Falls back to cd/pwd if readlink not available
#   - Handles both absolute and relative source file paths
#   - Validates that resolved directory exists before setting LIB_DIR
#   - This function is used by config.sh and config module files to ensure consistent LIB_DIR resolution
resolve_lib_dir() {
	local source_file="${1:-${BASH_SOURCE[0]}}"
	local levels_up="${2:-0}"
	local resolved_dir=""
	local current_dir

	# Try to resolve using readlink if available (handles symlinks better)
	# Note: We check for check_command_available function first (if common.sh was sourced),
	# but fall back to command -v if not available (for cases where this function is called
	# before common.sh is fully loaded)
	if { (declare -f check_command_available >/dev/null 2>&1 && check_command_available "readlink") || command -v readlink >/dev/null 2>&1; } && { [[ -L "$source_file" ]] || [[ -f "$source_file" ]]; }; then
		# Try to resolve to absolute path
		if current_dir=$(readlink -f "$source_file" 2>/dev/null) || [[ "$source_file" =~ ^/ ]]; then
			if [[ -n "$current_dir" ]]; then
				source_file="$current_dir"
			fi
			# Get directory containing source file
			current_dir="$(dirname "$source_file")"
			# Go up specified number of levels
			if [[ $levels_up -gt 0 ]]; then
				resolved_dir="$(cd "$current_dir" && for ((i = 0; i < levels_up; i++)); do cd ..; done && pwd)" 2>/dev/null || resolved_dir=""
			else
				resolved_dir="$(cd "$current_dir" && pwd)" 2>/dev/null || resolved_dir=""
			fi
		fi
	fi

	# Fallback: try relative path resolution if readlink method didn't work
	if [[ -z "$resolved_dir" ]] && [[ "$source_file" =~ \.\.?/ ]]; then
		current_dir="$(dirname "$source_file")"
		# Go up specified number of levels
		if [[ $levels_up -gt 0 ]]; then
			resolved_dir="$(cd "$current_dir" && for ((i = 0; i < levels_up; i++)); do cd ..; done && pwd)" 2>/dev/null || resolved_dir=""
		else
			resolved_dir="$(cd "$current_dir" && pwd)" 2>/dev/null || resolved_dir=""
		fi
	fi

	# Validate resolved directory exists
	if [[ -z "$resolved_dir" ]] || [[ ! -d "$resolved_dir" ]]; then
		# In fake mode, allow LIB_DIR to remain unset (subsequent code will handle it)
		if [[ -n "${NO_ESCALATE:-}" ]] && [[ "${NO_ESCALATE}" == "1" ]]; then
			LIB_DIR=""
			return 1
		fi
		# Normal mode: error out
		echo "ERROR: Cannot determine lib directory (source_file=${source_file:-<empty>}, levels_up=${levels_up})" >&2
		echo "ERROR: BASH_SOURCE[0]=${BASH_SOURCE[0]:-<empty>}" >&2
		LIB_DIR=""
		return 1
	fi

	# Set LIB_DIR to resolved path
	LIB_DIR="$resolved_dir"
	return 0
}

# Log error when module loading fails
#
# Used during module loading when log_message may not be available yet.
# Gracefully falls back to echo if log_message is not defined.
# This function consolidates duplicate logging helper functions used during
# module initialization across detection.sh and state.sh.
#
# Arguments:
#   $1: Error message to log
#
# Returns:
#   0: Always succeeds (logging never fails)
#
# Output:
#   - If log_message is available: logs via log_message to LOG_FILE and stderr
#   - Otherwise: prints error message to stderr
#
# Examples:
#   log_module_error "Failed to source detection/network_validation.sh"
#   log_module_error "Failed to source state_paths.sh"
#
# Note:
#   This function is used during module loading when log_message may not be available yet.
#   It gracefully falls back to echo if log_message is not defined.
log_module_error() {
	local message="$1"
	if type log_message >/dev/null 2>&1; then
		# log_message is available - use it (it will handle LOG_FILE not being set)
		log_message "ERROR" "SYSTEM" "$message"
	else
		# Fallback to echo if log_message not available
		echo "Error: $message" >&2
	fi
}
