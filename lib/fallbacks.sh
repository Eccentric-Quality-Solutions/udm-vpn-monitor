#!/bin/bash
#
# Centralized fallback function definitions for UDM VPN Monitor
# Provides standardized fallback implementations when modules can't be sourced
#
# Version: 0.6.0

# Define schema fallback functions
#
# Defines fallback implementations for schema-related functions when the schema
# file cannot be loaded. These are defined as a function to avoid duplication.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Defines global functions: get_config_schema, is_config_required, get_config_default
define_schema_fallbacks() {
	# Get configuration schema
	#
	# Fallback implementation that always returns failure. Used when schema file
	# cannot be loaded.
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   1: Always fails (schema not available)
	get_config_schema() { return 1; }
	# Check if configuration key is required
	#
	# Fallback implementation that always returns failure. Used when schema file
	# cannot be loaded.
	#
	# Arguments:
	#   $1: Configuration key name (ignored in fallback)
	#
	# Returns:
	#   1: Always fails (schema not available)
	is_config_required() { return 1; }
	# Get default value for configuration key
	#
	# Fallback implementation that always returns empty string. Used when schema
	# file cannot be loaded.
	#
	# Arguments:
	#   $1: Configuration key name (ignored in fallback)
	#
	# Returns:
	#   0: Always succeeds
	#
	# Output:
	#   Prints empty string to stdout
	get_config_default() {
		echo ""
		return 0
	}
}

# Define logging fallback functions
#
# Defines fallback implementations for logging functions when logging.sh
# cannot be loaded. These will output to stderr only (no log file).
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Defines global functions: log_message, handle_error
define_logging_fallbacks() {
	# Log a message with timestamp and level
	#
	# Outputs a formatted log message to stderr with timestamp and log level.
	# This is a fallback implementation used when logging.sh is not available.
	#
	# Arguments:
	#   $1: Log level (e.g., INFO, WARN, ERROR)
	#   $@: Remaining arguments form the log message
	#
	# Returns:
	#   0: Always succeeds
	#
	# Output:
	#   Prints formatted log message to stderr (format: [YYYY-MM-DD HH:MM:SS] [LEVEL] message)
	log_message() {
		local level="$1"
		shift
		local message="$*"
		local timestamp
		timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date +%s)
		echo "[$timestamp] [$level] $message" >&2
	}
	# Handle error with logging and optional exit
	#
	# Logs an error message and optionally exits the script. This is a fallback
	# implementation used when logging.sh is not available.
	#
	# Arguments:
	#   $1: Error severity level (e.g., ERROR, WARN)
	#   $2: Error message
	#   $3: Exit code (optional, default: 1)
	#
	# Returns:
	#   0: Success (if not exiting)
	#   Exits script with specified exit code if severity is ERROR and exit_code is non-zero
	handle_error() {
		local severity="$1"
		local message="$2"
		local exit_code="${3:-1}"
		log_message "$severity" "$message"
		if [[ "$severity" == "ERROR" ]] && [[ $exit_code -ne 0 ]]; then
			exit "$exit_code"
		fi
	}
}

# Define common utility fallback functions
#
# Defines fallback implementations for common utility functions when common.sh
# cannot be loaded.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Defines global functions: ensure_file_exists, try_ensure_directory_exists,
#   safe_source_lib, get_unix_timestamp, check_command_available, atomic_write_file
define_common_fallbacks() {
	# Ensure file exists with optional default content
	#
	# Creates a file if it doesn't exist, optionally with default content.
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   $1: Path to file to ensure exists
	#   $2: Optional default content to write if file doesn't exist
	#
	# Returns:
	#   0: File exists or was created successfully
	#   1: Failed to create file
	ensure_file_exists() {
		local file="$1"
		local default_content="${2:-}"
		if [[ ! -f "$file" ]]; then
			echo "$default_content" >"$file" 2>/dev/null || return 1
		fi
		return 0
	}
	# Try to ensure directory exists
	#
	# Attempts to create a directory if it doesn't exist.
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   $1: Directory path to ensure exists
	#
	# Returns:
	#   0: Directory exists or was created successfully
	#   1: Failed to create directory
	try_ensure_directory_exists() {
		local dir="$1"
		if [[ ! -d "$dir" ]]; then
			mkdir -p "$dir" 2>/dev/null || return 1
		fi
		return 0
	}
	# Safely source a library file
	#
	# Attempts to source a library file, silently failing if it doesn't exist.
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   $1: Path to library file to source
	#
	# Returns:
	#   0: File sourced successfully
	#   1: File not found or error sourcing
	safe_source_lib() {
		local lib_file="$1"
		source "$lib_file" 2>/dev/null
	}
	# Get current Unix timestamp
	#
	# Returns the current Unix timestamp (seconds since epoch).
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	#
	# Output:
	#   Prints Unix timestamp (integer) to stdout
	get_unix_timestamp() {
		date +%s
	}
	# Check if a command is available
	#
	# Checks if a command exists in the system PATH.
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is available
	#   1: Command is not available
	check_command_available() {
		local cmd="$1"
		command -v "$cmd" >/dev/null 2>&1
	}
	# Write file atomically
	#
	# Writes content to a file using atomic operation (write to temp, then rename).
	# This is a fallback implementation when common.sh is not available.
	#
	# Arguments:
	#   $1: Path to file to write
	#   $2: Content to write to file
	#
	# Returns:
	#   0: File written successfully
	#   1: Failed to write file
	atomic_write_file() {
		local file="$1"
		local content="$2"

		# If target file exists but is unreadable or unwritable, remove it first to avoid potential hangs
		# This can happen if file permissions were changed (e.g., chmod 000 or chmod 444)
		# Removing unwritable files prevents mv from hanging when trying to overwrite them
		# Note: This is a fallback implementation, so we use basic checks instead of file_exists_and_readable
		if [[ -f "$file" ]] && (! [[ -r "$file" ]] || ! [[ -w "$file" ]]); then
			rm -f "$file" 2>/dev/null || true
		fi

		if ! (echo "$content" >"${file}.tmp" && mv "${file}.tmp" "$file"); then
			return 1
		fi

		# Set explicit permissions for state files (security best practice)
		# chmod 600 ensures only owner can read/write, preventing information leakage
		chmod 600 "$file" 2>/dev/null || true

		return 0
	}
}

# Define logging timestamp fallback function
#
# Defines fallback implementation for get_formatted_timestamp when logging.sh
# cannot be loaded. This is a minimal version that only provides the timestamp
# function, not the full logging infrastructure.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Defines global function: get_formatted_timestamp
define_logging_timestamp_fallback() {
	# Get formatted timestamp
	#
	# Returns a formatted timestamp string in the format "YYYY-MM-DD HH:MM:SS".
	# This is a fallback implementation when logging.sh is not available.
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	#
	# Output:
	#   Prints formatted timestamp string to stdout
	get_formatted_timestamp() {
		date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
	}
}
