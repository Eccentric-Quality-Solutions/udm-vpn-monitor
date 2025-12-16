#!/bin/bash
#
# Common functions for UDM VPN Monitor
# Shared logging and utility functions for installation/uninstallation scripts and main monitor
#
# Version: 0.0.1
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
#       source "$config_file"
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
#   1: Failed to create file (exits script if die function is available)
#
# Side effects:
#   Creates file with default content if it doesn't exist
#
# Examples:
#   ensure_file_exists "$counter_file" "0"
#   ensure_file_exists "$log_file"
#
# Note:
#   If die function is available (from logging.sh), will exit on error.
#   Otherwise, returns error code.
ensure_file_exists() {
	local file="$1"
	local default_content="${2:-}"

	if [[ ! -f "$file" ]]; then
		if ! echo "$default_content" >"$file" 2>/dev/null; then
			# Try to use die if available, otherwise return error
			if command -v die >/dev/null 2>&1; then
				die "Cannot create file: $file"
			else
				return 1
			fi
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
