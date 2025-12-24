#!/bin/bash
#
# VPN status detection for UDM VPN Monitor
# Handles VPN detection using xfrm, ipsec, and ping checks
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
	[[ -z "${MIN_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MIN_IPV6_SEGMENT_HEX_DIGITS=1
	[[ -z "${MAX_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MAX_IPV6_SEGMENT_HEX_DIGITS=4
	[[ -z "${MAX_IPV4_OCTET:-}" ]] && readonly MAX_IPV4_OCTET=255
	[[ -z "${IPV4_OCTET_COUNT:-}" ]] && readonly IPV4_OCTET_COUNT=4
	[[ -z "${PING_PACKET_LOSS_THRESHOLD:-}" ]] && readonly PING_PACKET_LOSS_THRESHOLD=100
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
fi

# Source common utility functions
# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh" 2>/dev/null || {
	# Fallback if common.sh not found - define minimal version
	atomic_write_file() {
		local file="$1"
		local content="$2"
		if ! (echo "$content" >"${file}.tmp" && mv "${file}.tmp" "$file"); then
			return 1
		fi
		return 0
	}
}

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

	# Validate IPv4 format pattern: IPV4_OCTET_COUNT (4) octets separated by dots
	# Each octet is 1-3 digits (0-255 range, validated separately below)
	local octet_pattern="[0-9]{1,3}"
	local ipv4_pattern="${octet_pattern}\\.${octet_pattern}\\.${octet_pattern}\\.${octet_pattern}"
	if [[ ! "$ip" =~ ^${ipv4_pattern}$ ]]; then
		return 1
	fi

	# Validate each octet is 0-MAX_IPV4_OCTET
	local IFS='.'
	local -a octets
	read -ra octets <<<"$ip"
	for octet in "${octets[@]}"; do
		# Remove leading zeros for numeric comparison (but allow "0")
		local num=$((10#$octet))
		if [[ $num -lt 0 ]] || [[ $num -gt $MAX_IPV4_OCTET ]]; then
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
			# Each segment must be MIN_IPV6_SEGMENT_HEX_DIGITS-MAX_IPV6_SEGMENT_HEX_DIGITS hex digits
			# Build regex pattern dynamically since bash doesn't support variable interpolation in regex
			local hex_pattern="^[0-9a-fA-F]{${MIN_IPV6_SEGMENT_HEX_DIGITS},${MAX_IPV6_SEGMENT_HEX_DIGITS}}$"
			if [[ ! "$seg" =~ $hex_pattern ]]; then
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
			# Each segment must be MIN_IPV6_SEGMENT_HEX_DIGITS-MAX_IPV6_SEGMENT_HEX_DIGITS hex digits
			# Build regex pattern dynamically since bash doesn't support variable interpolation in regex
			local hex_pattern="^[0-9a-fA-F]{${MIN_IPV6_SEGMENT_HEX_DIGITS},${MAX_IPV6_SEGMENT_HEX_DIGITS}}$"
			if [[ ! "$seg" =~ $hex_pattern ]]; then
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

# Extract SPI (Security Parameter Index) from xfrm output
#
# Parses the output of 'ip xfrm state' to extract the SPI value.
# SPI uniquely identifies a Security Association and changes when SA rekeys.
# Handles hex format (0x12345678) and decimal format.
#
# Arguments:
#   $1: xfrm output text (from 'ip xfrm state' command, may be multi-line)
#
# Returns:
#   0: SPI successfully extracted and printed
#   1: SPI not found or invalid format
#
# Output:
#   Prints the SPI value to stdout if found (hex format preserved, e.g., "0x12345678" or "12345678")
#
# Examples:
#   spi=$(extract_spi "$xfrm_output")
#   if [[ $? -eq 0 ]]; then
#       echo "SPI: $spi"
#   fi
#
# Note:
#   Uses regex pattern matching to extract SPI from "proto <proto> spi <spi>" line
#   SPI format can be hex (0x12345678) or decimal (12345678)
#   Returns SPI in original format (hex or decimal)
extract_spi() {
	local xfrm_output="$1"
	local spi=""

	# Find the line containing "spi" (may be indented)
	# Format examples:
	#   "    proto esp spi 0x12345678 reqid 1 mode tunnel"
	#   "    proto esp spi 12345678 reqid 1 mode tunnel"
	local spi_line
	spi_line=$(echo "$xfrm_output" | grep -i "spi" | head -1)

	if [[ -z "$spi_line" ]]; then
		return 1
	fi

	# Extract SPI value (hex format: 0x[0-9a-fA-F]+ or decimal: [0-9]+)
	# Pattern matches: optional whitespace, "spi", whitespace, then hex or decimal value
	if [[ "$spi_line" =~ ^[[:space:]]*proto[[:space:]]+[a-zA-Z0-9]+[[:space:]]+spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
		spi="${BASH_REMATCH[1]}"
	elif [[ "$spi_line" =~ ^[[:space:]]*spi[[:space:]]+(0x[0-9a-fA-F]+|[0-9]+) ]]; then
		# Fallback: match "spi" directly if proto pattern doesn't match
		spi="${BASH_REMATCH[1]}"
	else
		# Fallback: try sed pattern matching
		spi=$(echo "$spi_line" | sed -n 's/.*[[:space:]]spi[[:space:]]*\(0x[0-9a-fA-F]\+\|[0-9]\+\)[[:space:]].*/\1/p' 2>/dev/null || echo "")
	fi

	# Validate extracted value
	if [[ -z "$spi" ]]; then
		return 1
	fi

	# Validate format: must be hex (0x...) or decimal (all digits)
	if [[ ! "$spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	echo "$spi"
	return 0
}

# Get local UDM IP address from configuration
#
# Retrieves and validates the LOCAL_UDM_IP configuration value.
# This is the internal IP address of the local UDM device used as source IP for ping checks.
#
# Returns:
#   0: LOCAL_UDM_IP is configured and valid
#   1: LOCAL_UDM_IP is not configured or invalid
#
# Output:
#   Prints LOCAL_UDM_IP to stdout if configured and valid, empty string otherwise
#
# Side effects:
#   - Logs warnings if LOCAL_UDM_IP is not configured
#
# Note:
#   Requires LOCAL_UDM_IP to be set in configuration
#   Validates IP address format using validate_ip_address()
get_local_udm_ip() {
	if [[ -z "${LOCAL_UDM_IP:-}" ]]; then
		return 1
	fi

	# Validate IP address format
	if ! validate_ip_address "$LOCAL_UDM_IP"; then
		handle_error "WARNING" "Invalid LOCAL_UDM_IP format: $LOCAL_UDM_IP"
		return 1
	fi

	echo "$LOCAL_UDM_IP"
	return 0
}

# Get local UDM IP for ping source
#
# Retrieves LOCAL_UDM_IP for use as ping source IP.
# Returns empty string if not configured (ping will work without -I flag).
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints LOCAL_UDM_IP to stdout if configured and valid, empty string otherwise
#
# Note:
#   Helper function to avoid code duplication
#   Returns empty string if LOCAL_UDM_IP not configured (graceful degradation)
get_local_ip_for_ping() {
	local local_ip=""
	if local_ip=$(get_local_udm_ip 2>/dev/null); then
		echo "$local_ip"
	else
		echo ""
	fi
	return 0
}

# Check if route (IP address) exists on br0 interface
#
# Checks if a specific IP address is already configured on the br0 interface.
# Used to determine if route needs to be added before pinging.
#
# Arguments:
#   $1: IP address to check (IPv4 format, e.g., "192.168.1.1")
#
# Returns:
#   0: Route exists (IP address is on br0)
#   1: Route does not exist or check failed
#
# Note:
#   Uses 'ip addr show br0' to check for IP address
#   Requires 'ip' command to be available
check_route_exists() {
	local local_ip="$1"

	if [[ -z "$local_ip" ]]; then
		return 1
	fi

	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	# Check if IP address exists on br0 interface
	# Format: "inet 192.168.1.1/32" or "inet 192.168.1.1/24" etc.
	if ip addr show br0 2>/dev/null | grep -q "inet ${local_ip}/"; then
		return 0
	fi

	return 1
}

# Add route (IP address) to br0 interface if needed
#
# Adds the local UDM IP address to the br0 interface using 'ip addr add'.
# This enables ping connectivity between UDM devices at each end of S2S VPN tunnels.
# The route is temporary (not persistent across reboots).
#
# Arguments:
#   $1: IP address to add (IPv4 format, e.g., "192.168.1.1")
#
# Returns:
#   0: Route added successfully or already exists
#   1: Failed to add route
#
# Side effects:
#   - Adds IP address to br0 interface: ip addr add <local_ip>/32 dev br0
#   - Logs actions and results
#
# Note:
#   Idempotent - safe to call multiple times
#   If route already exists, command will fail but function returns success
#   Requires 'ip' command and root privileges
add_route_if_needed() {
	local local_ip="$1"

	if [[ -z "$local_ip" ]]; then
		handle_error "WARNING" "Cannot add route: LOCAL_UDM_IP is not configured"
		return 1
	fi

	if ! command -v ip >/dev/null 2>&1; then
		handle_error "WARNING" "Cannot add route: ip command not available"
		return 1
	fi

	# Check if route already exists
	if check_route_exists "$local_ip"; then
		log_message "INFO" "Route already exists on br0: $local_ip/32"
		return 0
	fi

	# Add route: ip addr add <local_ip>/32 dev br0
	log_message "INFO" "Adding route to br0: $local_ip/32"
	if ip addr add "${local_ip}/32" dev br0 2>/dev/null; then
		log_message "INFO" "Route added successfully: $local_ip/32 on br0"
		return 0
	else
		# Check if error is "File exists" (route already present, race condition)
		if check_route_exists "$local_ip"; then
			log_message "INFO" "Route exists on br0 (added by another process): $local_ip/32"
			return 0
		fi

		# Other error occurred
		handle_error "WARNING" "Failed to add route to br0: $local_ip/32"
		return 1
	fi
}

# Check connectivity via ping
#
# Verifies end-to-end connectivity through the VPN tunnel by pinging a target IP.
# This complements xfrm state checks by confirming actual traffic can flow.
# Automatically manages route (IP address on br0) if needed before pinging.
#
# Arguments:
#   $1: Target IP address to ping (IPv4 or IPv6)
#   $2: Local IP address to use as source (optional, from LOCAL_UDM_IP config)
#
# Returns:
#   0: Ping successful (packet loss < 100%)
#   1: Ping failed (100% packet loss or command error)
#
# Configuration:
#   Uses PING_COUNT and PING_TIMEOUT from config file
#   Automatically detects IPv4 vs IPv6 and uses appropriate ping command
#   Uses LOCAL_UDM_IP as source IP if provided
#
# Note:
#   Tries multiple ping command formats for compatibility (Linux/BSD)
#   Requires log_message, PING_COUNT, PING_TIMEOUT to be set
#   If local_ip is provided, uses ping -I flag and manages route on br0
check_ping_connectivity() {
	local target_ip="$1"
	local local_ip="${2:-}"
	local ping_count="${PING_COUNT:-3}"
	local ping_timeout="${PING_TIMEOUT:-2}"

	# Validate ping target
	if [[ -z "$target_ip" ]]; then
		handle_error "WARNING" "Ping check enabled but target IP not configured"
		return 1
	fi

	# Check if ping command is available
	if ! warn_if_missing "ping"; then
		handle_error "WARNING" "Ping check enabled but ping command not available"
		return 1
	fi

	# If local_ip is provided, manage route on br0 before pinging
	if [[ -n "$local_ip" ]]; then
		# Check if route exists, add if needed
		if ! check_route_exists "$local_ip"; then
			log_message "INFO" "Route not found on br0, attempting to add: $local_ip/32"
			if ! add_route_if_needed "$local_ip"; then
				handle_error "WARNING" "Failed to add route for ping check, continuing anyway"
				# Continue with ping attempt - it may still work or fail naturally
			fi
		fi
	fi

	# Determine ping command based on IP version
	# Some systems have separate ping6, others use ping -6
	local ping_cmd
	local ping_args=()
	if [[ "$target_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		# IPv4
		ping_cmd="ping"
		# Add -I flag if local_ip is provided
		if [[ -n "$local_ip" ]]; then
			ping_args=(-I "$local_ip")
		fi
	else
		# IPv6
		if command -v ping6 >/dev/null 2>&1; then
			ping_cmd="ping6"
			# Add -I flag if local_ip is provided (ping6 uses -I for source interface/IP)
			if [[ -n "$local_ip" ]]; then
				ping_args=(-I "$local_ip")
			fi
		elif ping -6 >/dev/null 2>&1; then
			ping_cmd="ping"
			ping_args=(-6)
			# Add -I flag if local_ip is provided
			if [[ -n "$local_ip" ]]; then
				ping_args=(-6 -I "$local_ip")
			fi
		else
			handle_error "WARNING" "IPv6 ping not available"
			return 1
		fi
	fi

	# Perform ping check
	# Try Linux-style ping first (-W for timeout), fallback to BSD-style (-w)
	# -c: count of packets, -q: quiet (summary only), -W/-w: timeout per packet
	# -I: source IP address (if local_ip provided)
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
		packet_loss=$(echo "$ping_result" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' || echo "$PING_PACKET_LOSS_THRESHOLD")

		if [[ "$packet_loss" -lt $PING_PACKET_LOSS_THRESHOLD ]]; then
			if [[ -n "$local_ip" ]]; then
				log_message "INFO" "Ping check OK: $target_ip from $local_ip (${packet_loss}% packet loss)"
			else
				log_message "INFO" "Ping check OK: $target_ip (${packet_loss}% packet loss)"
			fi
			return 0
		else
			if [[ -n "$local_ip" ]]; then
				handle_error "WARNING" "Ping check failed: $target_ip from $local_ip (${PING_PACKET_LOSS_THRESHOLD}% packet loss)"
			else
				handle_error "WARNING" "Ping check failed: $target_ip (${PING_PACKET_LOSS_THRESHOLD}% packet loss)"
			fi
			return 1
		fi
	else
		# Ping command failed
		# If route was added but ping still failed, this indicates a tunnel issue
		if [[ -n "$local_ip" ]]; then
			handle_error "WARNING" "Ping check failed: $target_ip from $local_ip (ping command error or timeout)"
		else
			handle_error "WARNING" "Ping check failed: $target_ip (ping command error or timeout)"
		fi
		return 1
	fi
}

# Check if SA rekey occurred (read-only check)
#
# Checks if IPsec SA rekey occurred by comparing current SPI with stored SPI.
# This is a read-only check that does not modify state.
# Used for failure type detection without side effects.
#
# Arguments:
#   $1: Current SPI value (from xfrm output, hex or decimal format)
#   $2: Peer IP address (used for state lookup)
#
# Returns:
#   0: Rekey detected (SPI changed)
#   1: No rekey (SPI unchanged or first check)
#
# Side effects:
#   None (read-only check)
#
# Examples:
#   if check_sa_rekey_occurred "$current_spi" "$peer_ip"; then
#       echo "SA rekey occurred"
#   fi
#
# Note:
#   Requires get_peer_state from state.sh
#   This function does NOT reset byte counter baseline or update SPI
#   Use detect_sa_rekey() if you need to handle rekey (reset baseline, update SPI)
check_sa_rekey_occurred() {
	local current_spi="$1"
	local peer_ip="$2"

	# Validate SPI format
	if [[ -z "$current_spi" ]] || [[ ! "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	# Get last known SPI using abstraction layer
	# Use a sentinel value to detect if SPI was actually stored
	# get_peer_state with empty default returns "0" if file doesn't exist
	# So we check if the file exists first, or use a sentinel value
	local last_spi
	local spi_file
	spi_file=$(get_peer_state_file_path "$peer_ip" "spi")
	if [[ ! -f "$spi_file" ]]; then
		# No SPI file exists - no rekey
		return 1
	fi
	last_spi=$(get_peer_state "$peer_ip" "spi" "")

	# If last_spi is empty or "0" and file doesn't exist, no rekey
	# But we already checked file existence above, so if we get here, SPI exists
	if [[ -z "$last_spi" ]] || [[ "$last_spi" == "0" ]]; then
		# SPI file exists but value is empty/0 - treat as no stored SPI
		return 1
	fi

	# Compare SPI values
	if [[ "$current_spi" != "$last_spi" ]]; then
		# SPI changed - rekey occurred
		return 0
	fi

	# SPI unchanged - no rekey
	return 1
}

# Detect SA rekey event
#
# Detects IPsec SA rekey by comparing current SPI with stored SPI.
# When SA rekeys, SPI changes but peer IP remains the same.
# On rekey detection, resets byte counter baseline to prevent false positives.
#
# Arguments:
#   $1: Current SPI value (from xfrm output, hex or decimal format)
#   $2: Peer IP address (used for state management and logging)
#
# Returns:
#   0: Rekey detected (SPI changed)
#   1: No rekey (SPI unchanged or first check)
#
# Side effects:
#   - Updates stored SPI if different from current
#   - Resets byte counter baseline to 0 on rekey detection
#   - Logs rekey events for monitoring
#
# Examples:
#   if detect_sa_rekey "$current_spi" "$peer_ip"; then
#       echo "SA rekey detected"
#   fi
#
# Note:
#   Requires get_peer_state and set_peer_state from state.sh
#   First check (no stored SPI) always returns 1 (no rekey)
#   When SPI changes, resets last_bytes to 0 to allow new baseline
detect_sa_rekey() {
	local current_spi="$1"
	local peer_ip="$2"

	# Validate SPI format
	if [[ -z "$current_spi" ]] || [[ ! "$current_spi" =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]]; then
		return 1
	fi

	# Get last known SPI using abstraction layer
	# Check if SPI file exists first to distinguish between "no file" and "file with value"
	local last_spi
	local spi_file
	spi_file=$(get_peer_state_file_path "$peer_ip" "spi")
	if [[ ! -f "$spi_file" ]]; then
		# No SPI file exists - store current SPI and return (no rekey)
		set_peer_state "$peer_ip" "spi" "$current_spi" || true
		return 1
	fi
	last_spi=$(get_peer_state "$peer_ip" "spi" "")

	# If last_spi is empty or "0", treat as no stored SPI (shouldn't happen if file exists, but be safe)
	if [[ -z "$last_spi" ]] || [[ "$last_spi" == "0" ]]; then
		set_peer_state "$peer_ip" "spi" "$current_spi" || true
		return 1
	fi

	# Compare SPI values
	if [[ "$current_spi" != "$last_spi" ]]; then
		# SPI changed - rekey detected
		log_message "INFO" "SA rekey detected for $peer_ip: SPI changed from $last_spi to $current_spi"

		# Reset byte counter baseline to 0 (allows new baseline after rekey)
		set_peer_state "$peer_ip" "last_bytes" "0" || true

		# Update stored SPI
		set_peer_state "$peer_ip" "spi" "$current_spi" || true

		return 0
	fi

	# SPI unchanged - no rekey
	return 1
}

# Check byte counters for VPN status
#
# Validates that byte counters are increasing or at least non-zero.
# Updates the last_bytes file with current byte count if valid.
# This ensures VPN is actively passing traffic (bytes increasing) or at least has traffic history.
# Detects SA rekey events before checking bytes to prevent false positives.
#
# Arguments:
#   $1: Current byte count (integer from xfrm state)
#   $2: Path to last_bytes file (stores previous byte count for comparison) - DEPRECATED, kept for backward compatibility
#   $3: Peer IP address (used for state management and logging)
#   $4: Current SPI value (optional, used for rekey detection)
#
# Returns:
#   0: Byte counters are valid (increasing or non-zero, first check, or after rekey)
#   1: Byte counters are invalid (zero or not increasing)
#
# Side effects:
#   - Updates last_bytes state using abstraction layer if bytes are valid
#   - Detects SA rekey if SPI provided and resets byte counter baseline
#   - Logs INFO messages for valid counters
#   - Logs warning messages for invalid counters
#
# Examples:
#   if check_byte_counters "$current_bytes" "$last_bytes_file" "$peer_ip" "$current_spi"; then
#       echo "VPN is passing traffic"
#   fi
#
# Note:
#   Requires get_peer_state and set_peer_state from state.sh
#   First check (last_bytes=0) always passes if current_bytes > 0
#   Subsequent checks require current_bytes > last_bytes
#   If rekey detected, byte counter baseline is reset and check passes
#   Uses abstraction layer for state management (file path parameter is deprecated)
check_byte_counters() {
	local current_bytes="$1"
	local last_bytes_file="$2" # Deprecated, kept for backward compatibility
	local peer_ip="$3"
	local current_spi="${4:-}"

	# Check for SA rekey if SPI is provided
	if [[ -n "$current_spi" ]]; then
		if detect_sa_rekey "$current_spi" "$peer_ip"; then
			# Rekey detected - byte counter baseline was reset to 0
			# Treat this as first check (allow any non-zero bytes)
			local last_bytes
			last_bytes=$(get_peer_state "$peer_ip" "last_bytes" "0")
			if [[ "$current_bytes" -gt 0 ]]; then
				# Bytes are non-zero after rekey - update baseline
				if set_peer_state "$peer_ip" "last_bytes" "$current_bytes"; then
					log_message "INFO" "VPN OK: SA rekeyed, bytes=$current_bytes (baseline reset)"
					return 0
				else
					log_message "INFO" "VPN OK: SA rekeyed, bytes=$current_bytes (baseline reset, state update failed)"
					return 0
				fi
			fi
			# If bytes are 0 after rekey, continue to normal check below
		fi
	fi

	# Get last known bytes using abstraction layer
	local last_bytes
	last_bytes=$(get_peer_state "$peer_ip" "last_bytes" "0")

	# Check if bytes are increasing or at least non-zero
	if [[ "$current_bytes" -gt 0 ]]; then
		# Bytes are non-zero, check if they're increasing
		if [[ "$current_bytes" -gt "$last_bytes" ]] || [[ "$last_bytes" -eq 0 ]]; then
			# Bytes are increasing or this is first check
			# Use abstraction layer for atomic write
			if set_peer_state "$peer_ip" "last_bytes" "$current_bytes"; then
				log_message "INFO" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes)"
				return 0
			else
				# State update failed but bytes are valid - log and continue
				log_message "INFO" "VPN OK: SA exists, bytes=$current_bytes (was $last_bytes, state update failed)"
				return 0
			fi
		else
			handle_error "WARNING" "VPN suspect: SA exists but bytes not increasing (current=$current_bytes, last=$last_bytes)"
			return 1
		fi
	else
		handle_error "WARNING" "VPN suspect: SA exists but bytes=0"
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
	# Use fixed-string matching to prevent regex pattern injection and avoid partial IP matches
	# -A XFRM_OUTPUT_CONTEXT_LINES: show context lines after match (to get byte counter info)
	# -F: fixed-string matching (treats IP address as literal, not regex pattern)
	xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "$peer_ip" -A "$XFRM_OUTPUT_CONTEXT_LINES" || true)

	if [[ -z "$xfrm_output" ]]; then
		handle_error "WARNING" "VPN suspect: No SA found for $peer_ip in xfrm state"
		return 1
	fi

	# Extract SPI for rekey detection
	local current_spi=""
	current_spi=$(extract_spi "$xfrm_output" 2>/dev/null || echo "")

	# Check if we have byte counters
	local current_bytes
	if current_bytes=$(extract_byte_counter "$xfrm_output"); then
		# Successfully extracted byte counter - validate it
		# Pass SPI to check_byte_counters for rekey detection
		if check_byte_counters "$current_bytes" "$last_bytes_file" "$peer_ip" "$current_spi"; then
			# Update stored SPI if we have it (even if rekey not detected)
			if [[ -n "$current_spi" ]]; then
				set_peer_state "$peer_ip" "spi" "$current_spi" || true
			fi
			return 0
		else
			# SA exists but byte counters are suspect
			return 1
		fi
	else
		# SA exists but no byte counter info (or extraction failed)
		# Still update SPI if available for tracking
		if [[ -n "$current_spi" ]]; then
			set_peer_state "$peer_ip" "spi" "$current_spi" || true
		fi
		log_message "INFO" "VPN OK: SA exists for $peer_ip (no byte counter info)"
		return 0
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
	# Use fixed-string matching (-F) for consistency and safety (IP addresses don't need case-insensitive matching)
	ipsec_output=$(ipsec status 2>/dev/null | grep -F "$peer_ip" || true)

	if [[ -n "$ipsec_output" ]]; then
		log_message "INFO" "VPN OK: Connection found via ipsec status for $peer_ip"
		return 0
	else
		handle_error "WARNING" "VPN suspect: No connection found via ipsec status for $peer_ip"
		return 1
	fi
}

# Discover connection name from ipsec status
#
# Attempts to discover the IPsec connection name associated with a peer IP
# by parsing ipsec status output. Connection names are cached to avoid
# repeated parsing. This is for logging/debugging purposes only - recovery
# actions use ipsec reload which affects all connections.
#
# Arguments:
#   $1: Peer IP address (external/public IP)
#
# Returns:
#   0: Always succeeds (function never fails, returns empty string if not found)
#
# Output:
#   Prints connection name to stdout if found, empty string otherwise
#
# Side effects:
#   - Caches connection name in ${STATE_DIR}/connection_name_<sanitized_peer_ip>
#   - Logs debug messages if DEBUG=1
#
# Examples:
#   conn_name=$(discover_connection_name "192.168.1.1")
#   # Returns: "site-a" or empty string
#
# Note:
#   Requires sanitize_peer_ip, STATE_DIR, and log_message to be set
#   ipsec command is optional - cached values can be retrieved even if ipsec is unavailable
#   Connection names are for logging only - recovery uses ipsec reload (all connections)
discover_connection_name() {
	local peer_ip="$1"
	local connection_name=""

	# Sanitize peer IP for cache filename
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local cache_file="${STATE_DIR}/connection_name_${peer_sanitized}"

	# Check cache first - use cached value if available, even if ipsec is not available
	if [[ -f "$cache_file" ]]; then
		connection_name=$(cat "$cache_file" 2>/dev/null || echo "")
		if [[ -n "$connection_name" ]]; then
			[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "Using cached connection name '$connection_name' for $peer_ip"
			echo "$connection_name"
			return 0
		fi
	fi

	# Check if ipsec command is available (only needed if cache miss)
	if ! command -v ipsec >/dev/null 2>&1; then
		echo ""
		return 0
	fi

	# Get ipsec status output
	local ipsec_output
	ipsec_output=$(ipsec status 2>/dev/null || true)

	if [[ -z "$ipsec_output" ]]; then
		echo ""
		return 0
	fi

	# Parse ipsec status output to find connection name
	# Common formats:
	# - libreswan: "conn-name: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
	# - strongswan: "conn-name: IKEv1, ESTABLISHED, 192.168.1.1"
	# Look for lines containing the peer IP and extract connection name (text before colon)
	local IFS=$'\n'
	for line in $ipsec_output; do
		# Check if line contains peer IP
		if echo "$line" | grep -qF "$peer_ip"; then
			# Extract connection name (everything before first colon, trimmed)
			connection_name=$(echo "$line" | sed -n 's/^[[:space:]]*\([^:]*\):.*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
			if [[ -n "$connection_name" ]]; then
				# Cache the result
				echo "$connection_name" >"$cache_file" 2>/dev/null || true
				[[ "${DEBUG:-0}" -eq 1 ]] && log_message "DEBUG" "Discovered connection name '$connection_name' for $peer_ip"
				echo "$connection_name"
				return 0
			fi
		fi
	done

	# Not found - return empty string
	echo ""
	return 0
}

# Check ping connectivity if enabled
#
# Performs ping check if enabled, regardless of VPN status.
# Used to verify end-to-end connectivity or diagnose issues.
#
# Arguments:
#   $1: VPN status (1 = OK, 0 = failed)
#   $2: Ping target IP address (internal IP if provided, otherwise external IP)
#
# Returns:
#   0: Always succeeds (ping check is informational)
#
# Side effects:
#   - Logs warning/debug messages about ping results
#
# Note:
#   Uses PING_TARGET_IP if configured (for backward compatibility), otherwise uses the provided IP
#   The provided IP should be the internal IP if available, falling back to external IP
check_ping_if_enabled() {
	local vpn_ok="$1"
	local ping_ip="$2"

	if [[ "${ENABLE_PING_CHECK:-0}" -ne 1 ]]; then
		return 0
	fi

	# Determine ping target: use PING_TARGET_IP if configured (backward compatibility), otherwise use provided IP
	local ping_target="${PING_TARGET_IP:-$ping_ip}"

	# Get local UDM IP for ping source (if configured)
	local local_ip
	local_ip=$(get_local_ip_for_ping)

	if [[ $vpn_ok -eq 1 ]]; then
		# SA exists, verify connectivity with ping check
		if ! check_ping_connectivity "$ping_target" "$local_ip"; then
			# SA exists but ping failed - tunnel may be broken
			handle_error "WARNING" "VPN SA exists but ping check failed for $ping_target - tunnel may not be routing traffic"
			# Don't fail completely - SA exists, but mark as suspect
			# This allows xfrm to pass but warns about connectivity
			# If ping keeps failing, byte counters should also stop increasing
		else
			log_message "INFO" "VPN connectivity verified: ping check passed for $ping_target"
		fi
	else
		# SA doesn't exist, but try ping anyway to see if there's any connectivity
		if check_ping_connectivity "$ping_target" "$local_ip"; then
			handle_error "WARNING" "Ping check passed but no SA found - tunnel may be down but connectivity exists via other route"
		fi
		# Note: If ping fails when SA doesn't exist, check_ping_connectivity already logs the failure
	fi

	return 0
}

# Check for IPsec Phase 2 Security Association
#
# Checks if IPsec Phase 2 SA (ESP/AH SA) exists for a peer using xfrm.
# IPsec Phase 2 establishes the actual encrypted tunnel for data transfer.
# If Phase 2 is down but Phase 1 is up, the tunnel is partially established but cannot pass traffic.
#
# Arguments:
#   $1: Peer IP address to check
#
# Returns:
#   0: IPsec Phase 2 SA found
#   1: IPsec Phase 2 SA not found or xfrm unavailable
#
# Side effects:
#   - Logs debug messages about IPsec SA status
#
# Note:
#   Uses ip xfrm state which shows IPsec SAs (Phase 2).
#   xfrm shows ESP/AH SAs that are used for actual data encryption.
#   Requires ip command to be available
check_ipsec_phase2() {
	local peer_ip="$1"

	if ! command -v ip >/dev/null 2>&1; then
		return 1
	fi

	local xfrm_output
	# Use fixed-string matching to prevent regex pattern injection and avoid partial IP matches
	# -F: fixed-string matching (treats IP address as literal, not regex pattern)
	xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "$peer_ip" || true)

	if [[ -n "$xfrm_output" ]]; then
		return 0
	fi

	return 1
}

# Detect VPN failure type
#
# Determines the specific type of VPN failure by checking IPsec Phase 2 SAs and traffic flow.
# Categorizes failures into main types:
#   - "tunnel_down": IPsec Phase 2 SA doesn't exist (tunnel not established)
#   - "routing_issue": Phase 2 SA exists but traffic isn't flowing (byte counters/ping issues)
#   - "rekey": SA rekey detected (SPI changed, not a failure but logged for monitoring)
#   - "unknown": Unable to determine failure type (fallback)
#
# Note:
#   If Phase 2 SA doesn't exist, the tunnel is down (could be Phase 1 or Phase 2 issue, but we can't distinguish).
#   SA rekey is detected by SPI changes and is not treated as a failure.
#
# Arguments:
#   $1: External peer IP address (used for SA checks)
#   $2: Internal peer IP address (optional, used for ping checks)
#   $3: Last bytes file path (optional, used to check if bytes are increasing)
#
# Returns:
#   0: Failure type detected and printed to stdout
#   1: Unable to determine failure type
#
# Output:
#   Prints failure type to stdout: "tunnel_down", "routing_issue", "rekey", or "unknown"
#
# Side effects:
#   - Logs debug messages about failure type detection
#
# Examples:
#   failure_type=$(detect_failure_type "203.0.113.1" "192.168.1.1" "$last_bytes_file")
#   case "$failure_type" in
#       "tunnel_down") echo "VPN tunnel is down" ;;
#       "routing_issue") echo "Routing issue detected" ;;
#       "rekey") echo "SA rekey detected" ;;
#   esac
#
# Note:
#   Requires check_ipsec_phase2, check_byte_counters, check_ping_connectivity, detect_sa_rekey
#   External IP is used for SA checks, internal IP is used for ping checks
detect_failure_type() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local last_bytes_file="${3:-}"

	# Check IPsec Phase 2 (ESP/AH SA)
	# Phase 2 SA existence indicates tunnel is established (Phase 1 must be up for Phase 2 to exist)
	local ipsec_phase2_up=0
	if check_ipsec_phase2 "$external_peer_ip"; then
		ipsec_phase2_up=1
	fi

	# Determine failure type based on SA state
	if [[ $ipsec_phase2_up -eq 0 ]]; then
		# No Phase 2 SA found - tunnel is down
		echo "tunnel_down"
		return 0
	elif [[ $ipsec_phase2_up -eq 1 ]]; then
		# Phase 2 SA exists - tunnel is established, check for rekey first
		# Check for SA rekey by comparing SPI
		if [[ -n "$external_peer_ip" ]]; then
			local xfrm_output
			# Use fixed-string matching to prevent regex pattern injection
			# -F: fixed-string matching (treats IP address as literal, not regex pattern)
			# -A XFRM_OUTPUT_CONTEXT_LINES: show context lines after match (to get SPI info)
			xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "$external_peer_ip" -A "$XFRM_OUTPUT_CONTEXT_LINES" || true)
			if [[ -n "$xfrm_output" ]]; then
				local current_spi=""
				current_spi=$(extract_spi "$xfrm_output" 2>/dev/null || echo "")

				# Check for rekey if SPI is available (read-only check)
				if [[ -n "$current_spi" ]]; then
					if check_sa_rekey_occurred "$current_spi" "$external_peer_ip" 2>/dev/null; then
						# Rekey detected - not a failure, but log for monitoring
						# Note: We use read-only check here since detect_failure_type is called
						# after VPN check failed. The actual rekey handling (baseline reset)
						# should have happened in check_byte_counters during the check.
						echo "rekey"
						return 0
					fi
				fi
			fi
		fi

		# Phase 2 SA exists and no rekey detected - check for routing issues
		# Check byte counters if available
		local has_routing_issue=0

		# Check byte counters using abstraction layer (peer IP is available)
		if [[ -n "$external_peer_ip" ]]; then
			local xfrm_output
			# Use fixed-string matching to prevent regex pattern injection
			# -F: fixed-string matching (treats IP address as literal, not regex pattern)
			# -A XFRM_OUTPUT_CONTEXT_LINES: show context lines after match (to get byte counter info)
			xfrm_output=$(ip xfrm state 2>/dev/null | grep -F "$external_peer_ip" -A "$XFRM_OUTPUT_CONTEXT_LINES" || true)
			if [[ -n "$xfrm_output" ]]; then
				local current_bytes=""
				current_bytes=$(extract_byte_counter "$xfrm_output" 2>/dev/null || echo "")

				if [[ -n "$current_bytes" ]] && [[ "$current_bytes" =~ ^[0-9]+$ ]]; then
					# Successfully extracted byte counter - check if bytes are not increasing
					# Use abstraction layer to get last bytes
					local last_bytes
					last_bytes=$(get_peer_state "$external_peer_ip" "last_bytes" "0")

					# If bytes exist but aren't increasing (and it's not the first check), it's a routing issue
					if [[ "$current_bytes" -gt 0 ]] && [[ "$current_bytes" -le "$last_bytes" ]] && [[ "$last_bytes" -gt 0 ]]; then
						has_routing_issue=1
					elif [[ "$current_bytes" -eq 0 ]] && [[ "$last_bytes" -gt 0 ]]; then
						# Bytes dropped to zero after previously having traffic - routing issue
						has_routing_issue=1
					fi
				fi
			fi
		fi

		# Check ping if enabled and internal IP provided
		# Only check ping if we haven't already detected a routing issue from byte counters
		if [[ $has_routing_issue -eq 0 ]] && [[ -n "$internal_peer_ip" ]] && [[ "${ENABLE_PING_CHECK:-0}" -eq 1 ]]; then
			# Get local UDM IP for ping source (if configured)
			local local_ip
			local_ip=$(get_local_ip_for_ping)
			if ! check_ping_connectivity "$internal_peer_ip" "$local_ip" 2>/dev/null; then
				has_routing_issue=1
			fi
		fi

		if [[ $has_routing_issue -eq 1 ]]; then
			echo "routing_issue"
			return 0
		fi
		# Phase 2 SA exists but no routing issue detected
		# This can happen when:
		#   - Byte counters are not available (last_bytes_file not provided or extraction failed)
		#   - Ping check is disabled or internal IP not provided
		#   - VPN check failed for another reason (e.g., byte counter validation in check_xfrm_status)
		# In this case, we return "unknown" since we can't definitively determine the failure type
		# without additional diagnostic information
	fi

	# Unable to determine failure type (fallback)
	# This occurs when:
	#   - Phase 2 SA doesn't exist (handled above as "tunnel_down")
	#   - Phase 2 SA exists but we can't determine if it's a routing issue (see comment above)
	#   - Detection methods are unavailable or failed
	echo "unknown"
	return 1
}

# Get last detected failure type for a peer
#
# Retrieves the last detected failure type from the state file.
# This allows recovery actions to use failure-specific recovery strategies.
#
# Arguments:
#   $1: Peer IP address
#
# Returns:
#   0: Failure type found and printed to stdout
#   1: No failure type stored (or file doesn't exist)
#
# Output:
#   Prints failure type to stdout: "tunnel_down", "routing_issue", "rekey", or "unknown"
#
# Examples:
#   failure_type=$(get_failure_type "203.0.113.1")
#   if [[ "$failure_type" == "tunnel_down" ]]; then
#       echo "VPN tunnel is down"
#   fi
#
# Note:
#   Requires sanitize_peer_ip and STATE_DIR to be set
#   Failure type is stored in: ${STATE_DIR}/failure_type_<sanitized_peer_ip>
#   Note: "rekey" is not a failure type but is stored for monitoring purposes
get_failure_type() {
	local peer_ip="$1"
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$peer_ip")
	local failure_type_file="${STATE_DIR}/failure_type_${peer_sanitized}"

	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file" 2>/dev/null | head -1 | tr -d '\n\r ' || echo "unknown")
		if [[ -n "$failure_type" ]]; then
			echo "$failure_type"
			return 0
		fi
	fi

	echo "unknown"
	return 1
}

# Check VPN status using ip xfrm state
#
# Verifies VPN tunnel health by checking IPsec Security Association (SA) state and byte counters.
# Uses multiple methods in order: ip xfrm state (primary), ipsec status (fallback).
# If ping checks are enabled, also verifies end-to-end connectivity.
#
# Arguments:
#   $1: External peer IP address (external/public IP of remote VPN gateway, used for xfrm state checks)
#   $2: Internal peer IP address (optional, used for ping checks, falls back to external if not provided)
#
# Returns:
#   0: VPN is healthy (SA exists, bytes increasing or non-zero)
#   1: VPN check failed (no SA found or bytes not increasing)
#
# Detection logic:
#   1. Checks ip xfrm state for SA matching external peer IP
#   2. Validates byte counters are > 0 and increasing (if available)
#   3. Falls back to ipsec status if xfrm doesn't confirm
#   4. Optionally performs ping check if ENABLE_PING_CHECK=1 (uses internal IP if provided)
#
# Side effects:
#   - Creates/updates per-peer last_bytes file if byte counters found
#   - Logs debug/warning messages about VPN state
#
# Note:
#   Requires validate_ip_address, sanitize_peer_ip, log_message, STATE_DIR, ENABLE_PING_CHECK,
#   PING_TARGET_IP to be set
#   External IP is used for xfrm checks, internal IP is used for ping checks
check_vpn_status() {
	local external_peer_ip="$1"
	local internal_peer_ip="${2:-}"
	local vpn_ok=0

	# Validate external peer IP format using proper validation function
	if ! validate_ip_address "$external_peer_ip"; then
		handle_error "ERROR" "Invalid external peer IP format: $external_peer_ip" 0
		return 1
	fi

	# Per-peer bytes file (use external IP for state tracking)
	local peer_sanitized
	peer_sanitized=$(sanitize_peer_ip "$external_peer_ip")
	local last_bytes_file="${STATE_DIR}/last_bytes_${peer_sanitized}"

	# Try detection methods in order of reliability (use external IP for xfrm)
	if check_xfrm_status "$external_peer_ip" "$last_bytes_file"; then
		vpn_ok=1
	elif check_ipsec_status "$external_peer_ip"; then
		vpn_ok=1
	fi

	# Perform ping check if enabled (informational, doesn't affect vpn_ok)
	# Use internal IP if provided, otherwise fall back to external IP
	local ping_ip="${internal_peer_ip:-$external_peer_ip}"
	check_ping_if_enabled "$vpn_ok" "$ping_ip"

	# If VPN check failed, detect and log the failure type
	# Also check for rekey events (which are not failures but should be logged)
	if [[ $vpn_ok -eq 0 ]]; then
		local failure_type
		failure_type=$(detect_failure_type "$external_peer_ip" "$internal_peer_ip" "$last_bytes_file" 2>/dev/null || echo "unknown")

		# Store failure type in state file for recovery actions
		local failure_type_file="${STATE_DIR}/failure_type_${peer_sanitized}"
		atomic_write_file "$failure_type_file" "$failure_type" 2>/dev/null || true

		case "$failure_type" in
		"rekey")
			# Rekey detected - not a failure, but log for monitoring
			# Rekey is already logged in detect_sa_rekey, but we mark VPN as OK
			log_message "INFO" "SA rekey detected for $external_peer_ip (not a failure)"
			vpn_ok=1
			;;
		"tunnel_down")
			handle_error "WARNING" "VPN failure type: Tunnel down (no Phase 2 SA found) for $external_peer_ip"
			;;
		"routing_issue")
			handle_error "WARNING" "VPN failure type: Routing issue (tunnel established but traffic not flowing) for $external_peer_ip"
			;;
		*)
			handle_error "WARNING" "VPN failure type: Unknown (unable to determine specific failure type) for $external_peer_ip"
			;;
		esac
	fi

	# Return 0 if OK, 1 if failed (invert vpn_ok: 1 becomes 0, 0 becomes 1)
	return $((1 - vpn_ok))
}
