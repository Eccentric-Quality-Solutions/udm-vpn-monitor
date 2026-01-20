#!/bin/bash
#
# Network validation functions for UDM VPN Monitor
# Handles IP validation (IPv4/IPv6) and route checks
#
# Version: 0.6.0
#

# Source constants for magic numbers
# shellcheck source=lib/constants.sh
if [[ -z "${LIB_DIR:-}" ]]; then
	LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if ! source "${LIB_DIR}/constants.sh" 2>/dev/null; then
	[[ -z "${MAX_IPV6_SEGMENTS:-}" ]] && readonly MAX_IPV6_SEGMENTS=8
	[[ -z "${MIN_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MIN_IPV6_SEGMENT_HEX_DIGITS=1
	[[ -z "${MAX_IPV6_SEGMENT_HEX_DIGITS:-}" ]] && readonly MAX_IPV6_SEGMENT_HEX_DIGITS=4
	[[ -z "${MAX_IPV4_OCTET:-}" ]] && readonly MAX_IPV4_OCTET=255
	[[ -z "${IPV4_OCTET_COUNT:-}" ]] && readonly IPV4_OCTET_COUNT=4
	[[ -z "${IPV4_CIDR_SINGLE_HOST:-}" ]] && readonly IPV4_CIDR_SINGLE_HOST=32
	[[ -z "${PING_PACKET_LOSS_THRESHOLD:-}" ]] && readonly PING_PACKET_LOSS_THRESHOLD=100
	[[ -z "${PING_SUCCESS_THRESHOLD:-}" ]] && readonly PING_SUCCESS_THRESHOLD=0.3
	[[ -z "${PING_CEIL_ADJUSTMENT:-}" ]] && readonly PING_CEIL_ADJUSTMENT=0.999
	[[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && readonly XFRM_OUTPUT_CONTEXT_LINES=10
	[[ -z "${IPSEC_STATUS_TIMEOUT:-}" ]] && readonly IPSEC_STATUS_TIMEOUT=5
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# shellcheck source=lib/logging.sh
source "${LIB_DIR}/logging.sh"

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

# Count IPv6 segments in a colon-separated string
#
# Counts the number of non-empty segments in an IPv6 address portion
# (before or after compression). Handles empty strings and removes
# empty elements that result from leading/trailing colons.
#
# Arguments:
#   $1: Colon-separated string to count segments in
#
# Returns:
#   0: Always succeeds
#
# Outputs:
#   Number of segments (non-empty elements) to stdout
#
# Examples:
#   count_ipv6_segments "2001:db8"     # Outputs: 2
#   count_ipv6_segments "2001:"         # Outputs: 1
#   count_ipv6_segments ""              # Outputs: 0
count_ipv6_segments() {
	local segments_str="$1"
	local count=0

	if [[ -n "$segments_str" ]]; then
		# Count segments by splitting on ':' and counting non-empty elements
		local IFS=':'
		local -a temp_segs
		read -ra temp_segs <<<"$segments_str"
		count=${#temp_segs[@]}
		# Remove empty elements (from leading/trailing colons)
		for seg in "${temp_segs[@]}"; do
			[[ -z "$seg" ]] && ((count--))
		done
	fi

	echo "$count"
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
	local segments_before
	segments_before=$(count_ipv6_segments "$before_compression")

	# Count segments after compression
	local segments_after
	segments_after=$(count_ipv6_segments "$after_compression")

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

# Get local UDM IP address from configuration
#
# Retrieves and validates the LOCAL_UDM_IP configuration value.
# This is the internal IP address of the local UDM device used as source IP for ping checks.
#
# Arguments:
#   None
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
		handle_error "WARNING" "SYSTEM" "Invalid LOCAL_UDM_IP format: $LOCAL_UDM_IP"
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
# Arguments:
#   None
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

	# Validate IP address format for defense in depth
	# Even though callers should validate, this ensures we never use invalid IPs in commands
	if ! validate_ip_address "$local_ip"; then
		return 1
	fi

	if ! check_command_or_warn "ip" "Route check"; then
		return 1
	fi

	# Check if IP address exists on br0 interface
	# Format: "inet 192.168.1.1/${IPV4_CIDR_SINGLE_HOST}" or "inet 192.168.1.1/24" etc.
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
#   - Adds IP address to br0 interface: ip addr add <local_ip>/${IPV4_CIDR_SINGLE_HOST} dev br0
#   - Logs actions and results
#
# Note:
#   Idempotent - safe to call multiple times
#   If route already exists, command will fail but function returns success
#   Requires 'ip' command and root privileges
add_route_if_needed() {
	local local_ip="$1"

	if [[ -z "$local_ip" ]]; then
		handle_error "WARNING" "SYSTEM" "Cannot add route: LOCAL_UDM_IP is not configured"
		return 1
	fi

	if ! check_command_or_warn "ip" "Cannot add route"; then
		return 1
	fi

	# Check if route already exists
	if check_route_exists "$local_ip"; then
		log_message "INFO" "SYSTEM" "Route already exists on br0: $local_ip/${IPV4_CIDR_SINGLE_HOST}"
		return 0
	fi

	# Add route: ip addr add <local_ip>/${IPV4_CIDR_SINGLE_HOST} dev br0
	log_message "INFO" "SYSTEM" "Adding route to br0: $local_ip/${IPV4_CIDR_SINGLE_HOST}"
	if ip addr add "${local_ip}/${IPV4_CIDR_SINGLE_HOST}" dev br0 2>/dev/null; then
		log_message "INFO" "SYSTEM" "Route added successfully: $local_ip/${IPV4_CIDR_SINGLE_HOST} on br0"
		return 0
	else
		# Check if error is "File exists" (route already present, race condition)
		if check_route_exists "$local_ip"; then
			log_message "INFO" "SYSTEM" "Route exists on br0 (added by another process): $local_ip/${IPV4_CIDR_SINGLE_HOST}"
			return 0
		fi

		# Other error occurred
		handle_error "WARNING" "SYSTEM" "Failed to add route to br0: $local_ip/${IPV4_CIDR_SINGLE_HOST}"
		return 1
	fi
}

# Get route information for a destination IP
#
# Determines which interface and gateway (if any) is used to reach a destination IP.
# This helps identify alternative routes when VPN tunnel is down but connectivity exists.
#
# Arguments:
#   $1: Destination IP address (IPv4 format)
#   $2: Source IP address (optional, for source-specific routing)
#
# Returns:
#   0: Route information retrieved successfully
#   1: Failed to retrieve route information
#
# Output:
#   Prints route information in format: "via <gateway> dev <interface>" or "dev <interface>"
#   Prints empty string if route check fails
#
# Note:
#   Uses 'ip route get' command
#   Requires 'ip' command to be available
get_route_info() {
	local dest_ip="$1"
	local src_ip="${2:-}"

	if [[ -z "$dest_ip" ]]; then
		return 1
	fi

	# Validate IP address format
	if ! validate_ip_address "$dest_ip"; then
		return 1
	fi

	# Check if ip command is available (don't warn - this is optional diagnostic info)
	if ! check_command_available "ip"; then
		return 1
	fi

	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	local ip_cmd
	ip_cmd=$(get_command_path "ip")

	# Get route information
	# Format: "172.31.13.239 via 192.168.1.1 dev eth0 src 192.168.1.100"
	# We want to extract: "via <gateway> dev <interface>" or "dev <interface>"
	local route_output
	if [[ -n "$src_ip" ]] && validate_ip_address "$src_ip"; then
		# Use source-specific routing
		if ! route_output=$("$ip_cmd" route get "$dest_ip" from "$src_ip" 2>/dev/null); then
			return 1
		fi
	else
		# Standard routing
		if ! route_output=$("$ip_cmd" route get "$dest_ip" 2>/dev/null); then
			return 1
		fi
	fi

	if [[ -n "$route_output" ]]; then
		# Extract gateway and interface
		local gateway
		local interface
		gateway=$(echo "$route_output" | grep -oE 'via [0-9.]+' | sed 's/via //' || echo "")
		interface=$(echo "$route_output" | grep -oE 'dev [a-zA-Z0-9_-]+' | sed 's/dev //' || echo "")

		# Build route info string
		local route_info=""
		if [[ -n "$gateway" ]] && [[ -n "$interface" ]]; then
			route_info="via $gateway dev $interface"
		elif [[ -n "$interface" ]]; then
			route_info="dev $interface"
		fi

		if [[ -n "$route_info" ]]; then
			echo "$route_info"
			return 0
		fi
	fi

	return 1
}

# Build route message for alternative route warning
#
# Helper function to get route information and format it for warning messages.
# Used when VPN tunnel is down but ping succeeds, indicating alternative route exists.
#
# Arguments:
#   $1: Destination IP address (IPv4 format)
#   $2: Source IP address (optional, for source-specific routing)
#
# Returns:
#   0: Always succeeds (gracefully handles failures)
#
# Output:
#   Prints formatted route message: " (route: via <gateway> dev <interface>)" or " (route: dev <interface>)" or empty string
#
# Note:
#   Returns empty string if route info cannot be determined (non-fatal)
build_route_message() {
	local dest_ip="$1"
	local src_ip="${2:-}"
	local route_info
	local route_msg=""

	if route_info=$(get_route_info "$dest_ip" "$src_ip" 2>/dev/null); then
		route_msg=" (route: $route_info)"
	fi

	echo "$route_msg"
	return 0
}

# Check if default route exists
#
# Verifies that a default route exists in the routing table.
# A missing default route indicates network partition (no internet connectivity).
#
# Arguments:
#   None
#
# Returns:
#   0: Default route exists
#   1: Default route not found or check failed
#
# Note:
#   Uses 'ip route show default' to check for default route
#   Requires 'ip' command to be available
check_default_route() {
	if ! check_command_or_warn "ip" "Checking default route"; then
		return 1
	fi

	# Get full path to ip command for reliable execution in PATH-restricted environments (cron/systemd)
	local ip_cmd
	ip_cmd=$(get_command_path "ip")

	# Check if default route exists
	# ip route show default returns 0 if route exists, 1 if not found
	if "$ip_cmd" route show default >/dev/null 2>&1; then
		return 0
	fi

	return 1
}

# Check DNS resolution
#
# Verifies DNS resolution by querying a public DNS server.
# DNS failure indicates network partition (no internet connectivity).
#
# Arguments:
#   $1: DNS server to query (optional, defaults to 8.8.8.8)
#   $2: Hostname to resolve (optional, defaults to google.com)
#   $3: Timeout in seconds (optional, defaults to 2)
#
# Returns:
#   0: DNS resolution successful
#   1: DNS resolution failed or check unavailable
#
# Note:
#   Uses 'dig' command if available, falls back to 'nslookup'
#   Requires 'dig' or 'nslookup' command to be available
check_dns_resolution() {
	local dns_server="${1:-8.8.8.8}"
	local hostname="${2:-google.com}"
	local timeout="${3:-2}"

	# Try dig first (more reliable)
	if check_command_available "dig"; then
		# Use timeout to limit wait time
		# +timeout=N sets timeout in seconds, +tries=1 limits retries
		if timeout "$timeout" dig "@${dns_server}" "$hostname" +timeout="$timeout" +tries=1 +short >/dev/null 2>&1; then
			return 0
		fi
	fi

	# Fallback to nslookup
	if check_command_available "nslookup"; then
		if timeout "$timeout" nslookup "$hostname" "$dns_server" >/dev/null 2>&1; then
			return 0
		fi
	fi

	return 1
}

# Check critical network interfaces are up
#
# Verifies that critical network interfaces (br0, eth0) are in UP state.
# Down interfaces indicate network partition.
#
# Arguments:
#   $1: Comma-separated list of interfaces to check (optional, defaults to "br0,eth0")
#
# Returns:
#   0: All critical interfaces are UP
#   1: One or more critical interfaces are DOWN or check failed
#
# Note:
#   Uses 'ip link show' to check interface state
#   Requires 'ip' command to be available
check_interface_state() {
	local interfaces="${1:-br0,eth0}"
	local IFS=','
	local -a interface_array
	read -ra interface_array <<<"$interfaces"

	if ! check_command_or_warn "ip" "Checking interfaces"; then
		return 1
	fi

	# Check each interface
	for interface in "${interface_array[@]}"; do
		# Trim whitespace
		interface=$(trim "$interface")
		if [[ -z "$interface" ]]; then
			continue
		fi

		# Check if interface exists and is UP
		# ip link show <interface> returns 0 if interface exists
		# grep "state UP" checks if interface is UP
		if ! ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
			return 1
		fi
	done

	return 0
}
