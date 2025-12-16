#!/bin/bash
#
# UDM VPN Monitor
# Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters
# Implements tiered recovery: log → surgical cleanup → full restart
#
# Designed for UniFi Dream Machine (UDM) running UniFi OS 4.3+
#
# Version: 0.0.1
#

# Strict error handling: exit on error, undefined vars, pipe failures
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn-monitor.conf"
STATE_DIR="${SCRIPT_DIR}"
LOGS_DIR="${STATE_DIR}/logs"
LOCKFILE="${STATE_DIR}/vpn-monitor.lock"
LOG_FILE="${LOGS_DIR}/vpn-monitor.log"

# Script version
SCRIPT_VERSION="0.0.1"

# Default configuration values
PEER_IPS=""
VPN_NAME="Site-to-Site VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
COOLDOWN_MINUTES=15
MAX_RESTARTS_PER_HOUR=3
LOCKFILE_TIMEOUT=300
ENABLE_PING_CHECK=1
PING_TARGET_IP=""
PING_COUNT=3
PING_TIMEOUT=2
DEBUG=0
# Debug mode flag: when set, runs checks but doesn't escalate tiers
NO_ESCALATE=0

# Helper functions (defined early so they can be used throughout the script)

# Get formatted timestamp
#
# Returns a formatted timestamp string suitable for log entries.
# Format: YYYY-MM-DD HH:MM:SS
# Handles date command failures gracefully with fallback.
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints formatted timestamp to stdout
get_formatted_timestamp() {
	# Try date command with fallback (handles both Linux and BSD/macOS)
	date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
}

# Ensure directory exists
#
# Creates a directory if it doesn't exist, with consistent error handling.
# Exits script with error message if directory creation fails.
#
# Arguments:
#   $1: Directory path to create
#   $2: Description of directory (for error message, e.g., "state", "logs")
#
# Returns:
#   0: Directory exists or was created successfully
#   1: Failed to create directory (exits script)
#
# Side effects:
#   Exits script with error code 1 if directory creation fails
ensure_directory_exists() {
	local dir="$1"
	local description="${2:-directory}"

	if ! mkdir -p "$dir" 2>/dev/null; then
		echo "ERROR: Cannot create ${description} directory: $dir" >&2
		exit 1
	fi
}

# Log lockfile conflict and exit
#
# Logs a warning message about lockfile conflict and exits the script.
# Handles both log file write and stderr output consistently.
#
# Arguments:
#   $1: Optional PID of conflicting process (for message context)
#   $2: Optional custom message (defaults to "Another instance is already running")
#
# Returns:
#   Never returns (exits with code 0)
#
# Side effects:
#   - Writes to log file (if possible)
#   - Outputs to stderr
#   - Exits script with code 0
log_and_exit_lockfile_conflict() {
	local pid="${1:-}"
	local custom_message="${2:-}"
	local timestamp
	timestamp=$(get_formatted_timestamp)

	# Build message
	local message
	if [[ -n "$custom_message" ]]; then
		message="$custom_message"
	elif [[ -n "$pid" ]]; then
		message="Another instance (PID $pid) is already running, exiting"
	else
		message="Another instance is already running, exiting"
	fi

	# Try to log to file (may fail if lockfile issue prevents access)
	echo "[$timestamp] [WARNING] $message" >>"$LOG_FILE" 2>/dev/null || true

	# Always output to stderr
	echo "WARNING: $message" >&2

	exit 0
}

# Extract PID from lockfile
#
# Extracts the process ID from a lockfile in the format "timestamp:pid".
# Returns empty string if lockfile doesn't exist or PID cannot be extracted.
#
# Arguments:
#   $1: Optional lockfile path (defaults to $LOCKFILE)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints PID to stdout (or empty string if unavailable)
extract_lockfile_pid() {
	local lockfile="${1:-$LOCKFILE}"
	cat "$lockfile" 2>/dev/null | cut -d: -f2 || echo ""
}

# Check if process is running
#
# Checks if a process with the given PID is currently running.
# Uses kill -0 which checks process existence without sending a signal.
#
# Arguments:
#   $1: Process ID to check
#
# Returns:
#   0: Process is running
#   1: Process is not running or PID is empty
is_process_running() {
	local pid="$1"

	if [[ -z "$pid" ]]; then
		return 1 # Empty PID, not running
	fi

	if kill -0 "$pid" 2>/dev/null; then
		return 0 # Process is running
	else
		return 1 # Process is not running
	fi
}

# Create lockfile atomically
#
# Creates a lockfile atomically using noclobber mode (set -C).
# Format: timestamp:pid
# Sets up trap for cleanup on exit.
#
# Arguments:
#   $1: Optional lockfile path (defaults to $LOCKFILE)
#
# Returns:
#   0: Lockfile created successfully
#   1: Failed to create lockfile (already exists or other error)
#
# Side effects:
#   - Creates lockfile with timestamp:pid format
#   - Sets up trap to remove lockfile on EXIT, INT, TERM
create_lockfile_atomically() {
	local lockfile="${1:-$LOCKFILE}"

	# set -C: noclobber mode - prevents overwriting existing file (atomic check-and-create)
	if (
		set -C
		echo "$(date +%s):$$" >"$lockfile"
	) 2>/dev/null; then
		# Set up trap to remove lockfile on exit
		trap "rm -f $lockfile" EXIT INT TERM
		return 0 # Success
	else
		return 1 # Failed (file already exists or other error)
	fi
}

# Parse help flags early (before directory creation)
# This allows --help/-h to work even if directories don't exist
for arg in "$@"; do
	case "$arg" in
	--help | -h)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		echo "Monitors Site-to-Site VPN connections using IPsec xfrm state byte counters."
		echo "Implements tiered recovery: log → surgical cleanup → full restart"
		echo ""
		echo "Options:"
		echo "  --fake     Run checks and log failures but don't escalate tiers"
		echo "  --help     Show this help message"
		echo "  --version  Show version information"
		echo ""
		exit 0
		;;
	--version | -v)
		echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
		exit 0
		;;
	esac
done

# Ensure state directory exists (needed before logging)
ensure_directory_exists "$STATE_DIR" "state"

# Ensure logs directory exists (needed before logging)
ensure_directory_exists "$LOGS_DIR" "logs"

# State files
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"
# LAST_BYTES_FILE will be per-peer: ${STATE_DIR}/last_bytes_<peer_ip_sanitized>
COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"

# Logging function (defined early so it can be used during config loading)
# Note: This function must not cause script exit even if logging fails
#
# Logs a message with timestamp and level to both log file and stderr (for errors/warnings/debug)
# This function is designed to be resilient - it will not fail the script if logging fails
#
# Arguments:
#   $1: Log level (INFO, WARNING, ERROR, DEBUG)
#   $2+: Message text (all remaining arguments are concatenated)
#
# Returns:
#   0: Always returns 0 (never fails the script)
#
# Output:
#   - Writes to LOG_FILE (append mode)
#   - Outputs ERROR/WARNING/DEBUG to stderr
#   - Creates log directory if it doesn't exist
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

	# Always output ERROR and WARNING to stderr, and DEBUG if enabled
	if [[ "${DEBUG:-0}" -eq 1 ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]]; then
		echo "$log_entry" >&2
	fi

	return 0
}

# Recalculate log file paths after configuration changes
#
# Updates LOG_FILE and LOGS_DIR based on configuration overrides.
# If LOG_FILE was overridden (via config or environment), derives LOGS_DIR from LOG_FILE.
# Otherwise, uses STATE_DIR/logs as the default location.
#
# Side effects:
#   - Updates global LOGS_DIR variable
#   - Updates global LOG_FILE variable
#
# Note:
#   This function should be called after loading configuration or when STATE_DIR changes
#   to ensure log paths reflect the current configuration.
recalculate_log_paths() {
	if [[ "$LOG_FILE" != "${LOGS_DIR}/vpn-monitor.log" ]]; then
		# LOG_FILE was overridden (via config or environment), derive LOGS_DIR from it
		LOGS_DIR=$(dirname "$LOG_FILE")
	else
		# LOG_FILE not overridden, use STATE_DIR/logs
		LOGS_DIR="${STATE_DIR}/logs"
		LOG_FILE="${LOGS_DIR}/vpn-monitor.log"
	fi
}

# Test log file write capability early (before config loading)
#
# This test uses the default LOG_FILE path (${STATE_DIR}/logs/vpn-monitor.log).
# If LOG_FILE is later overridden in config, subsequent logs will go to the new location,
# but this initial test message will remain in the default location. This is intentional:
# the early test validates that the default log location is writable, which is important
# for error handling during config loading. If config loading fails, error messages can
# still be written to the default location.
#
# Note:
#   After config loading, recalculate_log_paths() is called to update LOG_FILE/LOGS_DIR
#   if they were overridden. The new log directory is created at that point.
if ! touch "$LOG_FILE" 2>/dev/null; then
	echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
	echo "ERROR: Check permissions on directory: $(dirname "$LOG_FILE")" >&2
	exit 1
fi

# Verify logging works by writing a test message
# This ensures log_message function will work before we proceed
if ! echo "[$(get_formatted_timestamp)] [INFO] Log file initialized" >>"$LOG_FILE" 2>/dev/null; then
	echo "ERROR: Cannot write to log file after touch test: $LOG_FILE" >&2
	exit 1
fi

# Load configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
	# Validate config file is readable and not empty
	if [[ ! -r "$CONFIG_FILE" ]]; then
		log_message "ERROR" "Configuration file is not readable: $CONFIG_FILE"
		exit 1
	fi
	# shellcheck source=/dev/null
	# Source config file to load user-defined variables (overrides defaults)
	if ! source "$CONFIG_FILE" 2>&1; then
		log_message "ERROR" "Failed to source configuration file: $CONFIG_FILE"
		exit 1
	fi

	# Recalculate LOG_FILE path before first log message (in case LOG_FILE was overridden in config)
	recalculate_log_paths

	log_message "INFO" "Configuration loaded from: $CONFIG_FILE"
else
	# Recalculate LOG_FILE path before first log message (in case STATE_DIR was set via environment)
	recalculate_log_paths

	log_message "WARNING" "Configuration file not found: $CONFIG_FILE"
	log_message "WARNING" "Using default configuration values"
fi

# Ensure logs directory exists after config loading (in case paths changed)
ensure_directory_exists "$LOGS_DIR" "logs"

# Update state file paths to use LOGS_DIR (in case STATE_DIR was overridden)
# Note: Failure counters are per-peer: ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
RESTART_COUNT_FILE="${LOGS_DIR}/restart_count"

# Initialize state files if they don't exist
#
# Creates required state files (restart_count) if they don't exist.
# Per-peer failure counter and byte counter files are created on-demand when needed.
#
# State files:
#   - RESTART_COUNT_FILE: Tracks restart timestamps for rate limiting
#   - Per-peer failure counters: Created on-demand as failure_counter_<peer_ip>
#   - Per-peer byte counters: Created on-demand as last_bytes_<peer_ip>
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail)
init_state() {
	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		echo "0" >"$RESTART_COUNT_FILE" || log_message "WARNING" "Failed to create restart count file"
	fi
	# Per-peer failure counters and byte counters are created on-demand
}

# Get current failure counter for a specific peer
#
# Reads the current consecutive failure count from the per-peer state file.
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   Current failure count (0 if file doesn't exist or is empty)
#
# Output:
#   Prints the failure count to stdout
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
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   New failure count value
#
# Output:
#   Prints the new failure count to stdout
increment_failure() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	local count
	count=$(get_failure_count "$peer_ip")
	echo "$((count + 1))" >"$counter_file"
	echo "$((count + 1))"
}

# Reset failure counter for a specific peer
#
# Resets the consecutive failure counter to 0 for the specified peer.
# Called when VPN check succeeds after previous failures for this peer.
# Each peer has its own independent failure counter.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Always succeeds
reset_failure_count() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local counter_file="${LOGS_DIR}/failure_counter_${peer_sanitized}"
	echo "0" >"$counter_file"
}

# Check if we're in cooldown period
#
# Verifies if the script is currently in a cooldown period after a restart.
# Cooldown periods prevent immediate re-restarts and allow VPN to stabilize.
#
# Returns:
#   0: Currently in cooldown period
#   1: Not in cooldown (or cooldown expired)
#
# Side effects:
#   Removes cooldown file if it has expired
check_cooldown() {
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ $now -lt $cooldown_until ]]; then
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

# Get timestamp plus N minutes
#
# Returns a Unix timestamp (seconds since epoch) that is N minutes in the future.
# Handles Linux and BSD/macOS date command differences.
#
# Arguments:
#   $1: Number of minutes to add
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the future timestamp to stdout
get_timestamp_plus_minutes() {
	local minutes="$1"
	# Try Linux date format first, then BSD/macOS, fallback to manual calculation
	# +%s: output as seconds since epoch
	date -d "+${minutes} minutes" +%s 2>/dev/null || date -v+${minutes}M +%s 2>/dev/null || echo $(($(date +%s) + minutes * 60))
}

# Get file modification time as timestamp
#
# Returns the file modification time as a Unix timestamp (seconds since epoch).
# Handles Linux and BSD/macOS stat command differences.
#
# Arguments:
#   $1: File path
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints the modification timestamp to stdout (or "0" if unavailable)
get_file_mtime() {
	local file="$1"
	# Try Linux stat format first, then BSD/macOS format
	# -c %Y: Linux format, modification time as seconds since epoch
	# -f %m: BSD/macOS format, modification time as seconds since epoch
	stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
}

# Set cooldown period
#
# Sets a cooldown period to prevent immediate re-restarts after a full restart.
# The cooldown period is stored as a timestamp in COOLDOWN_UNTIL_FILE.
#
# Arguments:
#   $1: Cooldown duration in minutes
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates/updates COOLDOWN_UNTIL_FILE with expiration timestamp
set_cooldown() {
	local minutes="$1"
	local cooldown_until
	cooldown_until=$(get_timestamp_plus_minutes "$minutes")
	echo "$cooldown_until" >"$COOLDOWN_UNTIL_FILE"
	log_message "INFO" "Cooldown period set for $minutes minutes"
}

# Check rate limiting
#
# Verifies if the maximum number of restarts per hour has been exceeded.
# Prevents restart loops by limiting how frequently full restarts can occur.
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Rate limit exceeded (restart blocked)
#
# Note:
#   Checks RESTART_COUNT_FILE for timestamps within the last hour
check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - 3600))

	# Get restart count file (format: timestamp per line)
	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	# Count restarts in the last hour
	# awk filters timestamps > one_hour_ago, wc -l counts lines, tr removes whitespace
	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
		log_message "WARNING" "Rate limit exceeded: $recent_restarts restarts in last hour (max: $MAX_RESTARTS_PER_HOUR)"
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

# Record restart timestamp
#
# Records the current timestamp to RESTART_COUNT_FILE for rate limiting.
# Also cleans up old entries (older than 24 hours) to prevent file growth.
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Appends timestamp to RESTART_COUNT_FILE
#   - Removes entries older than 24 hours from RESTART_COUNT_FILE
record_restart() {
	local timestamp
	timestamp=$(date +%s)
	echo "$timestamp" >>"$RESTART_COUNT_FILE"

	# Keep only last 24 hours of timestamps (cleanup old entries)
	# Prevents restart count file from growing indefinitely
	local one_day_ago
	one_day_ago=$((timestamp - 86400))
	# awk filters lines where first field (timestamp) > cutoff, writes to temp file
	awk -v cutoff="$one_day_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" >"${RESTART_COUNT_FILE}.tmp" 2>/dev/null || true
	mv "${RESTART_COUNT_FILE}.tmp" "$RESTART_COUNT_FILE" 2>/dev/null || true
}

# Sanitize peer IP for use in filenames
#
# Converts IP address characters that are unsafe for filenames to underscores.
# Used to create per-peer state files (e.g., last_bytes_192_168_1_1).
#
# Arguments:
#   $1: IP address (IPv4 or IPv6)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints sanitized IP address to stdout (dots and colons replaced with underscores)
sanitize_peer_ip() {
	local ip="$1"
	echo "$ip" | tr '.' '_' | tr ':' '_'
}

# Discover connection name from swanctl
#
# Attempts to discover the connection name for a peer IP by parsing swanctl output.
# Uses swanctl --list-sas to find active Security Associations and match them to connection names.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Connection name discovered and printed to stdout
#   1: Connection name not found (empty output)
#
# Output:
#   Prints connection name to stdout if discovered, empty string otherwise
#
# Note:
#   This function parses swanctl --list-sas output which typically shows:
#   "connection-name: #X, ESTABLISHED, <peer_ip>..."
#   We extract the connection name from lines containing the peer IP.
discover_connection_name() {
	local peer_ip="$1"

	if ! command -v swanctl >/dev/null 2>&1; then
		return 1
	fi

	# Get swanctl SA list and find entries matching this peer IP
	# swanctl --list-sas output format varies, but typically shows:
	# "connection-name: #X, ESTABLISHED, <peer_ip>..." or similar
	# We look for lines containing the peer IP and extract the connection name
	local sa_output
	sa_output=$(swanctl --list-sas 2>/dev/null || true)

	if [[ -z "$sa_output" ]]; then
		return 1
	fi

	# Try to extract connection name from SA output
	# Pattern: connection-name followed by colon, then peer IP appears later
	# We look for lines containing the peer IP and extract the connection name (first field before colon)
	local connection_name
	connection_name=$(echo "$sa_output" | grep -i "$peer_ip" | head -1 | sed -n 's/^\([^:]*\):.*/\1/p' | tr -d ' ' || true)

	# Alternative: try swanctl --list-conns and match by peer IP in connection details
	if [[ -z "$connection_name" ]]; then
		local conns_output
		conns_output=$(swanctl --list-conns 2>/dev/null || true)

		if [[ -n "$conns_output" ]]; then
			# Parse connection list - format varies, try to find connection with matching peer
			# This is a fallback method - may not always work depending on swanctl output format
			connection_name=$(echo "$conns_output" | grep -B5 -i "$peer_ip" | grep -E "^[a-zA-Z0-9_-]+:" | head -1 | sed 's/:.*//' | tr -d ' ' || true)
		fi
	fi

	if [[ -n "$connection_name" ]]; then
		echo "$connection_name"
		return 0
	else
		return 1
	fi
}

# Cache discovered connection name
#
# Stores a discovered connection name in a state file for future use.
# This avoids repeated discovery operations and improves performance.
#
# Arguments:
#   $1: Peer IP address
#   $2: Connection name to cache
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   Creates/updates connection name cache file: ${STATE_DIR}/connection_name_<sanitized_peer_ip>
cache_connection_name() {
	local peer_ip="$1"
	local connection_name="$2"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local cache_file="${STATE_DIR}/connection_name_${peer_sanitized}"

	echo "$connection_name" >"$cache_file" 2>/dev/null || true
}

# Get cached connection name
#
# Retrieves a previously discovered connection name from the cache.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Cached connection name found and printed to stdout
#   1: No cached connection name (empty output)
#
# Output:
#   Prints cached connection name to stdout if found
get_cached_connection_name() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local cache_file="${STATE_DIR}/connection_name_${peer_sanitized}"

	if [[ -f "$cache_file" ]]; then
		local connection_name
		connection_name=$(cat "$cache_file" 2>/dev/null | head -1 | tr -d '\n\r ' || true)

		if [[ -n "$connection_name" ]]; then
			echo "$connection_name"
			return 0
		fi
	fi

	return 1
}

# Get connection name for a peer IP
#
# Retrieves the connection name for a peer IP using the following priority:
# 1. Check configuration file (CONNECTION_NAME_<sanitized_peer_ip>)
# 2. Check cached discovered connection name
# 3. Attempt to discover from swanctl and cache the result
#
# This allows per-peer connection-specific reloads using swanctl --reload-conn.
# Connection names are automatically discovered if not configured.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Connection name found and printed to stdout
#   1: Connection name not found (empty output)
#
# Output:
#   Prints connection name to stdout if found, empty string otherwise
#
# Example:
#   If config contains: CONNECTION_NAME_203_0_113_1="site-to-site-1"
#   Then get_connection_name "203.0.113.1" outputs: "site-to-site-1"
#
#   If not configured, attempts to discover from swanctl and caches the result.
get_connection_name() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local var_name="CONNECTION_NAME_${peer_sanitized}"

	# Priority 1: Check configuration file
	local connection_name="${!var_name:-}"

	if [[ -n "$connection_name" ]]; then
		echo "$connection_name"
		return 0
	fi

	# Priority 2: Check cached discovered connection name
	if connection_name=$(get_cached_connection_name "$peer_ip" 2>/dev/null); then
		echo "$connection_name"
		return 0
	fi

	# Priority 3: Attempt to discover from swanctl
	if connection_name=$(discover_connection_name "$peer_ip" 2>/dev/null); then
		# Cache the discovered connection name for future use
		cache_connection_name "$peer_ip" "$connection_name"
		log_message "INFO" "Auto-discovered connection name for $peer_ip: $connection_name"
		echo "$connection_name"
		return 0
	fi

	return 1
}

# Check connectivity via ping
#
# Verifies end-to-end connectivity through the VPN tunnel by pinging a target IP.
# This complements xfrm state checks by confirming actual traffic can flow.
#
# Arguments:
#   $1: Target IP address to ping (IPv4 or IPv6)
#
# Returns:
#   0: Ping successful (packet loss < 100%)
#   1: Ping failed (100% packet loss or command error)
#
# Configuration:
#   Uses PING_COUNT and PING_TIMEOUT from config file
#   Automatically detects IPv4 vs IPv6 and uses appropriate ping command
#
# Note:
#   Tries multiple ping command formats for compatibility (Linux/BSD)
check_ping_connectivity() {
	local target_ip="$1"
	local ping_count="${PING_COUNT:-3}"
	local ping_timeout="${PING_TIMEOUT:-2}"

	# Validate ping target
	if [[ -z "$target_ip" ]]; then
		log_message "WARNING" "Ping check enabled but PING_TARGET_IP not configured"
		return 1
	fi

	# Check if ping command is available
	if ! command -v ping >/dev/null 2>&1; then
		log_message "WARNING" "Ping check enabled but ping command not available"
		return 1
	fi

	# Determine ping command based on IP version
	# Some systems have separate ping6, others use ping -6
	local ping_cmd
	if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		# IPv4
		ping_cmd="ping"
	else
		# IPv6
		if command -v ping6 >/dev/null 2>&1; then
			ping_cmd="ping6"
		elif ping -6 >/dev/null 2>&1; then
			ping_cmd="ping -6"
		else
			log_message "WARNING" "IPv6 ping not available"
			return 1
		fi
	fi

	# Perform ping check
	# Try Linux-style ping first (-W for timeout), fallback to BSD-style (-w)
	# -c: count of packets, -q: quiet (summary only), -W/-w: timeout per packet
	local ping_result
	local ping_success=0

	# Try Linux-style ping (most common on UDM)
	if ping_result=$($ping_cmd -c "$ping_count" -W "$ping_timeout" -q "$target_ip" 2>&1); then
		ping_success=1
	# Try BSD-style ping as fallback
	elif ping_result=$($ping_cmd -c "$ping_count" -w "$ping_timeout" -q "$target_ip" 2>&1); then
		ping_success=1
	# Try without timeout flag (some systems)
	elif ping_result=$($ping_cmd -c "$ping_count" -q "$target_ip" 2>&1); then
		ping_success=1
	fi

	if [[ $ping_success -eq 1 ]]; then
		# Extract packet loss percentage
		local packet_loss
		packet_loss=$(echo "$ping_result" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' || echo "100")

		if [[ "$packet_loss" -lt 100 ]]; then
			log_message "DEBUG" "Ping check OK: $target_ip (${packet_loss}% packet loss)"
			return 0
		else
			log_message "WARNING" "Ping check failed: $target_ip (100% packet loss)"
			return 1
		fi
	else
		# Ping command failed
		log_message "WARNING" "Ping check failed: $target_ip (ping command error or timeout)"
		return 1
	fi
}

# Validate IP address format
#
# Validates that an IP address is properly formatted as either IPv4 or IPv6.
# For IPv4: Validates 4 octets, each 0-255
# For IPv6: Validates proper IPv6 format including:
#   - Proper segment count (max 8 segments)
#   - Valid hex digits (0-9, a-f, A-F)
#   - Proper :: compression (only one allowed)
#   - Segment length (1-4 hex digits per segment)
#   - Handles IPv4-mapped IPv6 addresses (::ffff:x.x.x.x)
#
# Arguments:
#   $1: IP address to validate
#
# Returns:
#   0: IP address is valid
#   1: IP address is invalid
#
# Examples:
#   validate_ip_address "192.168.1.1"        # Returns 0 (valid IPv4)
#   validate_ip_address "2001:db8::1"        # Returns 0 (valid IPv6)
#   validate_ip_address "::::"               # Returns 1 (invalid)
#   validate_ip_address "1:2:3:4:5:6:7:8:9" # Returns 1 (too many segments)
validate_ip_address() {
	local ip="$1"

	# Check for empty input
	if [[ -z "$ip" ]]; then
		return 1
	fi

	# Validate IPv4 format
	# Pattern: 4 octets separated by dots, each 0-255
	if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		# Validate each octet is 0-255
		local IFS='.'
		local -a octets
		read -ra octets <<<"$ip"
		for octet in "${octets[@]}"; do
			# Remove leading zeros for numeric comparison (but allow "0")
			local num=$((10#$octet))
			if [[ $num -lt 0 ]] || [[ $num -gt 255 ]]; then
				return 1
			fi
		done
		return 0
	fi

	# Handle IPv4-mapped IPv6 addresses (::ffff:x.x.x.x or ::ffff:0:x.x.x.x)
	# Check this BEFORE hex/colons validation since these addresses contain dots
	if [[ "$ip" =~ ^::ffff: ]]; then
		# Extract the part after ::ffff:
		local after_prefix="${ip#::ffff:}"
		# Check if it's ::ffff:0:x.x.x.x format or ::ffff:x.x.x.x format
		if [[ "$after_prefix" =~ ^0:[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			# Format: ::ffff:0:x.x.x.x - extract IPv4 part
			local ipv4_part="${after_prefix#0:}"
			if validate_ip_address "$ipv4_part"; then
				return 0
			fi
		elif [[ "$after_prefix" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			# Format: ::ffff:x.x.x.x - validate IPv4 part directly
			if validate_ip_address "$after_prefix"; then
				return 0
			fi
		fi
	fi

	# Validate IPv6 format
	# Must contain only hex digits and colons
	if [[ ! "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
		return 1
	fi

	# Allow :: (unspecified address), but reject addresses that are all single colons
	if [[ "$ip" == "::" ]]; then
		return 0
	fi
	if [[ "$ip" =~ ^:+$ ]] && [[ "$ip" != "::" ]]; then
		return 1
	fi

	# Reject triple or more consecutive colons (only :: is allowed)
	if [[ "$ip" =~ ::: ]]; then
		return 1
	fi

	# Count occurrences of :: (must be exactly 0 or 1)
	# Check if removing one :: still leaves another ::
	local temp_ip="${ip/::/}"
	if [[ "$temp_ip" == *"::"* ]]; then
		# More than one :: found
		return 1
	fi

	# Split by :: to handle compression
	local before_compression=""
	local after_compression=""
	local has_compression=0

	if [[ "$ip" == *"::"* ]]; then
		has_compression=1
		# Split on :: (first occurrence)
		before_compression="${ip%%::*}"
		after_compression="${ip#*::}"
	else
		# No compression, treat entire string as segments
		before_compression="$ip"
	fi

	# Count segments before compression
	local segments_before=0
	if [[ -n "$before_compression" ]]; then
		# Count colons (segments = colons + 1)
		local colons_before
		colons_before=$(echo "$before_compression" | tr -cd ':' | wc -c)
		segments_before=$((colons_before + 1))

		# Validate each segment before compression
		local IFS=':'
		local -a segs_before
		read -ra segs_before <<<"$before_compression"
		for seg in "${segs_before[@]}"; do
			# Each segment must be 1-4 hex digits
			if [[ ! "$seg" =~ ^[0-9a-fA-F]{1,4}$ ]]; then
				return 1
			fi
		done
	fi

	# Count segments after compression
	local segments_after=0
	if [[ -n "$after_compression" ]]; then
		# Count colons (segments = colons + 1)
		local colons_after
		colons_after=$(echo "$after_compression" | tr -cd ':' | wc -c)
		segments_after=$((colons_after + 1))

		# Validate each segment after compression
		local IFS=':'
		local -a segs_after
		read -ra segs_after <<<"$after_compression"
		for seg in "${segs_after[@]}"; do
			# Each segment must be 1-4 hex digits
			if [[ ! "$seg" =~ ^[0-9a-fA-F]{1,4}$ ]]; then
				return 1
			fi
		done
	fi

	# Total segments must be <= 8
	local total_segments=$((segments_before + segments_after))
	if [[ $has_compression -eq 1 ]]; then
		# With compression, total can be < 8 (compression fills missing segments)
		if [[ $total_segments -gt 7 ]]; then
			return 1
		fi
	else
		# Without compression, must be exactly 8 segments
		if [[ $total_segments -ne 8 ]]; then
			return 1
		fi
	fi

	# Reject addresses starting or ending with single colon (unless it's part of ::)
	if [[ "$ip" =~ ^:[^:] ]] || [[ "$ip" =~ [^:]:$ ]]; then
		return 1
	fi

	return 0
}

# Extract byte counter from xfrm output
#
# Parses the output of 'ip xfrm state' to extract the current byte counter value.
# Handles various formats and edge cases robustly.
#
# Arguments:
#   $1: xfrm output text (from 'ip xfrm state' command)
#
# Returns:
#   0: Byte counter successfully extracted
#   1: Byte counter not found or invalid
#
# Output:
#   Prints the byte counter value to stdout (if found)
extract_byte_counter() {
	local xfrm_output="$1"
	local bytes=""

	# Find the line containing "lifetime current:"
	local lifetime_line
	lifetime_line=$(echo "$xfrm_output" | grep "lifetime current:" | head -1)

	if [[ -z "$lifetime_line" ]]; then
		return 1
	fi

	# Parse the lifetime line more robustly
	# Format examples:
	#   "lifetime current: 123456 bytes, 789 packets"
	#   "lifetime current: 123456 bytes"
	#   "lifetime current: 123456 bytes, 789 packets, 123 seconds"

	# Extract the number before "bytes" that comes after "lifetime current:"
	# Use a more specific pattern: match digits immediately before "bytes" keyword
	# This avoids matching other numbers in the line
	if [[ "$lifetime_line" =~ lifetime[[:space:]]+current:[[:space:]]+([0-9]+)[[:space:]]+bytes ]]; then
		bytes="${BASH_REMATCH[1]}"
	else
		# Fallback: try sed pattern matching
		bytes=$(echo "$lifetime_line" | sed -n 's/.*lifetime[[:space:]]*current:[[:space:]]*\([0-9]*\)[[:space:]]*bytes.*/\1/p' 2>/dev/null || echo "")
	fi

	# Validate extracted value
	if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
		return 1
	fi

	# Additional validation: ensure it's a reasonable number (not empty, not negative)
	if [[ "$bytes" -lt 0 ]]; then
		return 1
	fi

	echo "$bytes"
	return 0
}

# Check VPN status using ip xfrm state
#
# Verifies VPN tunnel health by checking IPsec Security Association (SA) state and byte counters.
# Uses multiple methods in order: ip xfrm state (primary), swanctl (fallback), ipsec status (fallback).
# If ping checks are enabled, also verifies end-to-end connectivity.
#
# Arguments:
#   $1: Peer IP address (external/public IP of remote VPN gateway)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Detection logic:
#   1. Checks ip xfrm state for SA matching peer IP
#   2. Validates byte counters are > 0 and increasing (if available)
#   3. Falls back to swanctl --list-sas if xfrm doesn't confirm
#   4. Falls back to ipsec status if swanctl doesn't confirm
#   5. Optionally performs ping check if ENABLE_PING_CHECK=1
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
check_vpn_status() {
	local peer_ip="$1"
	local vpn_ok=0

	# Validate peer IP format using proper validation function
	if ! validate_ip_address "$peer_ip"; then
		log_message "ERROR" "Invalid peer IP format: $peer_ip"
		return 1
	fi

	# Per-peer bytes file
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local last_bytes_file="${STATE_DIR}/last_bytes_${peer_sanitized}"

	# Try ip xfrm state first (most reliable)
	# xfrm = Linux IPsec framework - shows Security Associations (SAs) and byte counters
	if command -v ip >/dev/null 2>&1; then
		local xfrm_output
		# Use word boundaries to avoid partial IP matches (e.g., 192.168.1.1 matching 192.168.1.10)
		# -A 10: show 10 lines after match (to get byte counter info)
		xfrm_output=$(ip xfrm state 2>/dev/null | grep -E "(^|[^0-9a-fA-F:])${peer_ip}([^0-9a-fA-F:]|$)" -A 10 || true)

		if [[ -n "$xfrm_output" ]]; then
			# Check if we have byte counters
			local current_bytes
			if current_bytes=$(extract_byte_counter "$xfrm_output"); then
				# Successfully extracted byte counter
				# Get last known bytes
				local last_bytes=0
				if [[ -f "$last_bytes_file" ]]; then
					last_bytes=$(cat "$last_bytes_file" 2>/dev/null || echo "0")
					# Validate last_bytes is numeric
					if [[ ! "$last_bytes" =~ ^[0-9]+$ ]]; then
						last_bytes=0
					fi
				fi

				# Check if bytes are increasing or at least non-zero
				if [[ "$current_bytes" -gt 0 ]]; then
					# Bytes are non-zero, check if they're increasing
					if [[ "$current_bytes" -gt "$last_bytes" ]] || [[ "$last_bytes" -eq 0 ]]; then
						# Bytes are increasing or this is first check
						echo "$current_bytes" >"$last_bytes_file"
						vpn_ok=1
						log_message "DEBUG" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes)"
					else
						log_message "WARNING" "VPN suspect: SA exists but bytes not increasing (current=$current_bytes, last=$last_bytes)"
					fi
				else
					log_message "WARNING" "VPN suspect: SA exists but bytes=0"
				fi
			else
				# SA exists but no byte counter info (or extraction failed)
				log_message "DEBUG" "VPN OK: SA exists for $peer_ip (no byte counter info)"
				vpn_ok=1
			fi
		else
			log_message "WARNING" "VPN suspect: No SA found for $peer_ip in xfrm state"
		fi
	fi

	# Fallback to swanctl if xfrm didn't confirm
	# swanctl = strongSwan control utility (used by UDM for IPsec management)
	if [[ $vpn_ok -eq 0 ]] && command -v swanctl >/dev/null 2>&1; then
		local swanctl_output
		swanctl_output=$(swanctl --list-sas 2>/dev/null | grep -i "$peer_ip" || true)

		if [[ -n "$swanctl_output" ]]; then
			log_message "DEBUG" "VPN OK: SA found via swanctl for $peer_ip"
			vpn_ok=1
		else
			log_message "WARNING" "VPN suspect: No SA found via swanctl for $peer_ip"
		fi
	fi

	# Fallback to ipsec status if still not confirmed
	# ipsec = legacy IPsec tools (libreswan/strongswan compatibility command)
	if [[ $vpn_ok -eq 0 ]] && command -v ipsec >/dev/null 2>&1; then
		local ipsec_output
		ipsec_output=$(ipsec status 2>/dev/null | grep -i "$peer_ip" || true)

		if [[ -n "$ipsec_output" ]]; then
			log_message "DEBUG" "VPN OK: Connection found via ipsec status for $peer_ip"
			vpn_ok=1
		else
			log_message "WARNING" "VPN suspect: No connection found via ipsec status for $peer_ip"
		fi
	fi

	# If SA exists (vpn_ok=1), verify connectivity with ping check if enabled
	if [[ $vpn_ok -eq 1 ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		# Determine ping target: use PING_TARGET_IP if configured, otherwise use peer_ip
		local ping_target="${PING_TARGET_IP:-$peer_ip}"

		if ! check_ping_connectivity "$ping_target"; then
			# SA exists but ping failed - tunnel may be broken
			log_message "WARNING" "VPN SA exists but ping check failed for $ping_target - tunnel may not be routing traffic"
			# Don't fail completely - SA exists, but mark as suspect
			# This allows xfrm to pass but warns about connectivity
			# If ping keeps failing, byte counters should also stop increasing
		else
			log_message "DEBUG" "VPN connectivity verified: ping check passed for $ping_target"
		fi
	elif [[ $vpn_ok -eq 0 ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
		# SA doesn't exist, but try ping anyway to see if there's any connectivity
		local ping_target="${PING_TARGET_IP:-$peer_ip}"
		if check_ping_connectivity "$ping_target"; then
			log_message "WARNING" "Ping check passed but no SA found - tunnel may be down but connectivity exists via other route"
		fi
	fi

	# Return 0 if OK, 1 if failed (invert vpn_ok: 1 becomes 0, 0 becomes 1)
	return $((1 - vpn_ok))
}

# Surgical SA cleanup (Tier 2 recovery)
#
# Attempts to clean up specific Security Associations for a peer.
# If a connection name is configured for the peer, attempts per-connection reload.
# Otherwise falls back to reloading all IPsec connections.
#
# Arguments:
#   $1: Peer IP address to clean up
#
# Returns:
#   0: Always succeeds (even if cleanup commands fail)
#
# Actions:
#   Reloads swanctl configuration to clean up and re-establish SAs:
#   - If CONNECTION_NAME_<peer_ip> is configured: uses swanctl --reload-conn <name> (per-connection)
#   - Otherwise: uses swanctl --reload (affects all connections)
#
# Side effects:
#   - If connection name not configured: Calls swanctl --reload which reloads ALL IPsec connections
#   - If connection name configured: Calls swanctl --reload-conn which reloads only the specified connection
#   - May temporarily disrupt VPN connections (scope depends on whether connection name is configured)
#
# Note:
#   This function relies on swanctl to properly clean up and re-establish Security Associations.
#   Direct xfrm state deletion is not attempted because it requires full selectors (src, dst, proto, spi)
#   which are not easily extractable. swanctl reload handles SA cleanup and re-establishment correctly.
#   To enable per-connection reload, configure CONNECTION_NAME_<sanitized_peer_ip> in config file.
#   Example: CONNECTION_NAME_203_0_113_1="site-to-site-1"
surgical_cleanup() {
	local peer_ip="$1"
	log_message "INFO" "Attempting surgical SA cleanup for $peer_ip"

	# Reload connection using swanctl to clean up and re-establish SAs
	if command -v swanctl >/dev/null 2>&1; then
		local connection_name
		if connection_name=$(get_connection_name "$peer_ip" 2>/dev/null); then
			# Connection name configured - use per-connection reload
			log_message "INFO" "Using per-connection reload for $peer_ip (connection: $connection_name)"
			if swanctl --reload-conn "$connection_name" 2>/dev/null; then
				log_message "INFO" "Successfully reloaded connection: $connection_name"
			else
				log_message "WARNING" "Per-connection reload failed for $connection_name, falling back to full reload"
				swanctl --reload 2>/dev/null || true
			fi
		else
			# No connection name configured - use full reload (affects all connections)
			log_message "INFO" "No connection name configured for $peer_ip, using full reload (affects all tunnels)"
			swanctl --reload 2>/dev/null || true
		fi

		log_message "INFO" "Surgical cleanup completed for $peer_ip"
	else
		log_message "WARNING" "Cannot perform surgical cleanup: swanctl command not available"
	fi
}

# Full VPN restart (Tier 3 recovery)
#
# Performs a full restart of the IPsec service, affecting all VPN tunnels.
# This is the most disruptive recovery action and should only be used after other methods fail.
#
# Returns:
#   0: Restart successful
#   1: Restart failed (rate limited or command error)
#
# Actions:
#   1. Checks rate limiting (prevents restart loops)
#   2. Records restart timestamp for rate limiting
#   3. Executes 'ipsec restart' or 'swanctl --reload'
#   4. Sets cooldown period to allow VPN to stabilize
#
# Side effects:
#   - Affects ALL IPsec tunnels (not just the failing peer)
#   - Temporarily disrupts all Site-to-Site and remote user VPNs
#   - Sets cooldown period (COOLDOWN_MINUTES)
#
# Warning:
#   This is disruptive and should be a last resort. Consider adjusting thresholds
#   if this triggers too frequently.
full_restart() {
	log_message "WARNING" "Performing full IPsec restart (affects all VPN tunnels)"

	if ! check_rate_limit; then
		log_message "ERROR" "Rate limit exceeded, skipping full restart"
		return 1
	fi

	# Record restart
	record_restart

	# Perform restart
	if command -v ipsec >/dev/null 2>&1; then
		# Capture exit code explicitly to avoid PIPESTATUS being cleared
		# PIPESTATUS[0] = exit code of first command in pipe (ipsec), not tee
		ipsec restart 2>&1 | tee -a "$LOG_FILE"
		local ipsec_exit_code=${PIPESTATUS[0]}
		if [[ $ipsec_exit_code -ne 0 ]]; then
			log_message "ERROR" "Failed to restart IPsec service (exit code: $ipsec_exit_code)"
			return 1
		fi
	elif command -v swanctl >/dev/null 2>&1; then
		# Capture exit code explicitly to avoid PIPESTATUS being cleared
		# PIPESTATUS[0] = exit code of first command in pipe (swanctl), not tee
		swanctl --reload 2>&1 | tee -a "$LOG_FILE"
		local swanctl_exit_code=${PIPESTATUS[0]}
		if [[ $swanctl_exit_code -ne 0 ]]; then
			log_message "ERROR" "Failed to reload swanctl (exit code: $swanctl_exit_code)"
			return 1
		fi
	else
		log_message "ERROR" "Neither ipsec nor swanctl command available"
		return 1
	fi

	log_message "INFO" "Full IPsec restart completed"
	set_cooldown "$COOLDOWN_MINUTES"
	return 0
}

# Main monitoring function
#
# Monitors a single VPN peer and implements tiered recovery escalation.
# Checks VPN status and escalates recovery actions based on failure count thresholds.
#
# Arguments:
#   $1: Peer IP address to monitor
#
# Returns:
#   0: VPN is healthy (or recovered)
#   1: VPN check failed (or recovery actions taken)
#
# Tier escalation:
#   - Tier 1 (TIER1_THRESHOLD): Logging only
#   - Tier 2 (TIER2_THRESHOLD): Surgical SA cleanup (affects all tunnels)
#   - Tier 3 (TIER3_THRESHOLD): Full IPsec restart (affects all tunnels)
#
# Side effects:
#   - Increments per-peer failure counter on VPN check failure
#   - Resets per-peer failure counter on VPN recovery
#   - Executes recovery actions based on failure count
#   - Logs all actions and status changes
#
# Note:
#   Each peer has its own independent failure counter tracked in:
#   ${LOGS_DIR}/failure_counter_<peer_ip_sanitized>
#   This allows independent failure tracking and recovery per peer.
monitor_peer() {
	local peer_ip="$1"
	local failure_count

	# Check VPN status
	if check_vpn_status "$peer_ip"; then
		# VPN is OK
		failure_count=$(get_failure_count "$peer_ip")
		if [[ $failure_count -gt 0 ]]; then
			log_message "INFO" "${VPN_NAME:-VPN} recovered for $peer_ip after $failure_count failures"
			reset_failure_count "$peer_ip"
		fi
		return 0
	else
		# VPN check failed
		failure_count=$(increment_failure "$peer_ip")
		log_message "WARNING" "${VPN_NAME:-VPN} check failed for $peer_ip (failure count: $failure_count)"

		# Tier 1: Logging (triggers when failure_count >= TIER1_THRESHOLD)
		if [[ $failure_count -ge $TIER1_THRESHOLD ]]; then
			log_message "INFO" "Tier 1: Logging ${VPN_NAME:-VPN} failure for $peer_ip"
		fi

		# Tier 2: Surgical cleanup
		if [[ $failure_count -ge $TIER2_THRESHOLD ]] && [[ $failure_count -lt $TIER3_THRESHOLD ]]; then
			if [[ $NO_ESCALATE -eq 1 ]]; then
				log_message "INFO" "Tier 2: Would attempt surgical SA cleanup for $peer_ip (skipped in fake mode)"
			else
				log_message "WARNING" "Tier 2: Attempting surgical SA cleanup for $peer_ip"
				surgical_cleanup "$peer_ip"
			fi
		fi

		# Tier 3: Full restart
		if [[ $failure_count -ge $TIER3_THRESHOLD ]]; then
			if [[ $NO_ESCALATE -eq 1 ]]; then
				log_message "INFO" "Tier 3: Would attempt full IPsec restart (skipped in fake mode)"
			else
				log_message "ERROR" "Tier 3: Attempting full IPsec restart"
				if full_restart; then
					reset_failure_count "$peer_ip"
				fi
			fi
		fi

		return 1
	fi
}

# Check cron persistence
#
# Verifies that the cron job entry still exists in the crontab.
# This helps detect if cron jobs were removed during UniFi OS upgrades.
#
# Returns:
#   0: Always succeeds (warnings logged but don't fail script)
#
# Side effects:
#   Logs warning if cron job not found
#
# Note:
#   This check is performed once per script run (tracked via .cron_checked file)
#   to avoid log spam on every execution.
check_cron_persistence() {
	if ! crontab -l 2>/dev/null | grep -q "vpn-monitor.sh"; then
		log_message "WARNING" "Cron job not found! Persistence may have been lost."
		log_message "WARNING" "Re-run install.sh to restore cron job."
	fi
}

# Parse command-line arguments
#
# Processes command-line arguments and sets corresponding global flags.
#
# Arguments:
#   $@: Command-line arguments
#
# Supported options:
#   --fake: Enable fake mode (NO_ESCALATE=1) - runs checks but doesn't escalate tiers
#   --help, -h: Display help message and exit
#   --version, -v: Display version information and exit
#
# Returns:
#   0: Always succeeds (exits with 0 for --help/--version)
#
# Side effects:
#   Sets NO_ESCALATE flag if --fake is provided
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--fake)
			NO_ESCALATE=1
			log_message "INFO" "Fake mode enabled: tier escalation disabled"
			shift
			;;
		--help | -h)
			echo "Usage: $0 [OPTIONS]"
			echo ""
			echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
			echo ""
			echo "Options:"
			echo "  --fake     Run checks and log failures but don't escalate tiers"
			echo "  --help     Show this help message"
			echo "  --version  Show version information"
			echo ""
			exit 0
			;;
		--version | -v)
			echo "UDM VPN Monitor v${SCRIPT_VERSION:-0.0.1}"
			exit 0
			;;
		*)
			log_message "WARNING" "Unknown argument: $1 (use --help for usage)"
			shift
			;;
		esac
	done
}

# Main execution
#
# Main entry point for the VPN monitor script.
# Initializes state, checks cooldown, validates configuration, and monitors all configured peers.
#
# Arguments:
#   $@: Command-line arguments (passed to parse_args)
#
# Returns:
#   0: All peers healthy or checks completed successfully
#   1: One or more peers failed checks or configuration error
#
# Execution flow:
#   1. Parse command-line arguments
#   2. Initialize state files
#   3. Check cooldown period (exit if in cooldown)
#   4. Check cron persistence (once per run)
#   5. Validate PEER_IPS configuration
#   6. Monitor each configured peer IP
#   7. Exit with appropriate status code
#
# Side effects:
#   - Creates state files and directories
#   - Writes to log file
#   - May execute recovery actions (if not in fake mode)
main() {
	# Parse command-line arguments
	parse_args "$@"

	# Log script start
	if [[ $NO_ESCALATE -eq 1 ]]; then
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started in fake mode (PID: $$) - tier escalation disabled"
	else
		log_message "INFO" "${VPN_NAME:-VPN} monitor script started (PID: $$)"
	fi

	# Debug output (only if DEBUG=1)
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Starting main() function, PID: $$" >&2
		echo "DEBUG: After log_message call" >&2
	fi

	# Initialize state
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Calling init_state()" >&2
	fi
	init_state
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: After init_state()" >&2
	fi

	# Check cooldown
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Checking cooldown" >&2
	fi
	if check_cooldown; then
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			echo "DEBUG: In cooldown, exiting" >&2
		fi
		log_message "INFO" "Script exiting: in cooldown period"
		exit 0
	fi
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Not in cooldown, continuing" >&2
	fi

	# Check cron persistence (first run only, to avoid log spam)
	if [[ ! -f "${STATE_DIR}/.cron_checked" ]]; then
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			echo "DEBUG: Checking cron persistence" >&2
		fi
		check_cron_persistence
		touch "${STATE_DIR}/.cron_checked"
	fi

	# Validate configuration
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: Validating PEER_IPS (value: '${PEER_IPS}')" >&2
	fi
	if [[ -z "$PEER_IPS" ]]; then
		if [[ "${DEBUG:-0}" -eq 1 ]]; then
			echo "DEBUG: PEER_IPS is empty, logging error and exiting" >&2
		fi
		log_message "ERROR" "PEER_IPS not configured. Please set PEER_IPS in $CONFIG_FILE"
		exit 1
	fi
	if [[ "${DEBUG:-0}" -eq 1 ]]; then
		echo "DEBUG: PEER_IPS is configured, continuing" >&2
	fi

	# Validate and process each peer IP
	local all_ok=0
	for peer_ip in $PEER_IPS; do
		# Basic validation: non-empty
		if [[ -z "$peer_ip" ]]; then
			log_message "WARNING" "Skipping empty peer IP"
			continue
		fi

		# Validate IP address format using proper validation function
		# This function handles both IPv4 and IPv6 validation, including security checks
		if ! validate_ip_address "$peer_ip"; then
			log_message "ERROR" "Invalid peer IP format: $peer_ip"
			all_ok=1
			continue
		fi

		if ! monitor_peer "$peer_ip"; then
			all_ok=1
		fi
	done

	if [[ $all_ok -eq 0 ]]; then
		log_message "INFO" "VPN monitor check completed successfully"
	else
		log_message "WARNING" "VPN monitor check completed with warnings/errors"
	fi

	exit $all_ok
}

# Remove stale lockfile if needed
#
# Checks if lockfile is stale and removes it if so, logging a warning.
# This is a helper function to reduce code duplication.
#
# Returns:
#   0: Lockfile was stale and removed (or didn't exist)
#   1: Lockfile exists and is not stale
#
# Side effects:
#   Removes stale lockfile and logs warning if removed
remove_stale_lockfile_if_needed() {
	if [[ ! -f "$LOCKFILE" ]]; then
		return 0 # No lockfile, nothing to remove
	fi

	if ! check_lockfile_stale; then
		return 1 # Lockfile exists and is not stale
	fi

	# Lockfile is stale, remove it and log
	local stale_pid
	stale_pid=$(extract_lockfile_pid "$LOCKFILE" || echo "unknown")
	rm -f "$LOCKFILE"
	echo "WARNING: Removed stale lockfile (timeout exceeded, PID was: $stale_pid)" >&2
	return 0
}

# Check if lockfile is stale (exceeded timeout)
#
# Determines if an existing lockfile is stale (older than LOCKFILE_TIMEOUT seconds).
# Stale lockfiles indicate a hung or crashed previous instance.
#
# Returns:
#   0: Lockfile is stale (exceeded timeout)
#   1: Lockfile is not stale (or doesn't exist)
#
# Note:
#   Uses stat to get file modification time, handles both Linux and BSD/macOS formats
check_lockfile_stale() {
	if [[ ! -f "$LOCKFILE" ]]; then
		return 1 # No lockfile, not stale
	fi

	local lockfile_age
	local lockfile_mtime
	local now

	now=$(date +%s)
	lockfile_mtime=$(get_file_mtime "$LOCKFILE")

	if [[ $lockfile_mtime -eq 0 ]]; then
		# Can't get mtime, assume stale if file exists but unreadable
		return 0 # Consider stale
	fi

	lockfile_age=$((now - lockfile_mtime))

	if [[ $lockfile_age -gt $LOCKFILE_TIMEOUT ]]; then
		return 0 # Stale (exceeded timeout)
	fi

	return 1 # Not stale
}

# Run with lockfile protection
# flock = file locking utility (prevents multiple instances from running simultaneously)
if command -v flock >/dev/null 2>&1; then
	# Use flock if available (preferred method)
	# Open lockfile for writing, acquire exclusive non-blocking lock
	# File descriptor 9 is used for the lockfile
	(
		# Set up cleanup trap to ensure lock is released
		trap 'rm -f "$LOCKFILE"; exec 9>&-' EXIT INT TERM

		# Check if lockfile exists and is stale before trying to acquire
		remove_stale_lockfile_if_needed || true

		# Try to acquire lock, exit if another instance is running
		# -n: non-blocking (fail immediately if lock can't be acquired)
		if ! flock -n 9; then
			# Lock acquisition failed - another instance is running
			# Check if it's stale by file age
			if check_lockfile_stale; then
				# Lockfile is stale, force remove and try again
				rm -f "$LOCKFILE"
				if ! flock -n 9; then
					# Try to log before exiting (may fail if lockfile issue)
					log_and_exit_lockfile_conflict
				fi
			else
				# Lockfile is valid, another instance is actually running
				log_and_exit_lockfile_conflict
			fi
		fi

		# Lock acquired successfully, write timestamp:pid to lockfile for timeout checking
		echo "$(date +%s):$$" >"$LOCKFILE"

		# Run main
		main "$@"

		# Explicitly close file descriptor and remove lockfile before exit
		exec 9>&-
		rm -f "$LOCKFILE"
	) 9>"$LOCKFILE"
else
	# Fallback: simple lockfile check (less reliable but better than nothing)
	# Use atomic file creation to avoid race conditions
	# Format: timestamp:pid
	lock_pid=""
	lock_acquired=0

	# Check if existing lockfile is stale
	if [[ -f "$LOCKFILE" ]]; then
		if remove_stale_lockfile_if_needed; then
			# Lockfile was stale and removed, continue to try acquiring lock
			:
		else
			# Lockfile exists and is not stale, check PID
			lock_pid=$(extract_lockfile_pid "$LOCKFILE")
			if is_process_running "$lock_pid"; then
				# Process is still running
				log_and_exit_lockfile_conflict "$lock_pid"
			fi
			# PID is dead but lockfile not stale (shouldn't happen often), remove it
			rm -f "$LOCKFILE"
		fi
	fi

	# Try to create lockfile atomically with timestamp:pid format
	if create_lockfile_atomically "$LOCKFILE"; then
		# Successfully created lockfile
		lock_acquired=1
	else
		# Race condition - another process got it first
		# Check if the PID in the lockfile is still running before exiting
		if [[ -f "$LOCKFILE" ]]; then
			lock_pid=$(extract_lockfile_pid "$LOCKFILE")
			if is_process_running "$lock_pid"; then
				# Process is still running - legitimate lockfile
				log_and_exit_lockfile_conflict "$lock_pid"
			else
				# PID is not running - stale lockfile, remove it and try again
				rm -f "$LOCKFILE"
				echo "WARNING: Removed stale lockfile (PID $lock_pid not running), retrying" >&2
				# Retry lockfile creation once
				if create_lockfile_atomically "$LOCKFILE"; then
					lock_acquired=1
				else
					# Still can't acquire after retry - another process may have gotten it
					# Check PID one more time
					if [[ -f "$LOCKFILE" ]]; then
						lock_pid=$(extract_lockfile_pid "$LOCKFILE")
						if is_process_running "$lock_pid"; then
							log_and_exit_lockfile_conflict "$lock_pid"
						fi
					fi
					# Final fallback - couldn't acquire lockfile
					log_and_exit_lockfile_conflict "" "Could not acquire lockfile after retry, exiting"
				fi
			fi
		else
			# Lockfile doesn't exist (shouldn't happen after failed creation, but handle it)
			log_and_exit_lockfile_conflict "" "Could not acquire lockfile, exiting"
		fi
	fi

	if [[ $lock_acquired -eq 1 ]]; then
		main "$@"
	fi
fi
