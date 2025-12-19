#!/bin/bash
#
# VPN status detection for UDM VPN Monitor
# Handles VPN detection using xfrm, swanctl, ipsec, and ping checks
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
	[[ -z "${MAX_IPV6_SEGMENTS:-}" ]] && readonly MAX_IPV6_SEGMENTS=8
fi

# Validate IPv4 address format
#
# Validates that an IP address is properly formatted as IPv4.
# Validates 4 octets, each 0-255.
#
# Arguments:
#   $1: IP address to validate
#
# Returns:
#   0: IP address is valid IPv4
#   1: IP address is invalid IPv4
#
# Examples:
#   validate_ipv4 "192.168.1.1"  # Returns 0 (valid)
#   validate_ipv4 "256.1.1.1"    # Returns 1 (invalid)
validate_ipv4() {
	local ip="$1"

	# Check for empty input
	if [[ -z "$ip" ]]; then
		return 1
	fi

	# Validate IPv4 format pattern: 4 octets separated by dots
	if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		return 1
	fi

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
}

# Validate IPv6 compression format
#
# Validates that an IPv6 address has proper :: compression format.
# Ensures only one :: compression exists and no triple+ colons.
#
# Arguments:
#   $1: IPv6 address to validate
#
# Returns:
#   0: Compression format is valid
#   1: Compression format is invalid
#
# Examples:
#   validate_ipv6_compression "2001:db8::1"     # Returns 0 (valid)
#   validate_ipv6_compression "2001:db8::1::2" # Returns 1 (multiple ::)
#   validate_ipv6_compression "2001:db8:::1"  # Returns 1 (triple colon)
validate_ipv6_compression() {
	local ip="$1"

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

	# Reject addresses starting or ending with single colon (unless it's part of ::)
	if [[ "$ip" =~ ^:[^:] ]] || [[ "$ip" =~ [^:]:$ ]]; then
		return 1
	fi

	return 0
}

# Validate IPv6 segments format and count
#
# Validates that IPv6 segments are properly formatted and the total count
# is within acceptable limits. Each segment must be 1-4 hex digits.
#
# Arguments:
#   $1: IPv6 address to validate
#   $2: Number of segments before compression (if any)
#   $3: Number of segments after compression (if any)
#   $4: Whether compression exists (0 or 1)
#
# Returns:
#   0: Segments are valid
#   1: Segments are invalid
#
# Examples:
#   validate_ipv6_segments "2001:db8::1" 3 1 1  # Returns 0 (valid)
#   validate_ipv6_segments "1:2:3:4:5:6:7:8:9" 9 0 0  # Returns 1 (too many)
validate_ipv6_segments() {
	local ip="$1"
	local segments_before="$2"
	local segments_after="$3"
	local has_compression="$4"

	# Split by :: to handle compression
	local before_compression=""
	local after_compression=""

	if [[ "$ip" == *"::"* ]]; then
		# Split on :: (first occurrence)
		before_compression="${ip%%::*}"
		after_compression="${ip#*::}"
	else
		# No compression, treat entire string as segments
		before_compression="$ip"
	fi

	# Validate each segment before compression
	if [[ -n "$before_compression" ]]; then
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

	# Validate each segment after compression
	if [[ -n "$after_compression" ]]; then
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

	# Total segments must be <= MAX_IPV6_SEGMENTS
	local total_segments=$((segments_before + segments_after))
	if [[ $has_compression -eq 1 ]]; then
		# With compression, total can be < MAX_IPV6_SEGMENTS (compression fills missing segments)
		if [[ $total_segments -gt $((MAX_IPV6_SEGMENTS - 1)) ]]; then
			return 1
		fi
	else
		# Without compression, must be exactly MAX_IPV6_SEGMENTS segments
		if [[ $total_segments -ne $MAX_IPV6_SEGMENTS ]]; then
			return 1
		fi
	fi

	return 0
}

# Validate IPv6 address format
#
# Validates that an IP address is properly formatted as IPv6.
# Validates proper IPv6 format including:
#   - Proper segment count (max MAX_IPV6_SEGMENTS segments)
#   - Valid hex digits (0-9, a-f, A-F)
#   - Proper :: compression (only one allowed)
#   - Segment length (1-4 hex digits per segment)
#
# Arguments:
#   $1: IP address to validate
#
# Returns:
#   0: IP address is valid IPv6
#   1: IP address is invalid IPv6
#
# Examples:
#   validate_ipv6 "2001:db8::1"        # Returns 0 (valid)
#   validate_ipv6 "::::"               # Returns 1 (invalid)
#   validate_ipv6 "1:2:3:4:5:6:7:8:9" # Returns 1 (too many segments)
validate_ipv6() {
	local ip="$1"

	# Check for empty input
	if [[ -z "$ip" ]]; then
		return 1
	fi

	# Validate IPv6 format - must contain only hex digits and colons
	if [[ ! "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
		return 1
	fi

	# Validate compression format
	if ! validate_ipv6_compression "$ip"; then
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
	fi

	# Count segments after compression
	local segments_after=0
	if [[ -n "$after_compression" ]]; then
		# Count colons (segments = colons + 1)
		local colons_after
		colons_after=$(echo "$after_compression" | tr -cd ':' | wc -c)
		segments_after=$((colons_after + 1))
	fi

	# Validate segments format and count
	if ! validate_ipv6_segments "$ip" "$segments_before" "$segments_after" "$has_compression"; then
		return 1
	fi

	return 0
}

# Validate IP address format
#
# Validates that an IP address is properly formatted as either IPv4 or IPv6.
# For IPv4: Validates 4 octets, each 0-255
# For IPv6: Validates proper IPv6 format including:
#   - Proper segment count (max MAX_IPV6_SEGMENTS segments)
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

	# Try IPv4 validation first
	if validate_ipv4 "$ip"; then
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
			if validate_ipv4 "$ipv4_part"; then
				return 0
			fi
		elif [[ "$after_prefix" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			# Format: ::ffff:x.x.x.x - validate IPv4 part directly
			if validate_ipv4 "$after_prefix"; then
				return 0
			fi
		fi
	fi

	# Try IPv6 validation
	if validate_ipv6 "$ip"; then
		return 0
	fi

	# Not valid IPv4 or IPv6
	return 1
}

# Extract byte counter from xfrm output
#
# Parses the output of 'ip xfrm state' to extract the current byte counter value.
# Handles various formats and edge cases robustly.
# Looks for "lifetime current:" line and extracts the number before "bytes".
#
# Arguments:
#   $1: xfrm output text (from 'ip xfrm state' command, may be multi-line)
#
# Returns:
#   0: Byte counter successfully extracted and printed
#   1: Byte counter not found or invalid format
#
# Output:
#   Prints the byte counter value (integer) to stdout if found
#
# Examples:
#   bytes=$(extract_byte_counter "$xfrm_output")
#   if [[ $? -eq 0 ]]; then
#       echo "Byte count: $bytes"
#   fi
#
# Note:
#   Uses regex pattern matching to extract bytes from "lifetime current:" line
#   Falls back to sed pattern if regex fails
#   Validates extracted value is numeric and non-negative
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

# Discover connection name from swanctl
#
# Attempts to discover the connection name for a peer IP by parsing swanctl output.
# Uses swanctl --list-sas to find active Security Associations and match them to connection names.
# Falls back to swanctl --list-conns if --list-sas doesn't find a match.
#
# Arguments:
#   $1: Peer IP address to find connection name for
#
# Returns:
#   0: Connection name discovered and printed to stdout
#   1: Connection name not found (swanctl unavailable or no match)
#
# Output:
#   Prints connection name to stdout if discovered, empty string otherwise
#
# Examples:
#   conn_name=$(discover_connection_name "203.0.113.1")
#   if [[ $? -eq 0 ]]; then
#       echo "Found connection: $conn_name"
#   fi
#
# Note:
#   Requires swanctl command to be available (checks via warn_if_missing)
#   Parses swanctl --list-sas output which typically shows:
#   "connection-name: #X, ESTABLISHED, <peer_ip>..."
#   Extracts connection name from lines containing the peer IP
#   Requires warn_if_missing function to be available (from logging.sh)
discover_connection_name() {
	local peer_ip="$1"

	if ! warn_if_missing "swanctl"; then
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
# Cache file format: single line with connection name.
#
# Arguments:
#   $1: Peer IP address (used to generate cache filename)
#   $2: Connection name to cache (written to file)
#
# Returns:
#   0: Always succeeds (even if file write fails silently)
#
# Side effects:
#   Creates/updates connection name cache file (atomic write):
#   ${STATE_DIR}/connection_name_<sanitized_peer_ip>
#   File contains single line with connection name (no newline)
#
# Examples:
#   cache_connection_name "203.0.113.1" "site-to-site-1"
#   # Creates: ${STATE_DIR}/connection_name_203_0_113_1
#
# Note:
#   Requires STATE_DIR, sanitize_peer_ip, and log_message to be set (from config.sh, state.sh, logging.sh)
#   File write errors are logged as warnings but don't fail the function (returns 0)
#   Uses temporary file and mv for atomic write to prevent corruption on interruption
cache_connection_name() {
	local peer_ip="$1"
	local connection_name="$2"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local cache_file="${STATE_DIR}/connection_name_${peer_sanitized}"

	# Atomic write: write to temp file first, then rename
	if ! (echo "$connection_name" >"${cache_file}.tmp" 2>/dev/null && mv "${cache_file}.tmp" "$cache_file" 2>/dev/null); then
		log_message "WARNING" "Failed to cache connection name for $peer_ip (file: $cache_file)"
	fi
}

# Get cached connection name
#
# Retrieves a previously discovered connection name from the cache file.
# Reads the first line of the cache file and trims whitespace/newlines.
#
# Arguments:
#   $1: Peer IP address (used to locate cache file)
#
# Returns:
#   0: Cached connection name found and printed to stdout
#   1: No cached connection name (file doesn't exist or is empty)
#
# Output:
#   Prints cached connection name to stdout if found (trimmed, no newlines)
#
# Examples:
#   cached_name=$(get_cached_connection_name "203.0.113.1")
#   if [[ $? -eq 0 ]] && [[ -n "$cached_name" ]]; then
#       echo "Using cached: $cached_name"
#   fi
#
# Note:
#   Requires STATE_DIR and sanitize_peer_ip to be set (from config.sh and state.sh)
#   Cache file: ${STATE_DIR}/connection_name_<sanitized_peer_ip>
#   Reads first line only and trims whitespace/newlines
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
#
# Note:
#   Requires sanitize_peer_ip, log_message, and STATE_DIR to be set
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
#   Requires log_message, PING_COUNT, PING_TIMEOUT to be set
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
	if ! warn_if_missing "ping"; then
		log_message "WARNING" "Ping check enabled but ping command not available"
		return 1
	fi

	# Determine ping command based on IP version
	# Some systems have separate ping6, others use ping -6
	local ping_cmd
	local ping_args=()
	if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		# IPv4
		ping_cmd="ping"
	else
		# IPv6
		if command -v ping6 >/dev/null 2>&1; then
			ping_cmd="ping6"
		elif ping -6 >/dev/null 2>&1; then
			ping_cmd="ping"
			ping_args=(-6)
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
	if ping_result=$("$ping_cmd" "${ping_args[@]}" -c "$ping_count" -W "$ping_timeout" -q "$target_ip" 2>&1); then
		ping_success=1
	# Try BSD-style ping as fallback
	elif ping_result=$("$ping_cmd" "${ping_args[@]}" -c "$ping_count" -w "$ping_timeout" -q "$target_ip" 2>&1); then
		ping_success=1
	# Try without timeout flag (some systems)
	elif ping_result=$("$ping_cmd" "${ping_args[@]}" -c "$ping_count" -q "$target_ip" 2>&1); then
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

# Check byte counters for VPN status
#
# Validates that byte counters are increasing or at least non-zero.
# Updates the last_bytes file with current byte count if valid.
# This ensures VPN is actively passing traffic (bytes increasing) or at least has traffic history.
#
# Arguments:
#   $1: Current byte count (integer from xfrm state)
#   $2: Path to last_bytes file (stores previous byte count for comparison)
#   $3: Peer IP address (used for logging messages)
#
# Returns:
#   0: Byte counters are valid (increasing or non-zero, first check)
#   1: Byte counters are invalid (zero or not increasing)
#
# Side effects:
#   - Updates last_bytes file if bytes are valid (writes current_bytes)
#   - Logs debug messages for valid counters
#   - Logs warning messages for invalid counters
#
# Examples:
#   if check_byte_counters "$current_bytes" "$last_bytes_file" "$peer_ip"; then
#       echo "VPN is passing traffic"
#   fi
#
# Note:
#   Requires log_message function to be available (from logging.sh)
#   First check (last_bytes=0) always passes if current_bytes > 0
#   Subsequent checks require current_bytes > last_bytes
check_byte_counters() {
	local current_bytes="$1"
	local last_bytes_file="$2"
	local peer_ip="$3"

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
			# Atomic write: write to temp file first, then rename
			if ! (echo "$current_bytes" >"${last_bytes_file}.tmp" && mv "${last_bytes_file}.tmp" "$last_bytes_file"); then
				log_message "ERROR" "Failed to update byte counter for $peer_ip (file: $last_bytes_file)"
				# Continue execution but log the error
			fi
			log_message "DEBUG" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes)"
			return 0
		else
			log_message "WARNING" "VPN suspect: SA exists but bytes not increasing (current=$current_bytes, last=$last_bytes)"
			return 1
		fi
	else
		log_message "WARNING" "VPN suspect: SA exists but bytes=0"
		return 1
	fi
}

# Check VPN status using ip xfrm state
#
# Checks for Security Association (SA) existence using ip xfrm state command.
# Validates byte counters if available.
#
# Arguments:
#   $1: Peer IP address
#   $2: Path to last_bytes file
#
# Returns:
#   0: SA found and valid
#   1: SA not found or invalid
#
# Side effects:
#   - Logs debug/warning messages
check_xfrm_status() {
	local peer_ip="$1"
	local last_bytes_file="$2"

	# Try ip xfrm state first (most reliable)
	# xfrm = Linux IPsec framework - shows Security Associations (SAs) and byte counters
	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	local xfrm_output
	# Use word boundaries to avoid partial IP matches (e.g., 192.168.1.1 matching 192.168.1.10)
	# -A 10: show 10 lines after match (to get byte counter info)
	xfrm_output=$(ip xfrm state 2>/dev/null | grep -E "(^|[^0-9a-fA-F:])${peer_ip}([^0-9a-fA-F:]|$)" -A 10 || true)

	if [[ -z "$xfrm_output" ]]; then
		log_message "WARNING" "VPN suspect: No SA found for $peer_ip in xfrm state"
		return 1
	fi

	# Check if we have byte counters
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output"); then
		# Successfully extracted byte counter - validate it
		if check_byte_counters "$current_bytes" "$last_bytes_file" "$peer_ip"; then
			return 0
		else
			# SA exists but byte counters are suspect
			return 1
		fi
	else
		# SA exists but no byte counter info (or extraction failed)
		log_message "DEBUG" "VPN OK: SA exists for $peer_ip (no byte counter info)"
		return 0
	fi
}

# Check VPN status using swanctl
#
# Checks for Security Association (SA) existence using swanctl command.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: SA found
#   1: SA not found
#
# Side effects:
#   - Logs debug/warning messages
check_swanctl_status() {
	local peer_ip="$1"

	# swanctl = strongSwan control utility (used by UDM for IPsec management)
	if ! command -v swanctl >/dev/null 2>&1; then
		return 1
	fi

	local swanctl_output
	swanctl_output=$(swanctl --list-sas 2>/dev/null | grep -i "$peer_ip" || true)

	if [[ -n "$swanctl_output" ]]; then
		log_message "DEBUG" "VPN OK: SA found via swanctl for $peer_ip"
		return 0
	else
		log_message "WARNING" "VPN suspect: No SA found via swanctl for $peer_ip"
		return 1
	fi
}

# Check VPN status using ipsec status
#
# Checks for connection existence using ipsec status command.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Connection found
#   1: Connection not found
#
# Side effects:
#   - Logs debug/warning messages
check_ipsec_status() {
	local peer_ip="$1"

	# ipsec = legacy IPsec tools (libreswan/strongswan compatibility command)
	if ! command -v ipsec >/dev/null 2>&1; then
		return 1
	fi

	local ipsec_output
	ipsec_output=$(ipsec status 2>/dev/null | grep -i "$peer_ip" || true)

	if [[ -n "$ipsec_output" ]]; then
		log_message "DEBUG" "VPN OK: Connection found via ipsec status for $peer_ip"
		return 0
	else
		log_message "WARNING" "VPN suspect: No connection found via ipsec status for $peer_ip"
		return 1
	fi
}

# Check ping connectivity if enabled
#
# Performs ping check if enabled, regardless of VPN status.
# Used to verify end-to-end connectivity or diagnose issues.
#
# Arguments:
#   $1: VPN status (0 = OK, 1 = failed)
#   $2: Peer IP address
#
# Returns:
#   0: Always succeeds (ping check is informational)
#
# Side effects:
#   - Logs warning/debug messages about ping results
check_ping_if_enabled() {
	local vpn_ok="$1"
	local peer_ip="$2"

	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Determine ping target: use PING_TARGET_IP if configured, otherwise use peer_ip
	local ping_target="${PING_TARGET_IP:-$peer_ip}"

	if [[ $vpn_ok -eq 1 ]]; then
		# SA exists, verify connectivity with ping check
		if ! check_ping_connectivity "$ping_target"; then
			# SA exists but ping failed - tunnel may be broken
			log_message "WARNING" "VPN SA exists but ping check failed for $ping_target - tunnel may not be routing traffic"
			# Don't fail completely - SA exists, but mark as suspect
			# This allows xfrm to pass but warns about connectivity
			# If ping keeps failing, byte counters should also stop increasing
		else
			log_message "DEBUG" "VPN connectivity verified: ping check passed for $ping_target"
		fi
	else
		# SA doesn't exist, but try ping anyway to see if there's any connectivity
		if check_ping_connectivity "$ping_target"; then
			log_message "WARNING" "Ping check passed but no SA found - tunnel may be down but connectivity exists via other route"
		fi
	fi

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
#
# Note:
#   Requires validate_ip_address, sanitize_peer_ip, log_message, STATE_DIR, ENABLE_PING_CHECK,
#   PING_TARGET_IP to be set
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

	# Try detection methods in order of reliability
	if check_xfrm_status "$peer_ip" "$last_bytes_file"; then
		vpn_ok=1
	elif check_swanctl_status "$peer_ip"; then
		vpn_ok=1
	elif check_ipsec_status "$peer_ip"; then
		vpn_ok=1
	fi

	# Perform ping check if enabled (informational, doesn't affect vpn_ok)
	check_ping_if_enabled "$vpn_ok" "$peer_ip"

	# Return 0 if OK, 1 if failed (invert vpn_ok: 1 becomes 0, 0 becomes 1)
	return $((1 - vpn_ok))
}
