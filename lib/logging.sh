#!/bin/bash
#
# Logging functions for UDM VPN Monitor
# Provides centralized logging functionality with timestamp and level support
#
# Version: 0.6.0
#

# Source common utility functions
# shellcheck source=lib/common.sh
# Determine lib directory (where this file is located)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/common.sh"

# Get formatted timestamp
#
# Returns a formatted timestamp string suitable for log entries.
# Format: YYYY-MM-DD HH:MM:SS (e.g., "2025-01-15 14:30:45")
#
# Arguments:
#   None
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
get_formatted_timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
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
#   $2: Prefix name (location name or "SYSTEM" for system-level messages) - REQUIRED
#   $3+: Message text (all remaining arguments are concatenated with spaces)
#
# Returns:
#   0: Always returns 0 (never fails the script, even if file write fails)
#
# Output:
#   - Writes formatted log entry to LOG_FILE (append mode)
#   - Outputs ERROR/WARNING to stderr (always)
#   - Outputs DEBUG messages to stderr if DEBUG=1
#   - Outputs INFO messages to stderr if running interactively (TTY attached)
#   - Format: "[YYYY-MM-DD HH:MM:SS] [LEVEL] PREFIX: message"
#   - PREFIX is either a location name (e.g., "NYC") or "SYSTEM" for system-level messages
#
# Side effects:
#   - Creates log directory if it doesn't exist (mkdir -p)
#   - Writes to log file (may fail silently)
#   - Outputs to stderr based on level and execution context
#
# Examples:
#   log_message "INFO" "SYSTEM" "VPN monitor started"
#   log_message "WARNING" "SYSTEM" "Config file not found:" "$config_file"
#   log_message "ERROR" "SYSTEM" "Failed to restart VPN"
#   log_message "INFO" "NYC" "VPN monitor started"
#   log_message "WARNING" "NYC" "Config file not found:" "$config_file"
#
# Note:
#   Requires LOG_FILE and DEBUG variables to be set (typically from config.sh)
#   Log file write errors are caught and don't fail the script
#   DEBUG messages only output to stderr if DEBUG=1
#   INFO messages output to stderr when running interactively (manual execution)
#   When run via cron (no TTY), INFO messages only go to log file (quiet operation)
#   Prefix should not contain spaces or colons (will be treated as part of message if it does)
#   Prefix is REQUIRED - must be provided explicitly
log_message() {
	local level="$1"
	local prefix="$2"
	shift 2
	local message="$*"

	# Require prefix (location name or "SYSTEM")
	# Prefix must be provided - no default fallback
	if [[ -z "$prefix" ]]; then
		# This should never happen in production code
		prefix="SYSTEM"
		echo "[$(get_formatted_timestamp)] [ERROR] SYSTEM: log_message called without prefix - this is a bug" >&2
	fi

	local timestamp
	timestamp=$(get_formatted_timestamp)

	# Format log entry with prefix (always present)
	local log_entry="[$timestamp] [$level] $prefix: $message"

	# Ensure log directory exists and is writable
	# Note: We use try_ensure_directory_exists() instead of ensure_directory_exists()
	# because log_message must never exit the script (it's used in error handlers)
	local log_dir
	log_dir=$(dirname "$LOG_FILE")
	if ! try_ensure_directory_exists "$log_dir"; then
		echo "$log_entry" >&2
		echo "[$timestamp] [ERROR] SYSTEM: Cannot create log directory: $log_dir" >&2
		return 0 # Don't fail the script if logging fails
	fi

	# Write to log file (append, create if doesn't exist)
	# Try to write, but don't fail the script if it doesn't work
	{
		echo "$log_entry" >>"$LOG_FILE" 2>&1
	} || {
		# If write failed, at least we tried - output to stderr
		echo "$log_entry" >&2
		echo "[$timestamp] [ERROR] SYSTEM: Failed to write to log file: $LOG_FILE" >&2
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
	local should_output=0
	if [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]]; then
		should_output=1
	elif [[ "$level" == "DEBUG" ]] && [[ "${DEBUG:-0}" == "1" ]]; then
		should_output=1
	elif [[ "$level" == "INFO" ]] && [[ $is_interactive -eq 1 ]]; then
		should_output=1
	fi
	if [[ $should_output -eq 1 ]]; then
		echo "$log_entry" >&2
	fi

	return 0
}

# Check if script is running in fake mode
#
# Returns whether the script is running in fake mode (NO_ESCALATE=1).
# Fake mode allows the script to run checks and log errors but exit gracefully
# instead of crashing on configuration or initialization errors.
#
# Arguments:
#   None
#
# Returns:
#   0: Script is in fake mode (NO_ESCALATE=1)
#   1: Script is not in fake mode (NO_ESCALATE=0 or unset)
#
# Examples:
#   if is_fake_mode; then
#       handle_error "ERROR" "Config error" 0
#       exit 0
#   else
#       die "Config error"
#   fi
#
# Note:
#   Checks the NO_ESCALATE environment variable
is_fake_mode() {
	[[ "${NO_ESCALATE:-0}" -eq 1 ]]
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
	log_message "ERROR" "SYSTEM" "$message"
	exit "$exit_code"
}

# Parse message and optional exit code from arguments
#
# Helper function to extract message and optional exit code from variable arguments.
# Checks if the last argument is numeric (exit code) and separates it from the message.
# This function eliminates code duplication between handle_error() and handle_error_or_exit_fake_mode().
#
# Arguments:
#   $@ - Message arguments, optionally ending with numeric exit code
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints pipe-delimited values to stdout: "message|exit_code|exit_code_provided"
#   - message: The parsed message (may be empty)
#   - exit_code: The exit code ("0" if no exit code provided and last arg is non-numeric,
#                the provided exit code if last arg is numeric, "1" if no args provided)
#   - exit_code_provided: "1" if exit code was explicitly provided (last arg was numeric), "0" otherwise
#
# Examples:
#   parsed=$(_parse_message_and_exit_code "Failed to parse config" "2")
#   IFS='|' read -r message exit_code exit_code_provided <<< "$parsed"
#
#   parsed=$(_parse_message_and_exit_code "Retry count: 3")
#   IFS='|' read -r message exit_code exit_code_provided <<< "$parsed"
#
# Note:
#   Uses pipe delimiter (|) to separate values since messages may contain spaces
#   If last argument is numeric, it's treated as exit code and removed from message
#   If no arguments provided, returns empty message with default exit code
_parse_message_and_exit_code() {
	local arg_count=$#
	local exit_code="1" # Default exit code
	local exit_code_provided=0
	local message=""

	if [[ $arg_count -gt 0 ]]; then
		# Use array indexing to get last argument (shellcheck SC2124)
		local args_array=("$@")
		local last_arg="${args_array[$((arg_count - 1))]}"
		if [[ "$last_arg" =~ ^[0-9]+$ ]]; then
			# Last argument is numeric - treat as exit code
			exit_code="$last_arg"
			exit_code_provided=1
			# Remove last arg from message
			set -- "${args_array[@]:0:$((arg_count - 1))}"
			message="$*"
		else
			# Non-numeric last argument is treated as part of message
			# Set exit_code to 0 to prevent accidental exits when exit code parsing fails
			message="$*"
			exit_code="0"
			exit_code_provided=0
		fi
	else
		# No arguments provided
		message=""
		exit_code="1" # Default
		exit_code_provided=0
	fi

	# Output pipe-delimited: message|exit_code|exit_code_provided
	echo "${message}|${exit_code}|${exit_code_provided}"
}

# Handle error with consistent logging and optional exit
#
# Provides a unified interface for error handling that logs messages
# with appropriate severity levels and optionally exits for fatal errors.
# This function standardizes error handling patterns across the codebase.
#
# Arguments:
#   $1: Severity level (ERROR, WARNING, INFO)
#   $2: Prefix name (location name or "SYSTEM" for system-level messages) - REQUIRED
#   $3: Error message to log
#   $4: Exit code (optional, defaults to 1, only used for ERROR severity)
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
#   handle_error "WARNING" "SYSTEM" "Optional feature unavailable, using fallback"
#   handle_error "WARNING" "NYC" "Optional feature unavailable, using fallback"
#
#   # Fatal error (logs error and exits)
#   handle_error "ERROR" "SYSTEM" "Critical configuration missing" 1
#   handle_error "ERROR" "NYC" "Critical configuration missing" 1
#
#   # Informational error (logs info, continues execution)
#   handle_error "INFO" "SYSTEM" "Operation completed with minor issues"
#
# Note: Prefix is REQUIRED - must be provided explicitly (no default fallback)
#
# Note:
#   Requires log_message and die functions to be available (from this file)
#   For ERROR severity with non-zero exit_code, calls die() which exits the script
#   For other severities or zero exit_code, only logs the message
#   Location name should not contain spaces or colons (will be treated as part of message if it does)
handle_error() {
	local severity="$1"
	local prefix="$2"
	shift 2

	# Parse message and optional exit code from remaining arguments
	local parsed
	parsed=$(_parse_message_and_exit_code "$@")
	IFS='|' read -r message exit_code exit_code_provided <<<"$parsed"

	# Require prefix - no default fallback
	if [[ -z "$prefix" ]]; then
		# This should never happen in production code
		prefix="SYSTEM"
		log_message "ERROR" "SYSTEM" "handle_error called without prefix - this is a bug"
	fi

	# Validate severity
	if [[ "$severity" != "ERROR" ]] && [[ "$severity" != "WARNING" ]] && [[ "$severity" != "INFO" ]]; then
		# Invalid severity, default to ERROR
		log_message "ERROR" "SYSTEM" "Invalid severity '$severity' in handle_error, defaulting to ERROR"
		severity="ERROR"
		# When severity is defaulted due to invalid input, only exit if exit code was explicitly provided
		# This prevents accidental exits when invalid severity is passed
		if [[ $exit_code_provided -eq 0 ]]; then
			exit_code="0"
		fi
	fi

	# Log the message with prefix (always present)
	log_message "$severity" "$prefix" "$message"

	# For ERROR severity with non-zero exit code, exit the script
	if [[ "$severity" == "ERROR" ]] && [[ "$exit_code" -ne 0 ]]; then
		die "$message" "$exit_code"
	fi

	return 0
}

# Handle error in fake mode or die
#
# Provides consistent error handling for fatal errors that should exit gracefully
# in fake mode (NO_ESCALATE=1) or die in normal mode. This function standardizes
# the pattern of handling errors differently based on fake mode.
#
# Arguments:
#   $1: Prefix name (location name or "SYSTEM" for system-level messages) - REQUIRED
#   $2: Error message to log
#   $3: Exit code (optional, defaults to 1)
#
# Returns:
#   1: In fake mode (allows calling function to return failure)
#   Never returns in normal mode (dies with specified exit code)
#
# Side effects:
#   - Logs error message using handle_error
#   - Returns 1 in fake mode (allows test assertions to work correctly)
#   - Dies (exits with specified code) in normal mode
#
# Examples:
#   handle_error_or_exit_fake_mode "SYSTEM" "Failed to parse configuration file: $config_file"
#   handle_error_or_exit_fake_mode "SYSTEM" "Configuration validation failed" 2
#   handle_error_or_exit_fake_mode "NYC" "Failed to get external IP" 3
#
# Note:
#   Requires handle_error, die, and is_fake_mode functions to be available (from this file)
#   This function should be used for fatal errors that need fake mode support
#   Use EXIT_* constants from constants.sh for exit codes
#   In fake mode, returns 1 instead of exiting to allow tests to assert failure
#   Location name should not contain spaces or colons (will be treated as part of message if it does)
handle_error_or_exit_fake_mode() {
	local prefix="$1"
	shift

	# Parse message and optional exit code from remaining arguments
	local parsed
	parsed=$(_parse_message_and_exit_code "$@")
	IFS='|' read -r message exit_code exit_code_provided <<<"$parsed"

	# Fix inconsistency: handle_error_or_exit_fake_mode should default to exit_code=1
	# when no exit code is provided (unlike handle_error which uses 0 to prevent accidental exits)
	if [[ $exit_code_provided -eq 0 ]]; then
		exit_code="1"
	fi

	# Require prefix - no default fallback
	if [[ -z "$prefix" ]]; then
		# This should never happen in production code
		prefix="SYSTEM"
		log_message "ERROR" "SYSTEM" "handle_error_or_exit_fake_mode called without prefix - this is a bug"
	fi

	if is_fake_mode; then
		handle_error "ERROR" "$prefix" "$message" 0
		return 1
	else
		die "$message" "$exit_code"
	fi
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
		log_message "WARNING" "SYSTEM" "$cmd not available"
		return 1
	fi
	return 0
}
