#!/bin/bash
#
# Common functions for UDM VPN Monitor
# Shared logging and utility functions for installation/uninstallation scripts and main monitor
#
# Version: 0.6.0
#
# This module provides shared utility functions used throughout the codebase to reduce duplication:
# - File operations: file_exists_and_readable(), ensure_file_exists(), atomic_write_file()
# - Directory operations: directory_exists(), directory_writable()
# - Timestamp operations: get_unix_timestamp(), validate_timestamp(), safe_timestamp_subtract(), safe_timestamp_add(), safe_timestamp_diff()
# - String escaping: escape_sed_replacement(), escape_sed_regex()
# - String sanitization: sanitize_location_name()
# - String trimming: trim()
# - Config file operations: update_config_value()
# - Logging: log_info(), log_warn(), log_error()
# - System checks: check_root()
#
# All modules should use these shared functions instead of duplicating logic.
# See ARCHITECTURAL_REVIEW.md section 8.3 for code duplication reduction guidelines.
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
# This provides a consistent way to output debug information throughout the codebase.
#
# Arguments:
#   $@: Debug message text (all arguments are concatenated with spaces)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints to stderr if DEBUG=1: "DEBUG: <message>"
#
# Examples:
#   debug_log "Starting main() function, PID: $$"
#   debug_log "After log_message call"
#   debug_log "Validating EXTERNAL_PEER_IPS (value: '${EXTERNAL_PEER_IPS}')"
#
# Note:
#   Only outputs if DEBUG environment variable is set to 1
#   Output goes to stderr (>&2) to avoid interfering with stdout
debug_log() {
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: $*" >&2
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

# Ensure file exists with optional default content
#
# Creates a file if it doesn't exist, optionally writing default content.
# This reduces code duplication for file initialization patterns.
#
# Arguments:
#   $1: File path to ensure exists
#   $2: Optional default content to write if file doesn't exist (default: empty)
#
# Returns:
#   0: File exists or was created successfully
#   1: Failed to create file
#
# Side effects:
#   Creates file with default content if it doesn't exist
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
ensure_file_exists() {
	local file="$1"
	local default_content="${2:-}"

	if [[ ! -f "$file" ]]; then
		if ! echo "$default_content" >"$file" 2>/dev/null; then
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
		printf '%s\n' "$value" | sed 's/\\/\\\\/g' | sed 's/&/\\&/g' | sed "s#|#\\|#g"
	else
		printf '%s\n' "$value" | sed 's/\\/\\\\/g' | sed 's/&/\\&/g' | sed "s|${delimiter}|\\${delimiter}|g"
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
#   - Returns empty string if input is all whitespace
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
#   Uses escape_sed_replacement() to safely escape values for sed replacement
#   Uses | as delimiter in sed to avoid conflicts with / in paths/IPs
update_config_value() {
	local config_file="$1"
	local var_name="$2"
	local var_value="$3"
	local insert_after="${4:-}"

	# Validate config file exists
	if [[ ! -f "$config_file" ]]; then
		return 1
	fi

	# Check file readability before grep operation (prevents hangs on unreadable files)
	if ! file_exists_and_readable "$config_file"; then
		return 1
	fi

	# Escape value for sed replacement
	local escaped_value
	escaped_value=$(escape_sed_replacement "$var_value" "|")

	if grep -q "^${var_name}=" "$config_file"; then
		# Update existing line
		sed -i "s|^${var_name}=.*|${var_name}=\"${escaped_value}\"|" "$config_file"
	else
		# Add new line
		if [[ -n "$insert_after" ]]; then
			# Insert after specified pattern
			# Note: insert_after is used as a regex pattern in sed, so special regex
			# characters should be escaped by the caller if literal matching is desired
			sed -i "/${insert_after}/a ${var_name}=\"${escaped_value}\"" "$config_file"
		else
			# Append to end of file
			echo "${var_name}=\"${var_value}\"" >>"$config_file"
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
#   0: Always succeeds
#
# Side effects:
#   Sets global variable via declare -g + printf -v
#
# Examples:
#   safe_set_variable "VPN_NAME" "Site-to-Site VPN"
#   safe_set_variable "$var_name" "$var_value"
#
# Note:
#   This function is used throughout config.sh to safely set configuration
#   variables without risk of code injection. It replaces the repeated pattern
#   of "declare -g \"$var_name\"; printf -v \"$var_name\" '%s' \"$var_value\""
safe_set_variable() {
	local var_name="$1"
	local var_value="$2"
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
# Attempts to find the full path to a command, handling PATH restrictions
# common in cron/systemd environments. Returns the command name itself if
# path cannot be determined (fallback to PATH at execution time).
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
#   Uses same fallback logic as check_command_available() but returns path
#   Falls back to command name if path cannot be determined
#   Useful for executing commands in PATH-restricted environments (cron/systemd)
get_command_path() {
	local cmd="$1"
	local cmd_path=""

	# First try command -v (POSIX compliant, checks PATH)
	cmd_path=$(command -v "$cmd" 2>/dev/null || echo "")
	if [[ -n "$cmd_path" ]]; then
		echo "$cmd_path"
		return 0
	fi

	# Fallback: Check common system directories
	# This handles cases where PATH doesn't include /usr/sbin or /sbin
	# (common in cron/systemd environments on UDM systems)
	local system_dirs=("/usr/sbin" "/usr/bin" "/sbin" "/bin")
	for dir in "${system_dirs[@]}"; do
		if [[ -x "${dir}/${cmd}" ]]; then
			echo "${dir}/${cmd}"
			return 0
		fi
	done

	# Path not found - return command name (will rely on PATH at execution time)
	echo "$cmd"
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
#   $1: External peer IP address (required)
#   $2: Internal peer IP address(es) (optional, can be single IP or space-separated string)
#
# Returns:
#   Prints formatted IP string to stdout: "($internal_ip $external_ip)" or "($external_ip)"
#
# Examples:
#   ip_display=$(format_peer_ip_display "203.0.113.1" "192.168.1.1")
#   # Output: "(192.168.1.1 203.0.113.1)"
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
		echo "($internal_peer_ip $external_peer_ip)"
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
