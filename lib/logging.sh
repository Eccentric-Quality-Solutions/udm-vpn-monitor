#!/bin/bash
#
# Logging functions for UDM VPN Monitor
# Provides centralized logging functionality with timestamp and level support
#
# Version: 0.0.1
#

# Get formatted timestamp
#
# Returns a formatted timestamp string suitable for log entries.
# Format: YYYY-MM-DD HH:MM:SS (e.g., "2025-01-15 14:30:45")
# Handles date command failures gracefully with fallback.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted timestamp string to stdout
#
# Examples:
#   timestamp=$(get_formatted_timestamp)
#   echo "[$timestamp] Starting operation"
#
# Note:
#   Uses date '+%Y-%m-%d %H:%M:%S' command
#   Compatible with both Linux and BSD/macOS date commands
#   Fallback repeats same command (handles edge cases)
get_formatted_timestamp() {
	# Try date command with fallback (handles both Linux and BSD/macOS)
	date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
}

# Logging function
# Note: This function must not cause script exit even if logging fails
#
# Logs a message with timestamp and level to both log file and stderr (for errors/warnings/debug/info).
# This function is designed to be resilient - it will not fail the script if logging fails.
# Creates log directory if it doesn't exist.
#
# Arguments:
#   $1: Log level (INFO, WARNING, ERROR, DEBUG)
#   $2+: Message text (all remaining arguments are concatenated with spaces)
#
# Returns:
#   0: Always returns 0 (never fails the script, even if file write fails)
#
# Output:
#   - Writes formatted log entry to LOG_FILE (append mode)
#   - Outputs ERROR/WARNING to stderr (always)
#   - Outputs DEBUG messages to stderr if DEBUG=1
#   - Outputs INFO messages to stderr if running interactively (TTY attached)
#   - Format: "[YYYY-MM-DD HH:MM:SS] [LEVEL] message"
#
# Side effects:
#   - Creates log directory if it doesn't exist (mkdir -p)
#   - Writes to log file (may fail silently)
#   - Outputs to stderr based on level and execution context
#
# Examples:
#   log_message "INFO" "VPN monitor started"
#   log_message "WARNING" "Config file not found:" "$config_file"
#   log_message "ERROR" "Failed to restart VPN"
#
# Note:
#   Requires LOG_FILE and DEBUG variables to be set (typically from config.sh)
#   Log file write errors are caught and don't fail the script
#   DEBUG messages only output to stderr if DEBUG=1
#   INFO messages output to stderr when running interactively (manual execution)
#   When run via cron (no TTY), INFO messages only go to log file (quiet operation)
log_message() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(get_formatted_timestamp)

	# Always output to stderr first for debugging
	local log_entry="[$timestamp] [$level] $message"

	# Ensure log directory exists and is writable
	local log_dir
	log_dir=$(dirname "$LOG_FILE")
	if [[ ! -d "$log_dir" ]]; then
		if ! mkdir -p "$log_dir" 2>/dev/null; then
			echo "$log_entry" >&2
			echo "[$timestamp] [ERROR] Cannot create log directory: $log_dir" >&2
			return 0 # Don't fail the script if logging fails
		fi
	fi

	# Write to log file (append, create if doesn't exist)
	# Try to write, but don't fail the script if it doesn't work
	{
		echo "$log_entry" >>"$LOG_FILE" 2>&1
	} || {
		# If write failed, at least we tried - output to stderr
		echo "$log_entry" >&2
		echo "[$timestamp] [ERROR] Failed to write to log file: $LOG_FILE" >&2
	}

	# Determine if running interactively (TTY attached to stderr)
	# This allows INFO messages to be shown when running manually
	# Check stderr (fd 2) since that's where we output messages
	local is_interactive=0
	if [[ -t 2 ]]; then
		is_interactive=1
	fi

	# Output to stderr:
	# - Always: ERROR and WARNING
	# - If DEBUG=1: DEBUG messages
	# - If interactive (TTY): INFO messages (so users see success when running manually)
	if [[ "${DEBUG:-0}" -eq 1 ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]] || { [[ "$level" == "INFO" ]] && [[ $is_interactive -eq 1 ]]; }; then
		echo "$log_entry" >&2
	fi

	return 0
}

# Die function for fatal errors
#
# Logs an error message and exits the script with the specified exit code.
# This function provides consistent error handling for fatal errors that should
# cause the script to exit immediately.
#
# Arguments:
#   $1: Error message to log
#   $2: Exit code (optional, defaults to 1)
#
# Returns:
#   Never returns (exits script)
#
# Side effects:
#   - Logs error message using log_message
#   - Exits script with specified exit code
#
# Note:
#   Requires log_message function to be available (from this file)
#   This function should be used for fatal errors that cannot be recovered from
die() {
	local message="$1"
	local exit_code="${2:-1}"
	log_message "ERROR" "$message"
	exit "$exit_code"
}

# Handle error with consistent logging and optional exit
#
# Provides a unified interface for error handling that logs messages
# with appropriate severity levels and optionally exits for fatal errors.
# This function standardizes error handling patterns across the codebase.
#
# Arguments:
#   $1: Severity level (ERROR, WARNING, INFO)
#   $2: Error message to log
#   $3: Exit code (optional, defaults to 1, only used for ERROR severity)
#
# Returns:
#   0: Always returns 0 (unless severity is ERROR and exit_code is non-zero, then exits)
#   Never returns if severity is ERROR and exit_code is non-zero (exits script)
#
# Side effects:
#   - Logs message using log_message with specified severity
#   - Exits script if severity is ERROR and exit_code is non-zero
#
# Examples:
#   # Non-fatal error (logs warning, continues execution)
#   handle_error "WARNING" "Optional feature unavailable, using fallback"
#
#   # Fatal error (logs error and exits)
#   handle_error "ERROR" "Critical configuration missing" 1
#
#   # Informational error (logs info, continues execution)
#   handle_error "INFO" "Operation completed with minor issues"
#
# Note:
#   Requires log_message and die functions to be available (from this file)
#   For ERROR severity with non-zero exit_code, calls die() which exits the script
#   For other severities or zero exit_code, only logs the message
handle_error() {
	local severity="$1"
	local message="$2"
	local exit_code="${3:-1}"

	# Validate severity
	if [[ "$severity" != "ERROR" ]] && [[ "$severity" != "WARNING" ]] && [[ "$severity" != "INFO" ]]; then
		# Invalid severity, default to ERROR
		log_message "ERROR" "Invalid severity '$severity' in handle_error, defaulting to ERROR"
		severity="ERROR"
	fi

	# Log the message
	log_message "$severity" "$message"

	# For ERROR severity with non-zero exit code, exit the script
	if [[ "$severity" == "ERROR" ]] && [[ "$exit_code" -ne 0 ]]; then
		die "$message" "$exit_code"
	fi

	return 0
}

# Warn if command is missing
#
# Checks if a command is available in the system PATH using command -v.
# Logs a warning message if the command is not found, but does not fail the script.
# This is useful for optional commands that enhance functionality but are not required.
#
# Arguments:
#   $1: Command name to check (e.g., "ipsec", "ping", "ip")
#
# Returns:
#   0: Command is available (found in PATH)
#   1: Command is not available (warning logged)
#
# Side effects:
#   - Logs warning message via log_message if command is not available
#   - Does not exit script (allows graceful degradation)
#
# Examples:
#   if warn_if_missing "ipsec"; then
#       ipsec status
#   fi
#
# Note:
#   Requires log_message function to be available (from this file)
#   Uses command -v to check command availability
#   This function should be used for optional commands that enhance functionality
#   but are not critical for script operation
warn_if_missing() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		log_message "WARNING" "$cmd not available"
		return 1
	fi
	return 0
}
