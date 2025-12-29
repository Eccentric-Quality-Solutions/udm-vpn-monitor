#!/bin/bash
#
# Common functions for UDM VPN Monitor
# Shared logging and utility functions for installation/uninstallation scripts and main monitor
#
# Version: 0.4.0
#
# This module provides shared utility functions used throughout the codebase to reduce duplication:
# - File operations: file_exists_and_readable(), ensure_file_exists(), atomic_write_file()
# - Directory operations: directory_exists(), directory_writable()
# - Timestamp operations: get_unix_timestamp()
# - String escaping: escape_sed_replacement(), escape_sed_regex()
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
		exit 1
	fi
}

# Check if file exists and is readable
#
# Verifies that a file exists and is readable. This is a common pattern
# used throughout the codebase to check file accessibility before operations.
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
file_exists_and_readable() {
	[[ -f "$1" ]] && [[ -r "$1" ]]
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
			# Return error code - let caller decide how to handle
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
#   Compatible with Linux and BSD/macOS date commands
get_unix_timestamp() {
	date +%s
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
atomic_write_file() {
	local file="$1"
	local content="$2"

	if ! (echo "$content" >"${file}.tmp" && mv "${file}.tmp" "$file"); then
		return 1
	fi
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
#   1: Failed to update config file (file doesn't exist or write failed)
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
			sed -i "/${insert_after}/a ${var_name}=\"${var_value}\"" "$config_file"
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
